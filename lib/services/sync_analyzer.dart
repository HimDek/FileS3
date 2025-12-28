import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'models/remote_file.dart';
import 'file_sync_status.dart';

class SyncAnalysisResult {
  final List<File> newFile;
  final List<File> modifiedLocally;
  final List<RemoteFile> modifiedRemotely;
  final List<File> uploaded;
  final List<RemoteFile> remoteOnly;
  SyncAnalysisResult({
    required this.newFile,
    required this.modifiedLocally,
    required this.modifiedRemotely,
    required this.uploaded,
    required this.remoteOnly,
  });
}

class SyncAnalyzer {
  final Directory localRoot;
  final List<RemoteFile> remoteFiles;

  SyncAnalyzer({required this.localRoot, required this.remoteFiles});

  Future<SyncAnalysisResult> analyze() async {
    final newFile = <File>[];
    final modifiedLocally = <File>[];
    final modifiedRemotely = <RemoteFile>[];
    final already = <File>[];
    final localMap = <String, File>{};

    for (var ent in localRoot.listSync(recursive: true)) {
      if (ent is File) {
        final rel = p
            .relative(ent.path, from: localRoot.path)
            .replaceAll('\\', '/');
        localMap[p.join(p.split(localRoot.path).last, rel)] = ent;
      }
    }
    final remoteMap = {
      for (var f in remoteFiles.where((f) => f.key.split('/').last.isNotEmpty))
        f.key: f,
    };

    if (kDebugMode) {
      debugPrint(
        "Starting sync analysis at ${localRoot.path}: Local files count: ${localMap.length}, Remote files count: ${remoteMap.length}",
      );
    }

    for (var e in localMap.entries) {
      final file = e.value;
      final remote = remoteMap[e.key];
      final status = await FileSyncComparator.compare(
        localFile: file,
        remote: remote,
      );
      switch (status) {
        case FileSyncStatus.newFile:
          newFile.add(file);
          break;
        case FileSyncStatus.modifiedLocally:
          modifiedLocally.add(file);
          break;
        case FileSyncStatus.modifiedRemotely:
          modifiedRemotely.add(remoteMap[e.key]!);
          break;
        case FileSyncStatus.uploaded:
          already.add(file);
          break;
        case FileSyncStatus.remoteOnly:
          break;
      }
    }
    final remoteOnly = remoteFiles
        .where(
          (r) =>
              !localMap.containsKey(r.key) && r.key.split('/').last.isNotEmpty,
        )
        .toList();

    return SyncAnalysisResult(
      newFile: newFile,
      modifiedLocally: modifiedLocally,
      modifiedRemotely: modifiedRemotely,
      uploaded: already,
      remoteOnly: remoteOnly,
    );
  }
}
