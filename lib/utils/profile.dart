import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';

class Profile {
  String name;

  ValueNotifier<bool> accessible = ValueNotifier<bool>(true);

  late S3Config cfg;
  late S3FileManager? fileManager;
  late DeletionRegistrar deletionRegistrar;

  Profile({required this.name, required this.cfg}) {
    fileManager = S3FileManager.create(this, http.Client(), cfg);
    if (fileManager == null) {
      accessible.value = false;
    }
    deletionRegistrar = DeletionRegistrar(profile: this);
  }

  void updateConfig(S3Config newCfg) {
    cfg = newCfg;
    fileManager?.dispose();
    fileManager = S3FileManager.create(this, http.Client(), cfg);
    if (fileManager == null) {
      accessible.value = false;
    }
  }

  void dispose() {
    fileManager?.dispose();
  }

  Future<void> refreshRemote({required String dir}) async {
    try {
      final fetchedRemoteFiles = await fileManager!.listObjects(dir);
      Main.remoteFileRemoveByKey(dir, notify: false);
      Main.remoteFilesAddAll(fetchedRemoteFiles.toList());
      accessible.value = true;
    } catch (e) {
      accessible.value = false;
      if (p.s3.equals(name, dir) &&
          Main.remoteFileByKey(p.asDir(name, context: p.s3)) == null) {
        Main.remoteFilesAdd(
          RemoteFile(
            key: p.asDir(name, context: p.s3),
            etag: "",
          ),
        );
      }
      if (kDebugMode) {
        debugPrint("Error refreshing remote files: $e");
      }
    } finally {
      await ConfigManager.saveRemoteFiles(Main.remoteFiles);
    }
  }

  Future<void> listDirectories({bool background = false}) async {
    loading.value = true;

    if (fileManager == null) {
      accessible.value = false;
      loading.value = false;
      return;
    }
    if (kDebugMode) {
      debugPrint("Directory listing for profile: $name");
    }
    await refreshRemote(dir: name);
    await Main.refreshWatchers(background: background);
    if (kDebugMode) {
      debugPrint("Directory listing Completed for profile: $name");
    }
    loading.value = false;
  }
}
