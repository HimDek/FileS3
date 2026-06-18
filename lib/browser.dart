import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:files3/info_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:m3e_card_list/m3e_card_list.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_selector/file_selector.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/context_menu.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/scrollbar.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
import 'package:files3/models.dart';
import 'package:files3/helpers.dart';
import 'package:files3/settings.dart';
import 'package:files3/media_view.dart';
import 'package:files3/list_files.dart';
import 'package:files3/pointer_pill.dart';

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
    return MyListenableBuilder(
      name: 'path_picker_fab',
      listenable: Listenable.merge([
        loading,
        _controlsVisible,
        _driveDir,
        _profile,
        _profile.value?.accessible,
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
                    _profile.value!.accessible.value
                ? Offset.zero
                : const Offset(2, 0),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale:
                  !loading.value &&
                      _controlsVisible.value &&
                      _profile.value != null &&
                      _profile.value!.accessible.value
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
    required super.copyFile,
    required super.copyDirectory,
    required super.moveFiles,
    required super.moveDirectories,
    required super.deleteLocal,
    required super.deleteFiles,
    required super.deleteCache,
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
    return MyListenableBuilder(
      name: 'my_browser_fab',
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
                      p.join(_driveDir.value.key, p.basename(file.path)),
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
                      p.join(_driveDir.value.key, p.basename(directoryPath)),
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
                    if (Main.remoteFiles.any(
                      (file) => [
                        p.join(_driveDir.value.key, dir),
                        p.asDir(p.join(_driveDir.value.key, dir)),
                      ].contains(file.key),
                    )) {
                      showSnackBar(
                        SnackBar(
                          content: Text(
                            '"${p.join(_driveDir.value.key, dir)}" already exists.',
                          ),
                        ),
                      );
                      return;
                    }
                    await widget.createDirectory?.call(
                      p.join(_driveDir.value.key, dir),
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

  @override
  Widget drawer(BuildContext context) {
    return MyListenableBuilder(
      name: 'my_browser_drawer',
      listenable: Listenable.merge([_navIndex, Job.jobs, Job.onProgressUpdate]),
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
              trailing: Job.activeJobs.isNotEmpty
                  ? Text(Job.activeJobs.length.toString())
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
              color: _navIndex.value == 0 && _driveDir.value.key == ''
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              borderRadius: BorderRadius.circular(32),
            ),
            margin: EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              title: Text('Home'),
              leading: Icon(
                _navIndex.value == 0 && _driveDir.value.key == ''
                    ? Icons.home
                    : Icons.home_outlined,
              ),
              selected: _navIndex.value == 0 && _driveDir.value.key == '',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _navIndex.value = 0;
                _controlsVisible.value = true;
                _driveDir.value = BrowserState.root;
              },
            ),
          ),
          for (final pinned in ConfigManager.loadPinnedFolders())
            Container(
              decoration: BoxDecoration(
                color:
                    _navIndex.value == 0 && _driveDir.value.key == pinned.value
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
                  _navIndex.value == 0 && _driveDir.value.key == pinned.value
                      ? Icons.folder
                      : Icons.folder_outlined,
                ),
                selected:
                    _navIndex.value == 0 && _driveDir.value.key == pinned.value,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _navIndex.value = 0;
                  _controlsVisible.value = true;
                  _driveDir.value = Main.remoteFiles.firstWhere(
                    (file) => file.key == pinned.value,
                    orElse: () => RemoteFile(key: pinned.value, etag: ''),
                  );
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
}

class Browser extends StatefulWidget {
  final Widget title;
  final Widget? subtitle;
  final Function()? onInit;
  final RemoteFile? initialDir;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
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
  final Function(String)? deleteCache;
  final Future<void> Function(List<String>, {bool refresh})? deleteFiles;
  final Future<void> Function(List<String>, {bool refresh})? deleteDirectories;
  final Future<void> Function(String)? createDirectory;
  final void Function(String, Directory)? uploadDirectory;
  final Function(RemoteFile)? onPick;

  const Browser({
    super.key,
    this.title = const Text('Select Path'),
    this.subtitle,
    this.initialDir,
    this.onInit,
    this.drawer,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.downloadFile,
    this.downloadDirectory,
    this.saveFile,
    this.saveDirectory,
    this.copyFile,
    this.copyDirectory,
    this.moveFiles,
    this.moveDirectories,
    this.deleteLocal,
    this.deleteCache,
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
  static RemoteFile root = RemoteFile(key: '', etag: '');

  final List<RemoteFile> _allSelectableItems = <RemoteFile>[];
  final List<GalleryProps> _galleryFiles = <GalleryProps>[];
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
  final ValueNotifier<RemoteFile> _driveDir = ValueNotifier(BrowserState.root);
  final ValueNotifier<ListOptions> _listOptions = ValueNotifier(ListOptions());
  final ValueNotifier<SelectionAction> _selectionAction = ValueNotifier(
    SelectionAction.none,
  );
  final ValueNotifier<Set<RemoteFile>> _selection = ValueNotifier({});
  final ValueNotifier<List<Object>> _searchResults = ValueNotifier([]);
  final ValueNotifier<List> _currentItems = ValueNotifier<List>([]);
  final ValueNotifier<List<FileProps>> _currentProps = ValueNotifier([]);
  final ValueNotifier<Map<String, double>> _keysOffsetMap = ValueNotifier({});
  final ManualNotifier _rebuildContext = ManualNotifier();

  late Listenable _currentItemsNotifiers;

  Timer? _scrollbarTimer;
  Timer? _inaccessibleTimer;

  double _lastScrollOffset = 0;

  Future<void> _updateCounts() async {
    _dirCount.value = 0;
    _fileCount.value = 0;

    final counts = await _driveDir.value.getCount(recursive: false);
    _dirCount.value = counts.$1;
    _fileCount.value = counts.$2;
    if (_driveDir.value.key == '') {
      _fileCount.value = 0;
    }
  }

  Future<void> _setGalleryFiles(List<GalleryProps> files) async {
    _galleryFiles.clear();
    _galleryFiles.addAll(files);
  }

  void Function()? _getSelectAction(RemoteFile item) =>
      _selection.value.any((selected) => p.isWithin(selected.key, item.key)) ||
          _selectionAction.value != SelectionAction.none
      ? null
      : () {
          if (p.isDir(item.key)) {
            // Deselect all children
            _selection.value = _selection.value
                .where((selected) => !p.isWithin(item.key, selected.key))
                .toSet();
          }
          if (_selection.value.any((selected) {
            return selected.key == item.key;
          })) {
            _selection.value = _selection.value
                .where((selected) => selected.key != item.key)
                .toSet();
          } else {
            _selection.value = {..._selection.value, item};
          }
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
          keysOffsetMap: _keysOffsetMap.value,
          scrollController: _scrollController,
          buildContextMenu: _buildContextMenu,
          rebuildContext: _rebuildContext.notifyListeners,
        ),
      ),
    );
    return result;
  }

  void _scrollToFile(RemoteFile file) {
    final offset = _keysOffsetMap.value[file.key];
    if (offset == null) return;

    _scrollController.jumpTo(
      max(0, offset - MediaQuery.of(context).size.height / 3),
    );
  }

  void _changeDirectory(RemoteFile dir) {
    final oldDir = _driveDir.value;
    _navIndex.value = 0;
    _controlsVisible.value = true;
    String ndir = dir.key;
    for (RemoteFile item in _selection.value) {
      if (p.isWithin(item.key, dir.key) || item.key == dir.key) {
        dir = () {
          while (p.isWithin(item.key, ndir) || item.key == ndir) {
            ndir = p.s3(p.dirname(ndir));
            if (ndir == '') {
              break;
            }
          }
          return Main.remoteFiles.firstWhere((file) => file.key == ndir);
        }();
      }
    }
    _driveDir.value = ndir.isEmpty ? BrowserState.root : dir;
    _profile.value = Main.profileFromKey(_driveDir.value.key);
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
    }).toList();
    if (!_searching.value) {
      _currentProps.value = sort(
        _currentItems.value.map((file) {
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
  }

  void _setCurrentItems() {
    if (kDebugMode) {
      debugPrint('Refreshing current items set...');
    }
    _currentItems.value = _searching.value && _navIndex.value == 0
        ? _searchResults.value
        : _driveDir.value.key == '' && _navIndex.value == 0
        ? Set<RemoteFile>.from(
            Main.remoteFiles
                .where(
                  (file) =>
                      p.s3(p.dirname(file.key)).isEmpty && p.isDir(file.key),
                )
                .map<RemoteFile>((file) => file),
          ).toList()
        : _driveDir.value.key != '' && _navIndex.value == 0
        ? [
            ...Main.remoteFiles.where(
              (file) =>
                  p.s3(p.dirname(file.key)) == p.s3(_driveDir.value.key) &&
                  !Job.activeJobs.any((job) => job.remoteKey == file.key),
            ),
            ...Job.activeJobs.where(
              (job) =>
                  p.s3(p.dirname(job.remoteKey)) == p.s3(_driveDir.value.key),
            ),
          ]
        : _navIndex.value == 1
        ? Job.completedJobs.toList()
        : _navIndex.value == 2
        ? Job.activeJobs.toList()
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
        ...Main.remoteFiles.where(
          (file) =>
              p.isWithin(p.s3(_driveDir.value.key), p.s3(file.key)) &&
              !Job.activeJobs.any((job) => job.remoteKey == file.key),
        ),
        ...Job.activeJobs.where(
          (job) => p.isWithin(p.s3(_driveDir.value.key), p.s3(job.remoteKey)),
        ),
      ],
      cutoff: 40,
      getter: (item) {
        String key = item is Job ? item.remoteKey : (item as RemoteFile).key;
        return p.s3(key).toLowerCase();
      },
    ).map((result) => result.choice).toList();

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
          : _driveDir.value.key,
      options.toJson(),
    );
    if (_globalListOptions.value &&
        IniManager.config.value
                ?.options('list_options')
                ?.contains(_driveDir.value.key) ==
            true) {
      IniManager.config.value?.removeOption(
        'list_options',
        _driveDir.value.key,
      );
    }
    IniManager.save();
  }

  void _fetchListOptions() {
    if (IniManager.config.value?.get('list_options', _driveDir.value.key) !=
        null) {
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
                      : _driveDir.value.key,
                ) ??
                ListOptions().toJson(),
          );
  }

  void _cut(RemoteFile? item) {
    if (item != null) {
      _selection.value = {..._selection.value, item};
    }
    _selectionAction.value = SelectionAction.cut;
  }

  void _copy(RemoteFile? item) {
    if (item != null) {
      _selection.value = {..._selection.value, item};
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
            final selection = _selection.value.toList();
            if (_selectionAction.value == SelectionAction.copy) {
              final items = selection.where(
                (item) =>
                    p.s3(p.dirname(item.key)) != p.s3(_driveDir.value.key),
              );
              int progressCount = 0;
              final totalItems = items.length;

              for (final item in items) {
                progressCount += 1;
                progress.value = progressCount / totalItems;
                final newKey = p.join(
                  _driveDir.value.key,
                  p.basename(item.key),
                );
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
                        p.s3(p.dirname(item.key)) != p.s3(_driveDir.value.key),
                  )
                  .toList();
              final files = selection
                  .where(
                    (item) =>
                        !p.isDir(item.key) &&
                        p.s3(p.dirname(item.key)) != p.s3(_driveDir.value.key),
                  )
                  .toList();
              final dirsDestinations = dirs
                  .map(
                    (item) => p.join(_driveDir.value.key, p.basename(item.key)),
                  )
                  .toList();
              final filesDestinations = files
                  .map(
                    (item) => p.join(_driveDir.value.key, p.basename(item.key)),
                  )
                  .toList();
              widget.moveDirectories?.call(
                dirs.map((item) => item.key).toList(),
                dirsDestinations,
              );
              widget.moveFiles?.call(
                files.map((item) => item.key).toList(),
                filesDestinations,
              );
              _selection.value = {};
            }
            _selectionAction.value = SelectionAction.none;
          } catch (e) {
            showSnackBar(SnackBar(content: Text('Error pasting items: $e')));
          }
        };

  Widget _buildContextMenu(BuildContext context, RemoteFile? file) {
    return MyListenableBuilder(
      name: 'browser_context_menu',
      listenable: Listenable.merge([
        loading,
        _rebuildContext,
        Job.onProgressUpdate,
      ]),
      builder: (context, _) => SingleChildScrollView(
        child: file == null
            ? buildBulkContextMenu(
                context,
                _selection.value.toList(),
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
                    : (dirs, newDirs) async => await widget.moveDirectories
                          ?.call(dirs, newDirs, refresh: true),
                loading.value ? null : _cut,
                loading.value ? null : _copy,
                loading.value ? null : widget.deleteLocal,
                loading.value ? null : widget.deleteCache,
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
                  _selection.value = {};
                },
                () {
                  _rebuildContext.notifyListeners();
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
                loading.value ? null : widget.deleteCache,
                loading.value
                    ? null
                    : (List<String> dirs) async => await widget
                          .deleteDirectories
                          ?.call(dirs, refresh: true),
                () {
                  _rebuildContext.notifyListeners();
                },
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
                loading.value ? null : widget.deleteCache,
                loading.value
                    ? null
                    : (List<String> keys) async =>
                          await widget.deleteFiles?.call(keys, refresh: true),
                () {
                  _rebuildContext.notifyListeners();
                },
              ),
      ),
    );
  }

  Future<void> _showContextMenu(RemoteFile? file) async {
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
  }

  Widget _buildPopupMenu(BuildContext context) {
    return MyListenableBuilder(
      name: 'browser_popup_menu',
      listenable: Listenable.merge([
        loading,
        _searching,
        _listOptions,
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
              SizedBox(height: 0, width: 160),
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
    _changeDirectory(widget.initialDir ?? BrowserState.root);

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

    _currentItemsNotifiers = Listenable.merge([
      _navIndex,
      _driveDir,
      _searching,
      _searchResults,
      Main.onRemoteFilesChanged,
      Job.jobs,
      Job.onProgressUpdate,
    ]);

    _currentItemsNotifiers.addListener(_setCurrentItems);

    Listenable.merge([
      _navIndex,
      _driveDir,
      _searching,
    ]).addListener(_fetchListOptions);

    _currentItems.addListener(
      () => _updateAllSelectableItems(
        _currentItems.value.whereType<RemoteFile>().toList(),
      ),
    );

    Listenable.merge([
      _currentItems,
      _listOptions,
    ]).addListener(_applyListOptions);

    Main.onRemoteFilesChanged.addListener(_updateCounts);

    if (IniManager.config.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        IniManager.config.addListener(() {
          if (IniManager.config.value != null) {
            _fetchListOptions();
          }
        });
        if (!loading.value) {
          _setCurrentItems();
          _applyListOptions();
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchListOptions();
        if (!loading.value) {
          _setCurrentItems();
          _applyListOptions();
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
    return widget.drawer;
  }

  Widget? floatingActionButton(BuildContext context) {
    return widget.floatingActionButton;
  }

  Widget? bottomNavigationBar(BuildContext context) {
    return widget.bottomNavigationBar;
  }

  @override
  Widget build(BuildContext context) {
    return MyListenableBuilder(
      name: 'browser_pop_scope',
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
            _driveDir.value.key.isEmpty &&
            !_searching.value &&
            _selection.value.isEmpty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) {
            return;
          }
          if (_selectionAction.value != SelectionAction.none) {
            _selectionAction.value = SelectionAction.none;
            return;
          }
          if (_selection.value.isNotEmpty) {
            _selection.value = {};
            return;
          }
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
          if (_driveDir.value.key.isNotEmpty) {
            final newKey = p.s3(p.dirname(_driveDir.value.key));
            _changeDirectory(RemoteFile(key: newKey, etag: ''));
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
                MyListenableBuilder(
                  name: 'browser_app_bar',
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
                    Job.jobs,
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
                              isLabelVisible: Job.jobs.value.isNotEmpty,
                              label: Job.activeJobs.isNotEmpty
                                  ? Text(
                                      Job.activeJobs.length.toString(),
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
                                      ? "${_searchResults.value.where((item) => item is RemoteFile && p.isDir(item.key)).isNotEmpty ? '${_searchResults.value.where((item) => item is RemoteFile && p.isDir(item.key)).length} Folders ' : ''}${_searchResults.value.where((item) => item is RemoteFile && !p.isDir(item.key)).isNotEmpty ? '${_searchResults.value.where((item) => item is RemoteFile && !p.isDir(item.key)).length} Files ' : ''}found"
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
                                      : 'Copying '}${_selection.value.where((item) => p.isDir(item.key)).isNotEmpty ? '${_selection.value.where((item) => p.isDir(item.key)).length} Folders ' : ''}${_selection.value.where((item) => !p.isDir(item.key)).isNotEmpty ? '${_selection.value.where((item) => !p.isDir(item.key)).length} Files ' : ''}",

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
                          : Job.activeJobs.isNotEmpty && _navIndex.value == 2
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
                      _selection.value.isEmpty && !_searching.value
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
                              final bool showTitle = _driveDir.value.key != '';
                              final bool showBackupConfig =
                                  Main.pathFromKey(_driveDir.value.key) !=
                                      null &&
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
                                final bool showTitle =
                                    _driveDir.value.key != '';
                                final bool showBackupConfig =
                                    Main.pathFromKey(_driveDir.value.key) !=
                                        null &&
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
                              child: Column(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (uiConfigNotifier
                                          .showDirectorySummary
                                          .value ||
                                      _driveDir.value.key != '' ||
                                      (Main.pathFromKey(_driveDir.value.key) !=
                                              null &&
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (uiConfigNotifier
                                              .showDirectorySummary
                                              .value)
                                            SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: InfoRow(
                                                file: _driveDir.value,
                                                uiConfig: UiConfig(
                                                  showTime: true,
                                                  showSize: true,
                                                  showDownloadStatus: true,
                                                  showContent: true,
                                                ),
                                                spacing: 6,
                                                iconSize: 14,
                                                textStyle: Theme.of(
                                                  context,
                                                ).textTheme.labelSmall,
                                              ),
                                            ),
                                          if (_driveDir.value.key != '')
                                            SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Row(
                                                children:
                                                    <Widget>[
                                                          GestureDetector(
                                                            onTap: () =>
                                                                _changeDirectory(
                                                                  BrowserState
                                                                      .root,
                                                                ),
                                                            child: Text(
                                                              'FileS3',
                                                              style:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .textTheme
                                                                      .bodyLarge,
                                                            ),
                                                          ),
                                                        ]
                                                        .followedBy(
                                                          p
                                                              .split(
                                                                _driveDir
                                                                    .value
                                                                    .key,
                                                              )
                                                              .where(
                                                                (dir) => dir
                                                                    .isNotEmpty,
                                                              )
                                                              .map(
                                                                (
                                                                  dir,
                                                                ) => GestureDetector(
                                                                  onTap: () {
                                                                    String
                                                                    newPath =
                                                                        '';
                                                                    for (final part in p.split(
                                                                      _driveDir
                                                                          .value
                                                                          .key,
                                                                    )) {
                                                                      if (part
                                                                          .isEmpty) {
                                                                        continue;
                                                                      }
                                                                      newPath +=
                                                                          p.asDir(
                                                                            part,
                                                                          );
                                                                      if (part ==
                                                                          dir) {
                                                                        break;
                                                                      }
                                                                    }
                                                                    _changeDirectory(
                                                                      Main.remoteFiles.firstWhere(
                                                                        (
                                                                          file,
                                                                        ) =>
                                                                            p.s3(
                                                                              file.key,
                                                                            ) ==
                                                                            p.s3(
                                                                              newPath,
                                                                            ),
                                                                      ),
                                                                    );
                                                                  },
                                                                  child: Text(
                                                                    dir,
                                                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                                      color:
                                                                          p.asDir(
                                                                                dir,
                                                                              ) ==
                                                                              p.basename(
                                                                                _driveDir.value.key,
                                                                              )
                                                                          ? Theme.of(
                                                                              context,
                                                                            ).colorScheme.primary
                                                                          : null,
                                                                    ),
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
                                          if (Main.pathFromKey(
                                                    _driveDir.value.key,
                                                  ) !=
                                                  null &&
                                              uiConfigNotifier
                                                  .showDirectoryBackupConfig
                                                  .value)
                                            Row(
                                              children: [
                                                Text(
                                                  '${Main.backupModeFromKey(_driveDir.value.key).name}: ',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.labelSmall,
                                                ),
                                                SizedBox(width: 4),
                                                Expanded(
                                                  child: SingleChildScrollView(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: GestureDetector(
                                                      child: Text(
                                                        Main.pathFromKey(
                                                              _driveDir
                                                                  .value
                                                                  .key,
                                                            ) ??
                                                            '',
                                                        style: Theme.of(
                                                          context,
                                                        ).textTheme.labelSmall,
                                                      ),
                                                      onTap: () {
                                                        launchUrl(
                                                          Uri.file(
                                                            Main.pathFromKey(
                                                                  _driveDir
                                                                      .value
                                                                      .key,
                                                                ) ??
                                                                _driveDir
                                                                    .value
                                                                    .key,
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
                                      : _profile.value?.accessible.value ??
                                            false))
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
                                  if ((_profile.value == null
                                          ? true
                                          : _profile.value?.accessible.value ??
                                                false) &&
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
                ),
                ListFiles(
                  files: _currentProps,
                  galleryFiles: _galleryFiles,
                  setGalleryFiles: _setGalleryFiles,
                  groupOffsetMap: _groupOffsetMap,
                  keysOffsetMap: _keysOffsetMap,
                  listOptions: _listOptions,
                  relativeto: _driveDir,
                  selection: _selection,
                  selectionAction: _selectionAction,
                  showGallery: _pushGallery,
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
                ),
                ListenableBuilder(
                  listenable: _driveDir,
                  builder: (context, child) => SliverToBoxAdapter(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPress:
                          widget.onPick == null &&
                              _driveDir.value.key.isNotEmpty
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
