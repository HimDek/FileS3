import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:s3_drive/components.dart';
import 'hash_util.dart';

typedef ProgressCallback = void Function(int bytesTransferred, int totalBytes);
typedef StatusCallback = void Function(String status);

enum TransferTask { upload, download }

class S3TransferTask {
  final String accessKey;
  final String secretKey;
  final String region;
  final String bucket;
  final String key;
  final File localFile;
  final TransferTask task;
  final String md5;
  final ProgressCallback? onProgress;
  final StatusCallback? onStatus;
  final int validForSeconds;

  bool _sinkClosed = false;
  bool _isCancelled = false;
  StreamSubscription<List<int>>? sub;

  late final Uri _uri;
  late final http.Client _client;

  S3TransferTask({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.bucket,
    required this.key,
    required this.localFile,
    required this.task,
    required this.md5,
    this.onProgress,
    this.onStatus,
    this.validForSeconds = 3600,
  }) {
    _client = http.Client();
    _uri = Uri(
      scheme: 'https',
      host: '$bucket.s3.$region.amazonaws.com',
      path: '/${key.split('/').map(awsEncode).join('/')}',
    );
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
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final shortDate = _formatDate(now);

    // Prepare signed headers
    final headers = _buildSignedHeaders(
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
      contentMD5: base64.encode([
        for (var i = 0; i < md5.length; i += 2)
          int.parse(md5.substring(i, i + 2), radix: 16),
      ]),
      contentType: _guessMime(localFile),
    );
    headers['Expect'] = '100-continue';

    // Streamed request
    final request = http.StreamedRequest('PUT', _uri)
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
    final amzDate = _formatAmzDate(now);
    final shortDate = _formatDate(now);
    final contentHash = sha256.convert(utf8.encode("")).toString();

    final headers = _buildSignedHeaders(
      method: 'GET',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
    );

    final request = http.Request('GET', _uri)..headers.addAll(headers);

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
    final filemd5 = HashUtil.md5Hash(tempFile);
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

  Map<String, String> _buildSignedHeaders({
    required String method,
    required String amzDate,
    required String shortDate,
    required String contentHash,
    String? contentMD5,
    String? contentType,
  }) {
    final service = 's3';
    final host = '$bucket.s3.$region.amazonaws.com';
    final credentialScope = '$shortDate/$region/$service/aws4_request';

    // 1. Build the unsorted headers map
    final headers = <String, String>{
      'Host': host,
      'x-amz-content-sha256': contentHash,
      'x-amz-date': amzDate,
      if (contentMD5 != null) 'Content-MD5': contentMD5,
      if (contentType != null) 'Content-Type': contentType,
    };
    if (method == 'PUT' && contentType == null) {
      headers['Content-Type'] = 'application/octet-stream';
    }

    // 2. Sort entries by lowercase header name
    final sortedEntries = headers.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    // 3. Build canonicalHeaders in sorted order
    final canonicalHeaders = sortedEntries
        .map((e) => '${e.key.toLowerCase()}:${e.value.trim()}\n')
        .join();

    // 4. Build signedHeadersString from those same sorted keys
    final signedHeadersString = sortedEntries
        .map((e) => e.key.toLowerCase())
        .join(';');

    // 5. Canonical URI (already encoded)
    final encodedPath = '/${key.split('/').map(awsEncode).join('/')}';

    // 6. Assemble canonical request
    final canonicalRequest = [
      method,
      encodedPath,
      '', // no query string
      canonicalHeaders,
      signedHeadersString,
      contentHash,
    ].join('\n');

    // 7. Hash the canonical request
    final hashedCanonical = sha256
        .convert(utf8.encode(canonicalRequest))
        .toString();

    // 8. Build string to sign
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      hashedCanonical,
    ].join('\n');

    // 9. Derive signing key
    final signingKey = _getSigningKey(secretKey, shortDate, region, service);

    // 10. Compute signature
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    // 11. Build Authorization header
    final authorization = [
      'AWS4-HMAC-SHA256 Credential=$accessKey/$credentialScope',
      'SignedHeaders=$signedHeadersString',
      'Signature=$signature',
    ].join(', ');

    // 12. Return all headers including Authorization
    return {...headers, 'Authorization': authorization};
  }

  List<int> _sign(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  List<int> _getSigningKey(
    String secret,
    String date,
    String region,
    String service,
  ) {
    final kDate = _sign(utf8.encode('AWS4$secret'), date);
    final kRegion = _sign(kDate, region);
    final kService = _sign(kRegion, service);
    return _sign(kService, 'aws4_request');
  }

  String _formatAmzDate(DateTime time) =>
      '${time.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

  String _formatDate(DateTime time) =>
      time.toIso8601String().split('T').first.replaceAll('-', '');

  String _guessMime(File f) {
    final ext = f.path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  String awsEncode(String input) {
    return input.codeUnits.map((unit) {
      final c = String.fromCharCode(unit);
      if (RegExp(r'^[A-Za-z0-9\-_.~]$').hasMatch(c)) {
        return c;
      }
      return '%${unit.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    }).join();
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
