import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:s3_drive/services/models/remote_file.dart';
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
      theme: ThemeData(primarySwatch: Colors.blue),
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
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final List<Job> _jobs = <Job>[];
  final List<Job> _completedJobs = <Job>[];
  final List<Watcher> _watchers = <Watcher>[];
  final Map<String, List<RemoteFile>> _remoteFilesMap =
      <String, List<RemoteFile>>{};
  bool _showActiveJobs = false;
  bool _showCompletedJobs = false;
  Processor? _processor;
  bool _loading = true;
  http.Client httpClient = http.Client();

  void onJobStatus(Job job) {
    setState(() {});
  }

  void onJobComplete(Job job, dynamic result) {
    if (job.runtimeType == UploadJob && result['eTag'] != null) {
      _remoteFilesMap['${job.remoteKey.split('/')[0]}/']!.add(
        RemoteFile(
          key: job.remoteKey,
          size: job.bytes,
          etag: result['eTag']!.substring(1, result['eTag']!.length - 1),
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

    _localDirs.clear();
    _backupModes.clear();
    for (final dir in _dirs) {
      final localDir = await _storage.read(key: dir);
      final modeValue = int.parse(await _storage.read(key: 'mode_$dir') ?? '1');
      _backupModes.add(BackupMode.fromValue(modeValue));
      if (localDir != null && localDir.isNotEmpty) {
        _localDirs.add(localDir);
      } else {
        _localDirs.add('');
      }
    }

    for (final watcher in _watchers) {
      watcher.stop();
    }

    for (final dir in _dirs) {
      final localDir = await _storage.read(key: dir);
      final modeValue = int.parse(await _storage.read(key: 'mode_$dir') ?? '1');

      await refreshRemote(dir);

      if (localDir != null && localDir.isNotEmpty) {
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
    S3FileManager.create(context, httpClient).then((manager) {
      _s3Manager = manager;
      _listDirectories();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_rounded),
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
                await _createDirectory(dir);
              }
            },
          ),
          IconButton(
            icon: _loading
                ? const CircularProgressIndicator()
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _listDirectories,
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          ListView(
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
                                  maxHeight: 600,
                                  maxWidth: 800,
                                ),
                                builder: (context) => DirectoryOptions(
                                  directory: dir,
                                  onDelete: _deleteDirectory,
                                ),
                              ).then((value) => _listDirectories());
                            },
                      icon: const Icon(Icons.menu),
                    ),
                  ),
                )
                .toList(),
          ),
          if (_showCompletedJobs)
            CompletedJobs(
              completedJobs: _completedJobs,
              processor: _processor!,
              onClose: () {
                _showCompletedJobs = false;
                setState(() {});
              },
              onUpdate: () {
                setState(() {});
              },
            ),
          if (_showActiveJobs)
            ActiveJobs(
              jobs: _jobs,
              processor: _processor!,
              onClose: () {
                _showActiveJobs = false;
                setState(() {});
              },
              onUpdate: () {
                setState(() {});
              },
              onJobComplete: onJobComplete,
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Directories: ${_dirs.length}'),
            Row(
              children: [
                IconButton(
                  icon: Badge.count(
                    count: _completedJobs.length,
                    child: Icon(Icons.done_all),
                  ),
                  onPressed: () {
                    _showCompletedJobs = !_showCompletedJobs;
                    setState(() {});
                  },
                ),
                IconButton(
                  icon: Badge.count(
                    count: _jobs.length,
                    child: Icon(Icons.swap_vert),
                  ),
                  onPressed: () {
                    _showActiveJobs = !_showActiveJobs;
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
