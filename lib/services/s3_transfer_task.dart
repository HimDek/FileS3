import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'hash_util.dart';

typedef ProgressCallback = void Function(int bytesTransferred, int totalBytes);
typedef StatusCallback = void Function(String status);

enum TransferTask { upload, download, getUrl }

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

  late final http.Client _client;
  late final Uri _uri;
  bool _isCancelled = false;

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
      } else if (task == TransferTask.getUrl) {
        response = await _getUrl(
          validForSeconds: validForSeconds,
        );
        onStatus?.call('Pre-signed URL generated');
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
    _client.close();
  }

  Future<dynamic> _upload() async {
    final totalBytes = await localFile.length();
    final bytes = await localFile.readAsBytes();
    int uploaded = 0;

    final contentHash = sha256.convert(bytes).toString();
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

    // Streamed request
    final request = http.StreamedRequest('PUT', _uri)
      ..headers.addAll(headers)
      ..contentLength = totalBytes;

    final completer = Completer<void>();
    final stream = localFile.openRead();

    stream.listen(
      (chunk) {
        if (_isCancelled) return;
        request.sink.add(chunk);
        uploaded += chunk.length;
        onProgress?.call(uploaded, totalBytes);
        onStatus?.call('Uploading... ${uploaded}B / ${totalBytes}B');
      },
      onDone: () async {
        await request.sink.close();
        completer.complete();
      },
      onError: (e) async {
        await request.sink.close();
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
    if (_isCancelled) return;

    if (response.statusCode == 200) {
      final fileSink = localFile.openWrite();
      int received = 0;
      final total = response.contentLength ?? 0;

      await response.stream.listen(
        (chunk) {
          if (_isCancelled) return;
          fileSink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
          onStatus?.call('Downloading... ${received}B / ${total}B');
        },
        onDone: () async {
          await fileSink.close();
        },
        onError: (e) async {
          await fileSink.close();
          throw e;
        },
        cancelOnError: true,
      ).asFuture();
    } else {
      final body = await response.stream.bytesToString();
      throw Exception('Download failed: ${response.statusCode} - $body');
    }

    final filemd5 = await HashUtil.md5Hash(localFile);
    if (filemd5 == md5) {
      onStatus?.call('Download complete');
    } else {
      await localFile.delete();
      throw Exception(
        'Download failed: MD5 mismatch! expected $md5, got $filemd5',
      );
    }

    return null;
  }

  Future<String> _getUrl({
    int validForSeconds = 3600,
  }) async {
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final shortDate = _formatDate(now);

    final credentialScope = '$shortDate/$region/s3/aws4_request';

    final queryParams = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '$accessKey/$credentialScope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': validForSeconds.toString(),
      'X-Amz-SignedHeaders': 'host',
      'X-Amz-Content-Sha256': 'UNSIGNED-PAYLOAD',
    };

    /// Canonical query string (sorted)
    final encodedParams = queryParams.entries.map((e) {
      return MapEntry(_encode(e.key), _encode(e.value));
    }).toList();

    encodedParams.sort((a, b) => a.key.compareTo(b.key));

    final canonicalQuery =
        encodedParams.map((e) => '${e.key}=${e.value}').join('&');

    /// Canonical request
    final canonicalRequest = [
      'GET',
      _uri.path,
      canonicalQuery,
      'host:${_uri.host}\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _getSigningKey(
      secretKey,
      shortDate,
      region,
      's3',
    );

    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    final presignedUri = _uri.replace(
      query: '$canonicalQuery&X-Amz-Signature=$signature',
    );

    return presignedUri.toString();
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
    final signedHeadersString =
        sortedEntries.map((e) => e.key.toLowerCase()).join(';');

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
    final hashedCanonical =
        sha256.convert(utf8.encode(canonicalRequest)).toString();

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

  String _encode(String input) {
    return Uri.encodeComponent(input)
        .replaceAll('+', '%20')
        .replaceAll('%7E', '~');
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
}
