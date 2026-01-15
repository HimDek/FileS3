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
        duration: Duration(milliseconds: 250),
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
            duration: Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surface,
            ),
            padding: EdgeInsets.all(8),
            child: footer,
          ),
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 250),
            padding: EdgeInsets.only(
              left: selected ? 8 : 0,
              right: selected ? 8 : 0,
              top: selected ? 8 : 0,
              bottom: selected ? 40 : 32,
            ),
            child: Stack(
              children: [
                AnimatedPadding(
                  duration: Duration(milliseconds: 250),
                  padding: EdgeInsets.all(selected ? 2 : 0),
                  child: Center(child: child),
                ),
                AnimatedContainer(
                  duration: Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    border: selected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(selected ? 4 : 0),
                  ),
                ),
              ],
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
  final List<FileProps> files;
  final Function(List<GalleryProps>)? setGalleryFiles;
  final Map<String, double> keysOffsetMap;
  final SortMode sortMode;
  final bool gridView;
  final bool group;
  final RemoteFile relativeto;
  final Set<RemoteFile> selection;
  final SelectionAction selectionAction;
  final void Function(int) showGallery;
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
    this.setGalleryFiles,
    required this.keysOffsetMap,
    required this.sortMode,
    this.gridView = false,
    this.group = false,
    required this.relativeto,
    required this.selection,
    required this.selectionAction,
    required this.showGallery,
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
  List<MapEntry<String, List<FileProps>>> _groups = [];

  Map<String, List<FileProps>> getGroups() {
    Map<String, List<FileProps>> grouped = {};
    SortMode? groupBy = widget.group ? widget.sortMode : null;
    for (var file in widget.files) {
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
          } else if (file.size < 1024 * 1024 * 10) {
            key = '1 MB - 10 MB';
          } else if (file.size < 1024 * 1024 * 32) {
            key = '10 MB - 32 MB';
          } else if (file.size < 1024 * 1024 * 128) {
            key = '32 MB - 128 MB';
          } else if (file.size < 1024 * 1024 * 512) {
            key = '128 MB - 512 MB';
          } else if (file.size < 1024 * 1024 * 1024) {
            key = '512 MB - 1 GB';
          } else if (file.size < 1024 * 1024 * 1024) {
            key = '100 MB - 1 GB';
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
              : p.isDir(file.key)
              ? 'Folders'
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

  Widget preview(FileProps item) {
    return getMediaType(item.key) != null
        ? SizedBox(
            height: 256,
            width: 256,
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
                  height: 256,
                  width: 256,
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
            leading: SizedBox(
              height: 32,
              width: 32,
              child: Icon(
                p.split(item.key).length > 1
                    ? Icons.folder
                    : Icons.cloud_circle_rounded,
              ),
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
            leading: Hero(
              tag: item.key,
              child: SizedBox(height: 32, width: 32, child: preview(item)),
            ),
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
                : () => widget.showGallery(widget.files.indexOf(item)),
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
            onTap: () => widget.showGallery(widget.files.indexOf(item)),
            onLongPress: widget.getSelectAction(item.file!),
            child: Hero(tag: item.key, child: preview(item)),
          );
  }

  void buildKeysOffsetMap(BuildContext context) {
    widget.keysOffsetMap.clear();

    final width = MediaQuery.of(context).size.width;
    final columns = width < 600 ? 4 : 6;
    final tileWidth = width / columns;
    final tileHeight = tileWidth * (4 / 3); // inverse of 3/4

    double offset = 0;

    for (final group in _groups) {
      // Header height (if enabled)
      if (widget.group) {
        final style = Theme.of(context).textTheme.titleMedium!;
        final painter = TextPainter(
          text: TextSpan(text: group.key, style: style),
          textDirection: TextDirection.ltr,
        )..layout();

        offset += painter.height + 16; // 8px top + 8px bottom padding
      }

      // Grid items
      if (!widget.gridView) {
        // List view
        for (final file in group.value) {
          final listTileHeight = MediaQuery.of(context).size.width < 600
              ? 56.0
              : 72.0; // approximate heights for dense and standard ListTiles
          widget.keysOffsetMap[file.key] = offset;
          offset += listTileHeight;
        }
        continue;
      }

      for (int i = 0; i < group.value.length; i++) {
        final file = group.value[i];
        final row = i ~/ columns;
        widget.keysOffsetMap[file.key] = offset + row * tileHeight;
      }

      // Skip past this group’s grid
      final rows = (group.value.length + columns - 1) ~/ columns;
      offset += rows * tileHeight;
    }
  }

  @override
  void didUpdateWidget(covariant ListFiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.files != widget.files) {
      widget.setGalleryFiles?.call(
        widget.files
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
            .toList(),
      );
      _groups = getGroups().entries.toList();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      buildKeysOffsetMap(context);
    });
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
              return listItemBuilder(context, file);
            },
          ),
        );
      }
    }

    return slivers;
  }
}
