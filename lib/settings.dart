import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
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
            leading: Icon(Icons.palette),
            title: Text("Appearance"),
            subtitle: Text(
              "Configure UI settings like theme, colors, font size etc.",
            ),
            onTap: () async => await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => UiSettingsPage())),
          ),
          ListTile(
            leading: Icon(Icons.download),
            title: Text("Transfer"),
            subtitle: Text("Configure downloads and uploads settings"),
            onTap: () async => await Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => TransferSettingsPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class S3ConfigPage extends StatefulWidget {
  final Profile? profile;

  const S3ConfigPage({super.key, this.profile});

  @override
  S3ConfigPageState createState() => S3ConfigPageState();
}

class S3ConfigPageState extends State<S3ConfigPage> {
  bool _loading = true;
  bool _obscureSecret = true;
  bool _includeKeys = false;
  bool _includeBackupConfig = false;
  S3Config? _s3Config;
  String? _permissionPolicy;
  Profile? _profile;
  final Map<String, dynamic> _exportData = {};
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _profileFocusNode = FocusNode();
  final FocusNode _accessFocusNode = FocusNode();
  final FocusNode _secretFocusNode = FocusNode();
  final FocusNode _regionFocusNode = FocusNode();
  final FocusNode _bucketFocusNode = FocusNode();
  final FocusNode _prefixFocusNode = FocusNode();
  final FocusNode _hostFocusNode = FocusNode();
  final TextEditingController _profileNameController = TextEditingController();
  final TextEditingController _accessKeyController = TextEditingController();
  final TextEditingController _secretKeyController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _bucketController = TextEditingController();
  final TextEditingController _prefixController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  String? _localDir;
  BackupMode _backupMode = BackupMode.sync;

  bool get _profileNameExists =>
      Main.profiles.any((p) => p.name == _profileNameController.text);

  Future<void> _readConfig() async {
    setState(() {
      _loading = true;
    });
    try {
      _profile = widget.profile;
      _profile ??= Main.profiles.firstWhere(
        (p) => p.name == _profileNameController.text,
      );
    } catch (e) {
      _profile = null;
    }
    _profileNameController.text = _profile?.name ?? _profileNameController.text;
    _s3Config =
        (await ConfigManager.loadS3Config())[_profileNameController.text];
    setState(() {
      _accessKeyController.text = _s3Config?.accessKey ?? '';
      _secretKeyController.text = _s3Config?.secretKey ?? '';
      _regionController.text = _s3Config?.region ?? '';
      _bucketController.text = _s3Config?.bucket ?? '';
      _prefixController.text = _s3Config?.prefix ?? '';
      _hostController.text = _s3Config?.host ?? '';
      _localDir = _profile == null
          ? null
          : Main.pathFromKey('${_profile!.name}/');
      _backupMode = _profile == null
          ? BackupMode.sync
          : Main.backupModeFromKey('${_profile!.name}/');
      _loading = false;
    });
  }

  Future<void> Function()? _saveConfig() => _loading
      ? null
      : () async {
          if (!_formKey.currentState!.validate()) return;
          setState(() {
            _loading = true;
          });
          if (_profileNameController.text.isEmpty) return;
          await ConfigManager.saveS3Config(
            _profileNameController.text,
            S3Config(
              accessKey: _accessKeyController.text,
              secretKey: _secretKeyController.text,
              region: _regionController.text,
              bucket: _bucketController.text,
              prefix: _prefixController.text,
              host: _hostController.text,
            ),
          );
          ConfigManager.setBackupMode(
            '${_profileNameController.text}/',
            _backupMode,
          );
          ConfigManager.setLocalDir(
            '${_profileNameController.text}/',
            _localDir,
          );
          showSnackBar(SnackBar(content: Text('Configuration saved')));
          await Main.refreshProfiles();
          await _readConfig();
        };

  Future<void> _setConfig() async {
    if (_profile == null) return;
    _profile!.cfg = S3Config(
      accessKey: _accessKeyController.text,
      secretKey: _secretKeyController.text,
      region: _regionController.text,
      bucket: _bucketController.text,
      prefix: _prefixController.text,
      host: _hostController.text,
    );
    await _profile!.listDirectories();
  }

  @override
  void initState() {
    super.initState();
    _readConfig();
  }

  @override
  void dispose() {
    _formKey.currentState?.dispose();
    _profileFocusNode.dispose();
    _accessFocusNode.dispose();
    _secretFocusNode.dispose();
    _regionFocusNode.dispose();
    _bucketFocusNode.dispose();
    _prefixFocusNode.dispose();
    _hostFocusNode.dispose();
    _profileNameController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _regionController.dispose();
    _bucketController.dispose();
    _prefixController.dispose();
    _hostController.dispose();
    super.dispose();
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
        if (_profile != null) {
          _exportData.clear();
          _exportData['profile'] = _profile!.name;
          if (_includeKeys) {
            _exportData['accessKey'] = _profile!.cfg.accessKey;
            _exportData['secretKey'] = _profile!.cfg.secretKey;
          }
          _exportData['region'] = _profile!.cfg.region;
          _exportData['bucket'] = _profile!.cfg.bucket;
          _exportData['prefix'] = _profile!.cfg.prefix;
          _exportData['host'] = _profile!.cfg.host;
          if (_includeBackupConfig) {
            _exportData['backupMode'] = Main.backupModeFromKey(
              '${_profile!.name}/',
            ).value;
            _exportData['localDir'] = Main.pathFromKey('${_profile!.name}/');
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          _profile == null ||
          !_loading &&
              _s3Config?.accessKey.isNotEmpty == true &&
              _s3Config?.secretKey.isNotEmpty == true &&
              _s3Config?.region.isNotEmpty == true &&
              _s3Config?.bucket.isNotEmpty == true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop && !_loading && _profile != null && result != 1) {
          await _setConfig();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${_profileNameController.text.isEmpty ? "New " : ""}S3 Profile Config',
          ),
          actions: [
            IconButton(
              onPressed: _saveConfig(),
              icon: Icon(Icons.save),
              tooltip: 'Save Configuration',
            ),
          ],
        ),
        body: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    TextFormField(
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.cloud_circle),
                        labelText: 'Profile Name',
                        hintText: 'A unique name for this S3 configuration',
                        helperText:
                            'Used to identify this configuration in the app. Can\'t be changed later.',
                      ),
                      focusNode: _profileFocusNode,
                      controller: _profileNameController,
                      keyboardType: TextInputType.text,
                      onChanged: (value) {
                        setState(() {});
                      },
                      enabled: !_loading && _profile == null,
                      autofillHints: const [
                        'profile',
                        's3 profile',
                        's3_profile',
                      ],
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Profile name is required';
                        }
                        if (_profile == null && _profileNameExists) {
                          return 'Profile name already exists';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    TextFormField(
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
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Access key is required';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.lock),
                        labelText: 'Secret Key',
                        hintText: 'Your AWS secret access key',
                        suffixIcon: _secretKeyController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  _obscureSecret
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: _loading
                                    ? null
                                    : () {
                                        setState(() {
                                          _obscureSecret = !_obscureSecret;
                                        });
                                      },
                              )
                            : null,
                      ),
                      focusNode: _secretFocusNode,
                      controller: _secretKeyController,
                      keyboardType: TextInputType.visiblePassword,
                      obscureText: _obscureSecret,
                      onChanged: (value) {
                        setState(() {});
                      },
                      enabled: !_loading,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Secret key is required';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    Autocomplete<String>(
                      focusNode: _regionFocusNode,
                      textEditingController: _regionController,
                      onSelected: (String selection) {
                        setState(() {});
                      },
                      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                        focusNode.addListener(() {
                          if (focusNode.hasFocus && controller.text.isEmpty) {
                            controller.value = controller.value.copyWith();
                          }
                        });
                        return TextFormField(
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.public),
                            labelText: 'Region',
                            hintText: 'e.g. us-east-1',
                            helperText:
                                'AWS region where your S3 bucket is located',
                            errorText:
                                controller.text.isNotEmpty &&
                                    !awsRegions.values.any(
                                      (regionMap) => regionMap.containsKey(
                                        controller.text,
                                      ),
                                    )
                                ? 'This seems to be a non-standard region. Make sure it\'s correct.'
                                : null,
                          ),
                          focusNode: focusNode,
                          controller: controller,
                          onChanged: (value) {
                            setState(() {});
                          },
                          enabled: !_loading,
                          autofillHints: const [
                            'region',
                            's3 region',
                            's3_region',
                            'aws region',
                            'aws_region',
                          ],
                          textInputAction: TextInputAction.next,
                          onEditingComplete: onSubmit,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Region is required';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) =>
                              _bucketFocusNode.requestFocus(),
                        );
                      },
                      optionsBuilder: (value) {
                        if (value.text.isEmpty) {
                          return awsRegions.keys
                              .map((key) => awsRegions[key]!.keys)
                              .expand((element) => element);
                        }
                        return awsRegions.keys
                            .map(
                              (key) =>
                                  key.toLowerCase().contains(
                                    value.text.toLowerCase(),
                                  )
                                  ? awsRegions[key]!.keys
                                  : awsRegions[key]!.keys.where(
                                      (region) =>
                                          region.toLowerCase().contains(
                                            value.text.toLowerCase(),
                                          ) ||
                                          awsRegions[key]![region]!
                                              .toLowerCase()
                                              .contains(
                                                value.text.toLowerCase(),
                                              ),
                                    ),
                            )
                            .expand((element) => element);
                      },
                      optionsViewBuilder: (context, onSelected, options) =>
                          Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 5.0,
                                  offset: Offset(1, 1),
                                ),
                              ],
                            ),
                            child: Material(
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.all(8.0),
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return ListTile(
                                    subtitle: Text(option),
                                    title: Text(
                                      '(${awsRegions.keys.firstWhere((key) => awsRegions[key]!.containsKey(option))}) ${awsRegions.values.firstWhere((regionMap) => regionMap.containsKey(option), orElse: () => {}).entries.firstWhere((entry) => entry.key == option, orElse: () => MapEntry('', '')).value}',
                                    ),
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    onTap: () => onSelected(option),
                                    selected: _regionController.text == option,
                                  );
                                },
                              ),
                            ),
                          ),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
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
                      autofillHints: const [
                        'bucket',
                        's3 bucket',
                        's3bucket',
                        'bucket name',
                        'bucketname',
                        's3 bucket name',
                        's3bucketname',
                        's3_bucket_name',
                        's3_bucket',
                        'bucket_name',
                      ],
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Bucket name is required';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.folder),
                        labelText: 'Prefix (optional)',
                        hintText: 'e.g. myfolder',
                        helperText:
                            'Folder prefix within the bucket will be used as root',
                      ),
                      focusNode: _prefixFocusNode,
                      controller: _prefixController,
                      onChanged: (value) {
                        setState(() {});
                      },
                      enabled: !_loading,
                      autofillHints: const ['prefix', 's3 prefix', 's3_prefix'],
                      textInputAction: TextInputAction.next,
                    ),
                    SizedBox(height: 8),
                    TextFormField(
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
                      autofillHints: const [
                        'host',
                        's3 host',
                        's3_host',
                        'endpoint',
                        's3 endpoint',
                        's3_endpoint',
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _saveConfig()?.call(),
                    ),
                    SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.drive_folder_upload_rounded),
                      title: const Text('Backup From'),
                      subtitle: Text(
                        _localDir == null ? 'Not set' : _localDir!,
                      ),
                      onTap: () async {
                        final String? directoryPath = await getDirectoryPath();
                        if (directoryPath != null) {
                          setState(() {
                            _localDir = directoryPath;
                          });
                        }
                      },
                      trailing: _localDir == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                setState(() {
                                  _localDir = null;
                                });
                              },
                            ),
                    ),
                    if ((_profile != null || _localDir != null) &&
                        p.isAbsolute(_localDir ?? _profile!.name)) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.sync_rounded),
                        title: const Text('Backup Mode'),
                      ),
                      RadioGroup(
                        groupValue: _backupMode,
                        onChanged: (s) {
                          setState(() {
                            _backupMode = s ?? BackupMode.sync;
                          });
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile(
                              value: BackupMode.upload,
                              title: Text(BackupMode.upload.name),
                              subtitle: Text(BackupMode.upload.description),
                              dense: true,
                            ),
                            RadioListTile(
                              value: BackupMode.sync,
                              title: Text(BackupMode.sync.name),
                              subtitle: Text(BackupMode.sync.description),
                              dense: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              if (_bucketController.text.isNotEmpty) ...[
                SizedBox(height: 32),
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
              ],
              if (_permissionPolicy != null) ...[
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    "Minimum IAM Permissions Policy for the app to function properly:",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _permissionPolicy!),
                          );
                          SharePlus.instance.share(
                            ShareParams(
                              title: 'S3 Permissions Policy',
                              text: _permissionPolicy!,
                              subject:
                                  'S3 Permissions Policy for FileS3 Profile "${_profileNameController.text}"',
                            ),
                          );
                        },
                        icon: Icon(Icons.share),
                      ),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _permissionPolicy!),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Policy copied to clipboard'),
                            ),
                          );
                        },
                        icon: Icon(Icons.copy),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  subtitle: SelectableText(_permissionPolicy ?? ''),
                ),
              ],
              if (_profile != null) ...[
                SizedBox(height: 32),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text('Export:'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: jsonEncode(_exportData)),
                          );
                          SharePlus.instance.share(
                            ShareParams(
                              title: 'S3 Profile Export',
                              text: jsonEncode(_exportData),
                              subject:
                                  'S3 Profile "${_profileNameController.text}" Export Data',
                              files: [
                                XFile.fromData(
                                  Uint8List.fromList(
                                    jsonEncode(_exportData).codeUnits,
                                  ),
                                  mimeType: 'application/json',
                                  name:
                                      'FileS3_Profile_${_profileNameController.text}_Export.json',
                                ),
                              ],
                            ),
                          );
                        },
                        icon: Icon(Icons.share),
                      ),
                      IconButton(
                        onPressed: () async {
                          Clipboard.setData(
                            ClipboardData(text: jsonEncode(_exportData)),
                          );
                          FileSaveLocation? saveLocation;
                          try {
                            saveLocation = await getSaveLocation(
                              suggestedName:
                                  'FileS3_Profile_${_profileNameController.text}_Export.json',
                              canCreateDirectories: true,
                            );
                          } catch (e) {
                            saveLocation = await saveAsDialog(
                              context,
                              suggestedName:
                                  'FileS3_Profile_${_profileNameController.text}_Export.json',
                            );
                          }
                          if (saveLocation != null) {
                            final file = XFile.fromData(
                              Uint8List.fromList(
                                jsonEncode(_exportData).codeUnits,
                              ),
                              mimeType: 'application/json',
                              name:
                                  'FileS3_Profile_${_profileNameController.text}_Export.json',
                            );
                            await file.saveTo(saveLocation.path);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Profile exported to ${saveLocation.path}',
                                ),
                              ),
                            );
                          }
                        },
                        icon: Icon(Icons.output),
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text('Include Keys'),
                  subtitle: Text(
                    'Caution: AWS keys will be exported. Keep it secure.',
                  ),
                  value: _includeKeys,
                  onChanged: (value) {
                    _includeKeys = value ?? false;
                    setState(() {});
                  },
                ),
                CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text('Include Backup Configuration'),
                  value: _includeBackupConfig,
                  onChanged: (value) {
                    _includeBackupConfig = value ?? false;
                    setState(() {});
                  },
                ),
              ] else ...[
                SizedBox(height: 32),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text('Import:'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () async {
                          final XFile? file = await openFile(
                            confirmButtonText: 'Import',
                            acceptedTypeGroups: [
                              XTypeGroup(
                                label: 'Files3 Profile',
                                extensions: ['files3profile', 'json', 'txt'],
                                mimeTypes: [
                                  'text/plain',
                                  'application/json',
                                  'application/octet-stream',
                                ],
                              ),
                            ],
                          );
                          if (file != null) {
                            try {
                              final content = await file.readAsString();
                              final data = jsonDecode(content);
                              _profileNameController.text =
                                  data['profile'] ??
                                  _profileNameController.text;
                              _accessKeyController.text =
                                  data['accessKey'] ??
                                  _accessKeyController.text;
                              _secretKeyController.text =
                                  data['secretKey'] ??
                                  _secretKeyController.text;
                              _regionController.text =
                                  data['region'] ?? _regionController.text;
                              _bucketController.text =
                                  data['bucket'] ?? _bucketController.text;
                              _prefixController.text =
                                  data['prefix'] ?? _prefixController.text;
                              _hostController.text =
                                  data['host'] ?? _hostController.text;
                              _localDir = data['localDir'] ?? _localDir;
                              _backupMode = BackupMode.fromValue(
                                data['backupMode'] ?? _backupMode.value,
                              );
                              setState(() {});
                            } catch (e) {
                              showSnackBar(
                                SnackBar(
                                  content: Text('Failed to import profile: $e'),
                                ),
                              );
                            }
                          }
                        },
                        icon: Icon(Icons.input),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.profile != null &&
                  Main.remoteFiles.any(
                    (file) => file.key == widget.profile!.deletionRegistrar.key,
                  )) ...[
                SizedBox(height: 32),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(widget.profile!.deletionRegistrar.key),
                  subtitle: Text(
                    'This file is used to track and sync deleted files. Tap to view deletions. This file can be safely deleted if you do not want to sync the deletions in it.',
                  ),
                  trailing: IconButton(
                    onPressed: () async {
                      final yes = await showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Delete Deletion Registrar File?'),
                          content: Text(
                            'Are you sure you want to delete the ${widget.profile!.deletionRegistrar.key}? This will stop syncing deletions tracked in this file.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (yes) {
                        setState(() {
                          _loading = true;
                        });
                        await widget.profile!.deletionRegistrar.clear();
                        setState(() {
                          _loading = false;
                        });
                        showSnackBar(
                          SnackBar(
                            content: Text('Deletion registrar file deleted'),
                          ),
                        );
                        setState(() {});
                      }
                    },
                    icon: Icon(Icons.delete_sweep_rounded),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(
                          title: Text('Deletion Register'),
                          bottom: PreferredSize(
                            preferredSize: Size.fromHeight(14),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 16,
                                bottom: 8.0,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: Text(
                                  widget.profile!.deletionRegistrar.key,
                                  textAlign: TextAlign.start,
                                ),
                              ),
                            ),
                          ),
                        ),
                        body: FutureBuilder<Map<String, DateTime>>(
                          future: widget.profile!.deletionRegistrar
                              .pullDeletions(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return ListView(
                                children: [
                                  for (final entry in snapshot.data!.entries)
                                    ListTile(
                                      title: Text(entry.key),
                                      subtitle: Text(
                                        entry.value.toLocal().toString(),
                                      ),
                                    ),
                                ],
                              );
                            }
                            return Center(child: CircularProgressIndicator());
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (_profile != null) ...[
                SizedBox(height: 32),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text('Remove Profile'),
                  subtitle: Text(
                    'This will remove the profile and its configuration. The files in the bucket and local device will not be deleted.',
                  ),
                  leading: Icon(Icons.delete_forever_rounded),
                  onTap: () async {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Remove Profile?'),
                        content: Text(
                          'Are you sure you want to remove this profile? This action cannot be undone. The files in the bucket and local device will not be deleted.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              Navigator.of(context).pop(1);
                              await ConfigManager.deleteS3Config(
                                _profileNameController.text,
                              );
                              ConfigManager.setBackupMode(
                                '${_profileNameController.text}/',
                                null,
                              );
                              ConfigManager.setLocalDir(
                                '${_profileNameController.text}/',
                                null,
                              );
                              Main.refreshProfiles();
                            },
                            child: Text('Remove'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
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
                themeController.value = value;
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
                ultraDarkController.value = value;
              },
            ),
        ],
      ),
    );
  }
}

class TransferSettingsPage extends StatefulWidget {
  const TransferSettingsPage({super.key});

  @override
  TransferSettingsPageState createState() => TransferSettingsPageState();
}

class TransferSettingsPageState extends State<TransferSettingsPage> {
  late TransferConfig _downloadConfig;
  late int _cacheSize;

  @override
  void initState() {
    super.initState();
    _downloadConfig = ConfigManager.loadTransferConfig();
    _cacheSize = Job.cacheSize();
  }

  Future<void> _saveConfig() async {
    Job.maxrun = _downloadConfig.maxConcurrentTransfers;
    await ConfigManager.saveTransferConfig(_downloadConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Transfer Settings')),
      body: ListView(
        children: [
          ListTile(
            title: Text('Max Concurrent Transfers'),
            subtitle: Text('Set the maximum number of concurrent transfers'),
            trailing: DropdownButton<int>(
              value: _downloadConfig.maxConcurrentTransfers,
              items: List.generate(10, (index) => index + 1)
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text(value.toString()),
                    ),
                  )
                  .toList(),
              onChanged: (int? value) async {
                if (value != null) {
                  setState(() {
                    _downloadConfig = TransferConfig(
                      maxConcurrentTransfers: value,
                    );
                  });
                  await _saveConfig();
                }
              },
            ),
          ),
          ListTile(
            title: Text('Clear Download Cache'),
            subtitle: Text(bytesToReadable(Job.cacheSize())),
            trailing: ElevatedButton(
              onPressed: _cacheSize > 0
                  ? () {
                      Job.clearCache();
                      showSnackBar(
                        SnackBar(content: Text('Download cache cleared')),
                      );
                      setState(() {
                        _cacheSize = Job.cacheSize();
                      });
                    }
                  : null,
              child: Text('Clear'),
            ),
          ),
        ],
      ),
    );
  }
}
