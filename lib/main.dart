import 'dart:io';
import 'package:flutter/material.dart';
import 'package:s3_drive/components.dart';
import 'package:s3_drive/directory_contents.dart';
import 'package:s3_drive/list_files.dart';
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
  final List<dynamic> _searchResults = [];
  String _searchquery = '';
  String _searchdir = '';
  String? _focusedKey;
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
    final localDir = _dirs.contains('${key.split('/').first}/')
        ? _localDirs[_dirs.indexOf('${key.split('/').first}/')]
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
    await _refreshWatchers();
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

  Future<void> _stopWatchers() async {
    for (final watcher in _watchers) {
      await watcher.stop();
    }
  }

  void _startWatchers() {
    for (final watcher in _watchers) {
      watcher.start();
    }
  }

  Future<void> _refreshRemote(String dir) async {
    final remoteFiles = await _s3Manager.listObjects(dir: dir);
    _remoteFilesMap[dir] = remoteFiles;
    _updateCounts();
  }

  Future<void> _refreshWatchers() async {
    await _stopWatchers();
    _watchers.clear();

    for (final dir in _dirs) {
      final localDir = IniManager.config.get('directories', dir);
      final modeValue = int.parse(IniManager.config.get('modes', dir) ?? '1');

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

    _startWatchers();
  }

  Future<void> _listDirectories() async {
    setState(() {
      _loading = true;
    });
    _dirs = await _s3Manager.listDirectories();

    await _stopWatchers();

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

    _startWatchers();
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
      if (!File(_pathFromKey(newKey)).parent.existsSync()) {
        File(_pathFromKey(newKey)).parent.createSync(recursive: true);
      }
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
          await _copyFile(
              file.key, p.join(newDir, p.relative(file.key, from: dir)),
              refresh: false);
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
    await _s3Manager.deleteFile(key);
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
    await _deleteS3Directory(dir, refresh: false);
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
    await _deleteDirectory(dir, refresh: false);
    if (refresh) {
      _listDirectories();
    }
  }

  void _downloadFile(RemoteFile file, {String? localPath}) {
    _jobs.add(
      DownloadJob(
        localFile: File(localPath ?? _pathFromKey(file.key)),
        remoteKey: file.key,
        bytes: file.size,
        md5: file.etag,
        onStatus: _onJobStatus,
      ),
    );
    _startProcessor();
  }

  void _downloadDirectory(String dir, {String? localPath}) {
    for (final map in _remoteFilesMap.entries) {
      for (final file in map.value) {
        if (file.key.startsWith(dir) &&
            file.key != dir &&
            !file.key.endsWith('/')) {
          final relativePath = p.relative(file.key, from: dir);
          final localFilePath =
              p.join(localPath ?? _pathFromKey(dir), relativePath);
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
          await _copyFile(file.key, newKey, refresh: false);
        } else if (_selectionAction == SelectionAction.cut) {
          await _moveFile(file.key, newKey, refresh: false);
        }
      } else if (item is String) {
        final dir = item;
        final newDir = p.join(_localDir, p.basename(dir));
        if (_selectionAction == SelectionAction.copy) {
          await _copyDirectory(dir, newDir, refresh: false);
        } else if (_selectionAction == SelectionAction.cut) {
          await _moveDirectory(dir, newDir, refresh: false);
        }
      }
    }
    _selection.clear();
    _selectionAction = SelectionAction.none;
    _listDirectories();
  }

  void _saveFile(RemoteFile file, String savePath) {
    if (File(savePath).existsSync()) {
      File(savePath).deleteSync();
    }
    // if (!File(_pathFromKey(file.key)).existsSync()) {
    //   if (p.isAbsolute(_pathFromKey(file.key))) {
    //     _downloadFile(file);
    //   }
    // }
    // Has to wait for download to finish
    if (File(_pathFromKey(file.key)).existsSync()) {
      if (!File(savePath).parent.existsSync()) {
        File(savePath).parent.createSync(recursive: true);
      }
      File(_pathFromKey(file.key)).copySync(savePath);
    } else {
      _downloadFile(file, localPath: savePath);
    }
  }

  void _saveDirectory(String dir, String savePath) {
    if (Directory(savePath).existsSync()) {
      Directory(savePath).deleteSync(recursive: true);
    }
    // if (!Directory(_pathFromKey(dir)).existsSync()) {
    //   if (p.isAbsolute(_pathFromKey(dir))) {
    //     _downloadDirectory(dir);
    //   }
    // }
    // Has to wait for download to finish
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
      _downloadDirectory(dir, localPath: savePath);
    }
  }

  void _uploadFile(String key, File file) {
    if (!file.existsSync()) {
      return;
    }
    if (_pathFromKey(key) == file.path) {
      _jobs.add(
        UploadJob(
          localFile: file,
          remoteKey: key,
          bytes: file.lengthSync(),
          onStatus: _onJobStatus,
          md5: HashUtil.md5Hash(file),
        ),
      );
      _startProcessor();
    } else if (p.isAbsolute(_pathFromKey(key))) {
      final newKey = () {
        String base = p.basenameWithoutExtension(key);
        String ext = p.extension(key);
        int count = 1;
        String candidateKey = key;
        while (_remoteFilesMap['${key.split('/').first}/']
                ?.any((remoteFile) => remoteFile.key == candidateKey) ==
            true) {
          candidateKey = p.join(p.dirname(key), '$base${'($count)'}$ext');
          count++;
        }
        return candidateKey;
      }();
      if (!File(_pathFromKey(newKey)).parent.existsSync()) {
        File(_pathFromKey(newKey)).parent.createSync(recursive: true);
      }
      _stopWatchers().then((value) {
        file.copySync(_pathFromKey(newKey));
        _listDirectories();
      });
    } else {
      final newKey = () {
        String base = p.basenameWithoutExtension(key);
        String ext = p.extension(key);
        int count = 1;
        String candidateKey = key;
        while (_remoteFilesMap[key.split('/').first]
                ?.any((remoteFile) => remoteFile.key == candidateKey) ==
            true) {
          candidateKey = p.join(p.dirname(key), '${base}_${'($count)'}$ext');
          count++;
        }
        return candidateKey;
      }();
      _jobs.add(
        UploadJob(
          localFile: file,
          remoteKey: newKey,
          bytes: file.lengthSync(),
          onStatus: _onJobStatus,
          md5: HashUtil.md5Hash(file),
        ),
      );
      _startProcessor();
    }
  }

  void _uploadDirectory(String key, Directory directory) {
    for (final entity
        in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: directory.path);
        final remoteKey = p.join(key, relativePath).replaceAll('\\', '/');
        _uploadFile(remoteKey, entity);
      }
    }
  }

  void _updateCounts() {
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
          .where(
            (file) =>
                (file.key.split('/').last.isNotEmpty &&
                    '${File(file.key).parent.parent.path}/' == _localDir) ||
                (file.key.split('/').last.isEmpty &&
                    '${File(file.key).parent.path}/' == _localDir),
          )
          .map(
            (file) => '${File(file.key).parent.path}/' != _localDir
                ? File(file.key).parent.path
                : p.normalize(File(file.key).path),
          )
          .toSet()
          .toList()
          .length;

      _fileCount = remoteFiles
          .where((file) =>
              file.key.split('/').last.isNotEmpty &&
              '${File(file.key).parent.path}/' == _localDir)
          .length;
    }
    setState(() {});
  }

  Future<void> _showSearch() async {
    return await showSearch(
      context: context,
      maintainState: true,
      delegate: FileSearchDelegate(
        searchFieldLabel: 'Search in "$_localDir"',
        items: () {
          final allItems = [
            ..._dirs,
            ..._remoteFilesMap.entries.expand((entry) => entry.value),
          ];
          if (_localDir == './') {
            return allItems;
          } else {
            return allItems.where((item) {
              if (item is String) {
                return p.isWithin(_localDir, item);
              } else if (item is RemoteFile) {
                return p.isWithin(_localDir, item.key);
              }
              return false;
            }).toList();
          }
        }(),
        providedBuildResults: (context, query, results) {
          _searchquery = query;
          _searchdir = _localDir;
          _searchResults.clear();
          _searchResults.addAll(results);
          _updateAllSelectableItems(results);
          return Container();
        },
      ),
    );
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
                    : _navIndex == 3
                        ? GestureDetector(
                            onTap: () {
                              _showSearch();
                              setState(() {});
                            },
                            child: _searchquery.isNotEmpty
                                ? Text('Searched "$_searchquery"')
                                : const Text("Search"),
                          )
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
                                                        ? _localDirs[
                                                            _dirs.indexOf(
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
            if (_navIndex == 0 || _navIndex == 3)
              _selection.isNotEmpty
                  ? Text(
                      "${_selectionAction == SelectionAction.none ? '' : _selectionAction == SelectionAction.cut ? 'Moving ' : 'Copying '}${_selection.whereType<String>().isNotEmpty ? '${_selection.whereType<String>().length} Folders ' : ''}${_selection.whereType<RemoteFile>().isNotEmpty ? '${_selection.whereType<RemoteFile>().length} Files ' : ''}${_selectionAction == SelectionAction.none ? 'selected' : ''}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  : _navIndex == 0
                      ? Text("$_dirCount Folders  $_fileCount Files",
                          style: Theme.of(context).textTheme.bodyMedium)
                      : Text(
                          "${_searchResults.whereType<String>().isNotEmpty ? '${_searchResults.whereType<String>().length} Folders ' : ''}${_searchResults.whereType<RemoteFile>().isNotEmpty ? '${_searchResults.whereType<RemoteFile>().length} Files ' : ''} found in \"$_searchdir\"",
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
                        const CircularProgressIndicator(
                          padding: EdgeInsets.all(12),
                        ),
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
                                  onPressed: () async {
                                    await _stopWatchers();
                                    await showModalBottomSheet(
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
                                        _pathFromKey,
                                        _getLink,
                                        _downloadFile,
                                        _downloadDirectory,
                                        _saveFile,
                                        _saveDirectory,
                                        (dir, newDir) => _copyDirectory(
                                            dir, newDir,
                                            refresh: false),
                                        (key, newKey) => _moveFile(key, newKey,
                                            refresh: false),
                                        _cut,
                                        _copy,
                                        (key) =>
                                            _deleteFile(key, refresh: false),
                                        (dir) => _deleteDirectory(dir,
                                            refresh: false),
                                        () {
                                          _selection.clear();
                                          setState(() {});
                                        },
                                      ),
                                    ).then((value) => _listDirectories());
                                  },
                                  icon: Icon(Icons.more_vert),
                                ),
                              ]
                            : [
                                if (_localDir != './' && _navIndex == 0)
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
                            if (_navIndex != 3)
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: _loading ? null : _listDirectories,
                              ),
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
                                          if (_localDir != './' ||
                                              _navIndex == 3)
                                            for (var w in [
                                              ListTile(
                                                contentPadding: EdgeInsets.only(
                                                    left: 16, right: 16),
                                                titleTextStyle:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium,
                                                title: Text('Name'),
                                                trailing: _sortMode ==
                                                        SortMode.nameAsc
                                                    ? Icon(Icons.arrow_upward)
                                                    : _sortMode ==
                                                            SortMode.nameDesc
                                                        ? Icon(Icons
                                                            .arrow_downward)
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
                                                titleTextStyle:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium,
                                                title: Text('Date'),
                                                trailing: _sortMode ==
                                                        SortMode.dateAsc
                                                    ? Icon(Icons.arrow_upward)
                                                    : _sortMode ==
                                                            SortMode.dateDesc
                                                        ? Icon(Icons
                                                            .arrow_downward)
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
                                                titleTextStyle:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium,
                                                title: Text('Size'),
                                                trailing: _sortMode ==
                                                        SortMode.sizeAsc
                                                    ? Icon(Icons.arrow_upward)
                                                    : _sortMode ==
                                                            SortMode.sizeDesc
                                                        ? Icon(Icons
                                                            .arrow_downward)
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
                                                titleTextStyle:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium,
                                                title: Text('Type'),
                                                trailing: _sortMode ==
                                                        SortMode.typeAsc
                                                    ? Icon(Icons.arrow_upward)
                                                    : _sortMode ==
                                                            SortMode.typeDesc
                                                        ? Icon(Icons
                                                            .arrow_downward)
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
                                                    _foldersFirst =
                                                        value ?? true;
                                                  });
                                                  Navigator.of(context).pop();
                                                },
                                              ),
                                              const PopupMenuDivider(),
                                            ])
                                              w,
                                          ListTile(
                                            contentPadding: EdgeInsets.only(
                                                left: 16, right: 16),
                                            titleTextStyle: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                            title: Text('Settings'),
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      SettingsPage(),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
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
                  jobs: _jobs,
                  processor: _processor!,
                  remoteFilesMap: _remoteFilesMap,
                  foldersFirst: _foldersFirst,
                  sortMode: _sortMode,
                  focusedKey: _focusedKey,
                  selection: _selection,
                  selectionAction: _selectionAction,
                  select: _select,
                  updateAllSelectableItems: _updateAllSelectableItems,
                  pathFromKey: _pathFromKey,
                  setFocus: (String key) {
                    setState(() {
                      _focusedKey = key;
                    });
                  },
                  setNavIndex: (int index) {
                    _navIndex = index;
                    setState(() {});
                  },
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
                  moveFile: _moveFile,
                  deleteFile: _deleteFile,
                  cut: _cut,
                  copy: _copy,
                  moveDirectory: _moveDirectory,
                  deleteDirectory: _deleteDirectory,
                  stopWatchers: _stopWatchers,
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
                  : _navIndex == 2
                      ? ActiveJobs(
                          jobs: _jobs,
                          processor: _processor!,
                          onUpdate: () {
                            setState(() {});
                          },
                          onJobComplete: _onJobComplete,
                        )
                      : ListView(
                          children: sort(
                                  listFiles(
                                    context,
                                    _searchResults,
                                    true,
                                    _processor!,
                                    _focusedKey,
                                    _selection,
                                    _selectionAction,
                                    _select,
                                    _pathFromKey,
                                    (String key) {
                                      setState(() {
                                        _focusedKey = key;
                                      });
                                    },
                                    (int index) {
                                      _navIndex = index;
                                      setState(() {});
                                    },
                                    () => setState(() {}),
                                    _onJobComplete,
                                    (job) {
                                      setState(() {
                                        _jobs.remove(job);
                                      });
                                    },
                                    (String newDir) {
                                      setState(() {
                                        _localDir = newDir;
                                        _localRoot = _dirs.contains(newDir)
                                            ? _localDirs[_dirs.indexOf(newDir)]
                                            : _localRoot;
                                      });
                                      _updateCounts();
                                    },
                                    _getLink,
                                    _downloadFile,
                                    _downloadDirectory,
                                    _saveFile,
                                    _saveDirectory,
                                    _cut,
                                    _copy,
                                    _moveFile,
                                    _moveDirectory,
                                    _deleteFile,
                                    _deleteDirectory,
                                    _listDirectories,
                                    _stopWatchers,
                                  ),
                                  _sortMode,
                                  _foldersFirst)
                              .map((item) => item.$2)
                              .toList(),
                        ),
      floatingActionButton: _navIndex == 0 && !_loading && _selection.isEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_localDir != './')
                  FloatingActionButton(
                    heroTag: 'upload_file',
                    child: const Icon(Icons.file_upload_outlined),
                    onPressed: () async {
                      final XFile? file = await openFile();
                      if (file != null) {
                        _uploadFile(
                          p.join(_localDir, p.basename(file.path)),
                          File(file.path),
                        );
                      }
                    },
                  ),
                SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: 'upload_directory',
                  child: const Icon(Icons.drive_folder_upload_outlined),
                  onPressed: () async {
                    final String? directoryPath = await getDirectoryPath();
                    if (directoryPath != null) {
                      _uploadDirectory(
                        p.join(
                          _localDir,
                          p.basename(directoryPath),
                        ),
                        Directory(directoryPath),
                      );
                    }
                  },
                ),
                SizedBox(height: 16),
                FloatingActionButton(
                  heroTag: 'create_directory',
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
                      if (_remoteFilesMap[_localDir]!.any((file) => [
                                p.join(_localDir, dir),
                                '${p.join(_localDir, dir)}/'
                              ].contains(file.key)) ||
                          _remoteFilesMap.containsKey(p.join(_localDir, dir)) ||
                          _remoteFilesMap
                              .containsKey('${p.join(_localDir, dir)}/')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Directory "${p.join(_localDir, dir)}" already exists.'),
                          ),
                        );
                        return;
                      }
                      await _createDirectory(p.join(_localDir, dir));
                    }
                  },
                ),
              ],
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
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
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
        ],
        currentIndex: _navIndex,
        onTap: (index) async {
          _navIndex = index;
          setState(() {});
          if (index == 0) {
            _updateCounts();
          }
          if (index != 3) {
            _focusedKey = '';
            setState(() {});
          }
          if (index == 3) {
            await _showSearch();
            setState(() {});
          }
        },
      ),
    );
  }
}
