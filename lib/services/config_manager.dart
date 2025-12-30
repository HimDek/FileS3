import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:files3/services/models/remote_file.dart';
import 'package:files3/services/ini_manager.dart';
import 'package:files3/services/job.dart';
import 'package:files3/main.dart';
import 'package:flutter/services.dart';
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
  bool _loading = true;
  bool _obscureSecret = true;
  S3Config? _s3Config;
  final FocusNode _accessFocusNode = FocusNode();
  final FocusNode _secretFocusNode = FocusNode();
  final FocusNode _regionFocusNode = FocusNode();
  final FocusNode _bucketFocusNode = FocusNode();
  final FocusNode _prefixFocusNode = FocusNode();
  final FocusNode _hostFocusNode = FocusNode();
  final TextEditingController _accessKeyController = TextEditingController();
  final TextEditingController _secretKeyController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _bucketController = TextEditingController();
  final TextEditingController _prefixController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();

  Future<void> _readConfig() async {
    setState(() {
      _loading = true;
    });
    _s3Config = await ConfigManager.loadS3Config();
    setState(() {
      _accessKeyController.text = _s3Config!.accessKey;
      _secretKeyController.text = _s3Config!.secretKey;
      _regionController.text = _s3Config!.region;
      _bucketController.text = _s3Config!.bucket;
      _prefixController.text = _s3Config!.prefix;
      _hostController.text = _s3Config!.host;
      _loading = false;
    });
  }

  Future<void> _saveConfig() async {
    setState(() {
      _loading = true;
    });
    await ConfigManager.saveS3Config(
      S3Config(
        accessKey: _accessKeyController.text,
        secretKey: _secretKeyController.text,
        region: _regionController.text,
        bucket: _bucketController.text,
        prefix: _prefixController.text,
        host: _hostController.text,
      ),
    );
    await _readConfig();
  }

  Future<void> _setConfig() async {
    await Main.setConfig();
    await Main.listDirectories();
  }

  @override
  void initState() {
    super.initState();
    _readConfig();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          !_loading &&
          _s3Config?.accessKey.isNotEmpty == true &&
          _s3Config?.secretKey.isNotEmpty == true &&
          _s3Config?.region.isNotEmpty == true &&
          _s3Config?.bucket.isNotEmpty == true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          await _setConfig();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('AWS S3 Config'),
          actions: [
            IconButton(
              onPressed:
                  _loading ||
                      _accessKeyController.text.isEmpty ||
                      _secretKeyController.text.isEmpty ||
                      _regionController.text.isEmpty ||
                      _bucketController.text.isEmpty
                  ? null
                  : _saveConfig,
              icon: Icon(Icons.save),
              tooltip: 'Save Configuration',
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
              focusNode: _accessFocusNode,
              controller: _accessKeyController,
              onChanged: (value) {
                setState(() {});
              },
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
              focusNode: _secretFocusNode,
              controller: _secretKeyController,
              obscureText: _obscureSecret,
              onChanged: (value) {
                setState(() {});
              },
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
              focusNode: _regionFocusNode,
              controller: _regionController,
              onChanged: (value) {
                setState(() {});
              },
              enabled: !_loading,
            ),
            SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.storage),
                labelText: 'Bucket Name',
                helperText:
                    'Name of the S3 bucket to use. The bucket must exist',
              ),
              focusNode: _bucketFocusNode,
              controller: _bucketController,
              onChanged: (value) {
                setState(() {});
              },
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
              focusNode: _prefixFocusNode,
              controller: _prefixController,
              onChanged: (value) {
                setState(() {});
              },
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
              focusNode: _hostFocusNode,
              controller: _hostController,
              onChanged: (value) {
                setState(() {});
              },
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
                    'Make sure the provided AWS credentials have the following permissions:',
                  ),
                  Text('s3:ListBucket on arn:aws:s3:::*'),
                  Text(
                    's3:GetObject, s3:PutObject, s3:DeleteObject on arn:aws:s3:::${_bucketController.text}/${_prefixController.text}*',
                  ),
                ],
              ),
            ),
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                'Minimum IAM Permissions Policy for the app to function properly:',
              ),
              subtitle: Text(
                '\n{\n    "Version": "2012-10-17",\n    "Statement": [\n        {\n            "Effect": "Allow",\n            "Action": [\n                "s3:ListBucket",\n                "s3:GetObject",\n                "s3:PutObject",\n                "s3:DeleteObject"\n            ],\n            "Resource": "arn:aws:s3:::files3-dev/*"\n        },\n        {\n            "Effect": "Allow",\n            "Action": [\n                "s3:ListBucket"\n            ],\n            "Resource": "arn:aws:s3:::*"\n        }\n    ]\n}',
              ),
              onTap: () {
                Clipboard.setData(
                  ClipboardData(
                    text:
                        '{\n    "Version": "2012-10-17",\n    "Statement": [\n        {\n            "Effect": "Allow",\n            "Action": [\n                "s3:ListBucket",\n                "s3:GetObject",\n                "s3:PutObject",\n                "s3:DeleteObject"\n            ],\n            "Resource": "arn:aws:s3:::files3-dev/*"\n        },\n        {\n            "Effect": "Allow",\n            "Action": [\n                "s3:ListBucket"\n            ],\n            "Resource": "arn:aws:s3:::*"\n        }\n    ]\n}',
                  ),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Policy copied to clipboard')),
                );
              },
            ),
          ],
        ),
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
