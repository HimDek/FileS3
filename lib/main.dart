import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/s3_file_manager.dart';
import 'directory_options.dart';
import 'sync_dir.dart';
import 'services/models/backup_mode.dart';

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
  late List<String> _dirs = <String>[];
  late Future<S3FileManager> _s3ManagerFuture;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late List<UploadJob> _jobs = <UploadJob>[];
  late Processor? _processor = null;
  bool _loading = true;

  Future<void> _listDirectories() async {
    setState(() {
      _loading = true;
    });
    final s3Manager = await _s3ManagerFuture;
    _dirs = await s3Manager.listDirectories();

    final List<String> localDirs = <String>[];
    final List<String> remoteDirs = <String>[];
    final List<BackupMode> modes = <BackupMode>[];

    for (final dir in _dirs) {
      final localDir = await _storage.read(key: dir);
      final modeValue = int.parse(await _storage.read(key: 'mode_$dir') ?? '1');
      if (localDir != null && localDir.isNotEmpty) {
        localDirs.add(localDir);
        remoteDirs.add(dir);
        modes.add(BackupMode.fromValue(modeValue));
      }
    }

    if (_processor != null) {
      _processor!.stop();
    }

    _processor = Processor(
      localDirs: localDirs.map((d) => Directory(d)).toList(),
      remoteDirs: remoteDirs,
      modes: modes,
      onStatus: (jobs) {
        setState(() {
          _jobs = jobs;
        });
      },
      s3Manager: s3Manager,
    );

    _processor!.start();

    setState(() {
      _loading = false;
    });
  }

  Future<void> _createDirectory(String dir) async {
    setState(() {
      _loading = true;
    });
    final s3Manager = await _s3ManagerFuture;
    await s3Manager.createDirectory(dir);
    _listDirectories();
  }

  Future<void> _deleteDirectory(String dir) async {
    setState(() {
      _loading = true;
    });
    final s3Manager = await _s3ManagerFuture;
    await s3Manager.deleteFile(dir);
    _listDirectories();
  }

  @override
  void initState() {
    super.initState();
    setState(() {
      _loading = true;
    });
    _s3ManagerFuture = S3FileManager.create(context);
    _listDirectories();
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
      body: ListView(
        children: _dirs
            .map(
              (dir) => ListTile(
                leading: Icon(Icons.folder),
                title: Text(dir.substring(0, dir.length - 1)),
                trailing: IconButton(
                  onPressed: () => {
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
                    ),
                  },
                  icon: const Icon(Icons.menu),
                ),
              ),
            )
            .toList(),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Directories: ${_dirs.length}'),
            TextButton(
              child: Text('Jobs: ${_jobs.length}'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: Text('Upload Jobs'),
                      content: SingleChildScrollView(
                        child: ListBody(
                          children: _jobs.map((job) {
                            return ListTile(
                              title: Text(job.remoteKey),
                              subtitle: Text(job.localFile.path),
                            );
                          }).toList(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Close'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
