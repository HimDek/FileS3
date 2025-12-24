import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:s3_drive/services/models/remote_file.dart';
import 'models/backup_mode.dart';
import 'sync_analyzer.dart';
import 's3_transfer_task.dart';
import 'config_manager.dart';

abstract class Job {
  final File localFile;
  final String remoteKey;
  final String md5;
  final int bytes;
  S3TransferTask? task;
  int bytesCompleted = 0;
  bool completed = false;
  bool running = false;
  String statusMsg = '';

  static S3Config? cfg;
  static final List<Job> jobs = [];
  static final List<Job> completedJobs = [];

  final void Function(Job job, dynamic result)? onStatus;

  Job({
    required this.localFile,
    required this.remoteKey,
    required this.bytes,
    required this.onStatus,
    required this.md5,
  });

  void add() {
    if (!jobs.contains(this)) jobs.add(this);
    if (jobs.any((job) => !job.running)) startall();
  }

  bool startable() {
    return !running && !completed && cfg != null;
  }

  Future<void> start() async {
    if (!startable()) return;
    try {
      if (runtimeType == UploadJob) {
        running = true;
        task = S3TransferTask(
          accessKey: cfg!.accessKey,
          secretKey: cfg!.secretKey,
          region: cfg!.region,
          bucket: cfg!.bucket,
          key: (cfg!.prefix[cfg!.prefix.length - 1] != '/'
                  ? '${cfg!.prefix}/'
                  : cfg!.prefix) +
              remoteKey,
          localFile: localFile,
          task: TransferTask.upload,
          md5: md5,
          onProgress: (sent, total) {
            bytesCompleted = sent;
            onStatus?.call(this, null);
          },
          onStatus: (status) {
            statusMsg = status;
            onStatus?.call(this, null);
          },
        );
        final result = await task!.start();
        bytesCompleted = bytes;
        running = false;
        completed = true;
        jobs.remove(this);
        completedJobs.add(this);
        final resultFile = RemoteFile(
          key: remoteKey,
          size: bytes,
          etag: result['etag'] != null && result['etag']!.isNotEmpty
              ? result['etag']!.substring(1, result['etag']!.length - 1)
              : '',
          lastModified: localFile.lastModifiedSync(),
        );
        onStatus?.call(this, resultFile);
      }
      if (runtimeType == DownloadJob) {
        running = true;
        // final ifModifiedSince = await localFile.exists()
        //     ? localFile.lastModifiedSync()
        //     : null;
        final dir = Directory(p.dirname(this.localFile.path));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        task = S3TransferTask(
          accessKey: cfg!.accessKey,
          secretKey: cfg!.secretKey,
          region: cfg!.region,
          bucket: cfg!.bucket,
          key: (cfg!.prefix[cfg!.prefix.length - 1] != '/'
                  ? '${cfg!.prefix}/'
                  : cfg!.prefix) +
              remoteKey,
          localFile: localFile,
          task: TransferTask.download,
          md5: md5,
          onProgress: (received, total) {
            bytesCompleted = received;
            onStatus?.call(this, null);
          },
          onStatus: (status) {
            statusMsg = status;
            onStatus?.call(this, null);
          },
        );
        task!.start();
        bytesCompleted = bytes;
        running = false;
        completed = true;
        jobs.remove(this);
        completedJobs.add(this);
        onStatus?.call(this, null);
      }
    } catch (e) {
      running = false;
      bytesCompleted = 0;
      completed = false;
      statusMsg = "Error: ${e.toString()}";
      onStatus?.call(this, null);
    }
  }

  bool stoppable() {
    return task != null && running && !completed;
  }

  void stop(Job job) {
    if (stoppable()) task!.cancel();
  }

  bool removable() {
    return !completed && !running && jobs.contains(this);
  }

  void remove() {
    if (removable()) jobs.remove(this);
  }

  bool dismissible() {
    return completed && !running && completedJobs.contains(this);
  }

  void dismiss() {
    completedJobs.remove(this);
  }

  static Future<void> startall() async {
    int running = Job.jobs.where((job) {
      return job.running;
    }).length;
    final int maxrun = 10;

    while (running < maxrun) {
      if (Job.jobs.any((job) {
        return !job.completed && !job.running;
      })) {
        jobs.firstWhere((job) {
          return !job.completed && !job.running;
        }).start();
      } else {
        break;
      }
    }

    await Future.delayed(const Duration(milliseconds: 1000));
    startall();
  }

  static void stopall() {
    for (var job in jobs) {
      job.stop(job);
    }
  }

  static void clearCompleted() {
    completedJobs.clear();
  }

  static void clear() {
    jobs.clear();
  }
}

class UploadJob extends Job {
  UploadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.onStatus,
    required super.md5,
  });
}

class DownloadJob extends Job {
  DownloadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.onStatus,
    required super.md5,
  });
}

class Watcher {
  final Directory localDir;
  final String remoteDir;
  final BackupMode mode;
  final List<RemoteFile> remoteFiles;
  final List<StreamSubscription<FileSystemEvent>> _subscriptions = [];
  final Future<void> Function() remoteRefresh;
  final void Function(RemoteFile) downloadFile;
  final void Function(String, File) uploadFile;
  bool _watching = false;
  bool _scanning = false;
  bool _waitingScan = false;

  Watcher({
    required this.localDir,
    required this.remoteDir,
    required this.mode,
    required this.remoteFiles,
    required this.remoteRefresh,
    required this.downloadFile,
    required this.uploadFile,
  });

  Future<void> _scan() async {
    if (_waitingScan) {
      debugPrint(
        "A Scan is already waiting for a scan already in progress for ${localDir.path}. Skipping...",
      );
      return;
    }

    if (_scanning) {
      _waitingScan = true;
      if (kDebugMode) {
        debugPrint(
          "Scan is already in progress for ${localDir.path}. Waiting...",
        );
      }
      while (_scanning) {
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      if (kDebugMode) {
        debugPrint("Scan completed for ${localDir.path}. Resuming...");
      }
      _waitingScan = false;
    } else {
      _scanning = true;
    }

    if (!await localDir.exists()) {
      if (kDebugMode) {
        debugPrint("Local directory does not exist: ${localDir.path}");
      }
      return;
    }

    if (remoteFiles.isEmpty) {
      if (kDebugMode) {
        debugPrint("Remote files list is empty, refreshing remote files.");
      }
      await remoteRefresh();
    }

    final analyzer = SyncAnalyzer(
      localRoot: localDir,
      remoteFiles: remoteFiles,
    );
    final result = await analyzer.analyze();

    for (final job in Job.jobs.where((job) => !job.completed && !job.running)) {
      job.remove();
    }

    for (final file in [...result.newFile, ...result.modifiedLocally]) {
      if (Job.jobs.any((job) {
        return job.localFile.path == file.path && !job.completed;
      })) {
        return;
      }
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        uploadFile(
          p.join(
            remoteDir,
            p.relative(file.path, from: localDir.path),
          ),
          file,
        );
      }
    }

    for (final file in result.modifiedRemotely) {
      if (Job.jobs.any((job) {
        return job.remoteKey == file.key;
      })) {
        return;
      }
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        downloadFile(file);
      }
    }

    for (final file in result.remoteOnly) {
      if (Job.jobs.any((job) {
        return job.remoteKey == file.key;
      })) {
        return;
      }
      if (mode == BackupMode.sync) {
        downloadFile(file);
      }
    }

    _scanning = false;
  }

  Future<void> start() async {
    await _scan();

    if (_watching) {
      if (kDebugMode) {
        debugPrint("Watcher is already running for ${localDir.path}");
      }
      return;
    }

    _watching = true;

    final subscription = localDir.watch(recursive: true).listen((event) async {
      final file = File(event.path);
      if (await file.exists()) {
        _scan();
      }
    });
    _subscriptions.add(subscription);
  }

  Future<void> stop() async {
    for (var sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}
