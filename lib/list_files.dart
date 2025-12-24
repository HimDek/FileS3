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

// class ListFiles extends StatelessWidget {
//   final BuildContext context;
//   final List<dynamic> files;
//   final SortMode sortMode;
//   final bool foldersFirst;
//   final Function(RemoteFile) showContextMenu;
//   final bool showFullPath;
//   final Processor processor;
//   final String? focusedKey;
//   final Set<RemoteFile> selection;
//   final SelectionAction selectionAction;
//   final void Function(RemoteFile) select;
//   final String Function(String) pathFromKey;
//   final Function(String) setFocus;
//   final Function(int) setNavIndex;
//   final Function() onJobUpdate;
//   final Function(Job, dynamic) onJobComplete;
//   final Function(Job) removeJob;
//   final Function(String) onChangeDirectory;
//   final String Function(RemoteFile, int?) getLink;
//   final Function() stopWatchers;

//   const ListFiles({
//     super.key,
//     required this.context,
//     required this.files,
//     required this.sortMode,
//     required this.foldersFirst,
//     required this.showContextMenu,
//     required this.showFullPath,
//     required this.processor,
//     required this.focusedKey,
//     required this.selection,
//     required this.selectionAction,
//     required this.select,
//     required this.pathFromKey,
//     required this.setFocus,
//     required this.setNavIndex,
//     required this.onJobUpdate,
//     required this.onJobComplete,
//     required this.removeJob,
//     required this.onChangeDirectory,
//     required this.getLink,
//     required this.stopWatchers,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: listFiles(
//         this.context,
//         files,
//         sortMode,
//         foldersFirst,
//         showContextMenu,
//         showFullPath,
//         processor,
//         focusedKey,
//         selection,
//         selectionAction,
//         select,
//         pathFromKey,
//         setFocus,
//         setNavIndex,
//         onJobUpdate,
//         onJobComplete,
//         removeJob,
//         onChangeDirectory,
//         getLink,
//         stopWatchers,
//       ),
//     );
//   }
// }

List<Widget> listFiles(
  BuildContext context,
  List<dynamic> files,
  SortMode sortMode,
  bool foldersFirst,
  String relativeto,
  String? focusedKey,
  Set<RemoteFile> selection,
  SelectionAction selectionAction,
  Function() onUpdate,
  Function(String) setFocus,
  Function(String) onChangeDirectory,
  Function(RemoteFile) select,
  Function(RemoteFile) showContextMenu,
  String Function(RemoteFile, int?) getLink,
  String Function(String) pathFromKey,
) {
  Iterable<Job> jobs = files.whereType<Job>();
  Iterable<RemoteFile> remoteFiles = files.whereType<RemoteFile>();

  List<FileProps> list = sort([
    for (RemoteFile file in remoteFiles.where((file) => file.key.endsWith('/')))
      FileProps(
        key: file.key,
        size: file.size,
        file: file,
      ),
    for (Job job in jobs)
      FileProps(
        key: job.remoteKey,
        size: job.bytes,
        job: job,
      ),
    for (RemoteFile file in remoteFiles)
      if (!file.key.endsWith('/'))
        FileProps(
          key: file.key,
          size: file.size,
          file: file,
        ),
  ], sortMode, foldersFirst);

  return list
      .map(
        (item) => item.job != null
            ? JobView(
                job: item.job!,
                relativeTo: relativeto,
                onUpdate: onUpdate,
              )
            : item.key.endsWith('/')
                ? ListTile(
                    selected: (focusedKey == item.key && selection.isEmpty) ||
                        selection.any((selected) {
                          return selected.key == item.key;
                        }),
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    selectedColor: Theme.of(context).colorScheme.primary,
                    leading: Icon(Icons.folder),
                    title: Text(p.isWithin(relativeto, item.key)
                        ? "${p.relative(item.key, from: relativeto)}/"
                        : "${item.key}/"),
                    subtitle: Text(
                        '${bytesToReadable(item.size)}\t\t\t\t${item.file!.lastModified.toLocal().toString().split('.').first}'),
                    onTap: selection.isNotEmpty &&
                            selectionAction == SelectionAction.none
                        ? () {
                            select(item.file!);
                          }
                        : () {
                            onChangeDirectory(item.key);
                          },
                    onLongPress: selectionAction == SelectionAction.none
                        ? () {
                            select(item.file!);
                          }
                        : null,
                    trailing: selection.isNotEmpty
                        ? null
                        : IconButton(
                            onPressed: () async {
                              showContextMenu(item.file!);
                            },
                            icon: Icon(Icons.more_vert),
                          ),
                  )
                : ListTile(
                    selected: (focusedKey == item.key && selection.isEmpty) ||
                        selection.any((selected) {
                          return selected.key == item.key;
                        }),
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    selectedColor: Theme.of(context).colorScheme.primary,
                    leading: Icon(Icons.insert_drive_file),
                    title: Text(p.isWithin(relativeto, item.key)
                        ? p.relative(item.key, from: relativeto)
                        : item.file!.key),
                    subtitle: Text(
                        '${bytesToReadable(item.size)}\t\t\t\t${item.file!.lastModified.toLocal().toString().split('.').first}'),
                    trailing: selection.isNotEmpty
                        ? null
                        : IconButton(
                            onPressed: () async {
                              showContextMenu(item.file!);
                            },
                            icon: Icon(Icons.more_vert),
                          ),
                    onTap: selection.isNotEmpty &&
                            selectionAction == SelectionAction.none
                        ? () {
                            select(item.file!);
                          }
                        : selectionAction != SelectionAction.none
                            ? null
                            : File(pathFromKey(item.key)).existsSync()
                                ? () {
                                    setFocus(item.key);
                                    OpenFile.open(pathFromKey(item.key));
                                  }
                                : () {
                                    setFocus(item.key);
                                    launchUrl(Uri.parse(getLink(item.file!,
                                        Duration(minutes: 60).inSeconds)));
                                  },
                    onLongPress: selectionAction == SelectionAction.none
                        ? () {
                            select(item.file!);
                          }
                        : null,
                  ),
      )
      .toList();
}
