import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:files3/services/models/remote_file.dart';
import 'package:files3/services/ini_manager.dart';
import 'package:files3/services/job.dart';
import 'package:files3/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final themeController = ThemeController();
final ultraDarkController = UltraDarkController();

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

class UiConfig {
  final ThemeMode colorMode;
  final bool ultraDark;

  UiConfig({required this.colorMode, required this.ultraDark});
}

class ConfigManager {
  static const _storage = FlutterSecureStorage();

  static Future<S3Config> loadS3Config() async {
    final accessKey = await _storage.read(key: 'aws_access_key') ?? '';
    final secretKey = await _storage.read(key: 'aws_secret_key') ?? '';

    final region = IniManager.config?.get("aws", "region") ?? '';
    final bucket = IniManager.config?.get("s3", "bucket") ?? '';
    final prefix = IniManager.config?.get("s3", "prefix") ?? '';
    final host = IniManager.config?.get("s3", "host") ?? '';

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
    if (!IniManager.config!.sections().contains("aws")) {
      IniManager.config!.addSection("aws");
    }
    IniManager.config!.set("aws", "region", config.region);
    if (!IniManager.config!.sections().contains("s3")) {
      IniManager.config!.addSection("s3");
    }
    IniManager.config!.set("s3", "bucket", config.bucket);
    IniManager.config!.set("s3", "prefix", config.prefix);
    IniManager.config!.set("s3", "host", config.host);
    IniManager.save();
  }

  static UiConfig loadUiConfig() {
    final colorModeStr = IniManager.config?.get("ui", "color_mode") ?? 'system';
    final ultraDarkStr = IniManager.config?.get("ui", "ultra_dark") ?? 'false';

    final colorMode = switch (colorModeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final ultraDark = ultraDarkStr.toLowerCase() == 'true';

    return UiConfig(colorMode: colorMode, ultraDark: ultraDark);
  }

  static Future<void> saveUiConfig(UiConfig config) async {
    final colorModeStr = switch (config.colorMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    if (!IniManager.config!.sections().contains("ui")) {
      IniManager.config!.addSection("ui");
    }
    IniManager.config!.set("ui", "color_mode", colorModeStr);
    IniManager.config!.set("ui", "ultra_dark", config.ultraDark.toString());
    IniManager.save();
  }

  static Future<void> saveRemoteFiles(List<RemoteFile> files) async {
    final String jsonString = jsonEncode(
      files.map((file) => file.toJson()).toList(),
    );
    await _storage.write(key: 'remote_files', value: jsonString);
  }

  static Future<List<RemoteFile>> loadRemoteFiles() async {
    final jsonString = await _storage.read(key: 'remote_files') ?? '[]';
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList
        .map((json) => RemoteFile.fromJson(json as Map<String, dynamic>))
        .toList();
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
  bool _obscureSecret = true;

  Future<void> _readConfig() async {
    setState(() {
      _loading = true;
    });
    final config = await ConfigManager.loadS3Config();
    setState(() {
      _accessKey = config.accessKey;
      _secretKey = config.secretKey;
      _region = config.region;
      _bucket = config.bucket;
      _prefix = config.prefix;
      _host = config.host;
      _loading = false;
    });
  }

  Future<void> _saveConfig(BuildContext context) async {
    setState(() {
      _loading = true;
    });
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
    await _readConfig();
    await Main.setConfig();
    await Main.listDirectories();
    setState(() {
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _readConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AWS S3 Config'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _saveConfig(context),
            icon: _loading
                ? CircularProgressIndicator(padding: EdgeInsets.all(12))
                : Icon(Icons.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.vpn_key),
              labelText: 'Access Key',
              hintText: 'Your AWS access key ID',
            ),
            controller: TextEditingController(text: _accessKey),
            onChanged: (value) => _accessKey = value,
            enabled: !_loading,
          ),
          SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.lock),
              labelText: 'Secret Key',
              hintText: 'Your AWS secret access key',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureSecret ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: _loading
                    ? null
                    : () {
                        setState(() {
                          _obscureSecret = !_obscureSecret;
                        });
                      },
              ),
            ),
            controller: TextEditingController(text: _secretKey),
            obscureText: _obscureSecret,
            onChanged: (value) => _secretKey = value,
            enabled: !_loading,
          ),
          SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.public),
              labelText: 'Region',
              hintText: 'e.g. us-east-1',
              helperText: 'AWS region where your S3 bucket is located',
            ),
            controller: TextEditingController(text: _region),
            onChanged: (value) => _region = value,
            enabled: !_loading,
          ),
          SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.storage),
              labelText: 'Bucket Name',
              helperText: 'Name of the S3 bucket to use. The bucket must exist',
            ),
            controller: TextEditingController(text: _bucket),
            onChanged: (value) => _bucket = value,
            enabled: !_loading,
          ),
          SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.folder),
              labelText: 'Prefix (optional)',
              hintText: 'e.g. myfolder/',
              helperText:
                  'Folder prefix within the bucket will be used as root',
            ),
            controller: TextEditingController(text: _prefix),
            onChanged: (value) => _prefix = value.isEmpty ? '' : value,
            enabled: !_loading,
          ),
          SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.link),
              labelText: 'Host (optional)',
              hintText: 'e.g. https://s3.custom-endpoint.com',
              helperText: 'Custom S3-compatible endpoint (if any)',
            ),
            controller: TextEditingController(text: _host),
            onChanged: (value) => _host = value,
            enabled: !_loading,
          ),
          SizedBox(height: 16),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text('Note:'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make sure the provided AWS credentials have s3:ListBucket, s3:GetObject, s3:PutObject, s3:DeleteObject permissions on the specified S3 bucket and prefix.',
                ),
              ],
            ),
          ),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(
              '["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]',
            ),
            subtitle: Text(
              'Minimum required S3 permissions for the app to function properly.',
            ),
          ),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text('arn:aws:s3:::${_bucket}/${_prefix}*'),
            subtitle: Text('Resource ARN for the specified bucket and prefix.'),
          ),
        ],
      ),
    );
  }
}

class UiSettingsPage extends StatefulWidget {
  const UiSettingsPage({super.key});

  @override
  State<UiSettingsPage> createState() => UiSettingsPageState();
}

class UiSettingsPageState extends State<UiSettingsPage> {
  late UiConfig _uiConfig;

  @override
  void initState() {
    super.initState();
    _uiConfig = ConfigManager.loadUiConfig();
  }

  Future<void> _saveConfig() async {
    await ConfigManager.saveUiConfig(_uiConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Appearance Settings')),
      body: ListView(
        children: [
          ListTile(
            title: Text('Color Mode'),
            subtitle: Text('Select the app color mode'),
          ),
          RadioGroup<ThemeMode>(
            groupValue: _uiConfig.colorMode,
            onChanged: (ThemeMode? value) async {
              if (value != null) {
                setState(() {
                  _uiConfig = UiConfig(
                    colorMode: value,
                    ultraDark: _uiConfig.ultraDark,
                  );
                });
                await _saveConfig();
                themeController.update(value);
              }
            },
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('System Default'),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Light Mode'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Dark Mode'),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
          if (_uiConfig.colorMode != ThemeMode.light)
            SwitchListTile(
              title: Text('Ultra Dark Mode'),
              subtitle: Text('Pure black background for dark mode'),
              value: _uiConfig.ultraDark,
              onChanged: (value) async {
                setState(() {
                  _uiConfig = UiConfig(
                    colorMode: _uiConfig.colorMode,
                    ultraDark: value,
                  );
                });
                await _saveConfig();
                ultraDarkController.update(value);
              },
            ),
        ],
      ),
    );
  }
}
