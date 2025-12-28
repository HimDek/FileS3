import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:s3_drive/services/ini_manager.dart';
import 'package:s3_drive/services/job.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'services/models/backup_mode.dart';

class DirectoryOptions extends StatefulWidget {
  final RemoteFile directory;
  final List<RemoteFile> remoteFiles;
  final Function(String) deleteLocal;
  final Function(String) onDelete;
  final Function(BackupMode) setBackupMode;

  const DirectoryOptions({
    super.key,
    required this.directory,
    required this.remoteFiles,
    required this.deleteLocal,
    required this.onDelete,
    required this.setBackupMode,
  });

  @override
  DirectoryOptionsState createState() => DirectoryOptionsState();
}

class DirectoryOptionsState extends State<DirectoryOptions> {
  late String local;
  BackupMode mode = BackupMode.upload;

  void getLocal() {
    local = Main.pathFromKey(widget.directory.key) ?? '';
    mode = Main.backupMode(widget.directory.key);
    setState(() {});
  }

  void setLocal(String dir) {
    if (!IniManager.config!.sections().contains('directories')) {
      IniManager.config!.addSection('directories');
    }
    IniManager.config!.set('directories', widget.directory.key, dir);
    IniManager.save();
    Main.listDirectories();
    getLocal();
  }

  void setMode(BackupMode newMode) {
    widget.setBackupMode(newMode);
    getLocal();
  }

  List<RemoteFile> removableFiles() {
    final List<RemoteFile> removableFiles = <RemoteFile>[];
    if (mode == BackupMode.upload) {
      for (final file in widget.remoteFiles) {
        if (File(Main.pathFromKey(file.key) ?? file.key).existsSync()) {
          removableFiles.add(file);
        }
      }
    }
    return removableFiles;
  }

  @override
  void initState() {
    super.initState();
    getLocal();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              'Options for ${widget.directory}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.drive_folder_upload),
          title: const Text('Backup From'),
          subtitle: Text(local.isEmpty ? 'Not set' : local),
          onTap: () async {
            final String? directoryPath = await getDirectoryPath();
            if (directoryPath != null) {
              setLocal(directoryPath);
            }
          },
        ),
        if (local.isNotEmpty) ...[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Backup Mode'),
          ),
          RadioGroup(
            groupValue: mode,
            onChanged: (s) {
              setMode(s!);
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
        ],
        if (mode == BackupMode.upload)
          ListTile(
            leading: const Icon(Icons.auto_delete),
            title: const Text('Delete uploaded files'),
            subtitle: const Text('Remove uploaded files from local directory'),
            onTap: () async {
              bool yes =
                  await showDialog<bool>(
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
                                    for (final file in removableFiles())
                                      Text(
                                        Main.pathFromKey(file.key) ?? file.key,
                                      ),
                                    if (removableFiles().isEmpty)
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
                          onPressed: removableFiles().isNotEmpty
                              ? () => Navigator.of(context).pop(true)
                              : null,
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (yes) {
                for (final file in removableFiles()) {
                  try {
                    widget.deleteLocal(file.key);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Error deleting file ${Main.pathFromKey(file.key) ?? file.key}: $e',
                        ),
                      ),
                    );
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Files deleted successfully')),
                );
              }
            },
          ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.delete),
          title: Text('Delete'),
          subtitle: Text('Delete ${widget.directory} from S3'),
          onTap: () async {
            bool yes =
                await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Directory'),
                    content: Text(
                      'Are you sure you want to delete ${widget.directory} from S3?',
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
              widget.onDelete(widget.directory.key);
            } else {
              return;
            }
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
