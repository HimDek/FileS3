import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:s3_drive/services/job.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:s3_drive/services/models/remote_file.dart';

class FilesOptions extends StatefulWidget {
  final List<(File, RemoteFile)> files;
  final String localRoot;
  final List<Job> jobs;
  final Processor processor;
  final void Function(Job job) onJobStatus;
  final Function() startProcessor;
  final Function(String, String) deleteFile;

  const FilesOptions({
    super.key,
    required this.files,
    required this.localRoot,
    required this.jobs,
    required this.processor,
    required this.onJobStatus,
    required this.startProcessor,
    required this.deleteFile,
  });

  @override
  FilesOptionsState createState() => FilesOptionsState();
}

class FilesOptionsState extends State<FilesOptions> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              'Options for ${widget.files.length} files',
              style: Theme.of(context).textTheme.headlineSmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (widget.files.any((filePair) => !filePair.$1.existsSync()))
          ListTile(
            leading: const Icon(Icons.download),
            title: Text('Download'),
            subtitle: widget.localRoot.isEmpty
                ? Text('Set sync options to enable downloading')
                : null,
            onTap: widget.localRoot.isEmpty
                ? null
                : () {
                    for (final filePair in widget.files) {
                      if (!filePair.$1.existsSync()) {
                        FileSaveLocation fileSaveLocation = FileSaveLocation(
                            p.join(
                                widget.localRoot,
                                filePair.$2.key
                                    .split('/')
                                    .sublist(1)
                                    .join('/')));
                        final localPath = fileSaveLocation.path;
                        widget.jobs.add(
                          DownloadJob(
                            localFile: File(localPath),
                            remoteKey: filePair.$2.key,
                            bytes: filePair.$2.size,
                            onStatus: widget.onJobStatus,
                            md5: filePair.$2.etag,
                          ),
                        );
                        widget.startProcessor();
                      }
                    }
                    Navigator.of(context).pop();
                  },
          ),
        ListTile(
          leading: const Icon(Icons.save),
          title: Text('Save To...'),
          onTap: () async {
            final directory =
                await getDirectoryPath(canCreateDirectories: true);
            for (final filePair in widget.files) {
              if (directory != null) {
                final localPath =
                    p.join(directory, filePair.$2.key.split('/').last);
                if (File(localPath).existsSync()) {
                  File(localPath).deleteSync();
                }
                if (File(p.join(widget.localRoot,
                        filePair.$2.key.split('/').sublist(1).join('/')))
                    .existsSync()) {
                  File(p.join(widget.localRoot,
                          filePair.$2.key.split('/').sublist(1).join('/')))
                      .copySync(localPath);
                } else {
                  widget.jobs.add(
                    DownloadJob(
                      localFile: File(localPath),
                      remoteKey: filePair.$2.key,
                      bytes: filePair.$2.size,
                      onStatus: widget.onJobStatus,
                      md5: filePair.$2.etag,
                    ),
                  );
                  widget.startProcessor();
                }
              }
            }
            Navigator.of(context).pop();
          },
        ),
        ListTile(
          leading: const Icon(Icons.share),
          title: Text('Share Files'),
          subtitle: widget.files.any((filePair) => !filePair.$1.existsSync())
              ? Text('Some files are not downloaded')
              : null,
          onTap: widget.files.any((filePair) => filePair.$1.existsSync())
              ? () {
                  SharePlus.instance.share(
                    ShareParams(
                      files: widget.files
                          .where((filePair) => filePair.$1.existsSync())
                          .map((filePair) => XFile(filePair.$1.path))
                          .toList(),
                    ),
                  );
                  Navigator.of(context).pop();
                }
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: Text('Copy Links'),
          onTap: () async {
            final seconds = await showDialog<int>(
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
                            31,
                            (i) => DropdownMenuItem(
                                value: i, child: Text('$i d'))),
                        onChanged: (v) => set(() => d = v!),
                      ),
                      DropdownButton<int>(
                        value: h,
                        items: List.generate(
                            24,
                            (i) => DropdownMenuItem(
                                value: i, child: Text('$i h'))),
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

            final List<String> links = [];

            for (final filePair in widget.files) {
              final GetLinkJob job = GetLinkJob(
                localFile: File(
                  p.join(widget.localRoot,
                      filePair.$2.key.split('/').sublist(1).join('/')),
                ),
                remoteKey: filePair.$2.key,
                bytes: filePair.$2.size,
                onStatus: widget.onJobStatus,
                md5: filePair.$2.etag,
                validForSeconds: seconds ?? 3600,
              );
              await widget.processor.processJob(job, (job, result) {});
              links.add(job.statusMsg);
            }

            Clipboard.setData(
              ClipboardData(text: links.join('\n')),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File link copied to clipboard')),
            );
            Navigator.of(context).pop();
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete),
          title: Text('Delete'),
          subtitle: Text('Delete from device as well as S3'),
          onTap: () async {
            bool yes = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete File'),
                    content: Text(
                      'Are you sure you want to delete ${widget.files.length} files from your device and S3? This action cannot be undone.',
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
              for (final filePair in widget.files) {
                widget.deleteFile(
                    filePair.$2.key,
                    p.join(widget.localRoot,
                        filePair.$2.key.split('/').sublist(1).join('/')));
              }
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
