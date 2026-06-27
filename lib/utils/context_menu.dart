import 'dart:io';
import 'package:mime/mime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_selector/file_selector.dart';
import 'package:m3e_card_list/m3e_card_list.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/info_row.dart';
import 'package:files3/settings.dart';

abstract class ContextActionHandler {
  ContextActionHandler();

  void Function()? download();
  String Function()? saveAs(String? path);
  Future<String> Function()? delete(bool? yes);
  Future<String> Function()? deleteCache(bool? yes);
}

class FileContextActionHandler extends ContextActionHandler {
  final String file;
  final String? Function(String, int?) getLink;
  final Function(List<String>)? downloadFiles;
  final Function(String, String)? saveFile;
  final Future<void> Function(List<String>, List<String>)? moveFiles;
  final Function(List<String>)? deleteLocalFiles;
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
    required this.downloadFiles,
    required this.saveFile,
    required this.moveFiles,
    required this.deleteLocalFiles,
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

  bool get rootExists =>
      _rootExistsCache ??= p.isAbsolute(Main.pathFromKey(file));

  bool get downloaded => _downloadedCache ??=
      !p.isDir(file) && Main.remoteFileByKey(file)?.downloaded == true;

  bool get cacheExists => _cacheExistsCache ??=
      !p.isDir(file) && File(Main.cachePathFromKey(file)).existsSync();

  bool get active => _activeCache ??= Job.jobs.any(
    (job) => job.localFile.path == Main.pathFromKey(file),
  );

  bool get removable => _removableCache ??=
      downloaded && Main.backupModeFromKey(file) == BackupMode.upload;

  dynamic Function()? open() {
    final link = getLink(file, null);
    return downloaded
        ? () {
            OpenFile.open(Main.pathFromKey(file));
          }
        : cacheExists
        ? () {
            OpenFile.open(Main.cachePathFromKey(file));
          }
        : link == null
        ? null
        : () {
            launchUrl(Uri.parse(link));
          };
  }

  @override
  void Function()? download() {
    return !rootExists || downloaded || active || downloadFiles == null
        ? null
        : () {
            try {
              downloadFiles!([file]);
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
    return downloaded
        ? () {
            return XFile(Main.pathFromKey(file));
          }
        : cacheExists
        ? () {
            return XFile(Main.cachePathFromKey(file));
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
              final newKey = p.s3.join(
                p.s3.dirname(file),
                newName.replaceAll('/', '_').replaceAll('\\', '_'),
              );
              await moveFiles!([file], [newKey]);
              return 'Renamed ${p.s3.basename(file)} to $newName';
            } finally {
              invalidateCache();
            }
          };
  }

  Future<String> Function()? deleteUploaded(bool? yes) {
    return (yes ?? false) && deleteLocalFiles != null && removable
        ? () async {
            try {
              await deleteLocalFiles!([file]);
              return 'Deleted local copy of ${p.s3.basename(file)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  Future<String> Function()? deleteLocal(bool? yes) {
    return (yes ?? false) &&
            deleteLocalFiles != null &&
            !removable &&
            downloaded
        ? () async {
            try {
              await deleteLocalFiles!([file]);
              return 'Deleted local copy of ${p.s3.basename(file)}';
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
              await deleteFiles!([file]);
              return 'Deleted ${p.s3.basename(file)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache(bool? yes) {
    return (yes ?? false) && deleteCacheFile != null && cacheExists
        ? () async {
            try {
              await deleteCacheFile!(file);
              return 'Deleted cache of ${p.s3.basename(file)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }
}

class FilesContextActionHandler extends ContextActionHandler {
  final Iterable<String> files;
  final String? Function(String, int?) getLink;
  final Function(Iterable<String>)? downloadFiles;
  final Function(String, String)? saveFile;
  final Function(List<String>)? deleteLocalFiles;
  final Function(String)? deleteCacheFile;
  final Future<void> Function(Iterable<String>)? deleteFiles;
  List<bool>? _rootExistsCache;
  List<String>? _downloadedFilesCache;
  List<String>? _cachedFilesCache;
  List<String>? _activeFilesCache;
  List<String>? _removableFilesCache;

  FilesContextActionHandler({
    required this.files,
    required this.getLink,
    required this.downloadFiles,
    required this.saveFile,
    required this.deleteLocalFiles,
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

  List<bool> get rootExists => _rootExistsCache ??= List.unmodifiable(
    files.map((file) => p.isAbsolute(Main.pathFromKey(file))),
  );

  List<String> get downloadedFiles =>
      _downloadedFilesCache ??= List.unmodifiable(
        files.where(
          (f) => !p.isDir(f) && Main.remoteFileByKey(f)?.downloaded == true,
        ),
      );

  List<String> get cachedFiles => _cachedFilesCache ??= List.unmodifiable(
    files.where(
      (f) => !p.isDir(f) && File(Main.cachePathFromKey(f)).existsSync(),
    ),
  );

  List<String> get activeFiles => _activeFilesCache ??= List.unmodifiable(
    files.where(
      (f) => Job.jobs.any(
        (job) => !p.isDir(f) && job.localFile.path == Main.pathFromKey(f),
      ),
    ),
  );

  List<String> get removableFiles => _removableFilesCache ??= List.unmodifiable(
    files.where(
      (f) =>
          !p.isDir(f) &&
          Main.remoteFileByKey(f)?.downloaded == true &&
          Main.backupModeFromKey(f) == BackupMode.upload,
    ),
  );

  @override
  void Function()? download() {
    return downloadedFiles.length == files.length ||
            downloadedFiles.toSet().union(activeFiles.toSet()).length ==
                files.length ||
            downloadFiles == null
        ? null
        : () {
            try {
              downloadFiles!(
                files.where(
                  (file) => Main.remoteFileByKey(file)?.downloaded != true,
                ),
              );
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
                saveFile!(file, p.s3.join(path, p.s3.basename(file)));
              }
            } finally {
              invalidateCache();
            }
            return 'Saving ${files.length} files to $path';
          }
        : null;
  }

  List<XFile> Function()? getXFiles() {
    return downloadedFiles.isNotEmpty
        ? () {
            return files
                .where(
                  (file) =>
                      Main.remoteFileByKey(file)?.downloaded == true ||
                      File(Main.cachePathFromKey(file)).existsSync(),
                )
                .map((file) {
                  if (Main.remoteFileByKey(file)?.downloaded == true) {
                    return XFile(Main.pathFromKey(file));
                  } else if (File(Main.cachePathFromKey(file)).existsSync()) {
                    return XFile(Main.cachePathFromKey(file));
                  } else {
                    throw Exception('File $file does not exist locally');
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
    List<String> removableFiles,
    bool? yes,
  ) {
    return (yes ?? false) &&
            deleteLocalFiles != null &&
            removableFiles.isNotEmpty
        ? () async {
            try {
              await deleteLocalFiles!(removableFiles);
              return 'Deleted local copies of ${removableFiles.length} uploaded files';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  Future<String> Function()? deleteLocal(
    bool? yes,
    List<String> downloadedFiles,
  ) {
    return (yes ?? false) &&
            deleteLocalFiles != null &&
            downloadedFiles.isNotEmpty
        ? () async {
            try {
              await deleteLocalFiles!(downloadedFiles);
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
              await deleteFiles!(files);
              return 'Deleted ${files.length} files';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache(bool? yes) {
    final cacheFilesList = cachedFiles;
    return (yes ?? false) &&
            deleteCacheFile != null &&
            cacheFilesList.isNotEmpty
        ? () async {
            try {
              for (final file in cacheFilesList) {
                await deleteCacheFile!(file);
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
  final String file;
  final Function(List<String>)? downloadDirectories;
  final Function(String, String)? saveDirectory;
  final Future<void> Function(List<String>, List<String>)? moveDirectories;
  final Function(List<String>)? deleteLocalDirectories;
  final Function(String)? deleteCacheDirectory;
  final Future<void> Function(List<String>)? deleteDirectories;

  List<String>? _filesCache;
  bool? _rootExistsCache;
  bool? _localExistsCache;
  List<String>? _downloadedFilesCache;
  bool? _cacheExistCache;
  List<String>? _activeFilesCache;
  List<String>? _removableFilesCache;

  DirectoryContextActionHandler({
    required this.file,
    required this.downloadDirectories,
    required this.saveDirectory,
    required this.moveDirectories,
    required this.deleteLocalDirectories,
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

  List<String> get files => _filesCache ??= List.unmodifiable(
    Main.remoteFilesByDir(
      file,
      recursive: true,
    ).where((file) => !p.isDir(file.key)).map((f) => f.key),
  );

  bool get rootExists =>
      _rootExistsCache ??= p.context.isAbsolute(Main.pathFromKey(file));

  bool get localExists =>
      _localExistsCache ??= Directory(Main.pathFromKey(file)).existsSync();

  List<String> get downloadedFiles =>
      _downloadedFilesCache ??= List.unmodifiable(
        files.where((f) => Main.remoteFileByKey(f)?.downloaded == true),
      );

  bool get cacheExist =>
      _cacheExistCache ??= Directory(Main.cachePathFromKey(file)).existsSync();

  List<String> get activeFiles => _activeFilesCache ??= List.unmodifiable(
    files.where(
      (f) => Job.jobs.any(
        (job) => !p.isDir(f) && job.localFile.path == Main.pathFromKey(f),
      ),
    ),
  );

  List<String> get removableFiles => _removableFilesCache ??= List.unmodifiable(
    Main.remoteFilesByDir(file)
        .map((f) => f.key)
        .where(
          (f) =>
              !p.isDir(f) &&
              Main.remoteFileByKey(f)?.downloaded == true &&
              Main.backupModeFromKey(f) == BackupMode.upload,
        ),
  );

  void Function()? open() {
    return Directory(Main.pathFromKey(file)).existsSync()
        ? () {
            launchUrl(Uri.file(Main.pathFromKey(file)));
          }
        : null;
  }

  @override
  void Function()? download() {
    return !rootExists ||
            downloadedFiles.length == files.length ||
            downloadedFiles.toSet().union(activeFiles.toSet()).length ==
                files.length ||
            downloadDirectories == null
        ? null
        : () {
            try {
              downloadDirectories!([file]);
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
            return 'Saving ${p.s3.basename(file)} to $path';
          };
  }

  Future<String> Function()? rename(String newName) {
    return moveDirectories == null || p.s3.dirname(file).isEmpty
        ? null
        : () async {
            try {
              final key = file;
              final newKey = p.s3.asDir(
                p.s3.join(
                  p.s3.dirname(key),
                  newName.replaceAll('/', '_').replaceAll('\\', '_'),
                ),
              );
              await moveDirectories!([key], [newKey]);
              return 'Renamed ${p.s3.basename(file)} to $newName';
            } finally {
              invalidateCache();
            }
          };
  }

  Future<String> Function()? deleteUploaded(
    Iterable<String> removableFiles,
    bool? yes,
  ) {
    return (yes ?? false) &&
            deleteLocalDirectories != null &&
            removableFiles.isNotEmpty
        ? () async {
            try {
              await deleteLocalDirectories!(removableFiles.toList());
              return 'Deleted local copies of ${removableFiles.length} uploaded files in ${p.s3.basename(file)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  Future<String> Function()? deleteLocal(bool? yes) {
    return (yes ?? false) && deleteLocalDirectories != null && localExists
        ? () async {
            try {
              await deleteLocalDirectories!([file]);
              return 'Deleted local copy of ${p.s3.basename(file)}';
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
              deleteDirectories!([file]);
              return 'Deleted ${p.s3.basename(file)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache(bool? yes) {
    return (yes ?? false) && deleteCacheDirectory != null && cacheExist
        ? () async {
            try {
              deleteCacheDirectory!(file);
              return 'Deleted cache of ${p.s3.basename(file)}';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }
}

class DirectoriesContextActionHandler extends ContextActionHandler {
  final Iterable<String> directories;
  final Function(Iterable<String>)? downloadDirectories;
  final Function(String, String)? saveDirectory;
  final Function(List<String>)? deleteLocalDirectories;
  final Function(String)? deleteCacheDirectory;
  final Future<void> Function(Iterable<String>)? deleteDirectories;

  List<String>? _filesCache;
  List<bool>? _rootExistsCache;
  List<String>? _localDirectoriesCache;
  List<String>? _downloadedFilesCache;
  List<String>? _cachedDirectoriesCache;
  List<String>? _activeFilesCache;
  List<String>? _removableFilesCache;

  DirectoriesContextActionHandler({
    required this.directories,
    required this.downloadDirectories,
    required this.saveDirectory,
    required this.deleteLocalDirectories,
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

  List<String> get files => _filesCache ??= List.unmodifiable(() {
    List<String> files = [];
    for (final dir in directories) {
      files.addAll(
        Main.remoteFilesByDir(
          dir,
          recursive: true,
        ).where((f) => !p.isDir(f.key)).map((f) => f.key),
      );
    }
    return files;
  }());

  List<bool> get rootExists => _rootExistsCache ??= List.unmodifiable(
    directories.map((dir) => p.context.isAbsolute(Main.pathFromKey(dir))),
  );

  List<String> get localDirectories =>
      _localDirectoriesCache ??= List.unmodifiable(
        directories.where(
          (dir) => Directory(Main.pathFromKey(dir)).existsSync(),
        ),
      );

  List<String> get downloadedFiles =>
      _downloadedFilesCache ??= List.unmodifiable(
        files.where((f) => Main.remoteFileByKey(f)?.downloaded == true),
      );

  List<String> get cachedDirectories =>
      _cachedDirectoriesCache ??= List.unmodifiable(
        directories.where(
          (dir) => Directory(Main.cachePathFromKey(dir)).existsSync(),
        ),
      );

  List<String> get activeFiles => _activeFilesCache ??= List.unmodifiable(
    files.where(
      (f) => Job.jobs.any(
        (job) => !p.isDir(f) && job.localFile.path == Main.pathFromKey(f),
      ),
    ),
  );

  List<String> get removableFiles =>
      _removableFilesCache ??= List.unmodifiable(() {
        List<String> removable = [];
        for (final dir in directories) {
          removable.addAll(
            Main.remoteFilesByDir(dir, recursive: true)
                .where(
                  (f) =>
                      !p.isDir(f.key) &&
                      Main.remoteFileByKey(f.key)?.downloaded == true &&
                      Main.backupModeFromKey(f.key) == BackupMode.upload,
                )
                .map((f) => f.key),
          );
        }
        return removable;
      }());

  @override
  void Function()? download() {
    return rootExists.every((exists) => !exists) ||
            downloadedFiles.length == files.length ||
            downloadedFiles.toSet().union(activeFiles.toSet()).length ==
                files.length ||
            downloadDirectories == null
        ? null
        : () {
            try {
              downloadDirectories!(
                directories.where(
                  (dir) => Directory(Main.pathFromKey(dir)).existsSync(),
                ),
              );
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
                saveDirectory!(dir, p.s3.join(path, p.s3.basename(dir)));
              }
            } finally {
              invalidateCache();
            }
            return 'Saving ${directories.length} folders to $path';
          }
        : null;
  }

  Future<String> Function()? deleteUploaded(
    List<String> removableFiles,
    bool? yes,
  ) {
    return (yes ?? false) && deleteLocalDirectories != null
        ? () async {
            try {
              deleteLocalDirectories!(removableFiles);
              return 'Deleted local copies of ${removableFiles.length} uploaded files in ${directories.length} directories';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  Future<String> Function()? deleteLocal(bool? yes, List<String> localDirs) {
    return (yes ?? false) &&
            deleteLocalDirectories != null &&
            localDirs.isNotEmpty
        ? () async {
            try {
              deleteLocalDirectories!(localDirs);
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
              final keys = directories.map((dir) => dir);
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
    final cacheDirs = cachedDirectories;
    return (yes ?? false) &&
            deleteCacheDirectory != null &&
            cacheDirs.isNotEmpty
        ? () async {
            try {
              for (final dir in cacheDirs) {
                deleteCacheDirectory!(dir);
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
    final localExists = handler.downloaded;
    return FileContextOption(
      title: localExists
          ? 'Open with...'
          : openAction == null
          ? 'Link Unavailable'
          : 'Open Link',
      subtitle: Main.pathFromKey(handler.file),
      icon: Icons.open_in_new_rounded,
      action: openAction,
      popOnInvoked: false,
    );
  })();

  static FileContextOption download(FileContextActionHandler handler) => (() {
    final downloadAction = handler.download();
    final rootExists = handler.rootExists;
    final active = handler.active;
    final localPath = Main.pathFromKey(handler.file);
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
                suggestedName: p.s3.basename(handler.file),
                canCreateDirectories: true,
              );
            } catch (e) {
              saveLocation = await saveAsDialog(
                context,
                suggestedName: p.s3.basename(handler.file),
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
    Function(String)? cutKey,
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
    Function(String)? copyKey,
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
              p.s3.basename(handler.file),
            );
            if (newName != null &&
                newName.isNotEmpty &&
                newName != p.s3.basename(handler.file)) {
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
                    'Are you sure you want to delete the local copy of ${p.s3.basename(handler.file)}? This file has been uploaded and can be downloaded again later.',
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
                    'Are you sure you want to delete the local copy of ${p.s3.basename(handler.file)}? This action cannot be undone.',
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
                    'Are you sure you want to delete ${p.s3.basename(handler.file)} from your device and S3? This action cannot be undone.',
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
                    'Are you sure you want to delete the cached copy of ${p.s3.basename(handler.file)}? This action cannot be undone.',
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
    Function(String)? cutKey,
    Function(String)? copyKey,
  ) {
    return [
      [open(handler), download(handler), saveAs(handler, context)],
      [share(handler), copyLink(handler, context)],
      [cut(handler, cutKey), copy(handler, copyKey), rename(handler, context)],
      [
        if (handler.removable)
          deleteUploaded(handler, context)
        else if (handler.downloaded)
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
        final downloadedCount = handler.downloadedFiles.length;
        final totalCount = handler.files.length;
        final handledCount = handler.downloadedFiles
            .toSet()
            .union(handler.activeFiles.toSet())
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
        handler.downloadedFiles.length == handler.files.length;
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

  static FilesContextOption cut(Function(String?)? cutKey) =>
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

  static FilesContextOption copy(Function(String?)? copyKey) =>
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
    List<String> removableFiles,
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
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: removableFiles.isEmpty
                    //       ? const Text('No files to delete')
                    //       : ListView.builder(
                    //           shrinkWrap: true,
                    //           itemCount: removableFiles.length,
                    //           itemBuilder: (context, index) {
                    //             final file = removableFiles[index];
                    //             return SingleChildScrollView(
                    //               scrollDirection: Axis.horizontal,
                    //               child: Text(Main.pathFromKey(file)),
                    //             );
                    //           },
                    //         ),
                    // ),
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
    List<String> downloadedFiles,
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
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: downloadedFiles.isEmpty
                    //       ? const Text('No files to delete')
                    //       : ListView.builder(
                    //           shrinkWrap: true,
                    //           itemCount: downloadedFiles.length,
                    //           itemBuilder: (context, index) {
                    //             final file = downloadedFiles[index];
                    //             return SingleChildScrollView(
                    //               scrollDirection: Axis.horizontal,
                    //               child: Text(Main.pathFromKey(file)),
                    //             );
                    //           },
                    //         ),
                    // ),
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
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: handler.files.isEmpty
                    //       ? const Text('No files to delete')
                    //       : ListView.builder(
                    //           shrinkWrap: true,
                    //           itemCount: handler.files.length,
                    //           itemBuilder: (context, index) {
                    //             final file = handler.files[index];
                    //             return SingleChildScrollView(
                    //               scrollDirection: Axis.horizontal,
                    //               child: Text(Main.pathFromKey(file)),
                    //             );
                    //           },
                    //         ),
                    // ),
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
            final cacheFiles = handler.cachedFiles;
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
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: cacheFiles.isEmpty
                    //       ? const Text('No cached files to delete')
                    //       : ListView.builder(
                    //           shrinkWrap: true,
                    //           itemCount: cacheFiles.length,
                    //           itemBuilder: (context, index) {
                    //             final file = cacheFiles[index];
                    //             return SingleChildScrollView(
                    //               scrollDirection: Axis.horizontal,
                    //               child: Text(Main.pathFromKey(file)),
                    //             );
                    //           },
                    //         ),
                    // ),
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
              showSnackBar(const SnackBar(content: Text(' copies deleted')));
            }
          },
  );

  static List<List<FilesContextOption>> allOptions(
    BuildContext context,
    FilesContextActionHandler handler,
    Function(String?)? cutKey,
    Function(String?)? copyKey,
    Function() clearSelection,
  ) {
    return [
      [downloadAll(handler), saveAllTo(context, handler)],
      [shareAll(handler), copyAllLinks(context, handler)],
      [cut(cutKey), copy(copyKey)],
      [
        if (handler.removableFiles.isNotEmpty)
          deleteUploaded(context, handler, handler.removableFiles),
        if (handler.downloadedFiles.isNotEmpty)
          deleteLocalAll(context, handler, handler.downloadedFiles),
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
              : Main.pathFromKey(handler.file),
          icon: openAction == null ? Icons.open_in_new_off : Icons.open_in_new,
          action: openAction,
        );
      })();

  static DirectoryContextOption download(
    DirectoryContextActionHandler handler,
  ) => (() {
    final downloadAction = handler.download();
    final downloadedCount = handler.downloadedFiles.length;
    final totalCount = handler.files.length;
    final handledCount = handler.downloadedFiles
        .toSet()
        .union(handler.activeFiles.toSet())
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
                  : p.s3.join(directory, p.s3.basename(handler.file)),
            );
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(handle())));
            }
          },
  );

  static DirectoryContextOption cut(
    DirectoryContextActionHandler handler,
    Function(String)? cutKey,
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
    Function(String)? copyKey,
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
              p.s3.basenameWithoutExtension(handler.file),
            );
            if (newName != null &&
                newName.isNotEmpty &&
                newName != p.s3.basename(handler.file)) {
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
    Iterable<String> removableFiles,
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
                      'Are you sure you want to delete the local copies of ${removableFiles.length} uploaded files in ${p.s3.basename(handler.file)}? Only uploaded files will be deleted from the device and can be downloaded again later.',
                    ),
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: SingleChildScrollView(
                    //     child: SingleChildScrollView(
                    //       scrollDirection: Axis.horizontal,
                    //       child: Column(
                    //         crossAxisAlignment: CrossAxisAlignment.start,
                    //         children: [
                    //           for (final file in removableFiles)
                    //             Text(Main.pathFromKey(file)),
                    //           if (removableFiles.isEmpty)
                    //             const Text('No files to delete'),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: handler.removableFiles.isNotEmpty
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
                      handler.removableFiles,
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
                  'Are you sure you want to delete the local copy of ${p.s3.basename(handler.file)}? This action cannot be undone.',
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
                  'Are you sure you want to delete ${p.s3.basename(handler.file)} from your device and S3? This action cannot be undone.',
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
                  'Are you sure you want to delete the cached copy of ${p.s3.basename(handler.file)}? This action cannot be undone.',
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
    Function(String)? cutKey,
    Function(String)? copyKey,
  ) {
    return [
      [open(handler), download(handler), saveTo(handler, context)],
      [
        cut(handler, cutKey),
        copy(handler, copyKey),
        if (handler.rename('any name') != null) rename(context, handler),
      ],
      [
        if (handler.removableFiles.isNotEmpty)
          deleteUploaded(context, handler, handler.removableFiles),
        if (handler.localExists) deleteLocal(context, handler),
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
    final downloadedCount = handler.downloadedFiles.length;
    final totalCount = handler.files.length;
    final handledCount = handler.downloadedFiles
        .toSet()
        .union(handler.activeFiles.toSet())
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

  static DirectoriesContextOption cut(Function(String?)? cutKey) =>
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

  static DirectoriesContextOption copy(Function(String?)? copyKey) =>
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
    List<String> removableFiles,
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
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: SingleChildScrollView(
                    //     child: SingleChildScrollView(
                    //       scrollDirection: Axis.horizontal,
                    //       child: Column(
                    //         crossAxisAlignment: CrossAxisAlignment.start,
                    //         children: [
                    //           for (final file in removableFiles)
                    //             Text(Main.pathFromKey(file)),
                    //           if (removableFiles.isEmpty)
                    //             const Text('No files to delete'),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: handler.removableFiles.isNotEmpty
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
                      handler.removableFiles,
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
    List<String> localDirectories,
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
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: SingleChildScrollView(
                    //     child: SingleChildScrollView(
                    //       scrollDirection: Axis.horizontal,
                    //       child: Column(
                    //         crossAxisAlignment: CrossAxisAlignment.start,
                    //         children: [
                    //           for (final directory in localDirectories)
                    //             Text(Main.pathFromKey(directory) ?? directory),
                    //           if (localDirectories.isEmpty)
                    //             const Text('No directories to delete'),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
                    // ),
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
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: SingleChildScrollView(
                    //     child: SingleChildScrollView(
                    //       scrollDirection: Axis.horizontal,
                    //       child: Column(
                    //         crossAxisAlignment: CrossAxisAlignment.start,
                    //         children: [
                    //           for (final directory in handler.directories)
                    //             Text(Main.pathFromKey(directory) ?? directory),
                    //           if (handler.directories.isEmpty)
                    //             const Text('No directories to delete'),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
                    // ),
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
            final cachedDirectories = handler.cachedDirectories;
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
                    // Container(
                    //   height: 200,
                    //   padding: EdgeInsets.only(top: 16),
                    //   child: SingleChildScrollView(
                    //     child: SingleChildScrollView(
                    //       scrollDirection: Axis.horizontal,
                    //       child: Column(
                    //         crossAxisAlignment: CrossAxisAlignment.start,
                    //         children: [
                    //           for (final directory in cachedDirectories)
                    //             Text(Main.pathFromKey(directory) ?? directory),
                    //           if (cachedDirectories.isEmpty)
                    //             const Text('No cached directories to delete'),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
                    // ),
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
              showSnackBar(SnackBar(content: Text(' copies deleted')));
            }
          },
  );

  static List<List<DirectoriesContextOption>> allOptions(
    BuildContext context,
    DirectoriesContextActionHandler handler,
    Function(String?)? cutKey,
    Function(String?)? copyKey,
    Function() clearSelection,
  ) {
    return [
      [downloadAll(handler), saveAllTo(handler, context)],
      [cut(cutKey), copy(copyKey)],
      [
        if (handler.removableFiles.isNotEmpty)
          deleteUploaded(handler, context, handler.removableFiles),
        if (handler.localDirectories.isNotEmpty)
          deleteLocal(handler, context, handler.localDirectories),
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
        directoriesHandler.downloadedFiles.length ==
            directoriesHandler.files.length &&
        filesHandler.downloadedFiles.length == filesHandler.files.length;
    final allItemsHandled =
        <String>{
          ...directoriesHandler.downloadedFiles,
          ...directoriesHandler.activeFiles,
          ...filesHandler.downloadedFiles,
          ...filesHandler.activeFiles,
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
        final String Function()? handle = handler.saveAs(directory);
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

  static BulkContextOption cut(Function(String?)? cutKey) => BulkContextOption(
    title: 'Move To...',
    icon: Icons.cut_rounded,
    action: cutKey == null
        ? null
        : (BuildContext context) {
            cutKey(null);
          },
    popOnInvoked: true,
  );

  static BulkContextOption copy(Function(String?)? copyKey) =>
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
        ...directoriesHandler.removableFiles,
        ...filesHandler.removableFiles,
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
              // Container(
              //   height: 200,
              //   padding: const EdgeInsets.only(top: 16),
              //   child: removableFiles.isEmpty
              //       ? const Text('No files to delete')
              //       : ListView.builder(
              //           shrinkWrap: true,
              //           itemCount: removableFiles.length,
              //           itemBuilder: (context, index) {
              //             final file = removableFiles[index];
              //             return SingleChildScrollView(
              //               scrollDirection: Axis.horizontal,
              //               child: Text(Main.pathFromKey(file)),
              //             );
              //           },
              //         ),
              // ),
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
            .deleteUploaded(directoriesHandler.removableFiles, true)
            ?.call();
        await filesHandler
            .deleteUploaded(filesHandler.removableFiles, true)
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
      final localDirectories = directoriesHandler.localDirectories;
      final downloadedFiles = filesHandler.downloadedFiles;
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
              // Container(
              //   height: 200,
              //   padding: const EdgeInsets.only(top: 16),
              //   child: localDirectories.isEmpty && downloadedFiles.isEmpty
              //       ? const Text('No items to delete')
              //       : ListView.builder(
              //           shrinkWrap: true,
              //           itemCount:
              //               localDirectories.length + downloadedFiles.length,
              //           itemBuilder: (context, index) {
              //             final file = index < localDirectories.length
              //                 ? localDirectories[index]
              //                 : downloadedFiles[index -
              //                       localDirectories.length];
              //             return SingleChildScrollView(
              //               scrollDirection: Axis.horizontal,
              //               child: Text(Main.pathFromKey(file)),
              //             );
              //           },
              //         ),
              // ),
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
            .deleteLocal(true, directoriesHandler.localDirectories)!
            .call();
        await filesHandler
            .deleteLocal(true, filesHandler.downloadedFiles)!
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
                  // Container(
                  //   height: 200,
                  //   padding: const EdgeInsets.only(top: 16),
                  //   child: directories.isEmpty && files.isEmpty
                  //       ? const Text('No items to delete')
                  //       : ListView.builder(
                  //           shrinkWrap: true,
                  //           itemCount: directories.length + files.length,
                  //           itemBuilder: (context, index) {
                  //             final file = index < directories.length
                  //                 ? directories[index]
                  //                 : files[index - directories.length];
                  //             return SingleChildScrollView(
                  //               scrollDirection: Axis.horizontal,
                  //               child: Text(Main.pathFromKey(file)),
                  //             );
                  //           },
                  //         ),
                  // ),
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
            final cacheFiles = filesHandler.cachedFiles;
            final cachedDirectories = directoriesHandler.cachedDirectories;
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
                    // Container(
                    //   height: 200,
                    //   padding: const EdgeInsets.only(top: 16),
                    //   child: cachedDirectories.isEmpty && cacheFiles.isEmpty
                    //       ? const Text('Nothing to delete')
                    //       : ListView.builder(
                    //           shrinkWrap: true,
                    //           itemCount:
                    //               cachedDirectories.length + cacheFiles.length,
                    //           itemBuilder: (context, index) {
                    //             final file = index < cachedDirectories.length
                    //                 ? cachedDirectories[index]
                    //                 : cacheFiles[index -
                    //                       cachedDirectories.length];
                    //             return SingleChildScrollView(
                    //               scrollDirection: Axis.horizontal,
                    //               child: Text(file),
                    //             );
                    //           },
                    //         ),
                    // ),
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
              showSnackBar(SnackBar(content: Text(' copies deleted')));
            }
          },
  );

  static List<List<BulkContextOption>> allOptions(
    Function(String?)? cutKey,
    Function(String?)? copyKey,
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
        if (directoriesHandler.removableFiles.isNotEmpty ||
            filesHandler.removableFiles.isNotEmpty)
          deleteUploaded(directoriesHandler, filesHandler, context),
        if (directoriesHandler.localDirectories.isNotEmpty ||
            filesHandler.downloadedFiles.isNotEmpty)
          deleteLocalAll(directoriesHandler, filesHandler, context),
        deleteAll(directoriesHandler, filesHandler, context, clearSelection),
        deleteCache(directoriesHandler, filesHandler, context),
      ],
    ];
  }
}

Widget buildFileContextMenu(
  BuildContext context,
  String item,
  bool allowModify,
  String? Function(String, int?) getLink,
  Function(List<String>)? downloadFiles,
  Function(String, String)? saveFile,
  Function(String)? cut,
  Function(String)? copy,
  Future<void> Function(List<String>, List<String>)? moveFiles,
  Function(List<String>)? deleteLocals,
  Function(String)? deleteCache,
  Future<void> Function(List<String>)? deleteFiles,
  void Function()? onInvoked,
) {
  String? mediaType = lookupMimeType(item);
  return FutureBuilder(
    future: () async {
      FileContextActionHandler handler = FileContextActionHandler(
        file: item,
        getLink: getLink,
        downloadFiles: downloadFiles,
        saveFile: saveFile,
        moveFiles: allowModify ? moveFiles : null,
        deleteLocalFiles: deleteLocals,
        deleteCacheFile: deleteCache,
        deleteFiles: allowModify ? deleteFiles : null,
      );
      return (
        handler: handler,
        options: FileContextOption.allOptions(
          context,
          handler,
          allowModify ? cut : null,
          allowModify ? copy : null,
        ),
      );
    }(),
    builder: (context, snapshot) => Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: M3ECardColumn(
            outerRadius: 18,
            innerRadius: 4,
            gap: 3,
            padding: EdgeInsets.zero,
            color: Colors.transparent,
            children: [
              ListTile(
                visualDensity: VisualDensity.comfortable,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                leading: Icon(mediaTypeIcon(mediaType)),
                title: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(p.s3.basename(item)),
                ),
                subtitle: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: InfoRow(
                    remoteKey: item,
                    uiConfig: UiConfig(
                      showTime: true,
                      showSize: true,
                      showDownloadStatus: false,
                      showType: true,
                    ),
                  ),
                ),
              ),
              ListTile(
                visualDensity: VisualDensity.comfortable,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                leading: Icon(Icons.info_outline_rounded),
                title: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(item),
                ),
                subtitle: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text('MD5: ${Main.remoteFileByKey(item)?.etag}'),
                ),
              ),
            ],
          ),
        ),
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(),
          ),
        if (snapshot.hasData)
          ...(snapshot.data?.options ?? []).map(
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
                                snapshot.data!.handler.invalidateCache();
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
                              snapshot.data!.handler.invalidateCache();
                              onInvoked?.call();
                            },
                      enabled: option.action != null,
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    ),
  );
}

Widget buildFilesContextMenu(
  BuildContext context,
  Iterable<String> items,
  String? Function(String, int?) getLink,
  Function(Iterable<String>)? downloadFiles,
  Function(String, String)? saveFile,
  Function(String?)? cut,
  Function(String?)? copy,
  Function(List<String>)? deleteLocals,
  Function(String)? deleteCache,
  Future<void> Function(Iterable<String>)? deleteFiles,
  Function() clearSelection,
  void Function()? onInvoked,
) {
  return FutureBuilder(
    future: () async {
      FilesContextActionHandler handler = FilesContextActionHandler(
        files: items,
        getLink: getLink,
        downloadFiles: downloadFiles,
        saveFile: saveFile,
        deleteLocalFiles: deleteLocals,
        deleteCacheFile: deleteCache,
        deleteFiles: deleteFiles,
      );
      return (
        handler: handler,
        options: FilesContextOption.allOptions(
          context,
          handler,
          cut,
          copy,
          clearSelection,
        ),
      );
    }(),
    builder: (context, snapshot) => Column(
      mainAxisSize: MainAxisSize.min,
      children:
          snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData
          ? [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            ]
          : (snapshot.data?.options ?? [])
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
                                      snapshot.data?.handler.invalidateCache();
                                      onInvoked?.call();
                                    },
                                    icon: Icon(option.secondaryIcon),
                                  )
                                : null,
                            onTap: option.action != null
                                ? () async {
                                    if (option.popOnInvoked) {
                                      globalNavigator?.pop();
                                    }
                                    await option.action!();
                                    snapshot.data?.handler.invalidateCache();
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
    ),
  );
}

Widget buildDirectoryContextMenu(
  BuildContext context,
  String file,
  bool allowModify,
  Function(List<String>)? downloadDirectories,
  Function(String, String)? saveDirectory,
  Function(String)? cut,
  Function(String)? copy,
  Future<void> Function(List<String>, List<String>)? moveDirectories,
  Function(List<String>)? deleteLocals,
  Function(String)? deleteCache,
  Future<void> Function(List<String>)? deleteDirectories,
  void Function()? onInvoked,
) {
  return FutureBuilder(
    future: () async {
      DirectoryContextActionHandler handler = DirectoryContextActionHandler(
        file: file,
        downloadDirectories: downloadDirectories,
        saveDirectory: saveDirectory,
        moveDirectories: allowModify ? moveDirectories : null,
        deleteLocalDirectories: deleteLocals,
        deleteCacheDirectory: deleteCache,
        deleteDirectories: allowModify ? deleteDirectories : null,
      );
      return (
        handler: handler,
        options: DirectoryContextOption.allOptions(
          context,
          handler,
          allowModify ? cut : null,
          allowModify ? copy : null,
        ),
      );
    }(),
    builder: (context, snapshot) => Column(
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
                child: Text(p.s3.basename(file)),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: InfoRow(
                      remoteKey: file,
                      uiConfig: UiConfig(
                        showTime: true,
                        showSize: true,
                        showDownloadStatus: false,
                        showContent: true,
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(file),
                  ),
                ],
              ),
              onTap:
                  Main.profileFromKey(file) == null ||
                      p.s3.split(file).length != 1
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              S3ConfigPage(profile: Main.profileFromKey(file)!),
                        ),
                      );
                    },
            ),
          ),
        ),
        if (p.s3.split(file).length == 1)
          ProfileBackupConfig(
            initialBackupMode: Main.backupModeFromKey(file),
            initialLocalDir: Main.pathFromKey(file),
            onBackupModeChanged: (mode) {
              ConfigManager.setBackupMode(file, mode);
              Main.listDirectories();
              globalNavigator!.pop();
            },
            onLocalDirChanged: (localDir) {
              ConfigManager.setLocalDir(file, localDir);
              Main.listDirectories();
              globalNavigator!.pop();
            },
            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            outerRadius: 14,
            visualDensity: VisualDensity.comfortable,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          ),
        if (snapshot.hasData)
          ...(snapshot.data?.options ?? []).map(
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
                              snapshot.data?.handler.invalidateCache();
                              onInvoked?.call();
                            }
                          : null,
                      enabled: option.action != null,
                    ),
                  )
                  .toList(),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(),
          ),
      ],
    ),
  );
}

Widget buildDirectoriesContextMenu(
  BuildContext context,
  Iterable<String> dirs,
  Function(Iterable<String>)? downloadDirectories,
  Function(String, String)? saveDirectory,
  Function(String?)? cut,
  Function(String?)? copy,
  Function(List<String>)? deleteLocals,
  Function(String)? deleteCache,
  Future<void> Function(Iterable<String>)? deleteDirectories,
  Function() clearSelection,
  void Function()? onInvoked,
) {
  return FutureBuilder(
    future: () async {
      DirectoriesContextActionHandler handler = DirectoriesContextActionHandler(
        directories: dirs,
        downloadDirectories: downloadDirectories,
        saveDirectory: saveDirectory,
        deleteLocalDirectories: deleteLocals,
        deleteCacheDirectory: deleteCache,
        deleteDirectories: deleteDirectories,
      );
      return (
        handler: handler,
        options: DirectoriesContextOption.allOptions(
          context,
          handler,
          cut,
          copy,
          clearSelection,
        ),
      );
    }(),
    builder: (context, snapshot) => Column(
      children:
          snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData
          ? [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            ]
          : (snapshot.data?.options ?? [])
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
                                    await option.action!();
                                    snapshot.data?.handler.invalidateCache();
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
    ),
  );
}

Widget buildBulkContextMenu(
  BuildContext context,
  Iterable<String> items,
  String? Function(String, int?) getLink,
  Function(Iterable<String>)? downloadFiles,
  Function(Iterable<String>)? downloadDirectories,
  Function(String, String)? saveFile,
  Function(String, String)? saveDirectory,
  Function(String?)? cut,
  Function(String?)? copy,
  Function(List<String>)? deleteLocals,
  Function(String)? deleteCache,
  Future<void> Function(Iterable<String>)? deleteFiles,
  Future<void> Function(Iterable<String>)? deleteDirectories,
  Function() clearSelection,
  void Function()? onInvoked,
) {
  if (!items.any((item) => p.isDir(item))) {
    return buildFilesContextMenu(
      context,
      items,
      getLink,
      downloadFiles,
      saveFile,
      cut,
      copy,
      deleteLocals,
      deleteCache,
      deleteFiles,
      clearSelection,
      onInvoked,
    );
  } else if (items.every((item) => p.isDir(item))) {
    return buildDirectoriesContextMenu(
      context,
      items,
      downloadDirectories,
      saveDirectory,
      cut,
      copy,
      deleteLocals,
      deleteCache,
      deleteDirectories,
      clearSelection,
      onInvoked,
    );
  }
  return FutureBuilder(
    future: () async {
      DirectoriesContextActionHandler dirHandler =
          DirectoriesContextActionHandler(
            directories: items.where((item) => p.isDir(item)),
            downloadDirectories: downloadDirectories,
            saveDirectory: saveDirectory,
            deleteLocalDirectories: deleteLocals,
            deleteCacheDirectory: deleteCache,
            deleteDirectories: deleteDirectories,
          );
      FilesContextActionHandler fileHandler = FilesContextActionHandler(
        files: items.where((item) => !p.isDir(item)),
        getLink: getLink,
        downloadFiles: downloadFiles,
        saveFile: saveFile,
        deleteLocalFiles: deleteLocals,
        deleteCacheFile: deleteCache,
        deleteFiles: deleteFiles,
      );
      return (
        dirHandler: dirHandler,
        fileHandler: fileHandler,
        options: BulkContextOption.allOptions(
          cut,
          copy,
          dirHandler,
          fileHandler,
          context,
          clearSelection,
        ),
      );
    }(),
    builder: (context, snapshot) => Column(
      children:
          snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData
          ? [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            ]
          : (snapshot.data?.options ?? [])
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
                                    snapshot.data?.dirHandler.invalidateCache();
                                    snapshot.data?.fileHandler
                                        .invalidateCache();
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
    ),
  );
}

Widget buildExternalFilesContextMenu(
  BuildContext context,
  String? path,
  String? url,
  String? key,
  void Function(List<String>) upload,
) {
  assert(
    path != null || url != null || key != null,
    'At least one of path, url, or key must be provided',
  );
  return Column(
    children: path != null && File(path).existsSync()
        ? [
            ListTile(
              visualDensity: VisualDensity.comfortable,
              leading: Icon(mediaTypeIcon(lookupMimeType(path))),
              title: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(path),
              ),
              subtitle: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(bytesToReadable(File(path).lengthSync())),
                    const SizedBox(width: 8),
                    Text(p.context.extension(path)),
                  ],
                ),
              ),
            ),
            ListTile(
              visualDensity: VisualDensity.comfortable,
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open with...'),
              subtitle: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(path),
              ),
              onTap: () {
                OpenFile.open(path);
              },
            ),
            ListTile(
              visualDensity: VisualDensity.comfortable,
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                SharePlus.instance.share(
                  ShareParams(files: <XFile>[XFile(path)]),
                );
              },
            ),
            ListTile(
              visualDensity: VisualDensity.comfortable,
              leading: const Icon(Icons.upload),
              title: const Text('Upload'),
              onTap: () => upload([path]),
            ),
          ]
        : [
            ListTile(
              visualDensity: VisualDensity.comfortable,
              leading: const Icon(Icons.info_outline),
              title: const Text('Loading...'),
              subtitle: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(path ?? url ?? key!),
              ),
            ),
          ],
  );
}
