import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:m3e_card_list/m3e_card_list.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/info_row.dart';
import 'package:files3/job_view.dart';
import 'package:files3/media_view.dart';

typedef FileSelectionState = ({
  ValueNotifier<bool> explicitlySelected,
  ValueNotifier<bool> inherentlySelected,
  ValueNotifier<bool> partiallySelected,
});

class SelectionNotifiers {
  final Map<String, FileSelectionState> _map = {};
  final ValueNotifier<bool> anySelected = ValueNotifier(false);

  FileSelectionState operator [](String key) => _map[key] ??= (
    explicitlySelected: ValueNotifier(false),
    inherentlySelected: ValueNotifier(false),
    partiallySelected: ValueNotifier(false),
  );

  void dispose() {
    anySelected.dispose();
    for (final notifiers in _map.values) {
      notifiers.explicitlySelected.dispose();
      notifiers.inherentlySelected.dispose();
      notifiers.partiallySelected.dispose();
    }
    _map.clear();
  }

  void reset() {
    anySelected.value = false;
    for (final notifiers in _map.values) {
      notifiers.explicitlySelected.dispose();
      notifiers.inherentlySelected.dispose();
      notifiers.partiallySelected.dispose();
    }
    _map.clear();
  }
}

class MyGridTile extends StatelessWidget {
  final Widget child;
  final Widget? footer;
  final bool selected;
  final Widget? topLeftBadge;
  final Widget? topRightBadge;
  final Widget? bottomLeftBadge;
  final Widget? bottomRightBadge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MyGridTile({
    super.key,
    required this.child,
    this.footer,
    this.selected = false,
    this.topLeftBadge,
    this.topRightBadge,
    this.bottomLeftBadge,
    this.bottomRightBadge,
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
              ? Theme.of(context).colorScheme.secondaryContainer
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
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bottomLeftBadge != null || bottomRightBadge != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      bottomLeftBadge ?? SizedBox.shrink(),
                      bottomRightBadge ?? SizedBox.shrink(),
                    ],
                  ),
                ),
              AnimatedPadding(
                duration: Duration(milliseconds: 250),
                padding: EdgeInsets.all(8),
                child: footer,
              ),
            ],
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
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

class ListFiles extends StatefulWidget {
  final ValueNotifier<Iterable<FileProps>> files;
  final Map<String, GalleryProps> galleryFiles;
  final Future<void> Function(Map<String, GalleryProps>)? setGalleryFiles;
  final ValueNotifier<ListOptions> listOptions;
  final ValueNotifier<RemoteFile> relativeto;
  final ValueNotifier<Set<String>> selection;
  final ValueNotifier<SelectionAction> selectionAction;
  final ValueNotifier<Map<String, double>> keysOffsetMap;
  final Map<String, double> groupOffsetMap;
  final void Function(String)? showGallery;
  final Function(RemoteFile) changeDirectory;
  final void Function()? Function(RemoteFile) getSelectAction;
  final Function(RemoteFile)? showContextMenu;

  static void Function()? setSelectActionDefault(RemoteFile file) => () {};

  const ListFiles({
    super.key,
    required this.files,
    this.galleryFiles = const {},
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
  });

  @override
  State<StatefulWidget> createState() => ListFilesState();
}

class ListFilesState extends State<ListFiles> {
  final ValueNotifier<Map<String, List<FileProps>>> _groups = ValueNotifier({});
  final SelectionNotifiers _selectionNotifiers = SelectionNotifiers();

  void makeGroups() {
    final Map<String, List<FileProps>> groups = {};
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
      if (widget.listOptions.value.foldersFirst && p.isDir(file.key)) {
        key += '_folder';
      }

      if (!groups.containsKey(key)) {
        groups[key] = [];
      }
      groups[key]!.add(file);
    }
    _groups.value = groups;
  }

  Future<void> buildKeysOffsetMap(BuildContext context) async {
    widget.keysOffsetMap.value.clear();
    widget.groupOffsetMap.clear();

    final width = MediaQuery.of(context).size.width;
    final columns = width < 600 ? 4 : 6;
    final tileWidth = width / columns;
    final tileHeight = tileWidth * (4 / 3); // inverse of 3/4

    double offset = 0;

    for (final group in _groups.value.entries) {
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
      } else {
        for (int i = 0; i < group.value.length; i++) {
          final file = group.value[i];
          final row = i ~/ columns;
          widget.keysOffsetMap.value[file.key] = offset + row * tileHeight;
        }

        // Skip past this group’s grid
        final rows = (group.value.length + columns - 1) ~/ columns;
        offset += rows * tileHeight;
      }

      widget.groupOffsetMap[group.key] =
          widget.keysOffsetMap.value[group.value.first.key]!;
    }
  }

  Future<void> updateSelectionNotifiers() async {
    bool anySelected = false;
    for (final group in _groups.value.entries) {
      bool groupAllSelected = group.value.isNotEmpty;
      for (final file in group.value) {
        bool explicitlySelected = false,
            inherentlySelected = false,
            partiallySelected = false;
        for (final selected in widget.selection.value) {
          anySelected = true;
          if (file.key == selected) {
            explicitlySelected = true;
          } else if (p.isWithin(selected, file.key)) {
            inherentlySelected = true;
          } else if (p.isDir(file.key) && p.isWithin(file.key, selected)) {
            partiallySelected = true;
          }
          if (explicitlySelected && inherentlySelected && partiallySelected) {
            break;
          }
        }
        if (!explicitlySelected && !inherentlySelected) {
          groupAllSelected = false;
        }
        _selectionNotifiers[file.key].explicitlySelected.value =
            explicitlySelected;
        _selectionNotifiers[file.key].inherentlySelected.value =
            inherentlySelected;
        _selectionNotifiers[file.key].partiallySelected.value =
            partiallySelected;
      }
      _selectionNotifiers[group.key].explicitlySelected.value =
          groupAllSelected;
    }
    _selectionNotifiers.anySelected.value = anySelected;
  }

  Widget preview(FileProps item) {
    return SizedBox(
      height: 256,
      width: 256,
      child: MediaPreview(item: item, height: 256, width: 256),
    );
  }

  Widget listItemBuilder(BuildContext context, FileProps item) {
    return item.job != null
        ? ListenableBuilder(
            listenable: widget.relativeto,
            builder: (context, child) =>
                JobView(job: item.job!, relativeTo: widget.relativeto.value),
          )
        : p.isDir(item.key)
        ? ListenableBuilder(
            listenable: Listenable.merge([
              _selectionNotifiers.anySelected,
              _selectionNotifiers[item.key].explicitlySelected,
              _selectionNotifiers[item.key].inherentlySelected,
              _selectionNotifiers[item.key].partiallySelected,
              widget.selectionAction,
              widget.relativeto,
              uiConfigNotifier,
            ]),
            builder: (context, child) => ListTile(
              dense: MediaQuery.of(context).size.width < 600 ? true : false,
              visualDensity: MediaQuery.of(context).size.width < 600
                  ? VisualDensity.compact
                  : VisualDensity.standard,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              selected:
                  _selectionNotifiers[item.key].explicitlySelected.value ||
                  _selectionNotifiers[item.key].inherentlySelected.value ||
                  _selectionNotifiers[item.key].partiallySelected.value,
              selectedTileColor: Theme.of(
                context,
              ).colorScheme.secondaryContainer,
              selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
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
              subtitle:
                  uiConfigNotifier.dirListInfo ||
                      p.s3(p.dirname(item.file!.key)).isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (uiConfigNotifier.dirListInfo)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: InfoRow(file: item.file!),
                          ),
                        if (p.s3(p.dirname(item.file!.key)).isEmpty)
                          Row(
                            children: [
                              Text(
                                '${Main.backupModeFromKey(item.file!.key).name}:',
                              ),
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
                    )
                  : null,
              onTap:
                  widget.selection.value.isNotEmpty &&
                      widget.selectionAction.value == SelectionAction.none
                  ? widget.getSelectAction(item.file!)
                  : widget.showGallery != null
                  ? () => widget.changeDirectory(item.file!)
                  : null,
              onLongPress: widget.getSelectAction(item.file!),
              trailing: widget.selection.value.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.selectionAction.value ==
                                SelectionAction.none &&
                            !_selectionNotifiers[item.key]
                                .explicitlySelected
                                .value &&
                            !_selectionNotifiers[item.key]
                                .inherentlySelected
                                .value)
                          IconButton(
                            icon: Icon(Icons.zoom_out_map),
                            onPressed: () => widget.changeDirectory(item.file!),
                          ),
                        Icon(
                          _selectionNotifiers[item.key].explicitlySelected.value
                              ? Icons.check_circle
                              : _selectionNotifiers[item.key]
                                    .inherentlySelected
                                    .value
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          color:
                              widget.selectionAction.value ==
                                  SelectionAction.none
                              ? null
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant.withAlpha(100),
                        ),
                      ],
                    )
                  : widget.showContextMenu != null
                  ? GestureDetector(
                      onTap: () async {
                        widget.showContextMenu!(item.file!);
                      },
                      child: Icon(Icons.more_vert),
                    )
                  : null,
            ),
          )
        : ListenableBuilder(
            listenable: Listenable.merge([
              _selectionNotifiers.anySelected,
              _selectionNotifiers[item.key].explicitlySelected,
              _selectionNotifiers[item.key].inherentlySelected,
              _selectionNotifiers[item.key].partiallySelected,
              widget.selectionAction,
              widget.relativeto,
              uiConfigNotifier,
            ]),
            builder: (context, child) => ListTile(
              dense: MediaQuery.of(context).size.width < 600 ? true : false,
              visualDensity: MediaQuery.of(context).size.width < 600
                  ? VisualDensity.compact
                  : VisualDensity.standard,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              selected:
                  _selectionNotifiers[item.key].explicitlySelected.value ||
                  _selectionNotifiers[item.key].inherentlySelected.value ||
                  _selectionNotifiers[item.key].partiallySelected.value,
              selectedTileColor: Theme.of(
                context,
              ).colorScheme.secondaryContainer,
              selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
              leading: child!,
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
              subtitle: uiConfigNotifier.fileListInfo
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: InfoRow(file: item.file!),
                    )
                  : null,
              trailing: widget.selection.value.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.selectionAction.value ==
                            SelectionAction.none)
                          IconButton(
                            icon: Icon(Icons.zoom_out_map),
                            onPressed: () =>
                                widget.showGallery?.call(item.file!.key),
                          ),
                        Icon(
                          _selectionNotifiers[item.key].explicitlySelected.value
                              ? Icons.check_circle
                              : _selectionNotifiers[item.key]
                                    .inherentlySelected
                                    .value
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          color:
                              widget.selectionAction.value ==
                                  SelectionAction.none
                              ? null
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant.withAlpha(100),
                        ),
                      ],
                    )
                  : widget.showContextMenu != null
                  ? GestureDetector(
                      onTap: () async {
                        widget.showContextMenu!(item.file!);
                      },
                      child: Icon(Icons.more_vert),
                    )
                  : null,
              onTap:
                  widget.selection.value.isNotEmpty &&
                      widget.selectionAction.value == SelectionAction.none
                  ? widget.getSelectAction(item.file!)
                  : widget.showGallery != null
                  ? () => widget.showGallery!(item.key)
                  : null,
              onLongPress: widget.getSelectAction(item.file!),
            ),
            child: Hero(
              tag: item.key,
              child: SizedBox(height: 32, width: 32, child: preview(item)),
            ),
          );
  }

  Widget gridItemBuilder(BuildContext context, FileProps item) {
    return item.job != null
        ? ListenableBuilder(
            listenable: widget.relativeto,
            builder: (context, child) => JobView(
              job: item.job!,
              relativeTo: widget.relativeto.value,
              grid: true,
            ),
          )
        : p.isDir(item.key)
        ? ListenableBuilder(
            listenable: Listenable.merge([
              _selectionNotifiers.anySelected,
              _selectionNotifiers[item.key].explicitlySelected,
              _selectionNotifiers[item.key].inherentlySelected,
              _selectionNotifiers[item.key].partiallySelected,
              widget.selectionAction,
              widget.relativeto,
              uiConfigNotifier.showDownloadStatus,
            ]),
            builder: (context, child) => MyGridTile(
              selected:
                  _selectionNotifiers[item.key].explicitlySelected.value ||
                  _selectionNotifiers[item.key].inherentlySelected.value ||
                  _selectionNotifiers[item.key].partiallySelected.value,
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
              onTap:
                  widget.selection.value.isNotEmpty &&
                      widget.selectionAction.value == SelectionAction.none
                  ? widget.getSelectAction(item.file!)
                  : widget.showGallery != null
                  ? () => widget.changeDirectory(item.file!)
                  : null,
              onLongPress: widget.getSelectAction(item.file!),
              topLeftBadge: uiConfigNotifier.showDownloadStatus.value
                  ? DownloadStatusIcon(file: item.file!)
                  : null,
              topRightBadge: widget.selection.value.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        _selectionNotifiers[item.key].explicitlySelected.value
                            ? Icons.check_circle
                            : _selectionNotifiers[item.key]
                                  .inherentlySelected
                                  .value
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                      ),
                      disabledColor:
                          widget.selectionAction.value == SelectionAction.none
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      onPressed: null,
                    )
                  : widget.showContextMenu != null
                  ? IconButton(
                      onPressed: () async {
                        widget.showContextMenu!(item.file!);
                      },
                      icon: Icon(Icons.more_vert),
                    )
                  : null,
              bottomLeftBadge:
                  widget.selection.value.isNotEmpty &&
                      widget.selectionAction.value == SelectionAction.none &&
                      !_selectionNotifiers[item.key].explicitlySelected.value &&
                      !_selectionNotifiers[item.key].inherentlySelected.value
                  ? IconButton(
                      icon: Icon(Icons.zoom_out_map),
                      onPressed: () => widget.changeDirectory(item.file!),
                    )
                  : null,
              child: child!,
            ),
            child: Icon(
              p.split(item.key).length > 1
                  ? Icons.folder
                  : Icons.cloud_circle_rounded,
            ),
          )
        : ListenableBuilder(
            listenable: Listenable.merge([
              _selectionNotifiers.anySelected,
              _selectionNotifiers[item.key].explicitlySelected,
              _selectionNotifiers[item.key].inherentlySelected,
              _selectionNotifiers[item.key].partiallySelected,
              widget.selectionAction,
              widget.relativeto,
              uiConfigNotifier.showDownloadStatus,
            ]),
            builder: (context, child) => MyGridTile(
              selected:
                  _selectionNotifiers[item.key].explicitlySelected.value ||
                  _selectionNotifiers[item.key].inherentlySelected.value ||
                  _selectionNotifiers[item.key].partiallySelected.value,
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
              onTap:
                  widget.selection.value.isNotEmpty &&
                      widget.selectionAction.value == SelectionAction.none
                  ? widget.getSelectAction(item.file!)
                  : widget.showGallery != null
                  ? () => widget.showGallery!(item.key)
                  : null,
              onLongPress: widget.getSelectAction(item.file!),
              topLeftBadge: uiConfigNotifier.showDownloadStatus.value
                  ? Padding(
                      padding: EdgeInsets.all(16),
                      child: DownloadStatusIcon(file: item.file!),
                    )
                  : null,
              topRightBadge: widget.selection.value.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        _selectionNotifiers[item.key].explicitlySelected.value
                            ? Icons.check_circle
                            : _selectionNotifiers[item.key]
                                  .inherentlySelected
                                  .value
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                      ),
                      disabledColor:
                          widget.selectionAction.value == SelectionAction.none
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      onPressed: null,
                    )
                  : widget.showContextMenu != null
                  ? IconButton(
                      onPressed: () async {
                        widget.showContextMenu!(item.file!);
                      },
                      icon: Icon(Icons.more_vert),
                    )
                  : null,
              bottomLeftBadge:
                  widget.selection.value.isNotEmpty &&
                      widget.selectionAction.value == SelectionAction.none
                  ? IconButton(
                      icon: Icon(Icons.zoom_out_map),
                      onPressed: () => widget.showGallery?.call(item.file!.key),
                    )
                  : null,
              child: child!,
            ),
            child: Hero(tag: item.key, child: preview(item)),
          );
  }

  Widget _groupContent(MapEntry<String, List<FileProps>> group) {
    return widget.listOptions.value.viewMode == ViewMode.grid
        ? SliverGrid.builder(
            key: ValueKey(widget.relativeto.value.key + group.key),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width < 600 ? 4 : 6,
              childAspectRatio: 3 / 4,
            ),
            itemCount: group.value.length,
            itemBuilder: (context, index) =>
                gridItemBuilder(context, group.value[index]),
          )
        : SliverM3ECardList(
            key: ValueKey(widget.relativeto.value.key + group.key),
            itemCount: group.value.length,
            outerRadius: 14,
            innerRadius: 4,
            gap: 3,
            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            padding: EdgeInsets.zero,
            color: Colors.transparent,
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
          );
  }

  @override
  void initState() {
    super.initState();

    Listenable.merge([widget.files, widget.relativeto]).addListener(() {
      widget.setGalleryFiles?.call({
        for (var f in widget.files.value.where((f) => !p.isDir(f.key)))
          f.key: GalleryProps(
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
      });
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

    Listenable.merge([
      widget.selection,
      widget.files,
    ]).addListener(updateSelectionNotifiers);
  }

  @override
  void dispose() {
    super.dispose();
    _groups.dispose();
    _selectionNotifiers.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MyListenableBuilder(
      name: 'list_files',
      listenable: Listenable.merge([_groups, widget.listOptions]),
      builder: (ccontext, _) {
        return MultiSliver(
          children: [
            for (final group
                in widget.listOptions.value.group
                    ? _groups.value.entries
                    : [
                        MapEntry(
                          '',
                          _groups.value.entries
                              .map((g) => g.value)
                              .flattenedToList,
                        ),
                      ])
              if (widget.listOptions.value.group)
                SliverMainAxisGroup(
                  slivers: [
                    SliverPersistentHeader(
                      floating: false,
                      pinned: true,
                      delegate: MyPersistentHeaderDelegate(
                        height: 32,
                        child: Container(
                          color: Theme.of(context).colorScheme.surface,
                          padding: EdgeInsets.only(
                            left: 16,
                            right:
                                widget.listOptions.value.viewMode ==
                                    ViewMode.grid
                                ? 12
                                : 18,
                          ),
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                group.key.replaceAll('_folder', ''),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              ListenableBuilder(
                                listenable: Listenable.merge([
                                  _selectionNotifiers.anySelected,
                                  _selectionNotifiers[group.key]
                                      .explicitlySelected,
                                  widget.selectionAction,
                                ]),
                                builder: (context, _) =>
                                    widget.selection.value.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () {
                                          if (group.value.any(
                                            (f) => !widget.selection.value
                                                .contains(f.key),
                                          )) {
                                            for (final file in group.value) {
                                              if (!widget.selection.value
                                                  .contains(file.key)) {
                                                widget.selection.value = {
                                                  ...widget.selection.value,
                                                  file.key,
                                                };
                                              }
                                            }
                                          } else {
                                            widget.selection.value = {
                                              ...widget.selection.value.where(
                                                (f) => !group.value
                                                    .map((f) => f.key)
                                                    .contains(f),
                                              ),
                                            };
                                          }
                                        },
                                        child: Icon(
                                          group.value.any(
                                                (f) => !widget.selection.value
                                                    .contains(f.key),
                                              )
                                              ? Icons.circle_outlined
                                              : Icons.check_circle,
                                          color:
                                              widget.selectionAction.value ==
                                                  SelectionAction.none
                                              ? widget
                                                            .listOptions
                                                            .value
                                                            .viewMode ==
                                                        ViewMode.grid
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.primary
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onSecondaryContainer
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withAlpha(100),
                                        ),
                                      )
                                    : SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _groupContent(group),
                  ],
                )
              else
                _groupContent(group),
          ],
        );
      },
    );
  }
}
