import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class S3Config {
  final String accessKey;
  final String secretKey;
  final String region;
  final String bucket;
  final String prefix;
  final String? host;

  S3Config({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.bucket,
    this.prefix = '',
    this.host,
  });
}

class ConfigManager {
  static const _storage = FlutterSecureStorage();

  static Future<S3Config> loadS3Config(BuildContext context) async {
    final accessKey = await _storage.read(key: 'aws_access_key');
    final secretKey = await _storage.read(key: 'aws_secret_key');
    final region = await _storage.read(key: 'aws_region');
    final bucket = await _storage.read(key: 's3_bucket');
    final prefix = await _storage.read(key: 's3_prefix');
    final host = await _storage.read(key: 's3_host');

    if (accessKey == null ||
        secretKey == null ||
        region == null ||
        bucket == null) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => S3ConfigPage()));
      return loadS3Config(context);
    }

    return S3Config(
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      bucket: bucket,
      prefix: prefix ?? '',
      host: host,
    );
  }

  static Future<void> saveS3Config(S3Config config) async {
    await _storage.write(key: 'aws_access_key', value: config.accessKey);
    await _storage.write(key: 'aws_secret_key', value: config.secretKey);
    await _storage.write(key: 'aws_region', value: config.region);
    await _storage.write(key: 's3_bucket', value: config.bucket);
    await _storage.write(key: 's3_prefix', value: config.prefix);
    if (config.host != null) {
      await _storage.write(key: 's3_host', value: config.host);
    }
  }
}

class S3ConfigPage extends StatefulWidget {
  const S3ConfigPage({super.key});

  @override
  S3ConfigPageState createState() => S3ConfigPageState();
}

class S3ConfigPageState extends State<S3ConfigPage> {
  String _accessKey = '';
  String _secretKey = '';
  String _region = '';
  String _bucket = '';
  String _prefix = '';
  String? _host;

  void _readConfig(context) async {
    try {
      final config = await ConfigManager.loadS3Config(context);
      setState(() {
        _accessKey = config.accessKey;
        _secretKey = config.secretKey;
        _region = config.region;
        _bucket = config.bucket;
        _prefix = config.prefix;
        _host = config.host;
      });
    } catch (e) {
      // Handle error, e.g., show a dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading configuration: $e')),
      );
    }
  }

  void _saveConfig(context) async {
    final config = S3Config(
      accessKey: _accessKey,
      secretKey: _secretKey,
      region: _region,
      bucket: _bucket,
      prefix: _prefix,
      host: _host?.isEmpty ?? true ? null : _host,
    );

    try {
      await ConfigManager.saveS3Config(config);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Configuration saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving configuration: $e')));
    }
  }

  @override
  void setState(fn) {
    super.setState(() {
      _readConfig(context);
      fn();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AWS S3 Config')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            decoration: InputDecoration(labelText: 'Access Key'),
            onChanged: (value) => _accessKey = value,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Secret Key'),
            obscureText: true,
            onChanged: (value) => _secretKey = value,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Region'),
            onChanged: (value) => _region = value,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Bucket Name'),
            onChanged: (value) => _bucket = value,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Prefix (optional)'),
            onChanged: (value) => _prefix = value.isEmpty ? '' : value,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Host (optional)'),
            onChanged: (value) => _host = value.isEmpty ? null : value,
          ),
          ElevatedButton(
            onPressed: () => _saveConfig(context),
            child: Text('Save Configuration'),
          ),
        ],
      ),
    );
  }
}
