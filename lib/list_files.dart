import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/models.dart';
import 'package:files3/helpers.dart';
import 'package:files3/job_view.dart';
import 'package:files3/media_view.dart';

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
  final ValueNotifier<List<FileProps>> files;
  final List<GalleryProps> galleryFiles;
  final void Function(List<GalleryProps>)? setGalleryFiles;
  final ValueNotifier<ListOptions> listOptions;
  final ValueNotifier<RemoteFile> relativeto;
  final ValueNotifier<Set<RemoteFile>> selection;
  final ValueNotifier<SelectionAction> selectionAction;
  final ValueNotifier<Map<String, double>> keysOffsetMap;
  final Map<String, double> groupOffsetMap;
  final void Function(int)? showGallery;
  final Function(RemoteFile) changeDirectory;
  final void Function()? Function(RemoteFile) getSelectAction;
  final Function(RemoteFile)? showContextMenu;
  final (int, int) Function(RemoteFile, {bool recursive}) count;
  final int Function(RemoteFile) dirSize;
  final String Function(RemoteFile) dirModified;

  static void Function()? setSelectActionDefault(RemoteFile file) => () {};

  const ListFiles({
    super.key,
    required this.files,
    this.galleryFiles = const [],
    this.setGalleryFiles,
    this.groupOffsetMap = const {},
    required this.listOptions,
    required this.relativeto,
    required this.selection,
    required this.selectionAction,
    required this.keysOffsetMap,
    this.showGallery,
    required this.changeDirectory,
    this.getSelectAction = setSelectActionDefault,
    this.showContextMenu,
    required this.count,
    required this.dirSize,
    required this.dirModified,
  });

  @override
  State<StatefulWidget> createState() => ListFilesState();
}

class ListFilesState extends State<ListFiles> {
  final Map<String, bool> _fileDownloadedCache = {};
  final ValueNotifier<List<MapEntry<String, List<FileProps>>>> _groups =
      ValueNotifier([]);

  String? groupFromKey(String key) {
    return _groups.value
        .firstWhereOrNull((group) => group.value.any((file) => file.key == key))
        ?.key;
  }

  void makeGroups() {
    Map<String, List<FileProps>> grouped = {};
    SortMode? groupBy = widget.listOptions.value.sortMode;
    for (var file in widget.files.value) {
      String key;
      switch (groupBy) {
        case SortMode.nameAsc || SortMode.nameDesc:
          String fileKey = p.isWithin(widget.relativeto.value.key, file.key)
              ? p.s3(
                  p.asDir(
                    p.relative(file.key, from: widget.relativeto.value.key),
                  ),
                )
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
      }
      if (grouped.containsKey(key)) {
        grouped[key]!.add(file);
      } else {
        grouped[key] = [file];
      }
    }
    _groups.value = grouped.entries.toList();
  }

  Widget preview(FileProps item) {
    return getMediaType(item.key) != null
        ? SizedBox(
            height: 256,
            width: 256,
            child: MediaPreview(item: item, height: 256, width: 256),
          )
        : Icon(Icons.insert_drive_file);
  }

  Widget listItemBuilder(BuildContext context, FileProps item) {
    return item.job != null
        ? ListenableBuilder(
            listenable: widget.relativeto,
            builder: (ccontext, _) =>
                JobView(job: item.job!, relativeTo: widget.relativeto.value),
          )
        : p.isDir(item.key)
        ? ListenableBuilder(
            listenable: Listenable.merge([
              widget.selection,
              widget.relativeto,
              widget.selectionAction,
            ]),
            builder: (ccontext, _) => ListTile(
              dense: MediaQuery.of(context).size.width < 600 ? true : false,
              visualDensity: MediaQuery.of(context).size.width < 600
                  ? VisualDensity.compact
                  : VisualDensity.standard,
              selected: widget.selection.value.any(
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
                p.isWithin(widget.relativeto.value.key, item.key)
                    ? p.s3(
                        p.asDir(
                          p.relative(
                            item.key,
                            from: widget.relativeto.value.key,
                          ),
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
                          final count = widget.count(
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
              onTap: widget.selection.value.isNotEmpty
                  ? widget.getSelectAction(item.file!)
                  : () => widget.changeDirectory(item.file!),
              onLongPress: widget.getSelectAction(item.file!),
              trailing: widget.selection.value.isNotEmpty
                  ? widget.selection.value.any(
                          (selected) => selected.key == item.key,
                        )
                        ? Icon(Icons.check_circle)
                        : widget.selection.value.any(
                            (selected) => p.isWithin(selected.key, item.key),
                          )
                        ? Icon(Icons.check_circle_outline)
                        : widget.selectionAction.value == SelectionAction.none
                        ? Icon(Icons.circle_outlined)
                        : null
                  : widget.showContextMenu != null
                  ? IconButton(
                      onPressed: () async {
                        widget.showContextMenu!(item.file!);
                      },
                      icon: Icon(Icons.more_vert),
                    )
                  : null,
            ),
          )
        : ListenableBuilder(
            listenable: Listenable.merge([
              widget.selection,
              widget.relativeto,
              widget.selectionAction,
            ]),
            builder: (ccontext, _) => ListTile(
              dense: MediaQuery.of(context).size.width < 600 ? true : false,
              visualDensity: MediaQuery.of(context).size.width < 600
                  ? VisualDensity.compact
                  : VisualDensity.standard,
              selected: widget.selection.value.any(
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
                  p.isWithin(widget.relativeto.value.key, item.key)
                      ? p.s3(
                          p.relative(
                            item.key,
                            from: widget.relativeto.value.key,
                          ),
                        )
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
                    FutureBuilder<void>(
                      future: () async {
                        _fileDownloadedCache[item.key] = await File(
                          Main.pathFromKey(item.key) ?? item.key,
                        ).exists();
                      }(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            _fileDownloadedCache[item.key] == null) {
                          return Icon(Icons.hourglass_empty, size: 16);
                        }
                        if (_fileDownloadedCache[item.key] == true) {
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
              trailing: widget.selection.value.isNotEmpty
                  ? widget.selection.value.any(
                          (selected) => selected.key == item.key,
                        )
                        ? Icon(Icons.check_circle)
                        : widget.selection.value.any(
                            (selected) => p.isWithin(selected.key, item.key),
                          )
                        ? Icon(Icons.check_circle_outline)
                        : widget.selectionAction.value == SelectionAction.none
                        ? Icon(Icons.circle_outlined)
                        : null
                  : widget.showContextMenu != null
                  ? IconButton(
                      onPressed: () async {
                        widget.showContextMenu!(item.file!);
                      },
                      icon: Icon(Icons.more_vert),
                    )
                  : null,
              onTap: widget.selection.value.isNotEmpty
                  ? widget.getSelectAction(item.file!)
                  : widget.showGallery != null
                  ? () => widget.showGallery!(
                      widget.galleryFiles.indexWhere(
                        (g) => g.file.key == item.key,
                      ),
                    )
                  : null,
              onLongPress: widget.getSelectAction(item.file!),
            ),
          );
  }

  Widget gridItemBuilder(BuildContext context, FileProps item) {
    return item.job != null
        ? ListenableBuilder(
            listenable: widget.relativeto,
            builder: (ccontext, _) => JobView(
              job: item.job!,
              relativeTo: widget.relativeto.value,
              grid: true,
            ),
          )
        : p.isDir(item.key)
        ? ListenableBuilder(
            listenable: Listenable.merge([
              widget.selection,
              widget.relativeto,
              widget.selectionAction,
            ]),
            builder: (ccontext, _) => MyGridTile(
              selected: widget.selection.value.any(
                (selected) =>
                    selected.key == item.key ||
                    p.isWithin(selected.key, item.key),
              ),
              footer: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      p.isWithin(widget.relativeto.value.key, item.key)
                          ? p.s3(
                              p.asDir(
                                p.relative(
                                  item.key,
                                  from: widget.relativeto.value.key,
                                ),
                              ),
                            )
                          : item.key,
                    ),
                  ),
                ],
              ),
              onTap: () => widget.changeDirectory(item.file!),
              onLongPress: widget.getSelectAction(item.file!),
              topRightBadge: widget.selection.value.isNotEmpty
                  ? widget.selectionAction.value == SelectionAction.none
                        ? IconButton(
                            icon: Icon(
                              widget.selection.value.isEmpty ||
                                      widget.selection.value.any((selected) {
                                        return selected.key == item.key;
                                      })
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: widget.getSelectAction(item.file!),
                          )
                        : widget.selection.value.any(
                            (selected) => selected.key == item.key,
                          )
                        ? IconButton(
                            icon: Icon(Icons.check_circle),
                            onPressed: null,
                            color: Theme.of(context).colorScheme.primary,
                            disabledColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                          )
                        : widget.selection.value.any(
                            (selected) => p.isWithin(selected.key, item.key),
                          )
                        ? IconButton(
                            icon: Icon(Icons.check_circle_outline),
                            onPressed: null,
                            color: Theme.of(context).colorScheme.primary,
                            disabledColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                          )
                        : null
                  : widget.showContextMenu != null
                  ? IconButton(
                      onPressed: () async {
                        widget.showContextMenu!(item.file!);
                      },
                      icon: Icon(Icons.more_vert),
                    )
                  : null,
              child: Icon(
                p.split(item.key).length > 1
                    ? Icons.folder
                    : Icons.cloud_circle_rounded,
              ),
            ),
          )
        : ListenableBuilder(
            listenable: Listenable.merge([
              widget.selection,
              widget.relativeto,
              widget.selectionAction,
            ]),
            builder: (ccontext, _) => MyGridTile(
              selected: widget.selection.value.any(
                (selected) =>
                    selected.key == item.key ||
                    p.isWithin(selected.key, item.key),
              ),
              footer: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      p.isWithin(widget.relativeto.value.key, item.key)
                          ? p.s3(
                              p.relative(
                                item.key,
                                from: widget.relativeto.value.key,
                              ),
                            )
                          : item.file!.key,
                    ),
                  ),
                ],
              ),
              topLeftBadge: Padding(
                padding: EdgeInsets.all(16),
                child: FutureBuilder<void>(
                  future: () async {
                    _fileDownloadedCache[item.key] = await File(
                      Main.pathFromKey(item.key) ?? item.key,
                    ).exists();
                  }(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _fileDownloadedCache[item.key] == null) {
                      return Icon(Icons.hourglass_empty, size: 16);
                    }
                    if (_fileDownloadedCache[item.key] == true) {
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
              topRightBadge: widget.selection.value.isNotEmpty
                  ? widget.selectionAction.value == SelectionAction.none
                        ? IconButton(
                            icon: Icon(
                              widget.selection.value.isEmpty ||
                                      widget.selection.value.any((selected) {
                                        return selected.key == item.key;
                                      })
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: widget.getSelectAction(item.file!),
                          )
                        : widget.selection.value.any(
                            (selected) => selected.key == item.key,
                          )
                        ? IconButton(
                            icon: Icon(Icons.check_circle),
                            onPressed: null,
                            color: Theme.of(context).colorScheme.primary,
                            disabledColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                          )
                        : widget.selection.value.any(
                            (selected) => p.isWithin(selected.key, item.key),
                          )
                        ? IconButton(
                            icon: Icon(Icons.check_circle_outline),
                            onPressed: null,
                            color: Theme.of(context).colorScheme.primary,
                            disabledColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                          )
                        : null
                  : widget.showContextMenu != null
                  ? IconButton(
                      onPressed: () async {
                        widget.showContextMenu!(item.file!);
                      },
                      icon: Icon(Icons.more_vert),
                    )
                  : null,
              onTap: widget.showGallery != null
                  ? () => widget.showGallery!(
                      widget.galleryFiles.indexWhere(
                        (g) => g.file.key == item.key,
                      ),
                    )
                  : null,
              onLongPress: widget.getSelectAction(item.file!),
              child: Hero(tag: item.key, child: preview(item)),
            ),
          );
  }

  void buildKeysOffsetMap(BuildContext context) {
    widget.keysOffsetMap.value.clear();

    final width = MediaQuery.of(context).size.width;
    final columns = width < 600 ? 4 : 6;
    final tileWidth = width / columns;
    final tileHeight = tileWidth * (4 / 3); // inverse of 3/4

    double offset = 0;

    for (final group in _groups.value) {
      // Header height (if enabled)
      if (widget.listOptions.value.group) {
        final style = Theme.of(context).textTheme.titleMedium!;
        final painter = TextPainter(
          text: TextSpan(text: group.key, style: style),
          textDirection: TextDirection.ltr,
        )..layout();

        offset += painter.height + 16; // 8px top + 8px bottom padding
      }

      // Grid items
      if (widget.listOptions.value.viewMode != ViewMode.grid) {
        // List view
        for (final file in group.value) {
          final listTileHeight = MediaQuery.of(context).size.width < 600
              ? 56.0
              : 72.0; // approximate heights for dense and standard ListTiles
          widget.keysOffsetMap.value[file.key] = offset;
          offset += listTileHeight;
        }
        continue;
      }

      for (int i = 0; i < group.value.length; i++) {
        final file = group.value[i];
        final row = i ~/ columns;
        widget.keysOffsetMap.value[file.key] = offset + row * tileHeight;
      }

      // Skip past this group’s grid
      final rows = (group.value.length + columns - 1) ~/ columns;
      offset += rows * tileHeight;

      widget.groupOffsetMap[group.key] =
          widget.keysOffsetMap.value[group.value.first.key]!;
    }
  }

  @override
  void initState() {
    super.initState();

    Listenable.merge([widget.files, widget.relativeto]).addListener(() {
      widget.setGalleryFiles?.call(
        widget.files.value
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
                title: p.isWithin(widget.relativeto.value.key, f.key)
                    ? p.s3(p.relative(f.key, from: widget.relativeto.value.key))
                    : f.key,
                url: f.url!,
                path: Main.pathFromKey(f.key) ?? f.key,
                cachePath: Main.cachePathFromKey(f.key),
              ),
            )
            .toList(),
      );
    });

    Listenable.merge([
      widget.files,
      widget.listOptions,
      widget.relativeto,
    ]).addListener(() {
      makeGroups();
    });

    Listenable.merge([_groups, widget.listOptions]).addListener(() {
      buildKeysOffsetMap(context);
    });
  }

  @override
  void dispose() {
    super.dispose();
    _groups.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_groups, widget.listOptions]),
      builder: (ccontext, _) => MultiSliver(
        children: [
          for (final group
              in widget.listOptions.value.group
                  ? _groups.value
                  : [
                      MapEntry(
                        '',
                        _groups.value.map((g) => g.value).flattenedToList,
                      ),
                    ]) ...[
            if (widget.listOptions.value.group)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            if (widget.listOptions.value.viewMode == ViewMode.grid)
              SliverGrid.builder(
                key: ValueKey(widget.relativeto.value.key + group.key),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.of(context).size.width < 600
                      ? 4
                      : 6,
                  childAspectRatio: 3 / 4,
                ),
                itemCount: group.value.length,
                itemBuilder: (context, index) =>
                    gridItemBuilder(context, group.value[index]),
              )
            else
              SliverList.builder(
                key: ValueKey(widget.relativeto.value.key + group.key),
                itemCount: group.value.length,
                itemBuilder: (context, index) => TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 300),
                  tween: Tween(begin: 0, end: 1),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: listItemBuilder(context, group.value[index]),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
