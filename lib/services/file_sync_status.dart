import 'dart:io';
import 'models/remote_file.dart';
import 'hash_util.dart';

enum FileSyncStatus {
  uploaded,
  modifiedLocally,
  modifiedRemotely,
  newFile,
  remoteOnly,
}

class FileSyncComparator {
  static FileSyncStatus compare({
    required File localFile,
    required RemoteFile? remote,
  }) {
    if (!localFile.existsSync()) return FileSyncStatus.remoteOnly;
    if (remote == null) return FileSyncStatus.newFile;
    final localHash = HashUtil.md5Hash(localFile);
    return localHash == remote.etag
        ? FileSyncStatus.uploaded
        : remote.lastModified.isAfter(localFile.lastModifiedSync())
            ? FileSyncStatus.modifiedRemotely
            : FileSyncStatus.modifiedLocally;
  }
}
