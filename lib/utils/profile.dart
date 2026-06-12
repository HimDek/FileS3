import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';

class Profile {
  String name;

  ValueNotifier<bool> accessible = ValueNotifier<bool>(true);
  http.Client httpClient = http.Client();

  late S3Config cfg;
  late S3FileManager? fileManager;
  late DeletionRegistrar deletionRegistrar;

  Profile({required this.name, required this.cfg}) {
    fileManager = S3FileManager.create(this, httpClient, cfg);
    if (fileManager == null) {
      accessible.value = false;
    }
    deletionRegistrar = DeletionRegistrar(profile: this);
  }

  void updateConfig(S3Config newCfg) {
    cfg = newCfg;
    fileManager = S3FileManager.create(this, httpClient, cfg);
    if (fileManager == null) {
      accessible.value = false;
    }
  }

  Future<void> refreshRemote({required String dir}) async {
    try {
      final fetchedRemoteFiles = await fileManager!.listObjects(dir);
      Main.remoteFilesRemoveWhere(
        (file) => p.isWithin(dir, file.key) || file.key == dir || dir.isEmpty,
      );
      Main.remoteFilesAddAll(fetchedRemoteFiles);
      await ConfigManager.saveRemoteFiles(Main.remoteFiles);
      accessible.value = true;
    } catch (e) {
      accessible.value = false;
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

    await refreshRemote(dir: name);
    await Main.refreshWatchers(background: background);
    loading.value = false;
  }
}
