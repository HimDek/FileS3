import 'dart:io';
import 'dart:async';
import 'package:files3/browser.dart';
import 'package:files3/media_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:receive_intent/receive_intent.dart' as receive_intent;
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';

/// ===============================
/// SHARED ASYNC JOB
/// ===============================
Future<void> runJob({
  required void Function(double progress) onProgress,
}) async {
  await Main.init(background: true);
  Job.onProgressUpdate.addListener(() {
    final runningJobs = Job.jobs.value
        .where((job) => job.status.value == JobStatus.running)
        .toList();
    if (runningJobs.isEmpty) {
      onProgress(1.0);
      return;
    }
    double totalProgress = 0.0;
    for (final job in runningJobs) {
      totalProgress += job.bytesCompleted.value / job.bytes;
    }
    onProgress(totalProgress / runningJobs.length);
  });
  if (Job.jobs.value.any((job) => job.status.value == JobStatus.initialized)) {
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
  late StreamSubscription _intentSub;
  final ValueNotifier<List<String>> _sharedFiles = ValueNotifier<List<String>>(
    [],
  );
  final ValueNotifier<String?> _openedFile = ValueNotifier<String?>(null);

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
  }

  Future<void> _createDirectory(String dir) async {
    loading.value = true;
    try {
      await Main.profileFromKey(dir)!.fileManager!.createDirectory(dir);
      Main.remoteFilesAdd(
        RemoteFile(
          key: p.asDir(dir),
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
    loading.value = false;
  }

  Future<void> _copyFile(
    String key,
    String newKey, {
    bool refresh = true,
  }) async {
    loading.value = true;

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

    Main.remoteFilesAdd(newFile);
    if (refresh) {
      loading.value = false;
    }
  }

  Future<void> _copyDirectory(
    String dir,
    String newDir, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;
    final files = Main.remoteFiles
        .where(
          (file) =>
              p.isWithin(dir, file.key) &&
              file.key != dir &&
              !p.isDir(file.key),
        )
        .toList();
    int progressCount = 0;
    final totalFiles = files.length;
    for (final file in files) {
      progressCount += 1;
      (preprogress ?? progress).value = progressCount / totalFiles;
      await _copyFile(
        file.key,
        p.s3(p.join(newDir, p.relative(file.key, from: dir))),
        refresh: false,
      );
    }

    if (refresh) {
      loading.value = false;
    }
  }

  void _deleteLocal(String key) {
    if (p.isDir(key)) {
      if (Directory(Main.pathFromKey(key) ?? key).existsSync()) {
        if (Main.backupModeFromKey(key) != BackupMode.upload) {
          _setBackupMode(
            key,
            Main.backupModeFromKey(p.s3(p.dirname(key))) == BackupMode.upload
                ? null
                : BackupMode.upload,
          );
        }
        Directory(Main.pathFromKey(key) ?? key).deleteSync(recursive: true);
      }
    } else {
      if (File(Main.pathFromKey(key) ?? key).existsSync()) {
        if (Main.backupModeFromKey(key) != BackupMode.upload) {
          _setBackupMode(
            key,
            Main.backupModeFromKey(p.s3(p.dirname(key))) == BackupMode.upload
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
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    final List<String> files = Main.remoteFiles
        .where((file) => keys.contains(file.key) && !p.isDir(file.key))
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
        (preprogress ?? progress).value =
            progressCount / profileKeys.values.expand((e) => e).length;
        await profile.fileManager?.deleteFile(key);
        if (File(Main.pathFromKey(key) ?? key).existsSync()) {
          File(Main.pathFromKey(key) ?? key).deleteSync();
        }
      }

      Main.remoteFilesRemoveWhere((file) => keysForProfile.contains(file.key));
    }

    if (refresh) {
      loading.value = false;
    }
  }

  Future<void> _deleteS3(
    List<String> keys, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    final List<RemoteFile> files = Main.remoteFiles
        .where(
          (file) => keys.contains(file.key) || !p.isDir(file.key)
              ? keys.any((d) => p.isWithin(d, file.key))
              : false,
        )
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
          in filesForProfile.where((file) => !p.isDir(file.key)).toList()) {
        progressCount += 1;
        (preprogress ?? progress).value =
            progressCount / profileFiles.values.expand((e) => e).length;
        await profile.fileManager?.deleteFile(file.key);
      }

      Main.remoteFilesRemoveWhere(
        (file) =>
            filesForProfile.map((e) => e.key).contains(file.key) &&
            !p.isDir(file.key),
      );

      final dirsForProfile = Main.remoteFiles
          .where(
            (file) =>
                filesForProfile.map((e) => e.key).contains(file.key) &&
                p.isDir(file.key),
          )
          .toList();
      dirsForProfile.sort((a, b) => b.key.length.compareTo(a.key.length));

      for (final dir in dirsForProfile) {
        progressCount += 1;
        (preprogress ?? progress).value =
            progressCount / profileFiles.values.expand((e) => e).length;
        await profile.fileManager?.deleteFile(dir.key);
      }

      Main.remoteFilesRemoveWhere(
        (file) => dirsForProfile.map((e) => e.key).contains(file.key),
      );

      await profile.refreshRemote(dir: profile.name);
    }

    if (refresh) {
      loading.value = false;
    }
  }

  Future<void> _deleteDirectories(
    List<String> dirs, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    await _deleteS3(dirs, refresh: false, preprogress: preprogress ?? progress);

    for (final dir
        in dirs
            .map((dir) => Directory(Main.pathFromKey(dir) ?? dir))
            .where((dir) => dir.existsSync())) {
      dir.deleteSync(recursive: true);
    }

    if (refresh) {
      loading.value = false;
    }
  }

  Future<void> _moveFiles(
    List<String> keys,
    List<String> newKeys, {
    bool refresh = true,
  }) async {
    loading.value = true;
    for (int i = 0; i < keys.length; i++) {
      progress.value = (i + 1) * 0.5 / keys.length;
      await _copyFile(keys[i], newKeys[i], refresh: false);
      renameOrCopyAndDelete(
        File(Main.pathFromKey(keys[i]) ?? keys[i]),
        Main.pathFromKey(newKeys[i]) ?? newKeys[i],
      );
    }
    final ValueNotifier<double> preprogress = ValueNotifier<double>(0.0);
    preprogress.addListener(() {
      progress.value = 0.5 + 0.5 * preprogress.value;
    });
    await _deleteFiles(keys, refresh: false, preprogress: preprogress);
    preprogress.dispose();
    if (refresh) {
      loading.value = false;
    }
  }

  Future<void> _moveDirectories(
    List<String> dirs,
    List<String> newDirs, {
    bool refresh = true,
  }) async {
    loading.value = true;
    for (int i = 0; i < dirs.length; i++) {
      final ValueNotifier<double> preprogress = ValueNotifier<double>(0.0);
      preprogress.addListener(() {
        progress.value = (i + 1) * 0.5 * preprogress.value / dirs.length;
      });
      await _copyDirectory(
        dirs[i],
        newDirs[i],
        refresh: false,
        preprogress: preprogress,
      );
      preprogress.dispose();
    }
    final ValueNotifier<double> preprogress = ValueNotifier<double>(0.0);
    preprogress.addListener(() {
      progress.value = 0.5 + 0.5 * preprogress.value;
    });
    await _deleteDirectories(dirs, refresh: false, preprogress: preprogress);
    preprogress.dispose();
    if (refresh) {
      loading.value = false;
    }
  }

  void _downloadFile(RemoteFile file, {String? localPath}) {
    if (!File(Main.pathFromKey(file.key) ?? file.key).existsSync()) {
      if (Main.backupModeFromKey(file.key) != BackupMode.sync &&
          (localPath ?? Main.pathFromKey(file.key)) ==
              Main.pathFromKey(file.key)) {
        _setBackupMode(
          file.key,
          Main.backupModeFromKey(p.s3(p.dirname(file.key))) == BackupMode.sync
              ? null
              : BackupMode.sync,
        );
      }
      Main.downloadFile(file, localPath: localPath);
    }
  }

  void _downloadDirectory(RemoteFile dir, {String? localPath}) {
    if (Main.backupModeFromKey(dir.key) != BackupMode.sync &&
        (localPath ?? Main.pathFromKey(dir.key)) == Main.pathFromKey(dir.key)) {
      _setBackupMode(
        dir.key,
        Main.backupModeFromKey(p.s3(p.dirname(dir.key))) == BackupMode.sync
            ? null
            : BackupMode.sync,
      );
    }
    final files = Main.remoteFiles
        .where(
          (file) =>
              p.isWithin(dir.key, file.key) &&
              file.key != dir.key &&
              !p.isDir(file.key) &&
              Main.ignoreKeyRegexps.every(
                (String regexp) => !RegExp(regexp).hasMatch(file.key),
              ),
        )
        .toList();
    int progressCount = 0;
    final totalFiles = files.length;
    for (final file in files) {
      progressCount += 1;
      progress.value = progressCount / totalFiles;
      final relativePath = p.s3(p.relative(file.key, from: dir.key));
      final localFilePath = p.join(
        localPath ?? Main.pathFromKey(dir.key) ?? dir.key,
        relativePath,
      );
      final localFileDir = p.s3(p.dirname(localFilePath));
      if (!Directory(localFileDir).existsSync()) {
        Directory(localFileDir).createSync(recursive: true);
      }
      if (!File(localFilePath).existsSync()) {
        Main.downloadFile(file, localPath: localFilePath);
      }
    }
  }

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
        progress.value = progressCount / totalFiles;
        if (entity is File) {
          final relativePath = p.s3(
            p.relative(entity.path, from: Main.pathFromKey(dir.key)),
          );
          final newFilePath = p.join(savePath, relativePath);
          final newFileDir = p.s3(p.dirname(newFilePath));
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
      progress.value = progressCount / totalFiles;
      if (entity is File) {
        final relativePath = p.s3(
          p.relative(entity.path, from: directory.path),
        );
        final remoteKey = p
            .join(key, relativePath)
            .replaceAll('\\', p.separator);
        Main.uploadFile(remoteKey, entity);
      }
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

    loading.value = true;

    await Main.init();

    final uiConfig = ConfigManager.loadUiConfig();
    themeController.update(uiConfig.colorMode);
    ultraDarkController.update(uiConfig.ultraDark);

    loading.value = false;
  }

  Future<void> _handleIntent(receive_intent.Intent? intent) async {
    if (intent == null) return;

    switch (intent.action) {
      case 'android.intent.action.SEND':
        final uri = intent.extra?['android.intent.extra.STREAM'];

        if (uri != null) {
          final File file = await uriToFile(uri);
          _sharedFiles.value = [file.path];
        }
        break;

      case 'android.intent.action.SEND_MULTIPLE':
        final uris = intent.extra?['android.intent.extra.STREAM'];

        if (uris is List) {
          _sharedFiles.value = await Future.wait(
            uris.map((e) async {
              return (await uriToFile(e)).path;
            }),
          );
        }
        break;

      case 'android.intent.action.VIEW':
        final uri = intent.data;

        if (uri != null) {
          _openedFile.value = uri;
        }
        break;
    }
  }

  @override
  void initState() {
    _init();
    super.initState();

    _sharedFiles.addListener(() async {
      List<String> sharedFiles = _sharedFiles.value;
      if (sharedFiles.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PathPicker(
              title: Text('Select Upload Location'),
              subtitle: SingleChildScrollView(
                child: Text(
                  '${sharedFiles.length} file${sharedFiles.length > 1 ? 's' : ''}: ${sharedFiles.map((e) => p.basename(e)).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              onInit: RegExp(r'^[a-zA-Z]+://').hasMatch(sharedFiles.first)
                  ? () async {
                      loading.value = true;
                      int totalCount = sharedFiles.length;
                      int progressCount = 0;
                      sharedFiles = await Future.wait(
                        sharedFiles.map((e) async {
                          String f = (await uriToFile(
                            e,
                            onProgress: (d, t) => progress.value =
                                (progressCount + d / t) / totalCount,
                          )).path;
                          progressCount += 1;
                          return f;
                        }),
                      );
                      loading.value = false;
                    }
                  : null,
              onPick: (path) async {
                loading.value = true;
                for (final sharedFile in sharedFiles) {
                  final fileName = p.basename(sharedFile);
                  final remoteKey = p
                      .join(path.key, fileName)
                      .replaceAll('\\', '/');
                  await Main.uploadFile(remoteKey, File(sharedFile));
                }
                loading.value = false;
              },
            ),
          ),
        );
        _sharedFiles.value = [];
        receive_intent.ReceiveIntent.setResult(200);
      }
    });

    _openedFile.addListener(() async {
      String? openedFile = _openedFile.value;
      if (openedFile != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ExternalFileView(
              path: openedFile,
              upload: () {
                _sharedFiles.value = [openedFile];
              },
            ),
          ),
        );
        _openedFile.value = null;
        receive_intent.ReceiveIntent.setResult(200);
      }
    });

    _intentSub = receive_intent.ReceiveIntent.receivedIntentStream.listen(
      (intent) {
        _handleIntent(intent);
      },
      onError: (err) {
        showSnackBar(SnackBar(content: Text('Error receiving intent: $err')));
        receive_intent.ReceiveIntent.setResult(500);
      },
    );

    receive_intent.ReceiveIntent.getInitialIntent().then((intent) {
      if (intent != null) {
        _handleIntent(intent);
      }
    });
  }

  @override
  void dispose() {
    _intentSub.cancel();
    _sharedFiles.dispose();
    _openedFile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MyBrowser(
      title: Text('FileS3'),
      setBackupMode: _setBackupMode,
      downloadFile: _downloadFile,
      downloadDirectory: _downloadDirectory,
      saveFile: _saveFile,
      saveDirectory: _saveDirectory,
      copyFile: _copyFile,
      copyDirectory: _copyDirectory,
      moveFiles: _moveFiles,
      moveDirectories: _moveDirectories,
      deleteLocal: _deleteLocal,
      deleteFiles: _deleteFiles,
      deleteDirectories: _deleteDirectories,
      createDirectory: _createDirectory,
      uploadDirectory: _uploadDirectory,
    );
  }
}
