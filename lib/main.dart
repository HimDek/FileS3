import 'dart:io';
import 'dart:async';
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
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/context_menu.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/list_files.dart';
import 'package:files3/settings.dart';
import 'package:files3/globals.dart';
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
    final runningJobs = Job.jobs
        .where((job) => job.status == JobStatus.running)
        .toList();
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
  if (Job.jobs.any((job) => job.status == JobStatus.initialized)) {
    await Future.delayed(const Duration(seconds: 2), () {
      // TODO: Run Jobs?
    });
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
              home: Home(key: globalKey),
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
  final ValueNotifier<double> _progress = ValueNotifier<double>(0.0);
  Profile? _profile;
  RemoteFile _driveDir = RemoteFile(key: '', size: 0, etag: '');
  List<Object> _searchResults = [];
  ListOptions _listOptions = ListOptions(
    sortMode: SortMode.nameAsc,
    viewMode: ViewMode.list,
    foldersFirst: true,
  );
  bool _globalListOptions = true;
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
      return Main.profileFromKey(
        file.key,
      )?.fileManager?.getUrl(file.key, validForSeconds: seconds);
    } catch (e) {
      return null;
    }
  }

  String _dirModified(RemoteFile dir) {
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final file in Main.remoteFiles.where(
      (file) => p.isWithin(dir.key, file.key) && !file.key.endsWith('/'),
    )) {
      if (file.lastModified!.isAfter(latest)) {
        latest = file.lastModified!;
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
          (recursive ||
              p.normalize(p.dirname(file.key)) == p.normalize(dir.key))) {
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
    if (!(IniManager.config?.sections().contains('modes') ?? true)) {
      IniManager.config?.addSection('modes');
    }
    if (mode == null) {
      IniManager.config?.removeOption('modes', key);
    } else {
      IniManager.config?.set('modes', key, mode.value.toString());
      if (mode == BackupMode.sync && p.split(key).length == 1) {
        final toremove = <String>[];
        for (var dir in IniManager.config?.options('modes')?.toList() ?? []) {
          if (p.isWithin(key, dir) && dir != key) {
            toremove.add(dir);
          }
        }
        for (var dir in toremove) {
          IniManager.config?.removeOption('modes', dir);
        }
      }
    }
    IniManager.save();
    setState(() {});
  }

  void _setListOptions(ListOptions options) {
    if (!(IniManager.config?.sections().contains('list_options') ?? true)) {
      IniManager.config?.addSection('list_options');
    }
    IniManager.config?.set(
      'list_options',
      _globalListOptions || _navIndex != 0 ? '/' : _driveDir.key,
      options.toJson(),
    );
    if (_globalListOptions &&
        IniManager.config?.options('list_options')?.contains(_driveDir.key) ==
            true) {
      IniManager.config?.removeOption('list_options', _driveDir.key);
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
            _profile = Main.profileFromKey(_driveDir.key);
            _listOptions = ListOptions.fromJson(
              IniManager.config?.get('list_options', _driveDir.key) ??
                  IniManager.config?.get('list_options', '/') ??
                  '{"sortMode": 0,"viewMode": 0, "foldersFirst": true}',
            );
            if (IniManager.config?.get('list_options', _driveDir.key) != null) {
              _globalListOptions = false;
            } else {
              _globalListOptions = true;
            }
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
      await Main.profileFromKey(dir)!.fileManager!.createDirectory(dir);
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
      showSnackBar(SnackBar(content: Text('Error creating directory: $e')));
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

    RemoteFile oldFile = Main.remoteFiles.firstWhere((file) => file.key == key);
    RemoteFile newFile = RemoteFile(
      key: newKey,
      size: oldFile.size,
      etag: oldFile.etag,
      lastModified: oldFile.lastModified,
    );

    final Profile? profile = Main.profileFromKey(key);
    final Profile? newProfile = Main.profileFromKey(newKey);

    if (profile != newProfile) {
      String downloadTo = Main.pathFromKey(key) ?? key;
      downloadTo = p.isAbsolute(downloadTo)
          ? downloadTo
          : Main.cachePathFromKey(key);
      if (!File(downloadTo).parent.existsSync()) {
        File(downloadTo).parent.createSync(recursive: true);
      }
      // TODO: Download wait and Upload
      // Main.downloadFile(oldFile, localPath: downloadTo);
      // Main.uploadFile(newKey, File(downloadTo));
      return;
    }

    await Main.profileFromKey(key)!.fileManager!.copyFile(key, newKey);

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
    ValueNotifier<double>? progress,
  }) async {
    setState(() {
      _loading.value = true;
    });
    final files = Main.remoteFiles
        .where(
          (file) =>
              p.isWithin(dir, file.key) &&
              file.key != dir &&
              !file.key.endsWith('/'),
        )
        .toList();
    int progressCount = 0;
    final totalFiles = files.length;
    for (final file in files) {
      progressCount += 1;
      (progress ?? _progress).value = progressCount / totalFiles;
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

  Future<void> _deleteFiles(
    List<String> keys, {
    bool refresh = true,
    ValueNotifier<double>? progress,
  }) async {
    setState(() {
      _loading.value = true;
    });

    final List<String> files = Main.remoteFiles
        .where((file) => keys.contains(file.key) && !file.key.endsWith('/'))
        .map((e) => e.key)
        .toList();

    final Map<Profile, List<String>> profileKeys = {};
    for (final key in files) {
      final profile = Main.profileFromKey(key);
      if (profile != null) {
        profileKeys.putIfAbsent(profile, () => []).add(key);
      }
    }

    int progressCount = 0;
    for (final entry in profileKeys.entries) {
      final profile = entry.key;
      final keysForProfile = entry.value;

      await profile.deletionRegistrar.pullDeletions();
      profile.deletionRegistrar.logDeletions(keysForProfile);
      await profile.deletionRegistrar.pushDeletions();

      for (final key in keysForProfile) {
        progressCount += 1;
        (progress ?? _progress).value =
            progressCount / profileKeys.values.expand((e) => e).length;
        await profile.fileManager?.deleteFile(key);
        if (File(Main.pathFromKey(key) ?? key).existsSync()) {
          File(Main.pathFromKey(key) ?? key).deleteSync();
        }
      }

      Main.remoteFiles.removeWhere((file) => keysForProfile.contains(file.key));
    }

    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  Future<void> _deleteS3(
    List<String> keys, {
    bool refresh = true,
    ValueNotifier<double>? progress,
  }) async {
    setState(() {
      _loading.value = true;
    });

    final List<RemoteFile> files = Main.remoteFiles
        .where((file) => keys.contains(file.key))
        .toList();

    final Map<Profile, List<RemoteFile>> profileFiles = {};
    for (final file in files) {
      final profile = Main.profileFromKey(file.key);
      if (profile != null) {
        profileFiles.putIfAbsent(profile, () => []).add(file);
      }
    }

    int progressCount = 0;
    for (final entry in profileFiles.entries) {
      final profile = entry.key;
      final filesForProfile = entry.value;

      await profile.deletionRegistrar.pullDeletions();
      profile.deletionRegistrar.logDeletions(
        filesForProfile.map((e) => e.key).toList(),
      );
      await profile.deletionRegistrar.pushDeletions();

      for (final file
          in filesForProfile
              .where((file) => !file.key.endsWith('/'))
              .toList()) {
        progressCount += 1;
        (progress ?? _progress).value =
            progressCount / profileFiles.values.expand((e) => e).length;
        await profile.fileManager?.deleteFile(file.key);
      }

      Main.remoteFiles.removeWhere(
        (file) =>
            filesForProfile.map((e) => e.key).contains(file.key) &&
            !file.key.endsWith('/'),
      );

      final dirsForProfile = Main.remoteFiles
          .where(
            (file) =>
                filesForProfile.map((e) => e.key).contains(file.key) &&
                file.key.endsWith('/'),
          )
          .toList();
      dirsForProfile.sort((a, b) => b.key.length.compareTo(a.key.length));

      for (final dir in dirsForProfile) {
        progressCount += 1;
        (progress ?? _progress).value =
            progressCount / profileFiles.values.expand((e) => e).length;
        await profile.fileManager?.deleteFile(dir.key);
      }

      Main.remoteFiles.removeWhere(
        (file) => dirsForProfile.map((e) => e.key).contains(file.key),
      );

      await profile.refreshRemote(dir: profile.name);
    }

    if (refresh) {
      setState(() {
        _loading.value = false;
      });
    }
  }

  Future<void> _deleteDirectories(
    List<String> dirs, {
    bool refresh = true,
    ValueNotifier<double>? progress,
  }) async {
    setState(() {
      _loading.value = true;
    });

    _deleteS3(dirs, refresh: false, progress: progress);

    for (final dir
        in dirs
            .map((dir) => Directory(Main.pathFromKey(dir) ?? dir))
            .where((dir) => dir.existsSync())) {
      dir.deleteSync(recursive: true);
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
      _progress.value = (i + 1) * 0.5 / keys.length;
      await _copyFile(keys[i], newKeys[i], refresh: false);
      renameOrCopyAndDelete(
        File(Main.pathFromKey(keys[i]) ?? keys[i]),
        Main.pathFromKey(newKeys[i]) ?? newKeys[i],
      );
    }
    final ValueNotifier<double> progress = ValueNotifier<double>(0.0);
    progress.addListener(() {
      _progress.value = 0.5 + 0.5 * progress.value;
    });
    await _deleteFiles(keys, refresh: false, progress: progress);
    progress.dispose();
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
      final ValueNotifier<double> progress = ValueNotifier<double>(0.0);
      progress.addListener(() {
        _progress.value = (i + 1) * 0.5 * progress.value / dirs.length;
      });
      await _copyDirectory(
        dirs[i],
        newDirs[i],
        refresh: false,
        progress: progress,
      );
      progress.dispose();
    }
    final ValueNotifier<double> progress = ValueNotifier<double>(0.0);
    progress.addListener(() {
      _progress.value = 0.5 + 0.5 * progress.value;
    });
    await _deleteDirectories(dirs, refresh: false, progress: progress);
    progress.dispose();
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
    final files = Main.remoteFiles
        .where(
          (file) =>
              p.isWithin(dir.key, file.key) &&
              file.key != dir.key &&
              !file.key.endsWith('/'),
        )
        .toList();
    int progressCount = 0;
    final totalFiles = files.length;
    for (final file in files) {
      progressCount += 1;
      _progress.value = progressCount / totalFiles;
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
          _profile == null)
      ? null
      : () async {
          try {
            final selection = _selection.toList();
            if (_selectionAction == SelectionAction.copy) {
              final items = selection.where(
                (item) =>
                    p.normalize(p.dirname(item.key)) !=
                    p.normalize(_driveDir.key),
              );
              int progressCount = 0;
              final totalItems = items.length;

              for (final item in items) {
                progressCount += 1;
                _progress.value = progressCount / totalItems;
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
      final files = Directory(
        Main.pathFromKey(dir.key) ?? dir.key,
      ).listSync(recursive: true, followLinks: false);
      int progressCount = 0;
      final totalFiles = files.length;
      for (final entity in files) {
        progressCount += 1;
        _progress.value = progressCount / totalFiles;
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
    final files = directory.listSync(recursive: true, followLinks: false);
    int progressCount = 0;
    final totalFiles = files.length;
    for (final entity in files) {
      progressCount += 1;
      _progress.value = progressCount / totalFiles;
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
                !Job.jobs.any(
                  (job) =>
                      job.remoteKey == file.key &&
                      job.status != JobStatus.completed,
                ),
          ),
          ...Job.jobs.where(
            (job) =>
                p.isWithin(
                  p.normalize(_driveDir.key),
                  p.normalize(job.remoteKey),
                ) &&
                job.status != JobStatus.completed,
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

  Widget _buildContextMenu(BuildContext context, RemoteFile? file) {
    return ValueListenableBuilder<bool>(
      valueListenable: _loading,
      builder: (context, value, _) => SingleChildScrollView(
        child: file == null
            ? buildBulkContextMenu(
                context,
                _selection.toList(),
                _getLink,
                _loading.value ? null : _downloadFile,
                _loading.value ? null : _downloadDirectory,
                _loading.value ? null : _saveFile,
                _loading.value ? null : _saveDirectory,
                _loading.value
                    ? null
                    : (keys, newKeys) async =>
                          await _moveFiles(keys, newKeys, refresh: true),
                _loading.value
                    ? null
                    : (dirs, newDirs) async =>
                          await _moveDirectories(dirs, newDirs, refresh: true),
                _loading.value ? null : _cut,
                _loading.value ? null : _copy,
                _loading.value ? null : _deleteLocal,
                _loading.value ? null : _deleteS3,
                _loading.value
                    ? null
                    : (keys) async => await _deleteFiles(keys, refresh: true),
                _loading.value
                    ? null
                    : (dirs) async =>
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
                _loading.value ? null : _downloadDirectory,
                _loading.value ? null : _saveDirectory,
                _loading.value ? null : _cut,
                _loading.value ? null : _copy,
                _loading.value
                    ? null
                    : (List<String> dirs, List<String> newDirs) async =>
                          await _moveDirectories(dirs, newDirs, refresh: true),
                _loading.value ? null : _deleteLocal,
                _loading.value ? null : _deleteS3,
                _loading.value
                    ? null
                    : (List<String> dirs) async =>
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
                _loading.value ? null : _downloadFile,
                _loading.value ? null : _saveFile,
                _loading.value ? null : _cut,
                _loading.value ? null : _copy,
                _loading.value
                    ? null
                    : (List<String> keys, List<String> newKeys) async =>
                          await _moveFiles(keys, newKeys, refresh: true),
                _loading.value ? null : _deleteLocal,
                _loading.value
                    ? null
                    : (List<String> keys) async =>
                          await _deleteFiles(keys, refresh: true),
              ),
      ),
    );
  }

  Future<void> _showContextMenu(RemoteFile? file) async {
    setState(() {});
    try {
      await showModalBottomSheet(
        context: context,
        enableDrag: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxHeight: 1400, maxWidth: 1400),
        builder: (context) => _buildContextMenu(context, file),
      );
    } catch (e) {
      showSnackBar(SnackBar(content: Text('Error showing context menu: $e')));
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

    await Main.init();

    final uiConfig = ConfigManager.loadUiConfig();
    themeController.update(uiConfig.colorMode);
    ultraDarkController.update(uiConfig.ultraDark);
    _changeDirectory(RemoteFile(key: '', size: 0, etag: ''))?.call();

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
    _searchController.dispose();
    _loading.dispose();
    _progress.dispose();
    _inaccessibleTimer?.cancel();
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
    if (!(_profile?.accessible ?? false) &&
        !(_inaccessibleTimer?.isActive ?? false)) {
      _inaccessibleTimer = Timer.periodic(const Duration(seconds: 5), (
        timer,
      ) async {
        if (!(_profile == null ? true : _profile?.accessible ?? false)) {
          await Main.listDirectories();
        }
        if (!(_profile == null ? true : _profile?.accessible ?? false)) {
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
            RemoteFile(key: p.dirname(_driveDir.key), size: 0, etag: ''),
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
                      if (Job.jobs
                          .where((job) => job.status == JobStatus.completed)
                          .isNotEmpty)
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
                      if (Job.jobs
                          .where((job) => job.status != JobStatus.completed)
                          .isNotEmpty)
                        Job.jobs.any((job) => job.status == JobStatus.running)
                            ? IconButton(
                                onPressed: () {
                                  Job.stopall();
                                  setState(() {});
                                },
                                icon: Icon(Icons.stop),
                              )
                            : IconButton(
                                onPressed: () {
                                  Job.continueAll();
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
                                    ListTile(
                                      dense: true,
                                      enabled: !_loading.value && !_searching,
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
                                      trailing:
                                          _listOptions.sortMode ==
                                              SortMode.nameAsc
                                          ? Icon(Icons.arrow_upward)
                                          : _listOptions.sortMode ==
                                                SortMode.nameDesc
                                          ? Icon(Icons.arrow_downward)
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _listOptions.sortMode =
                                              _listOptions.sortMode ==
                                                  SortMode.nameAsc
                                              ? SortMode.nameDesc
                                              : SortMode.nameAsc;
                                        });
                                        Navigator.of(context).pop();
                                        _setListOptions(_listOptions);
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
                                      trailing:
                                          _listOptions.sortMode ==
                                              SortMode.dateAsc
                                          ? Icon(Icons.arrow_upward)
                                          : _listOptions.sortMode ==
                                                SortMode.dateDesc
                                          ? Icon(Icons.arrow_downward)
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _listOptions.sortMode =
                                              _listOptions.sortMode ==
                                                  SortMode.dateAsc
                                              ? SortMode.dateDesc
                                              : SortMode.dateAsc;
                                        });
                                        Navigator.of(context).pop();
                                        _setListOptions(_listOptions);
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
                                      trailing:
                                          _listOptions.sortMode ==
                                              SortMode.sizeAsc
                                          ? Icon(Icons.arrow_upward)
                                          : _listOptions.sortMode ==
                                                SortMode.sizeDesc
                                          ? Icon(Icons.arrow_downward)
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _listOptions.sortMode =
                                              _listOptions.sortMode ==
                                                  SortMode.sizeAsc
                                              ? SortMode.sizeDesc
                                              : SortMode.sizeAsc;
                                        });
                                        Navigator.of(context).pop();
                                        _setListOptions(_listOptions);
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
                                      trailing:
                                          _listOptions.sortMode ==
                                              SortMode.typeAsc
                                          ? Icon(Icons.arrow_upward)
                                          : _listOptions.sortMode ==
                                                SortMode.typeDesc
                                          ? Icon(Icons.arrow_downward)
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _listOptions.sortMode =
                                              _listOptions.sortMode ==
                                                  SortMode.typeAsc
                                              ? SortMode.typeDesc
                                              : SortMode.typeAsc;
                                        });
                                        Navigator.of(context).pop();
                                        _setListOptions(_listOptions);
                                      },
                                    ),
                                    const PopupMenuDivider(),
                                    if (_driveDir.key != '' || _searching) ...[
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
                                        value: _listOptions.foldersFirst,
                                        onChanged: (value) {
                                          setState(() {
                                            _listOptions.foldersFirst =
                                                value ?? true;
                                          });
                                          Navigator.of(context).pop();
                                          _setListOptions(_listOptions);
                                        },
                                      ),
                                      CheckboxListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.only(
                                          left: 16,
                                          right: 16,
                                        ),
                                        title: Text(
                                          'Grid View',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                        value:
                                            _listOptions.viewMode ==
                                            ViewMode.grid,
                                        onChanged: (value) {
                                          setState(() {
                                            _listOptions.viewMode =
                                                value ?? true
                                                ? ViewMode.grid
                                                : ViewMode.list;
                                          });
                                          Navigator.of(context).pop();
                                          _setListOptions(_listOptions);
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
                                          'Apply Everywhere',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                        value: _globalListOptions,
                                        onChanged: (value) {
                                          setState(() {
                                            _globalListOptions = value ?? true;
                                          });
                                          Navigator.of(context).pop();
                                          _setListOptions(_listOptions);
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
                                (!(_profile?.accessible ?? false)
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
                            (!(_profile == null
                                    ? true
                                    : _profile?.accessible ?? false)
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
                            if (!(_profile == null
                                ? true
                                : _profile?.accessible ?? false))
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
                            if ((_profile == null
                                    ? true
                                    : _profile?.accessible ?? false) &&
                                _loading.value)
                              ValueListenableBuilder<double>(
                                valueListenable: _progress,
                                builder: (context, value, _) =>
                                    LinearProgressIndicator(
                                      value: value <= 0.0 || value >= 1.0
                                          ? null
                                          : value,
                                    ),
                              ),
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
                    sortMode: _listOptions.sortMode,
                    foldersFirst: _listOptions.foldersFirst,
                    gridView: _listOptions.viewMode == ViewMode.grid,
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
                    buildContextMenu: _buildContextMenu,
                    count: _count,
                    dirSize: _dirSize,
                    dirModified: _dirModified,
                    getLink: _getLink,
                  )
                : _driveDir.key == '' && _navIndex == 0
                ? ListFiles(
                    files: () {
                      final files = Set<RemoteFile>.from(
                        Main.remoteFiles
                            .where(
                              (file) =>
                                  p.dirname(file.key).isEmpty &&
                                  file.key.endsWith('/'),
                            )
                            .map<RemoteFile>((file) => file),
                      ).toList();
                      _updateAllSelectableItems(
                        files.whereType<RemoteFile>().toList(),
                      );
                      return files;
                    }(),
                    sortMode: _listOptions.sortMode,
                    foldersFirst: _listOptions.foldersFirst,
                    gridView: _listOptions.viewMode == ViewMode.grid,
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
                    buildContextMenu: _buildContextMenu,
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
                              !Main.ignoreKeyRegexps.any(
                                (regexp) => RegExp(regexp).hasMatch(file.key),
                              ) &&
                              !Job.jobs.any(
                                (job) =>
                                    job.remoteKey == file.key &&
                                    job.status != JobStatus.completed,
                              ),
                        ),
                        ...Job.jobs.where(
                          (job) =>
                              p.normalize(p.dirname(job.remoteKey)) ==
                                  p.normalize(_driveDir.key) &&
                              job.status != JobStatus.completed,
                        ),
                      ];
                      _updateAllSelectableItems(
                        files.whereType<RemoteFile>().toList(),
                      );
                      return files;
                    }(),
                    sortMode: _listOptions.sortMode,
                    foldersFirst: _listOptions.foldersFirst,
                    gridView: _listOptions.viewMode == ViewMode.grid,
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
                    buildContextMenu: _buildContextMenu,
                    count: _count,
                    dirSize: _dirSize,
                    dirModified: _dirModified,
                    getLink: _getLink,
                  )
                : _navIndex == 1
                ? CompletedJobs(
                    completedJobs: Job.jobs
                        .where((job) => job.status == JobStatus.completed)
                        .toList(),
                    onUpdate: () {
                      setState(() {});
                    },
                  )
                : _navIndex == 2
                ? ActiveJobs(
                    jobs: Job.jobs
                        .where((job) => job.status != JobStatus.completed)
                        .toList(),
                    onUpdate: () {
                      setState(() {});
                    },
                  )
                : Container(),
          ],
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              offset:
                  _navIndex == 0 &&
                      !_loading.value &&
                      _selection.isEmpty &&
                      _controlsVisible &&
                      _profile != null &&
                      _profile!.accessible
                  ? const Offset(0, 1)
                  : const Offset(2, 1),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale:
                    _navIndex == 0 &&
                        !_loading.value &&
                        _selection.isEmpty &&
                        _controlsVisible &&
                        _profile != null &&
                        _profile!.accessible
                    ? 1
                    : 0,
                child: FloatingActionButton(
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
              ),
            ),
            SizedBox(height: 16),
            AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              offset:
                  _navIndex == 0 &&
                      !_loading.value &&
                      _selection.isEmpty &&
                      _controlsVisible &&
                      _profile != null &&
                      _profile!.accessible
                  ? const Offset(0, 1)
                  : const Offset(2, 1),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale:
                    _navIndex == 0 &&
                        !_loading.value &&
                        _selection.isEmpty &&
                        _controlsVisible &&
                        _profile != null &&
                        _profile!.accessible
                    ? 1
                    : 0,
                child: FloatingActionButton(
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
              ),
            ),
            SizedBox(height: 16),
            AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              offset:
                  _navIndex == 0 &&
                      !_loading.value &&
                      _selection.isEmpty &&
                      _controlsVisible &&
                      _profile != null &&
                      _profile!.accessible
                  ? const Offset(0, 1)
                  : const Offset(2, 1),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale:
                    _navIndex == 0 &&
                        !_loading.value &&
                        _selection.isEmpty &&
                        _controlsVisible &&
                        _profile != null &&
                        _profile!.accessible
                    ? 1
                    : 0,
                child: FloatingActionButton(
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
              ),
            ),
            AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              offset:
                  _navIndex == 0 &&
                      !_loading.value &&
                      _selection.isEmpty &&
                      _controlsVisible &&
                      _profile == null
                  ? Offset.zero
                  : const Offset(2, 0),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale:
                    _navIndex == 0 &&
                        !_loading.value &&
                        _selection.isEmpty &&
                        _controlsVisible &&
                        _profile == null
                    ? 1
                    : 0,
                child: FloatingActionButton(
                  heroTag: 'add_profile',
                  child: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => S3ConfigPage()),
                    );
                  },
                ),
              ),
            ),
          ],
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
                      icon: Icon(Icons.folder_outlined),
                      activeIcon: Icon(Icons.folder),
                      label: 'Directories',
                    ),
                    BottomNavigationBarItem(
                      icon: Badge.count(
                        isLabelVisible: Job.jobs
                            .where((job) => job.status == JobStatus.completed)
                            .isNotEmpty,
                        count: Job.jobs
                            .where((job) => job.status == JobStatus.completed)
                            .length,
                        child: Icon(Icons.check_circle_outline),
                      ),
                      activeIcon: Badge.count(
                        isLabelVisible: Job.jobs
                            .where((job) => job.status == JobStatus.completed)
                            .isNotEmpty,
                        count: Job.jobs
                            .where((job) => job.status == JobStatus.completed)
                            .length,
                        child: Icon(Icons.check_circle),
                      ),
                      label: 'Completed',
                    ),
                    BottomNavigationBarItem(
                      icon: Badge.count(
                        isLabelVisible: Job.jobs
                            .where((job) => job.status != JobStatus.completed)
                            .isNotEmpty,
                        count: Job.jobs
                            .where((job) => job.status != JobStatus.completed)
                            .length,
                        child: Icon(Icons.swap_vert_circle_outlined),
                      ),
                      activeIcon: Badge.count(
                        isLabelVisible: Job.jobs
                            .where((job) => job.status != JobStatus.completed)
                            .isNotEmpty,
                        count: Job.jobs
                            .where((job) => job.status != JobStatus.completed)
                            .length,
                        child: Icon(Icons.swap_vert_circle),
                      ),
                      label: 'Active',
                    ),
                  ],
                  enableFeedback: true,
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
