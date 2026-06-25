import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:pool/pool.dart';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_transfer_task.dart';
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
}) async {
  final localExists = await localFile.exists();
  if (remote == null) {
    if (localExists) {
      return _FileSyncStatus.newFile;
    } else {
      return null;
    }
  }
  if (!localExists) return _FileSyncStatus.remoteOnly;

  final localHash = (await HashUtil(localFile).md5Hash()).toString();

  return localHash == remote.etag
      ? _FileSyncStatus.uploaded
      : remote.lastModified!.isAfter(await localFile.lastModified())
      ? _FileSyncStatus.modifiedRemotely
      : _FileSyncStatus.modifiedLocally;
}

Future<_SyncAnalysisResult> _analysisCallback(
  ({
    Map<String, String> localFilesMap,
    Map<String, _RemoteFileForComparator> remoteFilesMap,
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
        already.add(path);
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
}) async {
  final files = await _syncPool.withResource<Iterable<String>>(
    () => _listCallback((path: localRootPath, recursive: recursive)),
  );

  final remoteFilesMap = Map<String, _RemoteFileForComparator>.fromEntries(
    remoteFiles.values.map((f) {
      final value = (
        key: f.key,
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
    )),
  );
}

sealed class Node<T, N extends Node<T, N>> {
  T value;
  final Map<String, N> children;
  Node<T, N>? parent;

  N createNode({required T value, Node<T, N>? parent});

  Node({required this.value, Map<String, N>? children, this.parent})
    : children = children ?? {};

  N? operator [](String key) {
    return children[key];
  }

  void operator []=(String key, T value) {
    children[key] = createNode(value: value, parent: this);
  }

  bool get isEmpty => children.isEmpty;

  void clear() {
    children.clear();
    parent?.children.removeWhere((key, child) => identical(child, this));
    parent = null;
  }

  Iterable<N> getDecendants({bool recursive = false}) sync* {
    for (final child in children.values) {
      yield child;

      if (recursive) {
        yield* child.getDecendants(recursive: true);
      }
    }
  }
}

class DirectoryTree extends Node<RemoteFile, DirectoryTree> {
  @override
  DirectoryTree createNode({
    required RemoteFile value,
    Node<RemoteFile, DirectoryTree>? parent,
  }) {
    return DirectoryTree(value: value, parent: parent);
  }

  DirectoryTree({required super.value, super.children, super.parent});

  @override
  DirectoryTree? operator [](String key) {
    DirectoryTree? current = this;
    for (final part in p.s3.split(key)) {
      if (part.isEmpty) continue;
      if (!(current?.children.containsKey(part) ?? false)) {
        return null;
      }
      current = current?.children[part];
    }
    return current;
  }

  @override
  void operator []=(String key, RemoteFile value) {
    DirectoryTree current = this;
    String path = '';
    for (final part in p.s3.split(key)) {
      if (part.isEmpty) continue;
      path = p.asDir(p.s3.join(path, part));
      current = current.children.putIfAbsent(
        part,
        () => DirectoryTree(
          value: RemoteFile(key: path, etag: ''),
          parent: current,
        ),
      );
    }
    current.value = value;
  }
}

abstract class Main {
  static String _documentsDir = '';
  static String _cacheDir = '';
  static String _thumbCacheDir = '';
  static String _downloadCacheDir = '';
  static final DirectoryTree _directoryTree = DirectoryTree(value: root);
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

  static Iterable<RemoteFile> get remoteFiles =>
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

  static void remoteFilesSet(List<RemoteFile> files) {
    remoteFilesClear(notify: false);
    remoteFilesAddAll(files);
  }

  static void remoteFilesAddAll(List<RemoteFile> files) {
    for (final file in files) {
      remoteFilesAdd(file, notify: false);
    }
    onRemoteFilesChanged.notifyListeners();
  }

  static void remoteFilesAdd(RemoteFile file, {bool notify = true}) {
    _directoryTree[file.key] = file;
    if (notify) {
      onRemoteFilesChanged.notifyListeners();
    }
  }

  static void remoteFilesClear({bool notify = true}) {
    _directoryTree.clear();
    if (notify) {
      onRemoteFilesChanged.notifyListeners();
    }
  }

  static void remoteFilesRemoveByKeys(
    Iterable<String> keys, {
    bool notify = true,
  }) {
    for (String key in keys) {
      remoteFileRemoveByKey(key, notify: false);
    }
    if (notify) {
      onRemoteFilesChanged.notifyListeners();
    }
  }

  static void remoteFileRemoveByKey(String key, {bool notify = true}) {
    _directoryTree[key]?.clear();
    if (notify) {
      onRemoteFilesChanged.notifyListeners();
    }
  }

  static RemoteFile? remoteFileByKey(String key) {
    return _directoryTree[key]?.value;
  }

  static Iterable<RemoteFile> remoteFilesByDir(
    String dir, {
    bool recursive = true,
  }) {
    return _directoryTree[dir]
            ?.getDecendants(recursive: recursive)
            .map((node) => node.value)
            .whereType<RemoteFile>()
            .where(
              (f) => _ignoreKeyRegexps.any((regexp) => !regexp.hasMatch(f.key)),
            ) ??
        [];
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
    ]);
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

  static Future<void> onJobStatus(Job job, dynamic result) async {
    if (job is UploadJob &&
        job.status.value == JobStatus.completed &&
        result is RemoteFile) {
      remoteFilesAdd(result);
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
        remoteFileRemoveByKey(profile.name, notify: false);
        await ConfigManager.saveRemoteFiles(remoteFiles);
      }
    }
    for (final entry in entries) {
      if (_profiles.containsKey(entry.key)) {
        _profiles[entry.key]!.updateConfig(entry.value);
        continue;
      }
      _profiles[entry.key] = Profile(name: entry.key, cfg: entry.value);
    }
    loading.value = false;
  }

  static Future<void> listDirectories({bool background = false}) async {
    loading.value = true;
    if (!background && _directoryTree.isEmpty) {
      remoteFilesSet(await ConfigManager.loadRemoteFiles());
    }

    for (final profile in _profiles.values) {
      await profile.listDirectories(background: background);
    }
    loading.value = false;
  }

  static void downloadFile(String key, {String? localPath}) {
    final file = remoteFileByKey(key);
    if (file == null) {
      return;
    }
    DownloadJob(
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
      onStatus: onJobStatus,
      profile: profileFromKey(key),
    ).add();
  }

  static Future<void> uploadFile(String key, File file) async {
    if (!file.existsSync()) {
      return;
    }

    if (p.context.equals(pathFromKey(key), file.path)) {
      final deleteionLog = await profileFromKey(
        key,
      )!.deletionRegistrar.pullDeletions();
      if (deleteionLog.containsKey(key) &&
          file.lastModifiedSync().toUtc().isBefore(
            deleteionLog[key]!.toUtc(),
          )) {
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
    } else if (p.context.isAbsolute(pathFromKey(key))) {
      final newKey = () {
        String base = p.s3.basenameWithoutExtension(key);
        String ext = p.s3.extension(key);
        int count = 1;
        String candidateKey = key;
        while (remoteFileByKey(candidateKey) != null) {
          candidateKey = p.s3.join(p.s3.dirname(key), '$base${'($count)'}$ext');
          count++;
        }
        return candidateKey;
      }();
      if (!File(pathFromKey(newKey)).parent.existsSync()) {
        File(pathFromKey(newKey)).parent.createSync(recursive: true);
      }
      file.copySync(pathFromKey(newKey));
      UploadJob(
        localFile: File(pathFromKey(newKey)),
        remoteKey: key,
        bytes: file.lengthSync(),
        onStatus: onJobStatus,
        md5: await HashUtil(file).md5Hash(),
        profile: profileFromKey(key),
      ).add();
    } else {
      final newKey = () {
        String base = p.s3.basenameWithoutExtension(key);
        String ext = p.s3.extension(key);
        int count = 1;
        String candidateKey = key;
        while (remoteFileByKey(candidateKey) != null) {
          candidateKey = p.s3.join(p.s3.dirname(key), '$base${'($count)'}$ext');
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

  static Future<void> copyFile(
    String key,
    String newKey, {
    bool refresh = true,
  }) async {
    loading.value = true;

    RemoteFile? oldFile = remoteFileByKey(key);
    if (oldFile == null) {
      loading.value = false;
      return;
    }
    RemoteFile newFile = RemoteFile(
      key: newKey,
      size: oldFile.size,
      etag: oldFile.etag,
      lastModified: oldFile.lastModified,
    );

    final Profile? profile = profileFromKey(key);
    final Profile? newProfile = profileFromKey(newKey);

    if (profile != newProfile) {
      String downloadTo = pathFromKey(key);
      downloadTo = p.context.isAbsolute(downloadTo)
          ? downloadTo
          : cachePathFromKey(key);
      File file = File(downloadTo);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      // TODO: Download wait and Upload
      // downloadFile(oldFile, localPath: downloadTo);
      // uploadFile(newKey, File(downloadTo));
      return;
    }

    await profileFromKey(key)!.fileManager!.copyFile(key, newKey);

    final file = File(pathFromKey(key));
    final cacheFile = File(cachePathFromKey(key));

    if (file.existsSync() && p.isAbsolute(pathFromKey(newKey))) {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.copySync(pathFromKey(newKey));
    }

    if (cacheFile.existsSync() && p.isAbsolute(pathFromKey(newKey))) {
      if (!cacheFile.parent.existsSync()) {
        cacheFile.parent.createSync(recursive: true);
      }
      cacheFile.copySync(pathFromKey(newKey));
    }

    remoteFilesAdd(newFile);
    if (refresh) {
      loading.value = false;
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
    final keys = remoteFilesByDir(
      dir,
    ).map((f) => f.key).where((key) => !p.isDir(key));
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

    if (refresh) {
      loading.value = false;
    }
  }

  static Future<void> deleteFiles(
    Iterable<String> keys, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    final Map<Profile, List<String>> profileKeys = {};
    for (final key in keys) {
      final profile = profileFromKey(key);
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
    }

    if (refresh) {
      loading.value = false;
    }
  }

  static Future<void> deleteS3(
    Iterable<String> keys, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    List<String> files = [];

    for (final key in keys) {
      if (!p.isDir(key)) {
        files.add(key);
      } else {
        files.addAll(
          remoteFilesByDir(key).map((f) => f.key).where((key) => !p.isDir(key)),
        );
      }
    }

    final Map<Profile, List<String>> profileFiles = {};
    for (final file in files) {
      final profile = profileFromKey(file);
      if (profile != null && remoteFileByKey(file) != null) {
        profileFiles.putIfAbsent(profile, () => []).add(file);
      }
    }

    int progressCount = 0;
    for (final entry in profileFiles.entries) {
      final profile = entry.key;
      final filesForProfile = entry.value;

      await profile.deletionRegistrar.pullDeletions();
      profile.deletionRegistrar.logDeletions(filesForProfile);
      await profile.deletionRegistrar.pushDeletions();

      for (final file in filesForProfile.where((file) => !p.isDir(file))) {
        progressCount += 1;
        (preprogress ?? progress).value =
            progressCount / profileFiles.values.expand((e) => e).length;
        await profile.fileManager?.deleteFile(file);
      }

      remoteFilesRemoveByKeys(
        filesForProfile.where((key) => !p.isDir(key)),
        notify: true,
      );

      final dirsForProfile = remoteFilesByDir(profile.name)
          .map((f) => f.key)
          .where((key) => filesForProfile.contains(key) && p.isDir(key))
          .toList();
      dirsForProfile.sort((a, b) => b.length.compareTo(a.length));

      for (final dir in dirsForProfile) {
        progressCount += 1;
        (preprogress ?? progress).value =
            progressCount / profileFiles.values.expand((e) => e).length;
        await profile.fileManager?.deleteFile(dir);
      }

      remoteFilesRemoveByKeys(dirsForProfile, notify: true);

      await profile.refreshRemote(dir: profile.name);
    }

    if (refresh) {
      loading.value = false;
    }
  }

  // uses deleteS3
  static Future<void> deleteDirectories(
    Iterable<String> dirs, {
    bool refresh = true,
    ValueNotifier<double>? preprogress,
  }) async {
    loading.value = true;

    await deleteS3(dirs, refresh: false, preprogress: preprogress ?? progress);

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

    if (refresh) {
      loading.value = false;
    }
  }

  // uses copyFile and deleteFiles
  static Future<void> moveFiles(
    Iterable<String> keys,
    Iterable<String> newKeys, {
    bool refresh = true,
  }) async {
    loading.value = true;
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
    if (refresh) {
      loading.value = false;
    }
  }

  // uses copyDirectory and deleteDirectories
  static Future<void> moveDirectories(
    Iterable<String> dirs,
    Iterable<String> newDirs, {
    bool refresh = true,
  }) async {
    loading.value = true;
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
    if (refresh) {
      loading.value = false;
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

abstract class Job {
  final File localFile;
  final String remoteKey;
  final Digest md5;
  final int bytes;
  final Profile? profile;

  S3TransferTask? task;

  static int maxrun = 5;
  static bool scheduled = false;

  static final List<Job> jobs = <Job>[];
  static final List<Job> completedJobs = <Job>[];
  static final ManualNotifier onJobsChanged = ManualNotifier();
  static Iterable<Job> get runningJobs =>
      jobs.where((job) => job.status.value == JobStatus.running);
  static Iterable<Job> get initializedJobs =>
      jobs.where((job) => job.status.value == JobStatus.initialized);
  static Iterable<Job> get unInitializedJobs => jobs.where(
    (job) =>
        job.status.value == JobStatus.failed ||
        job.status.value == JobStatus.stopped,
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
    if (jobs.any(
      (job) =>
          job.localFile.path == localFile.path &&
          job.remoteKey == remoteKey &&
          job.status.value != JobStatus.completed,
    )) {
      return;
    }
    jobs.add(this);
    status.addListener(() {
      if (status.value == JobStatus.completed) {
        completedJobs.add(this);
        jobs.remove(this);
      }
    });
    onJobsChanged.notifyListeners();
    startall();
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
        statusMsg.value = "Starting upload...";
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
    return status.value != JobStatus.running;
  }

  void remove() {
    if (removable()) {
      if (jobs.remove(this)) {
        onJobsChanged.notifyListeners();
      }
      dispose();
    }
  }

  bool dismissible() {
    return status.value == JobStatus.completed;
  }

  void dismiss() {
    if (dismissible()) {
      if (completedJobs.remove(this)) {
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

  static void continueAll() {
    for (var job in unInitializedJobs) {
      job.status.value = JobStatus.initialized;
    }
    startall();
  }

  static void startall() {
    if (scheduled) {
      return;
    }

    try {
      scheduled = true;
      while (runningJobs.length < maxrun) {
        Job? job = jobs.firstWhereOrNull(
          (job) => job.status.value == JobStatus.initialized,
        );
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

  static void stopall() {
    for (var job in jobs) {
      job.stop();
    }
    onProgressUpdate.notifyListeners();
  }

  static void clearCompleted() {
    for (final job in completedJobs.toList()) {
      job.dismiss();
    }
  }

  static void disposeAll() {
    for (final job in jobs.toList()) {
      jobs.remove(job);
      job.dispose();
    }
    for (final job in completedJobs.toList()) {
      completedJobs.remove(job);
      job.dispose();
    }
    onJobsChanged.notifyListeners();
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
        Main.remoteFilesByDir(remoteDir)
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
      final result = await _syncAnalyze(
        localDir.path,
        remoteFiles,
        recursive: recursive,
      );

      for (String path in [...result.newFile, ...result.modifiedLocally]) {
        final key = Main.keyFromPath(path) ?? '';
        if (Job.jobs.any(
          (job) => job.localFile.path == path && job.remoteKey == key,
        )) {
          continue;
        }
        BackupMode mode = Main.backupModeFromKey(Main.keyFromPath(path) ?? '');
        if (mode == BackupMode.sync || mode == BackupMode.upload) {
          Main.uploadFile(key, File(path));
        }
      }

      for (String key in result.modifiedRemotely) {
        if (Job.jobs.any(
          (job) =>
              job.localFile.path == Main.pathFromKey(key) &&
              job.remoteKey == key,
        )) {
          continue;
        }
        BackupMode mode = Main.backupModeFromKey(key);
        if (mode == BackupMode.sync || mode == BackupMode.upload) {
          Main.downloadFile(key);
        }
      }

      for (String key in result.remoteOnly) {
        if (Job.jobs.any(
          (job) =>
              job.localFile.path == Main.pathFromKey(key) &&
              job.remoteKey == key,
        )) {
          continue;
        }
        if (Main.backupModeFromKey(key) == BackupMode.sync) {
          Main.downloadFile(key);
        }
      }

      if (kDebugMode) {
        debugPrint("Scan completed for ${localDir.path}");
      }

      scanning = false;

      if (_rescanQueued) {
        _rescanQueued = false;
        unawaited(scan());
      }
    } finally {
      scanning = false;
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
