import 'dart:io';
import 'package:files3/info_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3e_card_list/m3e_card_list.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_selector/file_selector.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/settings.dart';

abstract class ContextActionHandler {
  ContextActionHandler();

  void Function()? download();
  String Function()? saveAs(String? path);
  Future<String> Function()? delete(bool? yes);
  Future<String> Function()? deleteCache(bool? yes);
}

class FileContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final String? Function(RemoteFile, int?) getLink;
  final Function(RemoteFile)? downloadFile;
  final Function(RemoteFile, String)? saveFile;
  final Future<void> Function(List<String>, List<String>)? moveFiles;
  final Function(String)? deleteLocalFile;
  final Function(String)? deleteCacheFile;
  final Future<void> Function(List<String>)? deleteFiles;

  bool? _rootExistsCache;
  bool? _downloadedCache;
  bool? _cacheExistsCache;
  bool? _activeCache;
  bool? _removableCache;

  FileContextActionHandler({
    required this.file,
    required this.getLink,
    required this.downloadFile,
    required this.saveFile,
    required this.moveFiles,
    required this.deleteLocalFile,
    required this.deleteCacheFile,
    required this.deleteFiles,
  });

  void invalidateCache() {
    _rootExistsCache = null;
    _downloadedCache = null;
    _cacheExistsCache = null;
    _activeCache = null;
    _removableCache = null;
  }

  bool get rootExistsCached =>
      _rootExistsCache ??= p.isAbsolute(Main.pathFromKey(file.key) ?? file.key);

  bool rootExists() {
    return rootExistsCached;
  }

  bool get downloadedCached => _downloadedCache ??=
      !p.isDir(file.key) &&
      File(Main.pathFromKey(file.key) ?? file.key).existsSync();

  bool downloaded() {
    return downloadedCached;
  }

  bool get cacheExistsCached => _cacheExistsCache ??=
      !p.isDir(file.key) && File(Main.cachePathFromKey(file.key)).existsSync();

  bool cacheExists() {
    return cacheExistsCached;
  }

  bool get activeCached => _activeCache ??= Job.activeJobs.any(
    (job) => job.localFile.path == Main.pathFromKey(file.key),
  );

  bool active() {
    return activeCached;
  }

  bool get removableCached => _removableCache ??=
      downloadedCached && Main.backupModeFromKey(file.key) == BackupMode.upload;

  bool removable() {
    return removableCached;
  }

  dynamic Function()? open() {
    final link = getLink(file, null);
    return File(Main.pathFromKey(file.key) ?? file.key).existsSync()
        ? () {
            OpenFile.open(Main.pathFromKey(file.key) ?? file.key);
          }
        : cacheExists()
        ? () {
            OpenFile.open(Main.cachePathFromKey(file.key));
          }
        : link == null
        ? null
        : () {
            launchUrl(Uri.parse(link));
          };
  }

  @override
  void Function()? download() {
    return !rootExists() || downloaded() || active() || downloadFile == null
        ? null
        : () {
            try {
              downloadFile!(file);
            } finally {
              invalidateCache();
            }
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path != null && saveFile != null
        ? () {
            try {
              saveFile!(file, path);
            } finally {
              invalidateCache();
            }
            return 'Saving to $path';
          }
        : null;
  }

  XFile Function()? getXFile() {
    return File(Main.pathFromKey(file.key) ?? file.key).existsSync()
        ? () {
            return XFile(Main.pathFromKey(file.key) ?? file.key);
          }
        : cacheExists()
        ? () {
            return XFile(Main.cachePathFromKey(file.key));
          }
        : null;
  }

  String? Function() getLinkToCopy(int? seconds) {
    return () {
      return getLink(file, seconds);
    };
  }

  Future<String> Function()? rename(String newName) {
    return moveFiles == null
        ? null
        : () async {
            try {
              final newKey = p.join(
                p.s3(p.dirname(file.key)),
                newName.replaceAll('/', '_').replaceAll('\\', '_'),
              );
              await moveFiles!([file.key], [newKey]);
              return 'Renamed ${p.basename(file.key)} to $newName';
            } finally {
              invalidateCache();
            }
          };
  }

  Future<String> Function()? deleteUploaded(bool? yes) {
    return (yes ?? false) && deleteLocalFile != null && removable()
        ? () async {
            try {
              await deleteLocalFile!(file.key);
              return 'Deleted local copy of ${p.basename(file.key)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  Future<String> Function()? deleteLocal(bool? yes) {
    return (yes ?? false) &&
            deleteLocalFile != null &&
            !removable() &&
            downloaded()
        ? () async {
            try {
              await deleteLocalFile!(file.key);
              return 'Deleted local copy of ${p.basename(file.key)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return (yes ?? false) && deleteFiles != null
        ? () async {
            try {
              await deleteFiles!([file.key]);
              return 'Deleted ${p.basename(file.key)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache(bool? yes) {
    return (yes ?? false) && deleteCacheFile != null && cacheExists()
        ? () async {
            try {
              await deleteCacheFile!(file.key);
              return 'Deleted cache of ${p.basename(file.key)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }
}

class FilesContextActionHandler extends ContextActionHandler {
  final List<RemoteFile> files;
  final String? Function(RemoteFile, int?) getLink;
  final Function(RemoteFile)? downloadFile;
  final Function(RemoteFile, String)? saveFile;
  final Future<void> Function(List<String>, List<String>)? moveFiles;
  final Function(String)? deleteLocalFile;
  final Function(String)? deleteCacheFile;
  final Future<void> Function(List<String>)? deleteFiles;
  List<bool>? _rootExistsCache;
  List<RemoteFile>? _downloadedFilesCache;
  List<RemoteFile>? _cachedFilesCache;
  List<RemoteFile>? _activeFilesCache;
  List<RemoteFile>? _removableFilesCache;

  FilesContextActionHandler({
    required this.files,
    required this.getLink,
    required this.downloadFile,
    required this.saveFile,
    required this.moveFiles,
    required this.deleteLocalFile,
    required this.deleteCacheFile,
    required this.deleteFiles,
  });

  void invalidateCache() {
    _rootExistsCache = null;
    _downloadedFilesCache = null;
    _cachedFilesCache = null;
    _activeFilesCache = null;
    _removableFilesCache = null;
  }

  List<bool> get rootExistsCached => _rootExistsCache ??= files
      .map((file) => p.isAbsolute(Main.pathFromKey(file.key) ?? file.key))
      .toList();

  List<bool> rootExists() {
    return rootExistsCached;
  }

  List<RemoteFile> get downloadedFilesCached =>
      _downloadedFilesCache ??= List.unmodifiable(
        files
            .where(
              (f) =>
                  !p.isDir(f.key) &&
                  File(Main.pathFromKey(f.key) ?? f.key).existsSync(),
            )
            .toList(),
      );

  List<RemoteFile> downloadedFiles() {
    return downloadedFilesCached;
  }

  List<RemoteFile> get cachedFilesCached =>
      _cachedFilesCache ??= List.unmodifiable(
        files
            .where(
              (f) =>
                  !p.isDir(f.key) &&
                  File(Main.cachePathFromKey(f.key)).existsSync(),
            )
            .toList(),
      );

  List<RemoteFile> cachedFiles() {
    return cachedFilesCached;
  }

  List<RemoteFile> get activeFilesCached =>
      _activeFilesCache ??= List.unmodifiable(
        files
            .where(
              (f) => Job.activeJobs.any(
                (job) =>
                    !p.isDir(f.key) &&
                    job.localFile.path == Main.pathFromKey(f.key),
              ),
            )
            .toList(),
      );

  List<RemoteFile> activeFiles() {
    return activeFilesCached;
  }

  List<RemoteFile> get removableFilesCached =>
      _removableFilesCache ??= List.unmodifiable(
        files
            .where(
              (f) =>
                  !p.isDir(f.key) &&
                  File(Main.pathFromKey(f.key) ?? f.key).existsSync() &&
                  Main.backupModeFromKey(f.key) == BackupMode.upload,
            )
            .toList(),
      );

  List<RemoteFile> removableFiles() {
    return removableFilesCached;
  }

  @override
  void Function()? download() {
    return downloadedFiles().length == files.length ||
            downloadedFiles()
                    .map((f) => f.key)
                    .toSet()
                    .union(activeFiles().map((f) => f.key).toSet())
                    .length ==
                files.length ||
            downloadFile == null
        ? null
        : () {
            try {
              for (RemoteFile file in files.where(
                (file) =>
                    !File(Main.pathFromKey(file.key) ?? file.key).existsSync(),
              )) {
                downloadFile!(file);
              }
            } finally {
              invalidateCache();
            }
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path != null && saveFile != null
        ? () {
            try {
              for (final file in files) {
                saveFile!(file, p.join(path, p.basename(file.key)));
              }
            } finally {
              invalidateCache();
            }
            return 'Saving ${files.length} files to $path';
          }
        : null;
  }

  List<XFile> Function()? getXFiles() {
    return downloadedFiles().isNotEmpty
        ? () {
            return files
                .where(
                  (file) =>
                      File(
                        (Main.pathFromKey(file.key) ?? file.key),
                      ).existsSync() ||
                      File(Main.cachePathFromKey(file.key)).existsSync(),
                )
                .map((file) {
                  if (File(
                    Main.pathFromKey(file.key) ?? file.key,
                  ).existsSync()) {
                    return XFile(Main.pathFromKey(file.key) ?? file.key);
                  } else if (File(
                    Main.cachePathFromKey(file.key),
                  ).existsSync()) {
                    return XFile(Main.cachePathFromKey(file.key));
                  } else {
                    throw Exception('File ${file.key} does not exist locally');
                  }
                })
                .toList();
          }
        : null;
  }

  String Function() getLinksToCopy(int? seconds) {
    return () {
      final buffer = StringBuffer();
      for (final file in files) {
        buffer.writeln(getLink(file, seconds));
        buffer.writeln();
      }
      return buffer.toString();
    };
  }

  Future<String> Function()? deleteUploaded(
    List<RemoteFile> removableFiles,
    bool? yes,
  ) {
    return (yes ?? false) &&
            deleteLocalFile != null &&
            removableFiles.isNotEmpty
        ? () async {
            try {
              for (final file in removableFiles) {
                await deleteLocalFile!(file.key);
              }
              return 'Deleted local copies of ${removableFiles.length} uploaded files';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  Future<String> Function()? deleteLocal(
    bool? yes,
    List<RemoteFile> downloadedFiles,
  ) {
    return (yes ?? false) &&
            deleteLocalFile != null &&
            downloadedFiles.isNotEmpty
        ? () async {
            try {
              for (final file in downloadedFiles) {
                await deleteLocalFile!(file.key);
              }
              return 'Deleted local copies of ${downloadedFiles.length} files';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return (yes ?? false) && deleteFiles != null
        ? () async {
            try {
              await deleteFiles!(files.map((f) => f.key).toList());
              return 'Deleted ${files.length} files';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache(bool? yes) {
    final cacheFilesList = cachedFiles();
    return (yes ?? false) &&
            deleteCacheFile != null &&
            cacheFilesList.isNotEmpty
        ? () async {
            try {
              for (final file in cacheFilesList) {
                await deleteCacheFile!(file.key);
              }
              return 'Deleted cache of ${cacheFilesList.length} files';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }
}

class DirectoryContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final Function(RemoteFile)? downloadDirectory;
  final Function(RemoteFile, String)? saveDirectory;
  final Future<void> Function(List<String>, List<String>)? moveDirectories;
  final Function(String)? deleteLocalDirectory;
  final Function(String)? deleteCacheDirectory;
  final Future<void> Function(List<String>)? deleteDirectories;

  List<RemoteFile>? _filesCache;
  bool? _rootExistsCache;
  bool? _localExistsCache;
  List<RemoteFile>? _downloadedFilesCache;
  bool? _cacheExistCache;
  List<RemoteFile>? _activeFilesCache;
  List<RemoteFile>? _removableFilesCache;

  DirectoryContextActionHandler({
    required this.file,
    required this.downloadDirectory,
    required this.saveDirectory,
    required this.moveDirectories,
    required this.deleteLocalDirectory,
    required this.deleteCacheDirectory,
    required this.deleteDirectories,
  });

  void invalidateCache() {
    _filesCache = null;
    _rootExistsCache = null;
    _localExistsCache = null;
    _downloadedFilesCache = null;
    _cacheExistCache = null;
    _activeFilesCache = null;
    _removableFilesCache = null;
  }

  List<RemoteFile> get filesCached => _filesCache ??= List.unmodifiable(
    Main.remoteFiles
        .where((f) => p.isWithin(file.key, f.key) && !p.isDir(f.key))
        .toList(),
  );

  List<RemoteFile> get files => _filesCache ??= List.unmodifiable(
    Main.remoteFiles
        .where((f) => p.isWithin(file.key, f.key) && !p.isDir(f.key))
        .toList(),
  );

  bool get rootExistsCached =>
      _rootExistsCache ??= p.isAbsolute(Main.pathFromKey(file.key) ?? file.key);

  bool rootExists() {
    return rootExistsCached;
  }

  bool get localExistsCached => _localExistsCache ??= Directory(
    Main.pathFromKey(file.key) ?? file.key,
  ).existsSync();

  bool localExists() {
    return localExistsCached;
  }

  List<RemoteFile> get downloadedFilesCached =>
      _downloadedFilesCache ??= List.unmodifiable(
        files
            .where((f) => File(Main.pathFromKey(f.key) ?? f.key).existsSync())
            .toList(),
      );

  List<RemoteFile> downloadedFiles() {
    return downloadedFilesCached;
  }

  bool get cacheExistCached => _cacheExistCache ??= Directory(
    Main.cachePathFromKey(file.key),
  ).existsSync();

  bool cacheExist() {
    return cacheExistCached;
  }

  List<RemoteFile> get activeFilesCached =>
      _activeFilesCache ??= List.unmodifiable(
        files
            .where(
              (f) => Job.activeJobs.any(
                (job) =>
                    !p.isDir(f.key) &&
                    job.localFile.path == Main.pathFromKey(f.key),
              ),
            )
            .toList(),
      );

  List<RemoteFile> activeFiles() {
    return activeFilesCached;
  }

  List<RemoteFile> get removableFilesCached =>
      _removableFilesCache ??= List.unmodifiable(
        Main.remoteFiles
            .where(
              (f) =>
                  p.isWithin(file.key, f.key) &&
                  !p.isDir(f.key) &&
                  File(Main.pathFromKey(f.key) ?? f.key).existsSync() &&
                  Main.backupModeFromKey(f.key) == BackupMode.upload,
            )
            .toList(),
      );

  List<RemoteFile> removableFiles() {
    return removableFilesCached;
  }

  void Function()? open() {
    return Directory(Main.pathFromKey(file.key) ?? file.key).existsSync()
        ? () {
            launchUrl(Uri.file(Main.pathFromKey(file.key) ?? file.key));
          }
        : null;
  }

  @override
  void Function()? download() {
    return !rootExists() ||
            downloadedFiles().length == files.length ||
            downloadedFiles()
                    .map((f) => f.key)
                    .toSet()
                    .union(activeFiles().map((f) => f.key).toSet())
                    .length ==
                files.length ||
            downloadDirectory == null
        ? null
        : () {
            try {
              downloadDirectory!(file);
            } finally {
              invalidateCache();
            }
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path == null || saveDirectory == null
        ? null
        : () {
            try {
              saveDirectory!(file, path);
            } finally {
              invalidateCache();
            }
            return 'Saving ${p.basename(file.key)} to $path';
          };
  }

  Future<String> Function()? rename(String newName) {
    return moveDirectories == null || p.s3(p.dirname(file.key)).isEmpty
        ? null
        : () async {
            try {
              final key = file.key;
              final newKey = p.s3(
                p.asDir(
                  p.join(
                    p.s3(p.dirname(key)),
                    newName.replaceAll('/', '_').replaceAll('\\', '_'),
                  ),
                ),
              );
              await moveDirectories!([key], [newKey]);
              return 'Renamed ${p.basename(file.key)} to $newName';
            } finally {
              invalidateCache();
            }
          };
  }

  Future<String> Function()? deleteUploaded(
    List<RemoteFile> removableFiles,
    bool? yes,
  ) {
    return (yes ?? false) &&
            deleteLocalDirectory != null &&
            removableFiles.isNotEmpty
        ? () async {
            try {
              for (final file in removableFiles) {
                deleteLocalDirectory!(file.key);
              }
              return 'Deleted local copies of ${removableFiles.length} uploaded files in ${p.basename(file.key)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  Future<String> Function()? deleteLocal(bool? yes) {
    return (yes ?? false) && deleteLocalDirectory != null && localExists()
        ? () async {
            try {
              final key = file.key;
              deleteLocalDirectory!(key);
              return 'Deleted local copy of ${p.basename(key)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return (yes ?? false) && deleteDirectories != null
        ? () async {
            try {
              final key = file.key;
              deleteDirectories!([key]);
              return 'Deleted ${p.basename(key)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache(bool? yes) {
    return (yes ?? false) && deleteCacheDirectory != null && cacheExist()
        ? () async {
            try {
              final key = file.key;
              deleteCacheDirectory!(key);
              return 'Deleted cache of ${p.basename(key)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }
}

class DirectoriesContextActionHandler extends ContextActionHandler {
  final List<RemoteFile> directories;
  final Function(RemoteFile)? downloadDirectory;
  final Function(RemoteFile, String)? saveDirectory;
  final Future<void> Function(List<String>, List<String>)? moveDirectories;
  final Function(String)? deleteLocalDirectory;
  final Function(String)? deleteCacheDirectory;
  final Future<void> Function(List<String>)? deleteDirectories;

  List<RemoteFile>? _filesCache;
  List<bool>? _rootExistsCache;
  List<RemoteFile>? _localDirectoriesCache;
  List<RemoteFile>? _downloadedFilesCache;
  List<RemoteFile>? _cachedDirectoriesCache;
  List<RemoteFile>? _activeFilesCache;
  List<RemoteFile>? _removableFilesCache;

  DirectoriesContextActionHandler({
    required this.directories,
    required this.downloadDirectory,
    required this.saveDirectory,
    required this.moveDirectories,
    required this.deleteLocalDirectory,
    required this.deleteCacheDirectory,
    required this.deleteDirectories,
  });

  void invalidateCache() {
    _filesCache = null;
    _rootExistsCache = null;
    _localDirectoriesCache = null;
    _downloadedFilesCache = null;
    _cachedDirectoriesCache = null;
    _activeFilesCache = null;
    _removableFilesCache = null;
  }

  List<RemoteFile> get filesCached => _filesCache ??= List.unmodifiable(
    Main.remoteFiles
        .where(
          (f) =>
              directories.any((dir) => p.isWithin(dir.key, f.key)) &&
              !p.isDir(f.key),
        )
        .toList(),
  );

  List<RemoteFile> get files => _filesCache ??= List.unmodifiable(
    Main.remoteFiles
        .where(
          (f) =>
              directories.any((dir) => p.isWithin(dir.key, f.key)) &&
              !p.isDir(f.key),
        )
        .toList(),
  );

  List<bool> get rootExistsCached => _rootExistsCache ??= List.unmodifiable(
    directories
        .map((dir) => p.isAbsolute(Main.pathFromKey(dir.key) ?? dir.key))
        .toList(),
  );

  List<bool> rootExists() {
    return rootExistsCached;
  }

  List<RemoteFile> get localDirectoriesCached =>
      _localDirectoriesCache ??= List.unmodifiable(
        directories
            .where(
              (dir) =>
                  Directory(Main.pathFromKey(dir.key) ?? dir.key).existsSync(),
            )
            .toList(),
      );

  List<RemoteFile> localDirectories() {
    return localDirectoriesCached;
  }

  List<RemoteFile> get downloadedFilesCached =>
      _downloadedFilesCache ??= List.unmodifiable(
        files
            .where((f) => File(Main.pathFromKey(f.key) ?? f.key).existsSync())
            .toList(),
      );

  List<RemoteFile> downloadedFiles() {
    return downloadedFilesCached;
  }

  List<RemoteFile> get cachedDirectoriesCached =>
      _cachedDirectoriesCache ??= List.unmodifiable(
        directories
            .where(
              (dir) => Directory(Main.cachePathFromKey(dir.key)).existsSync(),
            )
            .toList(),
      );

  List<RemoteFile> cachedDirectories() {
    return cachedDirectoriesCached;
  }

  List<RemoteFile> get activeFilesCached =>
      _activeFilesCache ??= List.unmodifiable(
        files
            .where(
              (f) => Job.activeJobs.any(
                (job) =>
                    !p.isDir(f.key) &&
                    job.localFile.path == Main.pathFromKey(f.key),
              ),
            )
            .toList(),
      );

  List<RemoteFile> activeFiles() {
    return activeFilesCached;
  }

  List<RemoteFile> get removableFilesCached =>
      _removableFilesCache ??= List.unmodifiable(
        Main.remoteFiles
            .where(
              (f) =>
                  directories.any((dir) => p.isWithin(dir.key, f.key)) &&
                  !p.isDir(f.key) &&
                  File(Main.pathFromKey(f.key) ?? f.key).existsSync() &&
                  Main.backupModeFromKey(f.key) == BackupMode.upload,
            )
            .toList(),
      );

  List<RemoteFile> removableFiles() {
    return removableFilesCached;
  }

  @override
  void Function()? download() {
    return rootExists().every((exists) => !exists) ||
            downloadedFiles().length ==
                Main.remoteFiles
                    .where(
                      (f) =>
                          directories.any(
                            (dir) => p.isWithin(dir.key, f.key),
                          ) &&
                          !p.isDir(f.key),
                    )
                    .length ||
            downloadedFiles()
                    .map((f) => f.key)
                    .toSet()
                    .union(activeFiles().map((f) => f.key).toSet())
                    .length ==
                Main.remoteFiles
                    .where(
                      (f) =>
                          directories.any(
                            (dir) => p.isWithin(dir.key, f.key),
                          ) &&
                          !p.isDir(f.key),
                    )
                    .length ||
            downloadDirectory == null
        ? null
        : () {
            try {
              for (final dir in directories.where(
                (dir) => Directory(
                  Main.pathFromKey(dir.key) ?? dir.key,
                ).existsSync(),
              )) {
                downloadDirectory!(dir);
              }
            } finally {
              invalidateCache();
            }
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path != null && saveDirectory != null
        ? () {
            try {
              for (final dir in directories) {
                saveDirectory!(dir, p.join(path, p.basename(dir.key)));
              }
            } finally {
              invalidateCache();
            }
            return 'Saving ${directories.length} folders to $path';
          }
        : null;
  }

  Future<String> Function()? deleteUploaded(
    List<RemoteFile> removableFiles,
    bool? yes,
  ) {
    return (yes ?? false) && deleteLocalDirectory != null
        ? () async {
            try {
              for (final dir in directories) {
                final key = dir.key;
                for (final file in removableFiles) {
                  if (p.isWithin(key, file.key)) {
                    deleteLocalDirectory!(file.key);
                  }
                }
              }
              return 'Deleted local copies of ${removableFiles.length} uploaded files in ${directories.length} directories';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  Future<String> Function()? deleteLocal(
    bool? yes,
    List<RemoteFile> localDirs,
  ) {
    return (yes ?? false) &&
            deleteLocalDirectory != null &&
            localDirs.isNotEmpty
        ? () async {
            try {
              for (final dir in localDirs) {
                final key = dir.key;
                deleteLocalDirectory!(key);
              }
              return 'Deleted local copies of ${localDirs.length} folders';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return (yes ?? false) && deleteDirectories != null
        ? () async {
            try {
              final keys = directories.map((dir) => dir.key).toList();
              await deleteDirectories!(keys);
              return 'Deleted ${directories.length} folders';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache(bool? yes) {
    final cacheDirs = cachedDirectories();
    return (yes ?? false) &&
            deleteCacheDirectory != null &&
            cacheDirs.isNotEmpty
        ? () async {
            try {
              for (final dir in cacheDirs) {
                final key = dir.key;
                deleteCacheDirectory!(key);
              }
              return 'Deleted cache of ${cacheDirs.length} folders';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }
}

class FileContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function()? action;
  final dynamic Function()? secondaryAction;
  final IconData? secondaryIcon;
  final bool popOnInvoked;

  FileContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
    this.secondaryAction,
    this.secondaryIcon,
    this.popOnInvoked = false,
  });

  static FileContextOption open(FileContextActionHandler handler) => (() {
    final openAction = handler.open();
    final localExists = handler.downloadedCached;
    return FileContextOption(
      title: localExists
          ? 'Open with...'
          : openAction == null
          ? 'Link Unavailable'
          : 'Open Link',
      subtitle: Main.pathFromKey(handler.file.key),
      icon: Icons.open_in_new_rounded,
      action: openAction,
      popOnInvoked: false,
    );
  })();

  static FileContextOption download(FileContextActionHandler handler) => (() {
    final downloadAction = handler.download();
    final rootExists = handler.rootExistsCached;
    final active = handler.activeCached;
    final localPath = Main.pathFromKey(handler.file.key);
    return FileContextOption(
      title: downloadAction == null
          ? rootExists
                ? active
                      ? 'Active Job'
                      : 'Downloaded'
                : 'Cannot Download'
          : 'Download',
      subtitle: downloadAction == null
          ? rootExists
                ? active
                      ? null
                      : localPath
                : 'Set backup folder to enable downloads'
          : localPath,
      icon: downloadAction == null && !active
          ? rootExists
                ? Icons.file_download_done_rounded
                : Icons.file_download_off_rounded
          : Icons.file_download_rounded,
      action: downloadAction,
      popOnInvoked: false,
    );
  })();

  static FileContextOption saveAs(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Save As...',
    icon: Icons.save_as_rounded,
    action: handler.saveFile == null
        ? null
        : () async {
            FileSaveLocation? saveLocation;
            try {
              saveLocation = await getSaveLocation(
                suggestedName: p.basename(handler.file.key),
                canCreateDirectories: true,
              );
            } catch (e) {
              saveLocation = await saveAsDialog(
                context,
                suggestedName: p.basename(handler.file.key),
              );
            }
            final String Function()? handle = handler.saveAs(
              saveLocation?.path,
            );
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(handle())));
            }
          },
    popOnInvoked: false,
  );

  static FileContextOption share(FileContextActionHandler handler) => (() {
    final getXFile = handler.getXFile();
    return FileContextOption(
      title: getXFile == null ? 'Cannot Share' : 'Share',
      icon: Icons.share_rounded,
      subtitle: getXFile == null ? 'Only downloaded files can be shared' : null,
      action: getXFile != null
          ? () {
              SharePlus.instance.share(ShareParams(files: <XFile>[getXFile()]));
            }
          : null,
      popOnInvoked: false,
    );
  })();

  static FileContextOption copyLink(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Copy Link',
    icon: Icons.link_rounded,
    action: () async {
      try {
        Clipboard.setData(
          ClipboardData(
            text: handler.getLinkToCopy(await expiryDialog(context))()!,
          ),
        );
        showSnackBar(
          const SnackBar(content: Text('File link copied to clipboard')),
        );
      } catch (e) {
        showSnackBar(SnackBar(content: Text('Failed to generate link: $e')));
      }
    },
    secondaryIcon: Icons.share_rounded,
    secondaryAction: () async {
      try {
        final link = handler.getLinkToCopy(await expiryDialog(context))()!;
        Clipboard.setData(ClipboardData(text: link));
        showSnackBar(
          const SnackBar(content: Text('File link copied to clipboard')),
        );
        SharePlus.instance.share(ShareParams(uri: Uri.tryParse(link)));
      } catch (e) {
        showSnackBar(SnackBar(content: Text('Failed to generate link: $e')));
      }
    },
    popOnInvoked: false,
  );

  static FileContextOption cut(
    FileContextActionHandler handler,
    Function(RemoteFile)? cutKey,
  ) => FileContextOption(
    title: 'Move To...',
    icon: Icons.cut_rounded,
    action: cutKey == null
        ? null
        : () {
            cutKey(handler.file);
          },
    popOnInvoked: true,
  );

  static FileContextOption copy(
    FileContextActionHandler handler,
    Function(RemoteFile)? copyKey,
  ) => FileContextOption(
    title: 'Copy To...',
    icon: Icons.file_copy_rounded,
    action: copyKey == null
        ? null
        : () {
            copyKey(handler.file);
          },
    popOnInvoked: true,
  );

  static FileContextOption rename(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Rename',
    icon: Icons.edit_rounded,
    action: handler.moveFiles == null
        ? null
        : () async {
            final newName = await renameDialog(
              context,
              p.basename(handler.file.key),
            );
            if (newName != null &&
                newName.isNotEmpty &&
                newName != p.basename(handler.file.key)) {
              showSnackBar(
                SnackBar(content: Text(await handler.rename(newName)!())),
              );
            }
          },
    popOnInvoked: true,
  );

  static FileContextOption deleteUploaded(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Remove from Device',
    subtitle: 'This file has been uploaded',
    icon: Icons.phonelink_off_rounded,
    action: handler.deleteUploaded(true) == null
        ? null
        : () async {
            final handle = handler.deleteUploaded(
              await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Remove from Device'),
                  content: Text(
                    'Are you sure you want to delete the local copy of ${p.basename(handler.file.key)}? This file has been uploaded and can be downloaded again later.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ),
            );
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(await handle())));
            }
          },
    popOnInvoked: false,
  );

  static FileContextOption deleteLocal(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Delete Local Copy',
    subtitle: 'Delete from device',
    icon: Icons.delete_rounded,
    action: handler.deleteLocal(true) == null
        ? null
        : () async {
            final handle = handler.deleteLocal(
              await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Local Copy'),
                  content: Text(
                    'Are you sure you want to delete the local copy of ${p.basename(handler.file.key)}? This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ),
            );
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(await handle())));
            }
          },
    popOnInvoked: false,
  );

  static FileContextOption delete(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Permanently Delete',
    icon: Icons.delete_forever_rounded,
    subtitle: 'Delete from device as well as S3',
    action: handler.delete(true) == null
        ? null
        : () async {
            final handle = handler.delete(
              await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Permanently Delete File'),
                  content: Text(
                    'Are you sure you want to delete ${p.basename(handler.file.key)} from your device and S3? This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ),
            );
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(await handle())));
            }
          },
    popOnInvoked: true,
  );

  static FileContextOption deleteCache(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Delete Cache',
    subtitle: 'Delete cached copy of file',
    icon: Icons.delete_outline_rounded,
    action: handler.deleteCache(true) == null
        ? null
        : () async {
            final handle = handler.deleteCache(
              await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Cache'),
                  content: Text(
                    'Are you sure you want to delete the cached copy of ${p.basename(handler.file.key)}? This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ),
            );
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(await handle())));
            }
          },
    popOnInvoked: false,
  );

  static List<List<FileContextOption>> allOptions(
    BuildContext context,
    FileContextActionHandler handler,
    Function(RemoteFile)? cutKey,
    Function(RemoteFile)? copyKey,
  ) {
    return [
      [open(handler), download(handler), saveAs(handler, context)],
      [share(handler), copyLink(handler, context)],
      [cut(handler, cutKey), copy(handler, copyKey), rename(handler, context)],
      [
        if (handler.removableCached)
          deleteUploaded(handler, context)
        else if (handler.downloadedCached)
          deleteLocal(handler, context),
        delete(handler, context),
        deleteCache(handler, context),
      ],
    ];
  }
}

class FilesContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function()? action;
  final dynamic Function()? secondaryAction;
  final IconData? secondaryIcon;
  final bool popOnInvoked;

  FilesContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
    this.secondaryAction,
    this.secondaryIcon,
    this.popOnInvoked = false,
  });

  static FilesContextOption downloadAll(FilesContextActionHandler handler) =>
      (() {
        final downloadAction = handler.download();
        final downloadedCount = handler.downloadedFilesCached.length;
        final totalCount = handler.files.length;
        final handledCount = handler.downloadedFilesCached
            .map((f) => f.key)
            .toSet()
            .union(handler.activeFilesCached.map((f) => f.key).toSet())
            .length;
        final allDownloaded = downloadedCount == totalCount;
        final allHandled = handledCount == totalCount;
        return FilesContextOption(
          title: downloadAction != null
              ? 'Download'
              : allDownloaded
              ? 'Downloaded'
              : allHandled
              ? 'Active Jobs'
              : 'Cannot Download',
          subtitle: downloadAction != null
              ? "Only missing files with backup folder set will be downloaded"
              : allDownloaded || allHandled
              ? null
              : 'Set backup folder to enable downloads',
          icon: downloadAction != null
              ? Icons.file_download_rounded
              : allDownloaded
              ? Icons.file_download_done_rounded
              : allHandled
              ? Icons.file_download_rounded
              : Icons.file_download_off_rounded,
          action: downloadAction,
          popOnInvoked: false,
        );
      })();

  static FilesContextOption saveAllTo(
    BuildContext context,
    FilesContextActionHandler handler,
  ) => FilesContextOption(
    title: 'Save To...',
    icon: Icons.save_as_rounded,
    action: handler.saveFile == null
        ? null
        : () async {
            final directory = await getDirectoryPath(
              canCreateDirectories: true,
            );
            bool saved = false;
            if (handler.saveAs(directory) != null) {
              handler.saveAs(directory)!();
              saved = true;
            }
            if (saved) {
              showSnackBar(
                SnackBar(content: Text('Saving files to $directory')),
              );
            }
          },
    popOnInvoked: false,
  );

  static FilesContextOption shareAll(FilesContextActionHandler handler) => (() {
    final getXFiles = handler.getXFiles();
    final allDownloaded =
        handler.downloadedFilesCached.length == handler.files.length;
    return FilesContextOption(
      title: getXFiles == null ? 'Cannot Share' : 'Share All',
      icon: Icons.share_rounded,
      subtitle: getXFiles == null
          ? 'No downloaded files to share'
          : allDownloaded
          ? null
          : 'Only downloaded files will be shared',
      action: getXFiles != null
          ? () {
              SharePlus.instance.share(ShareParams(files: getXFiles()));
            }
          : null,
    );
  })();

  static FilesContextOption copyAllLinks(
    BuildContext context,
    FilesContextActionHandler handler,
  ) => FilesContextOption(
    title: 'Copy Links',
    icon: Icons.link_rounded,
    action: () async {
      int? seconds = await expiryDialog(context);
      String allLinks = handler.getLinksToCopy(seconds)();
      if (allLinks.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: allLinks));
        showSnackBar(
          const SnackBar(content: Text('File links copied to clipboard')),
        );
      }
    },
    secondaryIcon: Icons.share_rounded,
    secondaryAction: () async {
      int? seconds = await expiryDialog(context);
      String allLinks = handler.getLinksToCopy(seconds)();
      if (allLinks.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: allLinks));
        showSnackBar(
          const SnackBar(content: Text('File links copied to clipboard')),
        );
        SharePlus.instance.share(ShareParams(text: allLinks));
      }
    },
  );

  static FilesContextOption cut(Function(RemoteFile?)? cutKey) =>
      FilesContextOption(
        title: 'Move To...',
        icon: Icons.cut_rounded,
        action: cutKey == null
            ? null
            : () {
                cutKey(null);
              },
        popOnInvoked: true,
      );

  static FilesContextOption copy(Function(RemoteFile?)? copyKey) =>
      FilesContextOption(
        title: 'Copy To...',
        icon: Icons.file_copy_rounded,
        action: copyKey == null
            ? null
            : () {
                copyKey(null);
              },
        popOnInvoked: true,
      );

  static FilesContextOption deleteUploaded(
    BuildContext context,
    FilesContextActionHandler handler,
    List<RemoteFile> removableFiles,
  ) => FilesContextOption(
    title: 'Remove from Device',
    subtitle: 'Only uploaded files',
    icon: Icons.phonelink_off_rounded,
    action: handler.deleteUploaded(removableFiles, true) == null
        ? null
        : () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Remove from Device'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete the local copies of ${removableFiles.length} uploaded files? Only uploaded files will be deleted from the device and can be downloaded again later.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: removableFiles.isEmpty
                          ? const Text('No files to delete')
                          : ListView.builder(
                              itemCount: removableFiles.length,
                              itemBuilder: (context, index) {
                                final file = removableFiles[index];
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    Main.pathFromKey(file.key) ?? file.key,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              await handler.deleteUploaded(removableFiles, true)!.call();
              showSnackBar(
                const SnackBar(
                  content: Text('Local copies of uploaded files deleted'),
                ),
              );
            }
          },
  );

  static FilesContextOption deleteLocalAll(
    BuildContext context,
    FilesContextActionHandler handler,
    List<RemoteFile> downloadedFiles,
  ) => FilesContextOption(
    title: 'Delete Local Copies',
    subtitle: 'Delete from device',
    icon: Icons.delete_rounded,
    action: handler.deleteLocal(true, downloadedFiles) == null
        ? null
        : () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Local Copies'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete the local copies of ${downloadedFiles.length} downloaded files? This action cannot be undone.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: downloadedFiles.isEmpty
                          ? const Text('No files to delete')
                          : ListView.builder(
                              itemCount: downloadedFiles.length,
                              itemBuilder: (context, index) {
                                final file = downloadedFiles[index];
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    Main.pathFromKey(file.key) ?? file.key,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              await handler.deleteLocal(true, downloadedFiles)!.call();
              showSnackBar(
                SnackBar(
                  content: Text(
                    'Local copies of ${downloadedFiles.length} selected files deleted',
                  ),
                ),
              );
            }
          },
  );

  static FilesContextOption deleteAll(
    BuildContext context,
    FilesContextActionHandler handler,
    Function() clearSelection,
  ) => FilesContextOption(
    title: 'Permanently Delete Files',
    icon: Icons.delete_forever_rounded,
    subtitle: 'Delete from device as well as S3',
    action: handler.delete(true) == null
        ? null
        : () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Permanently Delete Selected Files'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete ${handler.files.length} selected files from your device and S3? This action cannot be undone.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: handler.files.isEmpty
                          ? const Text('No files to delete')
                          : ListView.builder(
                              itemCount: handler.files.length,
                              itemBuilder: (context, index) {
                                final file = handler.files[index];
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    Main.pathFromKey(file.key) ?? file.key,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              await handler.delete(true)!.call();
              clearSelection();
              showSnackBar(
                const SnackBar(
                  content: Text('Selected files deleted from device and S3'),
                ),
              );
            }
          },
    popOnInvoked: true,
  );

  static FilesContextOption deleteCache(
    BuildContext context,
    FilesContextActionHandler handler,
  ) => FilesContextOption(
    title: 'Delete Cache',
    subtitle: 'Delete cached copies of files',
    icon: Icons.delete_outline_rounded,
    action: handler.deleteCache(true) == null
        ? null
        : () async {
            final cacheFiles = handler.cachedFilesCached;
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Cache'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete the cached copies of the following ${cacheFiles.length} selected files? This action cannot be undone.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: cacheFiles.isEmpty
                          ? const Text('No cached files to delete')
                          : ListView.builder(
                              itemCount: cacheFiles.length,
                              itemBuilder: (context, index) {
                                final file = cacheFiles[index];
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    Main.pathFromKey(file.key) ?? file.key,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              await handler.deleteCache(true)!.call();
              showSnackBar(
                const SnackBar(content: Text('Cached copies deleted')),
              );
            }
          },
  );

  static List<List<FilesContextOption>> allOptions(
    BuildContext context,
    FilesContextActionHandler handler,
    Function(RemoteFile?)? cutKey,
    Function(RemoteFile?)? copyKey,
    Function() clearSelection,
  ) {
    return [
      [downloadAll(handler), saveAllTo(context, handler)],
      [shareAll(handler), copyAllLinks(context, handler)],
      [cut(cutKey), copy(copyKey)],
      [
        if (handler.removableFilesCached.isNotEmpty)
          deleteUploaded(context, handler, handler.removableFilesCached),
        if (handler.downloadedFilesCached.isNotEmpty)
          deleteLocalAll(context, handler, handler.downloadedFilesCached),
        deleteAll(context, handler, clearSelection),
        deleteCache(context, handler),
      ],
    ];
  }
}

class DirectoryContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function()? action;
  final bool popOnInvoked;

  DirectoryContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
    this.popOnInvoked = false,
  });

  static DirectoryContextOption open(DirectoryContextActionHandler handler) =>
      (() {
        final openAction = handler.open();
        return DirectoryContextOption(
          title: openAction == null ? 'Cannot Open' : 'Open',
          subtitle: openAction == null
              ? 'Directory does not exist locally'
              : Main.pathFromKey(handler.file.key),
          icon: openAction == null ? Icons.open_in_new_off : Icons.open_in_new,
          action: openAction,
        );
      })();

  static DirectoryContextOption download(
    DirectoryContextActionHandler handler,
  ) => (() {
    final downloadAction = handler.download();
    final downloadedCount = handler.downloadedFilesCached.length;
    final totalCount = handler.files.length;
    final handledCount = handler.downloadedFilesCached
        .map((f) => f.key)
        .toSet()
        .union(handler.activeFilesCached.map((f) => f.key).toSet())
        .length;
    final allDownloaded = downloadedCount == totalCount;
    final allHandled = handledCount == totalCount;
    return DirectoryContextOption(
      title: downloadAction != null
          ? 'Download'
          : allDownloaded
          ? 'Downloaded'
          : allHandled
          ? 'Active Jobs'
          : 'Cannot Download',
      subtitle: downloadAction != null
          ? "Only missing files with backup folder set will be downloaded"
          : allDownloaded || allHandled
          ? null
          : 'Set backup folder to enable downloads',
      icon: downloadAction != null
          ? Icons.file_download_rounded
          : allDownloaded
          ? Icons.file_download_done_rounded
          : allHandled
          ? Icons.file_download_rounded
          : Icons.file_download_off_rounded,
      action: downloadAction,
    );
  })();

  static DirectoryContextOption saveTo(
    DirectoryContextActionHandler handler,
    BuildContext context,
  ) => DirectoryContextOption(
    title: 'Save To...',
    icon: Icons.save_as_rounded,
    action: handler.saveDirectory == null
        ? null
        : () async {
            final directory = await getDirectoryPath(
              canCreateDirectories: true,
            );
            final handle = handler.saveAs(
              directory == null
                  ? null
                  : p.join(directory, p.basename(handler.file.key)),
            );
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(handle())));
            }
          },
  );

  static DirectoryContextOption cut(
    DirectoryContextActionHandler handler,
    Function(RemoteFile)? cutKey,
  ) => DirectoryContextOption(
    title: 'Move To...',
    icon: Icons.cut_rounded,
    action: cutKey == null
        ? null
        : () {
            cutKey(handler.file);
          },
    popOnInvoked: true,
  );

  static DirectoryContextOption copy(
    DirectoryContextActionHandler handler,
    Function(RemoteFile)? copyKey,
  ) => DirectoryContextOption(
    title: 'Copy To...',
    icon: Icons.folder_copy_rounded,
    action: copyKey == null
        ? null
        : () {
            copyKey(handler.file);
          },
    popOnInvoked: true,
  );

  static DirectoryContextOption rename(
    BuildContext context,
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: 'Rename',
    icon: Icons.edit_rounded,
    action: handler.moveDirectories == null
        ? null
        : () async {
            final newName = await renameDialog(
              context,
              p.basenameWithoutExtension(handler.file.key),
            );
            if (newName != null &&
                newName.isNotEmpty &&
                newName != p.basename(handler.file.key)) {
              showSnackBar(
                SnackBar(content: Text(await handler.rename(newName)!())),
              );
            }
          },
    popOnInvoked: true,
  );

  static DirectoryContextOption deleteUploaded(
    BuildContext context,
    DirectoryContextActionHandler handler,
    List<RemoteFile> removableFiles,
  ) => DirectoryContextOption(
    title: 'Remove from Device',
    subtitle: 'Only uploaded files',
    icon: Icons.phonelink_off_rounded,
    action: handler.deleteUploaded(removableFiles, true) == null
        ? null
        : () async {
            bool? yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Remove from Device'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete the local copies of ${removableFiles.length} uploaded files in ${p.basename(handler.file.key)}? Only uploaded files will be deleted from the device and can be downloaded again later.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final file in removableFiles)
                                Text(Main.pathFromKey(file.key) ?? file.key),
                              if (removableFiles.isEmpty)
                                const Text('No files to delete'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: handler.removableFilesCached.isNotEmpty
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              showSnackBar(
                SnackBar(
                  content: Text(
                    await handler.deleteUploaded(
                      handler.removableFilesCached,
                      true,
                    )!(),
                  ),
                ),
              );
            }
          },
  );

  static DirectoryContextOption deleteLocal(
    BuildContext context,
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: 'Delete Local Copy',
    subtitle: 'Delete from device',
    icon: Icons.folder_delete_rounded,
    action: handler.deleteLocal(true) == null
        ? null
        : () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Local Copy'),
                content: Text(
                  'Are you sure you want to delete the local copy of ${p.basename(handler.file.key)}? This action cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              showSnackBar(
                SnackBar(content: Text(await handler.deleteLocal(true)!())),
              );
            }
          },
  );

  static DirectoryContextOption delete(
    BuildContext context,
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: 'Permanently Delete',
    icon: Icons.delete_forever_rounded,
    subtitle: 'Delete from device as well as S3',
    action: handler.delete(true) == null
        ? null
        : () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Permanently Delete Folder'),
                content: Text(
                  'Are you sure you want to delete ${p.basename(handler.file.key)} from your device and S3? This action cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              showSnackBar(
                SnackBar(content: Text(await handler.delete(true)!())),
              );
            }
          },
    popOnInvoked: true,
  );

  static DirectoryContextOption deleteCache(
    BuildContext context,
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: 'Delete Cache',
    subtitle: 'Delete cached copy of folder',
    icon: Icons.delete_outline_rounded,
    action: handler.deleteCache(true) == null
        ? null
        : () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Cache'),
                content: Text(
                  'Are you sure you want to delete the cached copy of ${p.basename(handler.file.key)}? This action cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              showSnackBar(
                SnackBar(content: Text(await handler.deleteCache(true)!())),
              );
            }
          },
  );

  static List<List<DirectoryContextOption>> allOptions(
    BuildContext context,
    DirectoryContextActionHandler handler,
    Function(RemoteFile)? cutKey,
    Function(RemoteFile)? copyKey,
  ) {
    return [
      [open(handler), download(handler), saveTo(handler, context)],
      [
        cut(handler, cutKey),
        copy(handler, copyKey),
        if (handler.rename('any name') != null) rename(context, handler),
      ],
      [
        if (handler.removableFilesCached.isNotEmpty)
          deleteUploaded(context, handler, handler.removableFilesCached),
        if (handler.localExistsCached) deleteLocal(context, handler),
        delete(context, handler),
        deleteCache(context, handler),
      ],
    ];
  }
}

class DirectoriesContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function()? action;
  final bool popOnInvoked;

  DirectoriesContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
    this.popOnInvoked = false,
  });

  static DirectoriesContextOption downloadAll(
    DirectoriesContextActionHandler handler,
  ) => (() {
    final downloadAction = handler.download();
    final downloadedCount = handler.downloadedFilesCached.length;
    final totalCount = handler.files.length;
    final handledCount = handler.downloadedFilesCached
        .map((f) => f.key)
        .toSet()
        .union(handler.activeFilesCached.map((f) => f.key).toSet())
        .length;
    final allDownloaded = downloadedCount == totalCount;
    final allHandled = handledCount == totalCount;
    return DirectoriesContextOption(
      title: downloadAction != null
          ? 'Download'
          : allDownloaded
          ? 'Downloaded'
          : allHandled
          ? 'Active Jobs'
          : 'Cannot Download',
      subtitle: downloadAction != null
          ? "Only missing files with backup folder set will be downloaded"
          : allDownloaded
          ? null
          : allHandled
          ? null
          : 'Set backup folder to enable downloads',
      icon: downloadAction != null
          ? Icons.file_download_rounded
          : allDownloaded
          ? Icons.file_download_done_rounded
          : allHandled
          ? Icons.file_download_rounded
          : Icons.file_download_off_rounded,
      action: downloadAction,
    );
  })();

  static DirectoriesContextOption saveAllTo(
    DirectoriesContextActionHandler handler,
    BuildContext context,
  ) => DirectoriesContextOption(
    title: 'Save To...',
    icon: Icons.save_as_rounded,
    action: handler.saveDirectory == null
        ? null
        : () async {
            final directory = await getDirectoryPath(
              canCreateDirectories: true,
            );
            bool saved = false;
            final handle = handler.saveAs(directory);
            if (handle != null) {
              handle();
              saved = true;
            }
            if (saved) {
              showSnackBar(
                SnackBar(content: Text('Saving directories to $directory')),
              );
            }
          },
  );

  static DirectoriesContextOption cut(Function(RemoteFile?)? cutKey) =>
      DirectoriesContextOption(
        title: 'Move To...',
        icon: Icons.cut_rounded,
        action: cutKey == null
            ? null
            : () {
                cutKey(null);
              },
        popOnInvoked: true,
      );

  static DirectoriesContextOption copy(Function(RemoteFile?)? copyKey) =>
      DirectoriesContextOption(
        title: 'Copy To...',
        icon: Icons.folder_copy_rounded,
        action: copyKey == null
            ? null
            : () {
                copyKey(null);
              },
        popOnInvoked: true,
      );

  static DirectoriesContextOption deleteUploaded(
    DirectoriesContextActionHandler handler,
    BuildContext context,
    List<RemoteFile> removableFiles,
  ) => DirectoriesContextOption(
    title: 'Remove from Device',
    subtitle: 'Only uploaded files',
    icon: Icons.phonelink_off_rounded,
    action: handler.deleteUploaded(removableFiles, true) == null
        ? null
        : () async {
            bool? yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Remove from Device'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete the local copies of ${removableFiles.length} uploaded files in the selected folders? Only uploaded files will be deleted from the device and can be downloaded again later.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final file in removableFiles)
                                Text(Main.pathFromKey(file.key) ?? file.key),
                              if (removableFiles.isEmpty)
                                const Text('No files to delete'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: handler.removableFilesCached.isNotEmpty
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              showSnackBar(
                SnackBar(
                  content: Text(
                    await handler.deleteUploaded(
                      handler.removableFilesCached,
                      true,
                    )!(),
                  ),
                ),
              );
            }
          },
  );

  static DirectoriesContextOption deleteLocal(
    DirectoriesContextActionHandler handler,
    BuildContext context,
    List<RemoteFile> localDirectories,
  ) => DirectoriesContextOption(
    title: 'Delete Local Copies',
    subtitle: 'Delete from device',
    icon: Icons.folder_delete_rounded,
    action: handler.deleteLocal(true, localDirectories) == null
        ? null
        : () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Local Copies'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete the local copies of the ${localDirectories.length} selected directories? This action cannot be undone.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final directory in localDirectories)
                                Text(
                                  Main.pathFromKey(directory.key) ??
                                      directory.key,
                                ),
                              if (localDirectories.isEmpty)
                                const Text('No directories to delete'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              await handler.deleteLocal(true, localDirectories)!.call();
              showSnackBar(
                SnackBar(
                  content: Text(
                    'Local copies of ${localDirectories.length} selected directories deleted',
                  ),
                ),
              );
            }
          },
  );

  static DirectoriesContextOption deleteAll(
    DirectoriesContextActionHandler handler,
    BuildContext context,
    Function() clearSelection,
  ) => DirectoriesContextOption(
    title: 'Permanently Delete Folders',
    subtitle: 'Delete from device as well as S3',
    icon: Icons.delete_forever_rounded,
    action: handler.deleteDirectories == null
        ? null
        : () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Permanently Delete Selected Folders'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete ${handler.directories.length} selected folders from your device and S3? This action cannot be undone.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final directory in handler.directories)
                                Text(
                                  Main.pathFromKey(directory.key) ??
                                      directory.key,
                                ),
                              if (handler.directories.isEmpty)
                                const Text('No directories to delete'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              await handler.delete(true)!.call();
              clearSelection();
              showSnackBar(
                SnackBar(
                  content: Text(
                    '${handler.directories.length} selected folders deleted from device and S3',
                  ),
                ),
              );
            }
          },
    popOnInvoked: true,
  );

  static DirectoriesContextOption deleteCache(
    DirectoriesContextActionHandler handler,
    BuildContext context,
  ) => DirectoriesContextOption(
    title: 'Delete Cache',
    subtitle: 'Delete cached copies of folders',
    icon: Icons.delete_outline_rounded,
    action: handler.deleteCache(true) == null
        ? null
        : () async {
            final cachedDirectories = handler.cachedDirectoriesCached;
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Cache'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete the cached copies of the following ${cachedDirectories.length} selected folders? This action cannot be undone.',
                    ),
                    Container(
                      height: 200,
                      padding: EdgeInsets.only(top: 16),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final directory in cachedDirectories)
                                Text(
                                  Main.pathFromKey(directory.key) ??
                                      directory.key,
                                ),
                              if (cachedDirectories.isEmpty)
                                const Text('No cached directories to delete'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              await handler.deleteCache(true)?.call();
              showSnackBar(SnackBar(content: Text('Cached copies deleted')));
            }
          },
  );

  static List<List<DirectoriesContextOption>> allOptions(
    BuildContext context,
    DirectoriesContextActionHandler handler,
    Function(RemoteFile?)? cutKey,
    Function(RemoteFile?)? copyKey,
    Function() clearSelection,
  ) {
    return [
      [downloadAll(handler), saveAllTo(handler, context)],
      [cut(cutKey), copy(copyKey)],
      [
        if (handler.removableFilesCached.isNotEmpty)
          deleteUploaded(handler, context, handler.removableFilesCached),
        if (handler.localDirectoriesCached.isNotEmpty)
          deleteLocal(handler, context, handler.localDirectoriesCached),
        deleteAll(handler, context, clearSelection),
        deleteCache(handler, context),
      ],
    ];
  }
}

class BulkContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function(BuildContext context)? action;
  final bool popOnInvoked;

  BulkContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
    this.popOnInvoked = false,
  });

  static BulkContextOption downloadAll(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
  ) => (() {
    final directoryDownload = directoriesHandler.download();
    final fileDownload = filesHandler.download();
    final hasDownloadAction = directoryDownload != null || fileDownload != null;
    final allDownloaded =
        directoriesHandler.downloadedFilesCached.length ==
            directoriesHandler.files.length &&
        filesHandler.downloadedFilesCached.length == filesHandler.files.length;
    final allItemsHandled =
        <String>{
          ...directoriesHandler.downloadedFilesCached.map((f) => f.key),
          ...directoriesHandler.activeFilesCached.map((f) => f.key),
          ...filesHandler.downloadedFilesCached.map((f) => f.key),
          ...filesHandler.activeFilesCached.map((f) => f.key),
        }.length ==
        directoriesHandler.files.length + filesHandler.files.length;
    return BulkContextOption(
      title: hasDownloadAction
          ? 'Download'
          : allDownloaded
          ? 'Downloaded'
          : allItemsHandled
          ? 'Active Jobs'
          : 'Cannot Download',
      subtitle: hasDownloadAction
          ? 'Only missing files with backup folder set will be downloaded'
          : allDownloaded
          ? null
          : allItemsHandled
          ? null
          : 'Set backup folder to enable downloads',
      icon: hasDownloadAction
          ? Icons.file_download_rounded
          : allDownloaded
          ? Icons.file_download_done_rounded
          : allItemsHandled
          ? Icons.file_download_rounded
          : Icons.file_download_off_rounded,
      action: directoryDownload == null && fileDownload == null
          ? null
          : (BuildContext context) {
              directoryDownload?.call();
              fileDownload?.call();
            },
    );
  })();

  static BulkContextOption saveAllTo(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
  ) => BulkContextOption(
    title: 'Save To...',
    icon: Icons.save_as_rounded,
    action: (BuildContext context) async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      bool saved = false;
      for (final handler in [directoriesHandler, filesHandler]) {
        late String Function()? handle;
        handle = handler.saveAs(directory);
        if (handle != null) {
          handle();
          saved = true;
        }
      }
      if (saved) {
        showSnackBar(SnackBar(content: Text('Saving items to $directory')));
      }
    },
  );

  static BulkContextOption cut(Function(RemoteFile?)? cutKey) =>
      BulkContextOption(
        title: 'Move To...',
        icon: Icons.cut_rounded,
        action: cutKey == null
            ? null
            : (BuildContext context) {
                cutKey(null);
              },
        popOnInvoked: true,
      );

  static BulkContextOption copy(Function(RemoteFile?)? copyKey) =>
      BulkContextOption(
        title: 'Copy To...',
        icon: Icons.copy_rounded,
        action: copyKey == null
            ? null
            : (BuildContext context) {
                copyKey(null);
              },
        popOnInvoked: true,
      );

  static BulkContextOption deleteUploaded(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
  ) => BulkContextOption(
    title: 'Remove from Device',
    subtitle: 'Only uploaded files',
    icon: Icons.phonelink_off_rounded,
    action: (BuildContext context) async {
      final removableFiles = [
        ...directoriesHandler.removableFilesCached,
        ...filesHandler.removableFilesCached,
      ];
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove from Device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to delete the local copies of ${removableFiles.length} files? Only uploaded files will be deleted from the device and can be downloaded again later.',
              ),
              Container(
                height: 200,
                padding: const EdgeInsets.only(top: 16),
                child: removableFiles.isEmpty
                    ? const Text('No files to delete')
                    : ListView.builder(
                        itemCount: removableFiles.length,
                        itemBuilder: (context, index) {
                          final file = removableFiles[index];
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(Main.pathFromKey(file.key) ?? file.key),
                          );
                        },
                      ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes ?? false) {
        await directoriesHandler
            .deleteUploaded(directoriesHandler.removableFilesCached, true)
            ?.call();
        await filesHandler
            .deleteUploaded(filesHandler.removableFilesCached, true)
            ?.call();
        showSnackBar(
          const SnackBar(
            content: Text('Local copies of uploaded items deleted'),
          ),
        );
      }
    },
  );

  static BulkContextOption deleteLocalAll(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
  ) => BulkContextOption(
    title: 'Delete Local Copies',
    subtitle: 'Delete from device',
    icon: Icons.folder_delete_rounded,
    action: (BuildContext context) async {
      final localDirectories = directoriesHandler.localDirectoriesCached;
      final downloadedFiles = filesHandler.downloadedFilesCached;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Local Copies'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to delete the local copies of ${localDirectories.length + downloadedFiles.length} selected items? This action cannot be undone.',
              ),
              Container(
                height: 200,
                padding: const EdgeInsets.only(top: 16),
                child: localDirectories.isEmpty && downloadedFiles.isEmpty
                    ? const Text('No items to delete')
                    : ListView.builder(
                        itemCount:
                            localDirectories.length + downloadedFiles.length,
                        itemBuilder: (context, index) {
                          final file = index < localDirectories.length
                              ? localDirectories[index]
                              : downloadedFiles[index -
                                    localDirectories.length];
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(Main.pathFromKey(file.key) ?? file.key),
                          );
                        },
                      ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes ?? false) {
        await directoriesHandler
            .deleteLocal(true, directoriesHandler.localDirectoriesCached)!
            .call();
        await filesHandler
            .deleteLocal(true, filesHandler.downloadedFilesCached)!
            .call();
        showSnackBar(
          const SnackBar(
            content: Text('Local copies of selected items deleted'),
          ),
        );
      }
    },
  );

  static BulkContextOption deleteAll(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
    Function() clearSelection,
  ) => BulkContextOption(
    title: 'Permanently Delete Selection',
    subtitle: 'Delete from device as well as S3',
    icon: Icons.delete_forever_rounded,
    action: (BuildContext context) async {
      final directories = directoriesHandler.directories;
      final files = filesHandler.files;
      final yes =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permanently Delete Selection'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Are you sure you want to permanently delete ${directories.length + files.length} selected items from your device and S3? This action cannot be undone.',
                  ),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.only(top: 16),
                    child: directories.isEmpty && files.isEmpty
                        ? const Text('No items to delete')
                        : ListView.builder(
                            itemCount: directories.length + files.length,
                            itemBuilder: (context, index) {
                              final file = index < directories.length
                                  ? directories[index]
                                  : files[index - directories.length];
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(
                                  Main.pathFromKey(file.key) ?? file.key,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
      if (yes) {
        for (final handler in [directoriesHandler, filesHandler]) {
          await handler.delete(true)!.call();
        }
        clearSelection();
        showSnackBar(
          const SnackBar(
            content: Text('Selected items deleted from device and S3'),
          ),
        );
      }
    },
    popOnInvoked: true,
  );

  static BulkContextOption deleteCache(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
  ) => BulkContextOption(
    title: 'Delete Cache',
    subtitle: 'Delete cached copies of folders',
    icon: Icons.delete_outline_rounded,
    action:
        filesHandler.deleteCache(true) == null &&
            directoriesHandler.deleteCache(true) == null
        ? null
        : (BuildContext context) async {
            final cacheFiles = filesHandler.cachedFilesCached;
            final cachedDirectories =
                directoriesHandler.cachedDirectoriesCached;
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Cache'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are you sure you want to delete the cached copies of ${cachedDirectories.length} selected folders and ${cacheFiles.length} selected files? This action cannot be undone.',
                    ),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.only(top: 16),
                      child: cachedDirectories.isEmpty && cacheFiles.isEmpty
                          ? const Text('Nothing to delete')
                          : ListView.builder(
                              itemCount:
                                  cachedDirectories.length + cacheFiles.length,
                              itemBuilder: (context, index) {
                                final file = index < cachedDirectories.length
                                    ? cachedDirectories[index]
                                    : cacheFiles[index -
                                          cachedDirectories.length];
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(file.key),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              await directoriesHandler.deleteCache(true)?.call();
              await filesHandler.deleteCache(true)?.call();
              showSnackBar(SnackBar(content: Text('Cached copies deleted')));
            }
          },
  );

  static List<List<BulkContextOption>> allOptions(
    Function(RemoteFile?)? cutKey,
    Function(RemoteFile?)? copyKey,
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
    Function() clearSelection,
  ) {
    return [
      [
        downloadAll(directoriesHandler, filesHandler),
        saveAllTo(directoriesHandler, filesHandler, context),
      ],
      [cut(cutKey), copy(copyKey)],
      [
        if (directoriesHandler.removableFilesCached.isNotEmpty ||
            filesHandler.removableFilesCached.isNotEmpty)
          deleteUploaded(directoriesHandler, filesHandler, context),
        if (directoriesHandler.localDirectoriesCached.isNotEmpty ||
            filesHandler.downloadedFilesCached.isNotEmpty)
          deleteLocalAll(directoriesHandler, filesHandler, context),
        deleteAll(directoriesHandler, filesHandler, context, clearSelection),
        deleteCache(directoriesHandler, filesHandler, context),
      ],
    ];
  }
}

Widget buildFileContextMenu(
  BuildContext context,
  RemoteFile item,
  bool allowModify,
  String? Function(RemoteFile, int?) getLink,
  Function(RemoteFile)? downloadFile,
  Function(RemoteFile, String)? saveFile,
  Function(RemoteFile)? cut,
  Function(RemoteFile)? copy,
  Future<void> Function(List<String>, List<String>)? moveFiles,
  Function(String)? deleteLocal,
  Function(String)? deleteCache,
  Future<void> Function(List<String>)? deleteFiles,
  void Function()? onInvoked,
) {
  String? mediaType = getMediaType(item.key);
  FileContextActionHandler handler = FileContextActionHandler(
    file: item,
    getLink: getLink,
    downloadFile: downloadFile,
    saveFile: saveFile,
    moveFiles: allowModify ? moveFiles : null,
    deleteLocalFile: deleteLocal,
    deleteCacheFile: deleteCache,
    deleteFiles: allowModify ? deleteFiles : null,
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: M3ECard(
          index: 0,
          position: M3ECardPosition.single,
          outerRadius: 18,
          innerRadius: 4,
          gap: 3,
          padding: EdgeInsets.zero,
          color: Colors.transparent,
          child: ListTile(
            visualDensity: VisualDensity.comfortable,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: Icon(mediaTypeIcon(mediaType)),
            title: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(item.key),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: InfoRow(
                    file: item,
                    uiConfig: UiConfig(
                      showTime: true,
                      showSize: true,
                      showDownloadStatus: false,
                      showType: true,
                    ),
                  ),
                ),
                Text('MD5: ${item.etag}'),
              ],
            ),
          ),
        ),
      ),
      ...(FileContextOption.allOptions(
        context,
        handler,
        allowModify ? cut : null,
        allowModify ? copy : null,
      ).map(
        (options) => M3ECardColumn(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: EdgeInsets.zero,
          outerRadius: 14,
          color: Colors.transparent,
          children: options
              .map(
                (option) => ListTile(
                  visualDensity: VisualDensity.comfortable,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  leading: Icon(option.icon),
                  title: Text(option.title),
                  subtitle: option.subtitle != null
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(option.subtitle!),
                        )
                      : null,
                  trailing: option.secondaryAction != null
                      ? IconButton(
                          onPressed: () async {
                            await option.secondaryAction!();
                            handler.invalidateCache();
                            onInvoked?.call();
                          },
                          icon: Icon(option.secondaryIcon),
                        )
                      : null,
                  onTap: option.action == null
                      ? null
                      : () async {
                          if (option.popOnInvoked) globalNavigator?.pop();
                          await option.action!();
                          handler.invalidateCache();
                          onInvoked?.call();
                        },
                  enabled: option.action != null,
                ),
              )
              .toList(),
        ),
      )),
    ],
  );
}

Widget buildFilesContextMenu(
  BuildContext context,
  List<RemoteFile> items,
  String? Function(RemoteFile, int?) getLink,
  Function(RemoteFile)? downloadFile,
  Function(RemoteFile, String)? saveFile,
  Function(RemoteFile?)? cut,
  Function(RemoteFile?)? copy,
  Future<void> Function(List<String>, List<String>)? moveFiles,
  Function(String)? deleteLocal,
  Function(String)? deleteCache,
  Future<void> Function(List<String>)? deleteFiles,
  Function() clearSelection,
  void Function()? onInvoked,
) {
  FilesContextActionHandler handler = FilesContextActionHandler(
    files: items,
    getLink: getLink,
    downloadFile: downloadFile,
    saveFile: saveFile,
    moveFiles: moveFiles,
    deleteLocalFile: deleteLocal,
    deleteCacheFile: deleteCache,
    deleteFiles: deleteFiles,
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children:
        FilesContextOption.allOptions(
              context,
              handler,
              cut,
              copy,
              clearSelection,
            )
            .map(
              (options) => M3ECardColumn(
                margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: EdgeInsets.zero,
                outerRadius: 14,
                color: Colors.transparent,
                children: options
                    .map(
                      (option) => ListTile(
                        visualDensity: VisualDensity.comfortable,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        leading: Icon(option.icon),
                        title: Text(option.title),
                        subtitle: option.subtitle != null
                            ? Text(option.subtitle!)
                            : null,
                        trailing: option.secondaryAction != null
                            ? IconButton(
                                onPressed: () async {
                                  await option.secondaryAction!();
                                  handler.invalidateCache();
                                  onInvoked?.call();
                                },
                                icon: Icon(option.secondaryIcon),
                              )
                            : null,
                        onTap: option.action != null
                            ? () async {
                                if (option.popOnInvoked) globalNavigator?.pop();
                                await option.action!();
                                handler.invalidateCache();
                                onInvoked?.call();
                              }
                            : null,
                        enabled: option.action != null,
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
  );
}

Widget buildDirectoryContextMenu(
  BuildContext context,
  RemoteFile file,
  bool allowModify,
  Function(RemoteFile)? downloadDirectory,
  Function(RemoteFile, String)? saveDirectory,
  Function(RemoteFile)? cut,
  Function(RemoteFile)? copy,
  Future<void> Function(List<String>, List<String>)? moveDirectories,
  Function(String)? deleteLocal,
  Function(String)? deleteCache,
  Future<void> Function(List<String>)? deleteDirectories,
  void Function()? onInvoked,
) {
  DirectoryContextActionHandler handler = DirectoryContextActionHandler(
    file: file,
    downloadDirectory: downloadDirectory,
    saveDirectory: saveDirectory,
    moveDirectories: allowModify ? moveDirectories : null,
    deleteLocalDirectory: deleteLocal,
    deleteCacheDirectory: deleteCache,
    deleteDirectories: allowModify ? deleteDirectories : null,
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: M3ECard(
          index: 0,
          position: M3ECardPosition.single,
          outerRadius: 14,
          innerRadius: 4,
          gap: 3,
          padding: EdgeInsets.zero,
          color: Colors.transparent,
          child: ListTile(
            visualDensity: VisualDensity.comfortable,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: Icon(Icons.cloud_circle_rounded),
            title: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(file.key),
            ),
            subtitle: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: InfoRow(
                file: file,
                uiConfig: UiConfig(
                  showTime: true,
                  showSize: true,
                  showDownloadStatus: false,
                  showContent: true,
                ),
              ),
            ),
            onTap:
                Main.profileFromKey(file.key) == null ||
                    p.split(file.key).length != 1
                ? null
                : () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => S3ConfigPage(
                          profile: Main.profileFromKey(file.key)!,
                        ),
                      ),
                    );
                  },
          ),
        ),
      ),
      if (p.split(file.key).length == 1)
        ProfileBackupConfig(
          initialBackupMode: Main.backupModeFromKey(file.key),
          initialLocalDir: Main.pathFromKey(file.key),
          onBackupModeChanged: (mode) {
            ConfigManager.setBackupMode(file.key, mode);
            Main.listDirectories();
            globalNavigator!.pop();
          },
          onLocalDirChanged: (localDir) {
            ConfigManager.setLocalDir(file.key, localDir);
            Main.listDirectories();
            globalNavigator!.pop();
          },
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          outerRadius: 14,
          visualDensity: VisualDensity.comfortable,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        ),
      ...(DirectoryContextOption.allOptions(
        context,
        handler,
        allowModify ? cut : null,
        allowModify ? copy : null,
      ).map(
        (options) => M3ECardColumn(
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: EdgeInsets.zero,
          outerRadius: 14,
          color: Colors.transparent,
          children: options
              .map(
                (option) => ListTile(
                  visualDensity: VisualDensity.comfortable,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  leading: Icon(option.icon),
                  title: Text(option.title),
                  subtitle: option.subtitle != null
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(option.subtitle!),
                        )
                      : null,
                  onTap: option.action != null
                      ? () async {
                          if (option.popOnInvoked) globalNavigator?.pop();
                          await option.action!();
                          handler.invalidateCache();
                          onInvoked?.call();
                        }
                      : null,
                  enabled: option.action != null,
                ),
              )
              .toList(),
        ),
      )),
    ],
  );
}

Widget buildDirectoriesContextMenu(
  BuildContext context,
  List<RemoteFile> dirs,
  Function(RemoteFile)? downloadDirectory,
  Function(RemoteFile, String)? saveDirectory,
  Function(RemoteFile?)? cut,
  Function(RemoteFile?)? copy,
  Future<void> Function(List<String>, List<String>)? moveDirectories,
  Function(String)? deleteLocal,
  Function(String)? deleteCache,
  Future<void> Function(List<String>)? deleteDirectories,
  Function() clearSelection,
  void Function()? onInvoked,
) {
  DirectoriesContextActionHandler handler = DirectoriesContextActionHandler(
    directories: dirs,
    downloadDirectory: downloadDirectory,
    saveDirectory: saveDirectory,
    moveDirectories: moveDirectories,
    deleteLocalDirectory: deleteLocal,
    deleteCacheDirectory: deleteCache,
    deleteDirectories: deleteDirectories,
  );
  return Column(
    children:
        DirectoriesContextOption.allOptions(
              context,
              handler,
              cut,
              copy,
              clearSelection,
            )
            .map(
              (options) => M3ECardColumn(
                margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: EdgeInsets.zero,
                outerRadius: 14,
                color: Colors.transparent,
                children: options
                    .map(
                      (option) => ListTile(
                        visualDensity: VisualDensity.comfortable,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        leading: Icon(option.icon),
                        title: Text(option.title),
                        subtitle: option.subtitle != null
                            ? Text(option.subtitle!)
                            : null,
                        onTap: option.action != null
                            ? () async {
                                if (option.popOnInvoked) globalNavigator?.pop();
                                await option.action!();
                                handler.invalidateCache();
                                onInvoked?.call();
                              }
                            : null,
                        enabled: option.action != null,
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
  );
}

Widget buildBulkContextMenu(
  BuildContext context,
  List<RemoteFile> items,
  String? Function(RemoteFile, int?) getLink,
  Function(RemoteFile)? downloadFile,
  Function(RemoteFile)? downloadDirectory,
  Function(RemoteFile, String)? saveFile,
  Function(RemoteFile, String)? saveDirectory,
  Future<void> Function(List<String>, List<String>)? moveFiles,
  Future<void> Function(List<String>, List<String>)? moveDirectories,
  Function(RemoteFile?)? cut,
  Function(RemoteFile?)? copy,
  Function(String)? deleteLocal,
  Function(String)? deleteCache,
  Future<void> Function(List<String>)? deleteFiles,
  Future<void> Function(List<String>)? deleteDirectories,
  Function() clearSelection,
  void Function()? onInvoked,
) {
  if (!items.any((item) => p.isDir(item.key))) {
    return buildFilesContextMenu(
      context,
      items,
      getLink,
      downloadFile,
      saveFile,
      cut,
      copy,
      moveFiles,
      deleteLocal,
      deleteCache,
      deleteFiles,
      clearSelection,
      onInvoked,
    );
  } else if (items.every((item) => p.isDir(item.key))) {
    return buildDirectoriesContextMenu(
      context,
      items,
      downloadDirectory,
      saveDirectory,
      cut,
      copy,
      moveDirectories,
      deleteLocal,
      deleteCache,
      deleteDirectories,
      clearSelection,
      onInvoked,
    );
  } else {
    DirectoriesContextActionHandler dirHandler =
        DirectoriesContextActionHandler(
          directories: items.where((item) => p.isDir(item.key)).toList(),
          downloadDirectory: downloadDirectory,
          saveDirectory: saveDirectory,
          moveDirectories: moveDirectories,
          deleteLocalDirectory: deleteLocal,
          deleteCacheDirectory: deleteCache,
          deleteDirectories: deleteDirectories,
        );
    FilesContextActionHandler fileHandler = FilesContextActionHandler(
      files: items.where((item) => !p.isDir(item.key)).toList(),
      getLink: getLink,
      downloadFile: downloadFile,
      saveFile: saveFile,
      moveFiles: moveFiles,
      deleteLocalFile: deleteLocal,
      deleteCacheFile: deleteCache,
      deleteFiles: deleteFiles,
    );
    return Column(
      children:
          BulkContextOption.allOptions(
                cut,
                copy,
                dirHandler,
                fileHandler,
                context,
                clearSelection,
              )
              .map(
                (options) => M3ECardColumn(
                  margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  padding: EdgeInsets.zero,
                  outerRadius: 14,
                  color: Colors.transparent,
                  children: options
                      .map(
                        (option) => ListTile(
                          visualDensity: VisualDensity.comfortable,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 0,
                          ),
                          leading: Icon(option.icon),
                          title: Text(option.title),
                          subtitle: option.subtitle != null
                              ? Text(option.subtitle!)
                              : null,
                          onTap: option.action != null
                              ? () async {
                                  if (option.popOnInvoked) {
                                    globalNavigator?.pop();
                                  }
                                  await option.action!(context);
                                  dirHandler.invalidateCache();
                                  fileHandler.invalidateCache();
                                  onInvoked?.call();
                                }
                              : null,
                          enabled: option.action != null,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
    );
  }
}
