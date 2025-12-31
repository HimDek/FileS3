import 'dart:io';
import 'dart:async';
import 'package:files3/globals.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_selector/file_selector.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:files3/utils/context_menu.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/list_files.dart';
import 'package:files3/settings.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';
import 'package:files3/jobs.dart';

/// ===============================
/// SHARED ASYNC JOB
/// ===============================
Future<void> runJob({
  required void Function(double progress) onProgress,
}) async {
  await Main.init(background: true);
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
    await Future.delayed(const Duration(seconds: 2));
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
    await runJob(
      onProgress: (p) {
        FlutterForegroundTask.updateService(
          notificationText: 'Progress ${(p * 100).toInt()}%',
        );
      },
    );

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
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  WidgetsBinding.instance.addObserver(LifecycleWatcher());

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await Workmanager().initialize(callbackDispatcher);
  }

  await IniManager.init();

  runApp(MainApp());
}

class MainApp extends StatelessWidget {
  MainApp({super.key});

  final snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
    showCloseIcon: true,
  );

  ThemeData getLightTheme(ColorScheme? lightScheme) => ThemeData(
    colorScheme: lightScheme ?? ColorScheme.fromSeed(seedColor: Colors.blue),
    useMaterial3: true,
    snackBarTheme: snackBarTheme,
  );

  ThemeData getDarkTheme(ColorScheme? darkScheme) => ThemeData(
    colorScheme:
        darkScheme?.copyWith(
          surface: ultraDarkController.ultraDark
              ? Colors.black
              : darkScheme.surface,
          surfaceDim: ultraDarkController.ultraDark
              ? Colors.black
              : darkScheme.surfaceDim,
        ) ??
        ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
    useMaterial3: true,
    snackBarTheme: snackBarTheme,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([themeController, ultraDarkController]),
      builder: (_, _) {
        return DynamicColorBuilder(
          builder: (lightScheme, darkScheme) {
            return MaterialApp(
              title: 'FileS3',
              theme: themeController.themeMode == ThemeMode.dark
                  ? getDarkTheme(darkScheme)
                  : getLightTheme(lightScheme),
              darkTheme: themeController.themeMode == ThemeMode.light
                  ? getLightTheme(lightScheme)
                  : getDarkTheme(darkScheme),
              home: Home(key: navigatorKey),
            );
          },
        );
      },
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final Set<RemoteFile> _selection = {};
  final List<RemoteFile> _allSelectableItems = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<bool> _loading = ValueNotifier<bool>(true);
  RemoteFile _driveDir = RemoteFile(key: '', size: 0, etag: '');
  List<Object> _searchResults = [];
  bool _foldersFirst = true;
  SortMode _sortMode = SortMode.nameAsc;
  SelectionAction _selectionAction = SelectionAction.none;
  int _dirCount = 0;
  int _fileCount = 0;
  int _navIndex = 0;
  bool _searching = false;
  bool _controlsVisible = true;

  Timer? _inaccessibleTimer;

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

  String? _getLink(RemoteFile file, int? seconds) {
    try {
      return Main.s3Manager!.getUrl(file.key, validForSeconds: seconds);
    } catch (e) {
      return null;
    }
  }

  String _dirModified(RemoteFile dir) {
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final file in Main.remoteFiles) {
      if (p.isWithin(dir.key, file.key) && !file.key.endsWith('/')) {
        if (file.lastModified!.isAfter(latest)) {
          latest = file.lastModified!;
        }
      }
    }

    return timeToReadable(latest);
  }

  (int, int) _count(RemoteFile dir, {bool recursive = false}) {
    int dirCount = 0;
    int fileCount = 0;
    for (final file in Main.remoteFiles) {
      if (p.isWithin(dir.key, file.key) &&
          file.key != dir.key &&
          (recursive || p.dirname(file.key) == p.normalize(dir.key))) {
        if (file.key.endsWith('/')) {
          dirCount += 1;
        } else {
          fileCount += 1;
        }
      }
    }

    return (dirCount, fileCount);
  }

  void _updateCounts() {
    _dirCount = 0;
    _fileCount = 0;

    final counts = _count(
      RemoteFile(
        key: _driveDir.key,
        size: 0,
        etag: '',
        lastModified: DateTime.now(),
      ),
      recursive: false,
    );
    _dirCount = counts.$1;
    _fileCount = counts.$2;
    if (_driveDir.key == '') {
      _fileCount = 0;
    }
  }

  int _dirSize(RemoteFile dir) {
    int size = 0;
    for (final file in Main.remoteFiles) {
      if (p.isWithin(dir.key, file.key)) {
        size += file.size;
      }
    }
    return size;
  }

  void _setBackupMode(String key, BackupMode? mode) {
    if (!IniManager.config!.sections().contains('modes')) {
      IniManager.config!.addSection('modes');
    }
    if (mode == null) {
      IniManager.config!.removeOption('modes', key);
    } else {
      IniManager.config!.set('modes', key, mode.value.toString());
      if (mode == BackupMode.sync && p.split(key).length == 1) {
        final toremove = <String>[];
        for (var dir in IniManager.config!.options('modes')!) {
          if (p.isWithin(key, dir) && dir != key) {
            toremove.add(dir);
          }
        }
        for (var dir in toremove) {
          IniManager.config!.removeOption('modes', dir);
        }
      }
    }
    IniManager.save();
    setState(() {});
  }

  Function()? _changeDirectory(RemoteFile dir) =>
      _selection.any((s) => p.isWithin(s.key, dir.key) || s.key == dir.key)
      ? null
      : () {
          setState(() {
            _navIndex = 0;
            _controlsVisible = true;
            _driveDir = dir;
            for (RemoteFile item in _selection) {
              if (p.isWithin(item.key, _driveDir.key) ||
                  item.key == _driveDir.key) {
                _driveDir = () {
                  String dir = _driveDir.key;
                  while (p.isWithin(item.key, dir) || item.key == dir) {
                    dir = p.dirname(dir);
                    if (dir == '') {
                      break;
                    }
                  }
                  return Main.remoteFiles.firstWhere((file) => file.key == dir);
                }();
              }
            }
          });
        };

  Future<void> _createDirectory(String dir) async {
    setState(() {
      _loading.value = true;
    });
    try {
      await Main.s3Manager!.createDirectory(dir);
      Main.remoteFiles.add(
        RemoteFile(
          key: dir.endsWith('/') ? dir : '$dir/',
          size: 0,
          etag: '',
          lastModified: DateTime.now(),
        ),
      );
      if (p.split(dir).length == 1) {
        await Main.addWatcher(dir);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        navigatorKey.currentContext!,
      ).showSnackBar(SnackBar(content: Text('Error creating directory: $e')));
    }
    setState(() {
      _loading.value = false;
    });
  }

  Future<void> _copyFile(
    String key,
    String newKey, {
    bool refresh = true,
  }) async {
    setState(() {
      _loading.value = true;
    });
    await Main.s3Manager!.copyFile(key, newKey);
    if (File(Main.pathFromKey(key) ?? key).existsSync() &&
        Main.pathFromKey(newKey) != null) {
      if (!File(Main.pathFromKey(newKey) ?? newKey).parent.existsSync()) {
        File(
          Main.pathFromKey(newKey) ?? newKey,
        ).parent.createSync(recursive: true);
      }
      File(
        Main.pathFromKey(key) ?? key,
      ).copySync(Main.pathFromKey(newKey) ?? newKey);
    }

    RemoteFile oldFile = Main.remoteFiles.firstWhere((file) => file.key == key);
    RemoteFile newFile = RemoteFile(
      key: newKey,
      size: oldFile.size,
      etag: oldFile.etag,
      lastModified: oldFile.lastModified,
    );

    Main.remoteFiles.add(newFile);
    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  Future<void> _copyDirectory(
    String dir,
    String newDir, {
    bool refresh = true,
  }) async {
    setState(() {
      _loading.value = true;
    });
    for (final file
        in Main.remoteFiles
            .where(
              (file) =>
                  p.isWithin(dir, file.key) &&
                  file.key != dir &&
                  !file.key.endsWith('/'),
            )
            .toList()) {
      await _copyFile(
        file.key,
        p.join(newDir, p.relative(file.key, from: dir)),
        refresh: false,
      );
    }

    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  void _deleteLocal(String key) {
    if (key.endsWith('/')) {
      if (Directory(Main.pathFromKey(key) ?? key).existsSync()) {
        if (Main.backupMode(key) != BackupMode.upload) {
          _setBackupMode(
            key,
            Main.backupMode(p.dirname(key)) == BackupMode.upload
                ? null
                : BackupMode.upload,
          );
        }
        Directory(Main.pathFromKey(key) ?? key).deleteSync(recursive: true);
      }
    } else {
      if (File(Main.pathFromKey(key) ?? key).existsSync()) {
        if (Main.backupMode(key) != BackupMode.upload) {
          _setBackupMode(
            key,
            Main.backupMode(p.dirname(key)) == BackupMode.upload
                ? null
                : BackupMode.upload,
          );
        }
        File(Main.pathFromKey(key) ?? key).deleteSync();
      }
    }
  }

  Future<void> _deleteFiles(List<String> keys, {bool refresh = true}) async {
    setState(() {
      _loading.value = true;
    });
    await DeletionRegistrar.pullDeletions();
    DeletionRegistrar.logDeletions(keys);
    await DeletionRegistrar.pushDeletions();
    for (final key in keys) {
      await Main.s3Manager!.deleteFile(key);
      if (File(Main.pathFromKey(key) ?? key).existsSync()) {
        File(Main.pathFromKey(key) ?? key).deleteSync();
      }
    }
    Main.remoteFiles.removeWhere((file) => keys.contains(file.key));
    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  Future<void> _deleteS3(List<String> keys, {bool refresh = true}) async {
    setState(() {
      _loading.value = true;
    });

    await DeletionRegistrar.pullDeletions();
    DeletionRegistrar.logDeletions(keys);
    await DeletionRegistrar.pushDeletions();

    for (final file
        in Main.remoteFiles
            .where((file) => keys.contains(file.key) && !file.key.endsWith('/'))
            .toList()) {
      await Main.s3Manager!.deleteFile(file.key);
    }

    Main.remoteFiles.removeWhere(
      (file) => keys.contains(file.key) && !file.key.endsWith('/'),
    );

    final dirs = Main.remoteFiles
        .where((file) => keys.contains(file.key) && file.key.endsWith('/'))
        .toList();
    dirs.sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final file in dirs) {
      await Main.s3Manager!.deleteFile(file.key);
    }

    await Main.refreshRemote();

    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  Future<void> _deleteDirectories(
    List<String> dirs, {
    bool refresh = true,
  }) async {
    setState(() {
      _loading.value = true;
    });
    for (final dir in dirs) {
      final files = Main.remoteFiles
          .where((file) => p.isWithin(dir, file.key))
          .toList();
      await _deleteS3(
        files.map((file) => file.key).toList().followedBy([dir]).toList(),
        refresh: false,
      );
      if (Directory(Main.pathFromKey(dir) ?? dir).existsSync()) {
        Directory(Main.pathFromKey(dir) ?? dir).deleteSync(recursive: true);
      }
    }
    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  Future<void> _moveFiles(
    List<String> keys,
    List<String> newKeys, {
    bool refresh = true,
  }) async {
    setState(() {
      _loading.value = true;
    });
    for (int i = 0; i < keys.length; i++) {
      await _copyFile(keys[i], newKeys[i], refresh: false);
      renameOrCopyAndDelete(
        File(Main.pathFromKey(keys[i]) ?? keys[i]),
        Main.pathFromKey(newKeys[i]) ?? newKeys[i],
      );
    }
    await _deleteFiles(keys, refresh: false);
    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  Future<void> _moveDirectories(
    List<String> dirs,
    List<String> newDirs, {
    bool refresh = true,
  }) async {
    setState(() {
      _loading.value = true;
    });
    for (int i = 0; i < dirs.length; i++) {
      await _copyDirectory(dirs[i], newDirs[i], refresh: false);
    }
    await _deleteDirectories(dirs, refresh: false);
    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  void _downloadFile(RemoteFile file, {String? localPath}) {
    if (!File(Main.pathFromKey(file.key) ?? file.key).existsSync()) {
      if (Main.backupMode(file.key) != BackupMode.sync &&
          (localPath ?? Main.pathFromKey(file.key)) ==
              Main.pathFromKey(file.key)) {
        _setBackupMode(
          file.key,
          Main.backupMode(p.dirname(file.key)) == BackupMode.sync
              ? null
              : BackupMode.sync,
        );
      }
      Main.downloadFile(file, localPath: localPath);
    }
  }

  void _downloadDirectory(RemoteFile dir, {String? localPath}) {
    if (Main.backupMode(dir.key) != BackupMode.sync &&
        (localPath ?? Main.pathFromKey(dir.key)) == Main.pathFromKey(dir.key)) {
      _setBackupMode(
        dir.key,
        Main.backupMode(p.dirname(dir.key)) == BackupMode.sync
            ? null
            : BackupMode.sync,
      );
    }
    for (final file
        in Main.remoteFiles
            .where(
              (file) =>
                  p.isWithin(dir.key, file.key) &&
                  file.key != dir.key &&
                  !file.key.endsWith('/'),
            )
            .toList()) {
      final relativePath = p.relative(file.key, from: dir.key);
      final localFilePath = p.join(
        localPath ?? Main.pathFromKey(dir.key) ?? dir.key,
        relativePath,
      );
      final localFileDir = p.dirname(localFilePath);
      if (!Directory(localFileDir).existsSync()) {
        Directory(localFileDir).createSync(recursive: true);
      }
      if (!File(localFilePath).existsSync()) {
        Main.downloadFile(file, localPath: localFilePath);
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

  Future<void> Function()? _paste() =>
      (_selectionAction == SelectionAction.none ||
          _selection.isEmpty ||
          _navIndex != 0 ||
          (_driveDir.key.isEmpty &&
              _selection.any((item) => !item.key.endsWith('/'))))
      ? null
      : () async {
          try {
            final selection = _selection.toList();
            if (_selectionAction == SelectionAction.copy) {
              for (final item in selection.where(
                (item) =>
                    p.normalize(p.dirname(item.key)) !=
                    p.normalize(_driveDir.key),
              )) {
                final newKey = p.join(_driveDir.key, p.basename(item.key));
                if (item.key == newKey) {
                  continue;
                }
                if (!item.key.endsWith('/')) {
                  await _copyFile(item.key, newKey);
                } else {
                  await _copyDirectory(item.key, newKey);
                }
              }
            } else {
              final dirs = selection
                  .where(
                    (item) =>
                        item.key.endsWith('/') &&
                        p.normalize(p.dirname(item.key)) !=
                            p.normalize(_driveDir.key),
                  )
                  .toList();
              final files = selection
                  .where(
                    (item) =>
                        !item.key.endsWith('/') &&
                        p.normalize(p.dirname(item.key)) !=
                            p.normalize(_driveDir.key),
                  )
                  .toList();
              final dirsDestinations = dirs
                  .map((item) => p.join(_driveDir.key, p.basename(item.key)))
                  .toList();
              final filesDestinations = files
                  .map((item) => p.join(_driveDir.key, p.basename(item.key)))
                  .toList();
              _moveDirectories(
                dirs.map((item) => item.key).toList(),
                dirsDestinations,
              );
              _moveFiles(
                files.map((item) => item.key).toList(),
                filesDestinations,
              );
              _selection.clear();
            }
            _selectionAction = SelectionAction.none;
          } catch (e) {
            showSnackBar(SnackBar(content: Text('Error pasting items: $e')));
          }
        };

  void _saveFile(RemoteFile file, String savePath) {
    if (File(savePath).existsSync()) {
      File(savePath).deleteSync();
    }
    if (File(Main.pathFromKey(file.key) ?? file.key).existsSync()) {
      if (!File(savePath).parent.existsSync()) {
        File(savePath).parent.createSync(recursive: true);
      }
      File(Main.pathFromKey(file.key) ?? file.key).copySync(savePath);
    } else {
      Main.downloadFile(file, localPath: savePath);
    }
  }

  void _saveDirectory(RemoteFile dir, String savePath) {
    if (Directory(savePath).existsSync()) {
      Directory(savePath).deleteSync(recursive: true);
    }
    if (Directory(Main.pathFromKey(dir.key) ?? dir.key).existsSync()) {
      for (final entity in Directory(
        Main.pathFromKey(dir.key) ?? dir.key,
      ).listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relativePath = p.relative(
            entity.path,
            from: Main.pathFromKey(dir.key),
          );
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
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: directory.path);
        final remoteKey = p.join(key, relativePath).replaceAll('\\', '/');
        Main.uploadFile(remoteKey, entity);
      }
    }
  }

  Future<void> _search() async {
    setState(() {
      _loading.value = true;
    });

    _searchResults =
        [
          ...Main.remoteFiles.where(
            (file) =>
                p.isWithin(p.normalize(_driveDir.key), p.normalize(file.key)) &&
                !Job.jobs.any((job) => job.remoteKey == file.key),
          ),
          ...Job.jobs.where(
            (job) => p.isWithin(
              p.normalize(_driveDir.key),
              p.normalize(job.remoteKey),
            ),
          ),
        ].where((item) {
          if (item is RemoteFile) {
            return item.key.toLowerCase().contains(
              _searchController.text.trim().toLowerCase(),
            );
          } else if (item is Job) {
            return item.remoteKey.toLowerCase().contains(
              _searchController.text.trim().toLowerCase(),
            );
          }
          return false;
        }).toList();

    setState(() {
      _loading.value = false;
    });
  }

  Future<void> _showContextMenu(RemoteFile? file) async {
    setState(() {});
    try {
      await showModalBottomSheet(
        context: context,
        enableDrag: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxHeight: 1400, maxWidth: 1400),
        builder: (context) {
          return ValueListenableBuilder<bool>(
            valueListenable: _loading,
            builder: (context, value, _) => value
                ? const Center(child: CircularProgressIndicator())
                : file == null
                ? buildBulkContextMenu(
                    context,
                    _selection.toList(),
                    _getLink,
                    _downloadFile,
                    _downloadDirectory,
                    _saveFile,
                    _saveDirectory,
                    (keys, newKeys) async =>
                        await _moveFiles(keys, newKeys, refresh: true),
                    (dirs, newDirs) async =>
                        await _moveDirectories(dirs, newDirs, refresh: true),
                    _cut,
                    _copy,
                    _deleteLocal,
                    _deleteS3,
                    (keys) async => await _deleteFiles(keys, refresh: true),
                    (dirs) async =>
                        await _deleteDirectories(dirs, refresh: true),
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
                    (List<String> dirs, List<String> newDirs) async =>
                        await _moveDirectories(dirs, newDirs, refresh: true),
                    _deleteLocal,
                    _deleteS3,
                    (List<String> dirs) async =>
                        await _deleteDirectories(dirs, refresh: true),
                    _count,
                    _dirSize,
                    _dirModified,
                    _setBackupMode,
                  )
                : buildFileContextMenu(
                    context,
                    file,
                    _getLink,
                    _downloadFile,
                    _saveFile,
                    _cut,
                    _copy,
                    (List<String> keys, List<String> newKeys) async =>
                        await _moveFiles(keys, newKeys, refresh: true),
                    _deleteLocal,
                    (List<String> keys) async =>
                        await _deleteFiles(keys, refresh: true),
                  ),
          );
        },
      );
    } catch (e) {
      await Main.refreshRemote();
    }

    if (_loading.value) {
      final completer = Completer<void>();
      late VoidCallback listener;
      listener = () {
        if (!completer.isCompleted) {
          _loading.removeListener(listener);
          completer.complete();
        }
      };

      _loading.addListener(listener);
      await completer.future;
    }

    await Main.refreshWatchers();
    setState(() {});
  }

  Future<void> _pushS3ConfigPage() async {
    if (Main.s3Manager == null) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => S3ConfigPage()));
    }
  }

  Future<void> _init() async {
    Permission? permission;
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      permission = sdkInt >= 30
          ? Permission.manageExternalStorage
          : Permission.storage;
    }
    if (permission != null) {
      while (await permission.request().isDenied) {
        showSnackBar(
          SnackBar(
            content: Text(
              'Storage permission is required to use this app.',
              style: TextStyle(color: globalTheme?.colorScheme.onError),
            ),
            backgroundColor: globalTheme?.colorScheme.error,
          ),
        );
      }

      PermissionStatus status = await Permission.manageExternalStorage
          .request();

      if (status.isPermanentlyDenied || status.isRestricted) {
        showSnackBar(
          SnackBar(
            content: Text(
              'Storage permission is required to use this app.',
              style: TextStyle(color: globalTheme?.colorScheme.onError),
            ),
            backgroundColor: globalTheme?.colorScheme.error,
          ),
        );
        await openAppSettings();
      }
    }

    final uiConfig = ConfigManager.loadUiConfig();
    themeController.update(uiConfig.colorMode);
    ultraDarkController.update(uiConfig.ultraDark);

    setState(() {
      _loading.value = true;
    });

    Main.setLoadingState = (bool loading) {
      setState(() {
        _loading.value = loading;
      });
    };
    Main.setHomeState = () {
      setState(() {});
    };
    Main.pushS3ConfigPage = _pushS3ConfigPage;
    await Main.init();

    setState(() {
      _loading.value = false;
    });
  }

  @override
  void initState() {
    _init();
    super.initState();
    _scrollController.addListener(() {
      final direction = _scrollController.position.userScrollDirection;

      if (direction == ScrollDirection.reverse && _controlsVisible) {
        setState(() => _controlsVisible = false);
      } else if (direction == ScrollDirection.forward && !_controlsVisible) {
        setState(() => _controlsVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void setState(void Function() fn) async {
    if (mounted) {
      super.setState(() {
        Main.ensureDirectoryObjects();
        fn();
        _updateCounts();
      });
    }
    if (!Main.accessible && !(_inaccessibleTimer?.isActive ?? false)) {
      _inaccessibleTimer = Timer.periodic(const Duration(seconds: 5), (
        timer,
      ) async {
        if (!Main.accessible) {
          await Main.listDirectories();
        }
        if (Main.accessible) {
          timer.cancel();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          _navIndex == 0 &&
          _driveDir.key.isEmpty &&
          !_searching &&
          _selection.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (_selectionAction != SelectionAction.none) {
          _selectionAction = SelectionAction.none;
          setState(() {});
          return;
        }
        if (_selection.isNotEmpty) {
          _selection.clear();
          setState(() {});
          return;
        }
        if (_searching) {
          _searching = false;
          _selection.clear();
          setState(() {});
          return;
        }
        if (_navIndex != 0) {
          _navIndex = 0;
          _controlsVisible = true;
          setState(() {});
          return;
        }
        if (_driveDir.key.isNotEmpty) {
          _changeDirectory(
            RemoteFile(
              key: p.dirname(_driveDir.key) == '.'
                  ? ''
                  : p.dirname(_driveDir.key),
              size: 0,
              etag: '',
            ),
          )?.call();
          return;
        }
      },
      child: Scaffold(
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              floating: _selection.isEmpty,
              snap: _selection.isEmpty,
              pinned: true,
              actionsPadding: EdgeInsets.only(right: 24, top: 4, bottom: 4),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_navIndex == 0)
                    if (_searching)
                      Form(
                        child: TextFormField(
                          autofocus: true,
                          controller: _searchController,
                          decoration: InputDecoration(
                            visualDensity: VisualDensity.compact,
                            hintText: 'Search',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (value) {
                            _selection.clear();
                            _search();
                          },
                          onFieldSubmitted: (value) {
                            _selection.clear();
                            _search();
                          },
                        ),
                      )
                    else
                      const Text('FileS3')
                  else if (_navIndex == 1)
                    const Text("Completed Jobs")
                  else
                    const Text("Active Jobs"),

                  if (_navIndex == 0)
                    _selection.isNotEmpty
                        ? Text(
                            "${_selectionAction == SelectionAction.none
                                ? ''
                                : _selectionAction == SelectionAction.cut
                                ? 'Moving '
                                : 'Copying '}${_selection.where((item) => item.key.endsWith('/')).isNotEmpty ? '${_selection.where((item) => item.key.endsWith('/')).length} Folders ' : ''}${_selection.where((item) => !item.key.endsWith('/')).isNotEmpty ? '${_selection.where((item) => !item.key.endsWith('/')).length} Files ' : ''}",

                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : _navIndex == 0
                        ? Text(
                            _searching
                                ? "${_searchResults.where((item) => item is RemoteFile && item.key.endsWith('/')).isNotEmpty ? '${_searchResults.where((item) => item is RemoteFile && item.key.endsWith('/')).length} Folders ' : ''}${_searchResults.where((item) => item is RemoteFile && !item.key.endsWith('/')).isNotEmpty ? '${_searchResults.where((item) => item is RemoteFile && !item.key.endsWith('/')).length} Files ' : ''}found"
                                : _dirCount > 0 || _fileCount > 0
                                ? "${_dirCount > 0 ? '$_dirCount Folders ' : ''}${_fileCount > 0 ? '$_fileCount Files' : ''}"
                                : "Empty",
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : SizedBox.shrink(),
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
                          icon: Icon(Icons.clear_all_rounded),
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
                  : _selection.isNotEmpty
                  ? _selectionAction == SelectionAction.none
                        ? [
                            if (_selection.length < _allSelectableItems.length)
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
                            if (!_loading.value)
                              IconButton(
                                onPressed: () async {
                                  await Main.stopWatchers();
                                  await _showContextMenu(null);
                                },
                                icon: Icon(Icons.more_vert),
                              ),
                          ]
                        : [
                            if (!_loading.value)
                              IconButton(
                                onPressed: _paste(),
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
                      if (!_loading.value) ...[
                        if (!_searching ||
                            _searchController.text.trim().isNotEmpty)
                          IconButton(
                            icon: _searching
                                ? Icon(Icons.backspace)
                                : Icon(Icons.search),
                            onPressed: _searching
                                ? () {
                                    _selection.clear();
                                    _searchController.clear();
                                    setState(() {});
                                  }
                                : () async {
                                    _selection.clear();
                                    _searching = true;
                                    _search();
                                  },
                          ),
                        if (_searching)
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searching = false;
                              _selection.clear();
                              setState(() {});
                            },
                          ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () {
                          showMenu(
                            context: context,
                            position: RelativeRect.fromLTRB(1000, 60, 0, 0),
                            menuPadding: EdgeInsets.zero,
                            items: [
                              PopupMenuItem(
                                padding: EdgeInsets.zero,
                                enabled: false,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: 0, width: 128),
                                    if (!_loading.value && !_searching) ...[
                                      ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.only(
                                          left: 16,
                                          right: 16,
                                        ),
                                        titleTextStyle: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                        title: Text('Refresh', maxLines: 1),
                                        trailing: Icon(Icons.refresh),
                                        onTap: () {
                                          Main.listDirectories();
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      const PopupMenuDivider(),
                                    ],
                                    if (_driveDir.key != '' || _searching) ...[
                                      ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.only(
                                          left: 16,
                                          right: 16,
                                        ),
                                        titleTextStyle: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                        title: Text('Name'),
                                        trailing: _sortMode == SortMode.nameAsc
                                            ? Icon(Icons.arrow_upward)
                                            : _sortMode == SortMode.nameDesc
                                            ? Icon(Icons.arrow_downward)
                                            : null,
                                        onTap: () {
                                          setState(() {
                                            _sortMode =
                                                _sortMode == SortMode.nameAsc
                                                ? SortMode.nameDesc
                                                : SortMode.nameAsc;
                                          });
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.only(
                                          left: 16,
                                          right: 16,
                                        ),
                                        titleTextStyle: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                        title: Text('Date'),
                                        trailing: _sortMode == SortMode.dateAsc
                                            ? Icon(Icons.arrow_upward)
                                            : _sortMode == SortMode.dateDesc
                                            ? Icon(Icons.arrow_downward)
                                            : null,
                                        onTap: () {
                                          setState(() {
                                            _sortMode =
                                                _sortMode == SortMode.dateAsc
                                                ? SortMode.dateDesc
                                                : SortMode.dateAsc;
                                          });
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.only(
                                          left: 16,
                                          right: 16,
                                        ),
                                        titleTextStyle: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                        title: Text('Size'),
                                        trailing: _sortMode == SortMode.sizeAsc
                                            ? Icon(Icons.arrow_upward)
                                            : _sortMode == SortMode.sizeDesc
                                            ? Icon(Icons.arrow_downward)
                                            : null,
                                        onTap: () {
                                          setState(() {
                                            _sortMode =
                                                _sortMode == SortMode.sizeAsc
                                                ? SortMode.sizeDesc
                                                : SortMode.sizeAsc;
                                          });
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.only(
                                          left: 16,
                                          right: 16,
                                        ),
                                        titleTextStyle: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                        title: Text('Type'),
                                        trailing: _sortMode == SortMode.typeAsc
                                            ? Icon(Icons.arrow_upward)
                                            : _sortMode == SortMode.typeDesc
                                            ? Icon(Icons.arrow_downward)
                                            : null,
                                        onTap: () {
                                          setState(() {
                                            _sortMode =
                                                _sortMode == SortMode.typeAsc
                                                ? SortMode.typeDesc
                                                : SortMode.typeAsc;
                                          });
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      const PopupMenuDivider(),
                                      CheckboxListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.only(
                                          left: 16,
                                          right: 16,
                                        ),
                                        title: Text(
                                          'Folders First',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                        value: _foldersFirst,
                                        onChanged: (value) {
                                          setState(() {
                                            _foldersFirst = value ?? true;
                                          });
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      const PopupMenuDivider(),
                                    ],
                                    ListTile(
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      contentPadding: EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                      ),
                                      titleTextStyle: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                      title: Text('Settings', maxLines: 1),
                                      trailing: Icon(Icons.settings),
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
              bottom: _navIndex == 0
                  ? PreferredSize(
                      preferredSize: Size.fromHeight(() {
                        return (28 +
                                (_driveDir.key != '' ? 24 : 0) +
                                (Main.pathFromKey(_driveDir.key) != null
                                    ? 16
                                    : 0) +
                                (!Main.accessible
                                    ? 16
                                    : _loading.value
                                    ? 4
                                    : 0))
                            .toDouble();
                      }()),
                      child: SizedBox(
                        width: double.infinity,
                        height:
                            28 +
                            (_driveDir.key != '' ? 24 : 0) +
                            (Main.pathFromKey(_driveDir.key) != null ? 16 : 0) +
                            (!Main.accessible
                                ? 16
                                : _loading.value
                                ? 4
                                : 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                left: 16,
                                right: 16,
                                top: 4,
                                bottom: 8,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        Text(
                                          _dirModified(_driveDir),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          bytesToReadable(_dirSize(_driveDir)),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          () {
                                            final count = _count(
                                              _driveDir,
                                              recursive: true,
                                            );
                                            if (count.$1 == 0) {
                                              return '${count.$2} files';
                                            }
                                            if (count.$2 == 0) {
                                              return '${count.$1} subfolders';
                                            }
                                            return '${count.$2} files in ${count.$1} subfolders';
                                          }(),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_driveDir.key != '')
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children:
                                            <Widget>[
                                                  GestureDetector(
                                                    onTap:
                                                        (_selection
                                                                .isNotEmpty &&
                                                            _selectionAction ==
                                                                SelectionAction
                                                                    .none)
                                                        ? null
                                                        : _changeDirectory(
                                                            RemoteFile(
                                                              key: '',
                                                              size: 0,
                                                              etag: '',
                                                            ),
                                                          ),
                                                    child: Text(
                                                      'FileS3',
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodyLarge,
                                                    ),
                                                  ),
                                                ]
                                                .followedBy(
                                                  _driveDir.key
                                                      .split('/')
                                                      .where(
                                                        (dir) => dir.isNotEmpty,
                                                      )
                                                      .map(
                                                        (
                                                          dir,
                                                        ) => GestureDetector(
                                                          onTap:
                                                              (_selection
                                                                      .isNotEmpty &&
                                                                  _selectionAction ==
                                                                      SelectionAction
                                                                          .none)
                                                              ? null
                                                              : () {
                                                                  String
                                                                  newPath = '';
                                                                  for (final part
                                                                      in _driveDir
                                                                          .key
                                                                          .split(
                                                                            '/',
                                                                          )) {
                                                                    if (part
                                                                        .isEmpty) {
                                                                      continue;
                                                                    }
                                                                    newPath +=
                                                                        '$part/';
                                                                    if (part ==
                                                                        dir) {
                                                                      break;
                                                                    }
                                                                  }
                                                                  _changeDirectory(
                                                                    Main.remoteFiles.firstWhere(
                                                                      (file) =>
                                                                          p.normalize(
                                                                            file.key,
                                                                          ) ==
                                                                          p.normalize(
                                                                            newPath,
                                                                          ),
                                                                    ),
                                                                  )?.call();
                                                                },
                                                          child: Text(
                                                            dir,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .bodyLarge,
                                                          ),
                                                        ),
                                                      )
                                                      .map(
                                                        (widget) => Row(
                                                          children: [
                                                            const Icon(
                                                              Icons
                                                                  .chevron_right,
                                                              size: 16,
                                                            ),
                                                            widget,
                                                          ],
                                                        ),
                                                      ),
                                                )
                                                .toList(),
                                      ),
                                    ),
                                  if (Main.pathFromKey(_driveDir.key) != null)
                                    Row(
                                      children: [
                                        Text(
                                          '${Main.backupMode(_driveDir.key).name}: ',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                        SizedBox(width: 4),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: GestureDetector(
                                              child: Text(
                                                Main.pathFromKey(
                                                      _driveDir.key,
                                                    ) ??
                                                    '',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelSmall,
                                              ),
                                              onTap: () {
                                                // TODO: Open file explorer at this location
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            if (!Main.accessible)
                              Container(
                                width: double.infinity,
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                alignment: Alignment.center,
                                child: Text(
                                  'Remote access failed!',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                      ),
                                ),
                              ),
                            if (Main.accessible && _loading.value)
                              LinearProgressIndicator(),
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
            _searching && _navIndex == 0
                ? ListFiles(
                    files: () {
                      _updateAllSelectableItems(
                        _searchResults.whereType<RemoteFile>().toList(),
                      );
                      return _searchResults;
                    }(),
                    sortMode: _sortMode,
                    foldersFirst: _foldersFirst,
                    relativeto: _driveDir,
                    selection: _selection,
                    selectionAction: _selectionAction,
                    onUpdate: () {
                      setState(() {});
                    },
                    changeDirectory: _changeDirectory,
                    select: _select,
                    showContextMenu: (file) async {
                      await Main.stopWatchers();
                      await _showContextMenu(file);
                    },
                    count: _count,
                    dirSize: _dirSize,
                    dirModified: _dirModified,
                    getLink: _getLink,
                  )
                : _driveDir.key == '' && _navIndex == 0
                ? ListFiles(
                    files: () {
                      return Set<RemoteFile>.from(
                        Main.remoteFiles
                            .where(
                              (file) =>
                                  p.dirname(file.key) == '.' &&
                                  file.key.endsWith('/'),
                            )
                            .map<RemoteFile>((file) => file),
                      ).toList();
                    }(),
                    sortMode: _sortMode,
                    foldersFirst: _foldersFirst,
                    relativeto: _driveDir,
                    selection: _selection,
                    selectionAction: _selectionAction,
                    onUpdate: () {
                      setState(() {});
                    },
                    changeDirectory: _changeDirectory,
                    select: _select,
                    showContextMenu: (file) async {
                      await Main.stopWatchers();
                      await _showContextMenu(file);
                    },
                    count: _count,
                    dirSize: _dirSize,
                    dirModified: _dirModified,
                    getLink: _getLink,
                  )
                : _driveDir.key != '' && _navIndex == 0
                ? ListFiles(
                    files: () {
                      final files = [
                        ...Main.remoteFiles.where(
                          (file) =>
                              p.normalize(p.dirname(file.key)) ==
                                  p.normalize(_driveDir.key) &&
                              !Job.jobs.any((job) => job.remoteKey == file.key),
                        ),
                        ...Job.jobs.where(
                          (job) =>
                              p.normalize(p.dirname(job.remoteKey)) ==
                              p.normalize(_driveDir.key),
                        ),
                      ];
                      _updateAllSelectableItems(
                        files.whereType<RemoteFile>().toList(),
                      );
                      return files;
                    }(),
                    sortMode: _sortMode,
                    foldersFirst: _foldersFirst,
                    relativeto: _driveDir,
                    selection: _selection,
                    selectionAction: _selectionAction,
                    onUpdate: () {
                      setState(() {});
                    },
                    changeDirectory: _changeDirectory,
                    select: _select,
                    showContextMenu: (file) async {
                      await Main.stopWatchers();
                      await _showContextMenu(file);
                    },
                    count: _count,
                    dirSize: _dirSize,
                    dirModified: _dirModified,
                    getLink: _getLink,
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
                : Container(),
          ],
        ),
        floatingActionButton: AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset:
              _navIndex == 0 &&
                  !_loading.value &&
                  _selection.isEmpty &&
                  _controlsVisible
              ? Offset.zero
              : const Offset(2, 0),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale:
                _navIndex == 0 &&
                    !_loading.value &&
                    _selection.isEmpty &&
                    _controlsVisible
                ? 1
                : 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_driveDir.key != '')
                  FloatingActionButton(
                    heroTag: 'upload_file',
                    child: const Icon(Icons.file_upload_outlined),
                    onPressed: () async {
                      final XFile? file = await openFile();
                      if (file != null) {
                        Main.uploadFile(
                          p.join(_driveDir.key, p.basename(file.path)),
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
                        p.join(_driveDir.key, p.basename(directoryPath)),
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
                      if (Main.remoteFiles.any(
                        (file) => [
                          p.join(_driveDir.key, dir),
                          '${p.join(_driveDir.key, dir)}/',
                        ].contains(file.key),
                      )) {
                        showSnackBar(
                          SnackBar(
                            content: Text(
                              'Directory "${p.join(_driveDir.key, dir)}" already exists.',
                            ),
                          ),
                        );
                        return;
                      }
                      await _createDirectory(p.join(_driveDir.key, dir));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _controlsVisible ? kBottomNavigationBarHeight + 24 : 0,
          child: Wrap(
            children: [
              SizedBox(
                height: kBottomNavigationBarHeight + 24,
                child: BottomNavigationBar(
                  items: [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.folder),
                      label: 'Directories',
                    ),
                    BottomNavigationBarItem(
                      icon: Badge.count(
                        isLabelVisible: Job.completedJobs.isNotEmpty,
                        count: Job.completedJobs.length,
                        child: Icon(Icons.done_all),
                      ),
                      label: 'Completed',
                    ),
                    BottomNavigationBarItem(
                      icon: Badge.count(
                        isLabelVisible: Job.jobs.isNotEmpty,
                        count: Job.jobs.length,
                        child: Icon(Icons.swap_vert),
                      ),
                      label: 'Active',
                    ),
                  ],
                  currentIndex: _navIndex,
                  onTap: (index) async {
                    setState(() {
                      _navIndex = index;
                      _controlsVisible = true;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
