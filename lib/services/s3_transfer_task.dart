import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:s3_drive/components.dart';
import 'package:s3_drive/services/s3_file_manager.dart';
import 'hash_util.dart';

typedef ProgressCallback = void Function(int bytesTransferred, int totalBytes);
typedef StatusCallback = void Function(String status);

enum TransferTask { upload, download }

class S3TransferTask {
  final String key;
  final File localFile;
  final Digest md5;
  final S3FileManager fileManager;
  final TransferTask task;
  final ProgressCallback? onProgress;
  final StatusCallback? onStatus;

  bool _sinkClosed = false;
  bool _isCancelled = false;
  StreamSubscription<List<int>>? sub;

  late final http.Client _client;

  static DateTime lastcallbackTime = DateTime.fromMicrosecondsSinceEpoch(0);

  S3TransferTask({
    required this.key,
    required this.localFile,
    required this.md5,
    required this.fileManager,
    required this.task,
    this.onProgress,
    this.onStatus,
  }) {
    _client = http.Client();
  }

  Future<dynamic> closeSink(http.StreamedRequest request) async {
    if (!_sinkClosed) {
      _sinkClosed = true;
      return await request.sink.close();
    }
  }

  /// Starts the upload or download operation.
  Future<dynamic> start() async {
    dynamic response;
    try {
      onStatus?.call(
        task == TransferTask.upload
            ? 'Starting upload...'
            : task == TransferTask.download
            ? 'Starting download...'
            : 'Generating pre-signed URL...',
      );
      if (task == TransferTask.upload) {
        response = await _upload();
      } else if (task == TransferTask.download) {
        response = await _download();
      }
    } catch (e) {
      if (_isCancelled) {
        onStatus?.call('Cancelled');
      } else {
        _client.close();
        onStatus?.call('Error: $e');
      }
      rethrow;
    } finally {
      _client.close();
    }

    return response;
  }

  /// Cancels the ongoing transfer.
  void cancel() {
    _isCancelled = true;
    sub?.cancel();
  }

  Future<dynamic> _upload() async {
    _sinkClosed = false;
    int uploaded = 0;
    final totalBytes = await localFile.length();

    final contentHash = await _sha256OfFile(localFile);
    final contentMD5 = base64.encode(md5.bytes);
    final now = DateTime.now().toUtc();
    final amzDate = fileManager.formatAmzDate(now);
    final shortDate = fileManager.formatDate(now);

    // Prepare signed headers
    final headers = fileManager.buildSignedHeaders(
      key: key,
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
      contentMD5: contentMD5,
      contentType: fileManager.guessMime(localFile),
    );
    headers['Expect'] = '100-continue';

    // Streamed request
    final request = http.StreamedRequest('PUT', fileManager.getUri(key))
      ..headers.addAll(headers)
      ..contentLength = totalBytes;

    final completer = Completer<void>();
    final stream = localFile.openRead();

    sub = stream.listen(
      (chunk) {
        if (_isCancelled) {
          closeSink(request);
          sub?.cancel();
          return;
        }
        request.sink.add(chunk);
        uploaded += chunk.length;
        if (DateTime.now().difference(lastcallbackTime).inMilliseconds < 100 &&
            uploaded < totalBytes) {
          return;
        }
        lastcallbackTime = DateTime.now();
        onProgress?.call(uploaded, totalBytes);
        onStatus?.call(
          'Uploading... ${bytesToReadable(uploaded)} / ${bytesToReadable(totalBytes)}',
        );
      },
      onDone: () async {
        await closeSink(request);
        completer.complete();
      },
      onError: (e) async {
        await closeSink(request);
        completer.completeError(e);
      },
      cancelOnError: true,
    );

    final responseFuture = _client.send(request);
    await completer.future;
    final response = await responseFuture;

    if (response.statusCode == 200) {
      onStatus?.call('Upload complete');
    } else {
      final body = await response.stream.bytesToString();
      throw Exception('Upload failed: ${response.statusCode} - $body');
    }

    return response.headers;
  }

  Future<dynamic> _download() async {
    final now = DateTime.now().toUtc();
    final amzDate = fileManager.formatAmzDate(now);
    final shortDate = fileManager.formatDate(now);
    final contentHash = S3FileManager.emptySha256;

    final headers = fileManager.buildSignedHeaders(
      key: key,
      method: 'GET',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
    );

    final request = http.Request('GET', fileManager.getUri(key))
      ..headers.addAll(headers);

    final response = await _client.send(request);
    if (_isCancelled) {
      return;
    }

    final File tempFile = await File(
      '${Directory.systemTemp.path}/app_${DateTime.now().microsecondsSinceEpoch}',
    ).create();

    if (response.statusCode == 200) {
      final IOSink fileSink = tempFile.openWrite();
      int received = 0;
      final total = response.contentLength ?? 0;

      await response.stream
          .listen(
            (chunk) {
              if (_isCancelled) {
                fileSink.close();
                if (tempFile.existsSync()) {
                  tempFile.deleteSync();
                }
                return;
              }
              fileSink.add(chunk);
              received += chunk.length;
              if (DateTime.now().difference(lastcallbackTime).inMilliseconds <
                      100 &&
                  received < total) {
                return;
              }
              lastcallbackTime = DateTime.now();
              onProgress?.call(received, total);
              onStatus?.call(
                'Downloading... ${bytesToReadable(received)} / ${bytesToReadable(total)}',
              );
            },
            onDone: () async {
              await fileSink.close();
            },
            onError: (e) async {
              await fileSink.close();
              throw e;
            },
            cancelOnError: true,
          )
          .asFuture();
    } else {
      final body = await response.stream.bytesToString();
      throw Exception('Download failed: ${response.statusCode} - $body');
    }

    if (_isCancelled) return;
    final filemd5 = await HashUtil(tempFile).md5Hash();
    if (filemd5 == md5) {
      if (localFile.existsSync()) {
        localFile.deleteSync();
      }
      tempFile.copySync(localFile.path);
      onStatus?.call('Download complete');
    } else {
      throw Exception(
        'Download failed: MD5 mismatch! expected $md5, got $filemd5',
      );
    }
    tempFile.deleteSync();

    return null;
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
