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
import 'package:files3/external_files.dart';

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
  if (Job.initializedJobs.isNotEmpty) {
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

  Future<void> _createDirectory(String dir) async {
    loading.value = true;
    try {
      await Main.profileFromKey(dir)!.fileManager!.createDirectory(dir);
      Main.remoteFilesAdd(RemoteFile(key: p.s3.asDir(dir), etag: ''));
      if (p.s3.split(dir).length == 1) {
        await Main.addWatcher(dir);
      }
    } catch (e) {
      showSnackBar(SnackBar(content: Text('Error creating directory: $e')));
    }
    loading.value = false;
  }

  void _deleteLocal(String key) {
    if (p.isDir(key)) {
      final dir = Directory(Main.pathFromKey(key));
      if (dir.existsSync()) {
        if (Main.backupModeFromKey(key) != BackupMode.upload) {
          ConfigManager.setBackupMode(
            key,
            Main.backupModeFromKey(p.s3.dirname(key)) == BackupMode.upload
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
      final file = File(Main.pathFromKey(key));
      if (file.existsSync()) {
        if (Main.backupModeFromKey(key) != BackupMode.upload) {
          ConfigManager.setBackupMode(
            key,
            Main.backupModeFromKey(p.s3.dirname(key)) == BackupMode.upload
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

  void _downloadFile(String key, {String? localPath}) {
    final mfile = File(Main.pathFromKey(key));
    final cacheFile = File(Main.cachePathFromKey(key));

    if (!mfile.existsSync()) {
      if (Main.backupModeFromKey(key) != BackupMode.sync &&
          (localPath ?? Main.pathFromKey(key)) == Main.pathFromKey(key)) {
        ConfigManager.setBackupMode(
          key,
          Main.backupModeFromKey(p.s3.dirname(key)) == BackupMode.sync
              ? null
              : BackupMode.sync,
        );
      }
      if (cacheFile.existsSync()) {
        renameOrCopyAndDelete(cacheFile, localPath ?? Main.pathFromKey(key));
      } else {
        Main.downloadFile(key, localPath: localPath);
      }
    }
  }

  void _downloadDirectory(String key, {String? localPath}) {
    if (Main.backupModeFromKey(key) != BackupMode.sync &&
        (localPath ?? Main.pathFromKey(key)) == Main.pathFromKey(key)) {
      ConfigManager.setBackupMode(
        key,
        Main.backupModeFromKey(p.s3.dirname(key)) == BackupMode.sync
            ? null
            : BackupMode.sync,
      );
    }
    final keys = Main.remoteFilesByDir(
      key,
      recursive: true,
    ).where((file) => !p.isDir(file.key)).map((file) => file.key).toList();
    int progressCount = 0;
    final totalFiles = keys.length;
    for (final key in keys) {
      progressCount += 1;
      progress.value = progressCount / totalFiles;
      final relativePath = p.s3.relative(key, from: key);
      final localFilePath = p.context.joinAll([
        localPath ?? Main.pathFromKey(key),
        ...p.s3.split(relativePath),
      ]);

      final localFileDir = Directory(p.context.dirname(localFilePath));
      if (!localFileDir.existsSync()) {
        localFileDir.createSync(recursive: true);
      }

      if (!File(localFilePath).existsSync()) {
        final cacheFile = File(Main.cachePathFromKey(key));
        if (cacheFile.existsSync()) {
          renameOrCopyAndDelete(cacheFile, localFilePath);
        } else {
          Main.downloadFile(key, localPath: localFilePath);
        }
      }
    }
  }

  void _saveFile(String key, String savePath) {
    final mFile = File(Main.pathFromKey(key));
    final cacheFile = File(Main.cachePathFromKey(key));
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
      Main.downloadFile(key, localPath: savePath);
    }
  }

  // uses _saveFile
  void _saveDirectory(String key, String savePath) {
    final keys = Main.remoteFilesByDir(
      key,
      recursive: true,
    ).where((file) => !p.isDir(file.key)).map((file) => file.key).toList();

    int progressCount = 0;
    final totalFiles = keys.length;

    for (final file in keys) {
      progressCount += 1;
      progress.value = progressCount / totalFiles;

      final relativePath = p.s3.relative(file, from: key);
      final saveFilePath = p.context.joinAll([
        savePath,
        ...p.s3.split(relativePath),
      ]);
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
        final relativePath = p.context.relative(
          entity.path,
          from: directory.path,
        );
        final remoteKey = p.s3.joinAll([key, ...p.context.split(relativePath)]);
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
          _sharedFiles.value = [uri];
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
            builder: (context) => ExternalFiles(
              path: sharedFiles,
              upload: (paths) async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PathPicker(
                      title: Text('Select Upload Location'),
                      subtitle: SingleChildScrollView(
                        child: Text(
                          '${paths.length} file${paths.length > 1 ? 's' : ''}: ${paths.map((e) => p.context.basename(e)).join(', ')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      onInit: RegExp(r'^[a-zA-Z]+://').hasMatch(paths.first)
                          ? () async {
                              loading.value = true;
                              int totalCount = paths.length;
                              int progressCount = 0;
                              paths = await Future.wait(
                                paths.map((e) async {
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
                        for (final sharedFile in paths) {
                          final fileName = p.context.basename(sharedFile);
                          final remoteKey = p.s3.join(path, fileName);
                          await Main.uploadFile(remoteKey, File(sharedFile));
                        }
                        loading.value = false;
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );
        _sharedFiles.value = [];
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
      deleteLocal: _deleteLocal,
      deleteCache: _deleteCache,
      createDirectory: _createDirectory,
      uploadDirectory: _uploadDirectory,
    );
  }
}
