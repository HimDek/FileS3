import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:files3/media_view.dart';
import 'package:files3/utils/context_menu.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/list_files.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/settings.dart';

class PathPicker extends Browser {
  const PathPicker({
    super.key,
    super.title,
    super.subtitle,
    super.initialDir,
    super.onInit,
    required super.onPick,
  });

  @override
  PathPickerState createState() => PathPickerState();
}

class PathPickerState extends BrowserState {
  @override
  Widget floatingActionButton(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset:
              !loading.value &&
                  _controlsVisible.value &&
                  _profile != null &&
                  _profile!.accessible
              ? Offset.zero
              : const Offset(2, 0),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale:
                !loading.value &&
                    _controlsVisible.value &&
                    _profile != null &&
                    _profile!.accessible
                ? 1
                : 0,
            child: FloatingActionButton(
              heroTag: 'done',
              child: const Icon(Icons.done),
              onPressed: () {
                Navigator.of(context).pop(widget.onPick?.call(_driveDir));
              },
            ),
          ),
        ),
      ],
    );
  }
}

class MyBrowser extends Browser {
  const MyBrowser({
    super.key,
    super.title,
    super.subtitle,
    super.initialDir,
    super.onInit,
    required super.setBackupMode,
    required super.downloadFile,
    required super.downloadDirectory,
    required super.saveFile,
    required super.saveDirectory,
    required super.copyFile,
    required super.copyDirectory,
    required super.moveFiles,
    required super.moveDirectories,
    required super.deleteLocal,
    required super.deleteFiles,
    required super.deleteDirectories,
    required super.createDirectory,
    required super.uploadDirectory,
  });

  @override
  MyBrowserState createState() => MyBrowserState();
}

class MyBrowserState extends BrowserState {
  @override
  Widget floatingActionButton(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset:
              _navIndex == 0 &&
                  !loading.value &&
                  _selection.isEmpty &&
                  _controlsVisible.value &&
                  _profile != null &&
                  _profile!.accessible
              ? const Offset(0, 1)
              : const Offset(2, 1),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale:
                _navIndex == 0 &&
                    !loading.value &&
                    _selection.isEmpty &&
                    _controlsVisible.value &&
                    _profile != null &&
                    _profile!.accessible
                ? 1
                : 0,
            child: FloatingActionButton(
              heroTag: 'upload_file',
              child: const Icon(Icons.file_upload_outlined),
              onPressed: () async {
                final XFile? file = await openFile();
                if (file != null) {
                  Main.uploadFile(
                    p.join(_driveDir.key, p.basename(file.path)),
                    File(file.path),
                  );
                }
              },
            ),
          ),
        ),
        SizedBox(height: 16),
        AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset:
              _navIndex == 0 &&
                  !loading.value &&
                  _selection.isEmpty &&
                  _controlsVisible.value &&
                  _profile != null &&
                  _profile!.accessible
              ? const Offset(0, 1)
              : const Offset(2, 1),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale:
                _navIndex == 0 &&
                    !loading.value &&
                    _selection.isEmpty &&
                    _controlsVisible.value &&
                    _profile != null &&
                    _profile!.accessible
                ? 1
                : 0,
            child: FloatingActionButton(
              heroTag: 'upload_directory',
              child: const Icon(Icons.drive_folder_upload_outlined),
              onPressed: () async {
                final String? directoryPath = await getDirectoryPath();
                if (directoryPath != null) {
                  widget.uploadDirectory?.call(
                    p.join(_driveDir.key, p.basename(directoryPath)),
                    Directory(directoryPath),
                  );
                }
              },
            ),
          ),
        ),
        SizedBox(height: 16),
        AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset:
              _navIndex == 0 &&
                  !loading.value &&
                  _selection.isEmpty &&
                  _controlsVisible.value &&
                  _profile != null &&
                  _profile!.accessible
              ? const Offset(0, 1)
              : const Offset(2, 1),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale:
                _navIndex == 0 &&
                    !loading.value &&
                    _selection.isEmpty &&
                    _controlsVisible.value &&
                    _profile != null &&
                    _profile!.accessible
                ? 1
                : 0,
            child: FloatingActionButton(
              heroTag: 'create_directory',
              child: const Icon(Icons.create_new_folder_rounded),
              onPressed: () async {
                final dir = await showDialog<String>(
                  context: context,
                  builder: (context) {
                    String newDir = '';
                    return AlertDialog(
                      title: const Text('Create Directory'),
                      content: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Directory Name',
                        ),
                        onChanged: (value) => newDir = value,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(null),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(newDir),
                          child: const Text('Create'),
                        ),
                      ],
                    );
                  },
                );
                if (dir != null && dir.isNotEmpty) {
                  if (Main.remoteFiles.any(
                    (file) => [
                      p.join(_driveDir.key, dir),
                      p.asDir(p.join(_driveDir.key, dir)),
                    ].contains(file.key),
                  )) {
                    showSnackBar(
                      SnackBar(
                        content: Text(
                          '"${p.join(_driveDir.key, dir)}" already exists.',
                        ),
                      ),
                    );
                    return;
                  }
                  await widget.createDirectory?.call(
                    p.join(_driveDir.key, dir),
                  );
                }
              },
            ),
          ),
        ),
        AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset:
              _navIndex == 0 &&
                  !loading.value &&
                  _selection.isEmpty &&
                  _controlsVisible.value &&
                  _profile == null
              ? Offset.zero
              : const Offset(2, 0),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale:
                _navIndex == 0 &&
                    !loading.value &&
                    _selection.isEmpty &&
                    _controlsVisible.value &&
                    _profile == null
                ? 1
                : 0,
            child: FloatingActionButton(
              heroTag: 'add_profile',
              child: const Icon(Icons.add_circle_outline),
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (context) => S3ConfigPage()));
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget bottomNavigationBar(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _controlsVisible.value ? kBottomNavigationBarHeight + 24 : 0,
      child: Wrap(
        children: [
          SizedBox(
            height: kBottomNavigationBarHeight + 24,
            child: BottomNavigationBar(
              items: [
                BottomNavigationBarItem(
                  icon: Icon(Icons.folder_outlined),
                  activeIcon: Icon(Icons.folder),
                  label: 'Directories',
                ),
                BottomNavigationBarItem(
                  icon: Badge.count(
                    isLabelVisible: Job.jobs
                        .where((job) => job.status == JobStatus.completed)
                        .isNotEmpty,
                    count: Job.jobs
                        .where((job) => job.status == JobStatus.completed)
                        .length,
                    child: Icon(Icons.check_circle_outline),
                  ),
                  activeIcon: Badge.count(
                    isLabelVisible: Job.jobs
                        .where((job) => job.status == JobStatus.completed)
                        .isNotEmpty,
                    count: Job.jobs
                        .where((job) => job.status == JobStatus.completed)
                        .length,
                    child: Icon(Icons.check_circle),
                  ),
                  label: 'Completed',
                ),
                BottomNavigationBarItem(
                  icon: Badge.count(
                    isLabelVisible: Job.jobs
                        .where((job) => job.status != JobStatus.completed)
                        .isNotEmpty,
                    count: Job.jobs
                        .where((job) => job.status != JobStatus.completed)
                        .length,
                    child: Icon(Icons.swap_vert_circle_outlined),
                  ),
                  activeIcon: Badge.count(
                    isLabelVisible: Job.jobs
                        .where((job) => job.status != JobStatus.completed)
                        .isNotEmpty,
                    count: Job.jobs
                        .where((job) => job.status != JobStatus.completed)
                        .length,
                    child: Icon(Icons.swap_vert_circle),
                  ),
                  label: 'Active',
                ),
              ],
              enableFeedback: true,
              currentIndex: _navIndex,
              onTap: (index) async {
                setState(() {
                  _navIndex = index;
                  _controlsVisible.value = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class Browser extends StatefulWidget {
  final Widget title;
  final Widget? subtitle;
  final Function()? onInit;
  final RemoteFile initialDir;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final void Function(String, BackupMode?)? setBackupMode;
  final Function(RemoteFile)? downloadFile;
  final Function(RemoteFile)? downloadDirectory;
  final Function(RemoteFile, String)? saveFile;
  final Function(RemoteFile, String)? saveDirectory;
  final Future<void> Function(String, String)? copyFile;
  final Future<void> Function(String, String)? copyDirectory;
  final Future<void> Function(List<String>, List<String>, {bool refresh})?
  moveFiles;
  final Future<void> Function(List<String>, List<String>, {bool refresh})?
  moveDirectories;
  final Function(String)? deleteLocal;
  final Future<void> Function(List<String>, {bool refresh})? deleteFiles;
  final Future<void> Function(List<String>, {bool refresh})? deleteDirectories;
  final Future<void> Function(String)? createDirectory;
  final void Function(String, Directory)? uploadDirectory;
  final Function(RemoteFile)? onPick;

  const Browser({
    super.key,
    this.title = const Text('Select Path'),
    this.subtitle,
    this.initialDir = const RemoteFile(key: '', size: 0, etag: ''),
    this.onInit,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.setBackupMode,
    this.downloadFile,
    this.downloadDirectory,
    this.saveFile,
    this.saveDirectory,
    this.copyFile,
    this.copyDirectory,
    this.moveFiles,
    this.moveDirectories,
    this.deleteLocal,
    this.deleteFiles,
    this.deleteDirectories,
    this.createDirectory,
    this.uploadDirectory,
    this.onPick,
  });

  @override
  BrowserState createState() => BrowserState();
}

class BrowserState extends State<Browser> {
  final Set<RemoteFile> _selection = <RemoteFile>{};
  final List<RemoteFile> _allSelectableItems = <RemoteFile>[];
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<bool> _searching = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _globalListOptions = ValueNotifier<bool>(true);
  final ValueNotifier<ListOptions> _listOptions = ValueNotifier(ListOptions());
  final Map<String, double> _keysOffsetMap = <String, double>{};
  final List<GalleryProps> _galleryFiles = <GalleryProps>[];
  late RemoteFile _driveDir;
  Timer? _inaccessibleTimer;
  List<Object> _searchResults = <Object>[];
  SelectionAction _selectionAction = SelectionAction.none;
  int _dirCount = 0;
  int _fileCount = 0;
  Profile? _profile;
  int _navIndex = 0;

  String _dirModified(RemoteFile dir) {
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final file in Main.remoteFiles.where(
      (file) => p.isWithin(dir.key, file.key) && !p.isDir(file.key),
    )) {
      if (file.lastModified!.isAfter(latest)) {
        latest = file.lastModified!;
      }
    }
    return timeToReadable(latest);
  }

  (int, int) _count(RemoteFile dir, {bool recursive = false}) {
    int dirCount = 0;
    int fileCount = 0;
    for (final file in Main.remoteFiles) {
      if (p.isWithin(dir.key, file.key) &&
          file.key != dir.key &&
          (recursive || p.s3(p.dirname(file.key)) == p.s3(dir.key))) {
        if (p.isDir(file.key)) {
          dirCount += 1;
        } else {
          fileCount += 1;
        }
      }
    }
    return (dirCount, fileCount);
  }

  int _dirSize(RemoteFile dir) {
    int size = 0;
    for (final file in Main.remoteFiles) {
      if (p.isWithin(dir.key, file.key)) {
        size += file.size;
      }
    }
    return size;
  }

  void _updateCounts() {
    _dirCount = 0;
    _fileCount = 0;

    final counts = _count(_driveDir, recursive: false);
    _dirCount = counts.$1;
    _fileCount = counts.$2;
    if (_driveDir.key == '') {
      _fileCount = 0;
    }
    setState(() {});
  }

  void _setGalleryFiles(List<GalleryProps> files) {
    _galleryFiles.clear();
    _galleryFiles.addAll(files);
  }

  void Function()? _getSelectAction(RemoteFile item) =>
      _selection.any((selected) => p.isWithin(selected.key, item.key)) ||
          _selectionAction != SelectionAction.none
      ? null
      : () {
          if (p.isDir(item.key)) {
            // Deselect all children
            _selection.removeWhere(
              (selected) => p.isWithin(item.key, selected.key),
            );
          }
          if (_selection.any((selected) {
            return selected.key == item.key;
          })) {
            _selection.removeWhere((selected) {
              return selected.key == item.key;
            });
          } else {
            _selection.add(item);
          }
          setState(() {});
        };

  void _updateAllSelectableItems(List<dynamic> items) {
    _allSelectableItems.clear();
    _allSelectableItems.addAll(items.whereType<RemoteFile>());
  }

  String? _getLink(RemoteFile file, int? seconds) {
    try {
      return Main.profileFromKey(
        file.key,
      )?.fileManager?.getUrl(file.key, validForSeconds: seconds);
    } catch (e) {
      return null;
    }
  }

  Future<int?> _pushGallery(int index) async {
    int? result = await Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => Gallery(
          files: _galleryFiles,
          initialIndex: index,
          keysOffsetMap: _keysOffsetMap,
          scrollController: _scrollController,
          buildContextMenu: _buildContextMenu,
        ),
      ),
    );
    return result;
  }

  void _scrollToFile(RemoteFile file) {
    final offset = _keysOffsetMap[file.key];
    if (offset == null) return;

    _scrollController.jumpTo(
      max(0, offset - MediaQuery.of(context).size.height / 3),
    );
  }

  Function()? _changeDirectory(RemoteFile dir) => () {
    final oldDir = _driveDir;
    _navIndex = 0;
    _controlsVisible.value = true;
    _driveDir = dir;
    _profile = Main.profileFromKey(_driveDir.key);
    if (IniManager.config?.get('list_options', _driveDir.key) != null) {
      _globalListOptions.value = false;
    } else {
      _globalListOptions.value = true;
    }
    _listOptions.value = ListOptions.fromJson(
      IniManager.config?.get(
            'list_options',
            _globalListOptions.value || _navIndex != 0
                ? 'navindex_$_navIndex'
                : _driveDir.key,
          ) ??
          ListOptions().toJson(),
    );
    for (RemoteFile item in _selection) {
      if (p.isWithin(item.key, _driveDir.key) || item.key == _driveDir.key) {
        _driveDir = () {
          String dir = _driveDir.key;
          while (p.isWithin(item.key, dir) || item.key == dir) {
            dir = p.s3(p.dirname(dir));
            if (dir == '') {
              break;
            }
          }
          return Main.remoteFiles.firstWhere((file) => file.key == dir);
        }();
      }
    }
    _updateCounts();
    _scrollToFile(oldDir);
    if (_searching.value) {
      _search();
    }
  };

  Iterable<FileProps> _getCurrentItems() {
    final items = _searching.value && _navIndex == 0
        ? _searchResults
        : _driveDir.key == '' && _navIndex == 0
        ? Set<RemoteFile>.from(
            Main.remoteFiles
                .where(
                  (file) =>
                      p.s3(p.dirname(file.key)).isEmpty && p.isDir(file.key),
                )
                .map<RemoteFile>((file) => file),
          ).toList()
        : _driveDir.key != '' && _navIndex == 0
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
        : _navIndex == 1
        ? Job.jobs.where((job) => job.status == JobStatus.completed).toList()
        : _navIndex == 2
        ? Job.jobs.where((job) => job.status != JobStatus.completed).toList()
        : [];

    _updateAllSelectableItems(items.whereType<RemoteFile>().toList());

    return sort(
      items.map((file) {
        String url =
            _getLink(
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
      _listOptions.value.sortMode,
      _listOptions.value.foldersFirst,
    );
  }

  Future<void> _search() async {
    loading.value = true;
    _searchResults =
        [
          ...Main.remoteFiles.where(
            (file) =>
                p.isWithin(p.s3(_driveDir.key), p.s3(file.key)) &&
                !Job.jobs.any(
                  (job) =>
                      job.remoteKey == file.key &&
                      job.status != JobStatus.completed,
                ),
          ),
          ...Job.jobs.where(
            (job) =>
                p.isWithin(p.s3(_driveDir.key), p.s3(job.remoteKey)) &&
                job.status != JobStatus.completed,
          ),
        ].where((item) {
          if (item is RemoteFile) {
            return p
                .s3(p.relative(item.key, from: _driveDir.key))
                .toLowerCase()
                .contains(_searchController.text.trim().toLowerCase());
          } else if (item is Job) {
            return p
                .s3(p.relative(item.remoteKey, from: _driveDir.key))
                .toLowerCase()
                .contains(_searchController.text.trim().toLowerCase());
          }
          return false;
        }).toList();

    loading.value = false;
  }

  void _setListOptions(ListOptions options) {
    if (!(IniManager.config?.sections().contains('list_options') ?? true)) {
      IniManager.config?.addSection('list_options');
    }
    IniManager.config?.set(
      'list_options',
      _globalListOptions.value || _navIndex != 0
          ? 'navindex_$_navIndex'
          : _driveDir.key,
      options.toJson(),
    );
    if (_globalListOptions.value &&
        IniManager.config?.options('list_options')?.contains(_driveDir.key) ==
            true) {
      IniManager.config?.removeOption('list_options', _driveDir.key);
    }
    IniManager.save();
    setState(() {});
  }

  void _cut(RemoteFile? item) {
    if (item != null) {
      _selection.add(item);
    }
    _selectionAction = SelectionAction.cut;
    setState(() {});
  }

  void _copy(RemoteFile? item) {
    if (item != null) {
      _selection.add(item);
    }
    _selectionAction = SelectionAction.copy;
    setState(() {});
  }

  Future<void> Function()? _paste() =>
      (_selectionAction == SelectionAction.none ||
          _selection.isEmpty ||
          _navIndex != 0 ||
          _profile == null ||
          !(_profile?.accessible ?? false))
      ? null
      : () async {
          try {
            final selection = _selection.toList();
            if (_selectionAction == SelectionAction.copy) {
              final items = selection.where(
                (item) => p.s3(p.dirname(item.key)) != p.s3(_driveDir.key),
              );
              int progressCount = 0;
              final totalItems = items.length;

              for (final item in items) {
                progressCount += 1;
                progress.value = progressCount / totalItems;
                final newKey = p.join(_driveDir.key, p.basename(item.key));
                if (item.key == newKey) {
                  continue;
                }
                if (!p.isDir(item.key)) {
                  await widget.copyFile?.call(item.key, newKey);
                } else {
                  await widget.copyDirectory?.call(item.key, newKey);
                }
              }
            } else {
              final dirs = selection
                  .where(
                    (item) =>
                        p.isDir(item.key) &&
                        p.s3(p.dirname(item.key)) != p.s3(_driveDir.key),
                  )
                  .toList();
              final files = selection
                  .where(
                    (item) =>
                        !p.isDir(item.key) &&
                        p.s3(p.dirname(item.key)) != p.s3(_driveDir.key),
                  )
                  .toList();
              final dirsDestinations = dirs
                  .map((item) => p.join(_driveDir.key, p.basename(item.key)))
                  .toList();
              final filesDestinations = files
                  .map((item) => p.join(_driveDir.key, p.basename(item.key)))
                  .toList();
              widget.moveDirectories?.call(
                dirs.map((item) => item.key).toList(),
                dirsDestinations,
              );
              widget.moveFiles?.call(
                files.map((item) => item.key).toList(),
                filesDestinations,
              );
              _selection.clear();
            }
            _selectionAction = SelectionAction.none;
          } catch (e) {
            showSnackBar(SnackBar(content: Text('Error pasting items: $e')));
          }
        };

  Widget _buildContextMenu(BuildContext context, RemoteFile? file) {
    return SingleChildScrollView(
      child: file == null
          ? buildBulkContextMenu(
              context,
              _selection.toList(),
              _getLink,
              loading.value ? null : widget.downloadFile,
              loading.value ? null : widget.downloadDirectory,
              loading.value ? null : widget.saveFile,
              loading.value ? null : widget.saveDirectory,
              loading.value
                  ? null
                  : (keys, newKeys) async => await widget.moveFiles?.call(
                      keys,
                      newKeys,
                      refresh: true,
                    ),
              loading.value
                  ? null
                  : (dirs, newDirs) async => await widget.moveDirectories?.call(
                      dirs,
                      newDirs,
                      refresh: true,
                    ),
              loading.value ? null : _cut,
              loading.value ? null : _copy,
              loading.value ? null : widget.deleteLocal,
              loading.value
                  ? null
                  : (keys) async =>
                        await widget.deleteFiles?.call(keys, refresh: true),
              loading.value
                  ? null
                  : (dirs) async => await widget.deleteDirectories?.call(
                      dirs,
                      refresh: true,
                    ),
              () {
                _selection.clear();
                setState(() {});
              },
            )
          : p.isDir(file.key)
          ? buildDirectoryContextMenu(
              context,
              file,
              loading.value ? null : widget.downloadDirectory,
              loading.value ? null : widget.saveDirectory,
              loading.value ? null : _cut,
              loading.value ? null : _copy,
              loading.value
                  ? null
                  : (List<String> dirs, List<String> newDirs) async =>
                        await widget.moveDirectories?.call(
                          dirs,
                          newDirs,
                          refresh: true,
                        ),
              loading.value ? null : widget.deleteLocal,
              loading.value
                  ? null
                  : (List<String> dirs) async => await widget.deleteDirectories
                        ?.call(dirs, refresh: true),
              _count,
              _dirSize,
              _dirModified,
              widget.setBackupMode!,
            )
          : buildFileContextMenu(
              context,
              file,
              _getLink,
              loading.value ? null : widget.downloadFile,
              loading.value ? null : widget.saveFile,
              loading.value ? null : _cut,
              loading.value ? null : _copy,
              loading.value
                  ? null
                  : (List<String> keys, List<String> newKeys) async =>
                        await widget.moveFiles?.call(
                          keys,
                          newKeys,
                          refresh: true,
                        ),
              loading.value ? null : widget.deleteLocal,
              loading.value
                  ? null
                  : (List<String> keys) async =>
                        await widget.deleteFiles?.call(keys, refresh: true),
            ),
    );
  }

  Future<void> _showContextMenu(RemoteFile? file) async {
    setState(() {});
    try {
      await showModalBottomSheet(
        context: context,
        enableDrag: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxHeight: 1400, maxWidth: 1400),
        builder: (context) => _buildContextMenu(context, file),
      );
    } catch (e) {
      showSnackBar(SnackBar(content: Text('Error showing context menu: $e')));
    }

    if (loading.value) {
      final completer = Completer<void>();
      late VoidCallback listener;
      listener = () {
        if (!completer.isCompleted) {
          loading.removeListener(listener);
          completer.complete();
        }
      };

      loading.addListener(listener);
      await completer.future;
    }

    await Main.refreshWatchers();
    setState(() {});
  }

  Widget _buildPopupMenu({bool showSettings = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 0, width: 128),
        ListTile(
          dense: true,
          enabled: !loading.value && !_searching.value,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.only(left: 16, right: 16),
          titleTextStyle: Theme.of(context).textTheme.bodyMedium,
          title: Text('Refresh', maxLines: 1),
          trailing: loading.value
              ? Icon(Icons.hourglass_empty)
              : Icon(Icons.refresh),
          onTap: () {
            Main.listDirectories();
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
            _listOptions.value = _listOptions.value.sortMode == SortMode.nameAsc
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
            _listOptions.value = _listOptions.value.sortMode == SortMode.dateAsc
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
            _listOptions.value = _listOptions.value.sortMode == SortMode.sizeAsc
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
            _listOptions.value = _listOptions.value.sortMode == SortMode.typeAsc
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
          value: _globalListOptions.value,
          onChanged: (value) {
            setState(() {
              _globalListOptions.value = value ?? true;
            });
            _setListOptions(_listOptions.value);
          },
        ),
        if (showSettings) ...[
          const PopupMenuDivider(),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.only(left: 16, right: 16),
            titleTextStyle: Theme.of(context).textTheme.bodyMedium,
            title: Text('Settings', maxLines: 1),
            trailing: Icon(Icons.settings),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (context) => SettingsPage()));
            },
          ),
        ],
      ],
    );
  }

  @override
  void initState() {
    _driveDir = widget.initialDir;
    super.initState();
    widget.onInit?.call();
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

    Main.setHomeState.addListener(() {
      setState(() {});
    });
    Main.onRemoteFilesChanged.addListener(() {
      _updateCounts();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _listOptions.dispose();
    _inaccessibleTimer?.cancel();
    super.dispose();
  }

  @override
  void setState(void Function() fn) async {
    if (mounted) {
      super.setState(fn);
    }
    if (!(_profile?.accessible ?? false) &&
        !(_inaccessibleTimer?.isActive ?? false)) {
      _inaccessibleTimer = Timer.periodic(const Duration(seconds: 5), (
        timer,
      ) async {
        if (!(_profile == null ? true : _profile?.accessible ?? false)) {
          await Main.listDirectories();
        }
        if (!(_profile == null ? true : _profile?.accessible ?? false)) {
          timer.cancel();
        }
      });
    }
  }

  Widget? floatingActionButton(BuildContext context) {
    return widget.floatingActionButton;
  }

  Widget? bottomNavigationBar(BuildContext context) {
    return widget.bottomNavigationBar;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          _navIndex == 0 &&
          _driveDir.key.isEmpty &&
          !_searching.value &&
          _selection.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (_selectionAction != SelectionAction.none) {
          _selectionAction = SelectionAction.none;
          setState(() {});
          return;
        }
        if (_selection.isNotEmpty) {
          _selection.clear();
          setState(() {});
          return;
        }
        if (_searching.value) {
          _selection.clear();
          _searching.value = false;
          return;
        }
        if (_navIndex != 0) {
          _navIndex = 0;
          _controlsVisible.value = true;
          setState(() {});
          return;
        }
        if (_driveDir.key.isNotEmpty) {
          final newKey = p.s3(p.dirname(_driveDir.key));
          _changeDirectory(RemoteFile(key: newKey, size: 0, etag: ''))?.call();
          return;
        }
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([
          loading,
          _searching,
          _listOptions,
          _globalListOptions,
        ]),
        builder: (context, _) => Scaffold(
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                floating: _selection.isEmpty,
                snap: _selection.isEmpty,
                pinned: true,
                actionsPadding: EdgeInsets.only(right: 24, top: 4, bottom: 4),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_navIndex == 0)
                      if (_searching.value && widget.onPick == null)
                        Form(
                          child: TextFormField(
                            autofocus: true,
                            controller: _searchController,
                            decoration: InputDecoration(
                              visualDensity: VisualDensity.compact,
                              hintText: 'Search',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (value) {
                              _selection.clear();
                              _search();
                            },
                            onFieldSubmitted: (value) {
                              _selection.clear();
                              _search();
                            },
                          ),
                        )
                      else ...[
                        widget.title,
                        widget.subtitle ?? SizedBox.shrink(),
                      ]
                    else if (_navIndex == 1)
                      const Text("Completed Jobs")
                    else
                      const Text("Active Jobs"),

                    if (_navIndex == 0)
                      _selection.isNotEmpty
                          ? Text(
                              "${_selectionAction == SelectionAction.none
                                  ? 'Selected '
                                  : _selectionAction == SelectionAction.cut
                                  ? 'Moving '
                                  : 'Copying '}${_selection.where((item) => p.isDir(item.key)).isNotEmpty ? '${_selection.where((item) => p.isDir(item.key)).length} Folders ' : ''}${_selection.where((item) => !p.isDir(item.key)).isNotEmpty ? '${_selection.where((item) => !p.isDir(item.key)).length} Files ' : ''}",

                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          : _navIndex == 0 && widget.onPick == null
                          ? Text(
                              _searching.value
                                  ? "${_searchResults.where((item) => item is RemoteFile && p.isDir(item.key)).isNotEmpty ? '${_searchResults.where((item) => item is RemoteFile && p.isDir(item.key)).length} Folders ' : ''}${_searchResults.where((item) => item is RemoteFile && !p.isDir(item.key)).isNotEmpty ? '${_searchResults.where((item) => item is RemoteFile && !p.isDir(item.key)).length} Files ' : ''}found"
                                  : _dirCount > 0 || _fileCount > 0
                                  ? "${_dirCount > 0 ? '$_dirCount Folders ' : ''}${_fileCount > 0 ? '$_fileCount Files' : ''}"
                                  : "Empty",
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          : SizedBox.shrink(),
                  ],
                ),
                actions: _navIndex == 1
                    ? [
                        if (Job.jobs
                            .where((job) => job.status == JobStatus.completed)
                            .isNotEmpty)
                          IconButton(
                            onPressed: () {
                              Job.clearCompleted();
                              setState(() {});
                            },
                            icon: Icon(Icons.clear_all_rounded),
                          ),
                      ]
                    : _navIndex == 2
                    ? [
                        if (Job.jobs
                            .where((job) => job.status != JobStatus.completed)
                            .isNotEmpty)
                          Job.jobs.any((job) => job.status == JobStatus.running)
                              ? IconButton(
                                  onPressed: () {
                                    Job.stopall();
                                    setState(() {});
                                  },
                                  icon: Icon(Icons.stop),
                                )
                              : IconButton(
                                  onPressed: () {
                                    Job.continueAll();
                                    setState(() {});
                                  },
                                  icon: Icon(Icons.start),
                                ),
                      ]
                    : _selection.isNotEmpty
                    ? _selectionAction == SelectionAction.none
                          ? [
                              if (_selection.length <
                                  _allSelectableItems.length)
                                IconButton(
                                  onPressed: () {
                                    _selection.addAll(_allSelectableItems);
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.select_all),
                                ),
                              IconButton(
                                onPressed: () {
                                  _selection.clear();
                                  setState(() {});
                                },
                                icon: Icon(Icons.close),
                              ),
                              if (!loading.value)
                                IconButton(
                                  onPressed: () async {
                                    await Main.stopWatchers();
                                    await _showContextMenu(null);
                                  },
                                  icon: Icon(Icons.more_vert),
                                ),
                            ]
                          : [
                              if (!loading.value)
                                IconButton(
                                  onPressed: _paste(),
                                  icon: const Icon(Icons.paste),
                                ),
                              IconButton(
                                onPressed: () {
                                  _selectionAction = SelectionAction.none;
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              ),
                            ]
                    : [
                        if (!loading.value && widget.onPick == null) ...[
                          if (!_searching.value ||
                              _searchController.text.trim().isNotEmpty)
                            IconButton(
                              icon: _searching.value
                                  ? Icon(Icons.backspace)
                                  : Icon(Icons.search),
                              onPressed: _searching.value
                                  ? () {
                                      _selection.clear();
                                      _searchController.clear();
                                      _search();
                                    }
                                  : () async {
                                      _selection.clear();
                                      _searching.value = true;
                                      _search();
                                    },
                            ),
                          if (_searching.value)
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searching.value = false;
                                _selection.clear();
                                setState(() {});
                              },
                            ),
                        ],
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
                                  child: _buildPopupMenu(
                                    showSettings: widget.onPick == null,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                bottom: _navIndex == 0
                    ? PreferredSize(
                        preferredSize: Size.fromHeight(() {
                          return (28 +
                                  (_driveDir.key != '' ? 24 : 0) +
                                  (Main.pathFromKey(_driveDir.key) != null
                                      ? 16
                                      : 0) +
                                  (!(_profile?.accessible ?? false)
                                      ? 16
                                      : loading.value
                                      ? 4
                                      : 0))
                              .toDouble();
                        }()),
                        child: SizedBox(
                          width: double.infinity,
                          height:
                              28 +
                              (_driveDir.key != '' ? 24 : 0) +
                              (Main.pathFromKey(_driveDir.key) != null
                                  ? 16
                                  : 0) +
                              (!(_profile == null
                                      ? true
                                      : _profile?.accessible ?? false)
                                  ? 16
                                  : loading.value
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
                                            _dirModified(_driveDir),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            bytesToReadable(
                                              _dirSize(_driveDir),
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            () {
                                              final count = _count(
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
                                                        .where(
                                                          (dir) =>
                                                              dir.isNotEmpty,
                                                        )
                                                        .map(
                                                          (
                                                            dir,
                                                          ) => GestureDetector(
                                                            onTap: () {
                                                              String newPath =
                                                                  '';
                                                              for (final part
                                                                  in p.split(
                                                                    _driveDir
                                                                        .key,
                                                                  )) {
                                                                if (part
                                                                    .isEmpty) {
                                                                  continue;
                                                                }
                                                                newPath += p
                                                                    .asDir(
                                                                      part,
                                                                    );
                                                                if (part ==
                                                                    dir) {
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
                                                                          p.s3(
                                                                            newPath,
                                                                          ),
                                                                    ),
                                                              )?.call();
                                                            },
                                                            child: Text(
                                                              dir,
                                                              style:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .textTheme
                                                                      .bodyLarge,
                                                            ),
                                                          ),
                                                        )
                                                        .map(
                                                          (widget) => Row(
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .chevron_right,
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
                                                  Main.pathFromKey(
                                                        _driveDir.key,
                                                      ) ??
                                                      '',
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.errorContainer,
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Remote access failed!',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onErrorContainer,
                                        ),
                                  ),
                                ),
                              if ((_profile == null
                                      ? true
                                      : _profile?.accessible ?? false) &&
                                  loading.value)
                                LinearProgressIndicator(
                                  value:
                                      progress.value <= 0.0 ||
                                          progress.value >= 1.0
                                      ? null
                                      : progress.value,
                                ),
                            ],
                          ),
                        ),
                      )
                    : null,
              ),
              ListFiles(
                files: _getCurrentItems().toList(),
                galleryFiles: _galleryFiles,
                setGalleryFiles: _setGalleryFiles,
                keysOffsetMap: _keysOffsetMap,
                sortMode: _listOptions.value.sortMode,
                gridView: _listOptions.value.viewMode == ViewMode.grid,
                group: _listOptions.value.group,
                relativeto: _driveDir,
                selection: _selection,
                selectionAction: _selectionAction,
                showGallery: _pushGallery,
                onUpdate: () {
                  setState(() {});
                },
                changeDirectory: _changeDirectory,
                getSelectAction: widget.onPick == null
                    ? _getSelectAction
                    : (RemoteFile file) => () {},
                showContextMenu: widget.onPick == null
                    ? (file) async {
                        await Main.stopWatchers();
                        await _showContextMenu(file);
                      }
                    : null,
                count: _count,
                dirSize: _dirSize,
                dirModified: _dirModified,
              ),
              SliverToBoxAdapter(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPress: widget.onPick == null
                      ? () async {
                          await Main.stopWatchers();
                          await _showContextMenu(_driveDir);
                        }
                      : null,
                  child: SizedBox(height: 256, width: double.infinity),
                ),
              ),
            ],
          ),
          floatingActionButton: floatingActionButton(context),
          bottomNavigationBar: bottomNavigationBar(context),
        ),
      ),
    );
  }
}
