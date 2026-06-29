import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/profile.dart';
import 'package:files3/models.dart';

class S3Exception extends HttpException {
  final int? code;

  const S3Exception(super.message, {this.code, super.uri});

  @override
  String toString() => 'S3Exception($code): $message';
}

class S3FileManager {
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

  Future<Map<String, String>> createDirectory(String dir) async {
    final encodedUri = getEncodedUri(key: p.s3.asDir(dir));
    final contentHash = emptySha256;
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final headers = buildSignedHeaders(
      encodedUri: encodedUri,
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
    );

    final request = http.Request('PUT', encodedUri)..headers.addAll(headers);

    final response = await _client
        .send(request)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw S3Exception(
        'Create Directory Failed with response: $body',
        code: response.statusCode,
        uri: encodedUri,
      );
    }

    return response.headers;
  }

  Future<Iterable<RemoteFile>> listObjects(String dir) async {
    String? prefix = p.s3.join(
      _prefix,
      p.s3.relative(dir, from: _profile.name),
    );
    prefix = prefix.isEmpty ? null : prefix;

    final files = <RemoteFile>[];
    String? continuationToken;

    while (true) {
      final contentHash = emptySha256;
      final now = DateTime.now().toUtc();
      final amzDate = formatAmzDate(now);
      final shortDate = formatDate(now);
      final query = <String, String>{
        'list-type': '2',
        'prefix': ?prefix,
        'continuation-token': ?continuationToken,
      };
      final encodedUri = getEncodedUri(queryParameters: query);

      final headers = buildSignedHeaders(
        encodedUri: encodedUri,
        method: 'GET',
        amzDate: amzDate,
        shortDate: shortDate,
        contentHash: contentHash,
      );

      final request = http.Request('GET', encodedUri)..headers.addAll(headers);

      final response = await _client
          .send(request)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Request timed out'),
          );

      final body = await response.stream.bytesToString();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw S3Exception(
          'ListObjectsV2 Failed with response: $body',
          code: response.statusCode,
          uri: encodedUri,
        );
      }

      final xml = XmlDocument.parse(body);

      for (final object in xml.findAllElements('Contents')) {
        final key = object.getElement('Key')?.innerText;
        if (key == null) continue;

        files.add(
          RemoteFile(
            key: p.s3.join(_profile.name, p.s3.relative(key, from: _prefix)),
            size: int.parse(object.getElement('Size')?.innerText ?? '0'),
            etag:
                object.getElement('ETag')?.innerText.replaceAll('"', '') ?? '',
            lastModified: DateTime.parse(
              object.getElement('LastModified')?.innerText ??
                  '1970-01-01T00:00:00Z',
            ),
          ),
        );
      }

      final truncated =
          xml
              .getElement('ListBucketResult')
              ?.getElement('IsTruncated')
              ?.innerText ==
          'true';

      if (!truncated) break;

      continuationToken = xml
          .getElement('ListBucketResult')
          ?.getElement('NextContinuationToken')
          ?.innerText;
    }

    return files;
  }

  Future<Map<String, String>> copyFile(
    String sourceKey,
    String destinationKey, {
    Profile? sourceProfile,
  }) async {
    sourceProfile ??= _profile;
    final copySource =
        '/${sourceProfile.cfg.bucket}/${p.s3.join(sourceProfile.cfg.prefix, p.s3.relative(sourceKey, from: sourceProfile.name)).split('/').map(awsEncode).join('/')}';
    final encodedUri = getEncodedUri(key: destinationKey);

    final contentHash = emptySha256;
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final headers = buildSignedHeaders(
      encodedUri: encodedUri,
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      copySource: copySource,
      contentHash: contentHash,
    );

    final request = http.Request('PUT', encodedUri)..headers.addAll(headers);

    final response = await _client
        .send(request)
        .timeout(
          const Duration(minutes: 1),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );

    if (response.statusCode == 403) {
      final body = await response.stream.bytesToString();
      throw S3Exception(
        'Copy Failed with response: $body',
        code: response.statusCode,
        uri: encodedUri,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw S3Exception(
        'Copy Failed with response: $body',
        code: response.statusCode,
        uri: encodedUri,
      );
    }

    return response.headers;
  }

  Future<Map<String, String>> deleteFile(String key) async {
    final encodedUri = getEncodedUri(key: key);
    final contentHash = emptySha256;
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final headers = buildSignedHeaders(
      encodedUri: encodedUri,
      method: 'DELETE',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
    );

    final request = http.Request('DELETE', encodedUri)..headers.addAll(headers);

    final response = await _client
        .send(request)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );

    if (response.statusCode != 204) {
      final body = await response.stream.bytesToString();
      throw S3Exception(
        'Delete Failed with response: $body',
        code: response.statusCode,
        uri: encodedUri,
      );
    }

    return response.headers;
  }

  Future<Map<String, String>> headObject(String key) async {
    final encodedUri = getEncodedUri(key: key);
    final now = DateTime.now().toUtc();

    final headers = buildSignedHeaders(
      encodedUri: encodedUri,
      method: 'HEAD',
      amzDate: formatAmzDate(now),
      shortDate: formatDate(now),
      contentHash: S3FileManager.emptySha256,
    );

    final res = await _client
        .head(encodedUri, headers: headers)
        .timeout(
          const Duration(minutes: 1),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw S3Exception(
        'HEAD Failed with response: ${res.body}',
        code: res.statusCode,
        uri: encodedUri,
      );
    }

    return res.headers;
  }

  Future<Map<String, String>> getTags(String key) async {
    final contentHash = emptySha256;
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final encodedUri = getEncodedUri(
      key: key,
      queryParameters: {'tagging': ''},
    );

    final headers = buildSignedHeaders(
      encodedUri: encodedUri,
      method: 'GET',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
    );

    final request = http.Request('GET', encodedUri)..headers.addAll(headers);

    final response = await _client
        .send(request)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Request timed out'),
        );

    final body = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw S3Exception(
        'GetObjectTagging Failed with response: $body',
        code: response.statusCode,
        uri: encodedUri,
      );
    }

    final xml = XmlDocument.parse(body);

    return {
      for (final tag in xml.findAllElements('Tag'))
        tag.getElement('Key')!.innerText: tag.getElement('Value')!.innerText,
    };
  }

  Future<void> setTags(String key, Map<String, String> tags) async {
    final builder = XmlBuilder();

    builder.processing('xml', 'version="1.0" encoding="UTF-8"');

    builder.element(
      'Tagging',
      nest: () {
        builder.element(
          'TagSet',
          nest: () {
            for (final entry in tags.entries) {
              builder.element(
                'Tag',
                nest: () {
                  builder.element('Key', nest: entry.key);
                  builder.element('Value', nest: entry.value);
                },
              );
            }
          },
        );
      },
    );

    final xmlBody = builder.buildDocument().toXmlString();
    final xmlBytes = utf8.encode(xmlBody);
    final contentMD5 = base64.encode(md5.convert(xmlBytes).bytes);
    final contentHash = sha256.convert(xmlBytes).toString();

    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);

    final encodedUri = getEncodedUri(
      key: key,
      queryParameters: {'tagging': ''},
    );

    final headers = buildSignedHeaders(
      encodedUri: encodedUri,
      method: 'PUT',
      amzDate: amzDate,
      shortDate: shortDate,
      contentHash: contentHash,
      contentMD5: contentMD5,
      contentType: 'application/xml; charset=utf-8',
    );

    final request = http.Request('PUT', encodedUri)
      ..headers.addAll(headers)
      ..body = xmlBody;

    final response = await _client
        .send(request)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Request timed out'),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw S3Exception(
        'PutObjectTagging Failed with response: $body',
        code: response.statusCode,
        uri: encodedUri,
      );
    }
  }

  String getUrl(String key, {int? validForSeconds}) {
    final now = DateTime.now().toUtc();
    final amzDate = formatAmzDate(now);
    final shortDate = formatDate(now);
    final credentialScope = '$shortDate/$_region/s3/aws4_request';

    final queryParams = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '$_accessKey/$credentialScope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': (validForSeconds ?? 604800).toString(),
      'X-Amz-SignedHeaders': 'host',
      'X-Amz-Content-Sha256': 'UNSIGNED-PAYLOAD',
    };

    final encodedUri = getEncodedUri(key: key, queryParameters: queryParams);

    final canonicalRequest = [
      'GET',
      encodedUri.path,
      encodedUri.query,
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

    return encodedUri
        .replace(query: '${encodedUri.query}&X-Amz-Signature=$signature')
        .toString();
  }

  Map<String, String> buildSignedHeaders({
    required Uri encodedUri,
    required String method,
    required String amzDate,
    required String shortDate,
    required String contentHash,
    String? contentMD5,
    String? contentType,
    String? copySource,
    Map<String, String?>? metadata,
  }) {
    final service = 's3';
    final host = _host;
    final credentialScope = '$shortDate/$_region/$service/aws4_request';

    // 1. Build the unsorted headers map
    final headers = <String, String>{
      'Host': host,
      'x-amz-content-sha256': contentHash,
      'x-amz-date': amzDate,
      'x-amz-copy-source': ?copySource,
      'Content-MD5': ?contentMD5,
      'Content-Type': ?contentType,
      ...?metadata?.map((k, v) => MapEntry('x-amz-meta-$k', v ?? '')),
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

    // 5. Assemble canonical request
    final canonicalRequest = [
      method,
      encodedUri.path,
      encodedUri.query,
      canonicalHeaders,
      signedHeadersString,
      contentHash,
    ].join('\n');

    // 6. Hash the canonical request
    final hashedCanonical = sha256
        .convert(utf8.encode(canonicalRequest))
        .toString();

    // 7. Build string to sign
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      hashedCanonical,
    ].join('\n');

    // 8. Derive signing key
    final signingKey = getSigningKey(_secretKey, shortDate, _region, service);

    // 9. Compute signature
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    // 10. Build Authorization header
    final authorization = [
      'AWS4-HMAC-SHA256 Credential=$_accessKey/$credentialScope',
      'SignedHeaders=$signedHeadersString',
      'Signature=$signature',
    ].join(', ');

    // 11. Return all headers including Authorization
    return {...headers, 'Authorization': authorization};
  }

  static List<int> _sign(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  (List<int>, String, String, String, String)? _signingKey;

  List<int> getSigningKey(
    String secret,
    String date,
    String region,
    String service,
  ) {
    if (_signingKey != null &&
        _signingKey!.$2 == secret &&
        _signingKey!.$3 == date &&
        _signingKey!.$4 == region &&
        _signingKey!.$5 == service) {
      return _signingKey!.$1;
    }

    final kDate = _sign(utf8.encode('AWS4$secret'), date);
    final kRegion = _sign(kDate, region);
    final kService = _sign(kRegion, service);

    _signingKey = (
      _sign(kService, 'aws4_request'),
      secret,
      date,
      region,
      service,
    );

    return _signingKey!.$1;
  }

  static String formatAmzDate(DateTime time) =>
      '${time.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

  static String formatDate(DateTime time) =>
      time.toIso8601String().split('T').first.replaceAll('-', '');

  Uri getEncodedUri({
    String? key,
    Map<String, String> queryParameters = const {},
  }) {
    final queryEntries = queryParameters.entries.map((e) {
      return MapEntry(awsEncode(e.key), awsEncode(e.value));
    }).toList();
    queryEntries.sort((a, b) {
      final c = a.key.compareTo(b.key);
      return c != 0 ? c : a.value.compareTo(b.value);
    });
    return Uri(
      scheme: 'https',
      host: _host,
      path: key == null
          ? '/'
          : '/${p.s3.join(_prefix, p.s3.relative(key, from: _profile.name)).split('/').map(awsEncode).join('/')}',
      query: queryEntries.map((e) => '${e.key}=${e.value}').join('&'),
    );
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

  void dispose() {
    _client.close();
  }
}
