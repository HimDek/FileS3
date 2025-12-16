import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:s3_drive/components.dart';
import 'package:s3_drive/job_view.dart';
import 'package:s3_drive/services/job.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:s3_drive/services/s3_file_manager.dart';

class DirectoryContents extends StatefulWidget {
  final String directory;
  final String localRoot;
  final S3FileManager s3Manager;
  final Processor processor;
  final List<Job> jobs;
  final Map<String, List<RemoteFile>> remoteFilesMap;
  final Set<(File, RemoteFile)> selection;
  final Function((File, RemoteFile)) selectFile;
  final void Function(Job job) onJobStatus;
  final Function(Job, dynamic) onJobComplete;
  final Function(String) onChangeDirectory;
  final Function(String, String) deleteFile;
  final Function(String, String) deleteDirectory;
  final Function() listDirectories;
  final Function() startProcessor;

  const DirectoryContents({
    super.key,
    required this.directory,
    required this.localRoot,
    required this.s3Manager,
    required this.processor,
    required this.jobs,
    required this.remoteFilesMap,
    required this.selection,
    required this.selectFile,
    required this.onJobStatus,
    required this.onJobComplete,
    required this.onChangeDirectory,
    required this.deleteFile,
    required this.deleteDirectory,
    required this.listDirectories,
    required this.startProcessor,
  });

  @override
  DirectoryContentsState createState() => DirectoryContentsState();
}

class DirectoryContentsState extends State<DirectoryContents> {
  @override
  Widget build(BuildContext context) {
    String dir = '${widget.directory.split('/').first}/';

    List<String> subDirectories = (widget.remoteFilesMap[dir] ?? [])
        .where(
          (file) =>
              (file.key.split('/').last.isNotEmpty &&
                  '${File(file.key).parent.parent.path}/' ==
                      widget.directory) ||
              (file.key.split('/').last.isEmpty &&
                  '${File(file.key).parent.path}/' == widget.directory),
        )
        .map(
          (file) => '${File(file.key).parent.path}/' != widget.directory
              ? File(file.key).parent.path
              : p.normalize(File(file.key).path),
        )
        .toSet()
        .toList();

    List<String> jobs = widget.jobs
        .where(
          (job) =>
              job.remoteKey.startsWith(widget.directory) &&
              '${File(job.remoteKey).parent.path}/' == widget.directory,
        )
        .map((job) => job.remoteKey.split('/').last)
        .toList();

    return ListView(
      children: [
        (
          {'name': '..', 'size': 0, 'file': null},
          ListTile(
            leading: Icon(Icons.folder),
            title: Text('../'),
            onTap: widget.selection.isNotEmpty
                ? null
                : () {
                    widget.onChangeDirectory(
                      "${Directory(widget.directory).parent.path}/",
                    );
                  },
          ),
        ),
        for (String subDir in subDirectories)
          (
            {
              'name': Directory(subDir).path.split('/').last,
              'size': 0,
              'file': null,
            },
            ListTile(
              leading: Icon(Icons.folder),
              title: Text("${Directory(subDir).path.split('/').last}/"),
              onTap: widget.selection.isNotEmpty
                  ? null
                  : () {
                      widget.onChangeDirectory("${Directory(subDir).path}/");
                    },
              trailing: IconButton(
                onPressed: () {
                  showModalBottomSheet(
                      context: context,
                      enableDrag: true,
                      showDragHandle: true,
                      constraints: const BoxConstraints(
                        maxHeight: 800,
                        maxWidth: 800,
                      ),
                      builder: (context) => buildDirectoryContextMenu(
                            context,
                            "${Directory(subDir).path}/",
                            widget.localRoot,
                            widget.s3Manager,
                            widget.jobs,
                            widget.startProcessor,
                            widget.onJobStatus,
                            widget.processor,
                            widget.deleteDirectory,
                          )).then((value) => widget.listDirectories());
                },
                icon: Icon(Icons.more_vert),
              ),
            ),
          ),
        for (final job in widget.jobs.where(
          (job) =>
              job.remoteKey.startsWith(widget.directory) &&
              '${File(job.remoteKey).parent.path}/' == widget.directory,
        ))
          (
            {
              'name': job.remoteKey.split('/').last,
              'size': job.bytes,
              'file': job.localFile,
              'job': job,
            },
            JobView(
              job: job,
              processor: widget.processor,
              onUpdate: () {
                setState(() {});
              },
              onJobComplete: widget.onJobComplete,
              remove: () {
                setState(() {
                  widget.jobs.remove(job);
                });
              },
            ),
          ),
        for (RemoteFile file in widget.remoteFilesMap[dir] ?? [])
          if (file.key.split('/').last.isNotEmpty &&
              '${File(file.key).parent.path}/' == widget.directory &&
              !jobs.contains(file.key.split('/').last))
            (
              {
                'name': file.key.split('/').last,
                'size': file.size,
                'file': file,
              },
              ListTile(
                leading: Icon(Icons.insert_drive_file),
                title: Text(file.key.split('/').last),
                subtitle: Text(
                    '${bytesToReadable(file.size)}\t\t\t\t${file.lastModified.toLocal().toString().split('.').first}'),
                onTap: widget.selection.isNotEmpty
                    ? () {
                        widget.selectFile((
                          File(
                            p.join(widget.localRoot,
                                file.key.split('/').sublist(1).join('/')),
                          ),
                          file
                        ));
                      }
                    : () {
                        showModalBottomSheet(
                            context: context,
                            enableDrag: true,
                            showDragHandle: true,
                            constraints: const BoxConstraints(
                              maxHeight: 800,
                              maxWidth: 800,
                            ),
                            builder: (context) => buildFileContextMenu(
                                  context,
                                  file,
                                  widget.localRoot,
                                  widget.s3Manager,
                                  widget.jobs,
                                  widget.startProcessor,
                                  widget.onJobStatus,
                                  widget.processor,
                                  widget.deleteFile,
                                )).then((value) => widget.listDirectories());
                      },
                onLongPress: () {
                  widget.selectFile((
                    File(
                      p.join(widget.localRoot,
                          file.key.split('/').sublist(1).join('/')),
                    ),
                    file
                  ));
                },
                selected: widget.selection.any((selected) =>
                    selected.$1.path ==
                        p.join(widget.localRoot,
                            file.key.split('/').sublist(1).join('/')) &&
                    selected.$2.key == file.key),
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                selectedColor: Theme.of(context).colorScheme.primary,
              ),
            ),
      ]
          .map((item) {
            return item.$2;
          })
          .toList()
          .followedBy([SizedBox(height: 160)])
          .toList(),
    );
  }
}
