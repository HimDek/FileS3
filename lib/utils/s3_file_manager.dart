import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:aws_s3_api/s3-2006-03-01.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/profile.dart';
import 'package:files3/models.dart';

class S3FileManager {
  late final S3 _s3;
  late final Profile _profile;
  late final String _accessKey;
  late final String _secretKey;
  late final String _region;
  late final String _bucket;
  late final String _prefix;
  late final String _host;
  late http.Client _client;

  static const emptySha256 =
      'e3b0c44298fc1c149afbf4c8996fb924'
      '27ae41e4649b934ca495991b7852b855';

  S3FileManager._(Profile profile, S3Config cfg, http.Client client) {
    _profile = profile;
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
          : 'https://${cfg.host}',
    );
    _bucket = cfg.bucket;
    _prefix = cfg.prefix;
    _host = cfg.host.isEmpty
        ? '$_bucket.s3.${cfg.region}.amazonaws.com'
        : '$_bucket.${cfg.host}';
    _accessKey = cfg.accessKey;
    _secretKey = cfg.secretKey;
    _region = cfg.region;
  }

  static S3FileManager? create(
    Profile profile,
    http.Client client,
    S3Config cfg,
  ) {
    if (cfg.accessKey.isNotEmpty &&
        cfg.secretKey.isNotEmpty &&
        cfg.region.isNotEmpty &&
        cfg.bucket.isNotEmpty) {
      return S3FileManager._(profile, cfg, client);
    } else {
      return null;
    }
  }

  Future<dynamic> createDirectory(String dir) async {
    String key = p.asDir(dir);

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

  Future<List<RemoteFile>> listObjects(String dir) async {
    String? prefix = p.join(
      _prefix,
      p.s3(p.relative(dir, from: _profile.name)),
    );
    prefix = prefix.isEmpty ? null : prefix;
    final ListObjectsOutput resp = await _s3.listObjects(
      bucket: _bucket,
      prefix: prefix,
    );
    final contents = resp.contents ?? [];
    List<RemoteFile> list = contents
        .where((item) => item.key != null)
        .map(
          (item) => RemoteFile(
            key: p.join(
              _profile.name,
              p.s3(p.relative(item.key!, from: _prefix)),
            ),
            size: item.size ?? 0,
            etag: item.eTag != null && item.eTag!.isNotEmpty
                ? item.eTag!.substring(1, item.eTag!.length - 1)
                : '',
            lastModified: item.lastModified ?? DateTime.now(),
          ),
        )
        .toList();
    return list;
  }

  Future<dynamic> copyFile(String sourceKey, String destinationKey) async {
    String prefixedSourceKey = p.join(
      _prefix,
      p.relative(sourceKey, from: _profile.name),
    );

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
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final credentialScope = '$shortDate/$_region/s3/aws4_request';
    final encodedPath =
        '/${p.join(_prefix, p.s3(p.relative(key, from: _profile.name))).split('/').map(awsEncode).join('/')}';

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
      encodedPath,
      canonicalQuery,
      'host:${_host.toLowerCase()}\n',
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

    final presignedUri = Uri(
      scheme: 'https',
      host: _host,
      path: encodedPath,
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
    final host = _host;
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
        '/${p.join(_prefix, p.s3(p.relative(key, from: _profile.name))).split('/').map(awsEncode).join('/')}';

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

  static List<int> _sign(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  static List<int> getSigningKey(
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

  static String formatAmzDate(DateTime time) =>
      '${time.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

  static String formatDate(DateTime time) =>
      time.toIso8601String().split('T').first.replaceAll('-', '');

  static String guessMime(File f) {
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

  Future<({String etag, int size})> headObject(String key) async {
    final now = DateTime.now().toUtc();

    final headers = buildSignedHeaders(
      key: key,
      method: 'HEAD',
      amzDate: formatAmzDate(now),
      shortDate: formatDate(now),
      contentHash: S3FileManager.emptySha256,
    );

    final uri = getUri(key);
    final res = await _client.head(uri, headers: headers);

    if (res.statusCode != 200) {
      throw Exception('HEAD failed: ${res.statusCode}');
    }

    final etag = res.headers['etag']?.replaceAll('"', '');
    final length = res.headers['content-length'];

    if (etag == null || length == null) {
      throw Exception('HEAD missing ETag or Content-Length');
    }

    return (etag: etag, size: int.parse(length));
  }

  Uri getUri(String key) {
    return Uri(
      scheme: 'https',
      host: _host,
      path:
          '/${p.join(_prefix, p.s3(p.relative(key, from: _profile.name))).split('/').map(awsEncode).join('/')}',
    );
  }

  static String encode(String input) {
    return Uri.encodeComponent(
      input,
    ).replaceAll('+', '%20').replaceAll('%7E', '~');
  }

  static String awsEncode(String input) {
    final bytes = utf8.encode(input);
    final buffer = StringBuffer();

    for (final b in bytes) {
      final c = String.fromCharCode(b);
      if (RegExp(r'^[A-Za-z0-9\-_.~]$').hasMatch(c)) {
        buffer.write(c);
      } else {
        buffer.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }

    return buffer.toString();
  }
}
