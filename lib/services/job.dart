import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:s3_drive/services/models/remote_file.dart';
import 'models/backup_mode.dart';
import 'sync_analyzer.dart';
import 's3_transfer_task.dart';
import 'config_manager.dart';

class Job {
  final File localFile;
  final String remoteKey;
  final String md5;
  final int bytes;
  int bytesCompleted = 0;
  bool completed = false;
  bool running = false;
  String statusMsg = '';

  static final List<Job> jobs = [];
  static final List<Job> completedJobs = [];

  final void Function(Job job)? onStatus;

  Job({
    required this.localFile,
    required this.remoteKey,
    required this.bytes,
    required this.onStatus,
    required this.md5,
  });

  void onCompleted(dynamic result) {
    jobs.remove(this);
    completedJobs.add(this);
  }

  void add() {
    if (!jobs.contains(this)) jobs.add(this);
  }

  void remove() {
    if (!completed && !running && jobs.contains(this)) jobs.remove(this);
  }

  bool dismissible() {
    return completed && !running && completedJobs.contains(this);
  }

  void dismiss() {
    completedJobs.remove(this);
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
  final void Function(Job job) onJobStatus;
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
    required this.onJobStatus,
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

class Processor {
  final S3Config cfg;
  final Function(Job, dynamic) onJobComplete;

  Processor({
    required this.cfg,
    required this.onJobComplete,
  });

  Future<void> start() async {
    int running = Job.jobs.where((job) {
      return job.running;
    }).length;
    final int maxrun = 10;

    while (running < maxrun) {
      if (Job.jobs.any((job) {
        return !job.completed && !job.running;
      })) {
        processJob(Job.jobs.firstWhere((job) {
          return !job.completed && !job.running;
        }));
      } else {
        break;
      }
    }
  }

  Future<void> stopall() async {}

  Future<void> stop(Job job) async {}

  Future<void> processJob(Job job) async {
    try {
      if (job.runtimeType == UploadJob) {
        job.running = true;
        final result = await S3TransferTask(
          accessKey: cfg.accessKey,
          secretKey: cfg.secretKey,
          region: cfg.region,
          bucket: cfg.bucket,
          key: (cfg.prefix[cfg.prefix.length - 1] != '/'
                  ? '${cfg.prefix}/'
                  : cfg.prefix) +
              job.remoteKey,
          localFile: job.localFile,
          task: TransferTask.upload,
          md5: job.md5,
          onProgress: (sent, total) {
            job.bytesCompleted = sent;
            job.onStatus?.call(job);
          },
          onStatus: (status) {
            job.statusMsg = status;
            job.onStatus?.call(job);
          },
        ).start();
        job.bytesCompleted = job.bytes;
        job.running = false;
        job.completed = true;
        job.onStatus?.call(job);
        job.onCompleted(result);
        onJobComplete(job, result);
      }
      if (job.runtimeType == DownloadJob) {
        job.running = true;
        // final ifModifiedSince = await job.localFile.exists()
        //     ? job.localFile.lastModifiedSync()
        //     : null;
        final dir = Directory(p.dirname(job.localFile.path));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        await S3TransferTask(
          accessKey: cfg.accessKey,
          secretKey: cfg.secretKey,
          region: cfg.region,
          bucket: cfg.bucket,
          key: (cfg.prefix[cfg.prefix.length - 1] != '/'
                  ? '${cfg.prefix}/'
                  : cfg.prefix) +
              job.remoteKey,
          localFile: job.localFile,
          task: TransferTask.download,
          md5: job.md5,
          onProgress: (received, total) {
            job.bytesCompleted = received;
            job.onStatus?.call(job);
          },
          onStatus: (status) {
            job.statusMsg = status;
            job.onStatus?.call(job);
          },
        ).start();
        job.bytesCompleted = job.bytes;
        job.running = false;
        job.completed = true;
        job.onStatus?.call(job);
        job.onCompleted(null);
        onJobComplete(job, null);
      }
    } catch (e) {
      job.running = false;
      job.bytesCompleted = 0;
      job.completed = false;
      job.statusMsg = "Error: ${e.toString()}";
      job.onStatus?.call(job);
    }
  }
}
