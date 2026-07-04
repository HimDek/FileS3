import 'package:flutter/foundation.dart';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/utils/db.dart';
import 'package:files3/models/models.dart';
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
    _fileManager ??= S3FileManager.create(this, cfg);
    return _fileManager;
  }

  Profile({required this.name, required this.cfg}) {
    if (fileManager == null || _metaDB == null) {
      accessible.value = false;
    }
  }

  void updateConfig(S3Config newCfg) {
    cfg = newCfg;
    _fileManager = S3FileManager.create(this, cfg);
    if (_fileManager == null) {
      accessible.value = false;
    }
  }

  Future<Iterable<RemoteFileMeta>> listDirectories({
    bool background = false,
  }) async {
    loading.value = true;
    if (!background) {
      Main.onRemoteFilesChanged.notifyListeners();
    }
    await metaDB.sync();
    if (kDebugMode) {
      debugPrint("[Profile.listDirectories] $name Querying remote");
    }
    final result = await listObjects(name);
    if (kDebugMode) {
      debugPrint(
        "[Profile.listDirectories] $name Done querying remote; found ${result.length} items",
      );
    }
    await Main.refreshWatchers(background: background);
    loading.value = false;
    return result;
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

  Future<Iterable<RemoteFileMeta>> listObjects(String dir) async {
    try {
      if (fileManager != null && _metaDB != null) {
        final result = await metaDB.withNestedTransaction((
          txn,
          localTxn,
        ) async {
          final results = await Future.wait([
            fileManager!.listObjects(p.s3.relative(dir, from: name)),
            () async {
              await metaDB.clear(dir, txn: txn);
              await metaDB.addOrUpdateFile(
                RemoteFileMeta(key: p.asDir(name), etag: '', deletedAt: null),
                txn: txn,
                localTxn: localTxn,
              );
              Main.onRemoteFilesChanged.notifyListeners();
            }(),
          ]);
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
          await metaDB.clean(txn: txn);
          return files;
        }, 'listObjects');
        accessible.value = true;
        return result;
      } else {
        throw 'Configuration error';
      }
    } catch (e) {
      accessible.value = false;
      if (kDebugMode) {
        debugPrint(
          "[Profile.listObjects] $name Error refreshing remote files: $e",
        );
      }
      return Iterable.empty();
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
          if (result['etag']?.isNotEmpty == true) {
            final metadata = <String, dynamic>{};
            result.forEach((name, values) {
              if (name.toLowerCase().startsWith('x-amz-meta-')) {
                metadata[name.toLowerCase().replaceFirst('x-amz-meta-', '')] =
                    values.first;
              }
            });
            return RemoteFile(
              key: key,
              etag: result['etag']!.first.replaceAll('"', ''),
              size:
                  int.tryParse(result['content-length']?.firstOrNull ?? '0') ??
                  0,
              lastModified:
                  DateTime.tryParse(
                    result['last-modified']?.firstOrNull ?? '',
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              created:
                  DateTime.tryParse(
                    result['x-amz-meta-created']?.firstOrNull ?? '',
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              original:
                  DateTime.tryParse(
                    result['x-amz-meta-original']?.firstOrNull ?? '',
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              contentType: result['content-type']?.firstOrNull ?? '',
              metadata: metadata,
              deletedAt: null,
            );
          } else {
            throw 'File not found';
          }
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
