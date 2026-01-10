import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';

class Profile {
  String name;

  bool accessible = true;
  http.Client httpClient = http.Client();

  late S3Config cfg;
  late S3FileManager? fileManager;
  late DeletionRegistrar deletionRegistrar;

  static void Function(bool loading)? setLoadingState;

  Profile({required this.name, required this.cfg}) {
    fileManager = S3FileManager.create(this, httpClient, cfg);
    if (fileManager == null) {
      accessible = false;
    }
    deletionRegistrar = DeletionRegistrar(profile: this);
  }

  void updateConfig(S3Config newCfg) {
    cfg = newCfg;
    fileManager = S3FileManager.create(this, httpClient, cfg);
    if (fileManager == null) {
      accessible = false;
    }
  }

  String profileKey(String key) {
    return p.relative(key, from: name);
  }

  Future<void> refreshRemote({required String dir}) async {
    try {
      final fetchedRemoteFiles = await fileManager!.listObjects(dir);
      Main.remoteFiles.removeWhere(
        (file) => p.isWithin(dir, file.key) || file.key == dir || dir.isEmpty,
      );
      Main.remoteFiles.addAll(fetchedRemoteFiles);
      Main.ensureDirectoryObjects();
      await ConfigManager.saveRemoteFiles(Main.remoteFiles);
      accessible = true;
    } catch (e) {
      accessible = false;
      if (kDebugMode) {
        debugPrint("Error refreshing remote files: $e");
      }
    }
  }

  Future<void> listDirectories({bool background = false}) async {
    setLoadingState?.call(true);

    if (fileManager == null) {
      accessible = false;
      setLoadingState?.call(false);
      return;
    }

    await refreshRemote(dir: name);
    await Main.refreshWatchers(background: background);
    setLoadingState?.call(false);
  }
}
