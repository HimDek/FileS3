// import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
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
  late final String _host;
  late http.Client _client;

  bool configured = false;

  static const emptySha256 =
      'e3b0c44298fc1c149afbf4c8996fb924'
      '27ae41e4649b934ca495991b7852b855';

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
    _prefix = cfg.prefix;
    _host = cfg.host.isEmpty
        ? '$_bucket.s3.${cfg.region}.amazonaws.com'
        : cfg.host;
    _accessKey = cfg.accessKey;
    _secretKey = cfg.secretKey;
    _region = cfg.region;
    configured = true;
  }

  static Future<S3FileManager?> create(
    BuildContext? context,
    http.Client client,
  ) async {
    final cfg = await ConfigManager.loadS3Config(context: context);
    if (cfg != null) {
      return S3FileManager._(cfg, client);
    } else {
      return null;
    }
  }

  Future<dynamic> createDirectory(String dir) async {
    String key = !dir.endsWith('/') ? '$dir/' : dir;

    final contentHash = emptySha256;
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final headers = buildSignedHeaders(
      key: key,
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
    );

    final request = http.Request('PUT', getUri(key))..headers.addAll(headers);

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('mkdir failed: ${response.statusCode} - $body');
    }

    return response.headers;
  }

  Future<List<RemoteFile>> listObjects({String dir = ''}) async {
    String prefix = p.posix.join(_prefix, dir);
    prefix = prefix.endsWith('/') ? prefix : '$prefix/';
    final ListObjectsOutput resp = await _s3.listObjects(
      bucket: _bucket,
      prefix: prefix,
    );
    final contents = resp.contents ?? [];
    List<RemoteFile> list = contents
        .map(
          (item) => RemoteFile(
            key: (item.key ?? prefix).substring(prefix.length),
            size: item.size ?? 0,
            etag: item.eTag != null && item.eTag!.isNotEmpty
                ? item.eTag!.substring(1, item.eTag!.length - 1)
                : '',
            lastModified: item.lastModified ?? DateTime.now(),
          ),
        )
        .toList();

    final existingPaths = list.map((o) => o.key).toSet();

    for (final obj in list.toList()) {
      final normalized = p.normalize(obj.key);
      final isDir = normalized.endsWith('/');

      final basePath = isDir
          ? p.posix.dirname(normalized.substring(0, normalized.length - 1))
          : p.posix.dirname(normalized);

      if (basePath == '.' || basePath.isEmpty) continue;

      final parts = p.posix.split(basePath);

      String current = '';
      for (final part in parts) {
        if (part.isEmpty) continue;

        current = p.posix.join(current, part);
        final dirPath = '$current/';

        if (!existingPaths.contains(dirPath)) {
          final dirObject = RemoteFile(
            key: dirPath,
            size: 0,
            etag: '',
            lastModified: DateTime.now(),
          );

          list.add(dirObject);
          existingPaths.add(dirPath);
        }
      }
    }

    return list;
  }

  Future<dynamic> copyFile(String sourceKey, String destinationKey) async {
    String prefixedSourceKey = p.posix.join(_prefix, sourceKey);

    final copySource =
        '/$_bucket/${prefixedSourceKey.split('/').map(awsEncode).join('/')}';

    final contentHash = emptySha256;
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final headers = buildSignedHeaders(
      key: destinationKey,
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      copySource: copySource,
      contentHash: contentHash,
    );

    final request = http.Request('PUT', getUri(destinationKey))
      ..headers.addAll(headers);

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('copy failed: ${response.statusCode} - $body');
    }

    return response.headers;
  }

  Future<dynamic> deleteFile(String key) async {
    final contentHash = emptySha256;
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final headers = buildSignedHeaders(
      key: key,
      method: 'DELETE',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
    );

    final request = http.Request('DELETE', getUri(key))
      ..headers.addAll(headers);

    final response = await _client.send(request);

    if (response.statusCode != 204) {
      final body = await response.stream.bytesToString();
      throw Exception('delete failed: ${response.statusCode} - $body');
    }

    return response.headers;
  }

  String getUrl(String key, {int? validForSeconds}) {
    final uri = getUri(key);

    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

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

    final canonicalQuery = encodedParams
        .map((e) => '${e.key}=${e.value}')
        .join('&');

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

    final signingKey = getSigningKey(_secretKey, shortDate, _region, 's3');

    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    final presignedUri = uri.replace(
      query: '$canonicalQuery&X-Amz-Signature=$signature',
    );

    return presignedUri.toString();
  }

  Map<String, String> buildSignedHeaders({
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
        .map(
          (e) =>
              '${e.key.toLowerCase()}:${e.value.trim().replaceAll(RegExp(r'\s+'), ' ')}\n',
        )
        .join();

    // 4. Build signedHeadersString from those same sorted keys
    final signedHeadersString = sortedEntries
        .map((e) => e.key.toLowerCase())
        .join(';');

    // 5. Canonical URI (already encoded)
    final encodedPath =
        '/${p.join(_prefix, key).split('/').map(awsEncode).join('/')}';

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
    final signingKey = getSigningKey(_secretKey, shortDate, _region, service);

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

  List<int> getSigningKey(
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

  String formatAmzDate(DateTime time) =>
      '${time.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

  String formatDate(DateTime time) =>
      time.toIso8601String().split('T').first.replaceAll('-', '');

  String guessMime(File f) {
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

  Uri getUri(String key) {
    return Uri(
      scheme: 'https',
      host: _host,
      path: '/${p.join(_prefix, key).split('/').map(awsEncode).join('/')}',
    );
  }

  String encode(String input) {
    return Uri.encodeComponent(
      input,
    ).replaceAll('+', '%20').replaceAll('%7E', '~');
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
