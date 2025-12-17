import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:s3_drive/services/models/common.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:s3_drive/components.dart';
import 'package:s3_drive/job_view.dart';
import 'package:s3_drive/services/job.dart';
import 'package:s3_drive/services/models/remote_file.dart';

class DirectoryContents extends StatefulWidget {
  final String directory;
  final String localRoot;
  final Processor processor;
  final List<Job> jobs;
  final Map<String, List<RemoteFile>> remoteFilesMap;
  final bool foldersFirst;
  final SortMode sortMode;
  final Set<dynamic> selection;
  final Function(dynamic) select;
  final Function(List<dynamic>) updateAllSelectableItems;
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
  final Function(String, String) copyFile;
  final Function(String, String) moveFile;
  final Function(String) deleteFile;
  final Function(String, String) copyDirectory;
  final Function(String, String) moveDirectory;
  final Function(String) deleteDirectory;
  final Function() listDirectories;
  final Function() startProcessor;

  const DirectoryContents({
    super.key,
    required this.directory,
    required this.localRoot,
    required this.processor,
    required this.jobs,
    required this.remoteFilesMap,
    required this.foldersFirst,
    required this.sortMode,
    required this.selection,
    required this.select,
    required this.updateAllSelectableItems,
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
    required this.copyFile,
    required this.moveFile,
    required this.deleteFile,
    required this.copyDirectory,
    required this.moveDirectory,
    required this.deleteDirectory,
    required this.listDirectories,
    required this.startProcessor,
  });

  @override
  DirectoryContentsState createState() => DirectoryContentsState();
}

class DirectoryContentsState extends State<DirectoryContents> {
  String? focusedKey;

  List<(Map<String, dynamic>, Widget)> sort(
      List<(Map<String, dynamic>, Widget)> items) {
    List<(Map<String, dynamic>, Widget)> sortedItems = List.from(items);
    sortedItems.sort((a, b) {
      var aIsDir = a.$1['file'] == null && a.$1['job'] == null;
      var bIsDir = b.$1['file'] == null && b.$1['job'] == null;

      if (a.$1['name'] == '..') return -1;
      if (b.$1['name'] == '..') return 1;

      if (widget.foldersFirst) {
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
      }

      switch (widget.sortMode) {
        case SortMode.nameAsc:
          return a.$1['name']
              .toLowerCase()
              .compareTo(b.$1['name'].toLowerCase());
        case SortMode.nameDesc:
          return b.$1['name']
              .toLowerCase()
              .compareTo(a.$1['name'].toLowerCase());
        case SortMode.dateAsc:
          DateTime aDate = a.$1['file'] != null
              ? (a.$1['file'] as RemoteFile).lastModified
              : DateTime.fromMillisecondsSinceEpoch(0);
          DateTime bDate = b.$1['file'] != null
              ? (b.$1['file'] as RemoteFile).lastModified
              : DateTime.fromMillisecondsSinceEpoch(0);
          return aDate.compareTo(bDate);
        case SortMode.dateDesc:
          DateTime aDate = a.$1['file'] != null
              ? (a.$1['file'] as RemoteFile).lastModified
              : DateTime.fromMillisecondsSinceEpoch(0);
          DateTime bDate = b.$1['file'] != null
              ? (b.$1['file'] as RemoteFile).lastModified
              : DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        case SortMode.sizeAsc:
          return a.$1['size'].compareTo(b.$1['size']);
        case SortMode.sizeDesc:
          return b.$1['size'].compareTo(a.$1['size']);
        case SortMode.typeAsc:
          String aExt = a.$1['name'].contains('.')
              ? a.$1['name'].split('.').last.toLowerCase()
              : '';
          String bExt = b.$1['name'].contains('.')
              ? b.$1['name'].split('.').last.toLowerCase()
              : '';
          return aExt.compareTo(bExt);
        case SortMode.typeDesc:
          String aExt = a.$1['name'].contains('.')
              ? a.$1['name'].split('.').last.toLowerCase()
              : '';
          String bExt = b.$1['name'].contains('.')
              ? b.$1['name'].split('.').last.toLowerCase()
              : '';
          return bExt.compareTo(aExt);
      }
    });
    return sortedItems;
  }

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

    widget.updateAllSelectableItems([
      ...subDirectories.map((subDir) => "${Directory(subDir).path}/"),
      ...widget.remoteFilesMap[dir]!.where((file) =>
          file.key.split('/').last.isNotEmpty &&
          '${File(file.key).parent.path}/' == widget.directory &&
          !jobs.contains(file.key.split('/').last)),
    ]);

    return ListView(
      children: sort([
        (
          {'name': '..', 'size': 0, 'file': null},
          ListTile(
            selected: focusedKey == '..' && widget.selection.isEmpty,
            selectedTileColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            selectedColor: Theme.of(context).colorScheme.primary,
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
              selected: (focusedKey == Directory(subDir).path.split('/').last &&
                      widget.selection.isEmpty) ||
                  widget.selection.any((selected) {
                    if (selected is String) {
                      return selected == "${Directory(subDir).path}/";
                    }
                    return false;
                  }),
              selectedTileColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              selectedColor: Theme.of(context).colorScheme.primary,
              leading: Icon(Icons.folder),
              title: Text("${Directory(subDir).path.split('/').last}/"),
              onTap: widget.selection.isNotEmpty
                  ? () {
                      widget.select("${Directory(subDir).path}/");
                    }
                  : () {
                      widget.onChangeDirectory("${Directory(subDir).path}/");
                    },
              onLongPress: () {
                widget.select("${Directory(subDir).path}/");
              },
              trailing: widget.selection.isNotEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        focusedKey = Directory(subDir).path.split('/').last;
                        setState(() {});
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
                                  widget.downloadDirectory,
                                  widget.saveDirectory,
                                  widget.cut,
                                  widget.copy,
                                  widget.copyDirectory,
                                  widget.moveDirectory,
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
                selected: (focusedKey == file.key.split('/').last &&
                        widget.selection.isEmpty) ||
                    widget.selection.any((selected) {
                      if (selected is RemoteFile) {
                        return selected.key == file.key;
                      }
                      return false;
                    }),
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                selectedColor: Theme.of(context).colorScheme.primary,
                leading: Icon(Icons.insert_drive_file),
                title: Text(file.key.split('/').last),
                subtitle: Text(
                    '${bytesToReadable(file.size)}\t\t\t\t${file.lastModified.toLocal().toString().split('.').first}'),
                trailing: widget.selection.isNotEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          focusedKey = file.key.split('/').last;
                          setState(() {});
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
                                    widget.getLink,
                                    widget.downloadFile,
                                    widget.saveFile,
                                    widget.cut,
                                    widget.copy,
                                    widget.copyFile,
                                    widget.moveFile,
                                    widget.deleteFile,
                                  )).then((value) => widget.listDirectories());
                        },
                        icon: Icon(Icons.more_vert),
                      ),
                onTap: widget.selection.isNotEmpty
                    ? () {
                        widget.select(file);
                      }
                    : File(p.join(widget.localRoot,
                                file.key.split('/').sublist(1).join('/')))
                            .existsSync()
                        ? () {
                            focusedKey = file.key.split('/').last;
                            setState(() {});
                            OpenFile.open(p.join(widget.localRoot,
                                file.key.split('/').sublist(1).join('/')));
                          }
                        : () {
                            focusedKey = file.key.split('/').last;
                            setState(() {});
                            widget
                                .getLink(file, Duration(minutes: 60).inSeconds)
                                .then((value) => launchUrl(Uri.parse(value)));
                          },
                onLongPress: () {
                  widget.select(file);
                },
              ),
            ),
      ])
          .map((item) {
            return item.$2;
          })
          .toList()
          .followedBy([SizedBox(height: 160)])
          .toList(),
    );
  }
}
