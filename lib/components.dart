import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:open_file/open_file.dart';
import 'package:s3_drive/services/job.dart';
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
            ? a.file!.lastModified
            : DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bDate = b.file != null
            ? b.file!.lastModified
            : DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      case SortMode.dateDesc:
        DateTime aDate = a.file != null
            ? a.file!.lastModified
            : DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bDate = b.file != null
            ? b.file!.lastModified
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

class SnapHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  SnapHeaderDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(elevation: overlapsContent ? 4 : 0, child: child);
  }

  @override
  bool shouldRebuild(covariant SnapHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

abstract class ContextActionHandler {
  ContextActionHandler();

  void Function()? download();
  String Function()? saveAs(String? path);
  Future<String> Function() rename(String newName);
  Future<String> Function()? delete(bool? yes);
}

class FileContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final String Function(RemoteFile, int?) getLink;
  final Function(RemoteFile, String) saveFile;
  final Function(String, String) moveFile;
  final Function(String) deleteFile;

  FileContextActionHandler({
    required this.file,
    required this.getLink,
    required this.saveFile,
    required this.moveFile,
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
            Main.downloadFile(file);
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
        title: 'Open',
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
                  ? null
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
      deleteAll(context, handlers, clearSelection),
    ];
  }
}

class DirectoryContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final Function(RemoteFile) downloadDirectory;
  final Function(RemoteFile, String) saveDirectory;
  final Function(String, String) moveDirectory;
  final Function(String) deleteDirectory;

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

  DirectoryContextActionHandler({
    required this.file,
    required this.downloadDirectory,
    required this.saveDirectory,
    required this.moveDirectory,
    required this.deleteDirectory,
  });
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
            : null,
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
      delete(context, handler),
    ];
  }
}

class DirectoriesContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function(BuildContext context)? action;

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
        ? (BuildContext context) {
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
    action: (BuildContext context) async {
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
        action: (BuildContext context) {
          cutKey(null);
        },
      );

  static DirectoriesContextOption copy(Function(RemoteFile?) copyKey) =>
      DirectoriesContextOption(
        title: 'Copy To...',
        icon: Icons.folder_copy,
        action: (BuildContext context) {
          copyKey(null);
        },
      );

  static DirectoriesContextOption deleteAll(
    List<DirectoryContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
  ) => DirectoriesContextOption(
    title: 'Delete Selection',
    icon: Icons.delete_sweep,
    action: (BuildContext context) async {
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
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile) cut,
  Function(RemoteFile) copy,
  Function(String, String) moveFile,
  Function(String) deleteFile,
) {
  FileContextActionHandler handler = FileContextActionHandler(
    file: item,
    getLink: getLink,
    saveFile: saveFile,
    moveFile: moveFile,
    deleteFile: deleteFile,
  );
  return ListView(
    children:
        FileContextOption.allOptions(context, handler, cut, copy, deleteFile)
            .map(
              (option) => ListTile(
                leading: Icon(option.icon),
                title: Text(option.title),
                subtitle: option.subtitle != null
                    ? Text(option.subtitle!)
                    : null,
                onTap: option.action == null
                    ? null
                    : () async {
                        await option.action!();
                        Navigator.of(context).pop();
                      },
              ),
            )
            .toList(),
  );
}

Widget buildFilesContextMenu(
  BuildContext context,
  List<RemoteFile> items,
  String Function(RemoteFile, int?) getLink,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile?) cut,
  Function(RemoteFile?) copy,
  Function(String, String) moveFile,
  Function(String) deleteFile,
  Function() clearSelection,
) {
  List<FileContextActionHandler> handlers = items
      .map(
        (item) => FileContextActionHandler(
          file: item,
          getLink: getLink,
          saveFile: saveFile,
          moveFile: moveFile,
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
  Function(String) deleteDirectory,
) {
  DirectoryContextActionHandler handler = DirectoryContextActionHandler(
    file: file,
    downloadDirectory: downloadDirectory,
    saveDirectory: saveDirectory,
    moveDirectory: moveDirectory,
    deleteDirectory: deleteDirectory,
  );
  return ListView(
    children: DirectoryContextOption.allOptions(context, handler, cut, copy)
        .map(
          (option) => ListTile(
            leading: Icon(option.icon),
            title: Text(option.title),
            subtitle: option.subtitle != null ? Text(option.subtitle!) : null,
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

Widget buildDirectoriesContextMenu(
  BuildContext context,
  List<RemoteFile> dirs,
  Function(RemoteFile) downloadDirectory,
  Function(RemoteFile, String) saveDirectory,
  Function(RemoteFile?) cut,
  Function(RemoteFile?) copy,
  Function(String, String) moveDirectory,
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
                        await option.action!(context);
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
  Function(RemoteFile) downloadDirectory,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile, String) saveDirectory,
  Function(String, String) moveFile,
  Function(String, String) moveDirectory,
  Function(RemoteFile?) cut,
  Function(RemoteFile?) copy,
  Function(String) deleteFile,
  Function(String) deleteDirectory,
  Function() clearSelection,
) {
  if (!items.any((item) => item.key.endsWith('/'))) {
    return buildFilesContextMenu(
      context,
      items.cast<RemoteFile>(),
      getLink,
      saveFile,
      cut,
      copy,
      moveFile,
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
      deleteDirectory,
      clearSelection,
    );
  } else {
    List<ContextActionHandler> handlers = items.map((item) {
      if (!item.key.endsWith('/')) {
        return FileContextActionHandler(
          file: item,
          getLink: getLink,
          saveFile: saveFile,
          moveFile: moveFile,
          deleteFile: deleteFile,
        );
      } else {
        return DirectoryContextActionHandler(
          file: item,
          downloadDirectory: downloadDirectory,
          saveDirectory: saveDirectory,
          moveDirectory: moveDirectory,
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
