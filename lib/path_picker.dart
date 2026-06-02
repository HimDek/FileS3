import 'dart:math';
import 'package:flutter/material.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/list_files.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:flutter/rendering.dart';

class PathPicker extends StatefulWidget {
  final Widget title;
  final Widget subtitle;
  final RemoteFile initialDir;
  final ValueNotifier<bool> loading;
  final ValueNotifier<double> progress;
  final ValueNotifier<bool> globalListOptions;
  final Map<String, ImageProvider> thumbnailCache;
  final (int, int) Function(RemoteFile, {bool recursive}) count;
  final int Function(RemoteFile) dirSize;
  final String Function(RemoteFile) dirModified;
  final Function(RemoteFile) onPick;

  const PathPicker({
    super.key,
    this.title = const Text('Select Path'),
    this.subtitle = const Text(''),
    this.initialDir = const RemoteFile(key: '', size: 0, etag: ''),
    required this.loading,
    required this.progress,
    required this.globalListOptions,
    required this.thumbnailCache,
    required this.count,
    required this.dirSize,
    required this.dirModified,
    required this.onPick,
  });

  @override
  PathPickerState createState() => PathPickerState();
}

class PathPickerState extends State<PathPicker> {
  final ValueNotifier<ListOptions> _listOptions = ValueNotifier(ListOptions());
  final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  final Map<String, double> _keysOffsetMap = {};
  late RemoteFile _driveDir;
  Profile? _profile;

  void _scrollToFile(RemoteFile file) {
    final offset = _keysOffsetMap[file.key];
    if (offset == null) return;

    _scrollController.jumpTo(
      max(0, offset - MediaQuery.of(context).size.height / 3),
    );
  }

  Function()? _changeDirectory(RemoteFile dir) => () {
    final oldDir = _driveDir;
    setState(() {
      _driveDir = dir;
      _profile = Main.profileFromKey(_driveDir.key);
      _controlsVisible.value = true;
      _listOptions.value = ListOptions.fromJson(
        IniManager.config?.get('list_options', _driveDir.key) ??
            ListOptions().toJson(),
      );
      if (IniManager.config?.get('list_options', _driveDir.key) != null) {
        widget.globalListOptions.value = false;
      } else {
        widget.globalListOptions.value = true;
      }
    });
    _scrollToFile(oldDir);
  };

  Iterable<FileProps> _getCurrentItems() {
    final items = _driveDir.key == ''
        ? Set<RemoteFile>.from(
            Main.remoteFiles
                .where(
                  (file) =>
                      p.s3(p.dirname(file.key)).isEmpty && p.isDir(file.key),
                )
                .map<RemoteFile>((file) => file),
          ).toList()
        : _driveDir.key != ''
        ? [
            ...Main.remoteFiles.where(
              (file) =>
                  p.s3(p.dirname(file.key)) == p.s3(_driveDir.key) &&
                  !Main.ignoreKeyRegexps.any(
                    (regexp) => RegExp(regexp).hasMatch(file.key),
                  ) &&
                  !Job.jobs.any(
                    (job) =>
                        job.remoteKey == file.key &&
                        job.status != JobStatus.completed,
                  ),
            ),
            ...Job.jobs.where(
              (job) =>
                  p.s3(p.dirname(job.remoteKey)) == p.s3(_driveDir.key) &&
                  job.status != JobStatus.completed,
            ),
          ]
        : [];

    return sort(
      items.map((file) {
        return file is Job
            ? FileProps(key: file.remoteKey, size: file.bytes, job: file)
            : p.isDir(file.key)
            ? FileProps(key: file.key, size: file.size, file: file)
            : FileProps(key: file.key, size: file.size, file: file);
      }),
      _listOptions.value.sortMode,
      _listOptions.value.foldersFirst,
    );
  }

  void _setListOptions(ListOptions options) {
    if (!(IniManager.config?.sections().contains('list_options') ?? true)) {
      IniManager.config?.addSection('list_options');
    }
    IniManager.config?.set(
      'list_options',
      widget.globalListOptions.value ? '/' : _driveDir.key,
      options.toJson(),
    );
    if (widget.globalListOptions.value &&
        IniManager.config?.options('list_options')?.contains(_driveDir.key) ==
            true) {
      IniManager.config?.removeOption('list_options', _driveDir.key);
    }
    IniManager.save();
    setState(() {});
  }

  Widget _buildPopupMenu() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.loading,
        _listOptions,
        widget.globalListOptions,
      ]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 0, width: 128),
          ListTile(
            dense: true,
            enabled: !widget.loading.value,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            titleTextStyle: Theme.of(context).textTheme.bodyMedium,
            title: Text('Refresh', maxLines: 1),
            trailing: widget.loading.value
                ? Icon(Icons.hourglass_empty)
                : Icon(Icons.refresh),
            onTap: () {
              Main.listDirectories();
              setState(() {});
            },
          ),
          const PopupMenuDivider(),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            titleTextStyle: Theme.of(context).textTheme.bodyMedium,
            title: Text('Name'),
            trailing: _listOptions.value.sortMode == SortMode.nameAsc
                ? Icon(Icons.arrow_upward)
                : _listOptions.value.sortMode == SortMode.nameDesc
                ? Icon(Icons.arrow_downward)
                : null,
            onTap: () {
              _listOptions.value =
                  _listOptions.value.sortMode == SortMode.nameAsc
                  ? _listOptions.value.copyWith(sortMode: SortMode.nameDesc)
                  : _listOptions.value.copyWith(sortMode: SortMode.nameAsc);
              _setListOptions(_listOptions.value);
            },
          ),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            titleTextStyle: Theme.of(context).textTheme.bodyMedium,
            title: Text('Date'),
            trailing: _listOptions.value.sortMode == SortMode.dateAsc
                ? Icon(Icons.arrow_upward)
                : _listOptions.value.sortMode == SortMode.dateDesc
                ? Icon(Icons.arrow_downward)
                : null,
            onTap: () {
              _listOptions.value =
                  _listOptions.value.sortMode == SortMode.dateAsc
                  ? _listOptions.value.copyWith(sortMode: SortMode.dateDesc)
                  : _listOptions.value.copyWith(sortMode: SortMode.dateAsc);
              _setListOptions(_listOptions.value);
            },
          ),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            titleTextStyle: Theme.of(context).textTheme.bodyMedium,
            title: Text('Size'),
            trailing: _listOptions.value.sortMode == SortMode.sizeAsc
                ? Icon(Icons.arrow_upward)
                : _listOptions.value.sortMode == SortMode.sizeDesc
                ? Icon(Icons.arrow_downward)
                : null,
            onTap: () {
              _listOptions.value =
                  _listOptions.value.sortMode == SortMode.sizeAsc
                  ? _listOptions.value.copyWith(sortMode: SortMode.sizeDesc)
                  : _listOptions.value.copyWith(sortMode: SortMode.sizeAsc);
              _setListOptions(_listOptions.value);
            },
          ),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            titleTextStyle: Theme.of(context).textTheme.bodyMedium,
            title: Text('Type'),
            trailing: _listOptions.value.sortMode == SortMode.typeAsc
                ? Icon(Icons.arrow_upward)
                : _listOptions.value.sortMode == SortMode.typeDesc
                ? Icon(Icons.arrow_downward)
                : null,
            onTap: () {
              _listOptions.value =
                  _listOptions.value.sortMode == SortMode.typeAsc
                  ? _listOptions.value.copyWith(sortMode: SortMode.typeDesc)
                  : _listOptions.value.copyWith(sortMode: SortMode.typeAsc);
              _setListOptions(_listOptions.value);
            },
          ),
          const PopupMenuDivider(),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            title: Text(
              'Folders First',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            value: _listOptions.value.foldersFirst,
            onChanged: (value) {
              _listOptions.value = _listOptions.value.copyWith(
                foldersFirst: value ?? true,
              );
              _setListOptions(_listOptions.value);
            },
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            title: Text(
              'Grid View',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            value: _listOptions.value.viewMode == ViewMode.grid,
            onChanged: (value) {
              _listOptions.value = _listOptions.value.copyWith(
                viewMode: value! ? ViewMode.grid : ViewMode.list,
              );
              _setListOptions(_listOptions.value);
            },
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            title: Text(
              'Grouped View',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            value: _listOptions.value.group,
            onChanged: (value) {
              _listOptions.value = _listOptions.value.copyWith(
                group: value ?? true,
              );
              _setListOptions(_listOptions.value);
            },
          ),
          const PopupMenuDivider(),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            title: Text(
              'Use Global',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            value: widget.globalListOptions.value,
            onChanged: (value) {
              setState(() {
                widget.globalListOptions.value = value ?? true;
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    _driveDir = widget.initialDir;
    super.initState();
    _changeDirectory(widget.initialDir)?.call();

    _scrollController.addListener(() {
      final direction = _scrollController.position.userScrollDirection;

      if (direction == ScrollDirection.reverse && _controlsVisible.value) {
        setState(() => _controlsVisible.value = false);
      } else if (direction == ScrollDirection.forward &&
          !_controlsVisible.value) {
        setState(() => _controlsVisible.value = true);
      }
    });

    widget.loading.addListener(() {
      setState(() {});
    });
    Main.setHomeState.addListener(() {
      setState(() {});
    });
    Main.onRemoteFilesChanged.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controlsVisible.dispose();
    _listOptions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _driveDir.key.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (_driveDir.key.isNotEmpty) {
          final newKey = p.s3(p.dirname(_driveDir.key));
          _changeDirectory(RemoteFile(key: newKey, size: 0, etag: ''))?.call();
          return;
        }
      },
      child: Scaffold(
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: true,
              actionsPadding: EdgeInsets.only(right: 24, top: 4, bottom: 4),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [widget.title, widget.subtitle],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    showMenu(
                      context: context,
                      position: RelativeRect.fromLTRB(1000, 60, 0, 0),
                      menuPadding: EdgeInsets.zero,
                      items: [
                        PopupMenuItem(
                          padding: EdgeInsets.zero,
                          enabled: false,
                          child: _buildPopupMenu(),
                        ),
                      ],
                    );
                  },
                ),
              ],
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(() {
                  return (28 +
                          (_driveDir.key != '' ? 24 : 0) +
                          (Main.pathFromKey(_driveDir.key) != null ? 16 : 0) +
                          (!(_profile?.accessible ?? false)
                              ? 16
                              : widget.loading.value
                              ? 4
                              : 0))
                      .toDouble();
                }()),
                child: SizedBox(
                  width: double.infinity,
                  height:
                      28 +
                      (_driveDir.key != '' ? 24 : 0) +
                      (Main.pathFromKey(_driveDir.key) != null ? 16 : 0) +
                      (!(_profile == null
                              ? true
                              : _profile?.accessible ?? false)
                          ? 16
                          : widget.loading.value
                          ? 4
                          : 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 4,
                          bottom: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Text(
                                    widget.dirModified(_driveDir),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    bytesToReadable(widget.dirSize(_driveDir)),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    () {
                                      final count = widget.count(
                                        _driveDir,
                                        recursive: true,
                                      );
                                      if (count.$1 == 0) {
                                        return '${count.$2} files';
                                      }
                                      if (count.$2 == 0) {
                                        return '${count.$1} subfolders';
                                      }
                                      return '${count.$2} files in ${count.$1} subfolders';
                                    }(),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            if (_driveDir.key != '')
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children:
                                      <Widget>[
                                            GestureDetector(
                                              onTap: _changeDirectory(
                                                RemoteFile(
                                                  key: '',
                                                  size: 0,
                                                  etag: '',
                                                ),
                                              ),
                                              child: Text(
                                                'FileS3',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge,
                                              ),
                                            ),
                                          ]
                                          .followedBy(
                                            p
                                                .split(_driveDir.key)
                                                .where((dir) => dir.isNotEmpty)
                                                .map(
                                                  (dir) => GestureDetector(
                                                    onTap: () {
                                                      String newPath = '';
                                                      for (final part
                                                          in p.split(
                                                            _driveDir.key,
                                                          )) {
                                                        if (part.isEmpty) {
                                                          continue;
                                                        }
                                                        newPath += p.asDir(
                                                          part,
                                                        );
                                                        if (part == dir) {
                                                          break;
                                                        }
                                                      }
                                                      _changeDirectory(
                                                        Main.remoteFiles
                                                            .firstWhere(
                                                              (file) =>
                                                                  p.s3(
                                                                    file.key,
                                                                  ) ==
                                                                  p.s3(newPath),
                                                            ),
                                                      )?.call();
                                                    },
                                                    child: Text(
                                                      dir,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodyLarge,
                                                    ),
                                                  ),
                                                )
                                                .map(
                                                  (widget) => Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.chevron_right,
                                                        size: 16,
                                                      ),
                                                      widget,
                                                    ],
                                                  ),
                                                ),
                                          )
                                          .toList(),
                                ),
                              ),
                            if (Main.pathFromKey(_driveDir.key) != null)
                              Row(
                                children: [
                                  Text(
                                    '${Main.backupModeFromKey(_driveDir.key).name}: ',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: GestureDetector(
                                        child: Text(
                                          Main.pathFromKey(_driveDir.key) ?? '',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                        onTap: () {
                                          // TODO: Open file explorer at this location
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (!(_profile == null
                          ? true
                          : _profile?.accessible ?? false))
                        Container(
                          width: double.infinity,
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.center,
                          child: Text(
                            'Remote access failed!',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                          ),
                        ),
                      if ((_profile == null
                          ? true
                          : _profile?.accessible ?? false))
                        ValueListenableBuilder<bool>(
                          valueListenable: widget.loading,
                          builder: (context, loading, _) =>
                              ValueListenableBuilder<double>(
                                valueListenable: widget.progress,
                                builder: (context, value, _) => loading
                                    ? LinearProgressIndicator(
                                        value: value <= 0.0 || value >= 1.0
                                            ? null
                                            : value,
                                      )
                                    : SizedBox.shrink(),
                              ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            ListFiles(
              files: _getCurrentItems().toList(),
              keysOffsetMap: _keysOffsetMap,
              thumbnailCache: widget.thumbnailCache,
              sortMode: _listOptions.value.sortMode,
              gridView: _listOptions.value.viewMode == ViewMode.grid,
              group: _listOptions.value.group,
              relativeto: _driveDir,
              onUpdate: () {
                setState(() {});
              },
              changeDirectory: _changeDirectory,
              count: widget.count,
              dirSize: widget.dirSize,
              dirModified: widget.dirModified,
            ),
          ],
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              offset:
                  !widget.loading.value &&
                      _controlsVisible.value &&
                      _profile != null &&
                      _profile!.accessible
                  ? Offset.zero
                  : const Offset(2, 0),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale:
                    !widget.loading.value &&
                        _controlsVisible.value &&
                        _profile != null &&
                        _profile!.accessible
                    ? 1
                    : 0,
                child: FloatingActionButton(
                  heroTag: 'done',
                  child: const Icon(Icons.done),
                  onPressed: () {
                    Navigator.of(context).pop(widget.onPick(_driveDir));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
