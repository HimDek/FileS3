import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:pool/pool.dart';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_transfer_task.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/hash_util.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';

enum _FileSyncStatus {
  uploaded,
  modifiedLocally,
  modifiedRemotely,
  newFile,
  remoteOnly,
}

typedef _RemoteFileForComparator = ({
  String key,
  int size,
  String localPath,
  String etag,
  DateTime? lastModified,
});

class _SyncAnalysisResult {
  final List<String> newFile;
  final List<String> modifiedLocally;
  final List<String> modifiedRemotely;
  final List<String> uploaded;
  final List<String> remoteOnly;

  _SyncAnalysisResult({
    required this.newFile,
    required this.modifiedLocally,
    required this.modifiedRemotely,
    required this.uploaded,
    required this.remoteOnly,
  });
}

Iterable<String> _listCallback(({String path, bool recursive}) arg) {
  return Directory(
    arg.path,
  ).listSync(recursive: arg.recursive).whereType<File>().map((f) => f.path);
}

Pool _syncPool = Pool(1);

Future<_FileSyncStatus?> _fileSyncCompare({
  required File localFile,
  required _RemoteFileForComparator? remote,
  bool fullyIgnoreHash = false,
  bool optimisticIgnoreHash = false,
}) async {
  final localStat = await localFile.stat();
  final localExists = localStat.type == FileSystemEntityType.file;
  if (remote == null) {
    if (localExists) {
      return _FileSyncStatus.newFile;
    } else {
      return null;
    }
  }
  if (!localExists) return _FileSyncStatus.remoteOnly;

  final localSize = localStat.size;

  DateTime localModified = localStat.modified;
  if (localStat.changed.isAfter(localModified)) {
    localModified = localStat.changed;
  }
  if (localStat.accessed.isAfter(localModified)) {
    localModified = localStat.accessed;
  }

  bool modifiedBeforeRemote = localModified.isBefore(remote.lastModified!);

  if (localSize != remote.size) {
    return modifiedBeforeRemote
        ? _FileSyncStatus.modifiedRemotely
        : _FileSyncStatus.modifiedLocally;
  } else {
    if ((optimisticIgnoreHash && modifiedBeforeRemote) || fullyIgnoreHash) {
      // Guessing that the file is unmodified.
      return _FileSyncStatus.uploaded;
    }

    final localHash = (await HashUtil(localFile).md5Hash()).toString();

    return localHash ==
            remote
                .etag // Not possible but just in case
        ? _FileSyncStatus.uploaded
        : modifiedBeforeRemote
        ? _FileSyncStatus.modifiedRemotely
        : _FileSyncStatus.modifiedLocally;
  }
}

Future<_SyncAnalysisResult> _analysisCallback(
  ({
    Map<String, String> localFilesMap,
    Map<String, _RemoteFileForComparator> remoteFilesMap,
    bool fullyIgnoreHash,
    bool optimisticIgnoreHash,
  })
  args,
) async {
  final localFilesMap = args.localFilesMap;
  final remoteFilesMap = Map<String, _RemoteFileForComparator>.from(
    args.remoteFilesMap,
  );

  if (kDebugMode) {
    debugPrint(
      "Local files count: ${localFilesMap.length}, "
      "Remote files count: ${remoteFilesMap.length}",
    );
  }

  final newFile = <String>[];
  final modifiedLocally = <String>[];
  final modifiedRemotely = <String>[];
  final already = <String>[];

  for (var path in localFilesMap.values) {
    final remote = remoteFilesMap[path];
    final status = await _fileSyncCompare(
      localFile: File(path),
      remote: remote,
      fullyIgnoreHash: args.fullyIgnoreHash,
      optimisticIgnoreHash: args.optimisticIgnoreHash,
    );
    switch (status) {
      case _FileSyncStatus.newFile:
        newFile.add(path);
        remoteFilesMap.remove(path);
        break;
      case _FileSyncStatus.modifiedLocally:
        modifiedLocally.add(path);
        remoteFilesMap.remove(path);
        break;
      case _FileSyncStatus.modifiedRemotely:
        modifiedRemotely.add(remote!.key);
        remoteFilesMap.remove(path);
        break;
      case _FileSyncStatus.uploaded:
        already.add(remote!.key);
        remoteFilesMap.remove(path);
        break;
      case _FileSyncStatus.remoteOnly:
        break;
      default:
        break;
    }
  }

  final remoteOnly = remoteFilesMap.values
      .where(
        (r) => localFilesMap[r.key] == null && p.s3.basename(r.key).isNotEmpty,
      )
      .map((r) => r.key)
      .toList();

  if (kDebugMode) {
    debugPrint(
      "New Files: ${newFile.length} "
      "Modified Locally: ${modifiedLocally.length} "
      "Modified Remotely: ${modifiedRemotely.length} "
      "Remote Only: ${remoteOnly.length} "
      "Uploaded: ${already.length} ",
    );
  }

  return _SyncAnalysisResult(
    newFile: newFile,
    modifiedLocally: modifiedLocally,
    modifiedRemotely: modifiedRemotely,
    uploaded: already,
    remoteOnly: remoteOnly,
  );
}

Future<_SyncAnalysisResult> _syncAnalyze(
  String localRootPath,
  Map<String, RemoteFile> remoteFiles, {
  bool recursive = true,
  bool fullyIgnoreHash = false,
  bool optimisticIgnoreHash = false,
}) async {
  final files = await _syncPool.withResource<Iterable<String>>(
    () => _listCallback((path: localRootPath, recursive: recursive)),
  );

  final remoteFilesMap = Map<String, _RemoteFileForComparator>.fromEntries(
    remoteFiles.values.map((f) {
      final value = (
        key: f.key,
        size: f.size,
        localPath: p.absolute(Main.pathFromKey(f.key)),
        etag: f.etag,
        lastModified: f.lastModified,
      );
      return MapEntry<String, _RemoteFileForComparator>(value.localPath, value);
    }),
  );

  final localFilesMap = Map<String, String>.fromEntries(
    files.map((f) => MapEntry<String, String>(Main.keyFromPath(f) ?? '', f)),
  );

  return _syncPool.withResource<_SyncAnalysisResult>(
    () => compute(_analysisCallback, (
      localFilesMap: localFilesMap,
      remoteFilesMap: remoteFilesMap,
      fullyIgnoreHash: fullyIgnoreHash,
      optimisticIgnoreHash: optimisticIgnoreHash,
    )),
  );
}

abstract class Main {
  static String _documentsDir = '';
  static String _cacheDir = '';
  static String _thumbCacheDir = '';
  static String _downloadCacheDir = '';
  static final Map<String, Profile> _profiles = <String, Profile>{};
  static final Map<String, Watcher> _watcherMap = <String, Watcher>{};
  static final ManualNotifier onRemoteFilesChanged = ManualNotifier();
  static final ValueNotifier<bool> initialized = ValueNotifier<bool>(false);
  static final List<RegExp> _ignoreKeyRegexps = <RegExp>[
    RegExp(r'^.*[/\\]deletion-register\.ini$'),
  ];

  static RemoteFile root = RemoteFile(key: '', etag: '');

  static String get cacheDir => _cacheDir;

  static String get thumbCacheDir => _thumbCacheDir;

  static String get downloadCacheDir => _downloadCacheDir;

  static String get documentsDir => _documentsDir;

  static List<RegExp> get ignoreKeyRegexps =>
      UnmodifiableListView(_ignoreKeyRegexps);

  static Future<Iterable<RemoteFile>> get remoteFiles =>
      remoteFilesByDir('', recursive: true);
  static Map<String, Profile> get profiles => _profiles;

  static void clearCache() {
    final directory = Directory(_cacheDir);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }

  static int cacheSize() {
    return dirSize(Directory(_cacheDir));
  }

  static void clearThumbCache() {
    final directory = Directory(_thumbCacheDir);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }

  static int thumbCacheSize() {
    return dirSize(Directory(_thumbCacheDir));
  }

  static void clearDownloadCache() {
    final directory = Directory(_downloadCacheDir);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }

  static int downloadCacheSize() {
    return dirSize(Directory(_downloadCacheDir));
  }

  static void dirClear(Directory directory) {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }

  static int dirSize(Directory directory) {
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

  static Future<void> updateMetadata(
    String key,
    Map<String, String> headers,
  ) async {
    RemoteFile? file = (await remoteFileByKey(key));
    final oldEtag = file?.etag;
    file ??= RemoteFile(
      key: key,
      etag: headers['etag'] ?? '',
      size: int.tryParse(headers['content-length'] ?? '0') ?? 0,
      lastModified:
          DateTime.tryParse(headers['last-modified'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      created:
          DateTime.tryParse(headers['x-amz-meta-created'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      original:
          DateTime.tryParse(headers['x-amz-meta-original'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      contentType: headers['content-type'] ?? '',
      metadata: Map.fromEntries(
        headers.entries
            .where((e) => e.key.startsWith('x-amz-meta-'))
            .map(
              (e) => MapEntry(e.key.replaceFirst('x-amz-meta-', ''), e.value),
            ),
      ),
      deletedAt: null,
    );

    await profileFromKey(key)?.metaDB.addOrUpdateFile(file, oldEtag: oldEtag);
  }

  static Future<void> remoteFilesSet(List<RemoteFile> files) async {
    await remoteFilesClear(notify: false);
    await remoteFilesAddAll(files);
  }

  static Future<void> remoteFilesAddAll(Iterable<RemoteFile> files) async {
    final Map<Profile, List<RemoteFile>> groupedFiles = {};
    for (final file in files) {
      final profile = profileFromKey(file.key);
      if (profile != null) {
        groupedFiles.putIfAbsent(profile, () => []).add(file);
      }
    }
    await Future.wait(
      groupedFiles.entries.map((entry) async {
        final profile = entry.key;
        await profile.metaDB.withNestedTransaction((txn, localTxn) async {
          final addedDirs = <String>{};
          for (final file in entry.value) {
            await profile.metaDB.addIntermediateDirectories(
              file.key,
              addedDirs,
              txn: txn,
              localTxn: localTxn,
            );
            await profile.metaDB.addOrUpdateFile(
              file,
              txn: txn,
              localTxn: localTxn,
            );
          }
        });
      }),
    );
    onRemoteFilesChanged.notifyListeners();
  }

  static Future<void> remoteFilesAdd(
    RemoteFile file, {
    bool notify = true,
  }) async {
    final profile = profileFromKey(file.key);
    await profile?.metaDB.withNestedTransaction((txn, localTxn) async {
      final addedDirs = <String>{};
      await profile.metaDB.addIntermediateDirectories(
        file.key,
        addedDirs,
        txn: txn,
        localTxn: localTxn,
      );
      await profile.metaDB.addOrUpdateFile(file, txn: txn, localTxn: localTxn);
    });
    if (notify) {
      onRemoteFilesChanged.notifyListeners();
    }
  }

  static Future<void> remoteFilesClear({bool notify = true}) async {
    for (final profile in _profiles.values) {
      await profile.metaDB.clear();
    }
    if (notify) {
      onRemoteFilesChanged.notifyListeners();
    }
  }

  static Future<void> remoteFilesRemoveByKeys(
    Iterable<String> keys, {
    bool notify = true,
  }) async {
    for (String key in keys) {
      await remoteFileRemoveByKey(key, notify: false);
    }
    if (notify) {
      onRemoteFilesChanged.notifyListeners();
    }
  }

  static Future<void> remoteFileRemoveByKey(
    String key, {
    bool notify = true,
  }) async {
    await profileFromKey(key)?.metaDB.deleteFile(key);
    if (notify) {
      onRemoteFilesChanged.notifyListeners();
    }
  }

  static Future<RemoteFile?> remoteFileByKey(String key) async {
    if (key.isEmpty) {
      return root;
    }
    return await profileFromKey(key)?.metaDB.getFile(key);
  }

  static Future<List<RemoteFile>> remoteFilesByKeys(
    Iterable<String> keys,
  ) async {
    Map<Profile, List<String>> groupedFiles = {};
    for (String key in keys) {
      final profile = profileFromKey(key);
      if (profile != null) {
        groupedFiles.putIfAbsent(profile, () => []).add(key);
      }
    }

    final List<RemoteFile> files = [];
    for (final profile in groupedFiles.keys) {
      files.addAll(await profile.metaDB.getFiles(groupedFiles[profile]!));
    }
    return files;
  }

  static Future<Iterable<RemoteFile>> remoteFilesByDir(
    String dir, {
    bool recursive = true,
    bool includeDirs = true,
    bool includeFiles = true,
  }) async {
    if (dir.isEmpty) {
      final List<RemoteFile> files = [];
      for (final profile in _profiles.values) {
        files.addAll(
          await profile.metaDB.getFilesByDir(
            '',
            recursive: recursive,
            includeDirs: includeDirs,
            includeFiles: includeFiles,
          ),
        );
      }
      return files;
    }
    final res =
        await profileFromKey(
          dir,
        )?.metaDB.getFilesByDir(dir, recursive: recursive) ??
        [];
    return res;
  }

  static Future<Iterable<RemoteFile>> remoteFilesByDirs(
    Iterable<String> dirs, {
    bool recursive = true,
    bool includeDirs = true,
    bool includeFiles = true,
  }) async {
    final Map<Profile, List<String>> groupedDirs = {};
    for (String dir in dirs) {
      final profile = profileFromKey(dir);
      if (profile != null) {
        groupedDirs.putIfAbsent(profile, () => []).add(dir);
      }
    }
    final List<RemoteFile> files = [];
    for (final profile in groupedDirs.keys) {
      files.addAll(
        await profile.metaDB.getFilesByDirs(
          groupedDirs[profile]!,
          recursive: recursive,
          includeDirs: includeDirs,
          includeFiles: includeFiles,
        ),
      );
    }
    return files;
  }

  static Profile? profileFromKey(String key) {
    try {
      return _profiles[p.s3.split(key).firstOrNull];
    } catch (e) {
      return null;
    }
  }

  static String pathFromKey(String key) {
    final localDir = IniManager.config.value?.get(
      'directories',
      p.s3.asDir(p.s3.split(key).firstOrNull ?? ''),
    );
    if (localDir != null) {
      final path = p.context.joinAll([localDir, ...p.s3.split(key).sublist(1)]);
      return p.isDir(key) ? p.asDir(path, context: p.context) : path;
    } else {
      return key;
    }
  }

  static String? keyFromPath(String path) {
    for (String dir in IniManager.config.value!.options('directories')!) {
      final localDir = IniManager.config.value!.get('directories', dir);
      if (localDir != null) {
        if (p.context.isWithin(localDir, path) ||
            p.context.equals(localDir, path)) {
          final relativePath = p.context.relative(path, from: localDir);
          return p.s3.joinAll([dir, ...p.context.split(relativePath)]);
        }
      }
    }
    return null;
  }

  static Watcher? watcherFromKey(String key) {
    final dirKey = p.s3.asDir(p.s3.split(key).firstOrNull ?? '');
    return _watcherMap[dirKey];
  }

  static String thumbPathFromKey(String key) {
    return p.context.joinAll([
      _thumbCacheDir,
      for (String part in p.s3.split(key))
        sha1.convert(utf8.encode(part)).toString(),
    ]);
  }

  static String cachePathFromKey(String key) {
    return p.context.joinAll([
          _downloadCacheDir,
          for (String part in p.s3.split(key))
            sha1.convert(utf8.encode(part)).toString(),
        ]) +
        (!p.isDir(key) ? p.s3.extension(key) : '');
  }

  static String tagPathFromKey(String key) {
    return "${cachePathFromKey(key)}.tag";
  }

  static BackupMode backupModeFromKey(String key) {
    String? value = IniManager.config.value?.get('modes', key);
    if (value == null && p.s3.split(key).length > 1) {
      return backupModeFromKey(p.s3.dirname(key));
    } else {
      return BackupMode.fromValue(int.parse(value ?? '1'));
    }
  }

  static Future<void> stopWatchers() async {
    if (kDebugMode) {
      debugPrint("Stopping all watchers...");
    }
    for (final watcher in _watcherMap.values) {
      await watcher.stop();
    }
  }

  static Future<void> addWatcher(String dir, {bool background = false}) async {
    final localDir = Main.pathFromKey(dir);

    if (p.isAbsolute(localDir) &&
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

  static Future<void> refreshWatchers({bool background = false}) async {
    loading.value = true;
    await stopWatchers();
    _watcherMap.clear();

    for (final dir in _profiles.keys) {
      await addWatcher(dir, background: background);
    }
    loading.value = false;
  }

  static Future<void> refreshProfiles() async {
    loading.value = true;
    final entries = (await ConfigManager.loadS3Config()).entries;
    for (final profile in _profiles.values) {
      if (entries.every((e) => e.key != profile.name)) {
        profile.dispose();
        _profiles.remove(profile.name);
        await remoteFileRemoveByKey(profile.name, notify: false);
      }
    }
    for (final entry in entries) {
      if (_profiles.containsKey(entry.key)) {
        _profiles[entry.key]!.updateConfig(entry.value);
        continue;
      }
      _profiles[entry.key] = Profile(name: entry.key, cfg: entry.value);
      await _profiles[entry.key]!.init();
    }
    loading.value = false;
  }

  static Future<void> listDirectories({bool background = false}) async {
    loading.value = true;
    for (final profile in _profiles.values) {
      await profile.listDirectories(background: background);
    }
    loading.value = false;
  }

  static Future<void> downloadFile(
    String key, {
    String? localPath,
    VoidCallback? onComplete,
  }) async {
    final file = await remoteFileByKey(key);
    if (file == null) {
      return;
    }
    final job = DownloadJob(
      localFile: File(localPath ?? pathFromKey(key)),
      remoteKey: key,
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
      profile: profileFromKey(key),
    );
    job.status.addListener(() {
      if (job.status.value == JobStatus.completed) {
        onComplete?.call();
      }
    });
    job.add();
  }

  static Future<void> uploadFile(
    String key,
    File file, {
    VoidCallback? onComplete,
  }) async {
    if (!file.existsSync()) {
      return;
    }
    Job? job;
    Digest md5 = await HashUtil(file).md5Hash();
    String localEtag = base64.encode(md5.bytes);
    if (p.context.equals(pathFromKey(key), file.path)) {
      final remoteFile = await remoteFileByKey(key);
      if (remoteFile != null &&
          remoteFile.deletedAt?.isAfter(
                DateTime.now().subtract(const Duration(minutes: 5)),
              ) ==
              true &&
          remoteFile.etag == localEtag) {
        file.deleteSync();
      } else {
        job = UploadJob(
          localFile: file,
          remoteKey: key,
          bytes: file.lengthSync(),
          md5: md5,
          profile: profileFromKey(key),
        );
      }
    } else if (p.context.isAbsolute(pathFromKey(key))) {
      final newKey = await () async {
        String base = p.s3.basenameWithoutExtension(key);
        String ext = p.s3.extension(key);
        int count = 1;
        String candidateKey = key;
        while ((await remoteFileByKey(candidateKey)) != null) {
          candidateKey = p.s3.join(p.s3.dirname(key), '$base${'($count)'}$ext');
          count++;
        }
        return candidateKey;
      }();
      if (!File(pathFromKey(newKey)).parent.existsSync()) {
        File(pathFromKey(newKey)).parent.createSync(recursive: true);
      }
      file.copySync(pathFromKey(newKey));
      job = UploadJob(
        localFile: File(pathFromKey(newKey)),
        remoteKey: key,
        bytes: file.lengthSync(),
        md5: md5,
        profile: profileFromKey(key),
      );
    } else {
      final newKey = await () async {
        String base = p.s3.basenameWithoutExtension(key);
        String ext = p.s3.extension(key);
        int count = 1;
        String candidateKey = key;
        while ((await remoteFileByKey(candidateKey)) != null) {
          candidateKey = p.s3.join(p.s3.dirname(key), '$base${'($count)'}$ext');
          count++;
        }
        return candidateKey;
      }();
      job = UploadJob(
        localFile: file,
        remoteKey: newKey,
        bytes: file.lengthSync(),
        md5: md5,
        profile: profileFromKey(newKey),
      );
    }
    job?.status.addListener(() {
      if (job?.status.value == JobStatus.completed) {
        onComplete?.call();
      }
    });
    job?.add();
  }

  static Future<void> copyFile(
    String key,
    String newKey, {
    bool refresh = true,
  }) async {
    loading.value = true;

    try {
      RemoteFile? oldFile = await remoteFileByKey(key);
      if (oldFile == null) {
        return;
      }

      final Profile? profile = profileFromKey(key);
      final Profile? newProfile = profileFromKey(newKey);

      if (profile != newProfile) {
        try {
          await newProfile?.fileManager?.copyFile(
            key,
            newKey,
            sourceProfile: profile,
          );
        } catch (e) {
          if (e is S3Exception && e.code == 403) {
            File file = File(pathFromKey(key));
            if (file.existsSync()) {
              uploadFile(newKey, file);
            } else {
              file = File(cachePathFromKey(key));
              if (file.existsSync()) {
                uploadFile(newKey, file);
              } else {
                downloadFile(
                  key,
                  localPath: file.path,
                  onComplete: () {
                    uploadFile(newKey, file);
                  },
                );
              }
            }
            return;
          } else {
            rethrow;
          }
        }
      }

      final headers = await profile!.fileManager!.copyFile(key, newKey);

      RemoteFile newFile = RemoteFile(
        key: newKey,
        size: oldFile.size,
        etag: oldFile.etag,
        lastModified:
            DateTime.tryParse(headers["last-modified"] ?? '') ??
            oldFile.lastModified,
      );

      final file = File(pathFromKey(key));
      final cacheFile = File(cachePathFromKey(key));

      if (file.existsSync() && p.isAbsolute(pathFromKey(newKey))) {
        final newLocalFile = File(pathFromKey(newKey));
        if (!newLocalFile.parent.existsSync()) {
          newLocalFile.parent.createSync(recursive: true);
        }
        file.copySync(newLocalFile.path);
        isDownloaded[newKey] = true;
      }

      if (cacheFile.existsSync() && p.isAbsolute(pathFromKey(newKey))) {
        final newCacheFile = File(pathFromKey(newKey));
        if (!newCacheFile.parent.existsSync()) {
          newCacheFile.parent.createSync(recursive: true);
        }
        cacheFile.copySync(newCacheFile.path);
      }
      remoteFilesAdd(newFile, notify: false);
    } finally {
      if (refresh) {
        loading.value = false;
      }
    }
  }

  // uses copyFile
  static Future<void> copyDirectory(
    String dir,
    String newDir, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;
    try {
      final keys = (await remoteFilesByDir(
        dir,
      )).map((f) => f.key).where((key) => !p.isDir(key));
      int progressCount = 0;
      final totalFiles = keys.length;
      for (final file in keys) {
        progressCount += 1;
        (preprogress ?? progress).value = progressCount / totalFiles;
        await copyFile(
          file,
          p.s3.join(newDir, p.s3.relative(file, from: dir)),
          refresh: false,
        );
      }
    } finally {
      if (refresh) {
        loading.value = false;
      }
    }
  }

  static Future<void> deleteFiles(
    Iterable<String> keys, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    try {
      final Map<Profile, List<String>> profileKeys = {};
      for (final key in keys) {
        final profile = profileFromKey(key);
        if (profile != null) {
          profileKeys.putIfAbsent(profile, () => []).add(key);
        }
      }

      int progressCount = 0;
      await Future.wait(
        profileKeys.entries.map((entry) async {
          final profile = entry.key;
          final keysForProfile = entry.value;
          await profile.metaDB.withNestedTransaction((txn, localTxn) async {
            for (final key in keysForProfile) {
              await profile.metaDB.deleteFile(
                key,
                txn: txn,
                localTxn: localTxn,
              );
            }
          });
          for (final key in keysForProfile) {
            progressCount += 1;
            (preprogress ?? progress).value =
                progressCount / profileKeys.values.expand((e) => e).length;
            await profile.fileManager?.deleteFile(key);
            File file = File(pathFromKey(key));
            File cacheFile = File(cachePathFromKey(key));
            if (file.existsSync()) {
              file.deleteSync();
            }
            if (cacheFile.existsSync()) {
              cacheFile.deleteSync();
            }
          }

          remoteFilesRemoveByKeys(keysForProfile, notify: true);
        }),
      );
    } finally {
      if (refresh) {
        loading.value = false;
      }
    }
  }

  static Future<void> deleteS3(
    Iterable<String> keys, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    try {
      List<String> files = [];

      for (final key in keys) {
        files.add(key);
        if (p.isDir(key)) {
          files.addAll((await remoteFilesByDir(key)).map((f) => f.key));
        }
      }

      final Map<Profile, List<String>> profileFiles = {};
      for (final file in files) {
        final profile = profileFromKey(file);
        if (profile != null && (await remoteFileByKey(file)) != null) {
          profileFiles.putIfAbsent(profile, () => []).add(file);
        }
      }

      int progressCount = 0;
      int total = profileFiles.values
          .expand((e) => e)
          .where((file) => !p.isDir(file))
          .length;
      await Future.wait(
        profileFiles.entries.map((entry) async {
          final profile = entry.key;
          final filesForProfile = entry.value
              .where((file) => !p.isDir(file))
              .toList();
          await profile.metaDB.withNestedTransaction((txn, localTxn) async {
            for (final key in filesForProfile) {
              await profile.metaDB.deleteFile(
                key,
                txn: txn,
                localTxn: localTxn,
              );
            }
          });
          for (final file in filesForProfile.where((file) => !p.isDir(file))) {
            progressCount += 1;
            (preprogress ?? progress).value = progressCount / total;
            await profile.fileManager?.deleteFile(file);
          }

          remoteFilesRemoveByKeys(
            filesForProfile.where((key) => !p.isDir(key)),
            notify: true,
          );

          final dirsForProfile = entry.value
              .where((file) => p.isDir(file))
              .toList();
          dirsForProfile.sort((a, b) => b.length.compareTo(a.length));

          for (final dir in dirsForProfile) {
            progressCount += 1;
            (preprogress ?? progress).value = progressCount / total;
            await profile.fileManager?.deleteFile(dir);
          }

          remoteFilesRemoveByKeys(dirsForProfile, notify: true);

          await profile.refreshRemote(dir: profile.name);
        }),
      );
    } finally {
      if (refresh) {
        loading.value = false;
      }
    }
  }

  // uses deleteS3
  static Future<void> deleteDirectories(
    Iterable<String> dirs, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    try {
      await deleteS3(
        dirs,
        refresh: false,
        preprogress: preprogress ?? progress,
      );

      for (final dirS in dirs) {
        final dir = Directory(pathFromKey(dirS));
        final cacheDir = Directory(cachePathFromKey(dirS));
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
        if (cacheDir.existsSync()) {
          cacheDir.deleteSync(recursive: true);
        }
      }
    } finally {
      if (refresh) {
        loading.value = false;
      }
    }
  }

  // uses copyFile and deleteFiles
  static Future<void> moveFiles(
    Iterable<String> keys,
    Iterable<String> newKeys, {
    bool refresh = true,
  }) async {
    loading.value = true;
    try {
      int i = 1;
      final ikeys = keys.iterator;
      final inewKeys = newKeys.iterator;
      while (ikeys.moveNext() && inewKeys.moveNext()) {
        final key = ikeys.current;
        final newKey = inewKeys.current;
        progress.value = i * 0.5 / keys.length;
        await copyFile(key, newKey, refresh: false);
        File file = File(pathFromKey(key));
        if (file.existsSync()) {
          renameOrCopyAndDelete(file, pathFromKey(newKey));
        }
        File cacheFile = File(cachePathFromKey(key));
        if (cacheFile.existsSync()) {
          renameOrCopyAndDelete(cacheFile, pathFromKey(newKey));
        }
        i++;
      }
      final ValueNotifier<double> preprogress = ValueNotifier<double>(0.0);
      preprogress.addListener(() {
        progress.value = 0.5 + 0.5 * preprogress.value;
      });
      await deleteFiles(keys, refresh: false, preprogress: preprogress);
      preprogress.dispose();
    } finally {
      if (refresh) {
        loading.value = false;
      }
    }
  }

  // uses copyDirectory and deleteDirectories
  static Future<void> moveDirectories(
    Iterable<String> dirs,
    Iterable<String> newDirs, {
    bool refresh = true,
  }) async {
    loading.value = true;
    try {
      final iDirs = dirs.iterator;
      final iNewDirs = newDirs.iterator;

      int i = 1;
      while (iDirs.moveNext() && iNewDirs.moveNext()) {
        final dir = iDirs.current;
        final newDir = iNewDirs.current;
        final ValueNotifier<double> preprogress = ValueNotifier<double>(0.0);
        preprogress.addListener(() {
          progress.value = i * 0.5 * preprogress.value / dirs.length;
        });
        await copyDirectory(
          dir,
          newDir,
          refresh: false,
          preprogress: preprogress,
        );
        preprogress.dispose();
        i++;
      }
      final ValueNotifier<double> preprogress = ValueNotifier<double>(0.0);
      preprogress.addListener(() {
        progress.value = 0.5 + 0.5 * preprogress.value;
      });
      await deleteDirectories(dirs, refresh: false, preprogress: preprogress);
      preprogress.dispose();
    } finally {
      if (refresh) {
        loading.value = false;
        progress.value = 0.0;
      }
    }
  }

  static Future<void> init({bool background = false}) async {
    if (_cacheDir.isEmpty) {
      final directory = await getApplicationCacheDirectory();
      _cacheDir = p.context.join(directory.path, 'tmp');
    }
    if (_thumbCacheDir.isEmpty) {
      final directory = await getApplicationCacheDirectory();
      _thumbCacheDir = p.context.join(directory.path, 'thumbnails');
    }
    if (_downloadCacheDir.isEmpty) {
      final directory = await getApplicationCacheDirectory();
      _downloadCacheDir = p.context.join(directory.path, 'downloads');
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

typedef JobKey = ({String remoteKey, String localPath});
typedef JobQuery = ({String? remoteKey, String? localPath, JobStatus? status});

abstract class Job {
  final File localFile;
  final String remoteKey;
  final Digest md5;
  final int bytes;
  final Profile? profile;
  late final int responseCode;

  S3TransferTask? task;

  static int maxrun = 5;
  static bool scheduled = false;

  static final Map<String, List<JobKey>> _remoteKeyToJobKeys = {};
  static final Map<JobKey, Job> _jobs = {};
  static final Map<JobKey, Job> _readyJobs = {};
  static final Map<JobKey, Job> _runningJobs = {};
  static final Map<JobKey, Job> _completedJobs = {};
  static final Map<JobKey, Job> _failedJobs = {};
  static final Map<JobKey, Job> _blockedJobs = {};
  static final ManualNotifier onJobsChanged = ManualNotifier();
  static final ManualNotifier onProgressUpdate = ManualNotifier();

  static Iterable<Job> get jobs => _jobs.values;
  static Iterable<Job> get readyJobs => _readyJobs.values;
  static Iterable<Job> get runningJobs => _runningJobs.values;
  static Iterable<Job> get completedJobs => _completedJobs.values;
  static Iterable<Job> get failedJobs => _failedJobs.values;
  static Iterable<Job> get blockedJobs => _blockedJobs.values;

  static Map<String, List<JobKey>> get remoteKeyToJobKeys =>
      Map.unmodifiable(_remoteKeyToJobKeys);
  static Map<JobKey, Job> get allMap => Map.unmodifiable(_jobs);
  static Map<JobKey, Job> get readyMap => Map.unmodifiable(_readyJobs);
  static Map<JobKey, Job> get runningMap => Map.unmodifiable(_runningJobs);
  static Map<JobKey, Job> get completedMap => Map.unmodifiable(_completedJobs);
  static Map<JobKey, Job> get failedMap => Map.unmodifiable(_failedJobs);
  static Map<JobKey, Job> get blockedMap => Map.unmodifiable(_blockedJobs);

  JobKey get jobKey => (remoteKey: remoteKey, localPath: localFile.path);
  Map<JobKey, Job> get _statusMap => switch (status.value) {
    JobStatus.ready => _readyJobs,
    JobStatus.running => _runningJobs,
    JobStatus.completed => _completedJobs,
    JobStatus.failed => _failedJobs,
    JobStatus.blocked => _blockedJobs,
  };

  final ValueNotifier<JobStatus> status = ValueNotifier<JobStatus>(
    JobStatus.ready,
  );
  final ValueNotifier<String> statusMsg = ValueNotifier<String>('');
  final ValueNotifier<int> bytesCompleted = ValueNotifier<int>(0);

  Job({
    required this.localFile,
    required this.remoteKey,
    required this.bytes,
    required this.md5,
    required this.profile,
  });

  void _add() {
    status.value == JobStatus.ready
        ? _readyJobs[jobKey] = this
        : _readyJobs.remove(jobKey);
    status.value == JobStatus.running
        ? _runningJobs[jobKey] = this
        : _runningJobs.remove(jobKey);
    status.value == JobStatus.completed
        ? _completedJobs[jobKey] = this
        : _completedJobs.remove(jobKey);
    status.value == JobStatus.failed
        ? _failedJobs[jobKey] = this
        : _failedJobs.remove(jobKey);
    status.value == JobStatus.blocked
        ? _blockedJobs[jobKey] = this
        : _blockedJobs.remove(jobKey);
  }

  Future<void> add() async {
    if (jobs.any(
      (job) =>
          job.localFile.path == localFile.path &&
          job.remoteKey == remoteKey &&
          job.status.value != JobStatus.completed,
    )) {
      return;
    }
    _remoteKeyToJobKeys.putIfAbsent(remoteKey, () => []).add(jobKey);
    _jobs[jobKey] = this;
    _add();
    status.addListener(_add);
    onJobsChanged.notifyListeners();
    startall();
  }

  bool startable() {
    return status.value != JobStatus.running &&
        status.value != JobStatus.completed &&
        (profile?.accessible.value ?? false);
  }

  Future<HttpClientResponse?> start() async {
    if (!startable()) return null;
    try {
      if (runtimeType == UploadJob) {
        status.value = JobStatus.running;
        statusMsg.value = "Starting upload...";
        task = S3TransferTask(
          key: remoteKey,
          localFile: localFile,
          task: TransferTask.upload,
          profile: profile,
          md5: md5,
          onProgress: (sent, total) {
            bytesCompleted.value = sent;
          },
          onStatus: (value) {
            statusMsg.value = value;
          },
        );
        final result = await task!.start();
        status.value = JobStatus.blocked;
        if (bytesCompleted.value >= bytes && result != null) {
          status.value = JobStatus.completed;
          final headers = await Main.profileFromKey(
            remoteKey,
          )?.fileManager?.headObject(remoteKey);
          if (headers != null) {
            Main.updateMetadata(remoteKey, headers);
          }
          final resultFile = RemoteFile(
            key: remoteKey,
            size: int.tryParse(headers?['content-length'] ?? '') ?? bytes,
            etag: headers?['etag']?.replaceAll('"', '') ?? '',
            lastModified:
                DateTime.tryParse(headers?['last-modified'] ?? '') ??
                localFile.lastModifiedSync(),
          );
          isDownloaded[remoteKey] = true;
          Main.remoteFilesAdd(resultFile);
        } else {
          status.value = JobStatus.failed;
          bytesCompleted.value = 0;
        }
        return result;
      }
      if (runtimeType == DownloadJob) {
        status.value = JobStatus.running;
        statusMsg.value = "Starting download...";
        // final ifModifiedSince = await localFile.exists()
        //     ? localFile.lastModifiedSync()
        //     : null;
        final dir = Directory(p.context.dirname(localFile.path));
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
          },
          onStatus: (value) {
            statusMsg.value = value;
          },
        );
        final result = await task!.start();
        status.value = JobStatus.blocked;
        if (bytesCompleted.value >= bytes) {
          status.value = JobStatus.completed;
          bytesCompleted.value = bytes;
        }
        return result;
      }
      return null;
    } catch (e) {
      status.value = JobStatus.failed;
      bytesCompleted.value = 0;
      statusMsg.value = "Error: ${e.toString()}";
    } finally {
      onProgressUpdate.notifyListeners();
      startall();
    }
    return null;
  }

  bool stoppable() {
    return status.value == JobStatus.running || status.value == JobStatus.ready;
  }

  void stop() {
    if (stoppable()) {
      task?.cancel.call();
      status.value = JobStatus.blocked;
      onProgressUpdate.notifyListeners();
    }
  }

  bool removable() {
    return status.value != JobStatus.running &&
        (_jobs.containsKey(jobKey) || _statusMap.containsKey(jobKey));
  }

  void remove() {
    if (removable()) {
      _jobs.remove(jobKey);
      _remoteKeyToJobKeys[remoteKey]?.remove(jobKey);
      _statusMap.remove(jobKey);
      onJobsChanged.notifyListeners();
      dispose();
    }
  }

  bool dismissible() {
    return status.value == JobStatus.completed &&
        (_jobs.containsKey(jobKey) || _statusMap.containsKey(jobKey));
  }

  void dismiss({bool notify = true}) {
    if (dismissible()) {
      _jobs.remove(jobKey);
      _remoteKeyToJobKeys[remoteKey]?.remove(jobKey);
      _statusMap.remove(jobKey);
      if (notify) {
        onJobsChanged.notifyListeners();
      }
      dispose();
    }
  }

  void dispose() {
    status.dispose();
    statusMsg.dispose();
    bytesCompleted.dispose();
  }

  static Future<void> continueAll() async {
    while (failedJobs.isNotEmpty) {
      failedJobs.firstOrNull?.status.value = JobStatus.ready;
    }
    while (blockedJobs.isNotEmpty) {
      blockedJobs.firstOrNull?.status.value = JobStatus.ready;
    }
    startall();
  }

  static Future<void> startall() async {
    if (scheduled) {
      return;
    }

    try {
      scheduled = true;
      while (runningJobs.length < maxrun) {
        Job? job = readyJobs.firstOrNull;
        if (job == null) {
          break;
        }
        job.start();
      }
    } finally {
      scheduled = false;
      onProgressUpdate.notifyListeners();
    }
  }

  static Future<void> stopall() async {
    while (runningJobs.isNotEmpty) {
      runningJobs.firstOrNull?.stop();
    }
    while (readyJobs.isNotEmpty) {
      readyJobs.firstOrNull?.stop();
    }
    onProgressUpdate.notifyListeners();
  }

  static Future<void> clearCompleted() async {
    while (completedJobs.isNotEmpty) {
      completedJobs.firstOrNull?.dismiss(notify: false);
    }
    onJobsChanged.notifyListeners();
  }

  static Future<void> disposeAll() async {
    while (jobs.isNotEmpty) {
      Job? job = _jobs.remove(jobs.first.jobKey);
      _remoteKeyToJobKeys[job?.remoteKey]?.remove(job?.jobKey);
      job?._statusMap.remove(jobs.first.jobKey);
      job?.dispose();
    }
    onJobsChanged.notifyListeners();
  }
}

class UploadJob extends Job {
  String? ifMatch;

  UploadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.md5,
    required super.profile,
    this.ifMatch,
  });
}

class DownloadJob extends Job {
  DownloadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
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

  Future<void> scan({String? dirKey, bool recursive = true}) async {
    final localDir = Directory(Main.pathFromKey(dirKey ?? remoteDir));

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

    try {
      scanning = true;

      if (!localDir.existsSync()) {
        if (kDebugMode) {
          debugPrint("Local directory does not exist: ${localDir.path}");
        }
        scanning = false;
        return;
      }

      final remoteFiles = Map.fromEntries(
        (await Main.remoteFilesByDir(remoteDir))
            .where((file) => !p.isDir(file.key))
            .map((file) => MapEntry(file.key, file)),
      );

      if (remoteFiles.isEmpty) {
        if (kDebugMode) {
          debugPrint("Remote files list is empty, skipping refresh.");
        }
        scanning = false;
        return;
      }

      if (kDebugMode) {
        debugPrint("Analyzing Sync for ${localDir.path}");
      }

      final transferConfig = ConfigManager.loadTransferConfig();

      final result = await _syncAnalyze(
        localDir.path,
        remoteFiles,
        recursive: recursive,
        fullyIgnoreHash: transferConfig.hashIgnoreMode == HashIgnoreMode.always,
        optimisticIgnoreHash:
            transferConfig.hashIgnoreMode == HashIgnoreMode.optimistic,
      );

      for (String path in [...result.newFile, ...result.modifiedLocally]) {
        final key = Main.keyFromPath(path) ?? '';
        final jobKey = (remoteKey: key, localPath: path);
        if (Job.allMap.containsKey(jobKey) &&
            Job.allMap[jobKey]?.status.value != JobStatus.completed) {
          continue;
        }
        // BackupMode mode = Main.backupModeFromKey(Main.keyFromPath(path) ?? '');
        // if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.uploadFile(key, File(path));
        // }
      }

      for (String key in result.modifiedRemotely) {
        final path = Main.pathFromKey(key);
        final jobKey = (remoteKey: key, localPath: path);
        if (Job.allMap.containsKey(jobKey) &&
            Job.allMap[jobKey]?.status.value != JobStatus.completed) {
          continue;
        }
        // BackupMode mode = Main.backupModeFromKey(key);
        // if (mode == BackupMode.sync || mode == BackupMode.upload) {
        Main.downloadFile(key);
        // }
      }

      for (String key in result.remoteOnly) {
        isDownloaded[key] = false;
        final path = Main.pathFromKey(key);
        final jobKey = (remoteKey: key, localPath: path);
        if (Job.allMap.containsKey(jobKey) &&
            Job.allMap[jobKey]?.status.value != JobStatus.completed) {
          continue;
        }
        if (Main.backupModeFromKey(key) == BackupMode.sync) {
          Main.downloadFile(key);
        }
      }

      for (String key in result.uploaded) {
        isDownloaded[key] = true;
      }
      Main.onRemoteFilesChanged.notifyListeners();

      if (kDebugMode) {
        debugPrint("Scan completed for ${localDir.path}");
      }
    } finally {
      scanning = false;
      if (_rescanQueued) {
        _rescanQueued = false;
        unawaited(scan());
      }
    }
  }

  Future<void> start() async {
    final localDir = Directory(Main.pathFromKey(remoteDir));

    if (watching) {
      if (kDebugMode) {
        debugPrint("Watcher is already running for ${localDir.path}");
      }
      return;
    }
    watching = true;

    await scan();

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      subscription = localDir.watch(recursive: true).listen((event) async {
        switch (event) {
          case FileSystemCreateEvent e:
            if (e.isDirectory) {
              break;
            }
            Main.uploadFile(Main.keyFromPath(e.path) ?? '', File(e.path));
            break;
          case FileSystemModifyEvent e:
            if (e.isDirectory) {
              if (e.contentChanged) {
                unawaited(scan(dirKey: Main.keyFromPath(e.path)));
              }
              break;
            }
            Main.uploadFile(Main.keyFromPath(e.path) ?? '', File(e.path));
            break;
          case FileSystemDeleteEvent e:
            final key = Main.keyFromPath(e.path);
            if (key == null) {
              break;
            }
            if (p.isDir(e.path)) {
              await Main.deleteDirectories([key], refresh: false);
              break;
            }
            await Main.deleteFiles([key], refresh: false);
            break;
          case FileSystemMoveEvent e:
            final srcKey = Main.keyFromPath(e.path);
            final destKey = e.destination != null
                ? Main.keyFromPath(e.destination!)
                : null;
            if (srcKey == null) {
              break;
            }
            if (destKey == null) {
              if (p.isDir(e.path)) {
                await Main.deleteDirectories([srcKey], refresh: false);
              } else {
                await Main.deleteFiles([srcKey], refresh: false);
              }
              break;
            }
            if (e.isDirectory) {
              await Main.moveDirectories([srcKey], [destKey], refresh: false);
              break;
            }
            await Main.moveFiles([srcKey], [destKey], refresh: false);
            break;
        }
        final file = File(event.path);
        if (file.existsSync()) {
          if (kDebugMode) {
            debugPrint(
              "File system event detected: ${event.type} - ${event.path}",
            );
          }
          // unawaited(scan());
        }
      });
    } else {
      timer = Timer.periodic(const Duration(seconds: 60), (timer) {
        if (kDebugMode) {
          debugPrint("Periodic scan triggered for ${localDir.path}");
        }
        unawaited(scan());
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
