import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/utils/db.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:sqflite/sqflite.dart';

class Profile {
  String name;

  ValueNotifier<bool> accessible = ValueNotifier<bool>(true);

  MetaDB? _metaDB;
  S3Config cfg;
  S3FileManager? _fileManager;

  MetaDB get metaDB {
    _metaDB ??= MetaDB(profile: this);
    return _metaDB!;
  }

  S3FileManager? get fileManager {
    _fileManager ??= S3FileManager.create(this, http.Client(), cfg);
    return _fileManager;
  }

  Profile({required this.name, required this.cfg}) {
    if (fileManager == null || _metaDB == null) {
      accessible.value = false;
    }
  }

  void updateConfig(S3Config newCfg) {
    cfg = newCfg;
    _fileManager?.dispose();
    _fileManager = S3FileManager.create(this, http.Client(), cfg);
    if (_fileManager == null) {
      accessible.value = false;
    }
  }

  void dispose() {
    _fileManager?.dispose();
  }

  Future<void> listDirectories({bool background = false}) async {
    loading.value = true;
    if (kDebugMode) {
      debugPrint("Directory listing for profile: $name");
    }
    await metaDB.sync();
    await listObjects(name);
    Main.onRemoteFilesChanged.notifyListeners();
    await Main.refreshWatchers(background: background);
    if (kDebugMode) {
      debugPrint("Directory listing Completed for profile: $name");
    }
    loading.value = false;
  }

  Future<void> createDirectory(String dir) async {
    try {
      if (fileManager != null && _metaDB != null) {
        await metaDB.withNestedTransaction((txn, localTxn) async {
          final result = await fileManager!.createDirectory(
            p.s3.relative(dir, from: name),
          );
          await metaDB.addOrUpdateFile(
            RemoteFileMeta(key: dir),
            txn: txn,
            localTxn: localTxn,
          );
          return result;
        }, 'createDirectory');
        accessible.value = true;
      } else {
        throw 'Configuration error';
      }
    } catch (e) {
      accessible.value = false;
      rethrow;
    }
  }

  Future<void> listObjects(String dir) async {
    try {
      if (fileManager != null && _metaDB != null) {
        await metaDB.withNestedTransaction((txn, localTxn) async {
          final results = await Future.wait([
            fileManager!.listObjects(p.s3.relative(dir, from: name)),
            () async {
              await metaDB.addOrUpdateFile(
                RemoteFileMeta(key: p.asDir(name), etag: ''),
                txn: txn,
                localTxn: localTxn,
              );
              Main.onRemoteFilesChanged.notifyListeners();
            }(),
          ]);
          final args = metaDB.filesByDirQueryArgs(
            dir,
            includeSelf: true,
            recursive: true,
            ifPresent: true,
            includeDirs: true,
            includeFiles: true,
          );
          await txn.update(
            'remotefiles',
            {
              'present': 0,
              'deletedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
            },
            where: args.where,
            whereArgs: args.whereArgs,
          );
          final files = (results[0] as Iterable<Map<String, dynamic>>).map(
            (file) => RemoteFileMeta(
              key: p.s3.join(name, file['key']),
              size: file['size'],
              etag: file['etag'],
              lastModified: file['lastModified'],
            ),
          );
          final addedDirs = <String>{};
          for (final file in files) {
            await metaDB.addIntermediateDirectories(
              file.key,
              addedDirs,
              txn: txn,
              localTxn: localTxn,
            );
            await metaDB.addOrUpdateFile(file, txn: txn, localTxn: localTxn);
          }
          return files;
        }, 'listObjects');
        accessible.value = true;
      } else {
        throw 'Configuration error';
      }
    } catch (e) {
      accessible.value = false;
      if (kDebugMode) {
        debugPrint("Error refreshing remote files: $e");
      }
    }
  }

  Future<RemoteFile> copyFile(
    String sourceKey,
    String destinationKey, {
    Profile? sourceProfile,
  }) async {
    try {
      if (fileManager != null && _metaDB != null) {
        final result = await metaDB.withNestedTransaction((
          txn,
          localTxn,
        ) async {
          await fileManager!.copyFile(
            p.s3.relative(sourceKey, from: name),
            p.s3.relative(destinationKey, from: name),
          );
          return headObject(destinationKey, txn: txn, localTxn: localTxn);
        }, 'copyFile');
        accessible.value = true;
        return result;
      } else {
        throw 'Configuration Error';
      }
    } catch (e) {
      accessible.value = false;
      rethrow;
    }
  }

  Future<void> deleteFile(String key) async {
    try {
      if (fileManager != null && _metaDB != null) {
        await metaDB.withNestedTransaction((txn, localTxn) async {
          await fileManager!.deleteFile(p.s3.relative(key, from: name));
          await metaDB.deleteFile(key, txn: txn, localTxn: localTxn);
        }, 'deleteFile');
        accessible.value = true;
      } else {
        throw 'Configuration Error';
      }
    } catch (e) {
      accessible.value = false;
      rethrow;
    }
  }

  Future<RemoteFile> headObject(
    String key, {
    bool nosave = false,
    Transaction? txn,
    Transaction? localTxn,
  }) async {
    assert(
      !(txn != null && localTxn == null) && !(txn == null && localTxn != null),
      'Both txn and localTxn must be provided together or not at all.',
    );
    try {
      if (fileManager != null) {
        Future<RemoteFile> body() async {
          final result = await fileManager!.headObject(
            p.s3.relative(key, from: name),
          );
          return RemoteFile(
            key: key,
            etag: result['etag']?.replaceAll('"', '') ?? '',
            size: int.tryParse(result['content-length'] ?? '0') ?? 0,
            lastModified:
                DateTime.tryParse(result['last-modified'] ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            created:
                DateTime.tryParse(result['x-amz-meta-created'] ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            original:
                DateTime.tryParse(result['x-amz-meta-original'] ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            contentType: result['content-type'] ?? '',
            metadata: Map.fromEntries(
              result.entries
                  .where((e) => e.key.startsWith('x-amz-meta-'))
                  .map(
                    (e) => MapEntry(
                      e.key.replaceFirst('x-amz-meta-', ''),
                      e.value,
                    ),
                  ),
            ),
            deletedAt: null,
          );
        }

        Future<RemoteFile> query(Transaction txn, Transaction localTxn) async {
          final file = await body();
          RemoteFile? oldFile = (await RemoteFile.getByKey(key, txn: txn));
          await metaDB.addOrUpdateFile(
            file,
            oldEtag: oldFile?.etag,
            txn: txn,
            localTxn: localTxn,
          );
          return file;
        }

        final result = nosave || _metaDB == null || _fileManager == null
            ? await body()
            : txn == null && localTxn == null
            ? await metaDB.withNestedTransaction(query, 'headObject')
            : await query(txn!, localTxn!);

        accessible.value = true;
        return result;
      } else {
        throw 'Configuration Error';
      }
    } catch (e) {
      accessible.value = false;
      rethrow;
    }
  }

  String getUrl(String key, {int? validForSeconds}) {
    try {
      if (_fileManager != null) {
        final result = fileManager!.getUrl(
          p.s3.relative(key, from: name),
          validForSeconds: validForSeconds,
        );
        accessible.value = true;
        return result;
      } else {
        throw 'Configuration Error';
      }
    } catch (e) {
      accessible.value = false;
      rethrow;
    }
  }
}
