import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:s3_drive/services/models/remote_file.dart';
import 's3_file_manager.dart';
import 'models/backup_mode.dart';
import 'sync_analyzer.dart';
import 's3_transfer_task.dart';
import 'config_manager.dart';

class Job {
  final File localFile;
  final String remoteKey;
  final int bytes;
  int bytesCompleted = 0;
  bool completed = false;
  bool running = false;
  String statusMsg = '';
  final void Function(Job job)? onStatus;

  Job({
    required this.localFile,
    required this.remoteKey,
    required this.bytes,
    required this.onStatus,
  });
}

class UploadJob extends Job {
  UploadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.onStatus,
  });
}

class DownloadJob extends Job {
  DownloadJob({
    required super.localFile,
    required super.remoteKey,
    required super.bytes,
    required super.onStatus,
  });
}

class Watcher {
  final Directory localDir;
  final String remoteDir;
  final BackupMode mode;
  final S3FileManager s3Manager;
  final List<Job> jobs;
  final List<RemoteFile> remoteFiles;
  final List<StreamSubscription<FileSystemEvent>> _subscriptions = [];
  final Future<void> Function() remoteRefresh;
  final void Function() onNewJobs;
  final void Function(Job job) onJobStatus;
  bool _watching = false;
  bool _scanning = false;

  Watcher({
    required this.localDir,
    required this.remoteDir,
    required this.mode,
    required this.s3Manager,
    required this.jobs,
    required this.remoteFiles,
    required this.remoteRefresh,
    required this.onNewJobs,
    required this.onJobStatus,
  });

  Future<void> _scan() async {
    if (_scanning) {
      if (kDebugMode) {
        debugPrint(
          "Scan is already in progress for ${localDir.path}. Waiting...",
        );
      }
      while (_scanning) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (kDebugMode) {
        debugPrint("Scan completed for ${localDir.path}. Resuming...");
      }
    }

    _scanning = true;

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

    for (final job in jobs.where((job) => !job.completed && !job.running)) {
      jobs.remove(job);
    }

    for (final file in [...result.newFile, ...result.modifiedLocally]) {
      if (jobs.any((job) {
        return job.localFile.path == file.path && !job.completed;
      })) {
        return;
      }
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        jobs.add(
          UploadJob(
            localFile: file,
            remoteKey:
                '$remoteDir${p.relative(file.path, from: localDir.path)}',
            bytes: file.lengthSync(),
            onStatus: onJobStatus,
          ),
        );
        onNewJobs();
      }
    }

    for (final file in result.modifiedRemotely) {
      if (jobs.any((job) {
        return job.remoteKey ==
            '$remoteDir${p.relative(file.path, from: localDir.path)}';
      })) {
        return;
      }
      if (mode == BackupMode.sync || mode == BackupMode.upload) {
        jobs.add(
          DownloadJob(
            localFile: file,
            remoteKey:
                '$remoteDir${p.relative(file.path, from: localDir.path)}',
            bytes: file.lengthSync(),
            onStatus: onJobStatus,
          ),
        );
        onNewJobs();
      }
    }

    for (final file in result.remoteOnly) {
      if (jobs.any((job) {
        return job.remoteKey == file.key;
      })) {
        return;
      }
      if (mode == BackupMode.sync) {
        jobs.add(
          DownloadJob(
            localFile: File(
              p.join(localDir.path, file.key.split('/').sublist(1).join('/')),
            ),
            remoteKey: file.key,
            bytes: file.size,
            onStatus: onJobStatus,
          ),
        );
        onNewJobs();
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

  void stop() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}

class Processor {
  final S3Config cfg;
  final List<Job> jobs;
  final Function(Job, dynamic) onJobComplete;

  Processor({
    required this.cfg,
    required this.jobs,
    required this.onJobComplete,
  });

  Future<void> start() async {
    int running = jobs.where((job) {
      return job.running;
    }).length;
    final int maxrun = 10;

    while (running < maxrun) {
      if (jobs.any((job) {
        return !job.completed && !job.running;
      })) {
        processJob(
          jobs.firstWhere((job) {
            return !job.completed && !job.running;
          }),
          onJobComplete,
        );
      } else {
        break;
      }
    }
  }

  Future<void> stopall() async {}

  Future<void> stop(Job job) async {}

  Future<void> processJob(Job job, Function(Job, dynamic) onCompleted) async {
    try {
      if (job.runtimeType == UploadJob) {
        job.running = true;
        final result = await S3TransferTask(
          accessKey: cfg.accessKey,
          secretKey: cfg.secretKey,
          region: cfg.region,
          bucket: cfg.bucket,
          key: job.remoteKey,
          localFile: job.localFile,
          task: TransferTask.upload,
          onProgress: (sent, total) {},
          onStatus: (status) {
            job.statusMsg = status;
            job.onStatus?.call(job);
          },
        ).start();
        job.bytesCompleted = job.bytes;
        job.running = false;
        job.completed = true;
        job.onStatus?.call(job);
        onCompleted(job, result);
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
          key: job.remoteKey,
          localFile: job.localFile,
          task: TransferTask.download,
          onProgress: (received, total) {},
          onStatus: (status) {
            job.statusMsg = status;
            job.onStatus?.call(job);
          },
        ).start();
        job.bytesCompleted = job.bytes;
        job.running = false;
        job.completed = true;
        job.onStatus?.call(job);
        onCompleted(job, null);
      }
    } catch (e) {
      job.running = false;
      job.statusMsg = "Error: ${e.toString()}";
      job.onStatus?.call(job);
    }
  }
}
