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
      if (profile?.fileManager == null || !(profile?.accessible ?? false)) {
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
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;

    if (task == TransferTask.upload) {
      onStatus?.call('Upload cancelled');
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

    final contentHash = _cachedSha256 ??= await _sha256OfFile(localFile);
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

    final tempFile = File(
      '${Main.downloadCacheDir}/app_${sha1.convert(utf8.encode(key)).toString()}.tmp',
    );
    final tagFile = File(
      '${Main.downloadCacheDir}/app_${sha1.convert(utf8.encode(key)).toString()}.tag',
    );
    String localEtag = remoteEtag;

    int offset = 0;
    if (tempFile.existsSync() && tagFile.existsSync()) {
      offset = tempFile.lengthSync();
      if (offset >= total) {
        offset = 0;
        tempFile.deleteSync();
        tagFile.deleteSync();
        tempFile.createSync(recursive: true);
        tagFile.createSync(recursive: true);
        tagFile.writeAsStringSync(remoteEtag, flush: true);
      } else {
        localEtag = tagFile.readAsStringSync();
      }
    } else {
      if (tempFile.existsSync()) tempFile.deleteSync();
      tempFile.createSync(recursive: true);
      if (tagFile.existsSync()) tagFile.deleteSync();
      tagFile.createSync(recursive: true);
      tagFile.writeAsStringSync(remoteEtag, flush: true);
    }

    if (_isCancelled) {
      throw TransferPaused();
    }

    if (offset > 0 && offset < total && localEtag == remoteEtag) {
      onStatus?.call('Resuming download...');
    } else {
      offset = 0;
      if (tempFile.existsSync()) tempFile.deleteSync();
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
      if (tempFile.existsSync()) tempFile.deleteSync();
      tagFile.writeAsStringSync(remoteEtag, flush: true);
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
      tagFile.deleteSync();
      onStatus?.call('Download complete');
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 18) {
        await tempFile.copy(localFile.path);
        tempFile.deleteSync();
        tagFile.deleteSync();
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

        if (task == TransferTask.download) {
          final base = sha1.convert(utf8.encode(key)).toString();
          File('${Main.downloadCacheDir}/app_$base.tmp').deleteSync();
          File('${Main.downloadCacheDir}/app_$base.tag').deleteSync();
        }

        if (i == attempts - 1) rethrow;
        await Future.delayed(Duration(seconds: 1 << i));
      }
    }
    throw StateError('unreachable');
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
