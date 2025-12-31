import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.cloud),
            title: Text("AWS S3 Configuration"),
            subtitle: Text(
              "Configure AWS S3 access key, secret key, region, bucket, host etc.",
            ),
            onTap: () async => await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => S3ConfigPage())),
          ),
          ListTile(
            leading: Icon(Icons.palette),
            title: Text("Appearance"),
            subtitle: Text(
              "Configure UI settings like theme, colors, font size etc.",
            ),
            onTap: () async => await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => UiSettingsPage())),
          ),
        ],
      ),
    );
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
  String? _permissionPolicy;
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
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(() {
        fn();
        _permissionPolicy = _bucketController.text.isNotEmpty
            ? _prefixController.text.isNotEmpty
                  ? '{\n    "Version": "2012-10-17",\n    "Statement": [\n        {\n            "Effect": "Allow",\n            "Action": [\n                "s3:GetObject",\n                "s3:PutObject",\n                "s3:DeleteObject"\n            ],\n            "Resource": "arn:aws:s3:::${_bucketController.text}/${_prefixController.text}*"\n        },\n        {\n            "Effect": "Allow",\n            "Action": [\n                "s3:ListBucket"\n            ],\n            "Resource": "arn:aws:s3:::${_bucketController.text}"\n        }\n    ]\n}'
                  : '{\n    "Version": "2012-10-17",\n    "Statement": [\n        {\n            "Effect": "Allow",\n            "Action": [\n                "s3:ListBucket",\n                "s3:GetObject",\n                "s3:PutObject",\n                "s3:DeleteObject"\n            ],\n            "Resource": "arn:aws:s3:::${_bucketController.text}*"\n        }\n    ]\n}'
            : null;
      });
    }
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
              keyboardType: TextInputType.visiblePassword,
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
              keyboardType: TextInputType.visiblePassword,
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
                hintText: _regionController.text.isNotEmpty
                    ? 's3.${_regionController.text}.amazonaws.com'
                    : 'Default for AWS S3: s3.{region-name}.amazonaws.com',
                helperText: 'Custom S3-compatible domain name',
              ),
              focusNode: _hostFocusNode,
              controller: _hostController,
              keyboardType: TextInputType.url,
              onChanged: (value) {
                setState(() {});
              },
              enabled: !_loading,
            ),
            SizedBox(height: 16),
            if (_bucketController.text.isNotEmpty)
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
                    if (_prefixController.text.isNotEmpty) ...[
                      SizedBox(height: 8),
                      Text('s3:ListBucket'),
                      Text('on arn:aws:s3:::${_bucketController.text}'),
                      SizedBox(height: 8),
                      Text('s3:GetObject, s3:PutObject, s3:DeleteObject'),
                      Text(
                        'on arn:aws:s3:::${_bucketController.text}/${_prefixController.text}*',
                      ),
                    ] else ...[
                      SizedBox(height: 8),
                      Text(
                        's3:ListBucket, s3:GetObject, s3:PutObject, s3:DeleteObject',
                      ),
                      Text('on arn:aws:s3:::${_bucketController.text}*'),
                    ],
                  ],
                ),
              ),
            if (_permissionPolicy != null)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  'Minimum IAM Permissions Policy for the app to function properly:',
                ),
                subtitle: Text('\n$_permissionPolicy'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _permissionPolicy!));
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
