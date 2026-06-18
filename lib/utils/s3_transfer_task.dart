import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/hash_util.dart';
import 'package:files3/helpers.dart';

enum TransferTask { upload, download }

class TransferPaused implements Exception {}

class TransferAborted implements Exception {}

class S3TransferTask {
  final String key;
  final File localFile;
  final Digest md5;
  final TransferTask task;
  final Profile? profile;
  final void Function(String status)? onStatus;
  final void Function(int bytesTransferred, int? totalBytes)? onProgress;

  Timer? watchdog;

  void resetWatchdog() {
    watchdog?.cancel();
    watchdog = Timer(
      const Duration(minutes: 1),
      () => cancel(reason: 'Watchdog timeout'),
    );
  }

  bool _isCancelled = false;
  DateTime lastCallbackTime = DateTime.fromMicrosecondsSinceEpoch(0);
  String? _cachedSha256;

  S3TransferTask({
    required this.key,
    required this.localFile,
    required this.md5,
    required this.profile,
    required this.task,
    this.onProgress,
    this.onStatus,
  });

  /// Starts upload or download
  Future<dynamic> start() async {
    _isCancelled = false;
    final HttpClient httpClient = HttpClient();

    try {
      if (profile?.fileManager == null ||
          !(profile?.accessible.value ?? false)) {
        throw Exception('Profile is not accessible');
      }

      httpClient.connectionTimeout = const Duration(seconds: 30);
      httpClient.badCertificateCallback = null;

      return task == TransferTask.upload
          ? await retry(() => _upload(httpClient))
          : await retry(() => _download(httpClient));
    } catch (e) {
      if (e is TransferPaused) {
      } else if (e is TransferAborted) {
        onStatus?.call('Upload cancelled');
      } else {
        onStatus?.call(
          task == TransferTask.upload
              ? 'Upload failed: $e'
              : 'Download failed: $e',
        );
      }
    } finally {
      httpClient.close();
    }
  }

  /// Cancel transfer
  void cancel({String? reason}) {
    if (_isCancelled) return;
    _isCancelled = true;

    if (task == TransferTask.upload) {
      onStatus?.call('Upload cancelled! $reason');
    } else {
      onStatus?.call('Download cancelled! $reason');
    }
  }

  // ---------------------------------------------------------------------------
  // UPLOAD
  // ---------------------------------------------------------------------------

  Future<dynamic> _upload(HttpClient httpClient) async {
    final totalBytes = await localFile.length();
    int uploaded = 0;

    if (totalBytes > 5 * 1024 * 1024 * 1024) {
      throw Exception('Multipart upload required for files > 5GB');
    }

    // final contentHash = _cachedSha256 ??= await _sha256OfFile(localFile);
    final contentHash = 'UNSIGNED-PAYLOAD';
    final contentMD5 = base64.encode(md5.bytes);
    final now = DateTime.now().toUtc();

    final headers = profile!.fileManager!.buildSignedHeaders(
      key: key,
      method: 'PUT',
      amzDate: S3FileManager.formatAmzDate(now),
      shortDate: S3FileManager.formatDate(now),
      contentHash: contentHash,
      contentMD5: contentMD5,
      contentType: S3FileManager.guessMime(localFile),
    );

    final uri = profile!.fileManager!.getUri(key);
    final req = await httpClient.openUrl('PUT', uri);

    headers.forEach(req.headers.set);
    req.contentLength = totalBytes;
    req.bufferOutput = false; // important for real progress

    if (_isCancelled) {
      throw TransferAborted();
    }

    await req.addStream(
      localFile.openRead().map((chunk) {
        if (_isCancelled) {
          throw TransferAborted();
        }

        uploaded += chunk.length;

        if (DateTime.now().difference(lastCallbackTime).inMilliseconds >= 100 ||
            uploaded >= totalBytes) {
          resetWatchdog();
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

    if (_isCancelled) {
      throw TransferAborted();
    }

    final res = await req.close();

    if (res.statusCode >= 200 && res.statusCode < 300) {
      onStatus?.call('Upload complete');

      final responseHeaders = <String, String>{};
      res.headers.forEach((k, v) {
        responseHeaders[k] = v.join(',');
      });

      return responseHeaders;
    } else {
      if (_isCancelled) {
        throw TransferAborted();
      }
      final body = await utf8.decodeStream(res);
      throw Exception('Upload failed: ${res.statusCode} - $body');
    }
  }

  // ---------------------------------------------------------------------------
  // DOWNLOAD
  // ---------------------------------------------------------------------------

  Future<dynamic> _download(HttpClient httpClient) async {
    final now = DateTime.now().toUtc();

    final head = await profile!.fileManager!.headObject(key);
    final remoteEtag = head.etag;
    final total = head.size;

    final tempFile = File(Main.cachePathFromKey(key));
    final tagFile = File(Main.tagPathFromKey(key));
    String localEtag = remoteEtag;

    int offset = 0;
    if ((await tempFile.exists()) && (await tagFile.exists())) {
      offset = await tempFile.length();
      if (offset >= total) {
        offset = 0;
        await tempFile.delete();
        await tagFile.delete();
        await tempFile.create(recursive: true);
        await tagFile.create(recursive: true);
        await tagFile.writeAsString(remoteEtag, flush: true);
      } else {
        localEtag = await tagFile.readAsString();
      }
    } else {
      if (await tempFile.exists()) await tempFile.delete();
      await tempFile.create(recursive: true);
      if (await tagFile.exists()) await tagFile.delete();
      await tagFile.create(recursive: true);
      await tagFile.writeAsString(remoteEtag, flush: true);
    }

    if (_isCancelled) {
      throw TransferPaused();
    }

    if (offset > 0 && offset < total && localEtag == remoteEtag) {
      onStatus?.call('Resuming download...');
    } else {
      offset = 0;
      if (await tempFile.exists()) await tempFile.delete();
    }

    final headers = profile!.fileManager!.buildSignedHeaders(
      key: key,
      method: 'GET',
      amzDate: S3FileManager.formatAmzDate(now),
      shortDate: S3FileManager.formatDate(now),
      contentHash: S3FileManager.emptySha256,
    );

    final uri = profile!.fileManager!.getUri(key);
    final req = await httpClient.openUrl('GET', uri);

    if (offset > 0) {
      req.headers.set('Range', 'bytes=$offset-');
    }

    headers.forEach(req.headers.set);
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

    if (_isCancelled) {
      throw TransferPaused();
    }

    final res = await req.close();

    if (_isCancelled) {
      throw TransferPaused();
    }

    if (offset > 0 && res.statusCode != 206) {
      if (await tempFile.exists()) await tempFile.delete();
      await tagFile.writeAsString(remoteEtag, flush: true);
      return await _download(httpClient);
    } else {
      if (offset > 0 && offset < total && localEtag == remoteEtag) {
        onStatus?.call('Resuming download...');
        onProgress?.call(offset, total);
      }
    }

    if (_isCancelled) {
      throw TransferPaused();
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = await utf8.decodeStream(res);
      throw Exception('Download failed: ${res.statusCode} - $body');
    }

    final sink = tempFile.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    int received = offset;

    try {
      await for (final chunk in res) {
        if (_isCancelled) {
          throw TransferPaused();
        }
        sink.add(chunk);

        received += chunk.length;

        if (DateTime.now().difference(lastCallbackTime).inMilliseconds >= 100 ||
            received >= (total)) {
          resetWatchdog();
          lastCallbackTime = DateTime.now();
          onProgress?.call(received, total);
          if (received >= (total)) {
            onStatus?.call('Finalizing download...');
          } else {
            onStatus?.call(
              'Downloaded ${bytesToReadable(received)} of ${bytesToReadable(total)}',
            );
          }
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (_isCancelled) {
      throw TransferPaused();
    }

    final fileMd5 = await HashUtil(tempFile).md5Hash();

    if (_isCancelled) {
      throw TransferPaused();
    }

    if (fileMd5 != md5) {
      await tempFile.delete();
      throw Exception(
        'Download failed: MD5 mismatch! expected $md5, got $fileMd5',
      );
    }

    if (await localFile.exists()) {
      await localFile.delete();
    }

    try {
      await tempFile.rename(localFile.path);
      await tagFile.delete();
      onStatus?.call('Download complete');
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 18) {
        await tempFile.copy(localFile.path);
        await tempFile.delete();
        await tagFile.delete();
        onStatus?.call('Download complete');
      } else {
        throw Exception('Storage write failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UTILS
  // ---------------------------------------------------------------------------

  Future<T> retry<T>(Future<T> Function() fn, {int attempts = 3}) async {
    for (int i = 0; i < attempts; i++) {
      try {
        return await fn();
      } catch (e) {
        if (e is TransferPaused) rethrow;

        // if (task == TransferTask.download) {
        //   await File(Main.cachePathFromKey(key)).delete();
        //   await File(Main.tagPathFromKey(key)).delete();
        // }

        if (i == attempts - 1) rethrow;
        await Future.delayed(Duration(seconds: 1 << i));
      }
    }
    throw StateError('unreachable');
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    _cachedSha256 = digest.toString();
    return _cachedSha256!;
  }
}
