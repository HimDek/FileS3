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
  final RemoteFile relativeto;
  final Set<RemoteFile> selection;
  final SelectionAction selectionAction;
  final Function() onUpdate;
  final Function()? Function(RemoteFile) changeDirectory;
  final Function(RemoteFile) select;
  final Function(RemoteFile) showContextMenu;
  final (int, int) Function(RemoteFile, {bool recursive}) count;
  final int Function(RemoteFile) dirSize;
  final String Function(RemoteFile) dirModified;
  final String Function(RemoteFile, int?) getLink;

  const ListFiles({
    super.key,
    required this.files,
    required this.sortMode,
    required this.foldersFirst,
    required this.relativeto,
    required this.selection,
    required this.selectionAction,
    required this.onUpdate,
    required this.changeDirectory,
    required this.select,
    required this.showContextMenu,
    required this.count,
    required this.dirSize,
    required this.dirModified,
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
                dense: MediaQuery.of(context).size.width < 600 ? true : false,
                visualDensity: MediaQuery.of(context).size.width < 600
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                selected: selection.any((selected) {
                  return selected.key == item.key;
                }),
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                selectedColor: Theme.of(context).colorScheme.primary,
                leading: Icon(Icons.folder),
                title: Text(
                  p.isWithin(relativeto.key, item.key)
                      ? "${p.relative(item.key, from: relativeto.key)}/"
                      : "${item.key}/",
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(dirModified(item.file!)),
                          SizedBox(width: 8),
                          Text(bytesToReadable(dirSize(item.file!))),
                          SizedBox(width: 8),
                          Text(() {
                            final count = this.count(
                              item.file!,
                              recursive: true,
                            );
                            if (count.$1 == 0) {
                              return '${count.$2} files';
                            }
                            if (count.$2 == 0) {
                              return '${count.$1} subfolders';
                            }
                            return '${count.$2} files in ${count.$1} subfolders';
                          }()),
                        ],
                      ),
                    ),
                    if (relativeto.key != '${p.dirname(item.file!.key)}/')
                      Row(
                        children: [
                          Text('${Main.backupMode(item.file!.key).name}:'),
                          SizedBox(width: 4),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              Main.pathFromKey(item.file!.key) ?? 'Not set',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                onTap:
                    selection.isNotEmpty &&
                        selectionAction == SelectionAction.none
                    ? () {
                        select(item.file!);
                      }
                    : selection.any(
                        (s) => p.isWithin(s.key, item.key) || s.key == item.key,
                      )
                    ? null
                    : changeDirectory(item.file!),
                onLongPress: selectionAction == SelectionAction.none
                    ? () {
                        select(item.file!);
                      }
                    : null,
                trailing: selection.isNotEmpty
                    ? selection.isEmpty ||
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
                dense: MediaQuery.of(context).size.width < 600 ? true : false,
                visualDensity: MediaQuery.of(context).size.width < 600
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                selected: selection.any((selected) {
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
                    p.isWithin(relativeto.key, item.key)
                        ? p.relative(item.key, from: relativeto.key)
                        : item.file!.key,
                  ),
                ),
                subtitle: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(timeToReadable(item.file!.lastModified!)),
                      SizedBox(width: 8),
                      Text(bytesToReadable(item.size)),
                      const SizedBox(width: 8),
                      Text(
                        item.key.split('.').length > 1
                            ? '.${item.key.split('.').last}'
                            : '',
                      ),
                    ],
                  ),
                ),

                trailing: selection.isNotEmpty
                    ? selection.any((selected) {
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
                        OpenFile.open(Main.pathFromKey(item.key) ?? item.key);
                      }
                    : () {
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
