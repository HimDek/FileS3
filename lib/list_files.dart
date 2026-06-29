import 'dart:async';
import 'package:mime/mime.dart';
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
  final bool enabled;

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
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    bottomLeftBadge ?? SizedBox.shrink(),
                    bottomRightBadge ?? SizedBox.shrink(),
                  ],
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
  final ValueNotifier<ListOptions> listOptions;
  final ValueNotifier<String> relativeto;
  final ValueNotifier<Set<String>> selection;
  final ValueNotifier<SelectionAction> selectionAction;
  final Map<String, double> keysOffsetMap;
  final Map<String, double> groupOffsetMap;
  final void Function(String)? showGallery;
  final Function(String) changeDirectory;
  final void Function()? Function(String) getSelectAction;
  final Function(String)? showContextMenu;
  final List<RegExp>? mimeTypes;
  final bool forceSelectionMode;

  static void Function()? setSelectActionDefault(String key) => () {};

  const ListFiles({
    super.key,
    required this.files,
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
    this.mimeTypes,
    this.forceSelectionMode = false,
  });

  @override
  State<StatefulWidget> createState() => ListFilesState();
}

class ListFilesState extends State<ListFiles> {
  final ValueNotifier<SortMode> _sortMode = ValueNotifier(
    ListOptions().sortMode,
  );
  final ValueNotifier<ViewMode> _viewMode = ValueNotifier(
    ListOptions().viewMode,
  );
  final ValueNotifier<bool> _foldersFirst = ValueNotifier(
    ListOptions().foldersFirst,
  );
  final ValueNotifier<bool> _group = ValueNotifier(ListOptions().group);
  final ValueNotifier<Map<String, Iterable<FileProps>>> _groups = ValueNotifier(
    {},
  );
  final SelectionNotifiers _selectionNotifiers = SelectionNotifiers();

  late List<RegExp> _mimeTypes = widget.mimeTypes ?? [allMimePattern];

  Future<void> makeGroups() async {
    final Map<String, List<FileProps>> groups = {};
    SortMode? groupBy = _sortMode.value;
    for (var file in widget.files.value) {
      String key;
      switch (groupBy) {
        case SortMode.nameAsc || SortMode.nameDesc:
          String fileKey = p.s3.isWithin(widget.relativeto.value, file.key)
              ? p.s3.asDir(
                  p.s3.relative(file.key, from: widget.relativeto.value),
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
              file.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
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
          key = p.s3.extension(file.key).isNotEmpty
              ? p.s3.extension(file.key).toUpperCase()
              : p.isDir(file.key)
              ? 'Folders'
              : 'No Extension';
          break;
      }
      if (_foldersFirst.value && p.isDir(file.key)) {
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
    widget.keysOffsetMap.clear();
    widget.groupOffsetMap.clear();

    final width = MediaQuery.of(context).size.width;
    final columns = width < 600 ? 4 : 6;
    final tileWidth = width / columns;
    final tileHeight = tileWidth * (4 / 3); // inverse of 3/4

    double offset = 0;

    for (final group in _groups.value.entries) {
      // Header height (if enabled)
      if (_group.value) {
        final style = Theme.of(context).textTheme.titleMedium!;
        final painter = TextPainter(
          text: TextSpan(text: group.key, style: style),
          textDirection: TextDirection.ltr,
        )..layout();

        offset += painter.height + 16; // 8px top + 8px bottom padding
      }

      // Grid items
      if (_viewMode.value != ViewMode.grid) {
        // List view
        for (final file in group.value) {
          final listTileHeight = MediaQuery.of(context).size.width < 600
              ? 56.0
              : 72.0; // approximate heights for dense and standard ListTiles
          widget.keysOffsetMap[file.key] = offset;
          offset += listTileHeight;
        }
      } else {
        int i = 0;
        final iGroupValue = group.value.iterator;
        while (iGroupValue.moveNext()) {
          final file = iGroupValue.current;
          final row = i ~/ columns;
          widget.keysOffsetMap[file.key] = offset + row * tileHeight;
          i++;
        }

        // Skip past this group’s grid
        final rows = (group.value.length + columns - 1) ~/ columns;
        offset += rows * tileHeight;
      }

      widget.groupOffsetMap[group.key] =
          widget.keysOffsetMap[group.value.first.key]!;
    }
  }

  Future<void> updateSelectionNotifiers() async {
    bool anySelected = false;
    for (final group in _groups.value.entries) {
      bool groupAllSelected = group.value.isNotEmpty;
      for (final file in group.value.where(
        (file) =>
            p.isDir(file.key) ||
            _mimeTypes.any(
              (mime) => mime.hasMatch(
                lookupMimeType(file.key) ?? 'application/octet-stream',
              ),
            ),
      )) {
        bool explicitlySelected = false,
            inherentlySelected = false,
            partiallySelected = false;
        for (final selected in widget.selection.value) {
          anySelected = true;
          if (file.key == selected) {
            explicitlySelected = true;
          } else if (p.s3.isWithin(selected, file.key)) {
            inherentlySelected = true;
          } else if (p.isDir(file.key) && p.s3.isWithin(file.key, selected)) {
            partiallySelected = true;
          }
          if (explicitlySelected || inherentlySelected || partiallySelected) {
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
                  p.s3.split(item.key).length > 1
                      ? Icons.folder
                      : Icons.cloud_circle_rounded,
                ),
              ),
              title: Text(
                p.s3.isWithin(widget.relativeto.value, item.key)
                    ? p.s3.asDir(
                        p.s3.relative(item.key, from: widget.relativeto.value),
                      )
                    : item.key,
              ),
              subtitle:
                  uiConfigNotifier.dirListInfo || p.s3.dirname(item.key).isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (uiConfigNotifier.dirListInfo)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: InfoRow(
                              remoteKey: item.key,
                              uiConfig: uiConfigNotifier.uiConfig,
                            ),
                          ),
                        if (p.s3.dirname(item.key).isEmpty)
                          Row(
                            children: [
                              Text('${Main.backupModeFromKey(item.key).name}:'),
                              SizedBox(width: 4),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(Main.pathFromKey(item.key)),
                              ),
                            ],
                          ),
                      ],
                    )
                  : null,
              onTap:
                  (_selectionNotifiers.anySelected.value &&
                          widget.selectionAction.value ==
                              SelectionAction.none) ||
                      widget.forceSelectionMode
                  ? widget.getSelectAction(item.key)
                  : widget.showGallery != null
                  ? () => widget.changeDirectory(item.key)
                  : null,
              onLongPress: widget.getSelectAction(item.key),
              trailing:
                  _selectionNotifiers.anySelected.value ||
                      widget.forceSelectionMode
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
                            onPressed: () => widget.changeDirectory(item.key),
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
                                ).colorScheme.onSurface.withAlpha(100),
                        ),
                      ],
                    )
                  : widget.showContextMenu != null
                  ? GestureDetector(
                      onTap: () async {
                        widget.showContextMenu!(item.key);
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
                  p.s3.isWithin(widget.relativeto.value, item.key)
                      ? p.s3.relative(item.key, from: widget.relativeto.value)
                      : item.key,
                ),
              ),
              subtitle: uiConfigNotifier.fileListInfo
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: InfoRow(
                        remoteKey: item.key,
                        uiConfig: uiConfigNotifier.uiConfig,
                      ),
                    )
                  : null,
              trailing:
                  _selectionNotifiers.anySelected.value ||
                      widget.forceSelectionMode
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.selectionAction.value ==
                                SelectionAction.none &&
                            widget.showGallery != null)
                          IconButton(
                            icon: Icon(Icons.zoom_out_map),
                            onPressed: () => widget.showGallery!(item.key),
                            color: Theme.of(context).colorScheme.onSurface,
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
                                ).colorScheme.onSurface.withAlpha(100),
                        ),
                      ],
                    )
                  : widget.showContextMenu != null
                  ? GestureDetector(
                      onTap: () async {
                        widget.showContextMenu!(item.key);
                      },
                      child: Icon(Icons.more_vert),
                    )
                  : null,
              onTap:
                  (_selectionNotifiers.anySelected.value &&
                          widget.selectionAction.value ==
                              SelectionAction.none) ||
                      widget.forceSelectionMode
                  ? widget.getSelectAction(item.key)
                  : widget.showGallery != null
                  ? () => widget.showGallery!(item.key)
                  : null,
              onLongPress: widget.getSelectAction(item.key),
              enabled: _mimeTypes.any(
                (mime) => mime.hasMatch(
                  lookupMimeType(item.key) ?? 'application/octet-stream',
                ),
              ),
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
                      p.s3.isWithin(widget.relativeto.value, item.key)
                          ? p.s3.asDir(
                              p.s3.relative(
                                item.key,
                                from: widget.relativeto.value,
                              ),
                            )
                          : item.key,
                    ),
                  ),
                ],
              ),
              onTap:
                  (_selectionNotifiers.anySelected.value &&
                          widget.selectionAction.value ==
                              SelectionAction.none) ||
                      widget.forceSelectionMode
                  ? widget.getSelectAction(item.key)
                  : widget.showGallery != null
                  ? () => widget.changeDirectory(item.key)
                  : null,
              onLongPress: widget.getSelectAction(item.key),
              topLeftBadge:
                  uiConfigNotifier.showDownloadStatus.value == DirOrFile.both ||
                      uiConfigNotifier.showDownloadStatus.value == DirOrFile.dir
                  ? Padding(
                      padding: EdgeInsets.all(16),
                      child: DownloadStatusIcon(remoteKey: item.key),
                    )
                  : null,
              topRightBadge:
                  _selectionNotifiers.anySelected.value ||
                      widget.forceSelectionMode
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
                        widget.showContextMenu!(item.key);
                      },
                      icon: Icon(Icons.more_vert),
                    )
                  : null,
              bottomLeftBadge:
                  (_selectionNotifiers.anySelected.value ||
                          widget.forceSelectionMode) &&
                      widget.selectionAction.value == SelectionAction.none &&
                      !_selectionNotifiers[item.key].explicitlySelected.value &&
                      !_selectionNotifiers[item.key].inherentlySelected.value
                  ? IconButton(
                      icon: Icon(Icons.zoom_out_map),
                      onPressed: () => widget.changeDirectory(item.key),
                    )
                  : null,
              child: child!,
            ),
            child: Icon(
              p.s3.split(item.key).length > 1
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
            builder: (context, child) {
              bool enabled = _mimeTypes.any(
                (mime) => mime.hasMatch(
                  lookupMimeType(item.key) ?? 'application/octet-stream',
                ),
              );
              return MyGridTile(
                selected:
                    _selectionNotifiers[item.key].explicitlySelected.value ||
                    _selectionNotifiers[item.key].inherentlySelected.value ||
                    _selectionNotifiers[item.key].partiallySelected.value,
                footer: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        p.s3.isWithin(widget.relativeto.value, item.key)
                            ? p.s3.relative(
                                item.key,
                                from: widget.relativeto.value,
                              )
                            : item.key,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: enabled
                              ? null
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(100),
                        ),
                      ),
                    ),
                  ],
                ),
                onTap:
                    (_selectionNotifiers.anySelected.value &&
                            widget.selectionAction.value ==
                                SelectionAction.none) ||
                        widget.forceSelectionMode
                    ? widget.getSelectAction(item.key)
                    : widget.showGallery != null
                    ? () => widget.showGallery!(item.key)
                    : null,
                onLongPress: widget.getSelectAction(item.key),
                enabled: enabled,
                topLeftBadge:
                    uiConfigNotifier.showDownloadStatus.value ==
                            DirOrFile.both ||
                        uiConfigNotifier.showDownloadStatus.value ==
                            DirOrFile.file
                    ? Padding(
                        padding: EdgeInsets.all(16),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            iconTheme: Theme.of(context).iconTheme.copyWith(
                              color: enabled
                                  ? Theme.of(context).iconTheme.color
                                  : Theme.of(
                                      context,
                                    ).iconTheme.color?.withAlpha(100),
                            ),
                          ),
                          child: DownloadStatusIcon(remoteKey: item.key),
                        ),
                      )
                    : null,
                topRightBadge:
                    _selectionNotifiers.anySelected.value ||
                        widget.forceSelectionMode
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
                            widget.selectionAction.value ==
                                    SelectionAction.none &&
                                enabled
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        onPressed: null,
                      )
                    : widget.showContextMenu != null
                    ? IconButton(
                        onPressed: () async {
                          widget.showContextMenu!(item.key);
                        },
                        icon: Icon(Icons.more_vert),
                      )
                    : null,
                bottomLeftBadge:
                    (_selectionNotifiers.anySelected.value ||
                            widget.forceSelectionMode) &&
                        widget.selectionAction.value == SelectionAction.none &&
                        widget.showGallery != null
                    ? IconButton(
                        icon: Icon(Icons.zoom_out_map),
                        onPressed: () => widget.showGallery!(item.key),
                      )
                    : null,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    iconTheme: Theme.of(context).iconTheme.copyWith(
                      color: enabled
                          ? Theme.of(context).iconTheme.color
                          : Theme.of(context).iconTheme.color?.withAlpha(100),
                    ),
                  ),
                  child: child!,
                ),
              );
            },
            child: Hero(tag: item.key, child: preview(item)),
          );
  }

  Widget _groupContent(MapEntry<String, List<FileProps>> group) {
    return ListenableBuilder(
      listenable: _viewMode,
      builder: (context, child) => _viewMode.value == ViewMode.grid
          ? SliverGrid.builder(
              key: ValueKey(widget.relativeto.value + group.key),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width < 600 ? 4 : 6,
                childAspectRatio: 3 / 4,
              ),
              itemCount: group.value.length,
              itemBuilder: (context, index) =>
                  gridItemBuilder(context, group.value[index]),
            )
          : SliverM3ECardList(
              key: ValueKey(widget.relativeto.value + group.key),
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
            ),
    );
  }

  @override
  void initState() {
    _sortMode.value = widget.listOptions.value.sortMode;
    _viewMode.value = widget.listOptions.value.viewMode;
    _foldersFirst.value = widget.listOptions.value.foldersFirst;
    _group.value = widget.listOptions.value.group;
    super.initState();

    Listenable.merge([
      widget.files,
      //widget.relativeto, //Change in relativeTo already triggers a change in files
    ]).addListener(() {
      unawaited(makeGroups());
    });

    Listenable.merge([
      _groups,
      _group,
      _viewMode,
    ]).addListener(() => unawaited(buildKeysOffsetMap(context)));

    Listenable.merge([
      widget.selection,
      widget.files,
    ]).addListener(() => unawaited(updateSelectionNotifiers()));

    Listenable.merge([widget.listOptions]).addListener(() {
      _sortMode.value = widget.listOptions.value.sortMode;
      _viewMode.value = widget.listOptions.value.viewMode;
      _foldersFirst.value = widget.listOptions.value.foldersFirst;
      _group.value = widget.listOptions.value.group;
    });
  }

  @override
  void dispose() {
    super.dispose();
    _groups.dispose();
    _selectionNotifiers.dispose();
  }

  @override
  void didUpdateWidget(covariant ListFiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mimeTypes != widget.mimeTypes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _mimeTypes = widget.mimeTypes ?? [allMimePattern];
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_groups, _group]),
      builder: (context, child) => !_group.value
          ? _groupContent(
              MapEntry(
                '',
                _groups.value.entries.map((g) => g.value).flattened.toList(),
              ),
            )
          : MultiSliver(
              children: [
                for (final group in _groups.value.entries)
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
                              right: _viewMode.value == ViewMode.grid ? 12 : 18,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  group.key.replaceAll('_folder', ''),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                ListenableBuilder(
                                  listenable: Listenable.merge([
                                    _viewMode,
                                    _selectionNotifiers.anySelected,
                                    _selectionNotifiers[group.key]
                                        .explicitlySelected,
                                    widget.selectionAction,
                                  ]),
                                  builder: (context, _) =>
                                      _selectionNotifiers.anySelected.value ||
                                          widget.forceSelectionMode
                                      ? GestureDetector(
                                          onTap: () {
                                            if (!_selectionNotifiers[group.key]
                                                .explicitlySelected
                                                .value) {
                                              for (final file in group.value) {
                                                if (!_selectionNotifiers[file
                                                        .key]
                                                    .explicitlySelected
                                                    .value) {
                                                  widget
                                                      .getSelectAction(file.key)
                                                      ?.call();
                                                }
                                              }
                                            } else {
                                              for (final file in group.value) {
                                                widget
                                                    .getSelectAction(file.key)
                                                    ?.call();
                                              }
                                            }
                                          },
                                          child: Icon(
                                            _selectionNotifiers[group.key]
                                                        .explicitlySelected
                                                        .value &&
                                                    group.value.any(
                                                      (file) =>
                                                          _selectionNotifiers[file
                                                                  .key]
                                                              .explicitlySelected
                                                              .value,
                                                    )
                                                ? Icons.check_circle
                                                : Icons.circle_outlined,
                                            color:
                                                widget.selectionAction.value ==
                                                        SelectionAction.none &&
                                                    group.value.any(
                                                      (file) =>
                                                          p.isDir(file.key) ||
                                                          _mimeTypes.any(
                                                            (
                                                              mime,
                                                            ) => mime.hasMatch(
                                                              lookupMimeType(
                                                                    file.key,
                                                                  ) ??
                                                                  'application/octet-stream',
                                                            ),
                                                          ),
                                                    )
                                                ? _viewMode.value ==
                                                          ViewMode.grid
                                                      ? Theme.of(
                                                          context,
                                                        ).colorScheme.primary
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .onSecondaryContainer
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
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
                      _groupContent(MapEntry(group.key, group.value.toList())),
                    ],
                  ),
              ],
            ),
    );
  }
}
