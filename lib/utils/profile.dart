import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/utils/db.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';

class Profile {
  String name;

  ValueNotifier<bool> accessible = ValueNotifier<bool>(true);

  late S3Config cfg;
  late S3FileManager? fileManager;
  late MetaDB metaDB;
  bool isInitialized = false;

  Profile({required this.name, required this.cfg}) {
    fileManager = S3FileManager.create(this, http.Client(), cfg);
    if (fileManager == null) {
      accessible.value = false;
    }
    metaDB = MetaDB(profile: this);
  }

  Future<void> init() async {
    await metaDB.init();
    isInitialized = true;
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
      await Main.remoteFileRemoveByKey(p.s3.asDir(dir), notify: false);
      await Main.remoteFilesAddAll(fetchedRemoteFiles);
      accessible.value = true;
    } catch (e) {
      accessible.value = false;
      if (p.s3.equals(name, dir) &&
          (await Main.remoteFileByKey(p.s3.asDir(name))) == null) {
        await Main.remoteFilesAdd(RemoteFile(key: p.s3.asDir(name), etag: ""));
      }
      if (kDebugMode) {
        debugPrint("Error refreshing remote files: $e");
      }
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
