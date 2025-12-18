import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:s3_drive/components.dart';
import 'package:s3_drive/job_view.dart';
import 'package:s3_drive/services/job.dart';
import 'package:s3_drive/services/models/common.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:url_launcher/url_launcher.dart';

List<(Map<String, dynamic>, Widget)> listFiles(
  BuildContext context,
  List<dynamic> files,
  bool showFullPath,
  Processor processor,
  String? focusedKey,
  Set<dynamic> selection,
  SelectionAction selectionAction,
  void Function(dynamic) select,
  String Function(String) pathFromKey,
  Function(String) setFocus,
  Function(int) setNavIndex,
  Function() onJobUpdate,
  Function(Job, dynamic) onJobComplete,
  Function(Job) removeJob,
  Function(String) onChangeDirectory,
  Future<String> Function(RemoteFile, int?) getLink,
  Function(RemoteFile) downloadFile,
  Function(String) downloadDirectory,
  Function(RemoteFile, String) saveFile,
  Function(String, String) saveDirectory,
  Function(dynamic) cut,
  Function(dynamic) copy,
  Function(String, String, {bool refresh}) moveFile,
  Function(String, String, {bool refresh}) moveDirectory,
  Function(String, {bool refresh}) deleteFile,
  Function(String, {bool refresh}) deleteDirectory,
  Function() listDirectories,
  Function() stopWatchers,
) {
  Iterable<String> dirs = files.whereType<String>();
  Iterable<Job> jobs = files.whereType<Job>();
  Iterable<RemoteFile> remoteFiles = files.whereType<RemoteFile>();
  return [
    for (String file in dirs)
      (
        {
          'name': Directory(file).path,
          'size': 0,
          'file': null,
        },
        ListTile(
          selected: (focusedKey == Directory(file).path && selection.isEmpty) ||
              selection.any((selected) {
                if (selected is String) {
                  return selected == "${Directory(file).path}/";
                }
                return false;
              }),
          selectedTileColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          selectedColor: Theme.of(context).colorScheme.primary,
          leading: Icon(Icons.folder),
          title: Text("${p.basename(Directory(file).path)}/"),
          onTap: selection.isNotEmpty && selectionAction == SelectionAction.none
              ? () {
                  select("${Directory(file).path}/");
                }
              : () {
                  setNavIndex(0);
                  onChangeDirectory("${Directory(file).path}/");
                },
          onLongPress: selectionAction == SelectionAction.none
              ? () {
                  select("${Directory(file).path}/");
                }
              : null,
          trailing: selection.isNotEmpty
              ? null
              : IconButton(
                  onPressed: () async {
                    setFocus(Directory(file).path);
                    await stopWatchers();
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
                        "${Directory(file).path}/",
                        pathFromKey,
                        downloadDirectory,
                        saveDirectory,
                        cut,
                        copy,
                        (String dir, String newDir) =>
                            moveDirectory(dir, newDir, refresh: false),
                        (String dir) => deleteDirectory(dir, refresh: false),
                      ),
                    ).then((value) => listDirectories());
                  },
                  icon: Icon(Icons.more_vert),
                ),
        ),
      ),
    for (Job job in jobs)
      (
        {
          'name': job.remoteKey,
          'size': job.bytes,
          'file': job.localFile,
          'job': job,
        },
        JobView(
          job: job,
          processor: processor,
          onUpdate: onJobUpdate,
          onJobComplete: onJobComplete,
          remove: () => removeJob(job),
        ),
      ),
    for (RemoteFile file in remoteFiles)
      (
        {
          'name': file.key,
          'size': file.size,
          'file': file,
        },
        ListTile(
          selected: (focusedKey == file.key && selection.isEmpty) ||
              selection.any((selected) {
                if (selected is RemoteFile) {
                  return selected.key == file.key;
                }
                return false;
              }),
          selectedTileColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          selectedColor: Theme.of(context).colorScheme.primary,
          leading: Icon(Icons.insert_drive_file),
          title: Text(showFullPath ? file.key : file.key.split('/').last),
          subtitle: Text(
              '${bytesToReadable(file.size)}\t\t\t\t${file.lastModified.toLocal().toString().split('.').first}'),
          trailing: selection.isNotEmpty
              ? null
              : IconButton(
                  onPressed: () async {
                    setFocus(file.key);
                    await stopWatchers();
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
                        pathFromKey,
                        getLink,
                        downloadFile,
                        saveFile,
                        cut,
                        copy,
                        (String key, String newKey) =>
                            moveFile(key, newKey, refresh: false),
                        (String key) => deleteFile(key, refresh: false),
                      ),
                    ).then((value) => listDirectories());
                  },
                  icon: Icon(Icons.more_vert),
                ),
          onTap: selection.isNotEmpty && selectionAction == SelectionAction.none
              ? () {
                  select(file);
                }
              : selectionAction != SelectionAction.none
                  ? null
                  : File(pathFromKey(file.key)).existsSync()
                      ? () {
                          setFocus(file.key);
                          OpenFile.open(pathFromKey(file.key));
                        }
                      : () {
                          setFocus(file.key);
                          getLink(file, Duration(minutes: 60).inSeconds)
                              .then((value) => launchUrl(Uri.parse(value)));
                        },
          onLongPress: selectionAction == SelectionAction.none
              ? () {
                  select(file);
                }
              : null,
        ),
      ),
  ];
}
