import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:s3_drive/components.dart';
import 'package:s3_drive/list_files.dart';
import 'package:s3_drive/services/job.dart';
import 'package:s3_drive/services/models/common.dart';
import 'package:s3_drive/services/models/remote_file.dart';

class DirectoryContents extends StatefulWidget {
  final String directory;
  final Processor processor;
  final List<Job> jobs;
  final Map<String, List<RemoteFile>> remoteFilesMap;
  final bool foldersFirst;
  final SortMode sortMode;
  final String? focusedKey;
  final Set<dynamic> selection;
  final SelectionAction selectionAction;
  final Function(dynamic) select;
  final Function(List<dynamic>) updateAllSelectableItems;
  final String Function(String) pathFromKey;
  final Function(String) setFocus;
  final Function(int) setNavIndex;
  final void Function(Job job) onJobStatus;
  final Function(Job, dynamic) onJobComplete;
  final Function(String) onChangeDirectory;
  final Future<String> Function(RemoteFile, int?) getLink;
  final Function(RemoteFile) downloadFile;
  final Function(RemoteFile, String) saveFile;
  final Function(String) downloadDirectory;
  final Function(String, String) saveDirectory;
  final Function(dynamic) cut;
  final Function(dynamic) copy;
  final Function(String, String, {bool refresh}) moveFile;
  final Function(String, {bool refresh}) deleteFile;
  final Function(String, String, {bool refresh}) moveDirectory;
  final Function(String, {bool refresh}) deleteDirectory;
  final Future<void> Function() stopWatchers;
  final Function() listDirectories;
  final Function() startProcessor;

  const DirectoryContents({
    super.key,
    required this.directory,
    required this.processor,
    required this.jobs,
    required this.remoteFilesMap,
    required this.foldersFirst,
    required this.sortMode,
    required this.focusedKey,
    required this.selection,
    required this.selectionAction,
    required this.select,
    required this.updateAllSelectableItems,
    required this.pathFromKey,
    required this.setFocus,
    required this.setNavIndex,
    required this.onJobStatus,
    required this.onJobComplete,
    required this.onChangeDirectory,
    required this.getLink,
    required this.downloadFile,
    required this.saveFile,
    required this.downloadDirectory,
    required this.saveDirectory,
    required this.cut,
    required this.copy,
    required this.moveFile,
    required this.deleteFile,
    required this.moveDirectory,
    required this.deleteDirectory,
    required this.stopWatchers,
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
        .map((job) => job.remoteKey)
        .toList();

    widget.updateAllSelectableItems([
      ...subDirectories.map((subDir) => "${Directory(subDir).path}/"),
      ...widget.remoteFilesMap[dir]!.where((file) =>
          file.key.split('/').last.isNotEmpty &&
          '${File(file.key).parent.path}/' == widget.directory &&
          !jobs.contains(file.key)),
    ]);

    return ListView(
      children: sort([
        (
          {'name': '..', 'size': 0, 'file': null},
          ListTile(
            selected: widget.focusedKey == '..' && widget.selection.isEmpty,
            selectedTileColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            selectedColor: Theme.of(context).colorScheme.primary,
            leading: Icon(Icons.folder),
            title: Text('../'),
            onTap: widget.selection.isNotEmpty &&
                    widget.selectionAction == SelectionAction.none
                ? null
                : () {
                    widget.onChangeDirectory(
                      "${Directory(widget.directory).parent.path}/",
                    );
                  },
          ),
        ),
        ...listFiles(
          context,
          [
            ...subDirectories,
            ...widget.jobs.where(
              (job) =>
                  job.remoteKey.startsWith(widget.directory) &&
                  '${File(job.remoteKey).parent.path}/' == widget.directory,
            ),
            ...(widget.remoteFilesMap[dir] ?? []).where((file) =>
                (file.key.split('/').last.isNotEmpty &&
                    '${File(file.key).parent.path}/' == widget.directory &&
                    !jobs.contains(file.key)))
          ],
          false,
          widget.processor,
          widget.focusedKey,
          widget.selection,
          widget.selectionAction,
          widget.select,
          widget.pathFromKey,
          widget.setFocus,
          widget.setNavIndex,
          () {
            setState(() {});
          },
          widget.onJobComplete,
          (job) {
            widget.jobs.remove(job);
            setState(() {});
          },
          widget.onChangeDirectory,
          widget.getLink,
          widget.downloadFile,
          widget.downloadDirectory,
          widget.saveFile,
          widget.saveDirectory,
          widget.cut,
          widget.copy,
          widget.moveFile,
          widget.moveDirectory,
          widget.deleteFile,
          widget.deleteDirectory,
          widget.listDirectories,
          widget.stopWatchers,
        ),
      ], widget.sortMode, widget.foldersFirst)
          .map((item) {
            return item.$2;
          })
          .toList()
          .followedBy([SizedBox(height: 256)])
          .toList(),
    );
  }
}
