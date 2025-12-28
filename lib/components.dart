import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:open_file/open_file.dart';
import 'package:s3_drive/services/ini_manager.dart';
import 'package:s3_drive/services/job.dart';
import 'package:s3_drive/services/models/backup_mode.dart';
import 'package:s3_drive/services/models/common.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:url_launcher/url_launcher.dart';

Future<int?> Function(BuildContext) expiryDialog = (BuildContext context) =>
    showDialog<int>(
      context: context,
      builder: (_) {
        int d = 0, h = 1;
        return StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: const Text('Select Validity Duration'),
            content: Row(
              children: [
                DropdownButton<int>(
                  value: d,
                  items: List.generate(
                    31,
                    (i) => DropdownMenuItem(value: i, child: Text('$i d')),
                  ),
                  onChanged: (v) => set(() => d = v!),
                ),
                DropdownButton<int>(
                  value: h,
                  items: List.generate(
                    24,
                    (i) => DropdownMenuItem(value: i, child: Text('$i h')),
                  ),
                  onChanged: (v) => set(() => h = v!),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: d * 86400 + h * 3600 == 0
                    ? null
                    : () => Navigator.pop(c, d * 86400 + h * 3600),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );

Future<String?> Function(BuildContext, String) renameDialog =
    (BuildContext context, String currentName) => showDialog<String>(
      context: context,
      builder: (_) {
        TextEditingController controller = TextEditingController(
          text: currentName,
        );
        return StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: const Text('Rename File'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'New Name'),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(c, controller.text.trim()),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );

String bytesToReadable(int bytes) {
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(2)} ${suffixes[i]}';
}

String _monthToString(int month) {
  return [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}

String timeToReadable(DateTime time) {
  final localTime = time.toLocal();
  final diff = DateTime.now().toLocal().difference(localTime);
  if (diff.inSeconds < 60) {
    return '${diff.inSeconds}s ago';
  } else if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  return "${localTime.day.toString().padLeft(2, '0')} ${_monthToString(localTime.month)} ${localTime.year} ${(localTime.hour % 12).toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')} ${localTime.hour >= 12 ? 'PM' : 'AM'}";
}

List<FileProps> sort(
  Iterable<FileProps> items,
  SortMode sortMode,
  bool foldersFirst,
) {
  List<FileProps> sortedItems = List.from(items);
  sortedItems.sort((a, b) {
    var aIsDir = a.key.endsWith('/');
    var bIsDir = b.key.endsWith('/');

    if (foldersFirst) {
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
    }

    switch (sortMode) {
      case SortMode.nameAsc:
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      case SortMode.nameDesc:
        return b.key.toLowerCase().compareTo(a.key.toLowerCase());
      case SortMode.dateAsc:
        DateTime aDate = a.file != null
            ? a.file!.lastModified!
            : DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bDate = b.file != null
            ? b.file!.lastModified!
            : DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      case SortMode.dateDesc:
        DateTime aDate = a.file != null
            ? a.file!.lastModified!
            : DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bDate = b.file != null
            ? b.file!.lastModified!
            : DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      case SortMode.sizeAsc:
        return a.size.compareTo(b.size);
      case SortMode.sizeDesc:
        return b.size.compareTo(a.size);
      case SortMode.typeAsc:
        String aExt = a.key.contains('.')
            ? a.key.split('.').last.toLowerCase()
            : '';
        String bExt = b.key.contains('.')
            ? b.key.split('.').last.toLowerCase()
            : '';
        return aExt.compareTo(bExt);
      case SortMode.typeDesc:
        String aExt = a.key.contains('.')
            ? a.key.split('.').last.toLowerCase()
            : '';
        String bExt = b.key.contains('.')
            ? b.key.split('.').last.toLowerCase()
            : '';
        return bExt.compareTo(aExt);
    }
  });
  return sortedItems;
}

abstract class ContextActionHandler {
  ContextActionHandler();

  void Function()? download();
  String Function()? saveAs(String? path);
  Future<String> Function() rename(String newName);
  Future<String> Function()? deleteLocal(bool? yes);
  Future<String> Function()? delete(bool? yes);
}

class FileContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final String Function(RemoteFile, int?) getLink;
  final Function(RemoteFile) downloadFile;
  final Function(RemoteFile, String) saveFile;
  final Function(String, String) moveFile;
  final Function(String) deleteLocalFile;
  final Function(String) deleteFile;

  FileContextActionHandler({
    required this.file,
    required this.getLink,
    required this.downloadFile,
    required this.saveFile,
    required this.moveFile,
    required this.deleteLocalFile,
    required this.deleteFile,
  });

  bool rootExists() {
    return p.isAbsolute(Main.pathFromKey(file.key) ?? file.key);
  }

  dynamic Function() open() {
    return File(Main.pathFromKey(file.key) ?? file.key).existsSync()
        ? () {
            OpenFile.open(Main.pathFromKey(file.key) ?? file.key);
          }
        : () {
            launchUrl(Uri.parse(getLink(file, null)));
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
            saveFile(file, Main.pathFromKey(file.key) ?? file.key);
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

  Future<String> Function() getLinkToCopy(int? seconds) {
    return () async {
      return await getLink(file, seconds);
    };
  }

  @override
  Future<String> Function() rename(String newName) {
    return () async {
      final newKey = p.join(p.dirname(file.key), newName.replaceAll('/', '_'));
      await moveFile(file.key, newKey);
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
            await deleteFile(file.key);
            return 'Deleted ${file.key.split('/').last}';
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
            : 'Opens Link',
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
      Clipboard.setData(
        ClipboardData(
          text: await handler.getLinkToCopy(await expiryDialog(context))(),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File link copied to clipboard')),
      );
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
    Function(String) deleteFile,
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

  static FilesContextOption downloadAll(
    List<FileContextActionHandler> handlers,
  ) => FilesContextOption(
    title: handlers.every((handler) => handler.download() == null)
        ? handlers.every((handler) => handler.rootExists())
              ? 'Downloaded'
              : 'Cannot Download'
        : 'Download',
    subtitle: handlers.every((handler) => handler.download() == null)
        ? handlers.every((handler) => handler.rootExists())
              ? null
              : 'Set backup directory to enable downloads'
        : 'Only missing files will be downloaded',
    icon: handlers.every((handler) => handler.download() == null)
        ? handlers.every((handler) => handler.rootExists())
              ? Icons.file_download_done_rounded
              : Icons.file_download_off
        : Icons.file_download_outlined,
    action: handlers.every((handler) => handler.download() != null)
        ? () {
            for (final handler in handlers) {
              if (handler.download() != null) {
                handler.download()!();
              }
            }
          }
        : null,
  );

  static FilesContextOption saveAllTo(
    BuildContext context,
    List<FileContextActionHandler> handlers,
  ) => FilesContextOption(
    title: 'Save To...',
    icon: Icons.save_as,
    action: () async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      bool saved = false;
      for (final handler in handlers) {
        FileSaveLocation savePath = await Future.value(
          directory == null
              ? null
              : FileSaveLocation(
                  p.join(directory, handler.file.key.split('/').last),
                ),
        );
        if (handler.saveAs(savePath.path) != null) {
          handler.saveAs(savePath.path)!();
          saved = true;
        }
      }
      if (saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saving files to $directory')));
      }
    },
  );

  static FilesContextOption shareAll(List<FileContextActionHandler> handlers) =>
      FilesContextOption(
        title: handlers.any((handler) => handler.getXFile() != null)
            ? 'Share'
            : 'Cannot Share',
        icon: Icons.share,
        subtitle: handlers.every((handler) => handler.getXFile() != null)
            ? null
            : handlers.any((handler) => handler.getXFile() != null)
            ? 'Only downloaded files will be shared'
            : 'No downloaded files to share',
        action: handlers.any((handler) => handler.getXFile() != null)
            ? () {
                SharePlus.instance.share(
                  ShareParams(
                    files: handlers
                        .where((handler) => handler.getXFile() != null)
                        .map((handler) => handler.getXFile()!())
                        .toList(),
                  ),
                );
              }
            : null,
      );

  static FilesContextOption copyAllLinks(
    BuildContext context,
    List<FileContextActionHandler> handlers,
  ) => FilesContextOption(
    title: 'Copy Links',
    icon: Icons.link,
    action: () async {
      String allLinks = '';
      int? seconds = await expiryDialog(context);
      for (final handler in handlers) {
        allLinks += '${await handler.getLinkToCopy(seconds)()}\n\n';
      }
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

  static FilesContextOption deleteLocalAll(
    BuildContext context,
    List<FileContextActionHandler> handlers,
    Function() clearSelection,
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
        for (final handler in handlers) {
          handler.deleteLocal(true)!.call();
        }
        clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local copies of selected files deleted'),
          ),
        );
      }
    },
  );

  static FilesContextOption deleteAll(
    BuildContext context,
    List<FileContextActionHandler> handlers,
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
        for (final handler in handlers) {
          handler.delete(true)!.call();
        }
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
    List<FileContextActionHandler> handlers,
    Function(RemoteFile?) cutKey,
    Function(RemoteFile?) copyKey,
    Function(String) deleteFile,
    Function() clearSelection,
  ) {
    return [
      downloadAll(handlers),
      saveAllTo(context, handlers),
      shareAll(handlers),
      copyAllLinks(context, handlers),
      cut(cutKey),
      copy(copyKey),
      deleteLocalAll(context, handlers, clearSelection),
      deleteAll(context, handlers, clearSelection),
    ];
  }
}

class DirectoryContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final Function(RemoteFile) downloadDirectory;
  final Function(RemoteFile, String) saveDirectory;
  final Function(String, String) moveDirectory;
  final Function(String) deleteLocalDirectory;
  final Function(String) deleteDirectory;

  DirectoryContextActionHandler({
    required this.file,
    required this.downloadDirectory,
    required this.saveDirectory,
    required this.moveDirectory,
    required this.deleteLocalDirectory,
    required this.deleteDirectory,
  });

  List<RemoteFile> removableFiles() {
    return Main.remoteFiles
        .where(
          (f) =>
              p.isWithin(file.key, f.key) &&
              !f.key.endsWith('/') &&
              File(Main.pathFromKey(file.key) ?? file.key).existsSync() &&
              Main.backupMode(file.key) == BackupMode.upload,
        )
        .toList();
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
            saveDirectory(file, Main.pathFromKey(file.key) ?? file.key);
            return 'Saving to $path';
          };
  }

  @override
  Future<String> Function() rename(String newName) {
    return () async {
      final key = file.key.endsWith('/') ? file.key : '${file.key}/';
      final newKey = '${p.dirname(key)}/${newName.replaceAll('/', '_')}/';
      await moveDirectory(key, newKey);
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

  @override
  Future<String> Function()? delete(bool? yes) {
    return yes ?? false
        ? () async {
            final key = file.key.endsWith('/') ? file.key : '${file.key}/';
            deleteDirectory(key);
            return 'Deleted ${p.basename(key)}';
          }
        : null;
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
      if (p.split(handler.file.key).length > 1) ...[
        cut(handler, cutKey),
        copy(handler, copyKey),
        rename(context, handler),
      ],
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
    List<DirectoryContextActionHandler> handlers,
  ) => DirectoriesContextOption(
    title: handlers.any((handler) => handler.download() == null)
        ? 'Cannot Download'
        : 'Download',
    subtitle: handlers.any((handler) => handler.download() == null)
        ? 'Set backup directory to enable downloads'
        : 'Only missing files will be downloaded',
    icon: handlers.any((handler) => handler.download() == null)
        ? Icons.file_download_off
        : Icons.file_download_outlined,
    action: handlers.any((handler) => handler.download() != null)
        ? () {
            for (final handler in handlers) {
              if (handler.download() != null) {
                handler.download();
              }
            }
          }
        : null,
  );

  static DirectoriesContextOption saveAllTo(
    List<DirectoryContextActionHandler> handlers,
    BuildContext context,
  ) => DirectoriesContextOption(
    title: 'Save To...',
    icon: Icons.save_as,
    action: () async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      bool saved = false;
      for (final handler in handlers) {
        final handle = handler.saveAs(directory);
        if (handle != null) {
          handle();
          saved = true;
        }
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
    List<DirectoryContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
  ) => DirectoriesContextOption(
    title: 'Delete Uploaded Files',
    subtitle: 'Delete local copies of uploaded files only',
    icon: Icons.delete_sweep,
    action: handlers.any((handler) => handler.removableFiles().isNotEmpty)
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
                              for (final file
                                  in handlers
                                      .expand(
                                        (handler) => handler.removableFiles(),
                                      )
                                      .toSet())
                                Text(Main.pathFromKey(file.key) ?? file.key),
                              if (handlers.every(
                                (handler) => handler.removableFiles().isEmpty,
                              ))
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
                    onPressed:
                        handlers.any(
                          (handler) => handler.removableFiles().isNotEmpty,
                        )
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (yes ?? false) {
              for (final handler in handlers) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      await handler.deleteUploaded(
                        handlers
                            .expand((handler) => handler.removableFiles())
                            .toSet()
                            .toList(),
                        true,
                      )!(),
                    ),
                  ),
                );
              }
            }
          }
        : null,
  );

  static DirectoriesContextOption deleteLocal(
    List<DirectoryContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
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
        for (final handler in handlers) {
          handler.deleteLocal(true)!.call();
        }
        clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local copies of selected directories deleted'),
          ),
        );
      }
    },
  );

  static DirectoriesContextOption deleteAll(
    List<DirectoryContextActionHandler> handlers,
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
        for (final handler in handlers) {
          handler.delete(true)!.call();
        }
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
    List<DirectoryContextActionHandler> handlers,
    Function(RemoteFile?) cutKey,
    Function(RemoteFile?) copyKey,
    Function() clearSelection,
  ) {
    return [
      downloadAll(handlers),
      saveAllTo(handlers, context),
      cut(cutKey),
      copy(copyKey),
      deleteUploaded(handlers, context, clearSelection),
      deleteLocal(handlers, context, clearSelection),
      deleteAll(handlers, context, clearSelection),
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

  static BulkContextOption downloadAll(List<ContextActionHandler> handlers) =>
      BulkContextOption(
        title: handlers.every((handler) => handler.download() == null)
            ? 'Cannot Download'
            : 'Download',
        subtitle: handlers.every((handler) => handler.download() == null)
            ? 'Set backup directory to enable downloads'
            : 'Only missing items will be downloaded',
        icon: handlers.every((handler) => handler.download() == null)
            ? Icons.file_download_off
            : Icons.file_download_outlined,
        action: handlers.any((handler) => handler.download() != null)
            ? (BuildContext context) {
                for (final handler in handlers) {
                  handler.download()!();
                }
              }
            : null,
      );

  static BulkContextOption saveAllTo(
    List<ContextActionHandler> handlers,
    BuildContext context,
  ) => BulkContextOption(
    title: 'Save To...',
    icon: Icons.save_as,
    action: (BuildContext context) async {
      final directory = await getDirectoryPath(canCreateDirectories: true);
      bool saved = false;
      for (final handler in handlers) {
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

  static BulkContextOption deleteLocalAll(
    List<ContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
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
        for (final handler in handlers) {
          handler.deleteLocal(true)!.call();
        }
        clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local copies of selected items deleted'),
          ),
        );
      }
    },
  );

  static BulkContextOption deleteAll(
    List<ContextActionHandler> handlers,
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
        for (final handler in handlers) {
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
    List<ContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
  ) {
    return [
      downloadAll(handlers),
      saveAllTo(handlers, context),
      cut(cutKey),
      copy(copyKey),
      deleteLocalAll(handlers, context, clearSelection),
      deleteAll(handlers, context, clearSelection),
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
  String Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile) cut,
  Function(RemoteFile) copy,
  Function(String, String) moveFile,
  Function(String) deleteLocal,
  Function(String) deleteFile,
) {
  FileContextActionHandler handler = FileContextActionHandler(
    file: item,
    getLink: getLink,
    downloadFile: downloadFile,
    saveFile: saveFile,
    moveFile: moveFile,
    deleteLocalFile: deleteLocal,
    deleteFile: deleteFile,
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
              FileContextOption.allOptions(
                context,
                handler,
                cut,
                copy,
                deleteFile,
              ).map(
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
  String Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile?) cut,
  Function(RemoteFile?) copy,
  Function(String, String) moveFile,
  Function(String) deleteLocal,
  Function(String) deleteFile,
  Function() clearSelection,
) {
  List<FileContextActionHandler> handlers = items
      .map(
        (item) => FileContextActionHandler(
          file: item,
          getLink: getLink,
          downloadFile: downloadFile,
          saveFile: saveFile,
          moveFile: moveFile,
          deleteLocalFile: deleteLocal,
          deleteFile: deleteFile,
        ),
      )
      .toList();
  return ListView(
    children:
        FilesContextOption.allOptions(
              context,
              handlers,
              cut,
              copy,
              deleteFile,
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
  Function(String, String) moveDirectory,
  Function(String) deleteLocal,
  Function(String) deleteDirectory,
  (int, int) Function(RemoteFile, {bool recursive}) countContent,
  int Function(RemoteFile) dirSize,
  String Function(RemoteFile) dirModified,
  Function(String, BackupMode) setBackupMode,
) {
  DirectoryContextActionHandler handler = DirectoryContextActionHandler(
    file: file,
    downloadDirectory: downloadDirectory,
    saveDirectory: saveDirectory,
    moveDirectory: moveDirectory,
    deleteLocalDirectory: deleteLocal,
    deleteDirectory: deleteDirectory,
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
  Function(String, String) moveDirectory,
  Function(String) deleteLocal,
  Function(String) deleteDirectory,
  Function() clearSelection,
) {
  List<DirectoryContextActionHandler> handlers = dirs
      .map(
        (dir) => DirectoryContextActionHandler(
          file: dir,
          downloadDirectory: downloadDirectory,
          saveDirectory: saveDirectory,
          moveDirectory: moveDirectory,
          deleteLocalDirectory: deleteLocal,
          deleteDirectory: deleteDirectory,
        ),
      )
      .toList();
  return ListView(
    children:
        DirectoriesContextOption.allOptions(
              context,
              handlers,
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
  String Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(RemoteFile) downloadDirectory,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile, String) saveDirectory,
  Function(String, String) moveFile,
  Function(String, String) moveDirectory,
  Function(RemoteFile?) cut,
  Function(RemoteFile?) copy,
  Function(String) deleteLocal,
  Function(String) deleteFile,
  Function(String) deleteDirectory,
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
      moveFile,
      deleteLocal,
      deleteFile,
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
      moveDirectory,
      deleteLocal,
      deleteDirectory,
      clearSelection,
    );
  } else {
    List<ContextActionHandler> handlers = items.map((item) {
      if (!item.key.endsWith('/')) {
        return FileContextActionHandler(
          file: item,
          getLink: getLink,
          downloadFile: downloadFile,
          saveFile: saveFile,
          moveFile: moveFile,
          deleteLocalFile: deleteLocal,
          deleteFile: deleteFile,
        );
      } else {
        return DirectoryContextActionHandler(
          file: item,
          downloadDirectory: downloadDirectory,
          saveDirectory: saveDirectory,
          moveDirectory: moveDirectory,
          deleteLocalDirectory: deleteLocal,
          deleteDirectory: deleteDirectory,
        );
      }
    }).toList();
    return ListView(
      children:
          BulkContextOption.allOptions(
                cut,
                copy,
                handlers,
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
