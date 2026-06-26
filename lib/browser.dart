import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:mime/mime.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:m3e_card_list/m3e_card_list.dart';
import 'package:file_selector/file_selector.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/context_menu.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/scrollbar.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
import 'package:files3/models.dart';
import 'package:files3/helpers.dart';
import 'package:files3/info_row.dart';
import 'package:files3/settings.dart';
import 'package:files3/media_view.dart';
import 'package:files3/list_files.dart';
import 'package:files3/pointer_pill.dart';

class FilesPicker extends Browser {
  const FilesPicker({
    super.key,
    super.title,
    super.subtitle,
    super.initialDir,
    super.onInit,
    required super.onFilesPick,
    super.mimeTypes,
    super.allowMultiple,
  });

  @override
  FilesPickerState createState() => FilesPickerState();
}

class FilesPickerState extends BrowserState {
  @override
  Widget floatingActionButton(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        loading,
        _controlsVisible,
        _driveDir,
        _profile,
        super._selection,
      ]),
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset:
                !loading.value &&
                    _controlsVisible.value &&
                    _profile.value != null &&
                    _selection.value.isNotEmpty
                ? Offset.zero
                : const Offset(2, 0),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale:
                  !loading.value &&
                      _controlsVisible.value &&
                      _profile.value != null
                  ? 1
                  : 0,
              child: FloatingActionButton(
                heroTag: 'done',
                child: const Icon(Icons.done),
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pop(widget.onFilesPick?.call(_selection.value.toList()));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    return ListenableBuilder(
      listenable: Listenable.merge([
        loading,
        _controlsVisible,
        _driveDir,
        _profile,
      ]),
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset:
                !loading.value &&
                    _controlsVisible.value &&
                    _profile.value != null
                ? Offset.zero
                : const Offset(2, 0),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale:
                  !loading.value &&
                      _controlsVisible.value &&
                      _profile.value != null
                  ? 1
                  : 0,
              child: FloatingActionButton(
                heroTag: 'done',
                child: const Icon(Icons.done),
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pop(widget.onPick?.call(_driveDir.value));
                },
              ),
            ),
          ),
        ],
      ),
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
    required super.downloadFile,
    required super.downloadDirectory,
    required super.saveFile,
    required super.saveDirectory,
    required super.deleteLocal,
    required super.deleteCache,
    required super.createDirectory,
    required super.uploadDirectory,
  });

  @override
  MyBrowserState createState() => MyBrowserState();
}

class MyBrowserState extends BrowserState {
  @override
  Widget floatingActionButton(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        loading,
        _navIndex,
        _driveDir,
        _controlsVisible,
        _selection,
        _profile,
        _profile.value?.accessible,
      ]),
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset:
                _navIndex.value == 0 &&
                    !loading.value &&
                    _selection.value.isEmpty &&
                    _controlsVisible.value &&
                    _profile.value != null &&
                    _profile.value!.accessible.value
                ? const Offset(0, 1)
                : const Offset(2, 1),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale:
                  _navIndex.value == 0 &&
                      !loading.value &&
                      _selection.value.isEmpty &&
                      _controlsVisible.value &&
                      _profile.value != null &&
                      _profile.value!.accessible.value
                  ? 1
                  : 0,
              child: FloatingActionButton(
                heroTag: 'upload_file',
                child: const Icon(Icons.file_upload_outlined),
                onPressed: () async {
                  final XFile? file = await openFile();
                  if (file != null) {
                    Main.uploadFile(
                      p.s3.join(_driveDir.value, p.context.basename(file.path)),
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
                _navIndex.value == 0 &&
                    !loading.value &&
                    _selection.value.isEmpty &&
                    _controlsVisible.value &&
                    _profile.value != null &&
                    _profile.value!.accessible.value
                ? const Offset(0, 1)
                : const Offset(2, 1),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale:
                  _navIndex.value == 0 &&
                      !loading.value &&
                      _selection.value.isEmpty &&
                      _controlsVisible.value &&
                      _profile.value != null &&
                      _profile.value!.accessible.value
                  ? 1
                  : 0,
              child: FloatingActionButton(
                heroTag: 'upload_directory',
                child: const Icon(Icons.drive_folder_upload_outlined),
                onPressed: () async {
                  final String? directoryPath = await getDirectoryPath();
                  if (directoryPath != null) {
                    widget.uploadDirectory?.call(
                      p.s3.join(
                        _driveDir.value,
                        p.context.basename(directoryPath),
                      ),
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
                _navIndex.value == 0 &&
                    !loading.value &&
                    _selection.value.isEmpty &&
                    _controlsVisible.value &&
                    _profile.value != null &&
                    _profile.value!.accessible.value
                ? const Offset(0, 1)
                : const Offset(2, 1),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale:
                  _navIndex.value == 0 &&
                      !loading.value &&
                      _selection.value.isEmpty &&
                      _controlsVisible.value &&
                      _profile.value != null &&
                      _profile.value!.accessible.value
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
                    if (Main.remoteFileByKey(p.s3.join(_driveDir.value, dir)) !=
                            null ||
                        Main.remoteFileByKey(
                              p.s3.asDir(p.s3.join(_driveDir.value, dir)),
                            ) !=
                            null) {
                      showSnackBar(
                        SnackBar(
                          content: Text(
                            '"${p.s3.join(_driveDir.value, dir)}" already exists.',
                          ),
                        ),
                      );
                      return;
                    }
                    await widget.createDirectory?.call(
                      p.s3.join(_driveDir.value, dir),
                    );
                  }
                },
              ),
            ),
          ),
          AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset:
                _navIndex.value == 0 &&
                    !loading.value &&
                    _selection.value.isEmpty &&
                    _controlsVisible.value &&
                    _profile.value == null
                ? Offset.zero
                : const Offset(2, 0),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale:
                  _navIndex.value == 0 &&
                      !loading.value &&
                      _selection.value.isEmpty &&
                      _controlsVisible.value &&
                      _profile.value == null
                  ? 1
                  : 0,
              child: FloatingActionButton(
                heroTag: 'add_profile',
                child: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => S3ConfigPage()),
                  );
                },
              ),
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
  final String initialDir;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Function(String)? downloadFile;
  final Function(String)? downloadDirectory;
  final Function(String, String)? saveFile;
  final Function(String, String)? saveDirectory;
  final Function(String)? deleteLocal;
  final Function(String)? deleteCache;
  final Future<void> Function(String)? createDirectory;
  final void Function(String, Directory)? uploadDirectory;
  final Function(String)? onPick;
  final Function(List<String>)? onFilesPick;
  final List<RegExp>? mimeTypes;
  final bool allowMultiple;

  const Browser({
    super.key,
    this.title = const Text('Select Path'),
    this.subtitle,
    this.initialDir = '',
    this.onInit,
    this.drawer,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.downloadFile,
    this.downloadDirectory,
    this.saveFile,
    this.saveDirectory,
    this.deleteLocal,
    this.deleteCache,
    this.createDirectory,
    this.uploadDirectory,
    this.onPick,
    this.onFilesPick,
    this.mimeTypes,
    this.allowMultiple = true,
  });

  @override
  BrowserState createState() => BrowserState();
}

class BrowserState extends State<Browser> {
  final Map<String, double> _keysOffsetMap = {};
  final Map<String, double> _groupOffsetMap = <String, double>{};

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  final ValueNotifier<int> _navIndex = ValueNotifier(0);
  final ValueNotifier<int> _dirCount = ValueNotifier(0);
  final ValueNotifier<int> _fileCount = ValueNotifier(0);
  final ValueNotifier<bool> _searching = ValueNotifier(false);
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
  final ValueNotifier<bool> _globalListOptions = ValueNotifier(true);
  final ValueNotifier<bool> _thumbVisibility = ValueNotifier(false);
  final ValueNotifier<Profile?> _profile = ValueNotifier(null);
  final ValueNotifier<String> _driveDir = ValueNotifier(Main.root.key);
  final ValueNotifier<ListOptions> _listOptions = ValueNotifier(ListOptions());
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
  final ValueNotifier<SelectionAction> _selectionAction = ValueNotifier(
    SelectionAction.none,
  );
  final ValueNotifier<Set<String>> _selection = ValueNotifier({});
  final ValueNotifier<Iterable> _searchResults = ValueNotifier<Iterable>([]);
  final ValueNotifier<Iterable> _currentItems = ValueNotifier<Iterable>([]);
  final ValueNotifier<Iterable<FileProps>> _currentProps =
      ValueNotifier<Iterable<FileProps>>([]);
  final ManualNotifier _rebuildContext = ManualNotifier();

  Iterable<String> get _allSelectableItems => widget.allowMultiple
      ? _currentItems.value
            .whereType<RemoteFile>()
            .map((file) => file.key)
            .where(
              (key) =>
                  p.isDir(key) ||
                  _mimeTypes.any(
                    (mime) => mime.hasMatch(
                      lookupMimeType(key) ?? 'application/octet-stream',
                    ),
                  ),
            )
      : const [];

  late final Listenable _currentItemsNotifiers = Listenable.merge([
    _navIndex,
    _driveDir,
    _searching,
    _searchResults,
    Main.onRemoteFilesChanged,
    Job.onJobsChanged,
    Job.onProgressUpdate,
  ]);
  late final List<RegExp> _mimeTypes = widget.mimeTypes ?? [allMimePattern];

  Timer? _scrollbarTimer;
  Timer? _inaccessibleTimer;

  double _lastScrollOffset = 0;

  Future<void> _updateCounts() async {
    _dirCount.value = 0;
    _fileCount.value = 0;

    final counts =
        await Main.remoteFileByKey(
          _driveDir.value,
        )?.getCount(recursive: false) ??
        (0, 0);
    _dirCount.value = counts.$1;
    _fileCount.value = counts.$2;
    if (_driveDir.value == '') {
      _fileCount.value = 0;
    }
  }

  void Function()? _getSelectAction(String key) =>
      _selection.value.any((selected) => p.s3.isWithin(selected, key)) ||
          _selectionAction.value != SelectionAction.none ||
          (!p.isDir(key) &&
              _mimeTypes.every(
                (mime) => !mime.hasMatch(
                  lookupMimeType(key) ?? 'application/octet-stream',
                ),
              ))
      ? null
      : () {
          if (p.isDir(key)) {
            if (_selection.value.any(
              (selected) => p.s3.isWithin(key, selected),
            )) {
              // Deselect all children
              _selection.value = _selection.value
                  .where((selected) => !p.s3.isWithin(key, selected))
                  .toSet();
            }
          }
          if (_selection.value.any((selected) => selected == key)) {
            _selection.value = _selection.value
                .where((selected) => selected != key)
                .toSet();
          } else {
            if (widget.allowMultiple) {
              _selection.value = {..._selection.value, key};
            } else {
              _selection.value = {key};
            }
          }
        };

  String? _getLink(String key, int? seconds) {
    try {
      return Main.profileFromKey(
        key,
      )?.fileManager?.getUrl(key, validForSeconds: seconds);
    } catch (e) {
      return null;
    }
  }

  Future<String?> _pushGallery(String key) async {
    int i = 0, index = 0;
    final files = _currentProps.value.where((f) => !p.isDir(f.key)).map((f) {
      if (f.key == key) {
        index = i;
      }
      i++;
      return GalleryProps(
        key: f.key,
        title: p.s3.isWithin(_driveDir.value, f.key)
            ? p.s3.relative(f.key, from: _driveDir.value)
            : f.key,
        url: f.url!,
        path: Main.pathFromKey(f.key),
        cachePath: Main.cachePathFromKey(f.key),
      );
    }).toList();

    final result = await Navigator.of(context).push<String>(
      PageRouteBuilder<String>(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => Gallery(
          files: files,
          initialIndex: index,
          keysOffsetMap: _keysOffsetMap,
          scrollController: _scrollController,
          buildContextMenu: (BuildContext context, int index) =>
              _buildContextMenu(context, files[index].key),
          rebuildContext: _rebuildContext.notifyListeners,
        ),
      ),
    );

    _scrollToFile(result ?? '');

    return result;
  }

  void _scrollToFile(String key) {
    final offset = _keysOffsetMap[key];
    if (offset == null) return;

    _scrollController.jumpTo(
      max(0, offset - MediaQuery.of(context).size.height / 3),
    );
  }

  void _changeDirectory(String ndir) {
    final oldDir = _driveDir.value;
    _navIndex.value = 0;
    _controlsVisible.value = true;
    var dir = ndir;
    for (String item in _selection.value) {
      if (p.s3.isWithin(item, ndir) || item == ndir) {
        dir = () {
          while (p.s3.isWithin(item, ndir) || item == ndir) {
            ndir = p.s3.dirname(ndir);
            if (ndir == '') {
              break;
            }
          }
          return ndir;
        }();
      }
    }
    _driveDir.value = dir.isEmpty ? Main.root.key : dir;
    _profile.value = Main.profileFromKey(_driveDir.value);
    _updateCounts();
    _scrollToFile(oldDir);
    if (_searching.value) {
      _search();
    }
  }

  void _applyListOptions() {
    _currentProps.value = _currentItems.value.map((file) {
      String url =
          _getLink(
            file is Job ? file.remoteKey : (file as RemoteFile).key,
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
          ? FileProps(
              key: file.key,
              size: file.size,
              lastModified: file.lastModified,
              url: url,
            )
          : FileProps(
              key: file.key,
              size: file.size,
              lastModified: file.lastModified,
              url: url,
            );
    });
    if (!_searching.value) {
      _currentProps.value = sort(
        _currentItems.value.map((file) {
          String url =
              _getLink(
                file is Job ? file.remoteKey : (file as RemoteFile).key,
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
              ? FileProps(
                  key: file.key,
                  size: file.size,
                  lastModified: file.lastModified,
                  url: url,
                )
              : FileProps(
                  key: file.key,
                  size: file.size,
                  lastModified: file.lastModified,
                  url: url,
                );
        }),
        _sortMode.value,
        _foldersFirst.value,
      );
    }
  }

  void _setCurrentItems() {
    if (kDebugMode) {
      debugPrint('Refreshing current items set...');
    }
    _currentItems.value = _searching.value && _navIndex.value == 0
        ? _searchResults.value
        : _driveDir.value == '' && _navIndex.value == 0
        ? Main.remoteFilesByDir(
            '',
            recursive: false,
          ).where((file) => p.isDir(file.key))
        : _driveDir.value != '' && _navIndex.value == 0
        ? Main.remoteFilesByDir(_driveDir.value, recursive: false)
              .where(
                (file) => !Job.jobs.any((job) => job.remoteKey == file.key),
              )
              .cast<dynamic>()
              .followedBy(
                Job.jobs
                    .where(
                      (job) => p.s3.dirname(job.remoteKey) == _driveDir.value,
                    )
                    .cast<dynamic>(),
              )
        : _navIndex.value == 1
        ? Job.completedJobs
        : _navIndex.value == 2
        ? Job.jobs
        : [];
    if (kDebugMode) {
      debugPrint('Current items set: ${_currentItems.value.length} items');
    }
  }

  Future<void> _search() async {
    loading.value = true;
    _searchResults.value = extractAllSorted(
      query: _searchController.text.trim().toLowerCase(),
      choices: [
        ...Main.remoteFilesByDir(
          _driveDir.value,
          recursive: true,
        ).where((file) => !Job.jobs.any((job) => job.remoteKey == file.key)),
        ...Job.jobs.where(
          (job) => p.s3.isWithin(_driveDir.value, job.remoteKey),
        ),
      ],
      cutoff: 40,
      getter: (item) {
        String key = item is Job ? item.remoteKey : (item as RemoteFile).key;
        return key.toLowerCase();
      },
    ).map((result) => result.choice);

    loading.value = false;
  }

  void _setListOptions(ListOptions options) {
    if (!(IniManager.config.value?.sections().contains('list_options') ??
        true)) {
      IniManager.config.value?.addSection('list_options');
    }
    IniManager.config.value?.set(
      'list_options',
      _globalListOptions.value || _navIndex.value != 0
          ? 'navindex_${_navIndex.value}'
          : _driveDir.value,
      options.toJson(),
    );
    if (_globalListOptions.value &&
        IniManager.config.value
                ?.options('list_options')
                ?.contains(_driveDir.value) ==
            true) {
      IniManager.config.value?.removeOption('list_options', _driveDir.value);
    }
    IniManager.save();
  }

  void _fetchListOptions() {
    if (IniManager.config.value?.get('list_options', _driveDir.value) != null) {
      _globalListOptions.value = false;
    } else {
      _globalListOptions.value = true;
    }
    _listOptions.value = _searching.value
        ? ListOptions()
        : ListOptions.fromJson(
            IniManager.config.value?.get(
                  'list_options',
                  _globalListOptions.value || _navIndex.value != 0
                      ? 'navindex_${_navIndex.value}'
                      : _driveDir.value,
                ) ??
                ListOptions().toJson(),
          );
  }

  void _cut(String? key) {
    if (key != null) {
      _selection.value = {..._selection.value, key};
    }
    _selectionAction.value = SelectionAction.cut;
  }

  void _copy(String? key) {
    if (key != null) {
      _selection.value = {..._selection.value, key};
    }
    _selectionAction.value = SelectionAction.copy;
  }

  void _profileAccessibilityListener() {
    if (!(_profile.value?.accessible.value ?? false) &&
        !(_inaccessibleTimer?.isActive ?? false)) {
      _inaccessibleTimer = Timer.periodic(const Duration(seconds: 5), (
        timer,
      ) async {
        if (!(_profile.value == null
            ? true
            : _profile.value?.accessible.value ?? false)) {
          await Main.listDirectories();
        }
        if ((_profile.value == null
            ? true
            : _profile.value?.accessible.value ?? false)) {
          timer.cancel();
        }
      });
    }
  }

  Future<void> Function()? _paste() =>
      (_selectionAction.value == SelectionAction.none ||
          _selection.value.isEmpty ||
          _navIndex.value != 0 ||
          _profile.value == null ||
          !(_profile.value?.accessible.value ?? false))
      ? null
      : () async {
          try {
            final selection = _selection.value;
            if (_selectionAction.value == SelectionAction.copy) {
              final items = selection.where(
                (item) => p.s3.dirname(item) != _driveDir.value,
              );
              int progressCount = 0;
              final totalItems = items.length;

              for (final item in items) {
                progressCount += 1;
                progress.value = progressCount / totalItems;
                final newKey = p.s3.join(_driveDir.value, p.s3.basename(item));
                if (item == newKey) {
                  continue;
                }
                if (!p.isDir(item)) {
                  await Main.copyFile(item, newKey);
                } else {
                  await Main.copyDirectory(item, newKey);
                }
              }
            } else {
              final dirs = selection.where(
                (item) =>
                    p.isDir(item) && p.s3.dirname(item) != _driveDir.value,
              );
              final files = selection.where(
                (item) =>
                    !p.isDir(item) && p.s3.dirname(item) != _driveDir.value,
              );
              final dirsDestinations = dirs.map(
                (item) => p.s3.join(_driveDir.value, p.s3.basename(item)),
              );
              final filesDestinations = files.map(
                (item) => p.s3.join(_driveDir.value, p.s3.basename(item)),
              );
              Main.moveDirectories(dirs.map((item) => item), dirsDestinations);
              Main.moveFiles(files.map((item) => item), filesDestinations);
              _selection.value = {};
            }
            _selectionAction.value = SelectionAction.none;
          } catch (e) {
            showSnackBar(SnackBar(content: Text('Error pasting items: $e')));
          }
        };

  Widget _buildContextMenu(BuildContext context, String? key) {
    final file = key == null ? null : Main.remoteFileByKey(key);
    return ListenableBuilder(
      listenable: Listenable.merge([
        loading,
        _rebuildContext,
        Job.onProgressUpdate,
      ]),
      builder: (context, _) => SingleChildScrollView(
        child: file == null
            ? buildBulkContextMenu(
                context,
                _selection.value,
                _getLink,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.downloadFile,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.downloadDirectory,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.saveFile,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.saveDirectory,
                loading.value || widget.onFilesPick != null ? null : _cut,
                loading.value || widget.onFilesPick != null ? null : _copy,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.deleteLocal,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.deleteCache,
                loading.value || widget.onFilesPick != null
                    ? null
                    : (keys) async =>
                          await Main.deleteFiles(keys, refresh: true),
                loading.value || widget.onFilesPick != null
                    ? null
                    : (dirs) async =>
                          await Main.deleteDirectories(dirs, refresh: true),
                () {
                  _selection.value = {};
                },
                () {
                  _rebuildContext.notifyListeners();
                },
              )
            : p.isDir(file.key)
            ? buildDirectoryContextMenu(
                context,
                file.key,
                _selection.value.isEmpty,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.downloadDirectory,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.saveDirectory,
                loading.value || widget.onFilesPick != null ? null : _cut,
                loading.value || widget.onFilesPick != null ? null : _copy,
                loading.value || widget.onFilesPick != null
                    ? null
                    : (List<String> dirs, List<String> newDirs) async =>
                          await Main.moveDirectories(
                            dirs,
                            newDirs,
                            refresh: true,
                          ),
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.deleteLocal,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.deleteCache,
                loading.value || widget.onFilesPick != null
                    ? null
                    : (List<String> dirs) async =>
                          await Main.deleteDirectories(dirs, refresh: true),
                () {
                  _rebuildContext.notifyListeners();
                },
              )
            : buildFileContextMenu(
                context,
                file.key,
                _selection.value.isEmpty,
                _getLink,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.downloadFile,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.saveFile,
                loading.value || widget.onFilesPick != null ? null : _cut,
                loading.value || widget.onFilesPick != null ? null : _copy,
                loading.value || widget.onFilesPick != null
                    ? null
                    : (List<String> keys, List<String> newKeys) async =>
                          await Main.moveFiles(keys, newKeys, refresh: true),
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.deleteLocal,
                loading.value || widget.onFilesPick != null
                    ? null
                    : widget.deleteCache,
                loading.value || widget.onFilesPick != null
                    ? null
                    : (List<String> keys) async =>
                          await Main.deleteFiles(keys, refresh: true),
                () {
                  _rebuildContext.notifyListeners();
                },
              ),
      ),
    );
  }

  Future<void> _showContextMenu(String? key) async {
    try {
      await showModalBottomSheet(
        context: context,
        enableDrag: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxHeight: 1400, maxWidth: 1400),
        builder: (context) => _buildContextMenu(context, key),
      );
    } catch (e) {
      showSnackBar(SnackBar(content: Text('Error showing context menu: $e')));
    }

    if (loading.value) {
      final completer = Completer<void>();
      void listener() {
        if (!completer.isCompleted) {
          loading.removeListener(listener);
          completer.complete();
        }
      }

      loading.addListener(listener);
      await completer.future;
    }

    await Main.refreshWatchers();
  }

  Widget _buildPopupMenu(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        loading,
        _searching,
        _sortMode,
        _foldersFirst,
        _viewMode,
        _group,
        _globalListOptions,
      ]),
      builder: (context, _) => M3ECardColumn(
        padding: EdgeInsets.all(8),
        children: [
          M3ECardColumn(
            padding: EdgeInsets.zero,
            outerRadius: 16,
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                enabled: !loading.value && !_searching.value,
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
            ],
          ),
          M3ECardColumn(
            padding: EdgeInsets.zero,
            outerRadius: 16,
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.only(left: 16, right: 16),
                titleTextStyle: Theme.of(context).textTheme.bodyMedium,
                title: Text('Name'),
                trailing: _sortMode.value == SortMode.nameAsc
                    ? Icon(Icons.arrow_upward)
                    : _sortMode.value == SortMode.nameDesc
                    ? Icon(Icons.arrow_downward)
                    : null,
                onTap: () {
                  _listOptions.value = _sortMode.value == SortMode.nameAsc
                      ? _listOptions.value.copyWith(sortMode: SortMode.nameDesc)
                      : _listOptions.value.copyWith(sortMode: SortMode.nameAsc);
                  _setListOptions(_listOptions.value);
                },
              ),
              SizedBox(height: 0, width: 160),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.only(left: 16, right: 16),
                titleTextStyle: Theme.of(context).textTheme.bodyMedium,
                title: Text('Date'),
                trailing: _sortMode.value == SortMode.dateAsc
                    ? Icon(Icons.arrow_upward)
                    : _sortMode.value == SortMode.dateDesc
                    ? Icon(Icons.arrow_downward)
                    : null,
                onTap: () {
                  _listOptions.value = _sortMode.value == SortMode.dateAsc
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
                trailing: _sortMode.value == SortMode.sizeAsc
                    ? Icon(Icons.arrow_upward)
                    : _sortMode.value == SortMode.sizeDesc
                    ? Icon(Icons.arrow_downward)
                    : null,
                onTap: () {
                  _listOptions.value = _sortMode.value == SortMode.sizeAsc
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
                trailing: _sortMode.value == SortMode.typeAsc
                    ? Icon(Icons.arrow_upward)
                    : _sortMode.value == SortMode.typeDesc
                    ? Icon(Icons.arrow_downward)
                    : null,
                onTap: () {
                  _listOptions.value = _sortMode.value == SortMode.typeAsc
                      ? _listOptions.value.copyWith(sortMode: SortMode.typeDesc)
                      : _listOptions.value.copyWith(sortMode: SortMode.typeAsc);
                  _setListOptions(_listOptions.value);
                },
              ),
            ],
          ),
          M3ECardColumn(
            padding: EdgeInsets.zero,
            outerRadius: 16,
            children: [
              CheckboxListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.only(left: 16, right: 16),
                title: Text(
                  'Folders First',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                value: _foldersFirst.value,
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
                value: _viewMode.value == ViewMode.grid,
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
                value: _group.value,
                onChanged: (value) {
                  _listOptions.value = _listOptions.value.copyWith(
                    group: value ?? true,
                  );
                  _setListOptions(_listOptions.value);
                },
              ),
              CheckboxListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.only(left: 16, right: 16),
                title: Text(
                  'Only here',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                value: !_globalListOptions.value,
                onChanged: (value) {
                  _globalListOptions.value = !(value ?? true);
                  _setListOptions(_listOptions.value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.onInit?.call();
    _changeDirectory(widget.initialDir);

    _profile.addListener(() {
      if (_profile.value != null) {
        _profile.value!.accessible.removeListener(
          _profileAccessibilityListener,
        );
        _profile.value!.accessible.addListener(_profileAccessibilityListener);
      }
      if (_profile.value != null && !_profile.value!.accessible.value) {
        _profileAccessibilityListener();
      }
    });

    _scrollController.addListener(() {
      var direction = ScrollDirection.idle;

      if (_scrollController.hasClients) {
        final offset = _scrollController.offset;
        direction = offset > _lastScrollOffset
            ? ScrollDirection.reverse
            : offset < _lastScrollOffset
            ? ScrollDirection.forward
            : ScrollDirection.idle;
        _lastScrollOffset = offset;
      }

      if (_scrollController.position.maxScrollExtent > 0) {
        _scrollbarTimer?.cancel();
        _thumbVisibility.value = true;
        _scrollbarTimer = Timer(const Duration(seconds: 2), () {
          _thumbVisibility.value = false;
        });
      }

      if (direction == ScrollDirection.reverse) {
        _controlsVisible.value = false;
      } else if (direction == ScrollDirection.forward) {
        _controlsVisible.value = true;
      }
    });

    _currentItemsNotifiers.addListener(_setCurrentItems);

    Listenable.merge([
      _navIndex,
      _driveDir,
      _searching,
    ]).addListener(_fetchListOptions);

    Listenable.merge([
      _currentItems,
      _sortMode,
      _foldersFirst,
    ]).addListener(_applyListOptions);

    Main.onRemoteFilesChanged.addListener(_updateCounts);

    Listenable.merge([_listOptions]).addListener(() {
      _sortMode.value = _listOptions.value.sortMode;
      _viewMode.value = _listOptions.value.viewMode;
      _foldersFirst.value = _listOptions.value.foldersFirst;
      _group.value = _listOptions.value.group;
    });

    if (IniManager.config.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        IniManager.config.addListener(() {
          if (IniManager.config.value != null) {
            _fetchListOptions();
          }
        });
        if (!loading.value) {
          _setCurrentItems();
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchListOptions();
        if (!loading.value) {
          _setCurrentItems();
        }
      });
    }
  }

  @override
  void dispose() {
    _profile.value?.accessible.removeListener(_profileAccessibilityListener);
    _currentItemsNotifiers.removeListener(_setCurrentItems);
    Main.onRemoteFilesChanged.removeListener(_updateCounts);
    _searchController.dispose();
    _scrollController.dispose();
    _navIndex.dispose();
    _dirCount.dispose();
    _fileCount.dispose();
    _searching.dispose();
    _controlsVisible.dispose();
    _globalListOptions.dispose();
    _thumbVisibility.dispose();
    _profile.dispose();
    _driveDir.dispose();
    _listOptions.dispose();
    _sortMode.dispose();
    _viewMode.dispose();
    _foldersFirst.dispose();
    _group.dispose();
    _selectionAction.dispose();
    _selection.dispose();
    _searchResults.dispose();
    _currentItems.dispose();
    _currentProps.dispose();
    _scrollbarTimer?.cancel();
    _inaccessibleTimer?.cancel();
    super.dispose();
  }

  Widget? drawer(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _navIndex,
        Job.onJobsChanged,
        Job.onProgressUpdate,
      ]),
      builder: (context, _) => NavigationDrawer(
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 32),
            title: Text(
              'Files3',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            onTap: () {
              Navigator.of(context).pop();
              _navIndex.value = 0;
              _controlsVisible.value = true;
            },
          ),
          Divider(),
          Container(
            decoration: BoxDecoration(
              color: _navIndex.value == 2
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              borderRadius: BorderRadius.circular(32),
            ),
            margin: EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              title: Text('Active'),
              leading: Icon(
                _navIndex.value == 2
                    ? Icons.swap_vert_circle
                    : Icons.swap_vert_circle_outlined,
              ),
              trailing: Job.jobs.isNotEmpty
                  ? Text(Job.jobs.length.toString())
                  : null,
              selected: _navIndex.value == 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _navIndex.value = 2;
                _controlsVisible.value = true;
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _navIndex.value == 1
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              borderRadius: BorderRadius.circular(32),
            ),
            margin: EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              title: Text('Completed'),
              leading: Icon(
                _navIndex.value == 1
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
              ),
              trailing: Job.completedJobs.isNotEmpty
                  ? Text(Job.completedJobs.length.toString())
                  : null,
              selected: _navIndex.value == 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _navIndex.value = 1;
                _controlsVisible.value = true;
              },
            ),
          ),
          Divider(),
          Container(
            decoration: BoxDecoration(
              color: _navIndex.value == 0 && _driveDir.value == ''
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              borderRadius: BorderRadius.circular(32),
            ),
            margin: EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              title: Text('Home'),
              leading: Icon(
                _navIndex.value == 0 && _driveDir.value == ''
                    ? Icons.home
                    : Icons.home_outlined,
              ),
              selected: _navIndex.value == 0 && _driveDir.value == '',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _navIndex.value = 0;
                _controlsVisible.value = true;
                _driveDir.value = Main.root.key;
              },
            ),
          ),
          for (final pinned in ConfigManager.loadPinnedFolders())
            Container(
              decoration: BoxDecoration(
                color: _navIndex.value == 0 && _driveDir.value == pinned.value
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                borderRadius: BorderRadius.circular(32),
              ),
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                title: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(pinned.key),
                ),
                leading: Icon(
                  _navIndex.value == 0 && _driveDir.value == pinned.value
                      ? Icons.folder
                      : Icons.folder_outlined,
                ),
                selected:
                    _navIndex.value == 0 && _driveDir.value == pinned.value,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _navIndex.value = 0;
                  _controlsVisible.value = true;
                  _driveDir.value = pinned.value;
                },
              ),
            ),
          Divider(),
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(32)),
            margin: EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              title: Text('Settings'),
              leading: Icon(Icons.settings),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (context) => SettingsPage()));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget? floatingActionButton(BuildContext context) {
    return widget.floatingActionButton;
  }

  Widget? bottomNavigationBar(BuildContext context) {
    return widget.bottomNavigationBar;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _navIndex,
        _driveDir,
        _searching,
        _selection,
        _selectionAction,
        _controlsVisible,
      ]),
      builder: (context, child) => PopScope(
        canPop:
            _navIndex.value == 0 &&
            _driveDir.value.isEmpty &&
            !_searching.value &&
            _selection.value.isEmpty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) {
            return;
          }
          // if (_selectionAction.value != SelectionAction.none) {
          //   _selectionAction.value = SelectionAction.none;
          //   return;
          // }
          // if (_selection.value.isNotEmpty) {
          //   _selection.value = {};
          //   return;
          // }
          if (_searching.value) {
            _selection.value = {};
            _searching.value = false;
            return;
          }
          if (_navIndex.value != 0) {
            _navIndex.value = 0;
            _controlsVisible.value = true;
            return;
          }
          if (_driveDir.value.isNotEmpty) {
            final newKey = p.s3.dirname(_driveDir.value);
            _changeDirectory(newKey);
            return;
          }
        },
        child: child!,
      ),
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async {
            Main.listDirectories();
          },
          child: ListenableBuilder(
            listenable: _thumbVisibility,
            builder: (context, child) => CustomThumbScrollbar(
              controller: _scrollController,
              padding: EdgeInsets.only(top: kToolbarHeight),
              thumbVisibility: _thumbVisibility.value,
              thumb: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              minThumbLength: 64,
              maxThumbLength: 64,
              popup: ListenableBuilder(
                listenable: Listenable.merge([_scrollController]),
                builder: (context, child) {
                  final group = _groupOffsetMap.keys.reduce(
                    (a, b) =>
                        (_groupOffsetMap[a]! -
                                    _scrollController.offset -
                                    MediaQuery.sizeOf(context).height / 2)
                                .abs() <
                            (_groupOffsetMap[b]! -
                                    _scrollController.offset -
                                    MediaQuery.sizeOf(context).height / 2)
                                .abs()
                        ? a
                        : b,
                  );
                  return Padding(
                    padding: EdgeInsets.all(8),
                    child: PointerPill(
                      color: Theme.of(context).colorScheme.primary,
                      pointerWidth: 28,
                      smoothness: 4,
                      child: Container(
                        constraints: BoxConstraints(minWidth: 24),
                        child: Text(
                          group.replaceAll('_folder', ''),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                },
              ),
              child: child!,
            ),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              controller: _scrollController,
              slivers: [
                ListenableBuilder(
                  listenable: Listenable.merge([
                    _navIndex,
                    _driveDir,
                    _searching,
                    _searchResults,
                    _selection,
                    _selectionAction,
                    _dirCount,
                    _fileCount,
                    _profile,
                    _profile.value?.accessible,
                    Main.onRemoteFilesChanged,
                    Job.onJobsChanged,
                    uiConfigNotifier.showDirectorySummary,
                    uiConfigNotifier.showDirectoryBackupConfig,
                    progress,
                    loading,
                  ]),
                  builder: (context, child) => SliverAppBar(
                    floating: _selection.value.isEmpty,
                    snap: _selection.value.isEmpty,
                    pinned: true,
                    actionsPadding: EdgeInsets.only(right: 6),
                    leading: drawer(context) != null
                        ? IconButton(
                            icon: Badge(
                              isLabelVisible: Job.jobs.isNotEmpty,
                              label: Job.jobs.isNotEmpty
                                  ? Text(
                                      Job.jobs.length.toString(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                          ),
                                    )
                                  : null,
                              child: Icon(Icons.menu),
                            ),
                            onPressed: () {
                              Scaffold.of(context).openDrawer();
                            },
                          )
                        : null,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_navIndex.value == 0)
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
                                  helperText: _searchResults.value.isNotEmpty
                                      ? "${_searchResults.value.any((item) => item is RemoteFile && p.isDir(item.key)) ? '${_searchResults.value.where((item) => item is RemoteFile && p.isDir(item.key)).length} Folders ' : ''}"
                                            "${_searchResults.value.any((item) => item is RemoteFile && !p.isDir(item.key)) ? '${_searchResults.value.where((item) => item is RemoteFile && !p.isDir(item.key)).length} Files ' : ''}found"
                                      : "No results found",
                                ),
                                onChanged: (value) {
                                  _selection.value = {};
                                  _search();
                                },
                                onFieldSubmitted: (value) {
                                  _selection.value = {};
                                  _search();
                                },
                              ),
                            )
                          else ...[
                            widget.title,
                            widget.subtitle ?? SizedBox.shrink(),
                          ]
                        else if (_navIndex.value == 1)
                          const Text("Completed Jobs")
                        else
                          const Text("Active Jobs"),

                        if (_navIndex.value == 0)
                          _selection.value.isNotEmpty
                              ? Text(
                                  "${_selectionAction.value == SelectionAction.none
                                      ? 'Selected '
                                      : _selectionAction.value == SelectionAction.cut
                                      ? 'Moving '
                                      : 'Copying '}${_selection.value.where((item) => p.isDir(item)).isNotEmpty ? '${_selection.value.where((item) => p.isDir(item)).length} Folders ' : ''}"
                                  "${_selection.value.where((item) => !p.isDir(item)).isNotEmpty ? '${_selection.value.where((item) => !p.isDir(item)).length} Files ' : ''}",

                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              : _navIndex.value == 0 &&
                                    widget.onPick == null &&
                                    !_searching.value
                              ? Text(
                                  _dirCount.value > 0 || _fileCount.value > 0
                                      ? "${_dirCount.value > 0 ? '${_dirCount.value} Folders ' : ''}${_fileCount.value > 0 ? '${_fileCount.value} Files' : ''}"
                                      : "Empty",
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              : SizedBox.shrink(),
                      ],
                    ),
                    actions: [
                      Job.completedJobs.isNotEmpty && _navIndex.value == 1
                          ? IconButton(
                              onPressed: () {
                                Job.clearCompleted();
                              },
                              icon: Icon(Icons.clear_all_rounded),
                            )
                          : Job.jobs.isNotEmpty && _navIndex.value == 2
                          ? Job.runningJobs.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      Job.stopall();
                                    },
                                    icon: Icon(Icons.stop),
                                  )
                                : IconButton(
                                    onPressed: () {
                                      Job.continueAll();
                                    },
                                    icon: Icon(Icons.start),
                                  )
                          : SizedBox.shrink(),
                      // Select All
                      _navIndex.value == 0 &&
                              _selection.value.isNotEmpty &&
                              _selectionAction.value == SelectionAction.none &&
                              _selection.value.length <
                                  _allSelectableItems.length
                          ? IconButton(
                              onPressed: () {
                                _selection.value = {
                                  ..._selection.value,
                                  ..._allSelectableItems,
                                };
                              },
                              icon: const Icon(Icons.select_all),
                            )
                          : SizedBox.shrink(),
                      // Clear Selection
                      _navIndex.value == 0 &&
                              _selection.value.isNotEmpty &&
                              _selectionAction.value == SelectionAction.none
                          ? IconButton(
                              onPressed: () {
                                _selection.value = {};
                              },
                              icon: Icon(Icons.close),
                            )
                          : SizedBox.shrink(),
                      // Context Menu
                      _navIndex.value == 0 &&
                              _selection.value.isNotEmpty &&
                              _selectionAction.value == SelectionAction.none &&
                              widget.onFilesPick == null &&
                              !loading.value
                          ? IconButton(
                              onPressed: () async {
                                await Main.stopWatchers();
                                await _showContextMenu(null);
                              },
                              icon: Icon(Icons.more_vert),
                            )
                          : SizedBox.shrink(),
                      // Paste
                      _navIndex.value == 0 &&
                              _selection.value.isNotEmpty &&
                              _selectionAction.value != SelectionAction.none &&
                              !loading.value
                          ? IconButton(
                              onPressed: _paste(),
                              icon: const Icon(Icons.paste),
                            )
                          : SizedBox.shrink(),
                      // Clear Selection
                      _navIndex.value == 0 &&
                              _selection.value.isNotEmpty &&
                              _selectionAction.value != SelectionAction.none
                          ? IconButton(
                              onPressed: () {
                                _selectionAction.value = SelectionAction.none;
                              },
                              icon: const Icon(Icons.close),
                            )
                          : SizedBox.shrink(),
                      // Search
                      _navIndex.value == 0 &&
                              _selection.value.isEmpty &&
                              !loading.value &&
                              widget.onPick == null &&
                              (!_searching.value ||
                                  _searchController.text.trim().isNotEmpty)
                          ? IconButton(
                              icon: _searching.value
                                  ? Icon(Icons.backspace)
                                  : Icon(Icons.search),
                              onPressed: _searching.value
                                  ? () {
                                      _selection.value = {};
                                      _searchController.clear();
                                      _search();
                                    }
                                  : () async {
                                      _selection.value = {};
                                      _searching.value = true;
                                      _search();
                                    },
                            )
                          : SizedBox.shrink(),
                      // Exit Search
                      _navIndex.value == 0 &&
                              _selection.value.isEmpty &&
                              !loading.value &&
                              widget.onPick == null &&
                              _searching.value
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searching.value = false;
                                _selection.value = {};
                              },
                            )
                          : SizedBox.shrink(),
                      // More Options
                      (_selection.value.isEmpty ||
                                  widget.onFilesPick != null ||
                                  _selectionAction.value !=
                                      SelectionAction.none) &&
                              !_searching.value
                          ? IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () {
                                showMenu(
                                  context: context,
                                  position: RelativeRect.fromLTRB(
                                    1000,
                                    60,
                                    0,
                                    0,
                                  ),
                                  menuPadding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  color: Colors.transparent,
                                  items: [
                                    PopupMenuItem(
                                      padding: EdgeInsets.zero,
                                      enabled: false,
                                      child: _buildPopupMenu(context),
                                    ),
                                  ],
                                );
                              },
                            )
                          : SizedBox.shrink(),
                    ],
                    bottom: _navIndex.value == 0
                        ? PreferredSize(
                            preferredSize: Size.fromHeight(() {
                              double size = 0;
                              final bool showSummary =
                                  uiConfigNotifier.showDirectorySummary.value;
                              final bool showTitle = _driveDir.value != '';
                              final bool showBackupConfig =
                                  p.isAbsolute(
                                    Main.pathFromKey(_driveDir.value),
                                  ) &&
                                  uiConfigNotifier
                                      .showDirectoryBackupConfig
                                      .value;
                              final bool showError = !(_profile.value == null
                                  ? true
                                  : _profile.value?.accessible.value ?? false);
                              final bool showProgress =
                                  (_profile.value == null
                                      ? true
                                      : _profile.value?.accessible.value ??
                                            false) &&
                                  loading.value;
                              if (showSummary ||
                                  showTitle ||
                                  showBackupConfig) {
                                size += 12;
                              }
                              if (showSummary) {
                                size += 14;
                              }
                              if (showTitle) {
                                size += 20;
                              }
                              if (showBackupConfig) {
                                size += 14;
                              }
                              if (showError) {
                                size += 14;
                              }
                              if (showProgress) {
                                size += 4;
                              }
                              return size;
                            }()),
                            child: SizedBox(
                              width: double.infinity,
                              height: () {
                                double size = 0;
                                final bool showSummary =
                                    uiConfigNotifier.showDirectorySummary.value;
                                final bool showTitle = _driveDir.value != '';
                                final bool showBackupConfig =
                                    p.isAbsolute(
                                      Main.pathFromKey(_driveDir.value),
                                    ) &&
                                    uiConfigNotifier
                                        .showDirectoryBackupConfig
                                        .value;
                                final bool showError = !(_profile.value == null
                                    ? true
                                    : _profile.value?.accessible.value ??
                                          false);
                                final bool showProgress =
                                    (_profile.value == null
                                        ? true
                                        : _profile.value?.accessible.value ??
                                              false) &&
                                    loading.value;
                                if (showSummary ||
                                    showTitle ||
                                    showBackupConfig) {
                                  size += 12;
                                }
                                if (showSummary) {
                                  size += 14;
                                }
                                if (showTitle) {
                                  size += 20;
                                }
                                if (showBackupConfig) {
                                  size += 14;
                                }
                                if (showError) {
                                  size += 14;
                                }
                                if (showProgress) {
                                  size += 4;
                                }
                                return size;
                              }(),
                              child: child!,
                            ),
                          )
                        : null,
                  ),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      _driveDir,
                      _profile,
                      _profile.value?.accessible,
                      uiConfigNotifier.showDirectorySummary,
                      uiConfigNotifier.showDirectoryBackupConfig,
                      progress,
                      loading,
                    ]),
                    builder: (context, child) => Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (uiConfigNotifier.showDirectorySummary.value ||
                            _driveDir.value != '' ||
                            (p.isAbsolute(Main.pathFromKey(_driveDir.value)) &&
                                uiConfigNotifier
                                    .showDirectoryBackupConfig
                                    .value))
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
                                if (uiConfigNotifier.showDirectorySummary.value)
                                  child!,
                                if (_driveDir.value != '')
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: <Widget>[
                                        GestureDetector(
                                          onTap: () =>
                                              _changeDirectory(Main.root.key),
                                          child: Text(
                                            'FileS3',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyLarge,
                                          ),
                                        ),
                                        ...p.s3
                                            .split(_driveDir.value)
                                            .where((dir) => dir.isNotEmpty)
                                            .map(
                                              (dir) => Row(
                                                children: [
                                                  const Icon(
                                                    Icons.chevron_right,
                                                    size: 16,
                                                  ),
                                                  GestureDetector(
                                                    onTap: () {
                                                      String newPath = '';
                                                      for (final part
                                                          in p.s3.split(
                                                            _driveDir.value,
                                                          )) {
                                                        if (part.isEmpty) {
                                                          continue;
                                                        }
                                                        newPath += p.s3.asDir(
                                                          part,
                                                        );
                                                        if (part == dir) {
                                                          break;
                                                        }
                                                      }
                                                      _changeDirectory(newPath);
                                                    },
                                                    child: Text(
                                                      dir,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyLarge
                                                          ?.copyWith(
                                                            color:
                                                                p.s3.asDir(
                                                                      dir,
                                                                    ) ==
                                                                    p.s3.basename(
                                                                      _driveDir
                                                                          .value,
                                                                    )
                                                                ? Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary
                                                                : null,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                if (p.isAbsolute(
                                      Main.pathFromKey(_driveDir.value),
                                    ) &&
                                    uiConfigNotifier
                                        .showDirectoryBackupConfig
                                        .value)
                                  Row(
                                    children: [
                                      Text(
                                        '${Main.backupModeFromKey(_driveDir.value).name}: ',
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
                                              Main.pathFromKey(_driveDir.value),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelSmall,
                                            ),
                                            onTap: () {
                                              launchUrl(
                                                Uri.file(
                                                  Main.pathFromKey(
                                                    _driveDir.value,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        if (!(_profile.value == null
                            ? true
                            : _profile.value?.accessible.value ?? false))
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
                        if ((_profile.value == null
                                ? true
                                : _profile.value?.accessible.value ?? false) &&
                            loading.value)
                          LinearProgressIndicator(
                            value:
                                progress.value <= 0.0 || progress.value >= 1.0
                                ? null
                                : progress.value,
                          ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          _driveDir,
                          Main.onRemoteFilesChanged,
                        ]),
                        builder: (context, child) {
                          return InfoRow(
                            remoteKey: _driveDir.value,
                            uiConfig: UiConfig(
                              showTime: true,
                              showSize: true,
                              showDownloadStatus: true,
                              showContent: true,
                            ),
                            spacing: 6,
                            iconSize: 14,
                            textStyle: Theme.of(context).textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                ListFiles(
                  files: _currentProps,
                  groupOffsetMap: _groupOffsetMap,
                  keysOffsetMap: _keysOffsetMap,
                  listOptions: _listOptions,
                  relativeto: _driveDir,
                  selection: _selection,
                  selectionAction: _selectionAction,
                  showGallery: _pushGallery,
                  changeDirectory: _changeDirectory,
                  getSelectAction:
                      widget.onPick == null || widget.onFilesPick == null
                      ? _getSelectAction
                      : (String key) => () {},
                  showContextMenu:
                      widget.onPick == null && widget.onFilesPick == null
                      ? (key) async {
                          await Main.stopWatchers();
                          await _showContextMenu(key);
                        }
                      : null,
                  mimeTypes: _mimeTypes,
                  forceSelectionMode: widget.onFilesPick != null,
                ),
                ListenableBuilder(
                  listenable: _driveDir,
                  builder: (context, child) => SliverToBoxAdapter(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPress:
                          (widget.onPick == null ||
                                  widget.onFilesPick == null) &&
                              _driveDir.value.isNotEmpty
                          ? () async {
                              await Main.stopWatchers();
                              await _showContextMenu(_driveDir.value);
                            }
                          : null,
                      child: child,
                    ),
                  ),
                  child: SizedBox(height: 256, width: double.infinity),
                ),
              ],
            ),
          ),
        ),
        drawer: drawer(context),
        floatingActionButton: floatingActionButton(context),
        bottomNavigationBar: bottomNavigationBar(context),
      ),
    );
  }
}
