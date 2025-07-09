import 'dart:io';
import 'package:path/path.dart' as p;
import 'models/remote_file.dart';
import 'file_sync_status.dart';

class SyncAnalysisResult {
  final List<File> toUpload;
  final List<File> modifiedLocally;
  final List<File> alreadyUploaded;
  final List<RemoteFile> remoteOnly;
  SyncAnalysisResult({
    required this.toUpload,
    required this.modifiedLocally,
    required this.alreadyUploaded,
    required this.remoteOnly,
  });
}

class SyncAnalyzer {
  final Directory localRoot;
  final List<RemoteFile> remoteFiles;
  SyncAnalyzer({required this.localRoot, required this.remoteFiles});
  Future<SyncAnalysisResult> analyze() async {
    final toUpload = <File>[];
    final modified = <File>[];
    final already = <File>[];
    final localMap = <String, File>{};
    await for (var ent in localRoot.list(recursive: true)) {
      if (ent is File) {
        final rel = p
            .relative(ent.path, from: localRoot.path)
            .replaceAll('\\', '/');
        localMap['${remoteFiles[0].key}$rel'] = ent;
      }
    }
    final remoteMap = {
      for (var f in remoteFiles.getRange(1, remoteFiles.length)) f.key: f,
    };

    for (var e in localMap.entries) {
      final file = e.value;
      final remote = remoteMap[e.key];
      final status = await FileSyncComparator.compare(
        localFile: file,
        remote: remote,
      );
      switch (status) {
        case FileSyncStatus.newFile:
          toUpload.add(file);
          break;
        case FileSyncStatus.modified:
          modified.add(file);
          break;
        case FileSyncStatus.uploaded:
          already.add(file);
          break;
        case FileSyncStatus.remoteOnly:
          break;
      }
    }
    final remoteOnly = remoteFiles
        .getRange(1, remoteFiles.length)
        .where((r) => !localMap.containsKey(r.key))
        .toList();
    return SyncAnalysisResult(
      toUpload: toUpload,
      modifiedLocally: modified,
      alreadyUploaded: already,
      remoteOnly: remoteOnly,
    );
  }
}
