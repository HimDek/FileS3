import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/media_view.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';
import 'package:files3/job_view.dart';

class MyGridTile extends StatelessWidget {
  final Widget child;
  final Widget? footer;
  final bool selected;
  final Widget? topLeftBadge;
  final Widget? topRightBadge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MyGridTile({
    super.key,
    required this.child,
    this.footer,
    this.selected = false,
    this.topLeftBadge,
    this.topRightBadge,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
        ),
        child: GridTile(
          header: topRightBadge != null || topLeftBadge != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    topLeftBadge ?? SizedBox.shrink(),
                    topRightBadge ?? SizedBox.shrink(),
                  ],
                )
              : null,
          footer: AnimatedContainer(
            duration: Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surface,
            ),
            padding: EdgeInsets.all(8),
            child: footer,
          ),
          child: AnimatedPadding(
            duration: Duration(milliseconds: 250),
            padding: EdgeInsets.only(
              left: selected ? 8 : 0,
              right: selected ? 8 : 0,
              top: selected ? 8 : 0,
              bottom: selected ? 40 : 32,
            ),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 250),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                border: selected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
                borderRadius: selected ? BorderRadius.circular(8) : null,
              ),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 250),
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  borderRadius: selected ? BorderRadius.circular(6) : null,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

sealed class GroupRow {}

class GroupHeaderRow extends GroupRow {
  final String title;
  GroupHeaderRow(this.title);
}

class FileRow extends GroupRow {
  final FileProps file;
  FileRow(this.file);
}

class ListFiles extends StatefulWidget {
  final List<dynamic> files;
  final Map<String, GlobalKey> keys;
  final SortMode sortMode;
  final bool foldersFirst;
  final bool gridView;
  final bool group;
  final RemoteFile relativeto;
  final Set<RemoteFile> selection;
  final SelectionAction selectionAction;
  final Function() onUpdate;
  final Function()? Function(RemoteFile) changeDirectory;
  final void Function()? Function(RemoteFile) getSelectAction;
  final Function(RemoteFile) showContextMenu;
  final Function(BuildContext, RemoteFile) buildContextMenu;
  final (int, int) Function(RemoteFile, {bool recursive}) count;
  final int Function(RemoteFile) dirSize;
  final String Function(RemoteFile) dirModified;
  final String? Function(RemoteFile, int?) getLink;

  const ListFiles({
    super.key,
    required this.files,
    required this.keys,
    required this.sortMode,
    this.foldersFirst = true,
    this.gridView = false,
    this.group = false,
    required this.relativeto,
    required this.selection,
    required this.selectionAction,
    required this.onUpdate,
    required this.changeDirectory,
    required this.getSelectAction,
    required this.showContextMenu,
    required this.buildContextMenu,
    required this.count,
    required this.dirSize,
    required this.dirModified,
    required this.getLink,
  });

  @override
  State<StatefulWidget> createState() => ListFilesState();
}

class ListFilesState extends State<ListFiles> {
  List<FileProps> _sortedFiles = [];
  List<GalleryProps>? _galleryFiles;
  List<MapEntry<String, List<FileProps>>> _groups = [];

  Map<String, List<FileProps>> getGroups() {
    Map<String, List<FileProps>> grouped = {};
    SortMode? groupBy = widget.group ? widget.sortMode : null;
    for (var file in _sortedFiles) {
      String key;
      switch (groupBy) {
        case SortMode.nameAsc || SortMode.nameDesc:
          String fileKey = p.isWithin(widget.relativeto.key, file.key)
              ? p.s3(p.asDir(p.relative(file.key, from: widget.relativeto.key)))
              : file.key;
          key = fileKey.isNotEmpty ? fileKey[0].toUpperCase() : '#';
          if (!RegExp(r'^[A-Z0-9]$').hasMatch(key)) {
            key = '#';
          }
          break;
        case SortMode.sizeAsc || SortMode.sizeDesc:
          if (file.size < 1024) {
            key = '0 B - 1 KB';
          } else if (file.size < 1024 * 1024) {
            key = '1 KB - 1 MB';
          } else if (file.size < 1024 * 1024 * 1024) {
            key = '1 MB - 1 GB';
          } else {
            key = '> 1 GB';
          }
          break;
        case SortMode.dateAsc || SortMode.dateDesc:
          DateTime modified =
              file.file?.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
          Duration diff = DateTime.now().difference(modified);
          if (diff.inHours < 1) {
            key = 'Last Hour';
          } else if (diff.inDays <= 1) {
            key = 'Today';
          } else if (diff.inDays <= 7 &&
              modified.month == DateTime.now().month) {
            key = 'This Week';
          } else {
            key = '${monthToString(modified.month)} ${modified.year}';
          }
          break;
        case SortMode.typeAsc || SortMode.typeDesc:
          key = p.extension(file.key).isNotEmpty
              ? p.extension(file.key).toUpperCase()
              : 'No Extension';
          break;
        default:
          key = 'All Files';
      }
      if (grouped.containsKey(key)) {
        grouped[key]!.add(file);
      } else {
        grouped[key] = [file];
      }
    }
    return grouped;
  }

  Future<int?> pushGallery(BuildContext context, int index) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<int>(
          pageBuilder: (_, _, _) => Gallery(
            keys: widget.keys,
            files: _galleryFiles!,
            initialIndex: index,
            buildContextMenu: (file) {
              return widget.buildContextMenu(context, file);
            },
          ),
        ),
      );

  Widget preview(FileProps item) {
    return getMediaType(item.key) != null
        ? SizedBox(
            height: 24,
            width: 24,
            child: FutureBuilder<String>(
              future: () async {
                return (await File(
                      Main.pathFromKey(item.key) ?? item.key,
                    ).exists())
                    ? Main.pathFromKey(item.key) ?? item.key
                    : Main.cachePathFromKey(item.key);
              }(),
              builder: (context, snapshot) {
                return MediaPreview(
                  remoteKey: item.key,
                  height: 24,
                  width: 24,
                  mediaProvider: MyUrlMediaProvider(
                    p.isWithin(widget.relativeto.key, item.key)
                        ? p.s3(
                            p.relative(item.key, from: widget.relativeto.key),
                          )
                        : item.file!.key,
                    getMediaType(item.key)!,
                    item.url!,
                    snapshot.connectionState == ConnectionState.waiting
                        ? Main.cachePathFromKey(item.key)
                        : snapshot.hasData && snapshot.data != null
                        ? snapshot.data!
                        : Main.cachePathFromKey(item.key),
                    size: item.size,
                  ),
                );
              },
            ),
          )
        : Icon(Icons.insert_drive_file);
  }

  Widget listItemBuilder(BuildContext context, FileProps item) {
    return item.job != null
        ? JobView(
            job: item.job!,
            relativeTo: widget.relativeto,
            onUpdate: widget.onUpdate,
          )
        : p.isDir(item.key)
        ? ListTile(
            dense: MediaQuery.of(context).size.width < 600 ? true : false,
            visualDensity: MediaQuery.of(context).size.width < 600
                ? VisualDensity.compact
                : VisualDensity.standard,
            selected: widget.selection.any(
              (selected) =>
                  selected.key == item.key ||
                  p.isWithin(selected.key, item.key),
            ),
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            selectedColor: Theme.of(context).colorScheme.primary,
            leading: Icon(
              p.split(item.key).length > 1
                  ? Icons.folder
                  : Icons.cloud_circle_rounded,
            ),
            title: Text(
              p.isWithin(widget.relativeto.key, item.key)
                  ? p.s3(
                      p.asDir(
                        p.relative(item.key, from: widget.relativeto.key),
                      ),
                    )
                  : item.key,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(widget.dirModified(item.file!)),
                      SizedBox(width: 8),
                      Text(bytesToReadable(widget.dirSize(item.file!))),
                      SizedBox(width: 8),
                      Text(() {
                        final count = widget.count(item.file!, recursive: true);
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
                if (p.s3(p.dirname(item.file!.key)).isEmpty)
                  Row(
                    children: [
                      Text('${Main.backupModeFromKey(item.file!.key).name}:'),
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
            onTap: widget.selection.isNotEmpty
                ? widget.getSelectAction(item.file!)
                : widget.changeDirectory(item.file!),
            onLongPress: widget.getSelectAction(item.file!),
            trailing: widget.selection.isNotEmpty
                ? widget.selection.any((selected) => selected.key == item.key)
                      ? Icon(Icons.check_circle)
                      : widget.selection.any(
                          (selected) => p.isWithin(selected.key, item.key),
                        )
                      ? Icon(Icons.check_circle_outline)
                      : widget.selectionAction == SelectionAction.none
                      ? Icon(Icons.circle_outlined)
                      : null
                : IconButton(
                    onPressed: () async {
                      widget.showContextMenu(item.file!);
                    },
                    icon: Icon(Icons.more_vert),
                  ),
          )
        : ListTile(
            dense: MediaQuery.of(context).size.width < 600 ? true : false,
            visualDensity: MediaQuery.of(context).size.width < 600
                ? VisualDensity.compact
                : VisualDensity.standard,
            selected: widget.selection.any(
              (selected) =>
                  selected.key == item.key ||
                  p.isWithin(selected.key, item.key),
            ),
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            selectedColor: Theme.of(context).colorScheme.primary,
            leading: Hero(tag: item.key, child: preview(item)),
            title: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                p.isWithin(widget.relativeto.key, item.key)
                    ? p.s3(p.relative(item.key, from: widget.relativeto.key))
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
                  SizedBox(width: 8),
                  FutureBuilder(
                    future: File(
                      Main.pathFromKey(item.key) ?? item.key,
                    ).exists(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Icon(Icons.hourglass_empty, size: 16);
                      }
                      if (snapshot.hasData && snapshot.data == true) {
                        return Icon(Icons.download_done, size: 16);
                      } else {
                        return Icon(
                          Icons.cloud_download,
                          color: Theme.of(context).colorScheme.primary,
                          size: 16,
                        );
                      }
                    },
                  ),
                  SizedBox(width: 8),
                  Text(p.extension(item.key)),
                ],
              ),
            ),
            trailing: widget.selection.isNotEmpty
                ? widget.selection.any((selected) => selected.key == item.key)
                      ? Icon(Icons.check_circle)
                      : widget.selection.any(
                          (selected) => p.isWithin(selected.key, item.key),
                        )
                      ? Icon(Icons.check_circle_outline)
                      : widget.selectionAction == SelectionAction.none
                      ? Icon(Icons.circle_outlined)
                      : null
                : IconButton(
                    onPressed: () async {
                      widget.showContextMenu(item.file!);
                    },
                    icon: Icon(Icons.more_vert),
                  ),
            onTap: widget.selection.isNotEmpty
                ? widget.getSelectAction(item.file!)
                : () => pushGallery(
                    context,
                    _galleryFiles!.indexWhere((f) => f.file.key == item.key),
                  ),
            onLongPress: widget.getSelectAction(item.file!),
          );
  }

  Widget gridItemBuilder(BuildContext context, FileProps item) {
    return item.job != null
        ? JobView(
            job: item.job!,
            relativeTo: widget.relativeto,
            onUpdate: widget.onUpdate,
            grid: true,
          )
        : p.isDir(item.key)
        ? MyGridTile(
            selected: widget.selection.any(
              (selected) =>
                  selected.key == item.key ||
                  p.isWithin(selected.key, item.key),
            ),
            footer: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    p.isWithin(widget.relativeto.key, item.key)
                        ? p.s3(
                            p.asDir(
                              p.relative(item.key, from: widget.relativeto.key),
                            ),
                          )
                        : item.key,
                  ),
                ),
              ],
            ),
            onTap: widget.changeDirectory(item.file!),
            onLongPress: widget.getSelectAction(item.file!),
            topRightBadge: widget.selection.isNotEmpty
                ? widget.selectionAction == SelectionAction.none
                      ? IconButton(
                          icon: Icon(
                            widget.selection.isEmpty ||
                                    widget.selection.any((selected) {
                                      return selected.key == item.key;
                                    })
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: widget.getSelectAction(item.file!),
                        )
                      : widget.selection.any(
                          (selected) => selected.key == item.key,
                        )
                      ? IconButton(
                          icon: Icon(Icons.check_circle),
                          onPressed: null,
                          color: Theme.of(context).colorScheme.primary,
                          disabledColor: Theme.of(context).colorScheme.primary,
                        )
                      : widget.selection.any(
                          (selected) => p.isWithin(selected.key, item.key),
                        )
                      ? IconButton(
                          icon: Icon(Icons.check_circle_outline),
                          onPressed: null,
                          color: Theme.of(context).colorScheme.primary,
                          disabledColor: Theme.of(context).colorScheme.primary,
                        )
                      : null
                : IconButton(
                    onPressed: () async {
                      widget.showContextMenu(item.file!);
                    },
                    icon: Icon(Icons.more_vert),
                  ),
            child: Icon(
              p.split(item.key).length > 1
                  ? Icons.folder
                  : Icons.cloud_circle_rounded,
            ),
          )
        : MyGridTile(
            selected: widget.selection.any(
              (selected) =>
                  selected.key == item.key ||
                  p.isWithin(selected.key, item.key),
            ),
            footer: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    p.isWithin(widget.relativeto.key, item.key)
                        ? p.s3(
                            p.relative(item.key, from: widget.relativeto.key),
                          )
                        : item.file!.key,
                  ),
                ),
              ],
            ),
            topLeftBadge: Padding(
              padding: EdgeInsets.all(16),
              child: FutureBuilder(
                future: File(Main.pathFromKey(item.key) ?? item.key).exists(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox.shrink();
                  }
                  if (snapshot.hasData && snapshot.data == true) {
                    return Icon(Icons.download_done, size: 16);
                  } else {
                    return Icon(
                      Icons.cloud_download,
                      color: Theme.of(context).colorScheme.primary,
                      size: 16,
                    );
                  }
                },
              ),
            ),
            topRightBadge: widget.selection.isNotEmpty
                ? widget.selectionAction == SelectionAction.none
                      ? IconButton(
                          icon: Icon(
                            widget.selection.isEmpty ||
                                    widget.selection.any((selected) {
                                      return selected.key == item.key;
                                    })
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: widget.getSelectAction(item.file!),
                        )
                      : widget.selection.any(
                          (selected) => selected.key == item.key,
                        )
                      ? IconButton(
                          icon: Icon(Icons.check_circle),
                          onPressed: null,
                          color: Theme.of(context).colorScheme.primary,
                          disabledColor: Theme.of(context).colorScheme.primary,
                        )
                      : widget.selection.any(
                          (selected) => p.isWithin(selected.key, item.key),
                        )
                      ? IconButton(
                          icon: Icon(Icons.check_circle_outline),
                          onPressed: null,
                          color: Theme.of(context).colorScheme.primary,
                          disabledColor: Theme.of(context).colorScheme.primary,
                        )
                      : null
                : IconButton(
                    onPressed: () async {
                      widget.showContextMenu(item.file!);
                    },
                    icon: Icon(Icons.more_vert),
                  ),
            onLongPress: widget.getSelectAction(item.file!),
            child: GestureDetector(
              onTap: () => pushGallery(
                context,
                _galleryFiles!.indexWhere((f) => f.file.key == item.key),
              ),
              child: Hero(tag: item.key, child: preview(item)),
            ),
          );
  }

  @override
  void didUpdateWidget(covariant ListFiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.files != widget.files) {
      _sortedFiles = sort(
        widget.files.map((file) {
          String url =
              widget.getLink(
                file is Job
                    ? RemoteFile(
                        key: file.remoteKey,
                        size: file.bytes,
                        etag: file.md5.toString(),
                      )
                    : file,
                null,
              ) ??
              '';
          return file is Job
              ? FileProps(
                  key: file.remoteKey,
                  size: file.bytes,
                  job: file,
                  url: url,
                )
              : p.isDir(file.key)
              ? FileProps(key: file.key, size: file.size, file: file, url: url)
              : FileProps(key: file.key, size: file.size, file: file, url: url);
        }),
        widget.sortMode,
        widget.foldersFirst,
      );
      _galleryFiles = _sortedFiles
          .where((f) {
            return !p.isDir(f.key);
          })
          .map(
            (f) => GalleryProps(
              file:
                  f.file ??
                  RemoteFile(
                    key: f.key,
                    size: f.size,
                    etag: f.job!.md5.toString(),
                  ),
              title: p.isWithin(widget.relativeto.key, f.key)
                  ? p.s3(p.relative(f.key, from: widget.relativeto.key))
                  : f.key,
              url: f.url!,
              path: File(Main.pathFromKey(f.key) ?? f.key).existsSync()
                  ? (Main.pathFromKey(f.key) ?? f.key)
                  : Main.cachePathFromKey(f.key),
            ),
          )
          .toList();
      _groups = getGroups().entries.toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiSliver(children: buildSlivers(context));
  }

  List<Widget> buildSlivers(BuildContext context) {
    final slivers = <Widget>[];

    for (final group in _groups) {
      if (widget.group) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                group.key,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        );
      }

      if (widget.gridView) {
        slivers.add(
          SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width < 600 ? 4 : 6,
              childAspectRatio: 3 / 4,
            ),
            itemCount: group.value.length,
            itemBuilder: (context, i) {
              final file = group.value[i];
              widget.keys[file.key] ??= GlobalKey();
              return gridItemBuilder(context, file);
            },
          ),
        );
      } else {
        slivers.add(
          SliverList.builder(
            itemCount: group.value.length,
            itemBuilder: (context, i) {
              final file = group.value[i];
              widget.keys[file.key] ??= GlobalKey();
              return listItemBuilder(context, file);
            },
          ),
        );
      }
    }

    return slivers;
  }
}
