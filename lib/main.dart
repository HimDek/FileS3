import 'dart:io';
import 'dart:async';
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
import 'package:files3/utils/job.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/browser.dart';
import 'package:files3/media_view.dart';

/// ===============================
/// SHARED ASYNC JOB
/// ===============================
Future<void> runJob({
  required void Function(double progress) onProgress,
}) async {
  await Main.init(background: true);
  Job.onProgressUpdate.addListener(() {
    if (Job.runningJobs.isEmpty) {
      onProgress(1.0);
      return;
    }
    double totalProgress = 0.0;
    for (final job in Job.runningJobs) {
      totalProgress += job.bytesCompleted.value / job.bytes;
    }
    onProgress(totalProgress / Job.runningJobs.length);
  });
  if (Job.pendingJobs.isNotEmpty) {
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

  final inputDecorationTheme = InputDecorationThemeData(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(32)),
    alignLabelWithHint: true,
  );

  ThemeData getLightTheme(ColorScheme? lightScheme) => ThemeData(
    colorScheme: lightScheme ?? ColorScheme.fromSeed(seedColor: Colors.blue),
    useMaterial3: true,
    snackBarTheme: snackBarTheme,
    inputDecorationTheme: inputDecorationTheme,
  );

  ThemeData getDarkTheme(ColorScheme? darkScheme) => ThemeData(
    colorScheme:
        darkScheme?.copyWith(
          surface: uiConfigNotifier.ultraDark.value
              ? Colors.black
              : darkScheme.surface,
          surfaceDim: uiConfigNotifier.ultraDark.value
              ? Colors.black
              : darkScheme.surfaceDim,
        ) ??
        ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
    useMaterial3: true,
    snackBarTheme: snackBarTheme,
    inputDecorationTheme: inputDecorationTheme,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        uiConfigNotifier.colorMode,
        uiConfigNotifier.accentColor,
        uiConfigNotifier.ultraDark,
      ]),
      builder: (context, child) {
        return DynamicColorBuilder(
          builder: (lightScheme, darkScheme) {
            return MaterialApp(
              title: 'FileS3',
              theme: getLightTheme(
                uiConfigNotifier.accentColor.value != null
                    ? ColorScheme.fromSeed(
                        seedColor: uiConfigNotifier.accentColor.value!,
                        primary: uiConfigNotifier.accentColor.value!,
                      )
                    : lightScheme,
              ),
              darkTheme: getDarkTheme(
                uiConfigNotifier.accentColor.value != null
                    ? ColorScheme.fromSeed(
                        seedColor: uiConfigNotifier.accentColor.value!,
                        primary: uiConfigNotifier.accentColor.value!,
                        brightness: Brightness.dark,
                      )
                    : darkScheme,
              ),
              themeMode: uiConfigNotifier.colorMode.value,
              home: child,
            );
          },
        );
      },
      child: Home(key: globalKey),
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

  Future<void> _createDirectory(String dir) async {
    loading.value = true;
    try {
      await Main.profileFromKey(dir)!.fileManager!.createDirectory(dir);
      Main.remoteFilesAdd(RemoteFile(key: p.asDir(dir), etag: ''));
      if (p.split(dir).length == 1) {
        await Main.addWatcher(dir);
      }
    } catch (e) {
      showSnackBar(SnackBar(content: Text('Error creating directory: $e')));
    }
    loading.value = false;
  }

  void _deleteLocal(String key) {
    if (p.isDir(key)) {
      final dir = Directory(Main.pathFromKey(key) ?? key);
      if (dir.existsSync()) {
        if (Main.backupModeFromKey(key) != BackupMode.upload) {
          ConfigManager.setBackupMode(
            key,
            Main.backupModeFromKey(p.s3(p.dirname(key))) == BackupMode.upload
                ? null
                : BackupMode.upload,
          );
        }
        dir.deleteSync(recursive: true);
      }
      final cacheDir = Directory(Main.cachePathFromKey(key));
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
      }
    } else {
      final file = File(Main.pathFromKey(key) ?? key);
      if (file.existsSync()) {
        if (Main.backupModeFromKey(key) != BackupMode.upload) {
          ConfigManager.setBackupMode(
            key,
            Main.backupModeFromKey(p.s3(p.dirname(key))) == BackupMode.upload
                ? null
                : BackupMode.upload,
          );
        }
        file.deleteSync();
      }
      final cacheFile = File(Main.cachePathFromKey(key));
      if (cacheFile.existsSync()) {
        cacheFile.deleteSync();
      }
    }
  }

  void _deleteCache(String key) {
    final FileSystemEntity e = p.isDir(key)
        ? Directory(Main.cachePathFromKey(key))
        : File(Main.cachePathFromKey(key));
    if (e.existsSync()) {
      e.deleteSync(recursive: true);
    }
  }

  void _downloadFile(RemoteFile file, {String? localPath}) {
    final mfile = File(Main.pathFromKey(file.key) ?? file.key);
    final cacheFile = File(Main.cachePathFromKey(file.key));

    if (!mfile.existsSync()) {
      if (Main.backupModeFromKey(file.key) != BackupMode.sync &&
          (localPath ?? Main.pathFromKey(file.key)) ==
              Main.pathFromKey(file.key)) {
        ConfigManager.setBackupMode(
          file.key,
          Main.backupModeFromKey(p.s3(p.dirname(file.key))) == BackupMode.sync
              ? null
              : BackupMode.sync,
        );
      }
      if (cacheFile.existsSync()) {
        renameOrCopyAndDelete(
          cacheFile,
          localPath ?? Main.pathFromKey(file.key) ?? file.key,
        );
      } else {
        Main.downloadFile(file, localPath: localPath);
      }
    }
  }

  void _downloadDirectory(RemoteFile dir, {String? localPath}) {
    if (Main.backupModeFromKey(dir.key) != BackupMode.sync &&
        (localPath ?? Main.pathFromKey(dir.key)) == Main.pathFromKey(dir.key)) {
      ConfigManager.setBackupMode(
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
              !p.isDir(file.key),
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

      final localFileDir = Directory(p.dirname(localFilePath));
      if (!localFileDir.existsSync()) {
        localFileDir.createSync(recursive: true);
      }

      if (!File(localFilePath).existsSync()) {
        final cacheFile = File(Main.cachePathFromKey(file.key));
        if (cacheFile.existsSync()) {
          renameOrCopyAndDelete(cacheFile, localFilePath);
        } else {
          Main.downloadFile(file, localPath: localFilePath);
        }
      }
    }
  }

  void _saveFile(RemoteFile file, String savePath) {
    final mFile = File(Main.pathFromKey(file.key) ?? file.key);
    final cacheFile = File(Main.cachePathFromKey(file.key));
    final saveFile = File(savePath);

    if (saveFile.existsSync()) {
      saveFile.deleteSync();
    }
    if (!saveFile.parent.existsSync()) {
      saveFile.parent.createSync(recursive: true);
    }

    if (mFile.existsSync()) {
      mFile.copySync(savePath);
    } else if (cacheFile.existsSync()) {
      cacheFile.copySync(savePath);
    } else {
      Main.downloadFile(file, localPath: savePath);
    }
  }

  // uses _saveFile
  void _saveDirectory(RemoteFile dir, String savePath) {
    final files = Main.remoteFiles
        .where(
          (file) =>
              p.isWithin(dir.key, file.key) &&
              file.key != dir.key &&
              !p.isDir(file.key),
        )
        .toList();

    int progressCount = 0;
    final totalFiles = files.length;

    for (final file in files) {
      progressCount += 1;
      progress.value = progressCount / totalFiles;

      final relativePath = p.s3(p.relative(file.key, from: dir.key));
      final saveFilePath = p.join(savePath, relativePath);
      _saveFile(file, saveFilePath);
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
    uiConfigNotifier.setValues(uiConfig);

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

    try {
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error setting up intent listener: $e');
      }
    }

    if (kDebugMode) {
      debugPrint('App initialized');
    }
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
      downloadFile: _downloadFile,
      downloadDirectory: _downloadDirectory,
      saveFile: _saveFile,
      saveDirectory: _saveDirectory,
      copyFile: Main.copyFile,
      copyDirectory: Main.copyDirectory,
      moveFiles: Main.moveFiles,
      moveDirectories: Main.moveDirectories,
      deleteLocal: _deleteLocal,
      deleteFiles: Main.deleteFiles,
      deleteCache: _deleteCache,
      deleteDirectories: Main.deleteDirectories,
      createDirectory: _createDirectory,
      uploadDirectory: _uploadDirectory,
    );
  }
}
