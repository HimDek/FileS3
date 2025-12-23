// import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:aws_s3_api/s3-2006-03-01.dart';
import 'models/remote_file.dart';
import 'config_manager.dart';

class S3FileManager {
  late final S3 _s3;
  late final String _accessKey;
  late final String _secretKey;
  late final String _region;
  late final String _bucket;
  late final String _prefix;
  late http.Client _client;

  S3FileManager._(S3Config cfg, http.Client client) {
    _client = client;
    _s3 = S3(
      region: cfg.region,
      credentials: AwsClientCredentials(
        accessKey: cfg.accessKey,
        secretKey: cfg.secretKey,
      ),
      client: _client,
      endpointUrl: cfg.host.isEmpty
          ? 'https://s3.${cfg.region}.amazonaws.com'
          : cfg.host,
    );
    _bucket = cfg.bucket;
    _prefix = cfg.prefix[cfg.prefix.length - 1] != '/'
        ? '${cfg.prefix}/'
        : cfg.prefix;
    _accessKey = cfg.accessKey;
    _secretKey = cfg.secretKey;
    _region = cfg.region;
  }

  static Future<S3FileManager> create(
      BuildContext context, http.Client client) async {
    final cfg = await ConfigManager.loadS3Config(context);
    return S3FileManager._(cfg, client);
  }

  Future<List<String>> listDirectories({String dir = ''}) async {
    final ListObjectsOutput resp = await _s3.listObjects(
      bucket: _bucket,
      prefix: '$_prefix$dir',
      delimiter: '/',
    );
    final contents = resp.commonPrefixes ?? [];
    return contents
        .map((item) => item.prefix?.substring(_prefix.length) ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
  }

  Future<dynamic> createDirectory(String dir) async {
    String key = '$_prefix$dir';

    if (!key.endsWith('/')) {
      key = '$key/';
    }

    final bytes = <int>[];
    final contentHash = sha256.convert(bytes).toString();
    final md5hash = md5.convert(bytes).toString();
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final shortDate = _formatDate(now);

    final headers = _buildSignedHeaders(
      key: key,
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
      contentMD5: base64.encode([
        for (var i = 0; i < md5hash.length; i += 2)
          int.parse(md5hash.substring(i, i + 2), radix: 16),
      ]),
      contentType: 'application/x-directory',
    );

    final request = http.Request(
      'PUT',
      Uri(
        scheme: 'https',
        host: '$_bucket.s3.$_region.amazonaws.com',
        path: '/${key.split('/').map(awsEncode).join('/')}',
      ),
    )
      ..headers.addAll(headers)
      ..bodyBytes = bytes;

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('mkdir failed: ${response.statusCode} - $body');
    }

    return response.headers;
  }

  Future<List<RemoteFile>> listObjects({String dir = ''}) async {
    final ListObjectsOutput resp = await _s3.listObjects(
      bucket: _bucket,
      prefix: '$_prefix$dir',
    );
    final contents = resp.contents ?? [];
    return contents
        .map(
          (item) => RemoteFile(
            key: (item.key ?? _prefix).substring(_prefix.length),
            size: item.size ?? 0,
            etag: item.eTag != null && item.eTag!.isNotEmpty
                ? item.eTag!.substring(1, item.eTag!.length - 1)
                : '',
            lastModified: item.lastModified ?? DateTime.now(),
          ),
        )
        .toList();
  }

  Future<dynamic> copyFile(String sourceKey, String destinationKey) async {
    sourceKey = '$_prefix$sourceKey';
    destinationKey = '$_prefix$destinationKey';

    final copySource =
        '/$_bucket/${sourceKey.split('/').map(awsEncode).join('/')}';

    final bytes = <int>[];
    final contentHash = sha256.convert(bytes).toString();
    final md5hash = md5.convert(bytes).toString();
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final shortDate = _formatDate(now);

    final headers = _buildSignedHeaders(
      key: destinationKey,
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      copySource: copySource,
      contentHash: contentHash,
      contentMD5: base64.encode([
        for (var i = 0; i < md5hash.length; i += 2)
          int.parse(md5hash.substring(i, i + 2), radix: 16),
      ]),
      contentType: 'application/octet-stream',
    );

    final request = http.Request(
      'PUT',
      Uri(
        scheme: 'https',
        host: '$_bucket.s3.$_region.amazonaws.com',
        path: '/${destinationKey.split('/').map(awsEncode).join('/')}',
      ),
    )..headers.addAll(headers);

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('copy failed: ${response.statusCode} - $body');
    }

    return response.headers;
  }

  Future<dynamic> deleteFile(String key) async {
    key = '$_prefix$key';

    final bytes = <int>[];
    final contentHash = sha256.convert(bytes).toString();
    final md5hash = md5.convert(bytes).toString();
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final shortDate = _formatDate(now);

    final headers = _buildSignedHeaders(
      key: key,
      method: 'DELETE',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
      contentMD5: base64.encode([
        for (var i = 0; i < md5hash.length; i += 2)
          int.parse(md5hash.substring(i, i + 2), radix: 16),
      ]),
      contentType: 'application/octet-stream',
    );

    final request = http.Request(
      'DELETE',
      Uri(
        scheme: 'https',
        host: '$_bucket.s3.$_region.amazonaws.com',
        path: '/${key.split('/').map(awsEncode).join('/')}',
      ),
    )..headers.addAll(headers);

    final response = await _client.send(request);

    if (response.statusCode != 204) {
      final body = await response.stream.bytesToString();
      throw Exception('delete failed: ${response.statusCode} - $body');
    }

    return response.headers;
  }

  String getUrl(String key, {int? validForSeconds}) {
    key = '$_prefix$key';
    final uri = Uri(
      scheme: 'https',
      host: '$_bucket.s3.$_region.amazonaws.com',
      path: '/${key.split('/').map(awsEncode).join('/')}',
    );

    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final shortDate = _formatDate(now);

    final credentialScope = '$shortDate/$_region/s3/aws4_request';

    final queryParams = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '$_accessKey/$credentialScope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': (validForSeconds ?? 3600).toString(),
      'X-Amz-SignedHeaders': 'host',
      'X-Amz-Content-Sha256': 'UNSIGNED-PAYLOAD',
    };

    /// Canonical query string (sorted)
    final encodedParams = queryParams.entries.map((e) {
      return MapEntry(encode(e.key), encode(e.value));
    }).toList();

    encodedParams.sort((a, b) => a.key.compareTo(b.key));

    final canonicalQuery =
        encodedParams.map((e) => '${e.key}=${e.value}').join('&');

    /// Canonical request
    final canonicalRequest = [
      'GET',
      uri.path,
      canonicalQuery,
      'host:${uri.host}\n',
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
      _secretKey,
      shortDate,
      _region,
      's3',
    );

    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    final presignedUri = uri.replace(
      query: '$canonicalQuery&X-Amz-Signature=$signature',
    );

    return presignedUri.toString();
  }

  Map<String, String> _buildSignedHeaders({
    required String key,
    required String method,
    required String amzDate,
    required String shortDate,
    required String contentHash,
    String? contentMD5,
    String? contentType,
    String? copySource,
  }) {
    final service = 's3';
    final host = '$_bucket.s3.$_region.amazonaws.com';
    final credentialScope = '$shortDate/$_region/$service/aws4_request';

    // 1. Build the unsorted headers map
    final headers = <String, String>{
      'Host': host,
      'x-amz-content-sha256': contentHash,
      'x-amz-date': amzDate,
      if (copySource != null) 'x-amz-copy-source': copySource,
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
    final signingKey = _getSigningKey(_secretKey, shortDate, _region, service);

    // 10. Compute signature
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    // 11. Build Authorization header
    final authorization = [
      'AWS4-HMAC-SHA256 Credential=$_accessKey/$credentialScope',
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

  // String _guessMime(File f) {
  //   final ext = f.path.split('.').last.toLowerCase();
  //   switch (ext) {
  //     case 'jpg':
  //     case 'jpeg':
  //       return 'image/jpeg';
  //     case 'png':
  //       return 'image/png';
  //     case 'pdf':
  //       return 'application/pdf';
  //     case 'txt':
  //       return 'text/plain';
  //     default:
  //       return 'application/octet-stream';
  //   }
  // }

  String encode(String input) {
    return Uri.encodeComponent(input)
        .replaceAll('+', '%20')
        .replaceAll('%7E', '~');
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
