import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
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
import 'package:files3/models/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/info_row.dart';
import 'package:files3/settings.dart';

sealed class ContextActionHandlerDelegate {
  final Iterable<String>? files;
  final String? Function(String, int?) getLink;
  final Future<void> Function(Iterable<String>)? downloadFiles;
  final Future<void> Function(String, String)? saveFile;
  final Future<void> Function(Iterable<String>)? deleteLocalFiles;
  final Future<void> Function(String)? deleteCacheFile;
  final Future<void> Function(Iterable<String>)? deleteFiles;
  List<String>? _downloadedFilesCache;
  List<String>? _cachedFilesCache;
  List<String>? _activeFilesCache;
  List<String>? _removableFilesCache;
  bool initialized = false;

  ContextActionHandlerDelegate({
    this.files = const [],
    required this.getLink,
    this.downloadFiles,
    this.saveFile,
    this.deleteLocalFiles,
    this.deleteCacheFile,
    this.deleteFiles,
  });

  /// files must be initialized before calling this method, and should not be changed after calling this method.
  Future<void> init() async {
    final remoteFilesDownloaded = await Future.wait(
      files!.map((f) async {
        final remoteFile = await RemoteFile.getByKey(f);
        return (
          key: remoteFile?.key,
          downloaded: await remoteFile?.getDownloaded(refresh: true),
        );
      }),
    );

    for (final file in remoteFilesDownloaded) {
      _downloadedFilesCache ??= [];
      if (file.downloaded == true) {
        _downloadedFilesCache!.add(file.key!);
      }
    }

    final cachedFilesList = await Future.wait(
      files!.map((f) async {
        final cached = await File(Main.cachePathFromKey(f)).exists();
        return (key: f, cached: cached);
      }),
    );
    for (final file in cachedFilesList) {
      _cachedFilesCache ??= [];
      if (file.cached) {
        _cachedFilesCache!.add(file.key);
      }
    }

    _activeFilesCache = List.unmodifiable(
      files!.where((f) {
        final status = Job
            .allMap[(remoteKey: f, localPath: Main.pathFromKey(f))]
            ?.status
            .value;
        if (status != JobStatus.completed && status != null) {
          return true;
        }
        return false;
      }),
    );

    _removableFilesCache ??= List.unmodifiable(
      downloadedFiles!.where(
        (f) => Main.backupModeFromKey(f) == BackupMode.upload,
      ),
    );

    initialized = true;
  }

  /// Call after any overrides
  void invalidateCache() {
    _downloadedFilesCache = null;
    _cachedFilesCache = null;
    _activeFilesCache = null;
    _removableFilesCache = null;
    initialized = false;
    init();
  }

  List<String>? get downloadedFiles => _downloadedFilesCache;

  List<String>? get cachedFiles => List.unmodifiable(_cachedFilesCache ?? []);

  List<String>? get activeFiles => _activeFilesCache;

  List<String>? get removableFiles => _removableFilesCache;

  String Function()? getLinksToCopy(int? seconds) {
    return files?.isNotEmpty == true
        ? () {
            final buffer = StringBuffer();
            for (final file in files!) {
              buffer.writeln(getLink(file, seconds));
              buffer.writeln();
            }
            return buffer.toString();
          }
        : null;
  }

  Future<void> Function()? download();

  Future<String> Function()? saveAs(String? path);

  Future<String> Function()? deleteUploaded(Iterable<String> removableFiles) {
    return initialized && deleteLocalFiles != null && removableFiles.isNotEmpty
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

  Future<String> Function()? deleteLocal(List<String> downloadedFiles);

  Future<String> Function()? delete();

  Future<String> Function()? deleteCache();
}

sealed class FileContextActionHandlerDelegate
    extends ContextActionHandlerDelegate {
  List<bool>? _rootExistsCache;

  FileContextActionHandlerDelegate({
    super.files = const [],
    required super.getLink,
    super.downloadFiles,
    super.saveFile,
    super.deleteLocalFiles,
    super.deleteCacheFile,
    super.deleteFiles,
  });

  @override
  Future<void> init() async {
    await super.init();
    _rootExistsCache = List.unmodifiable(
      files!.map((file) => p.isAbsolute(Main.pathFromKey(file))),
    );
  }

  @override
  void invalidateCache() {
    _rootExistsCache = null;
    super.invalidateCache();
  }

  List<bool>? get rootExists => _rootExistsCache;

  @override
  Future<void> Function()? download() {
    return !initialized ||
            (rootExists!.every((exists) => !exists) ||
                downloadedFiles!.length == files!.length ||
                downloadedFiles!.toSet().union(activeFiles!.toSet()).length ==
                    files!.length ||
                downloadFiles == null)
        ? null
        : () async {
            try {
              final List<String> notDownloaded = await Future.wait(
                files!.map((file) async {
                  final remoteFile = await RemoteFile.getByKey(file);
                  final downloaded = await remoteFile?.getDownloaded(
                    refresh: true,
                  );
                  if (downloaded != true) {
                    return file;
                  }
                  return null;
                }),
              ).then((list) => list.whereType<String>().toList());
              await downloadFiles!(notDownloaded);
            } finally {
              invalidateCache();
            }
          };
  }

  @override
  Future<String> Function()? saveAs(String? path) {
    return path != null && saveFile != null
        ? () async {
            try {
              for (final file in files!) {
                saveFile!(file, p.s3.join(path, p.s3.basename(file)));
              }
            } finally {
              invalidateCache();
            }
            return 'Saving ${files!.length} files to $path';
          }
        : null;
  }

  @override
  Future<String> Function()? deleteLocal(List<String> downloadedFiles) {
    return initialized && deleteLocalFiles != null && downloadedFiles.isNotEmpty
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
  Future<String> Function()? delete() {
    return initialized && deleteFiles != null
        ? () async {
            try {
              await deleteFiles!(files!);
              return 'Deleted ${files!.length} files';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache() {
    final cacheFilesList = cachedFiles;
    return initialized && deleteCacheFile != null && cacheFilesList!.isNotEmpty
        ? () async {
            try {
              for (final file in cacheFilesList) {
                await deleteCacheFile!(file);
              }
              return 'Deleted cached copies of ${cacheFilesList.length} files';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }
}

class FileContextActionHandler extends FileContextActionHandlerDelegate {
  final Future<void> Function(List<String>, List<String>)? moveFiles;

  FileContextActionHandler({
    required String file,
    required super.getLink,
    super.downloadFiles,
    super.saveFile,
    required this.moveFiles,
    super.deleteLocalFiles,
    super.deleteCacheFile,
    super.deleteFiles,
  }) : super(files: [file]);

  String? get file => files?.firstOrNull;

  dynamic Function()? open(BuildContext context) {
    return super.files?.isNotEmpty == true
        ? () async {
            final files = await keysToPathWithProgressDialog(
              context,
              keys: super.files!,
              title: 'Preparing file to open...',
            );
            if (files.isNotEmpty) {
              OpenFile.open(files.first);
            }
          }
        : null;
  }

  Future<String> Function()? rename(String newName) {
    return moveFiles == null || file == null
        ? null
        : () async {
            try {
              final newKey = p.s3.join(
                p.s3.dirname(file!),
                newName.replaceAll('/', '_').replaceAll('\\', '_'),
              );
              await moveFiles!([file!], [newKey]);
              return 'Renamed ${p.s3.basename(file!)} to $newName';
            } finally {
              invalidateCache();
            }
          };
  }
}

class FilesContextActionHandler extends FileContextActionHandlerDelegate {
  FilesContextActionHandler({
    required super.files,
    required super.getLink,
    super.downloadFiles,
    super.saveFile,
    super.deleteLocalFiles,
    super.deleteCacheFile,
    super.deleteFiles,
  });
}

sealed class DirectoryContextActionHandlerDelegate
    extends ContextActionHandlerDelegate {
  final Iterable<String> directories;
  final Future<void> Function(Iterable<String>)? downloadDirectories;
  final Future<void> Function(String, String)? saveDirectory;

  DirectoryContextActionHandlerDelegate({
    required this.directories,
    required super.getLink,
    this.downloadDirectories,
    this.saveDirectory,
    super.deleteLocalFiles,
    super.deleteCacheFile,
    super.deleteFiles,
  });

  List<String>? _filesCache;
  List<String>? _localDirectoriesCache;
  List<bool>? _dirRootsExistsCache;
  List<String>? _cachedDirectoriesCache;

  @override
  Future<void> init() async {
    _filesCache = (await RemoteFile.getChildrenByKeys<String>(
      directories,
      recursive: true,
      includeDirs: false,
      includeFiles: true,
    )).toList();

    _dirRootsExistsCache = List.unmodifiable(
      directories.map((dir) => p.context.isAbsolute(Main.pathFromKey(dir))),
    );

    _localDirectoriesCache = List.unmodifiable(
      directories.where((dir) => Directory(Main.pathFromKey(dir)).existsSync()),
    );

    _cachedDirectoriesCache = List.unmodifiable(
      directories.where(
        (dir) => Directory(Main.cachePathFromKey(dir)).existsSync(),
      ),
    );

    await super.init();
  }

  @override
  void invalidateCache() {
    super.invalidateCache();
    _filesCache = null;
    _localDirectoriesCache = null;
    _dirRootsExistsCache = null;
    _cachedDirectoriesCache = null;
  }

  @override
  List<String>? get files => _filesCache;

  List<bool>? get dirRootExists => _dirRootsExistsCache;

  List<String>? get localDirectories => _localDirectoriesCache;

  List<String>? get cachedDirectories => _cachedDirectoriesCache;

  @override
  Future<void> Function()? download() {
    return !initialized ||
            (dirRootExists!.every((exists) => !exists) ||
                downloadedFiles!.length == files!.length ||
                downloadedFiles!.toSet().union(activeFiles!.toSet()).length ==
                    files!.length ||
                downloadDirectories == null)
        ? null
        : () async {
            try {
              await downloadDirectories!(directories);
            } finally {
              invalidateCache();
            }
          };
  }

  @override
  Future<String> Function()? saveAs(String? path) {
    return path != null && saveDirectory != null
        ? () async {
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

  @override
  Future<String> Function()? deleteLocal(List<String> localDirs) {
    return initialized && deleteLocalFiles != null && localDirs.isNotEmpty
        ? () async {
            try {
              await deleteLocalFiles!(localDirs);
              return 'Deleted local copies of ${downloadedFiles!.length} files in ${localDirs.length} folders';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? delete() {
    return initialized && deleteFiles != null
        ? () async {
            try {
              await deleteFiles!(directories);
              return 'Deleted ${files!.length} files in ${directories.length} folders';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }

  @override
  Future<String> Function()? deleteCache() {
    final cacheDirs = cachedDirectories;
    return initialized && deleteCacheFile != null && cacheDirs!.isNotEmpty
        ? () async {
            try {
              for (final dir in cacheDirs) {
                await deleteCacheFile!(dir);
              }
              return 'Deleted cached copies of ${cachedFiles!.length} in ${cacheDirs.length} folders';
            } finally {
              invalidateCache();
            }
          }
        : null;
  }
}

class DirectoryContextActionHandler
    extends DirectoryContextActionHandlerDelegate {
  final Future<void> Function(List<String>, List<String>)? moveDirectories;

  DirectoryContextActionHandler({
    required String directory,
    required super.getLink,
    super.downloadDirectories,
    super.saveDirectory,
    this.moveDirectories,
    super.deleteLocalFiles,
    super.deleteCacheFile,
    super.deleteFiles,
  }) : super(directories: [directory]);

  String get file => directories.first;

  void Function()? open() {
    return Directory(Main.pathFromKey(file)).existsSync() &&
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
        ? () {
            launchUrl(Uri.file(Main.pathFromKey(file)));
          }
        : null;
  }

  Future<String> Function()? rename(String newName) {
    return !initialized || moveDirectories == null || p.s3.dirname(file).isEmpty
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
}

class DirectoriesContextActionHandler
    extends DirectoryContextActionHandlerDelegate {
  DirectoriesContextActionHandler({
    required super.directories,
    required super.getLink,
    super.downloadDirectories,
    super.saveDirectory,
    super.deleteLocalFiles,
    super.deleteCacheFile,
    super.deleteFiles,
  });
}

class BulkContextActionHandler extends ContextActionHandlerDelegate {
  final DirectoriesContextActionHandler directoriesHandler;
  final FilesContextActionHandler filesHandler;
  List<String>? _filesCache;

  BulkContextActionHandler({
    required this.directoriesHandler,
    required this.filesHandler,
    required super.getLink,
    super.downloadFiles,
    super.saveFile,
    super.deleteLocalFiles,
    super.deleteCacheFile,
    super.deleteFiles,
  });

  @override
  List<String>? get files => _filesCache;

  @override
  Future<void> init() async {
    await directoriesHandler.init();
    await filesHandler.init();
    _filesCache = List.unmodifiable(
      directoriesHandler.files!.toSet().union(filesHandler.files!.toSet()),
    );
    await super.init();
  }

  @override
  Future<void> Function()? download() {
    final directoryHandle = directoriesHandler.download();
    final fileHandle = filesHandler.download();
    if (directoryHandle == null && fileHandle == null) {
      return null;
    }
    return () async {
      await directoryHandle?.call();
      await fileHandle?.call();
    };
  }

  @override
  Future<String> Function()? saveAs(String? path) {
    final directoryHandle = directoriesHandler.saveAs(path);
    final fileHandle = filesHandler.saveAs(path);
    if (directoryHandle == null && fileHandle == null) {
      return null;
    }
    return () async {
      await directoryHandle?.call();
      await fileHandle?.call();
      return 'Saving ${directoriesHandler.files!.length} files from ${directoriesHandler.directories.length} folders and ${filesHandler.files!.length} files to $path';
    };
  }

  @override
  Future<String> Function()? deleteLocal(List<String> downloadedFiles) {
    final handleDirectory = directoriesHandler.deleteLocal(
      directoriesHandler.localDirectories ?? [],
    );
    final handleFiles = filesHandler.deleteLocal(
      filesHandler.downloadedFiles ?? [],
    );
    return handleDirectory == null && handleFiles == null
        ? null
        : () async {
            await handleDirectory?.call();
            await handleFiles?.call();
            return 'Deleted local copies of ${directoriesHandler.files!.length} files in ${directoriesHandler.localDirectories!.length} folders and ${filesHandler.downloadedFiles!.length} files';
          };
  }

  @override
  Future<String> Function()? delete() {
    final handleDirectory = directoriesHandler.delete();
    final handleFiles = filesHandler.delete();
    return handleDirectory == null && handleFiles == null
        ? null
        : () async {
            await handleDirectory?.call();
            await handleFiles?.call();
            return 'Deleted ${directoriesHandler.files!.length} files in ${directoriesHandler.directories.length} folders and ${filesHandler.files!.length} files';
          };
  }

  @override
  Future<String> Function()? deleteCache() {
    final handleDirectory = directoriesHandler.deleteCache();
    final handleFiles = filesHandler.deleteCache();
    return handleDirectory == null && handleFiles == null
        ? null
        : () async {
            await handleDirectory?.call();
            await handleFiles?.call();
            return 'Deleted cache of ${directoriesHandler.files!.length} files in ${directoriesHandler.directories.length} folders and ${filesHandler.files!.length} files';
          };
  }
}

class ContextOptionDelegate {
  final String title;
  final IconData icon;
  final String? subtitle;
  final FutureOr<dynamic> Function()? action;
  final FutureOr<dynamic> Function()? secondaryAction;
  final IconData? secondaryIcon;
  final bool popOnInvoked;

  ContextOptionDelegate({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
    this.secondaryAction,
    this.secondaryIcon,
    this.popOnInvoked = false,
  });

  factory ContextOptionDelegate.download(
    ContextActionHandlerDelegate handler,
  ) => (() {
    final handle = handler.download();
    final downloadedCount = handler.downloadedFiles?.length;
    final totalCount = handler.files?.length;
    final handledCount = handler.initialized
        ? handler.downloadedFiles!
              .toSet()
              .union(handler.activeFiles!.toSet())
              .length
        : null;
    final allDownloaded = handler.initialized && downloadedCount == totalCount;
    final allHandled = handler.initialized && handledCount == totalCount;
    return ContextOptionDelegate(
      title: handle != null || !handler.initialized
          ? 'Download'
          : allDownloaded
          ? 'Downloaded'
          : allHandled
          ? 'Active Jobs'
          : 'Cannot Download',
      subtitle: handle != null && handler.files?.elementAtOrNull(1) != null
          ? 'Only missing files with backup folder set will be downloaded'
          : allDownloaded || allHandled || !handler.initialized
          ? null
          : 'Set backup folder to enable downloads',
      icon: handle != null
          ? Icons.file_download_rounded
          : allDownloaded
          ? Icons.file_download_done_rounded
          : allHandled
          ? Icons.file_download_rounded
          : Icons.file_download_off_rounded,
      action: handle,
    );
  })();

  factory ContextOptionDelegate.share(
    BuildContext context,
    ContextActionHandlerDelegate handler,
  ) => ContextOptionDelegate(
    title: 'Share',
    icon: Icons.share_rounded,
    action: (handler.files ?? []).isNotEmpty
        ? () async {
            final files = await keysToPathWithProgressDialog(
              context,
              keys: handler.files!,
              title: 'Preparing to Share...',
            );
            if (files.isNotEmpty) {
              SharePlus.instance.share(
                ShareParams(files: files.map((path) => XFile(path)).toList()),
              );
            }
          }
        : null,
  );

  factory ContextOptionDelegate.copyLinks(
    BuildContext context,
    ContextActionHandlerDelegate handler,
  ) => ContextOptionDelegate(
    title: 'Copy Link',
    icon: Icons.link_rounded,
    action: handler.getLinksToCopy(3600) != null
        ? () async {
            try {
              final seconds = await expiryDialog(context);
              Clipboard.setData(
                ClipboardData(text: handler.getLinksToCopy(seconds)!()),
              );
              showSnackBar(
                const SnackBar(content: Text('File link copied to clipboard')),
              );
            } catch (e) {
              showSnackBar(
                SnackBar(content: Text('Failed to generate link: $e')),
              );
            }
          }
        : null,
    secondaryIcon: Icons.share_rounded,
    secondaryAction: () async {
      try {
        final link = handler.getLinksToCopy(await expiryDialog(context))!();
        Clipboard.setData(ClipboardData(text: link));
        showSnackBar(
          const SnackBar(content: Text('File link copied to clipboard')),
        );
        SharePlus.instance.share(ShareParams(uri: Uri.tryParse(link)));
      } catch (e) {
        showSnackBar(SnackBar(content: Text('Failed to generate link: $e')));
      }
    },
  );

  factory ContextOptionDelegate.deleteUploaded(
    BuildContext context,
    ContextActionHandlerDelegate handler,
  ) {
    final handle = handler.deleteUploaded(handler.removableFiles ?? []);
    return ContextOptionDelegate(
      title: 'Remove from Device',
      subtitle: 'Only if uploaded to S3',
      icon: Icons.phonelink_off_rounded,
      action: handle == null
          ? null
          : () async {
              final yes = await confirmDialog(
                context,
                title: 'Remove from Device',
                content: Text(
                  'Are you sure you want to delete the local copies of ${handler.removableFiles!.length} uploaded files? Only uploaded files will be deleted from the device and can be downloaded again later.',
                ),
                okText: 'Delete',
              );
              if (yes) {
                showSnackBar(SnackBar(content: Text(await handle.call())));
              }
            },
    );
  }

  factory ContextOptionDelegate.deleteLocal(
    BuildContext context,
    ContextActionHandlerDelegate handler,
  ) {
    final handle = handler.deleteLocal(handler.downloadedFiles ?? []);
    return ContextOptionDelegate(
      title: 'Remove from Device',
      icon: Icons.delete_rounded,
      action: handle == null
          ? null
          : () async {
              final yes = await confirmDialog(
                context,
                title: 'Remove from Device',
                content: Text(
                  'Are you sure you want to delete the local copies of ${handler.downloadedFiles!.length} downloaded files? This action cannot be undone.',
                ),
                okText: 'Delete',
              );
              if (yes) {
                showSnackBar(SnackBar(content: Text(await handle.call())));
              }
            },
    );
  }

  factory ContextOptionDelegate.delete(
    BuildContext context,
    ContextActionHandlerDelegate handler,
    Function() clearSelection,
  ) {
    final handle = handler.delete();
    return ContextOptionDelegate(
      title: 'Delete Permanently',
      icon: Icons.delete_forever_rounded,
      subtitle: 'Delete from device as well as S3',
      action: handle == null
          ? null
          : () async {
              final yes = await confirmDialog(
                context,
                title: 'Permanently Delete Selected Files',
                content: Text(
                  'Are you sure you want to delete ${handler.files!.length} files from your device and S3? This action cannot be undone.',
                ),
                okText: 'Delete',
              );
              if (yes) {
                final result = await handle.call();
                clearSelection();
                showSnackBar(SnackBar(content: Text(result)));
              }
            },
      popOnInvoked: true,
    );
  }

  factory ContextOptionDelegate.deleteCache(
    BuildContext context,
    ContextActionHandlerDelegate handler,
  ) {
    final handle = handler.deleteCache();
    return ContextOptionDelegate(
      title: 'Remove Cache',
      icon: Icons.delete_outline_rounded,
      action: handle == null
          ? null
          : () async {
              final yes = await confirmDialog(
                context,
                title: 'Remove Cache',
                content: Text(
                  'Are you sure you want to remove the cached copies of ${handler.cachedFiles!.length} files? This action cannot be undone.',
                ),
                okText: 'Delete',
              );
              if (yes) {
                showSnackBar(SnackBar(content: Text(await handle.call())));
              }
            },
    );
  }
}

class FileContextOptionDelegate extends ContextOptionDelegate {
  FileContextOptionDelegate({
    required super.title,
    required super.icon,
    super.subtitle,
    super.action,
    super.secondaryAction,
    super.secondaryIcon,
    super.popOnInvoked = false,
  });

  factory FileContextOptionDelegate.cut(
    FileContextActionHandlerDelegate handler,
    Function(Iterable<String>)? cutKey,
  ) => FileContextOptionDelegate(
    title: 'Move To...',
    icon: Icons.cut_rounded,
    action: cutKey == null
        ? null
        : () {
            cutKey(handler.files!);
          },
    popOnInvoked: true,
  );

  factory FileContextOptionDelegate.copy(
    FileContextActionHandlerDelegate handler,
    Function(Iterable<String>)? copyKey,
  ) => FileContextOptionDelegate(
    title: 'Copy To...',
    icon: Icons.file_copy_rounded,
    action: copyKey == null
        ? null
        : () {
            copyKey(handler.files!);
          },
    popOnInvoked: true,
  );
}

class FileContextOption extends FileContextOptionDelegate {
  FileContextOption({
    required super.title,
    required super.icon,
    super.subtitle,
    super.action,
    super.secondaryAction,
    super.secondaryIcon,
    super.popOnInvoked = false,
  });

  factory FileContextOption.open(
    BuildContext context,
    FileContextActionHandler handler,
  ) {
    final openAction = handler.open(context);
    return FileContextOption(
      title: 'Open with...',
      subtitle: Main.pathFromKey(handler.file!),
      icon: Icons.open_in_new_rounded,
      action: openAction,
    );
  }

  factory FileContextOption.saveAs(
    BuildContext context,
    FileContextActionHandler handler,
  ) => FileContextOption(
    title: 'Save As...',
    icon: Icons.save_as_rounded,
    action: handler.saveFile == null
        ? null
        : () async {
            FileSaveLocation? saveLocation;
            try {
              saveLocation = await getSaveLocation(
                suggestedName: p.s3.basename(handler.file!),
                canCreateDirectories: true,
              );
            } catch (e) {
              saveLocation = await saveAsDialog(
                context,
                suggestedName: p.s3.basename(handler.file!),
              );
            }
            final handle = handler.saveAs(saveLocation?.path);
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(await handle())));
            }
          },
  );

  factory FileContextOption.rename(
    BuildContext context,
    FileContextActionHandler handler,
  ) => FileContextOption(
    title: 'Rename',
    icon: Icons.edit_rounded,
    action: handler.moveFiles == null
        ? null
        : () async {
            final newName = await renameDialog(
              context,
              p.s3.basename(handler.file!),
            );
            if (newName != null &&
                newName.isNotEmpty &&
                newName != p.s3.basename(handler.file!)) {
              showSnackBar(
                SnackBar(content: Text(await handler.rename(newName)!())),
              );
            }
          },
    popOnInvoked: true,
  );

  static List<List<ContextOptionDelegate>> allOptions(
    BuildContext context,
    FileContextActionHandler handler,
    Function(Iterable<String>)? cutKeys,
    Function(Iterable<String>)? copyKeys,
  ) {
    return [
      [
        FileContextOption.open(context, handler),
        ContextOptionDelegate.download(handler),
        FileContextOption.saveAs(context, handler),
      ],
      [
        ContextOptionDelegate.share(context, handler),
        ContextOptionDelegate.copyLinks(context, handler),
      ],
      [
        FileContextOptionDelegate.cut(handler, cutKeys),
        FileContextOptionDelegate.copy(handler, copyKeys),
        FileContextOption.rename(context, handler),
      ],
      [
        if (handler.removableFiles?.isNotEmpty ?? true)
          ContextOptionDelegate.deleteUploaded(context, handler)
        else if (handler.downloadedFiles?.isNotEmpty ?? true)
          ContextOptionDelegate.deleteLocal(context, handler),
        ContextOptionDelegate.delete(context, handler, () {}),
        ContextOptionDelegate.deleteCache(context, handler),
      ],
    ];
  }
}

class FilesContextOption extends FileContextOptionDelegate {
  FilesContextOption({
    required super.title,
    required super.icon,
    super.subtitle,
    super.action,
    super.secondaryAction,
    super.secondaryIcon,
    super.popOnInvoked = false,
  });

  factory FilesContextOption.saveAs(
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
            final handle = handler.saveAs(directory);
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(await handle())));
            }
          },
  );

  static List<List<ContextOptionDelegate>> allOptions(
    BuildContext context,
    FilesContextActionHandler handler,
    Function(Iterable<String>)? cutKeys,
    Function(Iterable<String>)? copyKeys,
    Function() clearSelection,
  ) {
    return [
      [
        ContextOptionDelegate.download(handler),
        FilesContextOption.saveAs(context, handler),
      ],
      [
        ContextOptionDelegate.share(context, handler),
        ContextOptionDelegate.copyLinks(context, handler),
      ],
      [
        FileContextOptionDelegate.cut(handler, cutKeys),
        FileContextOptionDelegate.copy(handler, copyKeys),
      ],
      [
        if (handler.removableFiles?.isNotEmpty ?? true)
          ContextOptionDelegate.deleteUploaded(context, handler),
        if (handler.downloadedFiles?.isNotEmpty ?? true)
          ContextOptionDelegate.deleteLocal(context, handler),
        ContextOptionDelegate.delete(context, handler, clearSelection),
        ContextOptionDelegate.deleteCache(context, handler),
      ],
    ];
  }
}

class DirectoryContextOptionDelegate extends ContextOptionDelegate {
  DirectoryContextOptionDelegate({
    required super.title,
    required super.icon,
    super.subtitle,
    super.action,
    super.secondaryAction,
    super.secondaryIcon,
    super.popOnInvoked = false,
  });

  factory DirectoryContextOptionDelegate.saveAs(
    BuildContext context,
    DirectoryContextActionHandlerDelegate handler,
  ) => DirectoryContextOptionDelegate(
    title: 'Save To...',
    icon: Icons.save_as_rounded,
    action: handler.saveDirectory == null
        ? null
        : () async {
            final directory = await getDirectoryPath(
              canCreateDirectories: true,
            );
            final handle = handler.saveAs(directory);
            if (handle != null) {
              showSnackBar(SnackBar(content: Text(await handle())));
            }
          },
  );

  factory DirectoryContextOptionDelegate.cut(
    DirectoryContextActionHandlerDelegate handler,
    Function(Iterable<String>)? cutKeys,
  ) => DirectoryContextOptionDelegate(
    title: 'Move To...',
    icon: Icons.cut_rounded,
    action: cutKeys == null
        ? null
        : () {
            cutKeys(handler.directories);
          },
    popOnInvoked: true,
  );

  factory DirectoryContextOptionDelegate.copy(
    DirectoryContextActionHandlerDelegate handler,
    Function(Iterable<String>)? copyKeys,
  ) => DirectoryContextOptionDelegate(
    title: 'Copy To...',
    icon: Icons.folder_copy_rounded,
    action: copyKeys == null
        ? null
        : () {
            copyKeys(handler.directories);
          },
    popOnInvoked: true,
  );
}

class DirectoryContextOption extends DirectoryContextOptionDelegate {
  DirectoryContextOption({
    required super.title,
    required super.icon,
    super.subtitle,
    super.action,
    super.secondaryAction,
    super.secondaryIcon,
    super.popOnInvoked = false,
  });

  factory DirectoryContextOption.open(DirectoryContextActionHandler handler) {
    final openAction = handler.open();
    return DirectoryContextOption(
      title: openAction == null ? 'Cannot Open' : 'Open',
      subtitle: openAction == null
          ? handler.localDirectories?.isEmpty ?? true
                ? 'Directory does not exist locally'
                : 'Unsupported platform for opening directories'
          : Main.pathFromKey(handler.file),
      icon: openAction == null ? Icons.open_in_new_off : Icons.open_in_new,
      action: openAction,
    );
  }

  factory DirectoryContextOption.rename(
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

  static List<List<ContextOptionDelegate>> allOptions(
    BuildContext context,
    DirectoryContextActionHandler handler,
    Function(Iterable<String>)? cutKeys,
    Function(Iterable<String>)? copyKeys,
  ) {
    return [
      [
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          DirectoryContextOption.open(handler),
        ContextOptionDelegate.download(handler),
        DirectoryContextOptionDelegate.saveAs(context, handler),
      ],
      [
        ContextOptionDelegate.share(context, handler),
        ContextOptionDelegate.copyLinks(context, handler),
      ],
      [
        DirectoryContextOptionDelegate.cut(handler, cutKeys),
        DirectoryContextOptionDelegate.copy(handler, copyKeys),
        if (handler.rename('any name') != null)
          DirectoryContextOption.rename(context, handler),
      ],
      [
        if (handler.removableFiles?.isNotEmpty == true)
          ContextOptionDelegate.deleteUploaded(context, handler),
        if (handler.localDirectories?.isNotEmpty == true)
          ContextOptionDelegate.deleteLocal(context, handler),
        ContextOptionDelegate.delete(context, handler, () {}),
        ContextOptionDelegate.deleteCache(context, handler),
      ],
    ];
  }
}

class DirectoriesContextOption extends DirectoryContextOptionDelegate {
  DirectoriesContextOption({
    required super.title,
    required super.icon,
    super.subtitle,
    super.action,
    super.secondaryAction,
    super.secondaryIcon,
    super.popOnInvoked = false,
  });

  static List<List<ContextOptionDelegate>> allOptions(
    BuildContext context,
    DirectoriesContextActionHandler handler,
    Function(Iterable<String>)? cutKeys,
    Function(Iterable<String>)? copyKeys,
    Function() clearSelection,
  ) {
    return [
      [
        ContextOptionDelegate.download(handler),
        DirectoryContextOptionDelegate.saveAs(context, handler),
      ],
      [
        ContextOptionDelegate.share(context, handler),
        ContextOptionDelegate.copyLinks(context, handler),
      ],
      [
        DirectoryContextOptionDelegate.cut(handler, cutKeys),
        DirectoryContextOptionDelegate.copy(handler, copyKeys),
      ],
      [
        if (handler.removableFiles?.isNotEmpty == true)
          ContextOptionDelegate.deleteUploaded(context, handler),
        if (handler.localDirectories?.isNotEmpty == true)
          ContextOptionDelegate.deleteLocal(context, handler),
        ContextOptionDelegate.delete(context, handler, clearSelection),
        ContextOptionDelegate.deleteCache(context, handler),
      ],
    ];
  }
}

class BulkContextOption extends ContextOptionDelegate {
  BulkContextOption({
    required super.title,
    required super.icon,
    super.subtitle,
    super.action,
    super.secondaryAction,
    super.secondaryIcon,
    super.popOnInvoked = false,
  });

  factory BulkContextOption.saveAs(
    BuildContext context,
    BulkContextActionHandler handler,
  ) => BulkContextOption(
    title: 'Save To...',
    icon: Icons.save_as_rounded,
    action: () async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      final handle = handler.saveAs(directory);
      if (handle != null) {
        showSnackBar(SnackBar(content: Text(await handle())));
      }
    },
  );

  factory BulkContextOption.cut(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    Function(Iterable<String>)? cutKey,
  ) => BulkContextOption(
    title: 'Move To...',
    icon: Icons.cut_rounded,
    action: cutKey != null
        ? () {
            cutKey([...directoriesHandler.directories, ...filesHandler.files!]);
          }
        : null,
    popOnInvoked: true,
  );

  factory BulkContextOption.copy(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    Function(Iterable<String>)? copyKey,
  ) => BulkContextOption(
    title: 'Copy To...',
    icon: Icons.copy_rounded,
    action: copyKey != null
        ? () {
            copyKey([
              ...directoriesHandler.directories,
              ...filesHandler.files!,
            ]);
          }
        : null,
    popOnInvoked: true,
  );

  static List<List<ContextOptionDelegate>> allOptions(
    BulkContextActionHandler handler,
    Function(Iterable<String>)? cutKeys,
    Function(Iterable<String>)? copyKeys,
    BuildContext context,
    Function() clearSelection,
  ) {
    return [
      [
        ContextOptionDelegate.download(handler),
        BulkContextOption.saveAs(context, handler),
      ],
      [
        ContextOptionDelegate.share(context, handler),
        ContextOptionDelegate.copyLinks(context, handler),
      ],
      [
        BulkContextOption.cut(
          handler.directoriesHandler,
          handler.filesHandler,
          cutKeys,
        ),
        BulkContextOption.copy(
          handler.directoriesHandler,
          handler.filesHandler,
          copyKeys,
        ),
      ],
      [
        if (handler.removableFiles?.isNotEmpty ?? true)
          ContextOptionDelegate.deleteUploaded(context, handler),
        if ((handler.directoriesHandler.localDirectories?.isNotEmpty ?? true) ||
            (handler.downloadedFiles?.isNotEmpty ?? true))
          ContextOptionDelegate.deleteLocal(context, handler),
        ContextOptionDelegate.delete(context, handler, clearSelection),
        ContextOptionDelegate.deleteCache(context, handler),
      ],
    ];
  }
}

Iterable<Widget> buildContextOptions(
  BuildContext context, {
  required List<List<ContextOptionDelegate>> optionsGroups,
  required List<ContextActionHandlerDelegate> handlers,
  void Function()? onInvoked,
}) {
  return optionsGroups.map(
    (options) => M3ECardColumn(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      outerRadius: 14,
      color: Colors.transparent,
      children: options
          .map(
            (option) => ListTile(
              visualDensity: VisualDensity.comfortable,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
                        option.secondaryAction!();
                        onInvoked?.call();
                      },
                      icon: Icon(option.secondaryIcon),
                    )
                  : null,
              onTap: option.action == null
                  ? null
                  : () async {
                      if (option.popOnInvoked) globalNavigator?.pop();
                      option.action!();
                      onInvoked?.call();
                    },
              enabled: option.action != null,
            ),
          )
          .toList(),
    ),
  );
}

Widget buildFileContextMenu(
  BuildContext context,
  String item,
  bool allowModify,
  String? Function(String, int?) getLink,
  Future<void> Function(Iterable<String>)? downloadFiles,
  Future<void> Function(String, String)? saveFile,
  void Function(Iterable<String>)? cut,
  void Function(Iterable<String>)? copy,
  Future<void> Function(List<String>, List<String>)? moveFiles,
  Future<void> Function(Iterable<String>)? deleteLocals,
  Future<void> Function(String)? deleteCache,
  Future<void> Function(Iterable<String>)? deleteFiles,
  void Function()? onInvoked,
) {
  String? mediaType = lookupMimeType(item);
  final handler = FileContextActionHandler(
    file: item,
    getLink: getLink,
    downloadFiles: downloadFiles,
    saveFile: saveFile,
    moveFiles: allowModify ? moveFiles : null,
    deleteLocalFiles: deleteLocals,
    deleteCacheFile: deleteCache,
    deleteFiles: allowModify ? deleteFiles : null,
  );
  return FutureBuilder(
    future: () async {
      final file = File(Main.pathFromKey(item));
      if (await file.exists()) {
        final bytes = await file
            .openRead(0, 64)
            .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d));
        mediaType =
            lookupMimeType(item, headerBytes: bytes.takeBytes()) ??
            'application/octet-stream';
      }
      await handler.init();
    }(),
    builder: (context, snapshot) => Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: FutureBuilder(
            future: RemoteFile.getByKey(item),
            builder: (context, snapshot) => M3ECardColumn(
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
                        showTime: DirOrFile.both,
                        showSize: DirOrFile.both,
                        showDownloadStatus: DirOrFile.both,
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
                    child: snapshot.hasData && snapshot.data != null
                        ? Text('MD5: ${snapshot.data!.etag}')
                        : Text('MD5: Loading...'),
                  ),
                ),
                // TODO: Image Info Widget
                if (mediaType?.startsWith('image/') ?? false)
                  ListTile(
                    visualDensity: VisualDensity.comfortable,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                    leading: Icon(Icons.camera_rounded),
                    title: Text('Info: ${snapshot.data?.metadata ?? 'N/A'}'),
                  ),
              ],
            ),
          ),
        ),
        ...buildContextOptions(
          context,
          optionsGroups: FileContextOption.allOptions(
            context,
            handler,
            allowModify ? cut : null,
            allowModify ? copy : null,
          ),
          handlers: [handler],
          onInvoked: onInvoked,
        ),
      ],
    ),
  );
}

Widget buildFilesContextMenu(
  BuildContext context,
  Iterable<String> items,
  String? Function(String, int?) getLink,
  Future<void> Function(Iterable<String>)? downloadFiles,
  Future<void> Function(String, String)? saveFile,
  void Function(Iterable<String>)? cut,
  void Function(Iterable<String>)? copy,
  Future<void> Function(Iterable<String>)? deleteLocals,
  Future<void> Function(String)? deleteCache,
  Future<void> Function(Iterable<String>)? deleteFiles,
  Function() clearSelection,
  void Function()? onInvoked,
) {
  final handler = FilesContextActionHandler(
    files: items,
    getLink: getLink,
    downloadFiles: downloadFiles,
    saveFile: saveFile,
    deleteLocalFiles: deleteLocals,
    deleteCacheFile: deleteCache,
    deleteFiles: deleteFiles,
  );
  return FutureBuilder(
    future: () async {
      await handler.init();
    }(),
    builder: (context, snapshot) => Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
              leading: Icon(Icons.file_copy_rounded),
              title: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: items.length == 1
                    ? Text(p.s3.basename(items.first))
                    : Text('${items.length} selected files'),
              ),
            ),
          ),
        ),
        ...buildContextOptions(
          context,
          optionsGroups: FilesContextOption.allOptions(
            context,
            handler,
            cut,
            copy,
            clearSelection,
          ),
          handlers: [handler],
          onInvoked: onInvoked,
        ),
      ],
    ),
  );
}

Widget buildDirectoryContextMenu(
  BuildContext context,
  String file,
  bool allowModify,
  String? Function(String, int?) getLink,
  Future<void> Function(Iterable<String>)? downloadDirectories,
  Future<void> Function(String, String)? saveDirectory,
  void Function(Iterable<String>)? cut,
  void Function(Iterable<String>)? copy,
  Future<void> Function(List<String>, List<String>)? moveDirectories,
  Future<void> Function(Iterable<String>)? deleteLocals,
  Future<void> Function(String)? deleteCache,
  Future<void> Function(Iterable<String>)? deleteDirectories,
  void Function()? onInvoked,
) {
  final handler = DirectoryContextActionHandler(
    directory: file,
    getLink: getLink,
    downloadDirectories: downloadDirectories,
    saveDirectory: saveDirectory,
    moveDirectories: allowModify ? moveDirectories : null,
    deleteLocalFiles: deleteLocals,
    deleteCacheFile: deleteCache,
    deleteFiles: allowModify ? deleteDirectories : null,
  );
  return FutureBuilder(
    future: () async {
      await handler.init();
    }(),
    builder: (context, snapshot) => Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
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
                        showTime: DirOrFile.both,
                        showSize: DirOrFile.both,
                        showDownloadStatus: DirOrFile.none,
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

        ...buildContextOptions(
          context,
          optionsGroups: DirectoryContextOption.allOptions(
            context,
            handler,
            allowModify ? cut : null,
            allowModify ? copy : null,
          ),
          handlers: [handler],
          onInvoked: onInvoked,
        ),
      ],
    ),
  );
}

Widget buildDirectoriesContextMenu(
  BuildContext context,
  Iterable<String> dirs,
  String? Function(String, int?) getLink,
  Future<void> Function(Iterable<String>)? downloadDirectories,
  Future<void> Function(String, String)? saveDirectory,
  void Function(Iterable<String>)? cut,
  void Function(Iterable<String>)? copy,
  Future<void> Function(Iterable<String>)? deleteLocals,
  Future<void> Function(String)? deleteCache,
  Future<void> Function(Iterable<String>)? deleteDirectories,
  Function() clearSelection,
  void Function()? onInvoked,
) {
  final handler = DirectoriesContextActionHandler(
    directories: dirs,
    getLink: getLink,
    downloadDirectories: downloadDirectories,
    saveDirectory: saveDirectory,
    deleteLocalFiles: deleteLocals,
    deleteCacheFile: deleteCache,
    deleteFiles: deleteDirectories,
  );
  return FutureBuilder(
    future: () async {
      await handler.init();
    }(),
    builder: (context, snapshot) => Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
              leading: Icon(Icons.folder_copy_rounded),
              title: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: dirs.length == 1
                    ? Text(p.s3.basename(dirs.first))
                    : Text('${dirs.length} selected folders'),
              ),
            ),
          ),
        ),
        ...buildContextOptions(
          context,
          optionsGroups: DirectoriesContextOption.allOptions(
            context,
            handler,
            cut,
            copy,
            clearSelection,
          ),
          handlers: [handler],
          onInvoked: onInvoked,
        ),
      ],
    ),
  );
}

Widget buildBulkContextMenu(
  BuildContext context,
  Iterable<String> items,
  String? Function(String, int?) getLink,
  Future<void> Function(Iterable<String>)? downloadFiles,
  Future<void> Function(Iterable<String>)? downloadDirectories,
  Future<void> Function(String, String)? saveFile,
  Future<void> Function(String, String)? saveDirectory,
  void Function(Iterable<String>)? cut,
  void Function(Iterable<String>)? copy,
  Future<void> Function(Iterable<String>)? deleteLocals,
  Future<void> Function(String)? deleteCache,
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
      getLink,
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
  final dirHandler = DirectoriesContextActionHandler(
    directories: items.where((item) => p.isDir(item)),
    getLink: getLink,
    downloadDirectories: downloadDirectories,
    saveDirectory: saveDirectory,
    deleteLocalFiles: deleteLocals,
    deleteCacheFile: deleteCache,
    deleteFiles: deleteDirectories,
  );
  final fileHandler = FilesContextActionHandler(
    files: items.where((item) => !p.isDir(item)),
    getLink: getLink,
    downloadFiles: downloadFiles,
    saveFile: saveFile,
    deleteLocalFiles: deleteLocals,
    deleteCacheFile: deleteCache,
    deleteFiles: deleteFiles,
  );
  final bulkHandler = BulkContextActionHandler(
    directoriesHandler: dirHandler,
    filesHandler: fileHandler,
    getLink: getLink,
  );
  return FutureBuilder(
    future: () async {
      await bulkHandler.init();
    }(),
    builder: (context, snapshot) => Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
              leading: Icon(Icons.folder_copy_rounded),
              title: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  '${items.where((element) => p.isDir(element)).length} selected folders and ${items.where((element) => !p.isDir(element)).length} selected files',
                ),
              ),
            ),
          ),
        ),
        ...buildContextOptions(
          context,
          optionsGroups: BulkContextOption.allOptions(
            bulkHandler,
            cut,
            copy,
            context,
            clearSelection,
          ),
          handlers: [dirHandler, fileHandler],
          onInvoked: onInvoked,
        ),
      ],
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
