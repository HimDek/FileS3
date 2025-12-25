import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:s3_drive/components.dart';
import 'package:s3_drive/list_files.dart';
import 'package:s3_drive/services/models/common.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:s3_drive/settings.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'directory_options.dart';
import 'services/job.dart';
import 'active_jobs.dart';
import 'completed_jobs.dart';

/// ===============================
/// SHARED ASYNC JOB
/// ===============================
Future<void> runJob({
  required void Function(double progress) onProgress,
}) async {
  await Main.init(null, background: true);
  Job.onProgressUpdate = () {
    final runningJobs = Job.jobs.where((job) => job.running).toList();
    if (runningJobs.isEmpty) {
      onProgress(1.0);
      return;
    }
    double totalProgress = 0.0;
    for (final job in runningJobs) {
      totalProgress += job.bytesCompleted / job.bytes;
    }
    onProgress(totalProgress / runningJobs.length);
  };
  if (Job.jobs.any((job) => !job.completed && !job.running && !job.failed)) {
    sleep(Duration(seconds: 2));
  }
}

/// ===============================
/// WORKMANAGER ENTRY
/// ===============================
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final appRunning = prefs.getBool('app_running') ?? false;

    if (appRunning) return true;

    await FlutterForegroundTask.startService(
      notificationTitle: 'Job running',
      notificationText: 'Preparing...',
      callback: startForegroundTask,
    );

    return true;
  });
}

/// ===============================
/// FOREGROUND SERVICE ENTRY
/// ===============================
void startForegroundTask() {
  FlutterForegroundTask.setTaskHandler(FgHandler());
}

class FgHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter? starter) async {
    await runJob(onProgress: (p) {
      FlutterForegroundTask.updateService(
        notificationText: 'Progress ${(p * 100).toInt()}%',
      );
    });

    FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Not used
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool? isTimeout) async {
    // Clean up resources
  }
}

/// ===============================
/// APP LIFECYCLE
/// ===============================
class LifecycleWatcher extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('app_running', state == AppLifecycleState.resumed);
  }
}

/// ===============================
/// MAIN
/// ===============================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  WidgetsBinding.instance.addObserver(LifecycleWatcher());

  // if (!kIsWeb &&
  //     (defaultTargetPlatform == TargetPlatform.android ||
  //         defaultTargetPlatform == TargetPlatform.iOS)) {
  //   await Workmanager().initialize(callbackDispatcher);
  // }

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
  final Set<RemoteFile> _selection = {};
  final List<RemoteFile> _allSelectableItems = [];
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
  bool _loading = true;

  void _select(RemoteFile item) {
    if (_selection.any((selected) {
      return selected.key == item.key;
    })) {
      _selection.removeWhere((selected) {
        return selected.key == item.key;
      });
    } else {
      _selection.add(item);
    }
    setState(() {});
  }

  void _updateAllSelectableItems(List<dynamic> items) {
    _allSelectableItems.clear();
    _allSelectableItems.addAll(items.whereType<RemoteFile>());
  }

  String _getLink(RemoteFile file, int? seconds) {
    return Main.s3Manager!.getUrl(file.key, validForSeconds: seconds);
  }

  Future<void> _createDirectory(String dir) async {
    setState(() {
      _loading = true;
    });
    await Main.s3Manager!.createDirectory(dir);
    await Main.addWatcher(dir);
    setState(() {
      _loading = false;
    });
  }

  Future<void> _copyFile(String key, String newKey,
      {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    await Main.s3Manager!.copyFile(key, newKey);
    if (File(Main.pathFromKey(key)).existsSync()) {
      if (!File(Main.pathFromKey(newKey)).parent.existsSync()) {
        File(Main.pathFromKey(newKey)).parent.createSync(recursive: true);
      }
      File(Main.pathFromKey(key)).copySync(Main.pathFromKey(newKey));
    }

    RemoteFile oldFile = (Main.remoteFilesMap['${key.split('/').first}/']
        ?.firstWhere((file) => file.key == key))!;
    RemoteFile newFile = RemoteFile(
      key: newKey,
      size: oldFile.size,
      etag: oldFile.etag,
      lastModified: oldFile.lastModified,
    );

    Main.remoteFilesMap['${newKey.split('/').first}/'] = [
      ...(Main.remoteFilesMap['${newKey.split('/').first}/'] ?? [])
          .where((file) {
        return file.key != newKey;
      }),
      newFile,
    ];
    if (refresh) {
      Main.refreshWatchers();
    }
  }

  Future<void> _copyDirectory(String dir, String newDir,
      {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    for (final map in Main.remoteFilesMap.entries) {
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
      Main.refreshWatchers();
    }
  }

  Future<void> _deleteFile(String key, {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    await Main.s3Manager!.deleteFile(key);
    if (File(Main.pathFromKey(key)).existsSync()) {
      File(Main.pathFromKey(key)).deleteSync();
    }
    Main.remoteFilesMap['${key.split('/').first}/'] = [
      ...(Main.remoteFilesMap['${key.split('/').first}/'] ?? []).where((file) {
        return file.key != key;
      }),
    ];
    if (refresh) {
      Main.refreshWatchers();
    }
  }

  Future<void> _deleteS3Directory(String dir, {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    for (final map in Main.remoteFilesMap.entries) {
      for (final file in map.value) {
        if (file.key.startsWith(dir) &&
            file.key != dir &&
            !file.key.endsWith('/')) {
          await Main.s3Manager!.deleteFile(file.key);
          Main.remoteFilesMap['${file.key.split('/').first}/'] = [
            ...(Main.remoteFilesMap['${file.key.split('/').first}/'] ?? [])
                .where((f) {
              return f.key != file.key;
            }),
          ];
        }
      }
      for (final file in map.value) {
        if (file.key.startsWith(dir) &&
            file.key != dir &&
            file.key.endsWith('/')) {
          await Main.s3Manager!.deleteFile(file.key);
          Main.remoteFilesMap['${file.key.split('/').first}/'] = [
            ...(Main.remoteFilesMap['${file.key.split('/').first}/'] ?? [])
                .where((f) {
              return f.key != file.key;
            }),
          ];
        }
      }
    }
    await Main.s3Manager!.deleteFile(dir);
    Main.remoteFilesMap['${dir.split('/').first}/'] = [
      ...(Main.remoteFilesMap['${dir.split('/').first}/'] ?? []).where((file) {
        return file.key != dir;
      }),
    ];
    if (Main.dirs.contains(dir)) {
      Main.dirs.remove(dir);
    }
    if (refresh) {
      Main.refreshWatchers();
    }
  }

  Future<void> _deleteDirectory(String dir, {bool refresh = true}) async {
    setState(() {
      _loading = true;
    });
    await _deleteS3Directory(dir, refresh: false);
    if (Directory(Main.pathFromKey(dir)).existsSync()) {
      Directory(Main.pathFromKey(dir)).deleteSync(recursive: true);
    }
    if (refresh) {
      Main.refreshWatchers();
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
      Main.refreshWatchers();
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
      Main.refreshWatchers();
    }
  }

  void _downloadDirectory(RemoteFile dir, {String? localPath}) {
    for (final map in Main.remoteFilesMap.entries) {
      for (final file in map.value) {
        if (file.key.startsWith(dir.key) &&
            file.key != dir.key &&
            !file.key.endsWith('/')) {
          final relativePath = p.relative(file.key, from: dir.key);
          final localFilePath =
              p.join(localPath ?? Main.pathFromKey(dir.key), relativePath);
          final localFileDir = p.dirname(localFilePath);
          if (!Directory(localFileDir).existsSync()) {
            Directory(localFileDir).createSync(recursive: true);
          }
          if (!File(localFilePath).existsSync()) {
            Main.downloadFile(file, localPath: localFilePath);
          }
        }
      }
    }
  }

  void _cut(RemoteFile? item) {
    if (item != null) {
      _selection.add(item);
    }
    _selectionAction = SelectionAction.cut;
    setState(() {});
  }

  void _copy(RemoteFile? item) {
    if (item != null) {
      _selection.add(item);
    }
    _selectionAction = SelectionAction.copy;
    setState(() {});
  }

  Future<void> _paste() async {
    final selection = _selection.toList();
    for (final item in selection) {
      if (!item.key.endsWith('/')) {
        final file = item;
        final newKey = p.join(_localDir, p.basename(file.key));
        if (_selectionAction == SelectionAction.copy) {
          await _copyFile(file.key, newKey, refresh: false);
        } else if (_selectionAction == SelectionAction.cut) {
          await _moveFile(file.key, newKey, refresh: false);
        }
      } else if (item is String) {
        final dir = item;
        final newDir = p.join(_localDir, p.basename(dir.key));
        if (_selectionAction == SelectionAction.copy) {
          await _copyDirectory(dir.key, newDir, refresh: false);
        } else if (_selectionAction == SelectionAction.cut) {
          await _moveDirectory(dir.key, newDir, refresh: false);
        }
      }
    }
    _selection.clear();
    _selectionAction = SelectionAction.none;
    Main.refreshWatchers();
  }

  void _saveFile(RemoteFile file, String savePath) {
    if (File(savePath).existsSync()) {
      File(savePath).deleteSync();
    }
    // if (!File(_pathFromKey(file.key)).existsSync()) {
    //   if (p.isAbsolute(_pathFromKey(file.key))) {
    //     Main.downloadFile(file);
    //   }
    // }
    // Has to wait for download to finish
    if (File(Main.pathFromKey(file.key)).existsSync()) {
      if (!File(savePath).parent.existsSync()) {
        File(savePath).parent.createSync(recursive: true);
      }
      File(Main.pathFromKey(file.key)).copySync(savePath);
    } else {
      Main.downloadFile(file, localPath: savePath);
    }
  }

  void _saveDirectory(RemoteFile dir, String savePath) {
    if (Directory(savePath).existsSync()) {
      Directory(savePath).deleteSync(recursive: true);
    }
    // if (!Directory(_pathFromKey(dir)).existsSync()) {
    //   if (p.isAbsolute(_pathFromKey(dir))) {
    //     _downloadDirectory(dir);
    //   }
    // }
    // Has to wait for download to finish
    if (Directory(Main.pathFromKey(dir.key)).existsSync()) {
      for (final entity in Directory(Main.pathFromKey(dir.key))
          .listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relativePath =
              p.relative(entity.path, from: Main.pathFromKey(dir.key));
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

  void _uploadDirectory(String key, Directory directory) {
    for (final entity
        in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: directory.path);
        final remoteKey = p.join(key, relativePath).replaceAll('\\', '/');
        Main.uploadFile(remoteKey, entity);
      }
    }
  }

  void _updateCounts() {
    setState(() {
      _dirCount = 0;
      _fileCount = 0;
    });
    if (_localDir == './') {
      _dirCount = Main.dirs.length;
    } else {
      final remoteFiles =
          Main.remoteFilesMap['${_localDir.split('/').first}/'] ?? [];
      _dirCount = remoteFiles
          .where((file) => (file.key.endsWith('/') &&
              p.normalize(p.dirname(file.key)) == p.normalize(_localDir)))
          .length;

      _fileCount = remoteFiles
          .where((file) =>
              !file.key.endsWith('/') &&
              p.normalize(p.dirname(file.key)) == p.normalize(_localDir))
          .length;
    }
    setState(() {});
  }

  Future<void> _showContextMenu(RemoteFile? file) async {
    if (file != null) _focusedKey = (file.key);
    setState(() {});
    showModalBottomSheet(
      context: context,
      enableDrag: true,
      showDragHandle: true,
      constraints: const BoxConstraints(
        maxHeight: 800,
        maxWidth: 800,
      ),
      builder: (context) => file == null
          ? buildBulkContextMenu(
              context,
              _selection.toList(),
              _getLink,
              _downloadDirectory,
              _saveFile,
              _saveDirectory,
              (dir, newDir) => _copyDirectory(dir, newDir, refresh: true),
              (key, newKey) => _moveFile(key, newKey, refresh: true),
              _cut,
              _copy,
              (key) => _deleteFile(key, refresh: true),
              (dir) => _deleteDirectory(dir, refresh: true),
              () {
                _selection.clear();
                setState(() {});
              },
            )
          : file.key.endsWith('/')
              ? buildDirectoryContextMenu(
                  context,
                  file,
                  _downloadDirectory,
                  _saveDirectory,
                  _cut,
                  _copy,
                  (String dir, String newDir) =>
                      _moveDirectory(dir, newDir, refresh: true),
                  (String dir) => _deleteDirectory(dir, refresh: true),
                )
              : buildFileContextMenu(
                  context,
                  file,
                  _getLink,
                  _saveFile,
                  _cut,
                  _copy,
                  (String key, String newKey) =>
                      _moveFile(key, newKey, refresh: true),
                  (String key) => _deleteFile(key, refresh: true),
                ),
    );
  }

  Future<void> _showSearch() async {
    return await showSearch(
      context: context,
      maintainState: true,
      delegate: FileSearchDelegate(
        searchFieldLabel: 'Search in "$_localDir"',
        items: () {
          final allItems = [
            ...Main.dirs,
            ...Main.remoteFilesMap.entries.expand((entry) => entry.value),
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

  Future<void> _init() async {
    // var status = await Permission.manageExternalStorage.status;
    // if (status.isDenied) {
    //   await Permission.manageExternalStorage.request();
    // }

    setState(() {
      _loading = true;
    });
    Main.setLoadingState = (bool loading) {
      setState(() {
        _loading = loading;
      });
    };
    Main.setHomeState = () {
      setState(() {});
    };
    await Main.init(context);
    setState(() {
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void setState(void Function() fn) {
    Main.setConfig(context);
    super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_navIndex == 0)
              _localDir == "./"
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
                                          _localRoot = Main.dirs.contains(
                                                  "${p.normalize(newPath)}/")
                                              ? Main
                                                  .localDirs[Main.dirs.indexOf(
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
                    )
            else if (_navIndex == 1)
              const Text("Completed Jobs")
            else if (_navIndex == 2)
              const Text("Active Jobs")
            else if (_navIndex == 3)
              GestureDetector(
                onTap: () {
                  _showSearch();
                  setState(() {});
                },
                child: _searchquery.isNotEmpty
                    ? Text('Searched "$_searchquery"')
                    : const Text("Search"),
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
                if (Job.completedJobs.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      Job.clearCompleted();
                      setState(() {});
                    },
                    icon: Icon(Icons.delete_sweep),
                  ),
              ]
            : _navIndex == 2
                ? [
                    if (Job.jobs.isNotEmpty)
                      Job.jobs.any((job) => job.running)
                          ? IconButton(
                              onPressed: () {
                                Job.stopall();
                                setState(() {});
                              },
                              icon: Icon(Icons.stop),
                            )
                          : IconButton(
                              onPressed: () {
                                Job.startall();
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
                                    await Main.stopWatchers();
                                    _showContextMenu(null);
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
                                onPressed:
                                    _loading ? null : Main.listDirectories,
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
              children: Main.dirs
                  .map(
                    (dir) => ListTile(
                      leading: Icon(Icons.folder),
                      title: Text(dir.substring(0, dir.length - 1)),
                      subtitle: Main.backupModes.length > Main.dirs.indexOf(dir)
                          ? Text(
                              '${Main.backupModes[Main.dirs.indexOf(dir)].name}: ${Main.localDirs[Main.dirs.indexOf(dir)]}',
                            )
                          : Text("Loading..."),
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
                                    remoteFiles: Main.remoteFilesMap[dir] ?? [],
                                  ),
                                );
                              },
                        icon: const Icon(Icons.more_vert),
                      ),
                      onTap: () {
                        setState(() {
                          _localDir = dir;
                          _localRoot = Main.dirs.contains(dir)
                              ? Main.localDirs[Main.dirs.indexOf(dir)]
                              : _localRoot;
                        });
                        _updateCounts();
                      },
                    ),
                  )
                  .toList(),
            )
          : _localDir != './' && _navIndex == 0
              ? ListView(
                  children: [
                    ListTile(
                      selected: _focusedKey == '..' && _selection.isEmpty,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      selectedColor: Theme.of(context).colorScheme.primary,
                      leading: Icon(Icons.folder),
                      title: Text('../'),
                      onTap: _selection.isNotEmpty &&
                              _selectionAction == SelectionAction.none
                          ? null
                          : () {
                              setState(() {
                                _localDir =
                                    "${Directory(_localDir).parent.path}/";
                                _localRoot = Main.dirs.contains(_localDir)
                                    ? Main
                                        .localDirs[Main.dirs.indexOf(_localDir)]
                                    : _localRoot;
                              });
                              _updateCounts();
                            },
                    ),
                    ...listFiles(
                      context,
                      [
                        ...(Main.remoteFilesMap[
                                    '${_localDir.split('/').first}/'] ??
                                [])
                            .where(
                          (file) =>
                              p.normalize(p.dirname(file.key)) ==
                                  p.normalize(_localDir) &&
                              !Job.jobs.any((job) => job.remoteKey == file.key),
                        ),
                        ...Job.jobs.where(
                          (job) =>
                              p.normalize(p.dirname(job.remoteKey)) ==
                              p.normalize(_localDir),
                        ),
                      ],
                      _sortMode,
                      _foldersFirst,
                      _localDir,
                      _focusedKey,
                      _selection,
                      _selectionAction,
                      () {
                        setState(() {});
                      },
                      (String key) {
                        setState(() {
                          _focusedKey = key;
                        });
                      },
                      (String newDir) {
                        setState(() {
                          _navIndex = 0;
                          _localDir = newDir;
                          _localRoot = Main.dirs.contains(newDir)
                              ? Main.localDirs[Main.dirs.indexOf(newDir)]
                              : _localRoot;
                        });
                        _updateCounts();
                      },
                      _select,
                      (file) async {
                        await Main.stopWatchers();
                        _showContextMenu(file);
                      },
                      _getLink,
                    )
                  ].followedBy([SizedBox(height: 256)]).toList(),
                )
              : _navIndex == 1
                  ? CompletedJobs(
                      completedJobs: Job.completedJobs,
                      onUpdate: () {
                        setState(() {});
                      },
                    )
                  : _navIndex == 2
                      ? ActiveJobs(
                          jobs: Job.jobs,
                          onUpdate: () {
                            setState(() {});
                          },
                        )
                      : ListView(
                          children: listFiles(
                            context,
                            _searchResults,
                            _sortMode,
                            _foldersFirst,
                            _searchdir,
                            _focusedKey,
                            _selection,
                            _selectionAction,
                            () {
                              setState(() {});
                            },
                            (String key) {
                              setState(() {
                                _focusedKey = key;
                              });
                            },
                            (String newDir) {
                              setState(() {
                                _navIndex = 0;
                                _localDir = newDir;
                                _localRoot = Main.dirs.contains(newDir)
                                    ? Main.localDirs[Main.dirs.indexOf(newDir)]
                                    : _localRoot;
                              });
                              _updateCounts();
                            },
                            _select,
                            (file) async {
                              await Main.stopWatchers();
                              _showContextMenu(file);
                            },
                            _getLink,
                          ),
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
                        Main.uploadFile(
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
                      if (Main.remoteFilesMap[_localDir]!.any((file) => [
                                p.join(_localDir, dir),
                                '${p.join(_localDir, dir)}/'
                              ].contains(file.key)) ||
                          Main.remoteFilesMap
                              .containsKey(p.join(_localDir, dir)) ||
                          Main.remoteFilesMap
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
              count: Job.completedJobs.length,
              child: Icon(Icons.done_all),
            ),
            label: 'Completed',
          ),
          BottomNavigationBarItem(
            icon: Badge.count(
              count: Job.jobs.length,
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
