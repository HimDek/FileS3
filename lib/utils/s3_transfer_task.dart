import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/hash_util.dart';
import 'package:files3/helpers.dart';

enum TransferTask { upload, download }

class S3TransferTask {
  final String key;
  final File localFile;
  final Digest md5;
  final S3FileManager fileManager;
  final TransferTask task;
  final void Function(int bytesTransferred, int totalBytes)? onProgress;
  final void Function(String status)? onStatus;

  final HttpClient _httpClient = HttpClient();

  bool _isCancelled = false;

  static DateTime lastCallbackTime = DateTime.fromMicrosecondsSinceEpoch(0);

  S3TransferTask({
    required this.key,
    required this.localFile,
    required this.md5,
    required this.fileManager,
    required this.task,
    this.onProgress,
    this.onStatus,
  });

  /// Starts upload or download
  Future<dynamic> start() async {
    try {
      onStatus?.call(
        task == TransferTask.upload
            ? 'Starting upload...'
            : 'Starting download...',
      );

      if (task == TransferTask.upload) {
        return await _upload();
      } else {
        return await _download();
      }
    } catch (e) {
      if (_isCancelled) {
        onStatus?.call('Cancelled');
      } else {
        onStatus?.call('Error: $e');
      }
      rethrow;
    } finally {
      _httpClient.close(force: true);
    }
  }

  /// Cancel transfer
  void cancel() {
    _isCancelled = true;
  }

  // ---------------------------------------------------------------------------
  // UPLOAD
  // ---------------------------------------------------------------------------

  Future<dynamic> _upload() async {
    final totalBytes = await localFile.length();
    int uploaded = 0;

    final contentHash = await _sha256OfFile(localFile);
    final contentMD5 = base64.encode(md5.bytes);
    final now = DateTime.now().toUtc();

    final headers = fileManager.buildSignedHeaders(
      key: key,
      method: 'PUT',
      amzDate: fileManager.formatAmzDate(now),
      shortDate: fileManager.formatDate(now),
      contentHash: contentHash,
      contentMD5: contentMD5,
      contentType: fileManager.guessMime(localFile),
    );

    final uri = fileManager.getUri(key);
    final req = await _httpClient.openUrl('PUT', uri);

    headers.forEach(req.headers.set);
    req.contentLength = totalBytes;
    req.bufferOutput = false; // important for real progress

    await req.addStream(
      localFile.openRead().map((chunk) {
        if (_isCancelled) {
          throw Exception('Upload cancelled');
        }

        uploaded += chunk.length;

        if (DateTime.now().difference(lastCallbackTime).inMilliseconds >= 100 ||
            uploaded >= totalBytes) {
          lastCallbackTime = DateTime.now();
          onProgress?.call(uploaded, totalBytes);

          if (uploaded >= totalBytes) {
            onStatus?.call('Finalizing upload...');
          } else {
            onStatus?.call(
              'Uploading... ${bytesToReadable(uploaded)} / ${bytesToReadable(totalBytes)}',
            );
          }
        }

        return chunk;
      }),
    );

    final res = await req.close();

    if (res.statusCode == 200) {
      onStatus?.call('Upload complete');

      final responseHeaders = <String, String>{};
      res.headers.forEach((k, v) {
        responseHeaders[k] = v.join(',');
      });

      return responseHeaders;
    } else {
      final body = await utf8.decodeStream(res);
      throw Exception('Upload failed: ${res.statusCode} - $body');
    }
  }

  // ---------------------------------------------------------------------------
  // DOWNLOAD
  // ---------------------------------------------------------------------------

  Future<dynamic> _download() async {
    final now = DateTime.now().toUtc();

    final headers = fileManager.buildSignedHeaders(
      key: key,
      method: 'GET',
      amzDate: fileManager.formatAmzDate(now),
      shortDate: fileManager.formatDate(now),
      contentHash: S3FileManager.emptySha256,
    );

    final uri = fileManager.getUri(key);
    final req = await _httpClient.openUrl('GET', uri);

    headers.forEach(req.headers.set);

    final res = await req.close();

    if (res.statusCode != 200) {
      final body = await utf8.decodeStream(res);
      throw Exception('Download failed: ${res.statusCode} - $body');
    }

    final tempFile = await File(
      '${Directory.systemTemp.path}/app_${DateTime.now().microsecondsSinceEpoch}',
    ).create();

    final sink = tempFile.openWrite();
    final total = res.contentLength;
    int received = 0;

    try {
      await for (final chunk in res) {
        if (_isCancelled) {
          throw Exception('Download cancelled');
        }

        sink.add(chunk);
        received += chunk.length;

        if (DateTime.now().difference(lastCallbackTime).inMilliseconds >= 100 ||
            received >= total) {
          lastCallbackTime = DateTime.now();
          onProgress?.call(received, total);
          if (received >= total) {
            onStatus?.call('Finalizing download...');
          } else {
            onStatus?.call(
              'Downloading... ${bytesToReadable(received)} / ${bytesToReadable(total)}',
            );
          }
        }
      }
    } finally {
      await sink.close();
    }

    if (_isCancelled) {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      return;
    }

    final fileMd5 = await HashUtil(tempFile).md5Hash();
    if (fileMd5 != md5) {
      tempFile.deleteSync();
      throw Exception(
        'Download failed: MD5 mismatch! expected $md5, got $fileMd5',
      );
    }

    if (localFile.existsSync()) {
      localFile.deleteSync();
    }

    try {
      tempFile.renameSync(localFile.path);
      onStatus?.call('Download complete');
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 18) {
        await tempFile.copy(localFile.path);
        tempFile.deleteSync();
        onStatus?.call('Download complete');
      } else {
        throw Exception('Storage write failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UTILS
  // ---------------------------------------------------------------------------

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
