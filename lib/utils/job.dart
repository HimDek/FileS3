import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_transfer_task.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/sync_analyzer.dart';
import 'package:files3/utils/hash_util.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';

abstract class Main {
  static final Set<Profile> profiles = <Profile>{};
  static final Map<String, Watcher> watcherMap = <String, Watcher>{};
  static List<RemoteFile> remoteFiles = <RemoteFile>[];
  static Function(bool loading)? setLoadingState;
  static Function()? setHomeState;
  static String downloadCacheDir = '';
  static String documentsDir = '';
  static final List<String> ignoreKeyRegexps = <String>[
    r'^.*/deletion-register\.ini$',
  ];

  static Profile? profileFromKey(String key) {
    try {
      return profiles.firstWhere(
        (profile) => profile.name == key.split('/').first,
      );
    } catch (e) {
      return null;
    }
  }

  static String? pathFromKey(String key) {
    final localDir = IniManager.config
        ?.get('directories', "${key.split('/').first}/")
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
        if (p.isWithin(localDir, path) || localDir == path) {
          final relativePath = p
              .relative(path, from: localDir)
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

  static String cachePathFromKey(String key) {
    return '${Main.downloadCacheDir}/app_${sha1.convert(utf8.encode(key)).toString()}.tmp';
  }

  static String tagPathFromKey(String key) {
    return '${Main.downloadCacheDir}/app_${sha1.convert(utf8.encode(key)).toString()}.tag';
  }

  static Future<void> onJobStatus(Job job, dynamic result) async {
    if (job is UploadJob &&
        job.status == JobStatus.completed &&
        result is RemoteFile) {
      remoteFiles.removeWhere((file) => file.key == job.remoteKey);
      remoteFiles.add(result);
    }
    setHomeState?.call();
  }

  static Future<void> stopWatchers() async {
    if (kDebugMode) {
      debugPrint("Stopping all watchers...");
    }
    for (final watcher in watcherMap.values.toList()) {
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
          ? p.dirname(normalized.substring(0, normalized.length - 1))
          : p.dirname(normalized);

      if (basePath.isEmpty) continue;

      final parts = p.split(basePath);

      String current = '';
      for (final part in parts) {
        if (part.isEmpty) continue;

        current = p.join(current, part);
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

  static Future<void> refreshProfiles() async {
    setLoadingState?.call(true);
    for (final entry in (await ConfigManager.loadS3Config()).entries) {
      if (profiles.any((profile) => profile.name == entry.key)) {
        profiles
            .firstWhere((profile) => profile.name == entry.key)
            .updateConfig(entry.value);
        continue;
      }
      profiles.add(Profile(name: entry.key, cfg: entry.value));
    }
    setLoadingState?.call(false);
  }

  static Future<void> listDirectories({bool background = false}) async {
    setLoadingState?.call(true);
    for (final profile in profiles) {
      await profile.listDirectories(background: background);
    }
    setLoadingState?.call(false);
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
      profile: profileFromKey(file.key),
    ).add();
  }

  static Future<void> uploadFile(String key, File file) async {
    if (!file.existsSync()) {
      return;
    }

    if (p.normalize(pathFromKey(key) ?? key) == p.normalize(file.path)) {
      final deleteionLog = await profileFromKey(
        key,
      )!.deletionRegistrar.pullDeletions();
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
          profile: profileFromKey(key),
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
        profile: profileFromKey(newKey),
      ).add();
    }
  }

  static Future<void> init({bool background = false}) async {
    if (downloadCacheDir.isEmpty) {
      final directory = await getApplicationCacheDirectory();
      downloadCacheDir = p.join(directory.path, 'Downloads');
    }
    if (documentsDir.isEmpty) {
      final directory = await getApplicationDocumentsDirectory();
      documentsDir = directory.path;
    }
    if (!ConfigManager.initialized) {
      await ConfigManager.init();
    }
    Profile.setLoadingState = setLoadingState;
    Job.maxrun = ConfigManager.loadTransferConfig().maxConcurrentTransfers;
    Job.onProgressUpdate = () {
      setHomeState?.call();
    };
    await refreshProfiles();
    await listDirectories(background: background);
  }
}

abstract class Job {
  final File localFile;
  final String remoteKey;
  final Digest md5;
  final int bytes;
  final Profile? profile;
  S3TransferTask? task;
  int bytesCompleted = 0;
  JobStatus status = JobStatus.initialized;
  String statusMsg = '';

  static int maxrun = 5;
  static bool scheduled = false;
  static final List<Job> jobs = [];

  final void Function(Job job, dynamic result)? onStatus;

  static void Function()? onProgressUpdate;

  Job({
    required this.localFile,
    required this.remoteKey,
    required this.bytes,
    required this.onStatus,
    required this.md5,
    required this.profile,
  });

  void add() {
    if (jobs.any(
      (job) =>
          job.localFile.path == localFile.path &&
          job.remoteKey == remoteKey &&
          job.status != JobStatus.completed,
    )) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        "Adding job: ${runtimeType == UploadJob ? 'Upload' : 'Download'} - $remoteKey",
      );
    }
    if (!jobs.contains(this)) jobs.add(this);
    if (jobs.any((job) => job.status == JobStatus.initialized)) startall();
  }

  bool startable() {
    return status != JobStatus.running && (profile?.accessible ?? false);
  }

  Future<void> start() async {
    if (!startable()) return;
    try {
      if (runtimeType == UploadJob) {
        status = JobStatus.running;
        task = S3TransferTask(
          key: remoteKey,
          localFile: localFile,
          task: TransferTask.upload,
          profile: profile,
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
        status = JobStatus.stopped;
        if (bytesCompleted >= bytes && result != null) {
          status = JobStatus.completed;
          final resultFile = RemoteFile(
            key: remoteKey,
            size: bytes,
            etag: result['etag'] != null && result['etag']!.isNotEmpty
                ? result['etag']!.substring(1, result['etag']!.length - 1)
                : '',
            lastModified: localFile.lastModifiedSync(),
          );
          onStatus?.call(this, resultFile);
        } else {
          status = JobStatus.failed;
          bytesCompleted = 0;
          onStatus?.call(this, null);
        }
      }
      if (runtimeType == DownloadJob) {
        status = JobStatus.running;
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
          profile: profile,
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
        status = JobStatus.stopped;
        if (bytesCompleted >= bytes) {
          jobs.remove(this);
          status = JobStatus.completed;
          bytesCompleted = bytes;
          onStatus?.call(this, null);
        }
      }
    } catch (e) {
      status = JobStatus.failed;
      bytesCompleted = 0;
      statusMsg = "Error: ${e.toString()}";
      onStatus?.call(this, null);
    }
    onProgressUpdate?.call();
    startall();
  }

  bool stoppable() {
    return status == JobStatus.running || status == JobStatus.initialized;
  }

  void stop() {
    if (stoppable()) {
      task?.cancel.call();
      status = JobStatus.stopped;
      onStatus?.call(this, null);
      onProgressUpdate?.call();
    }
  }

  bool removable() {
    return status != JobStatus.running && jobs.contains(this);
  }

  void remove() {
    if (removable()) jobs.remove(this);
  }

  bool dismissible() {
    return status == JobStatus.completed;
  }

  void dismiss() {
    jobs.remove(this);
  }

  static void continueAll() {
    for (var job in jobs.where(
      (job) =>
          job.status == JobStatus.stopped || job.status == JobStatus.failed,
    )) {
      job.status = JobStatus.initialized;
    }
    startall();
  }

  static void startall() {
    if (scheduled) {
      if (kDebugMode) {
        debugPrint("Job scheduling is already in progress. Skipping...");
      }
      return;
    }

    scheduled = true;

    try {
      if (kDebugMode) {
        debugPrint(
          "Starting jobs: Running ${Job.jobs.where((job) => job.status == JobStatus.running).length}, Max Run $maxrun, Pending ${Job.jobs.where((job) => job.status == JobStatus.initialized).length}",
        );
      }

      while (Job.jobs.where((job) => job.status == JobStatus.running).length <
              maxrun &&
          Job.jobs.any((job) => job.status == JobStatus.initialized)) {
        Job job = jobs.firstWhere((job) => job.status == JobStatus.initialized);
        job.start();
      }

      if (kDebugMode) {
        debugPrint(
          "Job scheduling completed: Running ${Job.jobs.where((job) => job.status == JobStatus.running).length}, Max Run $maxrun, Pending ${Job.jobs.where((job) => job.status == JobStatus.initialized).length}",
        );
      }
    } finally {
      scheduled = false;
    }
  }

  static void stopall() {
    for (var job in jobs) {
      job.stop();
    }
  }

  static void clearCompleted() {
    jobs.removeWhere((job) => job.status == JobStatus.completed);
  }

  static void clear() {
    jobs.clear();
  }

  static void clearCache() {
    final directory = Directory(Main.downloadCacheDir);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }

  static int cacheSize() {
    final directory = Directory(Main.downloadCacheDir);
    int totalSize = 0;

    if (directory.existsSync()) {
      for (var file in directory.listSync(recursive: true)) {
        if (file is File) {
          totalSize += file.lengthSync();
        }
      }
    }

    return totalSize;
  }
}

class UploadJob extends Job {
  UploadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.onStatus,
    required super.md5,
    required super.profile,
  });
}

class DownloadJob extends Job {
  DownloadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.onStatus,
    required super.md5,
    required super.profile,
  }) {
    final tempFile = File(Main.cachePathFromKey(remoteKey));
    final tagFile = File(Main.tagPathFromKey(remoteKey));

    String localEtag = '';
    int offset = 0;
    if (tempFile.existsSync() && tagFile.existsSync()) {
      offset = tempFile.lengthSync();
      if (offset >= bytes) {
        offset = 0;
        tempFile.deleteSync();
        tagFile.deleteSync();
        tempFile.createSync(recursive: true);
        tagFile.createSync(recursive: true);
        tagFile.writeAsStringSync(base64.encode(super.md5.bytes), flush: true);
      } else {
        localEtag = tagFile.readAsStringSync();
      }
    } else {
      if (tempFile.existsSync()) tempFile.deleteSync();
      tempFile.createSync(recursive: true);
      if (tagFile.existsSync()) tagFile.deleteSync();
      tagFile.createSync(recursive: true);
      tagFile.writeAsStringSync(base64.encode(super.md5.bytes), flush: true);
    }

    if (offset > 0 &&
        offset < bytes &&
        localEtag == base64.encode(super.md5.bytes)) {
      bytesCompleted = offset;
      statusMsg =
          "Downloaded ${bytesToReadable(bytesCompleted)} of ${bytesToReadable(bytes)}";
    } else {
      offset = 0;
      if (tempFile.existsSync()) tempFile.deleteSync();
    }
  }
}

class Watcher {
  final String remoteDir;
  StreamSubscription<FileSystemEvent>? subscription;
  Timer? timer;
  bool watching = false;
  bool scanning = false;
  bool _rescanQueued = false;

  Watcher({required this.remoteDir});

  Future<void> scan() async {
    final localDir = Directory(Main.pathFromKey(remoteDir) ?? remoteDir);

    if (scanning) {
      if (_rescanQueued) {
        if (kDebugMode) {
          debugPrint("Scan already queued for ${localDir.path}, skipping.");
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            "Scan in progress for ${localDir.path}. Queued one rescan.",
          );
          _rescanQueued = true;
        }
      }
      return;
    }

    if (kDebugMode) {
      debugPrint("Starting scan for ${localDir.path}");
    }

    scanning = true;

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
        debugPrint("Remote files list is empty, skipping refresh.");
      }
      return;
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
    try {
      throw Exception("Debug Exception");
    } catch (e) {
      if (kDebugMode) {
        debugPrint("Debug Exception caught: $e");
      }
    }

    for (File file in [...result.newFile, ...result.modifiedLocally]) {
      final key = Main.keyFromPath(file.path) ?? '';
      if (Job.jobs.any(
        (job) =>
            job.localFile.path == file.path &&
            job.remoteKey == key &&
            job.status != JobStatus.completed,
      )) {
        continue;
      }
      BackupMode mode = Main.backupMode(Main.keyFromPath(file.path) ?? '');
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.uploadFile(key, file);
      }
    }

    for (RemoteFile file in result.modifiedRemotely) {
      if (Job.jobs.any(
        (job) => job.remoteKey == file.key && job.status != JobStatus.completed,
      )) {
        continue;
      }
      BackupMode mode = Main.backupMode(file.key);
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.downloadFile(file);
      }
    }

    for (RemoteFile file in result.remoteOnly) {
      if (Job.jobs.any(
        (job) => job.remoteKey == file.key && job.status != JobStatus.completed,
      )) {
        continue;
      }
      if (Main.backupMode(file.key) == BackupMode.sync) {
        Main.downloadFile(file);
      }
    }

    if (kDebugMode) {
      debugPrint("Scan completed for ${localDir.path}");
    }

    scanning = false;

    if (_rescanQueued) {
      _rescanQueued = false;
      scan();
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
