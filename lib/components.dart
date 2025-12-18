import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:open_file/open_file.dart';
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
            content: Row(children: [
              DropdownButton<int>(
                value: d,
                items: List.generate(
                    31, (i) => DropdownMenuItem(value: i, child: Text('$i d'))),
                onChanged: (v) => set(() => d = v!),
              ),
              DropdownButton<int>(
                value: h,
                items: List.generate(
                    24, (i) => DropdownMenuItem(value: i, child: Text('$i h'))),
                onChanged: (v) => set(() => h = v!),
              ),
            ]),
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
            TextEditingController controller =
                TextEditingController(text: currentName);
            return StatefulBuilder(
              builder: (c, set) => AlertDialog(
                title: const Text('Rename File'),
                content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'New Name',
                  ),
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

abstract class ContextActionHandler {
  final String localRoot;

  ContextActionHandler({
    required this.localRoot,
  });

  void Function()? download();
  String Function()? saveAs(String? path);
  Future<String> Function() rename(String newName);
  Future<String> Function()? delete(bool? yes);
}

class FileContextActionHandler extends ContextActionHandler {
  final RemoteFile file;
  final Future<String> Function(RemoteFile, int?) getLink;
  final Function(RemoteFile) downloadFile;
  final Function(RemoteFile, String) saveFile;
  final Function(String, String) moveFile;
  final Function(String) deleteFile;

  FileContextActionHandler({
    required super.localRoot,
    required this.file,
    required this.getLink,
    required this.downloadFile,
    required this.saveFile,
    required this.moveFile,
    required this.deleteFile,
  });

  bool rootExists() {
    return localRoot.isNotEmpty;
  }

  dynamic Function() open() {
    return File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
            .existsSync()
        ? () {
            OpenFile.open(
                p.join(localRoot, file.key.split('/').sublist(1).join('/')));
          }
        : () async {
            launchUrl(Uri.parse(await getLink(file, null)));
          };
  }

  @override
  void Function()? download() {
    return localRoot.isEmpty ||
            File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
                .existsSync()
        ? null
        : () {
            downloadFile(file);
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path != null
        ? () {
            saveFile(
              file,
              p.join(localRoot, file.key.split('/').sublist(1).join('/')),
            );
            return 'Saving to $path';
          }
        : null;
  }

  XFile Function()? getXFile() {
    return File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
            .existsSync()
        ? () {
            return XFile(
                p.join(localRoot, file.key.split('/').sublist(1).join('/')));
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

  static FileContextOption open(
    FileContextActionHandler handler,
  ) =>
      FileContextOption(
        title: 'Open',
        icon: Icons.open_in_new,
        action: handler.open(),
      );

  static FileContextOption download(
    FileContextActionHandler handler,
  ) =>
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
    RemoteFile file,
    FileContextActionHandler handler,
    BuildContext context,
  ) =>
      FileContextOption(
        title: 'Save As...',
        icon: Icons.save_as,
        action: () async {
          final String Function()? handle = handler.saveAs(
            (await getSaveLocation(
              suggestedName: file.key.split('/').last,
              canCreateDirectories: true,
            ))
                ?.path,
          );
          if (handle != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(handle()),
              ),
            );
          }
        },
      );

  static FileContextOption share(
    FileContextActionHandler handler,
  ) =>
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
                    ShareParams(
                      files: <XFile>[
                        handle(),
                      ],
                    ),
                  );
                }
              : null;
        }(),
      );

  static FileContextOption copyLink(
    FileContextActionHandler handler,
    BuildContext context,
  ) =>
      FileContextOption(
        title: 'Copy Link',
        icon: Icons.link,
        action: () async {
          Clipboard.setData(ClipboardData(
              text:
                  await handler.getLinkToCopy(await expiryDialog(context))()));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File link copied to clipboard')),
          );
        },
      );

  static FileContextOption cut(
      FileContextActionHandler handler, Function(RemoteFile) cutKey) {
    return FileContextOption(
      title: 'Move To...',
      icon: Icons.cut,
      action: () {
        cutKey(handler.file);
      },
    );
  }

  static FileContextOption copy(
      FileContextActionHandler handler, Function(RemoteFile) copyKey) {
    return FileContextOption(
      title: 'Copy To...',
      icon: Icons.file_copy_rounded,
      action: () {
        copyKey(handler.file);
      },
    );
  }

  static FileContextOption rename(
    RemoteFile file,
    FileContextActionHandler handler,
    BuildContext context,
  ) =>
      FileContextOption(
        title: 'Rename',
        icon: Icons.edit,
        action: () async {
          final newName = await renameDialog(context, file.key.split('/').last);
          if (newName != null &&
              newName.isNotEmpty &&
              newName != file.key.split('/').last) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(await handler.rename(newName)()),
              ),
            );
          }
        },
      );

  static FileContextOption delete(
    RemoteFile file,
    FileContextActionHandler handler,
    BuildContext context,
  ) =>
      FileContextOption(
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
                  'Are you sure you want to delete ${file.key.split('/').last} from your device and S3? This action cannot be undone.',
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(await handle()),
              ),
            );
          }
        },
      );

  static List<FileContextOption> allOptions(
    String localRoot,
    RemoteFile file,
    Function(RemoteFile) cutKey,
    Function(RemoteFile) copyKey,
    Function(String) deleteFile,
    FileContextActionHandler handler,
    BuildContext context,
  ) {
    return [
      open(handler),
      download(handler),
      saveAs(file, handler, context),
      share(handler),
      copyLink(handler, context),
      cut(handler, cutKey),
      copy(handler, copyKey),
      rename(file, handler, context),
      delete(file, handler, context),
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
  ) =>
      FilesContextOption(
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
    List<FileContextActionHandler> handlers,
    BuildContext context,
  ) =>
      FilesContextOption(
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saving files to $directory'),
              ),
            );
          }
        },
      );

  static FilesContextOption shareAll(
    List<FileContextActionHandler> handlers,
  ) =>
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
                        .map(
                          (handler) => handler.getXFile()!(),
                        )
                        .toList(),
                  ),
                );
              }
            : null,
      );

  static FilesContextOption copyAllLinks(
    List<FileContextActionHandler> handlers,
    BuildContext context,
  ) =>
      FilesContextOption(
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

  static FilesContextOption cut(
    Function(RemoteFile?) cutKey,
  ) =>
      FilesContextOption(
        title: 'Move To...',
        icon: Icons.cut,
        action: () {
          cutKey(null);
        },
      );

  static FilesContextOption copy(
    Function(RemoteFile?) copyKey,
  ) =>
      FilesContextOption(
        title: 'Copy To...',
        icon: Icons.file_copy_rounded,
        action: () {
          copyKey(null);
        },
      );

  static FilesContextOption deleteAll(
    List<FileContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
  ) =>
      FilesContextOption(
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
                  content: Text('Selected files deleted from device and S3')),
            );
          }
        },
      );

  static List<FilesContextOption> allOptions(
    String localRoot,
    List<RemoteFile> files,
    Function(RemoteFile?) cutKey,
    Function(RemoteFile?) copyKey,
    Function(String) deleteFile,
    List<FileContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
  ) {
    return [
      downloadAll(handlers),
      saveAllTo(handlers, context),
      shareAll(handlers),
      copyAllLinks(handlers, context),
      cut(cutKey),
      copy(copyKey),
      deleteAll(handlers, context, clearSelection),
    ];
  }
}

class DirectoryContextActionHandler extends ContextActionHandler {
  final String key;
  final Function(String) downloadDirectory;
  final Function(String, String) saveDirectory;
  final Function(String, String) moveDirectory;
  final Function(String) deleteDirectory;

  void Function()? open() {
    return Directory(p.join(localRoot, key.split('/').sublist(1).join('/')))
            .existsSync()
        ? () {
            OpenFile.open(
                p.join(localRoot, key.split('/').sublist(1).join('/')));
          }
        : null;
  }

  @override
  void Function()? download() {
    return localRoot.isEmpty
        ? null
        : () {
            downloadDirectory(key);
          };
  }

  @override
  String Function()? saveAs(String? path) {
    return path == null
        ? null
        : () {
            saveDirectory(
              key,
              p.join(localRoot, key.split('/').sublist(1).join('/')),
            );
            return 'Saving to $path';
          };
  }

  @override
  Future<String> Function() rename(String newName) {
    return () async {
      final key = this.key.endsWith('/') ? this.key : '${this.key}/';
      final newKey = '${p.dirname(key)}/${newName.replaceAll('/', '_')}/';
      await moveDirectory(key, newKey);
      return 'Renamed to $newName';
    };
  }

  @override
  Future<String> Function()? delete(bool? yes) {
    return yes ?? false
        ? () async {
            final key = this.key.endsWith('/') ? this.key : '${this.key}/';
            deleteDirectory(key);
            return 'Deleted ${p.basename(key)}';
          }
        : null;
  }

  DirectoryContextActionHandler({
    required super.localRoot,
    required this.key,
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

  static DirectoryContextOption open(
    DirectoryContextActionHandler handler,
  ) =>
      DirectoryContextOption(
        title: handler.open() == null ? 'Cannot Open' : 'Open',
        subtitle:
            handler.open() == null ? 'Directory does not exist locally' : null,
        icon:
            handler.open() == null ? Icons.open_in_new_off : Icons.open_in_new,
        action: handler.open(),
      );

  static DirectoryContextOption download(
    DirectoryContextActionHandler handler,
  ) =>
      DirectoryContextOption(
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
  ) =>
      DirectoryContextOption(
        title: 'Save To...',
        icon: Icons.save_as,
        action: () async {
          final directory = await getDirectoryPath(canCreateDirectories: true);
          final handle = handler.saveAs(directory == null
              ? null
              : p.join(directory, p.basename(handler.key)));
          if (handle != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(handle()),
              ),
            );
          }
        },
      );

  static DirectoryContextOption cut(
    String key,
    Function(String) cutKey,
  ) =>
      DirectoryContextOption(
        title: 'Move To...',
        icon: Icons.cut,
        action: () {
          cutKey(key);
        },
      );

  static DirectoryContextOption copy(
    String key,
    Function(String) copyKey,
  ) =>
      DirectoryContextOption(
        title: 'Copy To...',
        icon: Icons.folder_copy,
        action: () {
          copyKey(key);
        },
      );

  static DirectoryContextOption rename(
    String localRoot,
    String key,
    DirectoryContextActionHandler handler,
    BuildContext context,
  ) =>
      DirectoryContextOption(
        title: 'Rename',
        icon: Icons.edit,
        action: () async {
          final newName = await renameDialog(context, p.basename(key));
          if (newName != null &&
              newName.isNotEmpty &&
              newName != p.basename(key)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(await handler.rename(newName)()),
              ),
            );
          }
        },
      );

  static DirectoryContextOption delete(
    String localRoot,
    String key,
    DirectoryContextActionHandler handler,
    BuildContext context,
  ) =>
      DirectoryContextOption(
        title: 'Delete',
        icon: Icons.folder_delete,
        subtitle: 'Delete from device as well as S3',
        action: () async {
          final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Directory'),
              content: Text(
                'Are you sure you want to delete ${p.basename(key)} from your device and S3? This action cannot be undone.',
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
                content: Text(await handler.delete(true)!()),
              ),
            );
          }
        },
      );

  static List<DirectoryContextOption> allOptions(
    String localRoot,
    String key,
    Function(String) cutKey,
    Function(String) copyKey,
    DirectoryContextActionHandler handler,
    BuildContext context,
  ) {
    return [
      open(handler),
      download(handler),
      saveTo(handler, context),
      cut(localRoot, cutKey),
      copy(localRoot, copyKey),
      rename(localRoot, key, handler, context),
      delete(localRoot, key, handler, context),
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
  ) =>
      DirectoriesContextOption(
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
  ) =>
      DirectoriesContextOption(
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
              SnackBar(
                content: Text('Saving directories to $directory'),
              ),
            );
          }
        },
      );

  static DirectoriesContextOption cut(
    Function(String?) cutKey,
  ) =>
      DirectoriesContextOption(
        title: 'Move To...',
        icon: Icons.cut,
        action: (BuildContext context) {
          cutKey(null);
        },
      );

  static DirectoriesContextOption copy(
    Function(String?) copyKey,
  ) =>
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
  ) =>
      DirectoriesContextOption(
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
                  content:
                      Text('Selected directories deleted from device and S3')),
            );
          }
        },
      );

  static List<DirectoriesContextOption> allOptions(
    String localRoot,
    List<String> keys,
    Function(String?) cutKey,
    Function(String?) copyKey,
    List<DirectoryContextActionHandler> handlers,
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
    List<ContextActionHandler> handlers,
  ) =>
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
  ) =>
      BulkContextOption(
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
                            (handler as DirectoryContextActionHandler).key)),
              );
            }
            if (handle != null) {
              handle();
              saved = true;
            }
          }
          if (saved) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saving items to $directory'),
              ),
            );
          }
        },
      );

  static BulkContextOption cut(
    Function(dynamic) cutKey,
  ) =>
      BulkContextOption(
        title: 'Move To...',
        icon: Icons.cut,
        action: (BuildContext context) {
          cutKey(null);
        },
      );

  static BulkContextOption copy(
    Function(dynamic) copyKey,
  ) =>
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
  ) =>
      BulkContextOption(
        title: 'Delete Selection',
        icon: Icons.delete_sweep,
        action: (BuildContext context) async {
          final yes = await showDialog<bool>(
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
                  content: Text('Selected items deleted from device and S3')),
            );
          }
        },
      );

  static List<BulkContextOption> allOptions(
    Function(dynamic) cutKey,
    Function(dynamic) copyKey,
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
  String localRoot,
  Future<String> Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(RemoteFile, String) saveFile,
  Function(RemoteFile) cut,
  Function(RemoteFile) copy,
  Function(String, String) moveFile,
  Function(String) deleteFile,
) {
  FileContextActionHandler handler = FileContextActionHandler(
    localRoot: localRoot,
    file: item,
    getLink: getLink,
    downloadFile: downloadFile,
    saveFile: saveFile,
    moveFile: moveFile,
    deleteFile: deleteFile,
  );
  return ListView(
      children: FileContextOption.allOptions(
    localRoot,
    item,
    cut,
    copy,
    deleteFile,
    handler,
    context,
  )
          .map(
            (option) => ListTile(
              leading: Icon(option.icon),
              title: Text(option.title),
              subtitle: option.subtitle != null ? Text(option.subtitle!) : null,
              onTap: option.action == null
                  ? null
                  : () async {
                      await option.action!();
                      Navigator.of(context).pop();
                    },
            ),
          )
          .toList());
}

Widget buildFilesContextMenu(
  BuildContext context,
  List<RemoteFile> items,
  String localRoot,
  Future<String> Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
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
          localRoot: localRoot,
          file: item,
          getLink: getLink,
          downloadFile: downloadFile,
          saveFile: saveFile,
          moveFile: moveFile,
          deleteFile: deleteFile,
        ),
      )
      .toList();
  return ListView(
      children: FilesContextOption.allOptions(
    localRoot,
    items,
    cut,
    copy,
    deleteFile,
    handlers,
    context,
    clearSelection,
  )
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
          .toList());
}

Widget buildDirectoryContextMenu(
  BuildContext context,
  String key,
  String localRoot,
  Function(String) downloadDirectory,
  Function(String, String) saveDirectory,
  Function(String) cut,
  Function(String) copy,
  Function(String, String) moveDirectory,
  Function(String) deleteDirectory,
) {
  DirectoryContextActionHandler handler = DirectoryContextActionHandler(
    localRoot: localRoot,
    key: key,
    downloadDirectory: downloadDirectory,
    saveDirectory: saveDirectory,
    moveDirectory: moveDirectory,
    deleteDirectory: deleteDirectory,
  );
  return ListView(
      children: DirectoryContextOption.allOptions(
    localRoot,
    key,
    cut,
    copy,
    handler,
    context,
  )
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
          .toList());
}

Widget buildDirectoriesContextMenu(
  BuildContext context,
  List<String> keys,
  String localRoot,
  Function(String) downloadDirectory,
  Function(String, String) saveDirectory,
  Function(String?) cut,
  Function(String?) copy,
  Function(String, String) moveDirectory,
  Function(String) deleteDirectory,
  Function() clearSelection,
) {
  List<DirectoryContextActionHandler> handlers = keys
      .map(
        (key) => DirectoryContextActionHandler(
          localRoot: localRoot,
          key: key,
          downloadDirectory: downloadDirectory,
          saveDirectory: saveDirectory,
          moveDirectory: moveDirectory,
          deleteDirectory: deleteDirectory,
        ),
      )
      .toList();
  return ListView(
      children: DirectoriesContextOption.allOptions(
    localRoot,
    keys,
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
              subtitle: option.subtitle != null ? Text(option.subtitle!) : null,
              onTap: option.action != null
                  ? () async {
                      await option.action!(context);
                      Navigator.of(context).pop();
                    }
                  : null,
            ),
          )
          .toList());
}

Widget buildBulkContextMenu(
  BuildContext context,
  List<dynamic> items,
  String localRoot,
  Future<String> Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(String) downloadDirectory,
  Function(RemoteFile, String) saveFile,
  Function(String, String) saveDirectory,
  Function(String, String) moveFile,
  Function(String, String) moveDirectory,
  Function(dynamic) cut,
  Function(dynamic) copy,
  Function(String) deleteFile,
  Function(String) deleteDirectory,
  Function() clearSelection,
) {
  if (items.every((item) => item is RemoteFile)) {
    return buildFilesContextMenu(
      context,
      items.cast<RemoteFile>(),
      localRoot,
      getLink,
      downloadFile,
      saveFile,
      cut,
      copy,
      moveFile,
      deleteFile,
      clearSelection,
    );
  } else if (items.every((item) => item is String)) {
    return buildDirectoriesContextMenu(
      context,
      items.cast<String>(),
      localRoot,
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
      if (item is RemoteFile) {
        return FileContextActionHandler(
          localRoot: localRoot,
          file: item,
          getLink: getLink,
          downloadFile: downloadFile,
          saveFile: saveFile,
          moveFile: moveFile,
          deleteFile: deleteFile,
        );
      } else if (item is String) {
        return DirectoryContextActionHandler(
          localRoot: localRoot,
          key: item,
          downloadDirectory: downloadDirectory,
          saveDirectory: saveDirectory,
          moveDirectory: moveDirectory,
          deleteDirectory: deleteDirectory,
        );
      } else {
        throw Exception('Unknown item type');
      }
    }).toList();
    return ListView(
      children: BulkContextOption.allOptions(
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
              subtitle: option.subtitle != null ? Text(option.subtitle!) : null,
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
