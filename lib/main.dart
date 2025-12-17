import 'dart:io';
import 'package:flutter/material.dart';
import 'package:s3_drive/components.dart';
import 'package:s3_drive/directory_contents.dart';
import 'package:s3_drive/services/hash_util.dart';
import 'package:s3_drive/services/ini_manager.dart';
import 'package:s3_drive/services/models/common.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:s3_drive/settings.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'services/s3_file_manager.dart';
import 'directory_options.dart';
import 'services/job.dart';
import 'services/models/backup_mode.dart';
import 'package:http/http.dart' as http;
import 'active_jobs.dart';
import 'completed_jobs.dart';
import 'services/config_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'S3 Drive',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          showCloseIcon: true,
        ),
      ),
      home: const Scaffold(body: Home()),
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late S3FileManager _s3Manager;
  late List<String> _dirs = <String>[];
  final List<String> _localDirs = <String>[];
  final List<BackupMode> _backupModes = <BackupMode>[];
  final List<Job> _jobs = <Job>[];
  final List<Job> _completedJobs = <Job>[];
  final List<Watcher> _watchers = <Watcher>[];
  final Map<String, List<RemoteFile>> _remoteFilesMap =
      <String, List<RemoteFile>>{};
  final Set<dynamic> _selection = {};
  final List<dynamic> _allSelectableItems = [];
  final GlobalKey<ScaffoldState> _drawerKey = GlobalKey<ScaffoldState>();
  bool _foldersFirst = true;
  SortMode _sortMode = SortMode.nameAsc;
  SelectionAction _selectionAction = SelectionAction.none;
  int _dirCount = 0;
  int _fileCount = 0;
  int _navIndex = 0;
  String _localDir = './';
  String _localRoot = '';
  Processor? _processor;
  bool _loading = true;
  http.Client httpClient = http.Client();

  String _pathFromKey(String key) {
    final localDir = _dirs.contains(key.split('/').first)
        ? _localDirs[_dirs.indexOf(key.split('/').first)]
        : _localRoot;
    return p.join(localDir, key.split('/').sublist(1).join('/'));
  }

  void _select(dynamic item) {
    if (_selection.any((selected) {
      if (item is RemoteFile && selected is RemoteFile) {
        return selected.key == item.key;
      }
      if (item is String && selected is String) {
        return selected == item;
      }
      return false;
    })) {
      _selection.removeWhere((selected) {
        if (item is RemoteFile && selected is RemoteFile) {
          return selected.key == item.key;
        }
        if (item is String && selected is String) {
          return selected == item;
        }
        return false;
      });
    } else {
      _selection.add(item);
    }
    setState(() {});
  }

  void _updateAllSelectableItems(List<dynamic> items) {
    _allSelectableItems.clear();
    _allSelectableItems.addAll(items);
  }

  void _onJobStatus(Job job) {
    setState(() {});
  }

  void _onJobComplete(Job job, dynamic result) async {
    await _refreshRemote('${job.remoteKey.split('/').first}/');
    _completedJobs.add(job);
    _jobs.remove(job);
    _startProcessor();
    setState(() {});
  }

  void _startProcessor() async {
    _processor ??= Processor(
      cfg: await ConfigManager.loadS3Config(context),
      jobs: _jobs,
      onJobComplete: _onJobComplete,
    );
    _processor!.start();
  }

  Future<void> _refreshRemote(String dir) async {
    final remoteFiles = await _s3Manager.listObjects(dir: dir);
    _remoteFilesMap[dir] = remoteFiles;
    _updateCounts();
  }

  Future<void> _listDirectories() async {
    setState(() {
      _loading = true;
    });
    _dirs = await _s3Manager.listDirectories();

    for (final watcher in _watchers) {
      watcher.stop();
    }

    _watchers.clear();
    _jobs.clear();
    _localDirs.clear();
    _backupModes.clear();

    for (final dir in _dirs) {
      final localDir = IniManager.config.get('directories', dir);
      final modeValue = int.parse(IniManager.config.get('modes', dir) ?? '1');

      _backupModes.add(BackupMode.fromValue(modeValue));
      if (localDir != null &&
          localDir.isNotEmpty &&
          Directory(localDir).existsSync()) {
        _localDirs.add(localDir);
      } else {
        _localDirs.add('');
      }

      await _refreshRemote(dir);

      if (localDir != null &&
          localDir.isNotEmpty &&
          Directory(localDir).existsSync()) {
        _watchers.add(
          Watcher(
            localDir: Directory(localDir),
            remoteDir: dir,
            mode: BackupMode.fromValue(modeValue),
            jobs: _jobs,
            remoteFiles: _remoteFilesMap[dir] ?? [],
            remoteRefresh: () => _refreshRemote(dir),
            downloadFile: _downloadFile,
            uploadFile: _uploadFile,
            onJobStatus: _onJobStatus,
          ),
        );
      }
    }

    for (final watcher in _watchers) {
      watcher.start();
    }

    _startProcessor();

    setState(() {
      _loading = false;
    });
  }

  Future<String> _getLink(RemoteFile file, int? seconds) async {
    Job job = GetLinkJob(
      localFile: File(''),
      remoteKey: file.key,
      bytes: file.size,
      onStatus: _onJobStatus,
      md5: file.etag,
      validForSeconds: seconds ?? 3600,
    );
    await _processor!.processJob(job, (job, result) {});
    return job.statusMsg;
  }

  Future<void> _createDirectory(String dir) async {
    setState(() {
      _loading = true;
    });
    await _s3Manager.createDirectory(dir);
    _listDirectories();
  }

  Future<void> _copyFile(String key, String newKey,
      {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    await _s3Manager.copyFile(key, newKey);
    if (File(_pathFromKey(key)).existsSync()) {
      File(_pathFromKey(key)).copySync(_pathFromKey(newKey));
    }
    if (refresh) {
      _listDirectories();
    }
  }

  Future<void> _copyDirectory(String dir, String newDir,
      {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    for (final map in _remoteFilesMap.entries) {
      for (final file in map.value) {
        if (file.key.startsWith(dir) &&
            file.key != dir &&
            !file.key.endsWith('/')) {
          final newKey = file.key.replaceFirst(dir, newDir);
          await _s3Manager.copyFile(file.key, newKey);
        }
      }
    }
    if (Directory(_pathFromKey(dir)).existsSync()) {
      for (final entity in Directory(_pathFromKey(dir))
          .listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relativePath = p.relative(entity.path, from: _pathFromKey(dir));
          final newFilePath = p.join(_pathFromKey(newDir), relativePath);
          final newFileDir = p.dirname(newFilePath);
          if (!Directory(newFileDir).existsSync()) {
            Directory(newFileDir).createSync(recursive: true);
          }
          entity.copySync(newFilePath);
        }
      }
    }
    if (refresh) {
      _listDirectories();
    }
  }

  Future<void> _deleteFile(String key, {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    _s3Manager.deleteFile(key);
    if (File(_pathFromKey(key)).existsSync()) {
      File(_pathFromKey(key)).deleteSync();
    }
    if (refresh) {
      _listDirectories();
    }
  }

  Future<void> _deleteS3Directory(String dir, {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    for (final map in _remoteFilesMap.entries) {
      for (final file in map.value) {
        if (file.key.startsWith(dir) &&
            file.key != dir &&
            !file.key.endsWith('/')) {
          await _s3Manager.deleteFile(file.key);
        }
      }
      for (final file in map.value) {
        if (file.key.startsWith(dir) &&
            file.key != dir &&
            file.key.endsWith('/')) {
          await _s3Manager.deleteFile(file.key);
        }
      }
    }
    await _s3Manager.deleteFile(dir);
    if (refresh) {
      _listDirectories();
    }
  }

  Future<void> _deleteDirectory(String dir, {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    _deleteS3Directory(dir, refresh: false);
    if (Directory(_pathFromKey(dir)).existsSync()) {
      Directory(_pathFromKey(dir)).deleteSync(recursive: true);
    }
    if (refresh) {
      _listDirectories();
    }
  }

  Future<void> _moveFile(String key, String newKey,
      {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    await _copyFile(key, newKey, refresh: false);
    await _deleteFile(key, refresh: false);
    if (refresh) {
      _listDirectories();
    }
  }

  Future<void> _moveDirectory(String dir, String newDir,
      {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    await _copyDirectory(dir, newDir, refresh: false);
    await _deleteS3Directory(dir, refresh: false);
    if (Directory(_pathFromKey(dir)).existsSync()) {
      Directory(_pathFromKey(dir)).deleteSync(recursive: true);
    }
    if (refresh) {
      _listDirectories();
    }
  }

  Future<void> _downloadFile(RemoteFile file) async {
    _jobs.add(
      DownloadJob(
        localFile: File(_pathFromKey(file.key)),
        remoteKey: file.key,
        bytes: file.size,
        md5: file.etag,
        onStatus: _onJobStatus,
      ),
    );
    _startProcessor();
  }

  Future<void> _downloadDirectory(String dir) async {
    for (final map in _remoteFilesMap.entries) {
      for (final file in map.value) {
        if (file.key.startsWith(dir) &&
            file.key != dir &&
            !file.key.endsWith('/')) {
          final relativePath = p.relative(file.key, from: dir);
          final localFilePath = p.join(_pathFromKey(dir), relativePath);
          final localFileDir = p.dirname(localFilePath);
          if (!Directory(localFileDir).existsSync()) {
            Directory(localFileDir).createSync(recursive: true);
          }
          if (!File(localFilePath).existsSync()) {
            _jobs.add(
              DownloadJob(
                localFile: File(localFilePath),
                remoteKey: file.key,
                bytes: file.size,
                md5: file.etag,
                onStatus: _onJobStatus,
              ),
            );
          }
        }
      }
    }
    _startProcessor();
  }

  void _cut(dynamic item) {
    if (item != null) {
      _selection.add(item);
    }
    _selectionAction = SelectionAction.cut;
    setState(() {});
  }

  void _copy(dynamic item) {
    if (item != null) {
      _selection.add(item);
    }
    _selectionAction = SelectionAction.copy;
    setState(() {});
  }

  Future<void> _paste() async {
    final selection = _selection.toList();
    for (final item in selection) {
      if (item is RemoteFile) {
        final file = item;
        final newKey = p.join(_localDir, p.basename(file.key));
        if (_selectionAction == SelectionAction.copy) {
          _copyFile(file.key, newKey, refresh: false);
        } else if (_selectionAction == SelectionAction.cut) {
          _moveFile(file.key, newKey, refresh: false);
        }
      } else if (item is String) {
        final dir = item;
        final newDir = p.join(_localDir, p.basename(dir));
        if (_selectionAction == SelectionAction.copy) {
          _copyDirectory(dir, newDir, refresh: false);
        } else if (_selectionAction == SelectionAction.cut) {
          _moveDirectory(dir, newDir, refresh: false);
        }
      }
    }
    _selection.clear();
    _selectionAction = SelectionAction.none;
    _listDirectories();
  }

  Future<void> _saveFile(RemoteFile file, String savePath) async {
    if (File(savePath).existsSync()) {
      File(savePath).deleteSync();
    }
    if (File(_pathFromKey(file.key)).existsSync()) {
      if (!File(savePath).parent.existsSync()) {
        File(savePath).parent.createSync(recursive: true);
      }
      File(_pathFromKey(file.key)).copySync(savePath);
    } else {
      _downloadFile(file);
    }
  }

  Future<void> _saveDirectory(String dir, String savePath) async {
    if (Directory(savePath).existsSync()) {
      Directory(savePath).deleteSync(recursive: true);
    }
    if (Directory(_pathFromKey(dir)).existsSync()) {
      for (final entity in Directory(_pathFromKey(dir))
          .listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relativePath = p.relative(entity.path, from: _pathFromKey(dir));
          final newFilePath = p.join(savePath, relativePath);
          final newFileDir = p.dirname(newFilePath);
          if (!Directory(newFileDir).existsSync()) {
            Directory(newFileDir).createSync(recursive: true);
          }
          entity.copySync(newFilePath);
        }
      }
    } else {
      _downloadDirectory(dir);
    }
  }

  Future<void> _uploadFile(String key, File file) async {
    _jobs.add(
      UploadJob(
        localFile: file,
        remoteKey: key,
        bytes: file.lengthSync(),
        onStatus: _onJobStatus,
        md5: await HashUtil.md5Hash(file),
      ),
    );
    _startProcessor();
  }

  Future<void> _updateCounts() async {
    setState(() {
      _dirCount = 0;
      _fileCount = 0;
    });
    if (_localDir == './') {
      _dirCount = _dirs.length;
    } else {
      final remoteFiles =
          _remoteFilesMap['${_localDir.split('/').first}/'] ?? [];
      _dirCount = remoteFiles
          .where((file) =>
              file.key.split('/').last.isEmpty &&
              '${Directory(file.key).parent.path}/' == _localDir)
          .length;
      _fileCount = remoteFiles
          .where((file) =>
              file.key.split('/').last.isNotEmpty &&
              '${File(file.key).parent.path}/' == _localDir)
          .length;
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    setState(() {
      _loading = true;
    });
    IniManager.init();
    S3FileManager.create(context, httpClient).then((manager) {
      _s3Manager = manager;
      _listDirectories();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _navIndex == 1
                ? const Text("Completed Jobs")
                : _navIndex == 2
                    ? const Text("Active Jobs")
                    : _localDir == "./"
                        ? const Text('S3 Drive/')
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: "S3 Drive/$_localDir"
                                  .split('/')
                                  .where((dir) => dir.isNotEmpty)
                                  .map(
                                    (dir) => GestureDetector(
                                      onTap: dir == "S3 Drive"
                                          ? () {
                                              setState(() {
                                                _localDir = './';
                                              });
                                            }
                                          : () {
                                              String newPath = './';
                                              for (final part
                                                  in _localDir.split('/')) {
                                                if (part.isEmpty) continue;
                                                newPath += '$part/';
                                                if (part == dir) break;
                                              }
                                              setState(() {
                                                _localDir =
                                                    "${p.normalize(newPath)}/";
                                                _localRoot = _dirs.contains(
                                                        "${p.normalize(newPath)}/")
                                                    ? _localDirs[_dirs.indexOf(
                                                        "${p.normalize(newPath)}/",
                                                      )]
                                                    : _localRoot;
                                              });
                                            },
                                      child: Text("$dir/"),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
            if (_navIndex == 0)
              _selection.isNotEmpty
                  ? _selectionAction == SelectionAction.none
                      ? Text(
                          "${_selection.whereType<String>().isNotEmpty ? '${_selection.whereType<String>().length} Folders ' : ''}${_selection.whereType<RemoteFile>().isNotEmpty ? '${_selection.whereType<RemoteFile>().length} Files ' : ''}selected",
                          style: Theme.of(context).textTheme.bodyMedium)
                      : _selectionAction == SelectionAction.copy
                          ? Text(
                              "Copying ${_selection.whereType<String>().isNotEmpty ? '${_selection.whereType<String>().length} Folders ' : ''}${_selection.whereType<RemoteFile>().isNotEmpty ? '${_selection.whereType<RemoteFile>().length} Files ' : ''}",
                              style: Theme.of(context).textTheme.bodyMedium)
                          : Text(
                              "Cutting ${_selection.whereType<String>().isNotEmpty ? '${_selection.whereType<String>().length} Folders ' : ''}${_selection.whereType<RemoteFile>().isNotEmpty ? '${_selection.whereType<RemoteFile>().length} Files ' : ''}",
                              style: Theme.of(context).textTheme.bodyMedium)
                  : Text("$_dirCount Folders  $_fileCount Files",
                      style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        actions: _navIndex == 1
            ? [
                if (_completedJobs.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _completedJobs.clear();
                      setState(() {});
                    },
                    icon: Icon(Icons.delete_sweep),
                  ),
              ]
            : _navIndex == 2
                ? [
                    if (_jobs.isNotEmpty)
                      _jobs.any((job) => job.running)
                          ? IconButton(
                              onPressed: () {
                                _processor!.stopall();
                                setState(() {});
                              },
                              icon: Icon(Icons.stop),
                            )
                          : IconButton(
                              onPressed: () {
                                _processor!.start();
                                setState(() {});
                              },
                              icon: Icon(Icons.start),
                            ),
                  ]
                : _loading
                    ? [
                        const CircularProgressIndicator(),
                      ]
                    : _selection.isNotEmpty
                        ? _selectionAction == SelectionAction.none
                            ? [
                                if (_selection.length <
                                    _allSelectableItems.length)
                                  IconButton(
                                    onPressed: () {
                                      _selection.addAll(_allSelectableItems);
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.select_all),
                                  ),
                                IconButton(
                                  onPressed: () {
                                    _selection.clear();
                                    setState(() {});
                                  },
                                  icon: Icon(Icons.close),
                                ),
                                IconButton(
                                  onPressed: () => showModalBottomSheet(
                                          context: context,
                                          enableDrag: true,
                                          showDragHandle: true,
                                          constraints: const BoxConstraints(
                                            maxHeight: 800,
                                            maxWidth: 800,
                                          ),
                                          builder: (context) =>
                                              buildBulkContextMenu(
                                                context,
                                                _selection.toList(),
                                                _localRoot,
                                                _getLink,
                                                _downloadFile,
                                                _downloadDirectory,
                                                _saveFile,
                                                _saveDirectory,
                                                _copyFile,
                                                _copyDirectory,
                                                _moveFile,
                                                _moveDirectory,
                                                _cut,
                                                _copy,
                                                _deleteFile,
                                                _deleteDirectory,
                                                () {
                                                  _selection.clear();
                                                  setState(() {});
                                                },
                                              ))
                                      .then((value) => _listDirectories()),
                                  icon: Icon(Icons.more_vert),
                                ),
                              ]
                            : [
                                IconButton(
                                  onPressed: _paste,
                                  icon: const Icon(Icons.paste),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _selectionAction = SelectionAction.none;
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              ]
                        : [
                            if (_localDir != './')
                              IconButton(
                                icon: const Icon(Icons.more_vert),
                                onPressed: () {
                                  showMenu(
                                    context: context,
                                    position:
                                        RelativeRect.fromLTRB(1000, 60, 0, 0),
                                    menuPadding: EdgeInsets.zero,
                                    items: [
                                      PopupMenuItem(
                                        padding: EdgeInsets.zero,
                                        enabled: false,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ListTile(
                                              contentPadding: EdgeInsets.only(
                                                  left: 16, right: 16),
                                              titleTextStyle: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                              title: Text('Name'),
                                              trailing: _sortMode ==
                                                      SortMode.nameAsc
                                                  ? Icon(Icons.arrow_upward)
                                                  : _sortMode ==
                                                          SortMode.nameDesc
                                                      ? Icon(
                                                          Icons.arrow_downward)
                                                      : null,
                                              onTap: () {
                                                setState(() {
                                                  _sortMode = _sortMode ==
                                                          SortMode.nameAsc
                                                      ? SortMode.nameDesc
                                                      : SortMode.nameAsc;
                                                });
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                            ListTile(
                                              contentPadding: EdgeInsets.only(
                                                  left: 16, right: 16),
                                              titleTextStyle: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                              title: Text('Date'),
                                              trailing: _sortMode ==
                                                      SortMode.dateAsc
                                                  ? Icon(Icons.arrow_upward)
                                                  : _sortMode ==
                                                          SortMode.dateDesc
                                                      ? Icon(
                                                          Icons.arrow_downward)
                                                      : null,
                                              onTap: () {
                                                setState(() {
                                                  _sortMode = _sortMode ==
                                                          SortMode.dateAsc
                                                      ? SortMode.dateDesc
                                                      : SortMode.dateAsc;
                                                });
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                            ListTile(
                                              contentPadding: EdgeInsets.only(
                                                  left: 16, right: 16),
                                              titleTextStyle: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                              title: Text('Size'),
                                              trailing: _sortMode ==
                                                      SortMode.sizeAsc
                                                  ? Icon(Icons.arrow_upward)
                                                  : _sortMode ==
                                                          SortMode.sizeDesc
                                                      ? Icon(
                                                          Icons.arrow_downward)
                                                      : null,
                                              onTap: () {
                                                setState(() {
                                                  _sortMode = _sortMode ==
                                                          SortMode.sizeAsc
                                                      ? SortMode.sizeDesc
                                                      : SortMode.sizeAsc;
                                                });
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                            ListTile(
                                              contentPadding: EdgeInsets.only(
                                                  left: 16, right: 16),
                                              titleTextStyle: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                              title: Text('Type'),
                                              trailing: _sortMode ==
                                                      SortMode.typeAsc
                                                  ? Icon(Icons.arrow_upward)
                                                  : _sortMode ==
                                                          SortMode.typeDesc
                                                      ? Icon(
                                                          Icons.arrow_downward)
                                                      : null,
                                              onTap: () {
                                                setState(() {
                                                  _sortMode = _sortMode ==
                                                          SortMode.typeAsc
                                                      ? SortMode.typeDesc
                                                      : SortMode.typeAsc;
                                                });
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                            const PopupMenuDivider(),
                                            CheckboxListTile(
                                              contentPadding: EdgeInsets.only(
                                                  left: 16, right: 16),
                                              title: Text(
                                                'Folders First',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium,
                                              ),
                                              value: _foldersFirst,
                                              onChanged: (value) {
                                                setState(() {
                                                  _foldersFirst = value ?? true;
                                                });
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _loading ? null : _listDirectories,
                            ),
                          ],
      ),
      drawer: Drawer(
        key: _drawerKey,
        child: ListView(
          children: [
            Padding(
              padding: EdgeInsetsGeometry.all(16),
              child: Text(
                'S3 Drive',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Settings'),
              onTap: () {
                _drawerKey.currentState?.closeDrawer();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => SettingsPage(),
                ));
              },
            ),
          ],
        ),
      ),
      body: _localDir == './' && _navIndex == 0
          ? ListView(
              children: _dirs
                  .map(
                    (dir) => ListTile(
                      leading: Icon(Icons.folder),
                      title: Text(dir.substring(0, dir.length - 1)),
                      subtitle: Text(
                        '${_backupModes[_dirs.indexOf(dir)].name}: ${_localDirs[_dirs.indexOf(dir)]}',
                      ),
                      trailing: IconButton(
                        onPressed: _loading
                            ? null
                            : () {
                                showModalBottomSheet(
                                  context: context,
                                  enableDrag: true,
                                  showDragHandle: true,
                                  constraints: const BoxConstraints(
                                    maxHeight: 800,
                                    maxWidth: 800,
                                  ),
                                  builder: (context) => DirectoryOptions(
                                    directory: dir,
                                    onDelete: _deleteS3Directory,
                                    remoteFiles: _remoteFilesMap[dir] ?? [],
                                  ),
                                ).then((value) => _listDirectories());
                              },
                        icon: const Icon(Icons.more_vert),
                      ),
                      onTap: () {
                        setState(() {
                          _localDir = dir;
                          _localRoot = _dirs.contains(dir)
                              ? _localDirs[_dirs.indexOf(dir)]
                              : _localRoot;
                        });
                        _updateCounts();
                      },
                    ),
                  )
                  .toList(),
            )
          : _localDir != './' && _navIndex == 0
              ? DirectoryContents(
                  directory: _localDir,
                  localRoot: _localRoot,
                  jobs: _jobs,
                  processor: _processor!,
                  remoteFilesMap: _remoteFilesMap,
                  foldersFirst: _foldersFirst,
                  sortMode: _sortMode,
                  selection: _selection,
                  select: _select,
                  updateAllSelectableItems: _updateAllSelectableItems,
                  onJobStatus: _onJobStatus,
                  onJobComplete: _onJobComplete,
                  onChangeDirectory: (String newDir) {
                    setState(() {
                      _localDir = newDir;
                      _localRoot = _dirs.contains(newDir)
                          ? _localDirs[_dirs.indexOf(newDir)]
                          : _localRoot;
                    });
                    _updateCounts();
                  },
                  getLink: _getLink,
                  downloadFile: _downloadFile,
                  saveFile: _saveFile,
                  downloadDirectory: _downloadDirectory,
                  saveDirectory: _saveDirectory,
                  copyFile: _copyFile,
                  moveFile: _moveFile,
                  deleteFile: _deleteFile,
                  cut: _cut,
                  copy: _copy,
                  copyDirectory: _copyDirectory,
                  moveDirectory: _moveDirectory,
                  deleteDirectory: _deleteDirectory,
                  listDirectories: _listDirectories,
                  startProcessor: _startProcessor,
                )
              : _navIndex == 1
                  ? CompletedJobs(
                      completedJobs: _completedJobs,
                      processor: _processor!,
                      onUpdate: () {
                        setState(() {});
                      },
                    )
                  : ActiveJobs(
                      jobs: _jobs,
                      processor: _processor!,
                      onUpdate: () {
                        setState(() {});
                      },
                      onJobComplete: _onJobComplete,
                    ),
      floatingActionButton: _navIndex == 0 && !_loading && _selection.isEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_localDir != './')
                  FloatingActionButton(
                    child: const Icon(Icons.file_upload_outlined),
                    onPressed: () async {
                      final XFile? file = await openFile();
                      if (file != null) {
                        if (!Directory(p.join(_localRoot,
                                _localDir.split('/').sublist(1).join('/')))
                            .existsSync()) {
                          Directory(p.join(_localRoot,
                                  _localDir.split('/').sublist(1).join('/')))
                              .createSync(recursive: true);
                        }
                        if (!File(p.normalize(p.join(
                                _localRoot,
                                _localDir.split('/').sublist(1).join('/'),
                                file.name)))
                            .existsSync()) {
                          await file.saveTo(p.normalize(p.join(
                              _localRoot,
                              _localDir.split('/').sublist(1).join('/'),
                              file.name)));
                        } else {
                          final newname = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              String newName = '';
                              return AlertDialog(
                                title: const Text('File Already Exists'),
                                content: TextField(
                                  decoration: const InputDecoration(
                                    labelText: 'New File Name',
                                  ),
                                  onChanged: (value) => newName = value,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(null),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(newName),
                                    child: const Text('Rename'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (newname != null && newname.isNotEmpty) {
                            await file.saveTo(p.normalize(p.join(
                                _localRoot,
                                _localDir.split('/').sublist(1).join('/'),
                                newname)));
                          }
                        }
                      }
                    },
                  ),
                SizedBox(height: 16),
                FloatingActionButton(
                  child: const Icon(Icons.create_new_folder_rounded),
                  onPressed: () async {
                    final dir = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        String newDir = '';
                        return AlertDialog(
                          title: const Text('Create Directory'),
                          content: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Directory Name',
                            ),
                            onChanged: (value) => newDir = value,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(null),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(newDir),
                              child: const Text('Create'),
                            ),
                          ],
                        );
                      },
                    );
                    if (dir != null && dir.isNotEmpty) {
                      await _createDirectory(
                          p.normalize(p.join(_localDir, dir)));
                    }
                  },
                ),
              ],
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: 'Directories',
          ),
          BottomNavigationBarItem(
            icon: Badge.count(
              count: _completedJobs.length,
              child: Icon(Icons.done_all),
            ),
            label: 'Completed',
          ),
          BottomNavigationBarItem(
            icon: Badge.count(
              count: _jobs.length,
              child: Icon(Icons.swap_vert),
            ),
            label: 'Active',
          ),
        ],
        currentIndex: _navIndex,
        onTap: (index) {
          _navIndex = index;
          setState(() {});
        },
      ),
    );
  }
}
