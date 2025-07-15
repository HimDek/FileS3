import 'dart:typed_data';
import 'package:aws_s3_api/s3-2006-03-01.dart';
import 'package:http/http.dart' as http;
import 'models/remote_file.dart';
import 'config_manager.dart';

class S3FileManager {
  late final S3 _s3;
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
      endpointUrl: cfg.host ?? 'https://s3.${cfg.region}.amazonaws.com',
    );
    _bucket = cfg.bucket;
    _prefix = cfg.prefix[cfg.prefix.length - 1] != '/'
        ? '${cfg.prefix}/'
        : cfg.prefix;
  }

  static Future<S3FileManager> create(context, http.Client client) async {
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

  Future<void> createDirectory(String dir) async {
    final key = '$_prefix$dir/';
    await _s3.putObject(
      bucket: _bucket,
      key: key,
      body: Uint8List(0),
      contentType: 'application/x-directory',
    );
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

  Future<void> renameFile(String oldKey, String newKey) async {
    await _s3.copyObject(
      bucket: _bucket,
      copySource: '$_bucket/$_prefix$oldKey',
      key: '$_prefix$newKey',
    );
    await deleteFile(oldKey);
  }

  Future<void> deleteFile(String key) async {
    await _s3.deleteObject(bucket: _bucket, key: '$_prefix$key');
  }
}
