import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:s3_drive/services/job.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:s3_drive/services/s3_file_manager.dart';
import 'package:share_plus/share_plus.dart';

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

class FileContextActionHandler {
  final String localRoot;
  final RemoteFile file;
  final S3FileManager s3Manager;
  final List<Job> jobs;
  final Function startProcessor;
  final Function(Job)? onJobStatus;
  final Processor processor;
  final Function(String, String) deleteFile;

  FileContextActionHandler({
    required this.localRoot,
    required this.file,
    required this.s3Manager,
    required this.jobs,
    required this.startProcessor,
    required this.onJobStatus,
    required this.processor,
    required this.deleteFile,
  });

  Function()? open() {
    return File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
            .existsSync()
        ? () {
            OpenFile.open(
                p.join(localRoot, file.key.split('/').sublist(1).join('/')));
          }
        : null;
  }

  Function()? download() {
    return localRoot.isEmpty
        ? null
        : () {
            final localPath =
                p.join(localRoot, file.key.split('/').sublist(1).join('/'));
            jobs.add(
              DownloadJob(
                localFile: File(localPath),
                remoteKey: file.key,
                bytes: file.size,
                md5: file.etag,
                onStatus: onJobStatus,
              ),
            );
            startProcessor();
          };
  }

  Function()? saveAs(FileSaveLocation? savePath) {
    return () {
      if (savePath != null) {
        final localPath = savePath.path;
        if (File(localPath).existsSync()) {
          File(localPath).deleteSync();
        }
        if (File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
            .existsSync()) {
          File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
              .copySync(localPath);
        } else {
          jobs.add(
            DownloadJob(
              localFile: File(localPath),
              remoteKey: file.key,
              bytes: file.size,
              onStatus: onJobStatus,
              md5: file.etag,
            ),
          );
          startProcessor();
        }
        return 'Saving to $localPath';
      }
      return 'Save cancelled';
    };
  }

  Function()? share() {
    return File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
            .existsSync()
        ? () {
            SharePlus.instance.share(
              ShareParams(
                files: [
                  XFile(p.join(
                      localRoot, file.key.split('/').sublist(1).join('/')))
                ],
              ),
            );
          }
        : null;
  }

  Function()? copyLink(int? seconds) {
    return () async {
      Job job = GetLinkJob(
        localFile: File(
          p.join(localRoot, file.key.split('/').sublist(1).join('/')),
        ),
        remoteKey: file.key,
        bytes: file.size,
        onStatus: onJobStatus,
        md5: file.etag,
        validForSeconds: seconds ?? 3600,
      );
      await processor.processJob(job, (job, result) {});
      await Clipboard.setData(ClipboardData(text: job.statusMsg));
    };
  }

  Function()? rename(String newName) {
    return () async {
      final newKey = '${p.dirname(file.key)}/${newName.replaceAll('/', '_')}';
      await s3Manager.renameFile(file.key, newKey);
      if (File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
          .existsSync()) {
        final newLocalPath =
            p.join(localRoot, newKey.split('/').sublist(1).join('/'));
        File(p.join(localRoot, file.key.split('/').sublist(1).join('/')))
            .renameSync(newLocalPath);
      }
      return 'Renamed to $newName';
    };
  }

  Function()? delete(bool? yes) {
    return () {
      if (yes ?? false) {
        deleteFile(file.key,
            p.join(localRoot, file.key.split('/').sublist(1).join('/')));
        return 'Deleted ${file.key.split('/').last}';
      }
    };
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
    String localRoot,
    RemoteFile file,
    FileContextActionHandler handler,
  ) =>
      FileContextOption(
        title: 'Open',
        icon: Icons.open_in_new,
        action: handler.open(),
      );

  static FileContextOption download(
    String localRoot,
    RemoteFile file,
    List<Job> jobs,
    Function startProcessor,
    Function(Job)? onJobStatus,
    FileContextActionHandler handler,
  ) =>
      FileContextOption(
        title: 'Download',
        icon: Icons.download,
        action: handler.download(),
      );

  static FileContextOption saveAs(
    String localRoot,
    RemoteFile file,
    List<Job> jobs,
    Function startProcessor,
    Function(Job)? onJobStatus,
    FileContextActionHandler handler,
    BuildContext context,
  ) =>
      FileContextOption(
        title: 'Save As...',
        icon: Icons.save,
        action: () async {
          final handle = handler.saveAs(
            await getSaveLocation(
              suggestedName: file.key.split('/').last,
              canCreateDirectories: true,
            ),
          );
          if (handle != null) {
            String msg = handle();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
              ),
            );
          }
        },
      );

  static FileContextOption share(
    String localRoot,
    RemoteFile file,
    FileContextActionHandler handler,
  ) =>
      FileContextOption(
        title: 'Share',
        icon: Icons.share,
        subtitle: 'Only downloaded files can be shared',
        action: handler.share(),
      );

  static FileContextOption copyLink(
    Function(Job)? onJobStatus,
    Processor processor,
    String localRoot,
    RemoteFile file,
    FileContextActionHandler handler,
    BuildContext context,
  ) =>
      FileContextOption(
        title: 'Copy Link',
        icon: Icons.link,
        action: () async {
          final handle = handler.copyLink(await expiryDialog(context));
          if (handle != null) {
            handle();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File link copied to clipboard')),
            );
          }
        },
      );

  static FileContextOption rename(
    String localRoot,
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
            String msg = await handler.rename(newName)!();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
              ),
            );
          }
        },
      );

  static FileContextOption delete(
    String localRoot,
    RemoteFile file,
    final Function(String, String) deleteFile,
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
            String msg = handle();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
              ),
            );
          }
        },
      );

  static List<FileContextOption> allOptions(
    String localRoot,
    RemoteFile file,
    List<Job> jobs,
    Function startProcessor,
    Function(Job)? onJobStatus,
    Processor processor,
    Function(String, String) deleteFile,
    FileContextActionHandler handler,
    BuildContext context,
  ) {
    return [
      open(localRoot, file, handler),
      download(localRoot, file, jobs, startProcessor, onJobStatus, handler),
      saveAs(
          localRoot, file, jobs, startProcessor, onJobStatus, handler, context),
      share(localRoot, file, handler),
      copyLink(onJobStatus, processor, localRoot, file, handler, context),
      rename(localRoot, file, handler, context),
      delete(localRoot, file, deleteFile, handler, context),
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
    String localRoot,
    List<RemoteFile> files,
    List<Job> jobs,
    Function startProcessor,
    Function(Job)? onJobStatus,
    List<FileContextActionHandler> handlers,
  ) =>
      FilesContextOption(
          title: 'Download',
          icon: Icons.download,
          action: () {
            for (final handler in handlers) {
              if (handler.download() != null) {
                handler.download()!();
              }
            }
          });

  static FilesContextOption saveAllTo(
    String localRoot,
    List<RemoteFile> files,
    List<Job> jobs,
    Function startProcessor,
    Function(Job)? onJobStatus,
    List<FileContextActionHandler> handlers,
    BuildContext context,
  ) =>
      FilesContextOption(
        title: 'Save To...',
        icon: Icons.save,
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
            if (handler.saveAs(savePath) != null) {
              handler.saveAs(savePath)!();
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
    String localRoot,
    List<RemoteFile> files,
    List<FileContextActionHandler> handlers,
  ) =>
      FilesContextOption(
        title: 'Share',
        icon: Icons.share,
        subtitle: 'Only downloaded files can be shared',
        action: () {
          List<XFile> shareFiles = [];
          for (final handler in handlers) {
            if (handler.share() != null) {
              shareFiles.add(
                XFile(p.join(localRoot,
                    handler.file.key.split('/').sublist(1).join('/'))),
              );
            }
          }
          if (shareFiles.isNotEmpty) {
            SharePlus.instance.share(
              ShareParams(
                files: shareFiles,
              ),
            );
          }
        },
      );

  static FilesContextOption copyAllLinks(
    Function(Job)? onJobStatus,
    Processor processor,
    String localRoot,
    List<RemoteFile> files,
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
            Job job = GetLinkJob(
              localFile: File(
                p.join(localRoot,
                    handler.file.key.split('/').sublist(1).join('/')),
              ),
              remoteKey: handler.file.key,
              bytes: handler.file.size,
              onStatus: onJobStatus,
              md5: handler.file.etag,
              validForSeconds: seconds ?? 3600,
            );
            await processor.processJob(job, (job, result) {});
            allLinks += '${job.statusMsg}\n\n';
          }
          if (allLinks.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: allLinks));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File links copied to clipboard')),
            );
          }
        },
      );

  static FilesContextOption deleteAll(
    String localRoot,
    List<RemoteFile> files,
    final Function(String, String) deleteFile,
    List<FileContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
  ) =>
      FilesContextOption(
        title: 'Delete Selection',
        icon: Icons.delete,
        subtitle: 'Delete from device as well as S3',
        action: () async {
          final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Selected Files'),
              content: const Text(
                'Are you sure you want to delete all selected files from your device and S3? This action cannot be undone.',
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
    List<Job> jobs,
    Function startProcessor,
    Function(Job)? onJobStatus,
    Processor processor,
    Function(String, String) deleteFile,
    List<FileContextActionHandler> handlers,
    BuildContext context,
    Function() clearSelection,
  ) {
    return [
      downloadAll(
          localRoot, files, jobs, startProcessor, onJobStatus, handlers),
      saveAllTo(localRoot, files, jobs, startProcessor, onJobStatus, handlers,
          context),
      shareAll(localRoot, files, handlers),
      copyAllLinks(onJobStatus, processor, localRoot, files, handlers, context),
      deleteAll(
          localRoot, files, deleteFile, handlers, context, clearSelection),
    ];
  }
}

class DirectoryContextActionHandler {
  final String localRoot;
  final String key;
  final S3FileManager s3Manager;
  final Function(Job)? onJobStatus;
  final Processor processor;
  final Function(String, String) deleteDirectory;

  Function()? rename(String newName) {
    return () async {
      final key = this.key.endsWith('/') ? this.key : '${this.key}/';
      final newKey = '${p.dirname(key)}/${newName.replaceAll('/', '_')}/';
      await s3Manager.renameFile(key, newKey);
      if (File(p.join(localRoot, key.split('/').sublist(1).join('/')))
          .existsSync()) {
        final newLocalPath =
            p.join(localRoot, newKey.split('/').sublist(1).join('/'));
        File(p.join(localRoot, key.split('/').sublist(1).join('/')))
            .renameSync(newLocalPath);
      }
      return 'Renamed to $newName';
    };
  }

  Function()? delete(bool? yes) {
    return () {
      if (yes ?? false) {
        final key = this.key.endsWith('/') ? this.key : '${this.key}/';
        deleteDirectory(
            key, p.join(localRoot, key.split('/').sublist(1).join('/')));
        return 'Deleted ${p.basename(key)}';
      }
    };
  }

  DirectoryContextActionHandler({
    required this.localRoot,
    required this.key,
    required this.s3Manager,
    required this.onJobStatus,
    required this.processor,
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

  static DirectoryContextOption rename(
    String localRoot,
    String key,
    DirectoryContextActionHandler handler,
    BuildContext context,
  ) =>
      DirectoryContextOption(
        title: 'Rename Directory',
        icon: Icons.edit,
        action: () async {
          final newName = await renameDialog(context, p.basename(key));
          if (newName != null &&
              newName.isNotEmpty &&
              newName != p.basename(key)) {
            String msg = await handler.rename(newName)!();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
              ),
            );
          }
        },
      );

  static DirectoryContextOption delete(
    String localRoot,
    String key,
    final Function(String, String) deleteFile,
    DirectoryContextActionHandler handler,
    BuildContext context,
  ) =>
      DirectoryContextOption(
        title: 'Delete Directory',
        icon: Icons.delete,
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
            String msg = handler.delete(true)!();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
              ),
            );
          }
        },
      );

  static List<DirectoryContextOption> allOptions(
    String localRoot,
    String key,
    List<Job> jobs,
    Function startProcessor,
    Function(Job)? onJobStatus,
    Processor processor,
    Function(String, String) deleteFile,
    DirectoryContextActionHandler handler,
    BuildContext context,
  ) {
    return [
      rename(localRoot, key, handler, context),
      delete(localRoot, key, deleteFile, handler, context),
    ];
  }
}

class DirectoriesContextOption {
  final String title;
  final IconData icon;
  final String? subtitle;
  final dynamic Function(BuildContext context)? action;

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
  S3FileManager s3Manager,
  List<Job> jobs,
  Function startProcessor,
  Function(Job)? onJobStatus,
  Processor processor,
  Function(String, String) deleteFile,
) {
  FileContextActionHandler handler = FileContextActionHandler(
    localRoot: localRoot,
    file: item,
    s3Manager: s3Manager,
    jobs: jobs,
    startProcessor: startProcessor,
    onJobStatus: onJobStatus,
    processor: processor,
    deleteFile: deleteFile,
  );
  return ListView(
      children: FileContextOption.allOptions(
    localRoot,
    item,
    jobs,
    startProcessor,
    onJobStatus,
    processor,
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
  S3FileManager s3Manager,
  List<Job> jobs,
  Function startProcessor,
  Function(Job)? onJobStatus,
  Processor processor,
  Function(String, String) deleteFile,
  Function() clearSelection,
) {
  List<FileContextActionHandler> handlers = items
      .map(
        (item) => FileContextActionHandler(
          localRoot: localRoot,
          file: item,
          s3Manager: s3Manager,
          jobs: jobs,
          startProcessor: startProcessor,
          onJobStatus: onJobStatus,
          processor: processor,
          deleteFile: deleteFile,
        ),
      )
      .toList();
  return ListView(
      children: FilesContextOption.allOptions(
    localRoot,
    items,
    jobs,
    startProcessor,
    onJobStatus,
    processor,
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
  S3FileManager s3Manager,
  List<Job> jobs,
  Function startProcessor,
  Function(Job)? onJobStatus,
  Processor processor,
  Function(String, String) deleteDirectory,
) {
  DirectoryContextActionHandler handler = DirectoryContextActionHandler(
    localRoot: localRoot,
    key: key,
    s3Manager: s3Manager,
    onJobStatus: onJobStatus,
    processor: processor,
    deleteDirectory: deleteDirectory,
  );
  return ListView(
      children: DirectoryContextOption.allOptions(
    localRoot,
    key,
    jobs,
    startProcessor,
    onJobStatus,
    processor,
    deleteDirectory,
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
