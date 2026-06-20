import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:m3e_card_list/m3e_card_list.dart';
import 'package:app_settings/app_settings.dart';
import 'package:share_plus/share_plus.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';
import 'package:files3/browser.dart';

class ProfileBackupConfig extends StatefulWidget {
  final BackupMode initialBackupMode;
  final String? initialLocalDir;
  final Function(BackupMode)? onBackupModeChanged;
  final Function(String?)? onLocalDirChanged;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double outerRadius;
  final double innerRadius;
  final double gap;
  final Color? color;
  final EdgeInsetsGeometry? contentPadding;
  final VisualDensity? visualDensity;

  const ProfileBackupConfig({
    super.key,
    required this.initialBackupMode,
    this.initialLocalDir,
    this.onBackupModeChanged,
    this.onLocalDirChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.padding = EdgeInsets.zero,
    this.outerRadius = 14,
    this.innerRadius = 4,
    this.gap = 3,
    this.color = Colors.transparent,
    this.contentPadding,
    this.visualDensity,
  });

  @override
  ProfileBackupConfigState createState() => ProfileBackupConfigState();
}

class ProfileBackupConfigState extends State<ProfileBackupConfig> {
  final GlobalKey<PopupMenuButtonState> _popupKey = GlobalKey();
  late BackupMode _backupMode;
  String? _localDir;
  bool _popupVisible = false;

  @override
  void initState() {
    _backupMode = widget.initialBackupMode;
    _localDir = widget.initialLocalDir;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant ProfileBackupConfig oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBackupMode != oldWidget.initialBackupMode) {
      _backupMode = widget.initialBackupMode;
    }
    if (widget.initialLocalDir != oldWidget.initialLocalDir) {
      _localDir = widget.initialLocalDir;
    }
  }

  @override
  Widget build(BuildContext context) {
    return M3ECardColumn(
      margin: widget.margin,
      padding: widget.padding,
      outerRadius: widget.outerRadius,
      innerRadius: widget.innerRadius,
      gap: widget.gap,
      color: widget.color,
      children: [
        ListTile(
          visualDensity: widget.visualDensity,
          contentPadding: widget.contentPadding,
          leading: const Icon(Icons.drive_folder_upload_rounded),
          title: const Text('Backup From'),
          subtitle: Text(_localDir == null ? 'Not set' : _localDir!),
          onTap: () async {
            final String? directoryPath = await getDirectoryPath();
            if (directoryPath != null) {
              setState(() {
                _localDir = directoryPath;
              });
              widget.onLocalDirChanged?.call(directoryPath);
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
                    widget.onLocalDirChanged?.call(_localDir);
                  },
                ),
        ),
        ListTile(
          visualDensity: widget.visualDensity,
          contentPadding: widget.contentPadding,
          title: Text('BackupMode'),
          subtitle: Text(
            _backupMode == BackupMode.sync
                ? 'Sync'
                : _backupMode == BackupMode.upload
                ? 'Upload Only'
                : 'Unknown',
          ),
          leading: Icon(
            _backupMode == BackupMode.sync
                ? Icons.sync_rounded
                : _backupMode == BackupMode.upload
                ? Icons.upload_rounded
                : Icons.question_mark_rounded,
          ),
          trailing: MyPopupMenuButton(
            key: _popupKey,
            initialValue: _backupMode,
            onOpened: () => setState(() {
              _popupVisible = true;
            }),
            onSelected: (BackupMode value) async {
              setState(() {
                _popupVisible = false;
                _backupMode = value;
              });
              widget.onBackupModeChanged?.call(value);
            },
            onCanceled: () => setState(() {
              _popupVisible = false;
            }),
            menuPadding: EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            icon: Icon(
              _popupVisible
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
            ),
            position: PopupMenuPosition.under,
            itemBuilder: (context) => [
              MyPopupMenuItem(
                value: BackupMode.upload,
                child: Text('Upload'),
                backgroundColor: Colors.transparent,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                selectedForegroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimary,
              ),
              MyPopupMenuItem(
                value: BackupMode.sync,
                child: Text('Sync'),
                backgroundColor: Colors.transparent,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                selectedForegroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimary,
              ),
            ],
          ),
          onTap: () {
            setState(() {
              _popupVisible = !_popupVisible;
            });
            if (_popupVisible) {
              _popupKey.currentState?.showButtonMenu();
            }
          },
        ),
      ],
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
      Main.profiles.containsKey(_profileNameController.text);

  Future<void> _readConfig() async {
    setState(() {
      _loading = true;
    });
    try {
      _profile = widget.profile;
      _profile ??= Main.profiles[_profileNameController.text];
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
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: true,
              title: Text(
                '${_profileNameController.text.isEmpty ? "New " : ""}S3 Profile Config',
              ),
              actionsPadding: EdgeInsets.only(right: 4),
              actions: [
                IconButton(
                  onPressed: _saveConfig(),
                  icon: Icon(Icons.save),
                  tooltip: 'Save Configuration',
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: AutofillGroup(
                  child: Form(
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
                        SizedBox(height: 24),
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
                        SizedBox(height: 16),
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
                        SizedBox(height: 24),
                        Autocomplete<String>(
                          focusNode: _regionFocusNode,
                          textEditingController: _regionController,
                          onSelected: (String selection) {
                            setState(() {});
                          },
                          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                            focusNode.addListener(() {
                              if (focusNode.hasFocus &&
                                  controller.text.isEmpty) {
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
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(96),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.all(0),
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
                                        selected:
                                            _regionController.text == option,
                                      );
                                    },
                                  ),
                                ),
                              ),
                        ),
                        SizedBox(height: 16),
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
                        SizedBox(height: 24),
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
                          autofillHints: const [
                            'prefix',
                            's3 prefix',
                            's3_prefix',
                          ],
                          textInputAction: TextInputAction.next,
                        ),
                        SizedBox(height: 16),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: ProfileBackupConfig(
                initialBackupMode: _backupMode,
                initialLocalDir: _localDir,
                onBackupModeChanged: (mode) {
                  setState(() {
                    _backupMode = mode;
                  });
                },
                onLocalDirChanged: (dir) {
                  setState(() {
                    _localDir = dir;
                  });
                },
              ),
            ),
            if (_bucketController.text.isNotEmpty)
              SliverM3ECardList(
                itemCount: _permissionPolicy != null ? 3 : 1,
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                padding: EdgeInsets.zero,
                color: Colors.transparent,
                itemBuilder: (context, index) {
                  switch (index) {
                    case 0:
                      return _bucketController.text.isNotEmpty
                          ? ListTile(
                              title: Text(
                                'Make sure the provided AWS credentials have the following permissions:',
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_prefixController.text.isNotEmpty) ...[
                                    SizedBox(height: 8),
                                    Text('s3:ListBucket'),
                                    Text(
                                      'on arn:aws:s3:::${_bucketController.text}',
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      's3:GetObject, s3:PutObject, s3:DeleteObject',
                                    ),
                                    Text(
                                      'on arn:aws:s3:::${_bucketController.text}/${_prefixController.text}*',
                                    ),
                                  ] else ...[
                                    SizedBox(height: 8),
                                    Text(
                                      's3:ListBucket, s3:GetObject, s3:PutObject, s3:DeleteObject',
                                    ),
                                    Text(
                                      'on arn:aws:s3:::${_bucketController.text}*',
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : SizedBox.shrink();
                    case 1:
                      return ListTile(
                        subtitle: Text(
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
                      );
                    case 2:
                      return ListTile(
                        subtitle: SelectableText(_permissionPolicy ?? ''),
                      );
                    default:
                      return SizedBox.shrink();
                  }
                },
              ),
            if (_profile != null)
              SliverM3ECardList(
                itemCount: 3,
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                padding: EdgeInsets.zero,
                color: Colors.transparent,
                itemBuilder: (context, index) {
                  switch (index) {
                    case 0:
                      return ListTile(
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
                      );
                    case 1:
                      return CheckboxListTile(
                        title: Text('Include Keys'),
                        subtitle: Text(
                          'Caution: AWS keys will be exported. Keep it secure.',
                        ),
                        value: _includeKeys,
                        onChanged: (value) {
                          _includeKeys = value ?? false;
                          setState(() {});
                        },
                      );
                    case 2:
                      return CheckboxListTile(
                        title: Text('Include Backup Configuration'),
                        value: _includeBackupConfig,
                        onChanged: (value) {
                          _includeBackupConfig = value ?? false;
                          setState(() {});
                        },
                      );
                    default:
                      return SizedBox.shrink();
                  }
                },
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: M3ECard(
                    index: 0,
                    position: M3ECardPosition.single,
                    outerRadius: 24,
                    innerRadius: 4,
                    gap: 3,
                    padding: EdgeInsets.zero,
                    color: Colors.transparent,
                    child: ListTile(
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
                                    extensions: [
                                      'files3profile',
                                      'json',
                                      'txt',
                                    ],
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
                                      content: Text(
                                        'Failed to import profile: $e',
                                      ),
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
                  ),
                ),
              ),
            if (widget.profile != null &&
                Main.remoteFiles[widget.profile!.deletionRegistrar.key] != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: M3ECard(
                    index: 0,
                    position: M3ECardPosition.single,
                    outerRadius: 24,
                    innerRadius: 4,
                    gap: 3,
                    padding: EdgeInsets.zero,
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(widget.profile!.deletionRegistrar.key),
                      subtitle: Text(
                        'This file is used to track and sync deleted files. Tap to view deletions. This file can be safely deleted if you do not want to sync the deletions in it.',
                      ),
                      leading: Icon(Icons.delete_sweep_rounded),
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
                              actions: [
                                IconButton(
                                  onPressed: () async {
                                    final yes = await showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(
                                          'Delete Deletion Registrar File?',
                                        ),
                                        content: Text(
                                          'Are you sure you want to delete the ${widget.profile!.deletionRegistrar.key}? This will stop syncing deletions tracked in this file.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              context,
                                            ).pop(false),
                                            child: Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
                                            child: Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (yes) {
                                      setState(() {
                                        _loading = true;
                                      });
                                      await widget.profile!.deletionRegistrar
                                          .clear();
                                      setState(() {
                                        _loading = false;
                                      });
                                      showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Deletion registrar file deleted',
                                          ),
                                        ),
                                      );
                                      setState(() {});
                                    }
                                  },
                                  icon: Icon(Icons.delete_sweep_rounded),
                                ),
                              ],
                            ),
                            body: FutureBuilder<Map<String, DateTime>>(
                              future: widget.profile!.deletionRegistrar
                                  .pullDeletions(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  return ListView(
                                    children: [
                                      for (final entry
                                          in snapshot.data!.entries)
                                        ListTile(
                                          title: Text(entry.key),
                                          subtitle: Text(
                                            entry.value.toLocal().toString(),
                                          ),
                                        ),
                                    ],
                                  );
                                }
                                return Center(
                                  child: CircularProgressIndicator(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_profile != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: M3ECard(
                    index: 0,
                    position: M3ECardPosition.single,
                    outerRadius: 24,
                    innerRadius: 4,
                    gap: 3,
                    padding: EdgeInsets.zero,
                    color: Colors.transparent,
                    child: ListTile(
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
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  late UiConfig _uiConfig;
  late TransferConfig _downloadConfig;
  late int _cacheSize;

  bool _colorModePopupVisible = false;
  bool _maxTransfersPopupVisible = false;
  PackageInfo? packageInfo;

  final GlobalKey<PopupMenuButtonState<ThemeMode>> _colorModepopupKey =
      GlobalKey();
  final GlobalKey<PopupMenuButtonState<int>> _maxTransfersPopupKey =
      GlobalKey();

  Future<void> _getPackageInfo() async {
    packageInfo = await PackageInfo.fromPlatform();
    setState(() {});
  }

  Future<bool> colorPickerDialog() async {
    return ColorPicker(
      // Use the dialogPickerColor as start and active color.
      color: _uiConfig.accentColor ?? Theme.of(context).colorScheme.primary,
      // Update the dialogPickerColor using the callback.
      onColorChanged: (Color color) async {
        setState(() {
          _colorModePopupVisible = false;
          _uiConfig.accentColor = color;
        });
        await _saveConfig();
        uiConfigNotifier.accentColor.value = _uiConfig.accentColor;
      },
      width: 40,
      height: 40,
      borderRadius: 28,
      spacing: 5,
      runSpacing: 5,
      hasBorder: true,
      wheelDiameter: 155,
      columnSpacing: 12,
      title: Text(
        'Select color',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      recentColorsSubheading: Text(
        'Recent Colors',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      enableTonalPalette: true,
      showMaterialName: true,
      showColorName: true,
      showColorCode: true,
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
        copyButton: true,
        pasteButton: true,
        longPressMenu: true,
        secondaryMenu: true,
        copyFormat: ColorPickerCopyFormat.hexRRGGBB,
        snackBarParseError: true,
        feedbackParseError: true,
        parseShortHexCode: true,
      ),
      materialNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorCodeTextStyle: Theme.of(context).textTheme.bodySmall,
      showRecentColors: true,
      recentColors: ConfigManager.loadRecentColors(),
      maxRecentColors: 6,
      onRecentColorsChanged: (List<Color> recentColors) {
        ConfigManager.saveRecentColors(recentColors);
      },
      selectedPickerTypeColor: Theme.of(context).colorScheme.primary,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: true,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: true,
        ColorPickerType.custom: true,
        ColorPickerType.wheel: true,
      },
      pickerTypeLabels: {
        ColorPickerType.both: 'Accent',
        ColorPickerType.primary: 'Primary',
        ColorPickerType.accent: 'Accent',
        ColorPickerType.bw: 'Black & White',
        ColorPickerType.custom: 'Custom',
        ColorPickerType.wheel: 'Wheel',
      },
    ).showPickerDialog(
      context,
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> a1,
            Animation<double> a2,
            Widget widget,
          ) {
            final double curvedValue =
                Curves.easeInOutBack.transform(a1.value) - 1.0;
            return Transform(
              transform: Matrix4.translationValues(0.0, curvedValue * 200, 0.0),
              child: Opacity(opacity: a1.value, child: widget),
            );
          },
      transitionDuration: const Duration(milliseconds: 400),
      constraints: const BoxConstraints(
        minHeight: 460,
        minWidth: 300,
        maxWidth: 320,
      ),
    );
  }

  Future<void> _saveConfig() async {
    await ConfigManager.saveUiConfig(_uiConfig);
    Job.maxrun = _downloadConfig.maxConcurrentTransfers;
    await ConfigManager.saveTransferConfig(_downloadConfig);
  }

  @override
  void initState() {
    super.initState();
    _uiConfig = ConfigManager.loadUiConfig();
    _downloadConfig = ConfigManager.loadTransferConfig();
    _cacheSize = Job.cacheSize();
    _getPackageInfo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: false,
            snap: false,
            pinned: true,
            title: Text('Settings'),
          ),
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                floating: false,
                pinned: true,
                delegate: MyPersistentHeaderDelegate(
                  height: 34,
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Appearance",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              SliverM3ECardList(
                itemCount: 3,
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                padding: EdgeInsets.zero,
                color: Colors.transparent,
                itemBuilder: (context, index) {
                  switch (index) {
                    case 0:
                      return ListTile(
                        title: Text('Color Mode'),
                        subtitle: Text(
                          _uiConfig.colorMode == ThemeMode.system
                              ? 'System Default'
                              : _uiConfig.colorMode == ThemeMode.light
                              ? 'Light Mode'
                              : 'Dark Mode',
                        ),
                        leading: Icon(
                          _uiConfig.colorMode == ThemeMode.system
                              ? Icons.contrast_rounded
                              : _uiConfig.colorMode == ThemeMode.light
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                        ),
                        trailing: MyPopupMenuButton<ThemeMode>(
                          key: _colorModepopupKey,
                          initialValue: _uiConfig.colorMode,
                          onOpened: () => setState(() {
                            _colorModePopupVisible = true;
                          }),
                          onSelected: (ThemeMode value) async {
                            setState(() {
                              _colorModePopupVisible = false;
                              _uiConfig.colorMode = value;
                            });
                            await _saveConfig();
                            uiConfigNotifier.colorMode.value =
                                _uiConfig.colorMode;
                          },
                          onCanceled: () => setState(() {
                            _colorModePopupVisible = false;
                          }),
                          menuPadding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          icon: Icon(
                            _colorModePopupVisible
                                ? Icons.arrow_drop_up_rounded
                                : Icons.arrow_drop_down_rounded,
                          ),
                          position: PopupMenuPosition.under,
                          itemBuilder: (context) => [
                            MyPopupMenuItem(
                              value: ThemeMode.system,
                              child: Text('System Default'),
                              backgroundColor: Colors.transparent,
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                              selectedBackgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              selectedForegroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                            ),
                            MyPopupMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light Mode'),
                              backgroundColor: Colors.transparent,
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                              selectedBackgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              selectedForegroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                            ),
                            MyPopupMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark Mode'),
                              backgroundColor: Colors.transparent,
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                              selectedBackgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              selectedForegroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            _colorModePopupVisible = !_colorModePopupVisible;
                          });
                          if (_colorModePopupVisible) {
                            _colorModepopupKey.currentState?.showButtonMenu();
                          }
                        },
                      );
                    case 1:
                      return ListTile(
                        title: Text('Accent Color'),
                        subtitle: Text(
                          '${ColorTools.materialNameAndARGBCode(_uiConfig.accentColor ?? Theme.of(context).colorScheme.primary)} '
                          '${ColorTools.nameThatColor(_uiConfig.accentColor ?? Theme.of(context).colorScheme.primary)}',
                        ),
                        leading: Icon(Icons.color_lens_rounded),
                        onTap: () async {
                          // Store current color before we open the dialog.
                          final Color? colorBeforeDialog =
                              _uiConfig.accentColor;
                          // Wait for the picker to close, if dialog was dismissed,
                          // then restore the color we had before it was opened.
                          if (!(await colorPickerDialog())) {
                            setState(() {
                              _uiConfig.accentColor = colorBeforeDialog;
                            });
                            await _saveConfig();
                            uiConfigNotifier.accentColor.value =
                                _uiConfig.accentColor;
                          }
                        },
                        onLongPress: () async {
                          setState(() {
                            _uiConfig.accentColor = null;
                          });
                          showSnackBar(
                            SnackBar(
                              content: Text('Accent color reset to default'),
                            ),
                          );
                          await _saveConfig();
                          uiConfigNotifier.accentColor.value =
                              _uiConfig.accentColor;
                        },
                        trailing: ColorIndicator(
                          width: 44,
                          height: 44,
                          borderRadius: 22,
                          hasBorder: true,
                          color:
                              _uiConfig.accentColor ??
                              Theme.of(context).colorScheme.primary,
                          onSelectFocus: false,
                          onSelect: () async {
                            // Store current color before we open the dialog.
                            final Color? colorBeforeDialog =
                                _uiConfig.accentColor;
                            // Wait for the picker to close, if dialog was dismissed,
                            // then restore the color we had before it was opened.
                            if (!(await colorPickerDialog())) {
                              setState(() {
                                _uiConfig.accentColor = colorBeforeDialog;
                              });
                              await _saveConfig();
                              uiConfigNotifier.accentColor.value =
                                  _uiConfig.accentColor;
                            }
                          },
                        ),
                      );
                    case 2:
                      return SwitchListTile(
                        title: Text('Ultra Dark Mode'),
                        subtitle: Text('Pure black background for dark mode'),
                        secondary: Icon(
                          uiConfigNotifier.ultraDark.value
                              ? Icons.brightness_1_outlined
                              : Icons.brightness_1,
                        ),
                        value: _uiConfig.ultraDark,
                        onChanged: _uiConfig.colorMode != ThemeMode.light
                            ? (value) async {
                                setState(() {
                                  _uiConfig.ultraDark = value;
                                });
                                await _saveConfig();
                                uiConfigNotifier.ultraDark.value = value;
                              }
                            : null,
                      );
                    default:
                      return SizedBox.shrink();
                  }
                },
              ),
            ],
          ),
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                floating: false,
                pinned: true,
                delegate: MyPersistentHeaderDelegate(
                  height: 34,
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Interface",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              SliverM3ECardList(
                itemCount: 8,
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                padding: EdgeInsets.zero,
                color: Colors.transparent,
                itemBuilder: (context, index) {
                  switch (index) {
                    case 0:
                      return ListTile(
                        title: Text('Pinned Folders'),
                        subtitle: Text(
                          'Manage pinned folders for quick access',
                        ),
                        leading: Icon(Icons.push_pin_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => PinnedFoldersPage(),
                          ),
                        ),
                      );
                    case 1:
                      return SwitchListTile(
                        title: Text('Show Directory Summary'),
                        subtitle: Text("App Bar"),
                        secondary: Icon(Icons.folder_rounded),
                        value: _uiConfig.showDirectorySummary,
                        onChanged: (value) async {
                          setState(() {
                            _uiConfig.showDirectorySummary = value;
                          });
                          await _saveConfig();
                          uiConfigNotifier.showDirectorySummary.value = value;
                        },
                      );
                    case 2:
                      return SwitchListTile(
                        title: Text('Show Backup Configuration'),
                        subtitle: Text("App Bar"),
                        secondary: Icon(Icons.backup_rounded),
                        value: _uiConfig.showDirectoryBackupConfig,
                        onChanged: (value) async {
                          setState(() {
                            _uiConfig.showDirectoryBackupConfig = value;
                          });
                          await _saveConfig();
                          uiConfigNotifier.showDirectoryBackupConfig.value =
                              value;
                        },
                      );
                    case 3:
                      return SwitchListTile(
                        title: Text('Show Time'),
                        subtitle: Text("List View"),
                        secondary: Icon(Icons.access_time_rounded),
                        value: _uiConfig.showTime,
                        onChanged: (value) async {
                          setState(() {
                            _uiConfig.showTime = value;
                          });
                          await _saveConfig();
                          uiConfigNotifier.showTime.value = value;
                        },
                      );
                    case 4:
                      return SwitchListTile(
                        title: Text('Show Size'),
                        subtitle: Text("List View"),
                        secondary: Icon(Icons.storage_rounded),
                        value: _uiConfig.showSize,
                        onChanged: (value) async {
                          setState(() {
                            _uiConfig.showSize = value;
                          });
                          await _saveConfig();
                          uiConfigNotifier.showSize.value = value;
                        },
                      );
                    case 5:
                      return SwitchListTile(
                        title: Text('Show Download Status'),
                        subtitle: Text("List & Grid View"),
                        secondary: Icon(Icons.download_rounded),
                        value: _uiConfig.showDownloadStatus,
                        onChanged: (value) async {
                          setState(() {
                            _uiConfig.showDownloadStatus = value;
                          });
                          await _saveConfig();
                          uiConfigNotifier.showDownloadStatus.value = value;
                        },
                      );
                    case 6:
                      return SwitchListTile(
                        title: Text('Show File Type'),
                        subtitle: Text("List View"),
                        secondary: Icon(Icons.description_rounded),
                        value: _uiConfig.showType,
                        onChanged: (value) async {
                          setState(() {
                            _uiConfig.showType = value;
                          });
                          await _saveConfig();
                          uiConfigNotifier.showType.value = value;
                        },
                      );
                    case 7:
                      return SwitchListTile(
                        title: Text('Show Directory Content'),
                        subtitle: Text("List View"),
                        secondary: Icon(Icons.preview_rounded),
                        value: _uiConfig.showContent,
                        onChanged: (value) async {
                          setState(() {
                            _uiConfig.showContent = value;
                          });
                          await _saveConfig();
                          uiConfigNotifier.showContent.value = value;
                        },
                      );
                    default:
                      return SizedBox.shrink();
                  }
                },
              ),
            ],
          ),
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                floating: false,
                pinned: true,
                delegate: MyPersistentHeaderDelegate(
                  height: 34,
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Behavious",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),

              SliverM3ECardList(
                itemCount: 2,
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                padding: EdgeInsets.zero,
                color: Colors.transparent,
                itemBuilder: (context, index) {
                  switch (index) {
                    case 0:
                      return ListTile(
                        title: Text('Max Concurrent Transfers'),
                        subtitle: Text(
                          _downloadConfig.maxConcurrentTransfers.toString(),
                        ),
                        leading: Icon(Icons.swap_vertical_circle),
                        trailing: MyPopupMenuButton<int>(
                          key: _maxTransfersPopupKey,
                          initialValue: _downloadConfig.maxConcurrentTransfers,
                          position: PopupMenuPosition.under,
                          itemBuilder: (context) =>
                              List.generate(10, (i) => i + 1)
                                  .map(
                                    (index) => MyPopupMenuItem<int>(
                                      value: index,
                                      child: Text(index.toString()),
                                      backgroundColor: Colors.transparent,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      foregroundColor: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      selectedBackgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      selectedForegroundColor: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                  )
                                  .toList(),

                          onOpened: () => setState(() {
                            _maxTransfersPopupVisible = true;
                          }),
                          menuPadding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          icon: Icon(
                            _maxTransfersPopupVisible
                                ? Icons.arrow_drop_up_rounded
                                : Icons.arrow_drop_down_rounded,
                          ),
                          onSelected: (int value) async {
                            setState(() {
                              _maxTransfersPopupVisible = false;
                              _downloadConfig = TransferConfig(
                                maxConcurrentTransfers: value,
                              );
                            });
                            await _saveConfig();
                          },
                          onCanceled: () => setState(() {
                            _maxTransfersPopupVisible = false;
                          }),
                        ),
                        onTap: () {
                          setState(() {
                            _maxTransfersPopupVisible =
                                !_maxTransfersPopupVisible;
                          });
                          if (_maxTransfersPopupVisible) {
                            _maxTransfersPopupKey.currentState
                                ?.showButtonMenu();
                          }
                        },
                      );
                    case 1:
                      return ListTile(
                        title: Text('Downloads & Thumbnail Cache'),
                        subtitle: Text(bytesToReadable(Job.cacheSize())),
                        leading: Icon(Icons.history_rounded),
                        trailing: TextButton(
                          onPressed: _cacheSize > 0
                              ? () async {
                                  if (await confirmDialog(
                                    context,
                                    title: 'Confirm Clear Cache',
                                    content: Text(
                                      'Are you sure you want to clear the cache?',
                                    ),
                                    okText: 'Clear',
                                    cancelText: 'Cancel',
                                  )) {
                                    Job.clearCache();
                                    showSnackBar(
                                      SnackBar(content: Text('Cache cleared')),
                                    );
                                    setState(() {
                                      _cacheSize = Job.cacheSize();
                                    });
                                  }
                                }
                              : null,
                          child: Text('Clear'),
                        ),
                      );
                    default:
                      return SizedBox.shrink();
                  }
                },
              ),
            ],
          ),
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                floating: false,
                pinned: true,
                delegate: MyPersistentHeaderDelegate(
                  height: 34,
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "System",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              SliverM3ECardList(
                itemCount: 2,
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                padding: EdgeInsets.zero,
                color: Colors.transparent,
                itemBuilder: (context, index) {
                  switch (index) {
                    case 0:
                      return ListTile(
                        leading: Icon(Icons.info_rounded),
                        title: Text(
                          '${packageInfo?.appName ?? 'Files3'} Details',
                        ),
                        subtitle: Text(
                          '${packageInfo?.packageName ?? ''} ${packageInfo?.version ?? ''} ${packageInfo?.buildNumber ?? ''}',
                        ),
                        onTap: () => AppSettings.openAppSettings(
                          type: AppSettingsType.settings,
                        ),
                      );
                    case 1:
                      return ListTile(
                        leading: Icon(Icons.restart_alt_rounded),
                        title: Text('Set to Defaults'),
                        onTap: () async {
                          if ((await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Reset Settings'),
                                  content: Text(
                                    'Are you sure you want to reset all settings to their default values? This action cannot be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: Text('Reset'),
                                    ),
                                  ],
                                ),
                              )) ==
                              true) {
                            _uiConfig = UiConfig();
                            _downloadConfig = TransferConfig();
                            uiConfigNotifier.setValues(_uiConfig);
                            await _saveConfig();
                          }
                        },
                      );
                    default:
                      return SizedBox.shrink();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PinnedFoldersPage extends StatefulWidget {
  const PinnedFoldersPage({super.key});

  @override
  State<PinnedFoldersPage> createState() => PinnedFoldersPageState();
}

class PinnedFoldersPageState extends State<PinnedFoldersPage> {
  late List<MapEntry<String, String>> _pinnedFolders;

  @override
  void initState() {
    super.initState();
    _pinnedFolders = ConfigManager.loadPinnedFolders();
  }

  Future<void> _saveConfig() async {
    await ConfigManager.savePinnedFolders(_pinnedFolders);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pinned Folders')),
      body: ReorderableListView(
        onReorderItem: (oldIndex, newIndex) async {
          setState(() {
            if (newIndex > oldIndex) {
              newIndex -= 1;
            }
            final item = _pinnedFolders.removeAt(oldIndex);
            _pinnedFolders.insert(newIndex, item);
          });
          await _saveConfig();
        },
        padding: EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (int i = 0; i < _pinnedFolders.length; i++)
            Dismissible(
              key: ValueKey(_pinnedFolders[i].key),
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.endToStart) {
                  return false;
                } else {
                  return true;
                }
              },
              onDismissed: (direction) async {
                MapEntry<String, String> removedFolder = _pinnedFolders[i];
                setState(() {
                  _pinnedFolders.removeAt(i);
                });
                showSnackBar(
                  SnackBar(
                    content: Text('Pinned folder removed'),
                    showCloseIcon: false,
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () async {
                        setState(() {
                          _pinnedFolders.insert(
                            i,
                            MapEntry(removedFolder.key, removedFolder.value),
                          );
                        });
                        await _saveConfig();
                      },
                    ),
                  ),
                );
                await _saveConfig();
              },
              child: M3ECard(
                index: i,
                position: i <= 0
                    ? M3ECardPosition.first
                    : i >= _pinnedFolders.length - 1
                    ? M3ECardPosition.last
                    : M3ECardPosition.middle,
                outerRadius: 24,
                innerRadius: 4,
                gap: 3,
                padding: EdgeInsets.zero,
                child: ListTile(
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.only(left: 20, right: 8),
                  key: ValueKey(_pinnedFolders[i]),
                  title: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _pinnedFolders[i].key,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  subtitle: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _pinnedFolders[i].value,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  leading: Icon(Icons.drag_handle_rounded),
                  trailing: IconButton(
                    icon: Icon(Icons.close_rounded),
                    onPressed: () async {
                      MapEntry<String, String> removedFolder =
                          _pinnedFolders[i];
                      setState(() {
                        _pinnedFolders.removeAt(i);
                      });
                      showSnackBar(
                        SnackBar(
                          content: Text('Pinned folder removed'),
                          showCloseIcon: false,
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () async {
                              setState(() {
                                _pinnedFolders.insert(
                                  i,
                                  MapEntry(
                                    removedFolder.key,
                                    removedFolder.value,
                                  ),
                                );
                              });
                              await _saveConfig();
                            },
                          ),
                        ),
                      );
                      await _saveConfig();
                    },
                  ),
                  onTap: () async {
                    String newName =
                        (await renameDialog(
                          context,
                          _pinnedFolders[i].key,
                          title: 'Rename ${_pinnedFolders[i].key}',
                          existingNames: _pinnedFolders
                              .map((e) => e.key)
                              .toList(),
                        )) ??
                        _pinnedFolders[i].key;
                    if (newName != _pinnedFolders[i].key) {
                      _pinnedFolders[i] = MapEntry(
                        newName,
                        _pinnedFolders[i].value,
                      );
                      setState(() {});
                      await _saveConfig();
                    }
                  },
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PathPicker(
                onPick: (path) async {
                  setState(() {
                    _pinnedFolders.add(MapEntry(path.key, path.key));
                  });
                  await _saveConfig();
                },
              ),
            ),
          );
        },
        child: Icon(Icons.add_rounded),
      ),
    );
  }
}
