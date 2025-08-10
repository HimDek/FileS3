import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:s3_drive/services/ini_manager.dart';

class S3Config {
  final String accessKey;
  final String secretKey;
  final String region;
  final String bucket;
  final String prefix;
  final String host;

  S3Config({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.bucket,
    this.prefix = '',
    this.host = '',
  });
}

class ConfigManager {
  static const _storage = FlutterSecureStorage();

  static Future<S3Config> loadS3Config(
    BuildContext context, {
    bool push = true,
  }) async {
    final accessKey = await _storage.read(key: 'aws_access_key') ?? '';
    final secretKey = await _storage.read(key: 'aws_secret_key') ?? '';

    final region = IniManager.config.get("aws", "region") ?? '';
    final bucket = IniManager.config.get("s3", "bucket") ?? '';
    final prefix = IniManager.config.get("s3", "prefix") ?? '';
    final host = IniManager.config.get("s3", "host") ?? '';

    if ((accessKey.isEmpty ||
            secretKey.isEmpty ||
            region.isEmpty ||
            bucket.isEmpty) &&
        push) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => S3ConfigPage()));
      return await loadS3Config(context);
    }

    return S3Config(
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      bucket: bucket,
      prefix: prefix,
      host: host,
    );
  }

  static Future<void> saveS3Config(S3Config config) async {
    await _storage.write(key: 'aws_access_key', value: config.accessKey);
    await _storage.write(key: 'aws_secret_key', value: config.secretKey);
    IniManager.config.set("aws", "region", config.region);
    IniManager.config.set("s3", "bucket", config.bucket);
    IniManager.config.set("s3", "prefix", config.prefix);
    IniManager.config.set("s3", "host", config.host);
    IniManager.save();
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
  String _host = '';
  bool _loading = true;

  Future<void> _readConfig(BuildContext context) async {
    setState(() {
      _loading = true;
    });
    try {
      final config = await ConfigManager.loadS3Config(context, push: false);
      setState(() {
        _accessKey = config.accessKey;
        _secretKey = config.secretKey;
        _region = config.region;
        _bucket = config.bucket;
        _prefix = config.prefix;
        _host = config.host;
        _loading = false;
      });
    } catch (e) {
      // Handle error, e.g., show a dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading configuration: $e')),
      );
    }
  }

  Future<void> _saveConfig(BuildContext context) async {
    setState(() {
      _loading = true;
    });
    try {
      await ConfigManager.saveS3Config(
        S3Config(
          accessKey: _accessKey,
          secretKey: _secretKey,
          region: _region,
          bucket: _bucket,
          prefix: _prefix,
          host: _host,
        ),
      );
      await _readConfig(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Configuration saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving configuration: $e')));
    }
    setState(() {
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _readConfig(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AWS S3 Config'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _saveConfig(context),
            icon: _loading ? CircularProgressIndicator() : Icon(Icons.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            decoration: InputDecoration(labelText: 'Access Key'),
            controller: TextEditingController(text: _accessKey),
            onChanged: (value) => _accessKey = value,
            enabled: !_loading,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Secret Key'),
            controller: TextEditingController(text: _secretKey),
            obscureText: true,
            onChanged: (value) => _secretKey = value,
            enabled: !_loading,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Region'),
            controller: TextEditingController(text: _region),
            onChanged: (value) => _region = value,
            enabled: !_loading,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Bucket Name'),
            controller: TextEditingController(text: _bucket),
            onChanged: (value) => _bucket = value,
            enabled: !_loading,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Prefix (optional)'),
            controller: TextEditingController(text: _prefix),
            onChanged: (value) => _prefix = value.isEmpty ? '' : value,
            enabled: !_loading,
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Host (optional)'),
            controller: TextEditingController(text: _host),
            onChanged: (value) => _host = value,
            enabled: !_loading,
          ),
        ],
      ),
    );
  }
}
