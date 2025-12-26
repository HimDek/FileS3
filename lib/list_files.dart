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

class ListFiles extends StatelessWidget {
  final List<dynamic> files;
  final SortMode sortMode;
  final bool foldersFirst;
  final String relativeto;
  final String? focusedKey;
  final Set<RemoteFile> selection;
  final SelectionAction selectionAction;
  final Function() onUpdate;
  final Function(String) setFocus;
  final Function(String) onChangeDirectory;
  final Function(RemoteFile) select;
  final Function(RemoteFile) showContextMenu;
  final String Function(RemoteFile, int?) getLink;

  const ListFiles({
    super.key,
    required this.files,
    required this.sortMode,
    required this.foldersFirst,
    required this.relativeto,
    required this.focusedKey,
    required this.selection,
    required this.selectionAction,
    required this.onUpdate,
    required this.setFocus,
    required this.onChangeDirectory,
    required this.select,
    required this.showContextMenu,
    required this.getLink,
  });

  @override
  Widget build(BuildContext context) {
    final sortedFiles = sort(
      files.map(
        (file) => file is Job
            ? FileProps(key: file.remoteKey, size: file.bytes, job: file)
            : file.key.endsWith('/')
            ? FileProps(key: file.key, size: file.size, file: file)
            : FileProps(key: file.key, size: file.size, file: file),
      ),
      sortMode,
      foldersFirst,
    );
    return SliverList.builder(
      itemCount: sortedFiles.length,
      itemBuilder: (context, index) {
        final item = sortedFiles[index];
        return item.job != null
            ? JobView(
                job: item.job!,
                relativeTo: relativeto,
                onUpdate: onUpdate,
              )
            : item.key.endsWith('/')
            ? ListTile(
                selected:
                    (focusedKey == item.key && selection.isEmpty) ||
                    selection.any((selected) {
                      return selected.key == item.key;
                    }),
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                selectedColor: Theme.of(context).colorScheme.primary,
                leading: Icon(Icons.folder),
                title: Text(
                  p.isWithin(relativeto, item.key)
                      ? "${p.relative(item.key, from: relativeto)}/"
                      : "${item.key}/",
                ),
                subtitle: Text(
                  '${bytesToReadable(item.size)}\t\t\t\t${item.file!.lastModified.toLocal().toString().split('.').first}',
                ),
                onTap:
                    selection.isNotEmpty &&
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
                    ? (focusedKey == item.key && selection.isEmpty) ||
                              selection.any((selected) {
                                return selected.key == item.key;
                              })
                          ? Icon(Icons.check)
                          : null
                    : IconButton(
                        onPressed: () async {
                          showContextMenu(item.file!);
                        },
                        icon: Icon(Icons.more_vert),
                      ),
              )
            : ListTile(
                selected:
                    (focusedKey == item.key && selection.isEmpty) ||
                    selection.any((selected) {
                      return selected.key == item.key;
                    }),
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                selectedColor: Theme.of(context).colorScheme.primary,
                leading: Icon(Icons.insert_drive_file),
                title: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    p.isWithin(relativeto, item.key)
                        ? p.relative(item.key, from: relativeto)
                        : item.file!.key,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Text(bytesToReadable(item.size)),
                    SizedBox(width: 16),
                    Text(
                      item.file!.lastModified
                          .toLocal()
                          .toString()
                          .split('.')
                          .first,
                    ),
                  ],
                ),

                trailing: selection.isNotEmpty
                    ? (focusedKey == item.key && selection.isEmpty) ||
                              selection.any((selected) {
                                return selected.key == item.key;
                              })
                          ? Icon(Icons.check)
                          : null
                    : IconButton(
                        onPressed: () async {
                          showContextMenu(item.file!);
                        },
                        icon: Icon(Icons.more_vert),
                      ),
                onTap:
                    selection.isNotEmpty &&
                        selectionAction == SelectionAction.none
                    ? () {
                        select(item.file!);
                      }
                    : selectionAction != SelectionAction.none
                    ? null
                    : File(Main.pathFromKey(item.key) ?? item.key).existsSync()
                    ? () {
                        setFocus(item.key);
                        OpenFile.open(Main.pathFromKey(item.key) ?? item.key);
                      }
                    : () {
                        setFocus(item.key);
                        launchUrl(
                          Uri.parse(
                            getLink(
                              item.file!,
                              Duration(minutes: 60).inSeconds,
                            ),
                          ),
                        );
                      },
                onLongPress: selectionAction == SelectionAction.none
                    ? () {
                        select(item.file!);
                      }
                    : null,
              );
      },
    );
  }
}
