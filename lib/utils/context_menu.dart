import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_selector/file_selector.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';

abstract class ContextActionHandler {
  ContextActionHandler();

  void Function()? download();
  String Function()? saveAs(String? path);
  Future<String> Function()? deleteLocal(bool? yes);
  Future<String> Function()? delete(bool? yes);
}

class FileContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final String? Function(RemoteFile, int?) getLink;
  final Function(RemoteFile) downloadFile;
  final Function(RemoteFile, String) saveFile;
  final Future<void> Function(List<String>, List<String>) moveFiles;
  final Function(String) deleteLocalFile;
  final Future<void> Function(List<String>) deleteFiles;

  FileContextActionHandler({
    required this.file,
    required this.getLink,
    required this.downloadFile,
    required this.saveFile,
    required this.moveFiles,
    required this.deleteLocalFile,
    required this.deleteFiles,
  });

  bool rootExists() {
    return p.isAbsolute(Main.pathFromKey(file.key) ?? file.key);
  }

  dynamic Function()? open() {
    final link = getLink(file, null);
    return File(Main.pathFromKey(file.key) ?? file.key).existsSync()
        ? () {
            OpenFile.open(Main.pathFromKey(file.key) ?? file.key);
          }
        : link == null
        ? null
        : () {
            launchUrl(Uri.parse(link));
          };
  }

  @override
  void Function()? download() {
    return !rootExists() ||
            File(Main.pathFromKey(file.key) ?? file.key).existsSync()
        ? null
        : () {
            downloadFile(file);
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path != null
        ? () {
            saveFile(file, path);
            return 'Saving to $path';
          }
        : null;
  }

  XFile Function()? getXFile() {
    return File(Main.pathFromKey(file.key) ?? file.key).existsSync()
        ? () {
            return XFile(Main.pathFromKey(file.key) ?? file.key);
          }
        : null;
  }

  String? Function() getLinkToCopy(int? seconds) {
    return () {
      return getLink(file, seconds);
    };
  }

  Future<String> Function() rename(String newName) {
    return () async {
      final newKey = p.join(p.dirname(file.key), newName.replaceAll('/', '_'));
      await moveFiles([file.key], [newKey]);
      return 'Renamed to $newName';
    };
  }

  @override
  Future<String> Function()? deleteLocal(bool? yes) {
    return yes ?? false
        ? () async {
            await deleteLocalFile(file.key);
            return 'Deleted local copy of ${file.key.split('/').last}';
          }
        : null;
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return yes ?? false
        ? () async {
            await deleteFiles([file.key]);
            return 'Deleted ${file.key.split('/').last}';
          }
        : null;
  }
}

class FilesContextActionHandler extends ContextActionHandler {
  final List<RemoteFile> files;
  final String? Function(RemoteFile, int?) getLink;
  final Function(RemoteFile) downloadFile;
  final Function(RemoteFile, String) saveFile;
  final Future<void> Function(List<String>, List<String>) moveFiles;
  final Function(String) deleteLocalFile;
  final Future<void> Function(List<String>) deleteS3Files;
  final Future<void> Function(List<String>) deleteFiles;

  FilesContextActionHandler({
    required this.files,
    required this.getLink,
    required this.downloadFile,
    required this.saveFile,
    required this.moveFiles,
    required this.deleteLocalFile,
    required this.deleteS3Files,
    required this.deleteFiles,
  });

  List<bool> rootExists() {
    return files
        .map((file) => p.isAbsolute(Main.pathFromKey(file.key) ?? file.key))
        .toList();
  }

  List<bool> downloaded() {
    return files
        .map(
          (file) => File(Main.pathFromKey(file.key) ?? file.key).existsSync(),
        )
        .toList();
  }

  List<RemoteFile> cloudDeletable() {
    return files
        .where(
          (file) =>
              Main.backupMode(file.key) == BackupMode.upload &&
              !File(Main.pathFromKey(file.key) ?? file.key).existsSync(),
        )
        .toList();
  }

  List<RemoteFile> removableFiles() {
    return files
        .where(
          (f) =>
              !f.key.endsWith('/') &&
              File(Main.pathFromKey(f.key) ?? f.key).existsSync() &&
              Main.backupMode(f.key) == BackupMode.upload,
        )
        .toList();
  }

  @override
  void Function()? download() {
    return downloaded().every((exists) => exists) ||
            rootExists().every((exists) => !exists)
        ? null
        : () {
            files
                .where(
                  (file) => !File(
                    Main.pathFromKey(file.key) ?? file.key,
                  ).existsSync(),
                )
                .map(downloadFile);
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path != null
        ? () {
            for (final file in files) {
              saveFile(file, p.join(path, file.key.split('/').last));
            }
            return 'Saving to $path';
          }
        : null;
  }

  List<XFile> Function()? getXFiles() {
    return downloaded().any((exists) => exists)
        ? () {
            return files
                .where(
                  (file) => File(
                    (Main.pathFromKey(file.key) ?? file.key),
                  ).existsSync(),
                )
                .map((file) => XFile(Main.pathFromKey(file.key) ?? file.key))
                .toList();
          }
        : null;
  }

  String Function() getLinksToCopy(int? seconds) {
    return () {
      String allLinks = '';
      for (final file in files) {
        allLinks += '${getLink(file, seconds)}\n\n';
      }
      return allLinks;
    };
  }

  Future<String> Function()? deleteUploaded(
    List<RemoteFile> removableFiles,
    bool? yes,
  ) {
    return yes ?? false
        ? () async {
            for (final file in removableFiles) {
              await deleteLocalFile(file.key);
            }
            return 'Deleted local copies of ${removableFiles.length} uploaded files';
          }
        : null;
  }

  @override
  Future<String> Function()? deleteLocal(bool? yes) {
    return yes ?? false
        ? () async {
            for (final file in files.where(
              (file) =>
                  File(Main.pathFromKey(file.key) ?? file.key).existsSync(),
            )) {
              await deleteLocalFile(file.key);
            }
            return 'Deleted local copies of ${files.length} files';
          }
        : null;
  }

  Future<String> Function()? deleteS3(
    List<RemoteFile> cloudDeletable,
    bool? yes,
  ) {
    return yes ?? false
        ? () async {
            await deleteS3Files(cloudDeletable.map((f) => f.key).toList());
            return 'Deleted ${cloudDeletable.length} files from S3';
          }
        : null;
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return yes ?? false
        ? () async {
            await deleteFiles(files.map((f) => f.key).toList());
            return 'Deleted ${files.length} files';
          }
        : null;
  }
}

class DirectoryContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final Function(RemoteFile) downloadDirectory;
  final Function(RemoteFile, String) saveDirectory;
  final Future<void> Function(List<String>, List<String>) moveDirectories;
  final Function(String) deleteLocalDirectory;
  final Future<void> Function(List<String>) deleteS3Directories;
  final Future<void> Function(List<String>) deleteDirectories;

  DirectoryContextActionHandler({
    required this.file,
    required this.downloadDirectory,
    required this.saveDirectory,
    required this.moveDirectories,
    required this.deleteLocalDirectory,
    required this.deleteS3Directories,
    required this.deleteDirectories,
  });

  List<RemoteFile> removableFiles() {
    return Main.remoteFiles
        .where(
          (f) =>
              p.isWithin(file.key, f.key) &&
              !f.key.endsWith('/') &&
              File(Main.pathFromKey(f.key) ?? f.key).existsSync() &&
              Main.backupMode(f.key) == BackupMode.upload,
        )
        .toList();
  }

  List<RemoteFile> cloudDeletable() {
    return p.split(file.key).length > 1
        ? Main.remoteFiles
              .where(
                (f) =>
                    p.isWithin(file.key, f.key) &&
                    Main.backupMode(f.key) == BackupMode.upload &&
                    !File(Main.pathFromKey(f.key) ?? f.key).existsSync(),
              )
              .toList()
        : Main.remoteFiles.where((f) => p.isWithin(file.key, f.key)).toList();
  }

  bool rootExists() {
    return p.isAbsolute(Main.pathFromKey(file.key) ?? file.key);
  }

  void Function()? open() {
    return Directory(Main.pathFromKey(file.key) ?? file.key).existsSync()
        ? () {
            OpenFile.open(Main.pathFromKey(file.key));
          }
        : null;
  }

  @override
  void Function()? download() {
    return !rootExists()
        ? null
        : () {
            downloadDirectory(file);
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path == null
        ? null
        : () {
            saveDirectory(file, path);
            return 'Saving to $path';
          };
  }

  Future<String> Function() rename(String newName) {
    return () async {
      final key = file.key.endsWith('/') ? file.key : '${file.key}/';
      final newKey = '${p.dirname(key)}/${newName.replaceAll('/', '_')}/';
      await moveDirectories([key], [newKey]);
      return 'Renamed to $newName';
    };
  }

  Future<String> Function()? deleteUploaded(
    List<RemoteFile> removableFiles,
    bool? yes,
  ) {
    return yes ?? false
        ? () async {
            for (final file in removableFiles) {
              deleteLocalDirectory(file.key);
            }
            return 'Deleted local copies of uploaded files in ${p.basename(file.key)}';
          }
        : null;
  }

  @override
  Future<String> Function()? deleteLocal(bool? yes) {
    return yes ?? false
        ? () async {
            final key = file.key.endsWith('/') ? file.key : '${file.key}/';
            deleteLocalDirectory(key);
            return 'Deleted local copy of ${p.basename(key)}';
          }
        : null;
  }

  Future<String> Function()? deleteS3(
    List<RemoteFile> cloudDeletable,
    bool? yes,
  ) {
    return yes ?? false
        ? () async {
            await deleteS3Directories(
              cloudDeletable.map((f) => f.key).toList(),
            );
            return 'Deleted ${cloudDeletable.length} files from S3';
          }
        : null;
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return yes ?? false
        ? () async {
            final key = file.key.endsWith('/') ? file.key : '${file.key}/';
            deleteDirectories([key]);
            return 'Deleted ${p.basename(key)}';
          }
        : null;
  }
}

class DirectoriesContextActionHandler extends ContextActionHandler {
  final List<RemoteFile> directories;
  final Function(RemoteFile) downloadDirectory;
  final Function(RemoteFile, String) saveDirectory;
  final Future<void> Function(List<String>, List<String>) moveDirectories;
  final Function(String) deleteLocalDirectory;
  final Future<void> Function(List<String>) deleteS3Directories;
  final Future<void> Function(List<String>) deleteDirectories;

  DirectoriesContextActionHandler({
    required this.directories,
    required this.downloadDirectory,
    required this.saveDirectory,
    required this.moveDirectories,
    required this.deleteLocalDirectory,
    required this.deleteS3Directories,
    required this.deleteDirectories,
  });

  List<bool> rootExists() {
    return directories
        .map((dir) => p.isAbsolute(Main.pathFromKey(dir.key) ?? dir.key))
        .toList();
  }

  List<RemoteFile> removableFiles() {
    return Main.remoteFiles
        .where(
          (f) =>
              directories.any((dir) => p.isWithin(dir.key, f.key)) &&
              !f.key.endsWith('/') &&
              File(Main.pathFromKey(f.key) ?? f.key).existsSync() &&
              Main.backupMode(f.key) == BackupMode.upload,
        )
        .toList();
  }

  List<RemoteFile> cloudDeletable() {
    List<RemoteFile> deletable = [];
    for (final dir in directories) {
      deletable.addAll(
        p.split(dir.key).length > 1
            ? Main.remoteFiles
                  .where(
                    (f) =>
                        p.isWithin(dir.key, f.key) &&
                        Main.backupMode(f.key) == BackupMode.upload &&
                        !File(Main.pathFromKey(f.key) ?? f.key).existsSync(),
                  )
                  .toList()
            : Main.remoteFiles
                  .where((f) => p.isWithin(dir.key, f.key))
                  .toList(),
      );
    }
    return deletable;
  }

  @override
  void Function()? download() {
    return rootExists().every((exists) => !exists)
        ? null
        : () {
            directories
                .where(
                  (dir) => Directory(
                    Main.pathFromKey(dir.key) ?? dir.key,
                  ).existsSync(),
                )
                .map(downloadDirectory);
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path != null
        ? () {
            for (final dir in directories) {
              saveDirectory(dir, p.join(path, p.basename(dir.key)));
            }
            return 'Saving to $path';
          }
        : null;
  }

  Future<String> Function()? deleteUploaded(
    List<RemoteFile> removableFiles,
    bool? yes,
  ) {
    return yes ?? false
        ? () async {
            for (final dir in directories) {
              final key = dir.key.endsWith('/') ? dir.key : '${dir.key}/';
              for (final file in removableFiles) {
                if (p.isWithin(key, file.key)) {
                  deleteLocalDirectory(file.key);
                }
              }
            }
            return 'Deleted local copies of uploaded files in ${directories.length} directories';
          }
        : null;
  }

  @override
  Future<String> Function()? deleteLocal(bool? yes) {
    return yes ?? false
        ? () async {
            for (final dir in directories) {
              final key = dir.key.endsWith('/') ? dir.key : '${dir.key}/';
              deleteLocalDirectory(key);
            }
            return 'Deleted local copies of ${directories.length} directories';
          }
        : null;
  }

  Future<String> Function()? deleteS3(
    List<RemoteFile> cloudDeletable,
    bool? yes,
  ) {
    return yes ?? false
        ? () async {
            await deleteS3Directories(
              cloudDeletable.map((f) => f.key).toList(),
            );
            return 'Deleted ${cloudDeletable.length} files from S3';
          }
        : null;
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return yes ?? false
        ? () async {
            final keys = directories
                .map((dir) => dir.key.endsWith('/') ? dir.key : '${dir.key}/')
                .toList();
            await deleteDirectories(keys);
            return 'Deleted ${directories.length} directories';
          }
        : null;
  }
}

class FileContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function()? action;

  FileContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
  });

  static FileContextOption open(FileContextActionHandler handler) =>
      FileContextOption(
        title:
            File(
              Main.pathFromKey(handler.file.key) ?? handler.file.key,
            ).existsSync()
            ? 'Open'
            : handler.open() == null
            ? 'Link Unavailable'
            : 'Open Link',
        subtitle: Main.pathFromKey(handler.file.key),
        icon: Icons.open_in_new,
        action: handler.open(),
      );

  static FileContextOption download(FileContextActionHandler handler) =>
      FileContextOption(
        title: handler.download() == null
            ? handler.rootExists()
                  ? 'Downloaded'
                  : 'Cannot Download'
            : 'Download',
        subtitle: handler.download() == null
            ? handler.rootExists()
                  ? Main.pathFromKey(handler.file.key)
                  : 'Set backup directory to enable downloads'
            : null,
        icon: handler.download() == null
            ? handler.rootExists()
                  ? Icons.file_download_done_rounded
                  : Icons.file_download_off
            : Icons.file_download_outlined,
        action: handler.download(),
      );

  static FileContextOption saveAs(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Save As...',
    icon: Icons.save_as,
    action: () async {
      final String Function()? handle = handler.saveAs(
        (await getSaveLocation(
          suggestedName: handler.file.key.split('/').last,
          canCreateDirectories: true,
        ))?.path,
      );
      if (handle != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(handle())));
      }
    },
  );

  static FileContextOption share(FileContextActionHandler handler) =>
      FileContextOption(
        title: handler.getXFile() == null ? 'Cannot Share' : 'Share',
        icon: Icons.share,
        subtitle: handler.getXFile() == null
            ? 'Only downloaded files can be shared'
            : null,
        action: () {
          final XFile Function()? handle = handler.getXFile();
          return handle != null
              ? () {
                  SharePlus.instance.share(
                    ShareParams(files: <XFile>[handle()]),
                  );
                }
              : null;
        }(),
      );

  static FileContextOption copyLink(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Copy Link',
    icon: Icons.link,
    action: () async {
      try {
        Clipboard.setData(
          ClipboardData(
            text: handler.getLinkToCopy(await expiryDialog(context))()!,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File link copied to clipboard')),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate link: $e')));
      }
    },
  );

  static FileContextOption cut(
    FileContextActionHandler handler,
    Function(RemoteFile) cutKey,
  ) {
    return FileContextOption(
      title: 'Move To...',
      icon: Icons.cut,
      action: () {
        cutKey(handler.file);
      },
    );
  }

  static FileContextOption copy(
    FileContextActionHandler handler,
    Function(RemoteFile) copyKey,
  ) {
    return FileContextOption(
      title: 'Copy To...',
      icon: Icons.file_copy_rounded,
      action: () {
        copyKey(handler.file);
      },
    );
  }

  static FileContextOption rename(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Rename',
    icon: Icons.edit,
    action: () async {
      final newName = await renameDialog(
        context,
        handler.file.key.split('/').last,
      );
      if (newName != null &&
          newName.isNotEmpty &&
          newName != handler.file.key.split('/').last) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(await handler.rename(newName)())),
        );
      }
    },
  );

  static FileContextOption deleteLocal(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Delete Local Copy',
    subtitle: 'Delete from device only',
    icon: Icons.delete_outline,
    action: () async {
      final handle = handler.deleteLocal(
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Local Copy'),
            content: Text(
              'Are you sure you want to delete the local copy of ${handler.file.key.split('/').last}? This action cannot be undone.',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(await handle())));
      }
    },
  );

  static FileContextOption delete(
    FileContextActionHandler handler,
    BuildContext context,
  ) => FileContextOption(
    title: 'Delete',
    icon: Icons.delete,
    subtitle: 'Delete from device as well as S3',
    action: () async {
      final handle = handler.delete(
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete File'),
            content: Text(
              'Are you sure you want to delete ${handler.file.key.split('/').last} from your device and S3? This action cannot be undone.',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(await handle())));
      }
    },
  );

  static List<FileContextOption> allOptions(
    BuildContext context,
    FileContextActionHandler handler,
    Function(RemoteFile) cutKey,
    Function(RemoteFile) copyKey,
  ) {
    return [
      open(handler),
      download(handler),
      saveAs(handler, context),
      share(handler),
      copyLink(handler, context),
      cut(handler, cutKey),
      copy(handler, copyKey),
      rename(handler, context),
      deleteLocal(handler, context),
      delete(handler, context),
    ];
  }
}

class FilesContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function()? action;

  FilesContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
  });

  static FilesContextOption downloadAll(FilesContextActionHandler handler) =>
      FilesContextOption(
        title: handler.download() != null
            ? 'Download'
            : handler.downloaded().every((downloaded) => downloaded)
            ? 'Downloaded'
            : 'Cannot Download',
        subtitle: handler.download() != null
            ? null
            : handler.downloaded().every((downloaded) => downloaded)
            ? null
            : 'Backup directory must be set to enable downloads',
        icon: handler.download() != null
            ? Icons.file_download_outlined
            : handler.downloaded().every((downloaded) => downloaded)
            ? Icons.file_download_done_rounded
            : Icons.file_download_off,
        action: handler.download(),
      );

  static FilesContextOption saveAllTo(
    BuildContext context,
    FilesContextActionHandler handler,
  ) => FilesContextOption(
    title: 'Save To...',
    icon: Icons.save_as,
    action: () async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      bool saved = false;
      if (handler.saveAs(directory) != null) {
        handler.saveAs(directory)!();
        saved = true;
      }
      if (saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saving files to $directory')));
      }
    },
  );

  static FilesContextOption shareAll(FilesContextActionHandler handler) =>
      FilesContextOption(
        title: handler.getXFiles() == null ? 'Cannot Share' : 'Share All',
        icon: Icons.share,
        subtitle: handler.getXFiles() == null
            ? 'No downloaded files to share'
            : handler.downloaded().every((d) => d)
            ? null
            : 'Only downloaded files will be shared',
        action: handler.getXFiles() != null
            ? () {
                SharePlus.instance.share(
                  ShareParams(files: handler.getXFiles()!()),
                );
              }
            : null,
      );

  static FilesContextOption copyAllLinks(
    BuildContext context,
    FilesContextActionHandler handler,
  ) => FilesContextOption(
    title: 'Copy Links',
    icon: Icons.link,
    action: () async {
      int? seconds = await expiryDialog(context);
      String allLinks = handler.getLinksToCopy(seconds)();
      if (allLinks.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: allLinks));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File links copied to clipboard')),
        );
      }
    },
  );

  static FilesContextOption cut(Function(RemoteFile?) cutKey) =>
      FilesContextOption(
        title: 'Move To...',
        icon: Icons.cut,
        action: () {
          cutKey(null);
        },
      );

  static FilesContextOption copy(Function(RemoteFile?) copyKey) =>
      FilesContextOption(
        title: 'Copy To...',
        icon: Icons.file_copy_rounded,
        action: () {
          copyKey(null);
        },
      );

  static FilesContextOption deleteUploaded(
    BuildContext context,
    FilesContextActionHandler handler,
  ) => FilesContextOption(
    title: 'Delete Uploaded Copies',
    subtitle: 'Delete local copies of uploaded files only',
    icon: Icons.delete_forever_outlined,
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Uploaded Copies'),
          content: const Text(
            'Are you sure you want to delete the local copies of the uploaded files? This action cannot be undone.',
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
        handler.deleteUploaded(handler.removableFiles(), true)!.call();
        ScaffoldMessenger.of(context).showSnackBar(
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
  ) => FilesContextOption(
    title: 'Delete Local Copies',
    subtitle: 'Delete from device only',
    icon: Icons.delete_outline,
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Local Copies'),
          content: const Text(
            'Are you sure you want to delete the local copies of the selected files? This action cannot be undone.',
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
        handler.deleteLocal(true)!.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local copies of selected files deleted'),
          ),
        );
      }
    },
  );

  static FilesContextOption deleteS3All(
    BuildContext context,
    FilesContextActionHandler handler,
  ) => FilesContextOption(
    title: 'Delete from S3',
    subtitle: 'Delete from S3 only',
    icon: Icons.cloud_off,
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete from S3'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Are you sure you want to delete the selected files from S3? This action cannot be undone.',
              ),
              SingleChildScrollView(
                child: Column(
                  children: handler.cloudDeletable().map((file) {
                    return Text(file.key);
                  }).toList(),
                ),
              ),
              if (handler.cloudDeletable().isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: Text(
                    'Note: None of the selected files can be deleted from S3 because they either have local copies or are not set to be backed up.',
                    style: TextStyle(fontStyle: FontStyle.italic),
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
        handler.deleteS3(handler.cloudDeletable(), true)!.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected files deleted from S3')),
        );
      }
    },
  );

  static FilesContextOption deleteAll(
    BuildContext context,
    FilesContextActionHandler handler,
    Function() clearSelection,
  ) => FilesContextOption(
    title: 'Delete Selection',
    icon: Icons.delete_sweep,
    subtitle: 'Delete from device as well as S3',
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Selected Files'),
          content: const Text(
            'Are you sure you want to delete selected files from your device and S3? This action cannot be undone.',
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
        handler.delete(true)!.call();
        clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected files deleted from device and S3'),
          ),
        );
      }
    },
  );

  static List<FilesContextOption> allOptions(
    BuildContext context,
    FilesContextActionHandler handler,
    Function(RemoteFile?) cutKey,
    Function(RemoteFile?) copyKey,
    Function() clearSelection,
  ) {
    return [
      downloadAll(handler),
      saveAllTo(context, handler),
      shareAll(handler),
      copyAllLinks(context, handler),
      cut(cutKey),
      copy(copyKey),
      deleteUploaded(context, handler),
      deleteLocalAll(context, handler),
      deleteAll(context, handler, clearSelection),
    ];
  }
}

class DirectoryContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function()? action;

  DirectoryContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
  });

  static DirectoryContextOption open(DirectoryContextActionHandler handler) =>
      DirectoryContextOption(
        title: handler.open() == null ? 'Cannot Open' : 'Open',
        subtitle: handler.open() == null
            ? 'Directory does not exist locally'
            : Main.pathFromKey(handler.file.key),
        icon: handler.open() == null
            ? Icons.open_in_new_off
            : Icons.open_in_new,
        action: handler.open(),
      );

  static DirectoryContextOption download(
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: handler.download() == null ? 'Cannot Download' : 'Download',
    subtitle: handler.download() == null
        ? 'Set backup directory to enable downloads'
        : 'Only missing files will be downloaded',
    icon: handler.download() == null
        ? Icons.file_download_off
        : Icons.file_download_outlined,
    action: handler.download(),
  );

  static DirectoryContextOption saveTo(
    DirectoryContextActionHandler handler,
    BuildContext context,
  ) => DirectoryContextOption(
    title: 'Save To...',
    icon: Icons.save_as,
    action: () async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      final handle = handler.saveAs(
        directory == null
            ? null
            : p.join(directory, p.basename(handler.file.key)),
      );
      if (handle != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(handle())));
      }
    },
  );

  static DirectoryContextOption cut(
    DirectoryContextActionHandler handler,
    Function(RemoteFile) cutKey,
  ) => DirectoryContextOption(
    title: 'Move To...',
    icon: Icons.cut,
    action: () {
      cutKey(handler.file);
    },
  );

  static DirectoryContextOption copy(
    DirectoryContextActionHandler handler,
    Function(RemoteFile) copyKey,
  ) => DirectoryContextOption(
    title: 'Copy To...',
    icon: Icons.folder_copy,
    action: () {
      copyKey(handler.file);
    },
  );

  static DirectoryContextOption rename(
    BuildContext context,
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: 'Rename',
    icon: Icons.edit,
    action: () async {
      final newName = await renameDialog(context, p.basename(handler.file.key));
      if (newName != null &&
          newName.isNotEmpty &&
          newName != p.basename(handler.file.key)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(await handler.rename(newName)())),
        );
      }
    },
  );

  static DirectoryContextOption deleteUploaded(
    BuildContext context,
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: 'Delete Uploaded Files',
    subtitle: 'Delete local copies of uploaded files only',
    icon: Icons.delete_sweep,
    action: handler.removableFiles().isEmpty
        ? null
        : () async {
            bool? yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Uploaded Files'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'The following files will be deleted from your local directory:',
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
                              for (final file in handler.removableFiles())
                                Text(Main.pathFromKey(file.key) ?? file.key),
                              if (handler.removableFiles().isEmpty)
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
                    onPressed: handler.removableFiles().isNotEmpty
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    await handler.deleteUploaded(
                      handler.removableFiles(),
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
    subtitle: 'Delete from device only',
    icon: Icons.folder_delete,
    action: () async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(await handler.deleteLocal(true)!())),
        );
      }
    },
  );

  static DirectoryContextOption deleteS3(
    BuildContext context,
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: 'Delete from S3',
    subtitle: 'Delete from S3 only',
    icon: Icons.cloud_off,
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete from S3'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to delete ${p.basename(handler.file.key)} containing the following ${handler.cloudDeletable().length} files from S3? This action cannot be undone.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: handler.cloudDeletable().map((file) {
                        return Text(file.key);
                      }).toList(),
                    ),
                  ),
                ),
              ),
              if (handler.cloudDeletable().isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: Text(
                    'Note: This directory cannot be deleted from S3 because it either has local copies or its files are not set to be backed up.',
                    style: TextStyle(fontStyle: FontStyle.italic),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              await handler.deleteS3(handler.cloudDeletable(), true)!(),
            ),
          ),
        );
      }
    },
  );

  static DirectoryContextOption delete(
    BuildContext context,
    DirectoryContextActionHandler handler,
  ) => DirectoryContextOption(
    title: 'Delete',
    icon: Icons.folder_delete,
    subtitle: 'Delete from device as well as S3',
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Directory'),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(await handler.delete(true)!())));
      }
    },
  );

  static List<DirectoryContextOption> allOptions(
    BuildContext context,
    DirectoryContextActionHandler handler,
    Function(RemoteFile) cutKey,
    Function(RemoteFile) copyKey,
  ) {
    return [
      open(handler),
      download(handler),
      saveTo(handler, context),
      cut(handler, cutKey),
      copy(handler, copyKey),
      rename(context, handler),
      if (p.split(handler.file.key).length == 1 ||
          Main.backupMode(handler.file.key) == BackupMode.upload)
        deleteS3(context, handler),
      if (handler.removableFiles().isNotEmpty) deleteUploaded(context, handler),
      deleteLocal(context, handler),
      delete(context, handler),
    ];
  }
}

class DirectoriesContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function()? action;

  static DirectoriesContextOption downloadAll(
    DirectoriesContextActionHandler handler,
  ) => DirectoriesContextOption(
    title: handler.download() == null ? 'Cannot Download' : 'Download',
    subtitle: handler.download() == null
        ? 'Set backup directory to enable downloads'
        : 'Only missing files with backup directory set will be downloaded',
    icon: handler.download() == null
        ? Icons.file_download_off
        : Icons.file_download_outlined,
    action: handler.download() == null
        ? null
        : () {
            handler.download();
          },
  );

  static DirectoriesContextOption saveAllTo(
    DirectoriesContextActionHandler handler,
    BuildContext context,
  ) => DirectoriesContextOption(
    title: 'Save To...',
    icon: Icons.save_as,
    action: () async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      bool saved = false;
      final handle = handler.saveAs(directory);
      if (handle != null) {
        handle();
        saved = true;
      }
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saving directories to $directory')),
        );
      }
    },
  );

  static DirectoriesContextOption cut(Function(RemoteFile?) cutKey) =>
      DirectoriesContextOption(
        title: 'Move To...',
        icon: Icons.cut,
        action: () {
          cutKey(null);
        },
      );

  static DirectoriesContextOption copy(Function(RemoteFile?) copyKey) =>
      DirectoriesContextOption(
        title: 'Copy To...',
        icon: Icons.folder_copy,
        action: () {
          copyKey(null);
        },
      );

  static DirectoriesContextOption deleteUploaded(
    DirectoriesContextActionHandler handler,
    BuildContext context,
  ) => DirectoriesContextOption(
    title: 'Delete Uploaded Files',
    subtitle: 'Delete local copies of uploaded files only',
    icon: Icons.delete_sweep,
    action: handler.removableFiles().isNotEmpty
        ? () async {
            bool? yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Uploaded Files'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'The following files will be deleted from your local directories:',
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
                              for (final file in handler.removableFiles())
                                Text(Main.pathFromKey(file.key) ?? file.key),
                              if (handler.removableFiles().isEmpty)
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
                    onPressed: handler.removableFiles().isNotEmpty
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    await handler.deleteUploaded(
                      handler.removableFiles(),
                      true,
                    )!(),
                  ),
                ),
              );
            }
          }
        : null,
  );

  static DirectoriesContextOption deleteLocal(
    DirectoriesContextActionHandler handler,
    BuildContext context,
  ) => DirectoriesContextOption(
    title: 'Delete Local Copies',
    subtitle: 'Delete from device only',
    icon: Icons.delete_outline,
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Local Copies'),
          content: const Text(
            'Are you sure you want to delete the local copies of the selected directories? This action cannot be undone.',
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
        handler.deleteLocal(true)!.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local copies of selected directories deleted'),
          ),
        );
      }
    },
  );

  static DirectoriesContextOption deleteS3(
    DirectoriesContextActionHandler handler,
    BuildContext context,
  ) => DirectoriesContextOption(
    title: 'Delete from S3',
    subtitle: 'Delete from S3 only',
    icon: Icons.cloud_off,
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete from S3'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Are you sure you want to delete the selected directories from S3? This action cannot be undone.',
              ),
              SingleChildScrollView(
                child: Column(
                  children: handler.cloudDeletable().map((file) {
                    return Text(file.key);
                  }).toList(),
                ),
              ),
              if (handler.cloudDeletable().isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: Text(
                    'Note: None of the selected directories can be deleted from S3 because they either have local copies or their files are not set to be backed up.',
                    style: TextStyle(fontStyle: FontStyle.italic),
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
        handler.deleteS3(handler.cloudDeletable(), true)!.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected directories deleted from S3')),
        );
      }
    },
  );

  static DirectoriesContextOption deleteAll(
    DirectoriesContextActionHandler handler,
    BuildContext context,
    Function() clearSelection,
  ) => DirectoriesContextOption(
    title: 'Delete Selection',
    icon: Icons.delete_sweep,
    action: () async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Selected Directories'),
          content: const Text(
            'Are you sure you want to delete the selected directories from your device and S3? This action cannot be undone.',
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
        handler.delete(true)!.call();
        clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected directories deleted from device and S3'),
          ),
        );
      }
    },
  );

  static List<DirectoriesContextOption> allOptions(
    BuildContext context,
    DirectoriesContextActionHandler handler,
    Function(RemoteFile?) cutKey,
    Function(RemoteFile?) copyKey,
    Function() clearSelection,
  ) {
    return [
      downloadAll(handler),
      saveAllTo(handler, context),
      cut(cutKey),
      copy(copyKey),
      if (handler.removableFiles().isNotEmpty) deleteUploaded(handler, context),
      if (handler.directories.every(
        (dir) =>
            p.split(dir.key).length == 1 ||
            Main.backupMode(dir.key) == BackupMode.upload,
      ))
        deleteS3(handler, context),
      deleteLocal(handler, context),
      deleteAll(handler, context, clearSelection),
    ];
  }

  DirectoriesContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
  });
}

class BulkContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function(BuildContext context)? action;

  static BulkContextOption downloadAll(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
  ) => BulkContextOption(
    title:
        directoriesHandler.download() != null || filesHandler.download() != null
        ? 'Download'
        : 'Cannot Download',
    subtitle:
        directoriesHandler.download() == null && filesHandler.download() == null
        ? 'Set backup directory to enable downloads'
        : 'Only missing files with backup directory set will be downloaded',
    icon:
        directoriesHandler.download() == null && filesHandler.download() == null
        ? Icons.file_download_off
        : Icons.file_download_outlined,
    action:
        directoriesHandler.download() != null || filesHandler.download() != null
        ? (BuildContext context) {
            if (directoriesHandler.download() != null) {
              directoriesHandler.download()!();
            }
            if (filesHandler.download() != null) {
              filesHandler.download()!();
            }
          }
        : null,
  );

  static BulkContextOption saveAllTo(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
  ) => BulkContextOption(
    title: 'Save To...',
    icon: Icons.save_as,
    action: (BuildContext context) async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      bool saved = false;
      for (final handler in [directoriesHandler, filesHandler]) {
        late String Function()? handle;
        if (handler is FileContextActionHandler) {
          handle = handler.saveAs(
            directory == null
                ? null
                : p.join(directory, handler.file.key.split('/').last),
          );
        } else {
          handle = handler.saveAs(
            directory == null
                ? null
                : p.join(
                    directory,
                    p.basename(
                      (handler as DirectoryContextActionHandler).file.key,
                    ),
                  ),
          );
        }
        if (handle != null) {
          handle();
          saved = true;
        }
      }
      if (saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saving items to $directory')));
      }
    },
  );

  static BulkContextOption cut(Function(RemoteFile?) cutKey) =>
      BulkContextOption(
        title: 'Move To...',
        icon: Icons.cut,
        action: (BuildContext context) {
          cutKey(null);
        },
      );

  static BulkContextOption copy(Function(RemoteFile?) copyKey) =>
      BulkContextOption(
        title: 'Copy To...',
        icon: Icons.copy,
        action: (BuildContext context) {
          copyKey(null);
        },
      );

  static BulkContextOption deleteUploaded(
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
  ) => BulkContextOption(
    title: 'Delete Uploaded Copies',
    subtitle: 'Delete local copies of uploaded items only',
    icon: Icons.delete_sweep,
    action: (BuildContext context) async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Uploaded Copies'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Are you sure you want to delete the local copies of the uploaded items? This action cannot be undone.',
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
                        for (final file in [
                          ...directoriesHandler.removableFiles(),
                          ...filesHandler.removableFiles(),
                        ])
                          Text(Main.pathFromKey(file.key) ?? file.key),
                        if (directoriesHandler.removableFiles().isEmpty &&
                            filesHandler.removableFiles().isEmpty)
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
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes ?? false) {
        directoriesHandler
            .deleteUploaded(directoriesHandler.removableFiles(), true)!
            .call();
        filesHandler
            .deleteUploaded(filesHandler.removableFiles(), true)!
            .call();
        ScaffoldMessenger.of(context).showSnackBar(
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
    subtitle: 'Delete from device only',
    icon: Icons.delete_outline,
    action: (BuildContext context) async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Local Copies'),
          content: const Text(
            'Are you sure you want to delete the local copies of the selected items? This action cannot be undone.',
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
        for (final handler in [directoriesHandler, filesHandler]) {
          handler.deleteLocal(true)!.call();
        }
        ScaffoldMessenger.of(context).showSnackBar(
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
    title: 'Delete Selection',
    icon: Icons.delete_sweep,
    action: (BuildContext context) async {
      final yes =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Selected Items'),
              content: const Text(
                'Are you sure you want to delete the selected items from your device and S3? This action cannot be undone.',
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
          handler.delete(true)!.call();
        }
        clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected items deleted from device and S3'),
          ),
        );
      }
    },
  );

  static List<BulkContextOption> allOptions(
    Function(RemoteFile?) cutKey,
    Function(RemoteFile?) copyKey,
    DirectoriesContextActionHandler directoriesHandler,
    FilesContextActionHandler filesHandler,
    BuildContext context,
    Function() clearSelection,
  ) {
    return [
      downloadAll(directoriesHandler, filesHandler),
      saveAllTo(directoriesHandler, filesHandler, context),
      cut(cutKey),
      copy(copyKey),
      if (directoriesHandler.removableFiles().isNotEmpty ||
          filesHandler.removableFiles().isNotEmpty)
        deleteUploaded(directoriesHandler, filesHandler, context),
      deleteLocalAll(directoriesHandler, filesHandler, context),
      deleteAll(directoriesHandler, filesHandler, context, clearSelection),
    ];
  }

  BulkContextOption({
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
  });
}

Widget buildFileContextMenu(
  BuildContext context,
  RemoteFile item,
  String? Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile) cut,
  Function(RemoteFile) copy,
  Future<void> Function(List<String>, List<String>) moveFiles,
  Function(String) deleteLocal,
  Future<void> Function(List<String>) deleteFiles,
) {
  FileContextActionHandler handler = FileContextActionHandler(
    file: item,
    getLink: getLink,
    downloadFile: downloadFile,
    saveFile: saveFile,
    moveFiles: moveFiles,
    deleteLocalFile: deleteLocal,
    deleteFiles: deleteFiles,
  );
  return ListView(
    children:
        <Widget>[
              ListTile(
                visualDensity: VisualDensity.comfortable,
                leading: Icon(Icons.insert_drive_file_rounded),
                title: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(item.key),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(timeToReadable(item.lastModified!)),
                          const SizedBox(width: 8),
                          Text(bytesToReadable(item.size)),
                          const SizedBox(width: 8),
                          Text(
                            item.key.split('.').length > 1
                                ? '.${item.key.split('.').last}'
                                : '',
                          ),
                        ],
                      ),
                    ),
                    Text('MD5: ${item.etag}'),
                  ],
                ),
              ),
            ]
            .followedBy(
              FileContextOption.allOptions(context, handler, cut, copy).map(
                (option) => ListTile(
                  visualDensity: VisualDensity.comfortable,
                  leading: Icon(option.icon),
                  title: Text(option.title),
                  subtitle: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: option.subtitle != null
                        ? Text(option.subtitle!)
                        : null,
                  ),
                  onTap: option.action == null
                      ? null
                      : () async {
                          await option.action!();
                          Navigator.of(context).pop();
                        },
                ),
              ),
            )
            .toList(),
  );
}

Widget buildFilesContextMenu(
  BuildContext context,
  List<RemoteFile> items,
  String? Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile?) cut,
  Function(RemoteFile?) copy,
  Future<void> Function(List<String>, List<String>) moveFiles,
  Function(String) deleteLocal,
  Future<void> Function(List<String>) deleteS3Files,
  Future<void> Function(List<String>) deleteFiles,
  Function() clearSelection,
) {
  FilesContextActionHandler handler = FilesContextActionHandler(
    files: items,
    getLink: getLink,
    downloadFile: downloadFile,
    saveFile: saveFile,
    moveFiles: moveFiles,
    deleteLocalFile: deleteLocal,
    deleteS3Files: deleteS3Files,
    deleteFiles: deleteFiles,
  );
  return ListView(
    children:
        FilesContextOption.allOptions(
              context,
              handler,
              cut,
              copy,
              clearSelection,
            )
            .map(
              (option) => ListTile(
                leading: Icon(option.icon),
                title: Text(option.title),
                subtitle: option.subtitle != null
                    ? Text(option.subtitle!)
                    : null,
                onTap: option.action != null
                    ? () async {
                        await option.action!();
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
            )
            .toList(),
  );
}

Widget buildDirectoryContextMenu(
  BuildContext context,
  RemoteFile file,
  Function(RemoteFile) downloadDirectory,
  Function(RemoteFile, String) saveDirectory,
  Function(RemoteFile) cut,
  Function(RemoteFile) copy,
  Future<void> Function(List<String>, List<String>) moveDirectories,
  Function(String) deleteLocal,
  Future<void> Function(List<String>) deleteS3,
  Future<void> Function(List<String>) deleteDirectories,
  (int, int) Function(RemoteFile, {bool recursive}) countContent,
  int Function(RemoteFile) dirSize,
  String Function(RemoteFile) dirModified,
  Function(String, BackupMode) setBackupMode,
) {
  DirectoryContextActionHandler handler = DirectoryContextActionHandler(
    file: file,
    downloadDirectory: downloadDirectory,
    saveDirectory: saveDirectory,
    moveDirectories: moveDirectories,
    deleteLocalDirectory: deleteLocal,
    deleteS3Directories: deleteS3,
    deleteDirectories: deleteDirectories,
  );
  return ListView(
    children:
        <Widget>[
              ListTile(
                visualDensity: VisualDensity.comfortable,
                leading: Icon(Icons.insert_drive_file_rounded),
                title: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(file.key),
                ),
                subtitle: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(dirModified(file)),
                      SizedBox(width: 8),
                      Text(bytesToReadable(dirSize(file))),
                      SizedBox(width: 8),
                      Text(() {
                        final count = countContent(file, recursive: true);
                        if (count.$1 == 0) {
                          return '${count.$2} files';
                        }
                        if (count.$2 == 0) {
                          return '${count.$1} subfolders';
                        }
                        return '${count.$2} files in ${count.$1} subfolders';
                      }()),
                    ],
                  ),
                ),
              ),
              if (p.split(file.key).length == 1)
                ListTile(
                  leading: const Icon(Icons.drive_folder_upload),
                  title: const Text('Backup From'),
                  subtitle: Text(
                    Main.pathFromKey(file.key) == null
                        ? 'Not set'
                        : Main.pathFromKey(file.key)!,
                  ),
                  onTap: () async {
                    final String? directoryPath = await getDirectoryPath();
                    if (directoryPath != null) {
                      if (!IniManager.config!.sections().contains(
                        'directories',
                      )) {
                        IniManager.config!.addSection('directories');
                      }
                      IniManager.config!.set(
                        'directories',
                        file.key,
                        directoryPath,
                      );
                      IniManager.save();
                      Main.listDirectories();
                      Navigator.of(context).pop();
                    }
                  },
                ),
              if (p.isAbsolute(Main.pathFromKey(file.key) ?? file.key) &&
                  p.split(file.key).length == 1) ...[
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Backup Mode'),
                ),
                RadioGroup(
                  groupValue: Main.backupMode(file.key),
                  onChanged: (s) {
                    setBackupMode(file.key, s!);
                    Navigator.of(context).pop();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile(
                        value: BackupMode.upload,
                        title: Text(BackupMode.upload.name),
                        subtitle: Text(BackupMode.upload.description),
                        dense: true,
                      ),
                      RadioListTile(
                        value: BackupMode.sync,
                        title: Text(BackupMode.sync.name),
                        subtitle: Text(BackupMode.sync.description),
                        dense: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ]
            .followedBy(
              DirectoryContextOption.allOptions(
                context,
                handler,
                cut,
                copy,
              ).map(
                (option) => ListTile(
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
                          await option.action!();
                          Navigator.of(context).pop();
                        }
                      : null,
                ),
              ),
            )
            .toList(),
  );
}

Widget buildDirectoriesContextMenu(
  BuildContext context,
  List<RemoteFile> dirs,
  Function(RemoteFile) downloadDirectory,
  Function(RemoteFile, String) saveDirectory,
  Function(RemoteFile?) cut,
  Function(RemoteFile?) copy,
  Future<void> Function(List<String>, List<String>) moveDirectories,
  Function(String) deleteLocal,
  Future<void> Function(List<String>) deleteS3,
  Future<void> Function(List<String>) deleteDirectories,
  Function() clearSelection,
) {
  DirectoriesContextActionHandler handler = DirectoriesContextActionHandler(
    directories: dirs,
    downloadDirectory: downloadDirectory,
    saveDirectory: saveDirectory,
    moveDirectories: moveDirectories,
    deleteLocalDirectory: deleteLocal,
    deleteS3Directories: deleteS3,
    deleteDirectories: deleteDirectories,
  );
  return ListView(
    children:
        DirectoriesContextOption.allOptions(
              context,
              handler,
              cut,
              copy,
              clearSelection,
            )
            .map(
              (option) => ListTile(
                leading: Icon(option.icon),
                title: Text(option.title),
                subtitle: option.subtitle != null
                    ? Text(option.subtitle!)
                    : null,
                onTap: option.action != null
                    ? () async {
                        await option.action!();
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
            )
            .toList(),
  );
}

Widget buildBulkContextMenu(
  BuildContext context,
  List<RemoteFile> items,
  String? Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(RemoteFile) downloadDirectory,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile, String) saveDirectory,
  Future<void> Function(List<String>, List<String>) moveFiles,
  Future<void> Function(List<String>, List<String>) moveDirectories,
  Function(RemoteFile?) cut,
  Function(RemoteFile?) copy,
  Function(String) deleteLocal,
  Future<void> Function(List<String>) deleteS3,
  Future<void> Function(List<String>) deleteFiles,
  Future<void> Function(List<String>) deleteDirectories,
  Function() clearSelection,
) {
  if (!items.any((item) => item.key.endsWith('/'))) {
    return buildFilesContextMenu(
      context,
      items.cast<RemoteFile>(),
      getLink,
      downloadFile,
      saveFile,
      cut,
      copy,
      moveFiles,
      deleteLocal,
      deleteS3,
      deleteFiles,
      clearSelection,
    );
  } else if (items.every((item) => item.key.endsWith('/'))) {
    return buildDirectoriesContextMenu(
      context,
      items,
      downloadDirectory,
      saveDirectory,
      cut,
      copy,
      moveDirectories,
      deleteLocal,
      deleteS3,
      deleteDirectories,
      clearSelection,
    );
  } else {
    DirectoriesContextActionHandler dirHandler =
        DirectoriesContextActionHandler(
          directories: items.where((item) => item.key.endsWith('/')).toList(),
          downloadDirectory: downloadDirectory,
          saveDirectory: saveDirectory,
          moveDirectories: moveDirectories,
          deleteLocalDirectory: deleteLocal,
          deleteS3Directories: deleteS3,
          deleteDirectories: deleteDirectories,
        );
    FilesContextActionHandler fileHandler = FilesContextActionHandler(
      files: items.where((item) => !item.key.endsWith('/')).toList(),
      getLink: getLink,
      downloadFile: downloadFile,
      saveFile: saveFile,
      moveFiles: moveFiles,
      deleteLocalFile: deleteLocal,
      deleteS3Files: deleteS3,
      deleteFiles: deleteFiles,
    );
    return ListView(
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
                (option) => ListTile(
                  leading: Icon(option.icon),
                  title: Text(option.title),
                  subtitle: option.subtitle != null
                      ? Text(option.subtitle!)
                      : null,
                  onTap: option.action != null
                      ? () async {
                          await option.action!(context);
                          Navigator.of(context).pop();
                        }
                      : null,
                ),
              )
              .toList(),
    );
  }
}
