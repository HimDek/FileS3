import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:files3/utils/s3_transfer_task.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/sync_analyzer.dart';
import 'package:files3/utils/hash_util.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';

abstract class Main {
  static String _documentsDir = '';
  static String _cacheDir = '';
  static String _downloadCacheDir = '';
  static List<RemoteFile> _remoteFiles = <RemoteFile>[];
  static final Set<Profile> _profiles = <Profile>{};
  static final Map<String, Watcher> _watcherMap = <String, Watcher>{};
  static final ManualNotifier onRemoteFilesChanged = ManualNotifier();
  static final ValueNotifier<bool> initialized = ValueNotifier<bool>(false);
  static final List<RegExp> _ignoreKeyRegexps = <RegExp>[
    RegExp(r'^.*[/\\]deletion-register\.ini$'),
  ];

  static Set<Profile> get profiles => _profiles;
  static List<RemoteFile> _filteredRemoteFiles = [];

  static List<RemoteFile> get remoteFiles => _filteredRemoteFiles;
  static List<RemoteFile> get remoteFilesRaw => _remoteFiles;

  static void rebuildRemoteFiles() {
    _filteredRemoteFiles = List.unmodifiable(
      _remoteFiles.where(
        (file) => _ignoreKeyRegexps.every((r) => !r.hasMatch(file.key)),
      ),
    );
  }

  static void remoteFilesSet(List<RemoteFile> files) {
    _remoteFiles = files;
    rebuildRemoteFiles();
    _ensureDirectoryObjects();
    onRemoteFilesChanged.notifyListeners();
  }

  static void remoteFilesAdd(RemoteFile file) {
    _remoteFiles.add(file);
    rebuildRemoteFiles();
    _ensureDirectoryObjects();
    onRemoteFilesChanged.notifyListeners();
  }

  static void remoteFilesAddAll(List<RemoteFile> files) {
    _remoteFiles.addAll(files);
    rebuildRemoteFiles();
    _ensureDirectoryObjects();
    onRemoteFilesChanged.notifyListeners();
  }

  static void remoteFilesRemoveWhere(bool Function(RemoteFile element) test) {
    remoteFilesRemoveWhereNoNotify(test);
    onRemoteFilesChanged.notifyListeners();
  }

  static void remoteFilesRemoveWhereNoNotify(
    bool Function(RemoteFile element) test,
  ) {
    _remoteFiles.removeWhere(test);
    rebuildRemoteFiles();
    _ensureDirectoryObjects();
  }

  static void remoteFilesClear() {
    _remoteFiles.clear();
    rebuildRemoteFiles();
    onRemoteFilesChanged.notifyListeners();
  }

  static String get cacheDir => _cacheDir;

  static String get downloadCacheDir => _downloadCacheDir;

  static String get documentsDir => _documentsDir;

  static List<RegExp> get ignoreKeyRegexps =>
      UnmodifiableListView(_ignoreKeyRegexps);

  static Profile? profileFromKey(String key) {
    try {
      return _profiles.firstWhere(
        (profile) => profile.name == p.split(key).firstOrNull,
      );
    } catch (e) {
      return null;
    }
  }

  static String? pathFromKey(String key) {
    final localDir = IniManager.config.value
        ?.get('directories', p.s3(p.asDir(p.split(key).firstOrNull ?? '')))
        ?.replaceAll('\\', p.separator);
    if (localDir != null) {
      final path = p.joinAll([localDir, ...p.split(key).sublist(1)]);
      return p.normalize(p.isDir(key) ? p.asDir(path) : path);
    } else {
      return null;
    }
  }

  static String? keyFromPath(String path) {
    for (String dir in IniManager.config.value!.options('directories')!) {
      final localDir = IniManager.config.value!
          .get('directories', dir)
          ?.replaceAll('\\', p.separator);
      if (localDir != null) {
        if (p.isWithin(localDir, path) || localDir == path) {
          final relativePath = p
              .s3(p.relative(path, from: localDir))
              .replaceAll('\\', p.separator);
          return p.s3(p.join(dir, relativePath).replaceAll('\\', p.separator));
        }
      }
    }
    return null;
  }

  static Watcher? watcherFromKey(String key) {
    final dirKey = p.s3(p.asDir(p.split(key).firstOrNull ?? ''));
    return _watcherMap[dirKey];
  }

  static String cachePathFromKey(String key) {
    return p.join(
      _downloadCacheDir,
      'app_${sha1.convert(utf8.encode(key)).toString()}.tmp',
    );
  }

  static String tagPathFromKey(String key) {
    return p.join(
      _downloadCacheDir,
      'app_${sha1.convert(utf8.encode(key)).toString()}.tag',
    );
  }

  static BackupMode backupModeFromKey(String key) {
    String? value = IniManager.config.value?.get('modes', key);
    if (value == null && p.split(key).length > 1) {
      return backupModeFromKey(p.s3(p.dirname(key)));
    } else {
      return BackupMode.fromValue(int.parse(value ?? '1'));
    }
  }

  static Future<void> onJobStatus(Job job, dynamic result) async {
    if (job is UploadJob &&
        job.status.value == JobStatus.completed &&
        result is RemoteFile) {
      _remoteFiles.removeWhere((file) => file.key == job.remoteKey);
      remoteFilesAdd(result);
    }
  }

  static Future<void> stopWatchers() async {
    if (kDebugMode) {
      debugPrint("Stopping all watchers...");
    }
    for (final watcher in _watcherMap.values.toList()) {
      await watcher.stop();
    }
  }

  static Future<void> addWatcher(String dir, {bool background = false}) async {
    final localDir = Main.pathFromKey(dir);

    if (localDir != null &&
        localDir.isNotEmpty &&
        Directory(localDir).existsSync()) {
      Watcher watcher = Watcher(remoteDir: dir);

      _watcherMap[dir] = watcher;
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

  static void _ensureDirectoryObjects() {
    final existingPaths = _remoteFiles.map((o) => o.key).toSet();

    for (final obj in _remoteFiles.toList()) {
      final normalized = p.normalize(obj.key);
      final isDir = p.isDir(normalized);

      final basePath = isDir
          ? p.s3(p.dirname(normalized.substring(0, normalized.length - 1)))
          : p.s3(p.dirname(normalized));

      if (basePath.isEmpty) continue;

      final parts = p.split(basePath);

      String current = '';
      for (final part in parts) {
        if (part.isEmpty) continue;

        current = p.join(current, part);
        final dirPath = p.asDir(current);

        if (!existingPaths.contains(dirPath)) {
          final dirObject = RemoteFile(
            key: dirPath,
            size: 0,
            etag: '',
            lastModified: DateTime.now(),
          );

          _remoteFiles.add(dirObject);
          existingPaths.add(dirPath);
        }
      }
    }
  }

  static Future<void> refreshWatchers({bool background = false}) async {
    loading.value = true;
    await stopWatchers();
    _watcherMap.clear();

    final dirs = _remoteFiles
        .where((dir) => p.isDir(dir.key))
        .map((file) => p.s3(p.asDir(p.split(file.key).firstOrNull ?? '')))
        .toSet()
        .toList();

    for (final dir in dirs) {
      await addWatcher(dir, background: background);
    }
    loading.value = false;
  }

  static Future<void> refreshProfiles() async {
    loading.value = true;
    final entries = (await ConfigManager.loadS3Config()).entries;
    for (final profile in _profiles.toList()) {
      if (entries.map((e) => e.key).contains(profile.name) == false) {
        _profiles.remove(profile);
        remoteFilesRemoveWhere(
          (file) => p.split(file.key).firstOrNull == profile.name,
        );
        await ConfigManager.saveRemoteFiles(Main.remoteFiles);
      }
    }
    for (final entry in entries) {
      if (_profiles.any((profile) => profile.name == entry.key)) {
        _profiles
            .firstWhere((profile) => profile.name == entry.key)
            .updateConfig(entry.value);
        continue;
      }
      _profiles.add(Profile(name: entry.key, cfg: entry.value));
    }
    loading.value = false;
  }

  static Future<void> listDirectories({bool background = false}) async {
    loading.value = true;
    if (!background && _remoteFiles.isEmpty) {
      remoteFilesSet(
        (await ConfigManager.loadRemoteFiles())
            .where(
              (file) => _profiles.any(
                (profile) => profile.name == p.split(file.key).firstOrNull,
              ),
            )
            .toList(),
      );
    }

    for (final profile in _profiles) {
      await profile.listDirectories(background: background);
    }
    if (kDebugMode) {
      debugPrint("Directory listing completed for all profiles");
    }
    loading.value = false;
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
        while (_remoteFiles.any(
              (remoteFile) => remoteFile.key == candidateKey,
            ) ==
            true) {
          candidateKey = p.join(p.s3(p.dirname(key)), '$base${'($count)'}$ext');
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
        while (_remoteFiles.any(
              (remoteFile) => remoteFile.key == candidateKey,
            ) ==
            true) {
          candidateKey = p.join(p.s3(p.dirname(key)), '$base${'($count)'}$ext');
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
    if (_cacheDir.isEmpty) {
      final directory = await getApplicationCacheDirectory();
      _cacheDir = directory.path;
    }
    if (_downloadCacheDir.isEmpty) {
      final directory = await getApplicationCacheDirectory();
      _downloadCacheDir = p.join(directory.path, 'Downloads');
    }
    if (_documentsDir.isEmpty) {
      final directory = await getApplicationDocumentsDirectory();
      _documentsDir = directory.path;
    }
    if (!ConfigManager.initialized.value) {
      await ConfigManager.init(_documentsDir);
    }
    Job.maxrun = ConfigManager.loadTransferConfig().maxConcurrentTransfers;
    refreshProfiles().then((_) {
      listDirectories(background: background);
    });
    initialized.value = true;
    if (kDebugMode) {
      debugPrint("Main initialized");
    }
  }
}

abstract class Job {
  final File localFile;
  final String remoteKey;
  final Digest md5;
  final int bytes;
  final Profile? profile;

  S3TransferTask? task;

  static int maxrun = 5;
  static bool scheduled = false;

  static final ValueNotifier<List<Job>> jobs = ValueNotifier<List<Job>>(
    <Job>[],
  );
  static final ManualNotifier onProgressUpdate = ManualNotifier();

  final ValueNotifier<JobStatus> status = ValueNotifier<JobStatus>(
    JobStatus.initialized,
  );
  final ValueNotifier<String> statusMsg = ValueNotifier<String>('');
  final ValueNotifier<int> bytesCompleted = ValueNotifier<int>(0);

  final void Function(Job job, dynamic result)? onStatus;

  Job({
    required this.localFile,
    required this.remoteKey,
    required this.bytes,
    required this.onStatus,
    required this.md5,
    required this.profile,
  });

  void add() {
    if (jobs.value.any(
      (job) =>
          job.localFile.path == localFile.path &&
          job.remoteKey == remoteKey &&
          job.status.value != JobStatus.completed,
    )) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        "Adding job: ${runtimeType == UploadJob ? 'Upload' : 'Download'} - $remoteKey",
      );
    }
    if (!jobs.value.contains(this)) jobs.value = [...jobs.value, this];
    if (jobs.value.any((job) => job.status.value == JobStatus.initialized)) {
      startall();
    }
  }

  bool startable() {
    return status.value != JobStatus.running &&
        status.value != JobStatus.completed &&
        (profile?.accessible.value ?? false);
  }

  Future<void> start() async {
    if (!startable()) return;
    try {
      if (runtimeType == UploadJob) {
        status.value = JobStatus.running;
        task = S3TransferTask(
          key: remoteKey,
          localFile: localFile,
          task: TransferTask.upload,
          profile: profile,
          md5: md5,
          onProgress: (sent, total) {
            bytesCompleted.value = sent;
            onStatus?.call(this, null);
          },
          onStatus: (value) {
            statusMsg.value = value;
            onStatus?.call(this, null);
          },
        );
        final result = await task!.start();
        status.value = JobStatus.stopped;
        if (bytesCompleted.value >= bytes && result != null) {
          status.value = JobStatus.completed;
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
          status.value = JobStatus.failed;
          bytesCompleted.value = 0;
          onStatus?.call(this, null);
        }
      }
      if (runtimeType == DownloadJob) {
        status.value = JobStatus.running;
        // final ifModifiedSince = await localFile.exists()
        //     ? localFile.lastModifiedSync()
        //     : null;
        final dir = Directory(p.s3(p.dirname(localFile.path)));
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
            bytesCompleted.value = received;
            onStatus?.call(this, null);
          },
          onStatus: (value) {
            statusMsg.value = value;
            onStatus?.call(this, null);
          },
        );
        await task!.start();
        status.value = JobStatus.stopped;
        if (bytesCompleted.value >= bytes) {
          status.value = JobStatus.completed;
          bytesCompleted.value = bytes;
          onStatus?.call(this, null);
        }
      }
    } catch (e) {
      status.value = JobStatus.failed;
      bytesCompleted.value = 0;
      statusMsg.value = "Error: ${e.toString()}";
      onStatus?.call(this, null);
    }
    onProgressUpdate.notifyListeners();
    startall();
  }

  bool stoppable() {
    return status.value == JobStatus.running ||
        status.value == JobStatus.initialized;
  }

  void stop() {
    if (stoppable()) {
      task?.cancel.call();
      status.value = JobStatus.stopped;
      onStatus?.call(this, null);
      onProgressUpdate.notifyListeners();
    }
  }

  bool removable() {
    return status.value != JobStatus.running && jobs.value.contains(this);
  }

  void remove() {
    if (removable()) jobs.value = jobs.value.where((j) => j != this).toList();
  }

  bool dismissible() {
    return status.value == JobStatus.completed;
  }

  void dismiss() {
    if (dismissible()) jobs.value = jobs.value.where((j) => j != this).toList();
  }

  static void continueAll() {
    for (var job in jobs.value.where(
      (job) =>
          job.status.value == JobStatus.stopped ||
          job.status.value == JobStatus.failed,
    )) {
      job.status.value = JobStatus.initialized;
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
          "Starting jobs: Running ${Job.jobs.value.where((job) => job.status.value == JobStatus.running).length}, Max Run $maxrun, Pending ${Job.jobs.value.where((job) => job.status.value == JobStatus.initialized).length}",
        );
      }

      while (Job.jobs.value
                  .where((job) => job.status.value == JobStatus.running)
                  .length <
              maxrun &&
          Job.jobs.value.any(
            (job) => job.status.value == JobStatus.initialized,
          )) {
        Job job = jobs.value.firstWhere(
          (job) => job.status.value == JobStatus.initialized,
        );
        job.start();
      }

      if (kDebugMode) {
        debugPrint(
          "Job scheduling completed: Running ${Job.jobs.value.where((job) => job.status.value == JobStatus.running).length}, Max Run $maxrun, Pending ${Job.jobs.value.where((job) => job.status.value == JobStatus.initialized).length}",
        );
      }
    } finally {
      scheduled = false;
    }
    onProgressUpdate.notifyListeners();
  }

  static void stopall() {
    for (var job in jobs.value) {
      job.stop();
    }
    onProgressUpdate.notifyListeners();
  }

  static void clearCompleted() {
    jobs.value = jobs.value
        .where((job) => job.status.value != JobStatus.completed)
        .toList();
  }

  static void clear() {
    jobs.value = [];
  }

  static void clearCache() {
    final directory = Directory(Main.cacheDir);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }

  static int cacheSize() {
    final directory = Directory(Main.cacheDir);
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
      bytesCompleted.value = offset;
      statusMsg.value =
          "Downloaded ${bytesToReadable(bytesCompleted.value)} of ${bytesToReadable(bytes)}";
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
      debugPrint("Analyzing sync status.value for ${localDir.path}");
    }
    final analyzer = SyncAnalyzer(
      localRoot: localDir,
      remoteFiles: Main.remoteFiles
          .where(
            (file) =>
                p.isWithin(
                  localDir.path,
                  Main.pathFromKey(file.key) ?? file.key,
                ) &&
                !p.isDir(file.key),
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
      if (Job.jobs.value.any(
            (job) =>
                job.localFile.path == file.path &&
                job.remoteKey == key &&
                job.status.value != JobStatus.completed,
          ) ||
          Main.ignoreKeyRegexps.any((regexp) => regexp.hasMatch(key))) {
        continue;
      }
      BackupMode mode = Main.backupModeFromKey(
        Main.keyFromPath(file.path) ?? '',
      );
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.uploadFile(key, file);
      }
    }

    for (RemoteFile file in result.modifiedRemotely) {
      if (Job.jobs.value.any(
            (job) =>
                job.remoteKey == file.key &&
                job.status.value != JobStatus.completed,
          ) ||
          Main.ignoreKeyRegexps.any((regexp) => regexp.hasMatch(file.key))) {
        continue;
      }
      BackupMode mode = Main.backupModeFromKey(file.key);
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.downloadFile(file);
      }
    }

    for (RemoteFile file in result.remoteOnly) {
      if (Job.jobs.value.any(
            (job) =>
                job.remoteKey == file.key &&
                job.status.value != JobStatus.completed,
          ) ||
          Main.ignoreKeyRegexps.any((regexp) => regexp.hasMatch(file.key))) {
        continue;
      }
      if (Main.backupModeFromKey(file.key) == BackupMode.sync) {
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
