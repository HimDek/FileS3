import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:s3_drive/services/hash_util.dart';
import 'package:s3_drive/services/ini_manager.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:s3_drive/services/s3_file_manager.dart';
import 'models/backup_mode.dart';
import 'sync_analyzer.dart';
import 's3_transfer_task.dart';
import 'config_manager.dart';

abstract class Main {
  static late S3FileManager? s3Manager;
  static final List<Watcher> watchers = <Watcher>[];
  static final Map<String, List<RemoteFile>> remoteFilesMap =
      <String, List<RemoteFile>>{};
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

  static Future<void> onJobStatus(Job job, dynamic result) async {
    if (job is UploadJob && job.completed && !job.running) {
      remoteFilesMap['${job.remoteKey.split('/').first}/'] = [
        ...(remoteFilesMap['${job.remoteKey.split('/').first}/'] ?? []).where((
          file,
        ) {
          return file.key != job.remoteKey;
        }),
        result,
      ];
      await refreshWatchers();
    }
    if (job is DownloadJob && job.completed && !job.running) {
      await refreshWatchers();
    }
    setHomeState?.call();
  }

  static void setConfig(BuildContext? context) async {
    Job.cfg = Job.cfg ?? await ConfigManager.loadS3Config(context: context);
  }

  static Future<void> stopWatchers() async {
    for (final watcher in watchers) {
      await watcher.stop();
    }
  }

  static BackupMode backupMode(String key) {
    final dir = key.split('/').first;
    return BackupMode.fromValue(
      int.parse(IniManager.config?.get('modes', dir) ?? '1'),
    );
  }

  static Future<void> addWatcher(String dir, {bool background = false}) async {
    final localDir = IniManager.config!
        .get('directories', dir)
        ?.replaceAll('\\', '/');

    if (localDir != null &&
        localDir.isNotEmpty &&
        Directory(localDir).existsSync()) {
      Watcher watcher = Watcher(
        localDir: Directory(localDir),
        remoteDir: dir,
        remoteFiles: remoteFilesMap[dir] ?? [],
        remoteRefresh: () => refreshRemote(dir),
      );

      watchers.add(watcher);
      if (background) {
        await watcher.scan();
      } else {
        watcher.start();
      }
    }
  }

  static Future<void> refreshRemote(String dir) async {
    setLoadingState?.call(true);
    final remoteFiles = await s3Manager!.listObjects(dir: dir);
    remoteFilesMap[dir] = remoteFiles;
    setLoadingState?.call(false);
  }

  static Future<void> refreshWatchers() async {
    setLoadingState?.call(true);
    stopWatchers();
    watchers.clear();

    for (final dir in Main.remoteFilesMap.keys) {
      await addWatcher(dir);
    }
    setLoadingState?.call(false);
  }

  static Future<void> listDirectories({bool background = false}) async {
    await setLoadingState?.call(true);
    final dirs = await s3Manager!.listDirectories();

    await stopWatchers();

    Job.clear();
    watchers.clear();

    for (final dir in dirs) {
      await refreshRemote(dir);
      await addWatcher(dir, background: background);
    }
    await setLoadingState?.call(false);
  }

  static void downloadFile(RemoteFile file, {String? localPath}) {
    DownloadJob(
      localFile: File(localPath ?? pathFromKey(file.key) ?? file.key),
      remoteKey: file.key,
      bytes: file.size,
      md5: file.etag,
      onStatus: onJobStatus,
    ).add();
  }

  static void uploadFile(String key, File file) {
    if (!file.existsSync()) {
      return;
    }
    if (pathFromKey(key) == file.path) {
      UploadJob(
        localFile: file,
        remoteKey: key,
        bytes: file.lengthSync(),
        onStatus: onJobStatus,
        md5: HashUtil.md5Hash(file),
      ).add();
    } else if (p.isAbsolute(pathFromKey(key) ?? key)) {
      final newKey = () {
        String base = p.basenameWithoutExtension(key);
        String ext = p.extension(key);
        int count = 1;
        String candidateKey = key;
        while (remoteFilesMap['${key.split('/').first}/']?.any(
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
      stopWatchers().then((value) {
        file.copySync(pathFromKey(newKey) ?? newKey);
        refreshWatchers();
      });
    } else {
      final newKey = () {
        String base = p.basenameWithoutExtension(key);
        String ext = p.extension(key);
        int count = 1;
        String candidateKey = key;
        while (remoteFilesMap[key.split('/').first]?.any(
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
        md5: HashUtil.md5Hash(file),
      ).add();
    }
  }

  static Future<void> init(
    BuildContext? context, {
    bool background = false,
  }) async {
    await IniManager.init();
    setConfig(context);
    s3Manager = await S3FileManager.create(context, httpClient);
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
  final String md5;
  final int bytes;
  S3TransferTask? task;
  int bytesCompleted = 0;
  bool completed = false;
  bool running = false;
  bool failed = false;
  String statusMsg = '';

  static S3Config? cfg;
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
    if (!jobs.contains(this)) jobs.add(this);
    if (jobs.any((job) => !job.running)) startall();
  }

  bool startable() {
    return !running && !completed && cfg != null;
  }

  Future<void> start() async {
    if (!startable()) return;
    try {
      if (runtimeType == UploadJob) {
        running = true;
        task = S3TransferTask(
          accessKey: cfg!.accessKey,
          secretKey: cfg!.secretKey,
          region: cfg!.region,
          bucket: cfg!.bucket,
          key:
              (cfg!.prefix[cfg!.prefix.length - 1] != '/'
                  ? '${cfg!.prefix}/'
                  : cfg!.prefix) +
              remoteKey,
          localFile: localFile,
          task: TransferTask.upload,
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
          accessKey: cfg!.accessKey,
          secretKey: cfg!.secretKey,
          region: cfg!.region,
          bucket: cfg!.bucket,
          key:
              (cfg!.prefix[cfg!.prefix.length - 1] != '/'
                  ? '${cfg!.prefix}/'
                  : cfg!.prefix) +
              remoteKey,
          localFile: localFile,
          task: TransferTask.download,
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
    if (scheduled) return;
    scheduled = true;

    while (Job.jobs.where((job) => job.running).length < maxrun &&
        Job.jobs.any((job) => !job.completed && !job.running)) {
      Job job = jobs.firstWhere((job) => !job.completed && !job.running);
      job.start();
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
  final Directory localDir;
  final String remoteDir;
  final List<RemoteFile> remoteFiles;
  final Future<void> Function() remoteRefresh;
  StreamSubscription<FileSystemEvent>? subscription;
  Timer? timer;
  bool watching = false;
  bool scanning = false;
  bool waitingScan = false;

  Watcher({
    required this.localDir,
    required this.remoteDir,
    required this.remoteFiles,
    required this.remoteRefresh,
  });

  Future<void> scan() async {
    if (waitingScan) {
      debugPrint(
        "A Scan is already waiting for a scan already in progress for ${localDir.path}. Skipping...",
      );
      return;
    }

    if (scanning) {
      waitingScan = true;
      if (kDebugMode) {
        debugPrint(
          "Scan is already in progress for ${localDir.path}. Waiting...",
        );
      }
      while (scanning) {
        sleep(const Duration(milliseconds: 2000));
      }
      if (kDebugMode) {
        debugPrint("Scan completed for ${localDir.path}. Resuming...");
      }
      waitingScan = false;
    } else {
      scanning = true;
    }

    if (!localDir.existsSync()) {
      if (kDebugMode) {
        debugPrint("Local directory does not exist: ${localDir.path}");
      }
      return;
    }

    if (remoteFiles.isEmpty) {
      if (kDebugMode) {
        debugPrint("Remote files list is empty, refreshing remote files.");
      }
      await remoteRefresh();
    }

    final analyzer = SyncAnalyzer(
      localRoot: localDir,
      remoteFiles: remoteFiles,
    );
    final result = analyzer.analyze();

    for (Job job in Job.jobs.where((job) => !job.completed && !job.running)) {
      job.remove();
    }

    for (File file in [...result.newFile, ...result.modifiedLocally]) {
      if (Job.jobs.any((job) {
        return job.localFile.path == file.path && !job.completed;
      })) {
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
      if (Job.jobs.any((job) {
        return job.remoteKey == file.key;
      })) {
        continue;
      }
      BackupMode mode = Main.backupMode(file.key);
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.downloadFile(file);
      }
    }

    for (RemoteFile file in result.remoteOnly) {
      if (Job.jobs.any((job) {
        return job.remoteKey == file.key;
      })) {
        continue;
      }
      if (Main.backupMode(file.key) == BackupMode.sync) {
        Main.downloadFile(file);
      }
    }

    scanning = false;
  }

  Future<void> start() async {
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
          scan();
        }
      });
    } else {
      timer = Timer.periodic(const Duration(seconds: 60), (timer) {
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
