import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:files3/services/models/backup_mode.dart';
import 'package:files3/services/models/remote_file.dart';
import 'package:files3/services/s3_transfer_task.dart';
import 'package:files3/services/s3_file_manager.dart';
import 'package:files3/services/config_manager.dart';
import 'package:files3/services/sync_analyzer.dart';
import 'package:files3/services/ini_manager.dart';
import 'package:files3/services/hash_util.dart';
import 'package:ini/ini.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

class DeletionRegistrar {
  static late File _file;
  static Config? config;
  static DateTime lastPulled = DateTime.fromMillisecondsSinceEpoch(0).toUtc();

  static Future<void> init() async {
    _file = File(
      '${(await getApplicationDocumentsDirectory()).path}/deletion-register.ini',
    );

    if (!_file.existsSync()) {
      _file.createSync(recursive: true);
      _file.writeAsStringSync('[register]');
    }

    config = Config.fromStrings(await _file.readAsLines());
  }

  static void save() {
    _file.writeAsStringSync(config.toString());
  }

  static void logDeletions(List<String> keys) {
    if (!config!.sections().contains('register')) {
      config!.addSection('register');
    }
    for (String key in keys) {
      config!.set('register', key, DateTime.now().toUtc().toIso8601String());
    }
    save();
  }

  static Future<Map<String, DateTime>> pullDeletions() async {
    await Main.refreshRemote(dir: 'deletion-register.ini');

    if (Main.remoteFiles.every((file) => file.key != 'deletion-register.ini')) {
      if (kDebugMode) {
        debugPrint("Remote deletion register does not exist.");
      }
      return {};
    }

    final remoteFile = Main.remoteFiles.firstWhere(
      (file) => file.key == 'deletion-register.ini',
    );

    if (lastPulled.toUtc().isAfter(
          remoteFile.lastModified?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
        ) &&
        _file.existsSync()) {
      if (kDebugMode) {
        debugPrint("Local deletion register is up to date.");
      }
      return {
        for (var entry in config!.options('register')!)
          entry: DateTime.parse(config!.get('register', entry)!).toUtc(),
      };
    }

    Job job = DownloadJob(
      localFile: _file,
      remoteKey: 'deletion-register.ini',
      bytes: remoteFile.size,
      md5: () {
        final hex = remoteFile.etag.replaceAll('"', '');

        if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hex)) {
          throw StateError('ETag is not a single-part MD5 digest');
        }

        final bytes = List<int>.generate(
          16,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        );

        return Digest(bytes);
      }(),
      onStatus: (job, result) {},
    );

    await job.start();
    Job.completedJobs.remove(job);

    if (_file.existsSync()) {
      config = Config.fromStrings(_file.readAsLinesSync());
    }

    lastPulled = DateTime.now().toUtc();

    return {
      for (var entry in config!.options('register')!)
        entry: DateTime.parse(config!.get('register', entry)!).toUtc(),
    };
  }

  static Future<void> pushDeletions() async {
    Job job = UploadJob(
      localFile: _file,
      remoteKey: 'deletion-register.ini',
      bytes: _file.lengthSync(),
      onStatus: (job, result) {},
      md5: await HashUtil(_file).md5Hash(),
    );
    await job.start();
    Job.completedJobs.remove(job);
  }
}

abstract class Main {
  static late S3FileManager? s3Manager;
  static final Map<String, Watcher> watcherMap = <String, Watcher>{};
  static List<RemoteFile> remoteFiles = <RemoteFile>[];
  static http.Client httpClient = http.Client();
  static Function(bool loading)? setLoadingState;
  static Function()? setHomeState;

  static String? pathFromKey(String key) {
    final localDir = IniManager.config!
        .get('directories', "${key.split('/').first}/")
        ?.replaceAll('\\', '/');
    if (localDir != null) {
      return p.join(localDir, key.split('/').sublist(1).join('/'));
    } else {
      return null;
    }
  }

  static String? keyFromPath(String path) {
    for (String dir in IniManager.config!.options('directories')!) {
      final localDir = IniManager.config!
          .get('directories', dir)
          ?.replaceAll('\\', '/');
      if (localDir != null) {
        final normalizedLocalDir = p.normalize(localDir);
        final normalizedPath = p.normalize(path);
        if (p.isWithin(normalizedLocalDir, normalizedPath) ||
            normalizedLocalDir == normalizedPath) {
          final relativePath = p
              .relative(normalizedPath, from: normalizedLocalDir)
              .replaceAll('\\', '/');
          return p.join(dir, relativePath).replaceAll('\\', '/');
        }
      }
    }
    return null;
  }

  static Watcher? watcherFromKey(String key) {
    final dirKey = '${key.split('/').first}/';
    return watcherMap[dirKey];
  }

  static Future<void> onJobStatus(Job job, dynamic result) async {
    if (job is UploadJob && job.completed && !job.running) {
      remoteFiles.removeWhere((file) => file.key == job.remoteKey);
      remoteFiles.add(result);
    }
    setHomeState?.call();
  }

  static Future<void> stopWatchers() async {
    if (kDebugMode) {
      debugPrint("Stopping all watchers...");
    }
    for (final watcher in watcherMap.values) {
      await watcher.stop();
    }
  }

  static BackupMode backupMode(String key) {
    String? value = IniManager.config?.get('modes', key);
    if (value == null && p.split(key).length > 1) {
      return backupMode(p.dirname(key));
    } else {
      return BackupMode.fromValue(int.parse(value ?? '1'));
    }
  }

  static Future<void> addWatcher(String dir, {bool background = false}) async {
    final localDir = Main.pathFromKey(dir);

    if (localDir != null &&
        localDir.isNotEmpty &&
        Directory(localDir).existsSync()) {
      Watcher watcher = Watcher(remoteDir: dir);

      watcherMap[dir] = watcher;
      if (background) {
        if (kDebugMode) {
          debugPrint("Performing background scan for $localDir");
        }
        await watcher.scan();
      } else {
        if (kDebugMode) {
          debugPrint("Starting watcher for $localDir");
        }
        watcher.start();
      }
    }
  }

  static void ensureDirectoryObjects() {
    final existingPaths = remoteFiles.map((o) => o.key).toSet();

    for (final obj in remoteFiles.toList()) {
      final normalized = p.normalize(obj.key);
      final isDir = normalized.endsWith('/');

      final basePath = isDir
          ? p.posix.dirname(normalized.substring(0, normalized.length - 1))
          : p.posix.dirname(normalized);

      if (basePath == '.' || basePath.isEmpty) continue;

      final parts = p.posix.split(basePath);

      String current = '';
      for (final part in parts) {
        if (part.isEmpty) continue;

        current = p.posix.join(current, part);
        final dirPath = '$current/';

        if (!existingPaths.contains(dirPath)) {
          final dirObject = RemoteFile(
            key: dirPath,
            size: 0,
            etag: '',
            lastModified: DateTime.now(),
          );

          remoteFiles.add(dirObject);
          existingPaths.add(dirPath);
        }
      }
    }
  }

  static Future<void> refreshRemote({String dir = ''}) async {
    final fetchedRemoteFiles = await s3Manager!.listObjects(dir: dir);
    remoteFiles.removeWhere((file) => p.isWithin(dir, file.key));
    remoteFiles.addAll(fetchedRemoteFiles);
    ensureDirectoryObjects();
    await ConfigManager.saveRemoteFiles(remoteFiles);
  }

  static Future<void> refreshWatchers({bool background = false}) async {
    setLoadingState?.call(true);
    await stopWatchers();
    watcherMap.clear();

    final dirs = remoteFiles
        .where((dir) => dir.key.endsWith('/'))
        .map((file) => '${file.key.split('/').first}/')
        .toSet()
        .toList();

    for (final dir in dirs) {
      await addWatcher(dir, background: background);
    }
    setLoadingState?.call(false);
  }

  static Future<void> listDirectories({bool background = false}) async {
    await setLoadingState?.call(true);

    if (!background) {
      remoteFiles = await ConfigManager.loadRemoteFiles();
    }

    while (s3Manager == null || !s3Manager!.configured) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await refreshRemote();
    await refreshWatchers(background: true);
    await setLoadingState?.call(false);
  }

  static void downloadFile(RemoteFile file, {String? localPath}) {
    DownloadJob(
      localFile: File(localPath ?? pathFromKey(file.key) ?? file.key),
      remoteKey: file.key,
      bytes: file.size,
      md5: () {
        final hex = file.etag.replaceAll('"', '');

        if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hex)) {
          throw StateError('ETag is not a single-part MD5 digest');
        }

        final bytes = List<int>.generate(
          16,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        );

        return Digest(bytes);
      }(),
      onStatus: onJobStatus,
    ).add();
  }

  static Future<void> uploadFile(String key, File file) async {
    if (!file.existsSync()) {
      return;
    }

    if (p.normalize(pathFromKey(key) ?? key) == p.normalize(file.path)) {
      final deleteionLog = await DeletionRegistrar.pullDeletions();
      if (deleteionLog.containsKey(key) &&
          file.lastModifiedSync().toUtc().isBefore(
            deleteionLog[key]!.toUtc(),
          )) {
        if (kDebugMode) {
          debugPrint("File deleted remotely, deleting locally: ${file.path}");
        }
        file.deleteSync();
      } else {
        UploadJob(
          localFile: file,
          remoteKey: key,
          bytes: file.lengthSync(),
          onStatus: onJobStatus,
          md5: await HashUtil(file).md5Hash(),
        ).add();
      }
    } else if (p.isAbsolute(pathFromKey(key) ?? key)) {
      final newKey = () {
        String base = p.basenameWithoutExtension(key);
        String ext = p.extension(key);
        int count = 1;
        String candidateKey = key;
        while (remoteFiles.any(
              (remoteFile) => remoteFile.key == candidateKey,
            ) ==
            true) {
          candidateKey = p.join(p.dirname(key), '$base${'($count)'}$ext');
          count++;
        }
        return candidateKey;
      }();
      if (!File(pathFromKey(newKey) ?? newKey).parent.existsSync()) {
        File(pathFromKey(newKey) ?? newKey).parent.createSync(recursive: true);
      }
      file.copySync(pathFromKey(newKey) ?? newKey);
      if (kDebugMode) {
        debugPrint(
          "File copied to monitored directory: ${pathFromKey(newKey) ?? newKey}",
        );
      }
      watcherFromKey(newKey)?.scan();
    } else {
      final newKey = () {
        String base = p.basenameWithoutExtension(key);
        String ext = p.extension(key);
        int count = 1;
        String candidateKey = key;
        while (remoteFiles.any(
              (remoteFile) => remoteFile.key == candidateKey,
            ) ==
            true) {
          candidateKey = p.join(p.dirname(key), '$base${'($count)'}$ext');
          count++;
        }
        return candidateKey;
      }();
      UploadJob(
        localFile: file,
        remoteKey: newKey,
        bytes: file.lengthSync(),
        onStatus: onJobStatus,
        md5: await HashUtil(file).md5Hash(),
      ).add();
    }
  }

  static Future<void> setConfig() async {
    s3Manager = await S3FileManager.create(httpClient);
  }

  static Future<void> init({bool background = false}) async {
    if (IniManager.config == null) {
      await IniManager.init();
    }
    if (DeletionRegistrar.config == null) {
      await DeletionRegistrar.init();
    }
    await setConfig();
    Job.onProgressUpdate = () {
      setHomeState?.call();
    };
    if (s3Manager == null) {
      // TODO: Show config notification
      return;
    }
    await listDirectories(background: background);
  }
}

abstract class Job {
  final File localFile;
  final String remoteKey;
  final Digest md5;
  final int bytes;
  S3TransferTask? task;
  int bytesCompleted = 0;
  bool completed = false;
  bool running = false;
  bool failed = false;
  String statusMsg = '';

  static S3FileManager fileManager = Main.s3Manager!;
  static int maxrun = 5;
  static bool scheduled = false;
  static final List<Job> jobs = [];
  static final List<Job> completedJobs = [];

  final void Function(Job job, dynamic result)? onStatus;

  static void Function()? onProgressUpdate;

  Job({
    required this.localFile,
    required this.remoteKey,
    required this.bytes,
    required this.onStatus,
    required this.md5,
  });

  void add() {
    if (kDebugMode) {
      debugPrint(
        "Adding job: ${runtimeType == UploadJob ? 'Upload' : 'Download'} - $remoteKey",
      );
    }
    if (!jobs.contains(this)) jobs.add(this);
    if (jobs.any((job) => !job.running)) startall();
  }

  bool startable() {
    return !running &&
        !completed &&
        Main.s3Manager != null &&
        Main.s3Manager!.configured;
  }

  Future<void> start() async {
    if (!startable()) return;
    try {
      if (runtimeType == UploadJob) {
        running = true;
        task = S3TransferTask(
          key: remoteKey,
          localFile: localFile,
          task: TransferTask.upload,
          fileManager: fileManager,
          md5: md5,
          onProgress: (sent, total) {
            bytesCompleted = sent;
            onStatus?.call(this, null);
          },
          onStatus: (status) {
            statusMsg = status;
            onStatus?.call(this, null);
          },
        );
        final result = await task!.start();
        failed = false;
        running = false;
        completed = true;
        bytesCompleted = bytes;
        jobs.remove(this);
        completedJobs.add(this);
        final resultFile = RemoteFile(
          key: remoteKey,
          size: bytes,
          etag: result['etag'] != null && result['etag']!.isNotEmpty
              ? result['etag']!.substring(1, result['etag']!.length - 1)
              : '',
          lastModified: localFile.lastModifiedSync(),
        );
        onStatus?.call(this, resultFile);
      }
      if (runtimeType == DownloadJob) {
        running = true;
        // final ifModifiedSince = await localFile.exists()
        //     ? localFile.lastModifiedSync()
        //     : null;
        final dir = Directory(p.dirname(localFile.path));
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        task = S3TransferTask(
          key: remoteKey,
          localFile: localFile,
          task: TransferTask.download,
          fileManager: fileManager,
          md5: md5,
          onProgress: (received, total) {
            bytesCompleted = received;
            onStatus?.call(this, null);
          },
          onStatus: (status) {
            statusMsg = status;
            onStatus?.call(this, null);
          },
        );
        await task!.start();
        failed = false;
        running = false;
        completed = true;
        bytesCompleted = bytes;
        jobs.remove(this);
        completedJobs.add(this);
        onStatus?.call(this, null);
      }
    } catch (e) {
      failed = true;
      running = false;
      completed = false;
      bytesCompleted = 0;
      statusMsg = "Error: ${e.toString()}";
      onStatus?.call(this, null);
    }
    onProgressUpdate?.call();
    startall();
  }

  bool stoppable() {
    return task != null && running && !completed;
  }

  void stop(Job job) {
    if (stoppable()) task!.cancel();
    failed = true;
    running = false;
    completed = false;
    bytesCompleted = 0;
    statusMsg = "Cancelled";
    onStatus?.call(this, null);
    onProgressUpdate?.call();
  }

  bool removable() {
    return !completed && !running && jobs.contains(this);
  }

  void remove() {
    if (removable()) jobs.remove(this);
  }

  bool dismissible() {
    return completed && !running && completedJobs.contains(this);
  }

  void dismiss() {
    completedJobs.remove(this);
  }

  static void startall() {
    if (scheduled) {
      if (kDebugMode) {
        debugPrint("Job scheduling is already in progress. Skipping...");
      }
      return;
    }
    scheduled = true;

    if (kDebugMode) {
      debugPrint(
        "Starting jobs: Running ${Job.jobs.where((job) => job.running).length}, Max Run $maxrun, Pending ${Job.jobs.where((job) => !job.completed && !job.running).length}",
      );
    }

    while (Job.jobs.where((job) => job.running).length < maxrun &&
        Job.jobs.any((job) => !job.completed && !job.running && !job.failed)) {
      Job job = jobs.firstWhere(
        (job) => !job.completed && !job.running && !job.failed,
      );
      job.start();
    }

    if (kDebugMode) {
      debugPrint(
        "Job scheduling completed: Running ${Job.jobs.where((job) => job.running).length}, Max Run $maxrun, Pending ${Job.jobs.where((job) => !job.completed && !job.running).length}",
      );
    }

    scheduled = false;
  }

  static void stopall() {
    for (var job in jobs) {
      job.stop(job);
    }
  }

  static void clearCompleted() {
    completedJobs.clear();
  }

  static void clear() {
    jobs.clear();
  }
}

class UploadJob extends Job {
  UploadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.onStatus,
    required super.md5,
  });
}

class DownloadJob extends Job {
  DownloadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.onStatus,
    required super.md5,
  });
}

class Watcher {
  final String remoteDir;
  StreamSubscription<FileSystemEvent>? subscription;
  Timer? timer;
  bool watching = false;
  bool scanning = false;
  Completer<void>? _scanWaiter;
  bool _rescanQueued = false;

  Watcher({required this.remoteDir});

  Future<void> scan() async {
    final localDir = Directory(Main.pathFromKey(remoteDir) ?? remoteDir);

    if (scanning) {
      if (_rescanQueued) {
        if (kDebugMode) {
          debugPrint("Scan already queued for ${localDir.path}, skipping.");
        }
        return;
      }

      _rescanQueued = true;

      if (_scanWaiter != null) {
        if (kDebugMode) {
          debugPrint(
            "Scan in progress for ${localDir.path}. Queued one rescan.",
          );
        }
        await _scanWaiter!.future;
      }
      return;
    }

    if (kDebugMode) {
      debugPrint("Starting scan for ${localDir.path}");
    }

    scanning = true;
    _scanWaiter = Completer<void>();

    if (!localDir.existsSync()) {
      if (kDebugMode) {
        debugPrint("Local directory does not exist: ${localDir.path}");
      }
      scanning = false;
      return;
    }

    if (Main.remoteFiles
        .where((file) => p.isWithin(remoteDir, file.key))
        .isEmpty) {
      if (kDebugMode) {
        debugPrint("Remote files list is empty, refreshing remote files.");
      }
      await Main.refreshRemote(dir: remoteDir);
    }

    if (kDebugMode) {
      debugPrint("Analyzing sync status for ${localDir.path}");
    }
    final analyzer = SyncAnalyzer(
      localRoot: localDir,
      remoteFiles: Main.remoteFiles
          .where(
            (file) => p.isWithin(
              localDir.path,
              Main.pathFromKey(file.key) ?? file.key,
            ),
          )
          .toList(),
    );
    final result = await analyzer.analyze();
    if (kDebugMode) {
      debugPrint(
        "Sync analysis completed for ${localDir.path}: New Files: ${result.newFile.length}, Modified Locally: ${result.modifiedLocally.length}, Modified Remotely: ${result.modifiedRemotely.length}, Remote Only: ${result.remoteOnly.length}",
      );
    }

    for (Job job
        in Job.jobs.where((job) => !job.completed && !job.running).toList()) {
      job.remove();
    }

    for (File file in [...result.newFile, ...result.modifiedLocally]) {
      if (Job.jobs.any(
        (job) => job.localFile.path == file.path && !job.completed,
      )) {
        continue;
      }
      BackupMode mode = Main.backupMode(Main.keyFromPath(file.path) ?? '');
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.uploadFile(
          p.join(remoteDir, p.relative(file.path, from: localDir.path)),
          file,
        );
      }
    }

    for (RemoteFile file in result.modifiedRemotely) {
      if (Job.jobs.any((job) => job.remoteKey == file.key)) {
        continue;
      }
      BackupMode mode = Main.backupMode(file.key);
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.downloadFile(file);
      }
    }

    for (RemoteFile file in result.remoteOnly) {
      if (Job.jobs.any((job) => job.remoteKey == file.key)) {
        continue;
      }
      print(
        'Remote only file: ${file.key}, mode: ${Main.backupMode(file.key).value}',
      );
      if (Main.backupMode(file.key) == BackupMode.sync) {
        Main.downloadFile(file);
      }
    }

    if (kDebugMode) {
      debugPrint("Scan completed for ${localDir.path}");
    }

    scanning = false;
    _scanWaiter?.complete();
    _scanWaiter = null;

    if (_rescanQueued) {
      _rescanQueued = false;
      await scan();
    }
  }

  Future<void> start() async {
    final localDir = Directory(Main.pathFromKey(remoteDir) ?? remoteDir);

    if (watching) {
      if (kDebugMode) {
        debugPrint("Watcher is already running for ${localDir.path}");
      }
      return;
    }
    watching = true;

    await scan();

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      subscription = localDir.watch(recursive: true).listen((event) {
        final file = File(event.path);
        if (file.existsSync()) {
          if (kDebugMode) {
            debugPrint(
              "File system event detected: ${event.type} - ${event.path}",
            );
          }
          scan();
        }
      });
    } else {
      timer = Timer.periodic(const Duration(seconds: 60), (timer) {
        if (kDebugMode) {
          debugPrint("Periodic scan triggered for ${localDir.path}");
        }
        scan();
      });
    }
  }

  Future<void> stop() async {
    if (subscription != null) {
      await subscription?.cancel();
      subscription = null;
    }
    if (timer != null) {
      timer?.cancel();
      timer = null;
    }
    watching = false;
  }
}
