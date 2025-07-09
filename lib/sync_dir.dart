import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'services/s3_file_manager.dart';
import 'services/models/backup_mode.dart';
import 'services/sync_analyzer.dart';

class UploadJob {
  final File localFile;
  final String remoteKey;
  bool completed;
  UploadJob({
    required this.localFile,
    required this.remoteKey,
    this.completed = false,
  });
}

typedef UploadStatusCallback = void Function(List<UploadJob> jobs);

class Processor {
  final List<Directory> localDirs;
  final List<String> remoteDirs;
  final List<BackupMode> modes;
  final UploadStatusCallback onStatus;
  final S3FileManager s3Manager;
  final List<StreamSubscription<FileSystemEvent>> _subscriptions = [];
  final Map<String, UploadJob> _jobMap = {};

  Processor({
    required this.localDirs,
    required this.remoteDirs,
    required this.modes,
    required this.onStatus,
    required this.s3Manager,
  });

  Future<void> start() async {
    await _initialScan();

    for (int i = 0; i < localDirs.length; i++) {
      final dir = localDirs[i];
      final mode = modes[i];
      final remoteBase = remoteDirs[i];
      final subscription = dir.watch(recursive: true).listen((event) async {
        final file = File(event.path);
        if (await file.exists()) {
          if (mode == BackupMode.sync || mode == BackupMode.upload) {
            await _handleFile(file, dir, remoteBase, mode);
            onStatus(_jobMap.values.toList());
          }
        }
      });
      _subscriptions.add(subscription);
    }
  }

  void stop() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _initialScan() async {
    for (int i = 0; i < localDirs.length; i++) {
      final dir = localDirs[i];
      final mode = modes[i];
      final remoteBase = remoteDirs[i];

      // Fetch remote files
      final remoteFiles = await s3Manager.listObjects(dir: remoteBase);

      // Run analysis
      final analyzer = SyncAnalyzer(localRoot: dir, remoteFiles: remoteFiles);
      final result = await analyzer.analyze();

      for (final file in [...result.toUpload, ...result.modifiedLocally]) {
        if (mode == BackupMode.sync || mode == BackupMode.upload) {
          await _handleFile(file, dir, remoteBase, mode);
          onStatus(_jobMap.values.toList());
        }
      }
    }
  }

  Future<void> _handleFile(
    File file,
    Directory base,
    String remoteBase,
    BackupMode mode,
  ) async {
    final relPath = p
        .relative(file.path, from: base.path)
        .replaceAll('\\', '/');
    final remoteKey = '$remoteBase$relPath';

    if (_jobMap.containsKey(file.path) && _jobMap[file.path]!.completed) return;

    _jobMap[file.path] = UploadJob(localFile: file, remoteKey: remoteKey);

    try {
      await s3Manager.uploadFile(file: file, key: remoteKey);
      _jobMap[file.path]!.completed = true;
    } catch (e) {
      debugPrint('Upload failed: $e');
    }
  }
}
