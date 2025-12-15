import 'dart:io';
import 'package:flutter/material.dart';
import 'package:s3_drive/directory_contents.dart';
import 'package:s3_drive/files_options.dart';
import 'package:s3_drive/services/ini_manager.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:s3_drive/settings.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'services/s3_file_manager.dart';
import 'directory_options.dart';
import 'services/job.dart';
import 'services/models/backup_mode.dart';
import 'package:http/http.dart' as http;
import 'active_jobs.dart';
import 'completed_jobs.dart';
import 'services/config_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'S3 Drive',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          showCloseIcon: true,
        ),
      ),
      home: const Scaffold(body: Home()),
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late S3FileManager _s3Manager;
  late List<String> _dirs = <String>[];
  final List<String> _localDirs = <String>[];
  final List<BackupMode> _backupModes = <BackupMode>[];
  final List<Job> _jobs = <Job>[];
  final List<Job> _completedJobs = <Job>[];
  final List<Watcher> _watchers = <Watcher>[];
  final Map<String, List<RemoteFile>> _remoteFilesMap =
      <String, List<RemoteFile>>{};
  final Set<(File, RemoteFile)> _selection = <(File, RemoteFile)>{};
  final GlobalKey<ScaffoldState> _drawerKey = GlobalKey<ScaffoldState>();
  int _navIndex = 0;
  String _localDir = './';
  String _localRoot = '';
  Processor? _processor;
  bool _loading = true;
  http.Client httpClient = http.Client();

  void selectFile((File, RemoteFile) filePair) {
    if (_selection.any((selected) =>
        selected.$1.path == filePair.$1.path &&
        selected.$2.key == filePair.$2.key)) {
      _selection.removeWhere((selected) =>
          selected.$1.path == filePair.$1.path &&
          selected.$2.key == filePair.$2.key);
    } else {
      _selection.add(filePair);
    }
    setState(() {});
  }

  void onJobStatus(Job job) {
    setState(() {});
  }

  void onJobComplete(Job job, dynamic result) {
    if (job.runtimeType == UploadJob &&
        result != null &&
        result['etag'] != null) {
      _remoteFilesMap['${job.remoteKey.split('/').first}/']!.add(
        RemoteFile(
          key: job.remoteKey,
          size: job.bytes,
          etag: result['etag']!.substring(1, result['etag']!.length - 1),
          lastModified: job.localFile.lastModifiedSync(),
        ),
      );
    }
    _completedJobs.add(job);
    _jobs.remove(job);
    startProcessor();
    setState(() {});
  }

  void startProcessor() async {
    _processor ??= Processor(
      cfg: await ConfigManager.loadS3Config(context),
      jobs: _jobs,
      onJobComplete: onJobComplete,
    );
    _processor!.start();
  }

  Future<void> refreshRemote(String dir) async {
    final remoteFiles = await _s3Manager.listObjects(dir: dir);
    _remoteFilesMap[dir] = remoteFiles;
  }

  Future<void> _listDirectories() async {
    setState(() {
      _loading = true;
    });
    _dirs = await _s3Manager.listDirectories();

    for (final watcher in _watchers) {
      watcher.stop();
    }

    _watchers.clear();

    _localDirs.clear();
    _backupModes.clear();

    for (final dir in _dirs) {
      final localDir = IniManager.config.get('directories', dir);
      final modeValue = int.parse(IniManager.config.get('modes', dir) ?? '1');

      _backupModes.add(BackupMode.fromValue(modeValue));
      if (localDir != null &&
          localDir.isNotEmpty &&
          Directory(localDir).existsSync()) {
        _localDirs.add(localDir);
      } else {
        _localDirs.add('');
      }

      await refreshRemote(dir);

      if (localDir != null &&
          localDir.isNotEmpty &&
          Directory(localDir).existsSync()) {
        _watchers.add(
          Watcher(
            localDir: Directory(localDir),
            remoteDir: dir,
            mode: BackupMode.fromValue(modeValue),
            s3Manager: _s3Manager,
            jobs: _jobs,
            remoteFiles: _remoteFilesMap[dir] ?? [],
            remoteRefresh: () => refreshRemote(dir),
            onNewJobs: () {
              setState(() {});
              startProcessor();
            },
            onJobStatus: onJobStatus,
          ),
        );
      }
    }

    for (final watcher in _watchers) {
      watcher.start();
    }

    startProcessor();

    setState(() {
      _loading = false;
    });
  }

  Future<void> _createDirectory(String dir) async {
    setState(() {
      _loading = true;
    });
    await _s3Manager.createDirectory(dir);
    _listDirectories();
  }

  Future<void> _deleteDirectory(String dir) async {
    setState(() {
      _loading = true;
    });
    await _s3Manager.deleteFile(dir);
    _listDirectories();
  }

  @override
  void initState() {
    super.initState();
    setState(() {
      _loading = true;
    });
    IniManager.init();
    S3FileManager.create(context, httpClient).then((manager) {
      _s3Manager = manager;
      _listDirectories();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _navIndex == 1
            ? const Text("Completed Jobs")
            : _navIndex == 2
                ? const Text("Active Jobs")
                : _localDir == "./"
                    ? const Text('S3 Drive/')
                    : _selection.isNotEmpty
                        ? Text("${_selection.length} selected")
                        : Row(
                            children: "S3 Drive/$_localDir"
                                .split('/')
                                .where((dir) => dir.isNotEmpty)
                                .map(
                                  (dir) => GestureDetector(
                                    onTap: dir == "S3 Drive"
                                        ? () {
                                            setState(() {
                                              _localDir = './';
                                            });
                                          }
                                        : () {
                                            String newPath = './';
                                            for (final part
                                                in _localDir.split('/')) {
                                              if (part.isEmpty) continue;
                                              newPath += '$part/';
                                              if (part == dir) break;
                                            }
                                            setState(() {
                                              _localDir =
                                                  "${p.normalize(newPath)}/";
                                              _localRoot = _dirs.contains(
                                                      "${p.normalize(newPath)}/")
                                                  ? _localDirs[_dirs.indexOf(
                                                      "${p.normalize(newPath)}/",
                                                    )]
                                                  : _localRoot;
                                            });
                                          },
                                    child: Text("$dir/"),
                                  ),
                                )
                                .toList(),
                          ),
        actions: _navIndex == 1
            ? [
                if (_completedJobs.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _completedJobs.clear();
                      setState(() {});
                    },
                    icon: Icon(Icons.delete_sweep),
                  ),
              ]
            : _navIndex == 2
                ? [
                    if (_jobs.isNotEmpty)
                      _jobs.any((job) => job.running)
                          ? IconButton(
                              onPressed: () {
                                _processor!.stopall();
                                setState(() {});
                              },
                              icon: Icon(Icons.stop),
                            )
                          : IconButton(
                              onPressed: () {
                                _processor!.start();
                                setState(() {});
                              },
                              icon: Icon(Icons.start),
                            ),
                  ]
                : _loading
                    ? [
                        const CircularProgressIndicator(),
                      ]
                    : _selection.isNotEmpty
                        ? [
                            IconButton(
                                onPressed: () => showModalBottomSheet(
                                      context: context,
                                      enableDrag: true,
                                      showDragHandle: true,
                                      constraints: const BoxConstraints(
                                        maxHeight: 800,
                                        maxWidth: 800,
                                      ),
                                      builder: (context) => FilesOptions(
                                        files: _selection.toList(),
                                        jobs: _jobs,
                                        localRoot: _localRoot,
                                        processor: _processor!,
                                        deleteFile: (key, path) {
                                          _s3Manager.deleteFile(key);
                                          if (File(path).existsSync()) {
                                            File(path).deleteSync();
                                          }
                                          setState(() {});
                                        },
                                        onJobStatus: onJobStatus,
                                        startProcessor: startProcessor,
                                      ),
                                    ).then((value) => _listDirectories()),
                                icon: Icon(Icons.more_vert))
                          ]
                        : [
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _loading ? null : _listDirectories,
                            ),
                          ],
      ),
      drawer: Drawer(
        key: _drawerKey,
        child: ListView(
          children: [
            Padding(
              padding: EdgeInsetsGeometry.all(16),
              child: Text(
                'S3 Drive',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Settings'),
              onTap: () {
                _drawerKey.currentState?.closeDrawer();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => SettingsPage(),
                ));
              },
            ),
          ],
        ),
      ),
      body: _localDir == './' && _navIndex == 0
          ? ListView(
              children: _dirs
                  .map(
                    (dir) => ListTile(
                      leading: Icon(Icons.folder),
                      title: Text(dir.substring(0, dir.length - 1)),
                      subtitle: Text(
                        '${_backupModes[_dirs.indexOf(dir)].name}: ${_localDirs[_dirs.indexOf(dir)]}',
                      ),
                      trailing: IconButton(
                        onPressed: _loading
                            ? null
                            : () {
                                showModalBottomSheet(
                                  context: context,
                                  enableDrag: true,
                                  showDragHandle: true,
                                  constraints: const BoxConstraints(
                                    maxHeight: 800,
                                    maxWidth: 800,
                                  ),
                                  builder: (context) => DirectoryOptions(
                                    directory: dir,
                                    onDelete: _deleteDirectory,
                                    remoteFiles: _remoteFilesMap[dir] ?? [],
                                  ),
                                ).then((value) => _listDirectories());
                              },
                        icon: const Icon(Icons.menu),
                      ),
                      onTap: () {
                        setState(() {
                          _localDir = dir;
                          _localRoot = _dirs.contains(dir)
                              ? _localDirs[_dirs.indexOf(dir)]
                              : _localRoot;
                        });
                      },
                    ),
                  )
                  .toList(),
            )
          : _localDir != './' && _navIndex == 0
              ? DirectoryContents(
                  directory: _localDir,
                  localRoot: _localRoot,
                  jobs: _jobs,
                  processor: _processor!,
                  remoteFilesMap: _remoteFilesMap,
                  selection: _selection,
                  selectFile: selectFile,
                  onJobStatus: onJobStatus,
                  onJobComplete: onJobComplete,
                  onChangeDirectory: (String newDir) {
                    setState(() {
                      _localDir = newDir;
                      _localRoot = _dirs.contains(newDir)
                          ? _localDirs[_dirs.indexOf(newDir)]
                          : _localRoot;
                    });
                  },
                  deleteFile: (key, path) {
                    _s3Manager.deleteFile(key);
                    if (File(path).existsSync()) File(path).deleteSync();
                    setState(() {});
                  },
                  listDirectories: _listDirectories,
                  startProcessor: startProcessor,
                )
              : _navIndex == 1
                  ? CompletedJobs(
                      completedJobs: _completedJobs,
                      processor: _processor!,
                      onUpdate: () {
                        setState(() {});
                      },
                    )
                  : ActiveJobs(
                      jobs: _jobs,
                      processor: _processor!,
                      onUpdate: () {
                        setState(() {});
                      },
                      onJobComplete: onJobComplete,
                    ),
      floatingActionButton: _navIndex == 0 && !_loading && _selection.isEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_localDir != './')
                  FloatingActionButton(
                    child: const Icon(Icons.file_upload_outlined),
                    onPressed: () async {
                      final XFile? file = await openFile();
                      if (file != null) {
                        if (!Directory(p.join(_localRoot,
                                _localDir.split('/').sublist(1).join('/')))
                            .existsSync()) {
                          Directory(p.join(_localRoot,
                                  _localDir.split('/').sublist(1).join('/')))
                              .createSync(recursive: true);
                        }
                        if (!File(p.normalize(p.join(
                                _localRoot,
                                _localDir.split('/').sublist(1).join('/'),
                                file.name)))
                            .existsSync()) {
                          await file.saveTo(p.normalize(p.join(
                              _localRoot,
                              _localDir.split('/').sublist(1).join('/'),
                              file.name)));
                          _listDirectories();
                        } else {
                          final newname = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              String newName = '';
                              return AlertDialog(
                                title: const Text('File Already Exists'),
                                content: TextField(
                                  decoration: const InputDecoration(
                                    labelText: 'New File Name',
                                  ),
                                  onChanged: (value) => newName = value,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(null),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(newName),
                                    child: const Text('Rename'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (newname != null && newname.isNotEmpty) {
                            await file.saveTo(p.normalize(p.join(
                                _localRoot,
                                _localDir.split('/').sublist(1).join('/'),
                                newname)));
                            _listDirectories();
                          }
                        }
                      }
                    },
                  ),
                SizedBox(height: 16),
                FloatingActionButton(
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
                              onPressed: () =>
                                  Navigator.of(context).pop(newDir),
                              child: const Text('Create'),
                            ),
                          ],
                        );
                      },
                    );
                    if (dir != null && dir.isNotEmpty) {
                      await _createDirectory(
                          p.normalize(p.join(_localDir, dir)));
                    }
                  },
                ),
              ],
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: 'Directories',
          ),
          BottomNavigationBarItem(
            icon: Badge.count(
              count: _completedJobs.length,
              child: Icon(Icons.done_all),
            ),
            label: 'Completed',
          ),
          BottomNavigationBarItem(
            icon: Badge.count(
              count: _jobs.length,
              child: Icon(Icons.swap_vert),
            ),
            label: 'Active',
          ),
        ],
        currentIndex: _navIndex,
        onTap: (index) {
          _navIndex = index;
          setState(() {});
        },
      ),
    );
  }
}
