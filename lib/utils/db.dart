import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:files3/utils/s3_file_manager.dart';
import 'package:mime/mime.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:files3/models.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/hash_util.dart';
import 'package:files3/utils/path_utils.dart' as p;

Future<void> _lastOperation = Future.value();

Future<T> _enqueue<T>(String name, Future<T> Function() action) async {
  await _lastOperation;

  final future = action();

  _lastOperation = future.then<void>((_) {}, onError: (_) {});

  return await future;
}

typedef Metadata = ({
  String key,
  String etag,
  int size,
  DateTime lastModified,
  DateTime created,
  DateTime original,
  String contentType,
  Map<String, dynamic> metadata,
  bool present,
  DateTime? deletedAt,
  (int, int) count,
});

enum OpType { addOrUpdate, remove }

enum OpStatus { pending, applied }

typedef Operation = ({
  String key,
  OpType type,
  Metadata? row,
  String? oldEtag,
  String? appliedToDBEtag,
});

class MetaDB {
  Database? _db;
  Database? _localDb;
  final Profile profile;
  String? etag;
  late final String _key = p.s3.join(profile.name, 'metadata.db');
  late final File _file = File(
    p.context.joinAll([
      Main.documentsDir,
      'profiles',
      profile.name,
      'metadata',
      'metadata.db',
    ]),
  );
  late final File _opFile = File(
    p.context.joinAll([
      Main.documentsDir,
      'profiles',
      profile.name,
      'metadata',
      'operations.db',
    ]),
  );
  bool isInitialized = false;

  MetaDB({required this.profile});

  Future<void> init() => _enqueue("init", () async {
    if (isInitialized) {
      return;
    }
    if (!_file.existsSync()) {
      bool? pooled = await _pullDb();
      if (pooled == false) {
        // No remote DB exists, so we can proceed
        await _openDb();
      }
    } else {
      // Local DB exists, so we can open it
      await _openDb();
    }
    if (_localDb == null) {
      await _openLocalDb();
    }
    if (_db != null && _localDb != null) {
      isInitialized = true;
    }
  });

  Future<void> sync() => _enqueue("sync", () async => await _sync());

  /// Only use for Read operations, not for Write operations.
  Future<T> withDB<T>(Future<T> Function(Database db) callback) =>
      _db != null && _db!.isOpen
      ? callback(_db!)
      : _enqueue<T>("withDB", () async {
          await _openDb();
          return callback(_db!);
        });

  /// Only use for Read operations, not for Write operations.
  Future<T> withLocalDb<T>(Future<T> Function(Database db) callback) =>
      _localDb != null && _localDb!.isOpen
      ? callback(_localDb!)
      : _enqueue<T>("withLocalDb", () async {
          await _openLocalDb();
          return callback(_localDb!);
        });

  Future<T> withTransaction<T>(Future<T> Function(Transaction txn) callback) =>
      _enqueue<T>("dbTransaction", () async {
        return await _db!.transaction((txn) async {
          return await callback(txn);
        });
      });

  Future<T> withLocalTransaction<T>(
    Future<T> Function(Transaction localTxn) callback,
  ) => _enqueue<T>("localDbTransaction", () async {
    return await _localDb!.transaction((localTxn) async {
      return await callback(localTxn);
    });
  });

  Future<T> withNestedTransaction<T>(
    Future<T> Function(Transaction txn, Transaction localTxn) callback,
  ) => _enqueue<T>("nestedTransaction", () async {
    return await _db!.transaction((txn) async {
      return await _localDb!.transaction((localTxn) async {
        return await callback(txn, localTxn);
      });
    });
  });

  Future<void> addIntermediateDirectories(
    String key,
    Set<String> addedDirs, {
    required Transaction txn,
    required Transaction localTxn,
  }) async {
    final parts = key.split('/');
    if (parts.length <= 1) return;

    var path = '';
    for (var i = 0; i < parts.length - 1; i++) {
      path = path.isEmpty ? parts[i] : '$path/${parts[i]}';
      final dirKey = '$path/';

      if (addedDirs.add(dirKey)) {
        await addOrUpdateFile(
          RemoteFile(key: dirKey, etag: ''),
          txn: txn,
          localTxn: localTxn,
        );
      }
    }
  }

  /// Add or update a file in the database, marking it as present in the remote.
  Future<void> addOrUpdateFile(
    RemoteFile file, {
    String? oldEtag,
    Transaction? txn,
    Transaction? localTxn,
  }) async {
    Future<void> body() async {
      final Metadata metadata = (
        key: file.key,
        etag: file.etag,
        size: file.size,
        lastModified: file.lastModified.toUtc(),
        created: file.created.toUtc(),
        original: file.original.toUtc(),
        contentType: lookupMimeType(file.key) ?? 'application/octet-stream',
        metadata: file.metadata,
        present: true,
        deletedAt: null,
        count: file.count,
      );

      final op = (
        key: file.key,
        type: OpType.addOrUpdate,
        row: metadata,
        oldEtag: oldEtag,
        appliedToDBEtag: null,
      );

      Future<void> callback(
        Operation op,
        Transaction? txn,
        Transaction localTxn,
      ) async {
        await _addOrUpdateOp(op, txn: localTxn);
        await _applyAdd(op, txn: txn);
        await _applyOp(file.key, txn: localTxn);
      }

      if (localTxn != null) {
        await callback(op, txn, localTxn);
        return;
      }

      await _localDb?.transaction((localTxn) async {
        await callback(op, txn, localTxn);
      });
    }

    if (txn != null && localTxn != null) {
      await body();
    } else {
      await _enqueue('addOrUpdateFile', body);
    }
  }

  /// Delete a file from the database, marking it as not present in the remote.
  Future<void> deleteFile(
    String key, {
    String? oldEtag,
    Transaction? txn,
    Transaction? localTxn,
  }) async {
    Future<void> body() async {
      final op = (
        key: key,
        type: OpType.remove,
        row: null,
        oldEtag: oldEtag,
        appliedToDBEtag: null,
      );

      Future<void> callback(
        Operation op,
        Transaction? txn,
        Transaction localTxn,
      ) async {
        await _addOrUpdateOp(op, txn: localTxn);
        await _applyRemove(op, txn: txn);
        await _applyOp(key, txn: localTxn);
      }

      if (localTxn != null) {
        await callback(op, txn, localTxn);
        return;
      }

      await _localDb?.transaction((localTxn) async {
        await callback(op, txn, localTxn);
      });
    }

    if (txn != null && localTxn != null) {
      await body();
    } else {
      await _enqueue('deleteFile', body);
    }
  }

  Future<RemoteFile?> getFile(String key, {bool ifPresent = true}) async {
    final result = await _db?.query(
      'remotefiles',
      where: ifPresent ? 'key = ? AND present = 1' : 'key = ?',
      whereArgs: [key],
    );
    if (result != null && result.isNotEmpty) {
      return _remoteFileFromRow(result.first);
    }
    return null;
  }

  Future<Iterable<RemoteFile>> getFiles(
    List<String> keys, {
    bool ifPresent = true,
  }) async {
    final result = await _db?.query(
      'remotefiles',
      where: ifPresent
          ? 'key IN (${List.filled(keys.length, '?').join(',')}) AND present = 1'
          : 'key IN (${List.filled(keys.length, '?').join(',')})',
      whereArgs: keys,
    );
    if (result != null && result.isNotEmpty) {
      return result.map((row) {
        return _remoteFileFromRow(row);
      });
    }
    return [];
  }

  ({String where, List<Object?> whereArgs}) filesByDirQueryArgs(
    String dir, {
    bool recursive = true,
    bool ifPresent = true,
    bool includeDirs = true,
    bool includeFiles = true,
  }) {
    String where;
    List<Object?> whereArgs;

    if (recursive) {
      where = ifPresent
          ? '''
          key LIKE ? AND key != ? AND present = 1
        '''
          : '''
          key LIKE ? AND key != ?
        ''';
      whereArgs = ['$dir%', dir];
    } else if (dir.isEmpty) {
      where = ifPresent
          ? '''
          present = 1 AND (
            instr(key, '/') = 0 OR
            instr(key, '/') = length(key)
          )
        '''
          : '''
          instr(key, '/') = 0 OR
          instr(key, '/') = length(key)
        ''';
      whereArgs = [];
    } else {
      where = ifPresent
          ? '''
          key LIKE ? AND key != ? AND present = 1
          AND (
            instr(substr(key, length(?) + 1), '/') = 0
            OR
            instr(substr(key, length(?) + 1), '/') =
              length(substr(key, length(?) + 1))
          )
        '''
          : '''
          key LIKE ? AND key != ?
          AND (
            instr(substr(key, length(?) + 1), '/') = 0
            OR
            instr(substr(key, length(?) + 1), '/') =
              length(substr(key, length(?) + 1))
          )
        ''';
      whereArgs = ['$dir%', dir, dir, dir, dir];
    }

    if (!includeDirs && !includeFiles) {
      where = '0';
      whereArgs = [];
    } else if (includeDirs != includeFiles) {
      where += includeDirs
          ? " AND substr(key, -1) = '/'"
          : " AND substr(key, -1) != '/'";
    }

    return (where: where, whereArgs: whereArgs);
  }

  Future<Iterable<RemoteFile>> getFilesByDir(
    String dir, {
    bool recursive = true,
    bool ifPresent = true,
    bool includeDirs = true,
    bool includeFiles = true,
  }) async {
    final args = filesByDirQueryArgs(
      dir,
      recursive: recursive,
      ifPresent: ifPresent,
      includeDirs: includeDirs,
      includeFiles: includeFiles,
    );

    final result = await _db?.query(
      'remotefiles',
      where: args.where,
      whereArgs: args.whereArgs,
    );

    if (result != null && result.isNotEmpty) {
      return result.map(_remoteFileFromRow);
    }
    return [];
  }

  Future<Iterable<RemoteFile>> getFilesByDirs(
    List<String> dirs, {
    bool recursive = true,
    bool ifPresent = true,
    bool includeDirs = true,
    bool includeFiles = true,
  }) async {
    final args = dirs.map((dir) {
      return filesByDirQueryArgs(
        dir,
        recursive: recursive,
        ifPresent: ifPresent,
        includeDirs: includeDirs,
        includeFiles: includeFiles,
      );
    }).toList();
    final where = args.map((arg) => '(${arg.where})').join(' OR ');
    final whereArgs = args.expand((arg) => arg.whereArgs).toList();
    final result = await _db?.query(
      'remotefiles',
      where: where,
      whereArgs: whereArgs,
    );
    if (result != null && result.isNotEmpty) {
      return result.map((row) {
        return _remoteFileFromRow(row);
      });
    }
    return [];
  }

  /// Clear all present files in the database, marking them as deleted, to be added back later if they are still present on the remote.
  /// This is used when a full refresh of the remote files is needed.
  Future<void> clear() => _enqueue("clear", () async {
    await _db?.execute(
      '''
          UPDATE remotefiles
          SET present = 0, deletedAt = ?
          WHERE present = 1
      ''',
      [DateTime.now().toUtc().millisecondsSinceEpoch],
    );
  });

  // Clean up old deleted entries that are no longer needed
  Future<void> clean() => _enqueue("clean", () async {
    await _db?.execute(
      '''
          DELETE FROM remotefiles
          WHERE present = 0 AND deletedAt IS NOT NULL AND deletedAt < ?
      ''',
      [
        DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch,
      ],
    );
  });

  Future<void> _openLocalDb() async {
    _localDb?.isOpen ?? false ? await _localDb!.close() : null;
    _localDb = await openDatabase(
      _opFile.path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
            CREATE TABLE IF NOT EXISTS operations (
              key TEXT PRIMARY KEY NOT NULL,
              type TEXT NOT NULL,
              row TEXT,
              oldEtag TEXT,
              appliedToDBEtag TEXT
            )
          ''');
      },
    );
  }

  Future<void> _openDb() async {
    _db?.isOpen ?? false ? await _db!.close() : null;
    _db = await openDatabase(
      _file.path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
            CREATE TABLE IF NOT EXISTS remotefiles (
              key TEXT PRIMARY KEY NOT NULL,
              etag TEXT NOT NULL DEFAULT '',
              size INT NOT NULL DEFAULT 0,
              lastModified INT NOT NULL DEFAULT 0,
              created INT NOT NULL DEFAULT 0,
              original INT NOT NULL DEFAULT 0,
              contentType TEXT NOT NULL DEFAULT 'application/octet-stream',
              metadata TEXT NOT NULL DEFAULT '{}',
              present INT CHECK(present IN (0, 1)) NOT NULL DEFAULT 1,
              deletedAt INT
              count TEXT NOT NULL DEFAULT '(0, 0)',
              CONSTRAINT present_deletedAt CHECK (present = 1 OR deletedAt IS NOT NULL)
            )
          ''');
      },
      onOpen: (db) async {
        await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_remotefiles_present
            ON remotefiles (present)
          ''');
        await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_remotefiles_deletedAt
            ON remotefiles (deletedAt)
          ''');
        await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_remotefiles_lastModified
            ON remotefiles (lastModified)
          ''');
        await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_remotefiles_created
            ON remotefiles (created)
          ''');
        await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_remotefiles_original
            ON remotefiles (original)
          ''');
        await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_remotefiles_contentType
            ON remotefiles (contentType)
          ''');
        await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_remotefiles_size
            ON remotefiles (size)
          ''');
      },
    );
  }

  RemoteFile _remoteFileFromRow(Map<String, dynamic> row) {
    final Map<String, dynamic> resRow = Map.from(row);
    resRow['metadata'] =
        jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
    resRow['count'] = (row['count'] as String)
        .substring(1, (row['count'] as String).length - 1)
        .split(',')
        .map((e) => int.parse(e.trim()))
        .toList();
    final meta = _metadataFromJson(resRow);
    return RemoteFile(
      key: meta.key,
      etag: meta.etag,
      size: meta.size,
      lastModified: meta.lastModified,
      created: meta.created,
      original: meta.original,
      contentType: meta.contentType,
      metadata: meta.metadata,
      deletedAt: meta.deletedAt,
      count: meta.count,
    );
  }

  List<Object?> _rowFromMetadata(Metadata metadata) {
    return [
      metadata.key,
      metadata.etag,
      metadata.size,
      metadata.lastModified.millisecondsSinceEpoch,
      metadata.created.millisecondsSinceEpoch,
      metadata.original.millisecondsSinceEpoch,
      metadata.contentType,
      jsonEncode(metadata.metadata),
      metadata.present ? 1 : 0,
      metadata.deletedAt?.millisecondsSinceEpoch,
      '(${metadata.count.$1}, ${metadata.count.$2})',
    ];
  }

  Map<String, dynamic> _jsonFromMetadata(Metadata metadata) {
    return {
      'key': metadata.key,
      'etag': metadata.etag,
      'size': metadata.size,
      'lastModified': metadata.lastModified.millisecondsSinceEpoch,
      'created': metadata.created.millisecondsSinceEpoch,
      'original': metadata.original.millisecondsSinceEpoch,
      'contentType': metadata.contentType,
      'metadata': metadata.metadata,
      'present': metadata.present ? 1 : 0,
      'deletedAt': metadata.deletedAt?.millisecondsSinceEpoch,
      'count': [metadata.count.$1, metadata.count.$2],
    };
  }

  Metadata _metadataFromJson(Map<String, dynamic> json) {
    return (
      key: json['key'] as String,
      etag: json['etag'] as String,
      size: json['size'] as int,
      lastModified: DateTime.fromMillisecondsSinceEpoch(
        json['lastModified'] as int,
        isUtc: true,
      ),
      created: DateTime.fromMillisecondsSinceEpoch(
        json['created'] as int,
        isUtc: true,
      ),
      original: DateTime.fromMillisecondsSinceEpoch(
        json['original'] as int,
        isUtc: true,
      ),
      contentType: json['contentType'] as String,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      present: (json['present'] as int?) == 1,
      deletedAt: json['deletedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              json['deletedAt'] as int,
              isUtc: true,
            )
          : null,
      count: (json['count'] as List<dynamic>?) != null
          ? (json['count'][0] as int, json['count'][1] as int)
          : (0, 0),
    );
  }

  List<Object?> _rowFromOperation(Operation op) {
    return [
      op.key,
      op.type.name,
      op.row == null ? null : jsonEncode(_jsonFromMetadata(op.row!)),
      op.oldEtag,
      op.appliedToDBEtag,
    ];
  }

  Operation _operationFromJson(Map<String, dynamic> json) {
    return (
      key: json['key'] as String,
      type: OpType.values.firstWhere((e) => e.name == (json['type'] as String)),
      row: (json['row'] as Map<String, dynamic>?) != null
          ? _metadataFromJson(json['row'] as Map<String, dynamic>)
          : null,
      oldEtag: json['oldEtag'] as String?,
      appliedToDBEtag: json['appliedToDBEtag'] as String?,
    );
  }

  Future<void> _addOrUpdateOp(Operation op, {Transaction? txn}) async {
    await (txn ?? _localDb)?.execute('''INSERT OR REPLACE INTO operations
        (key, type, row, oldEtag, appliedToDBEtag)
        VALUES (?, ?, ?, ?, ?)''', _rowFromOperation(op));
  }

  Future<void> _applyOp(String key, {Transaction? txn}) async {
    await (txn ?? _localDb)?.execute(
      '''UPDATE operations
        SET appliedToDBEtag = ?
        WHERE key = ?''',
      [etag, key],
    );
  }

  Future<List<Operation>> _getOps() async {
    final List<Map<String, Object?>>? rows = await _localDb?.query(
      'operations',
    );
    if (rows == null) {
      return [];
    }
    return rows.map((row) {
      final rowJson = {
        'key': row['key'] as String,
        'type': row['type'] as String,
        'row': row['row'] != null
            ? jsonDecode(row['row'] as String) as Map<String, dynamic>
            : null,
        'oldEtag': row['oldEtag'] as String?,
        'appliedToDBEtag': row['appliedToDBEtag'] as String?,
      };
      return _operationFromJson(rowJson);
    }).toList();
  }

  Future<void> _cleanOps() async {
    await _localDb?.execute(
      'DELETE FROM operations WHERE appliedToDBEtag is NOT NULL',
    );
  }

  Future<bool> _sync() async {
    while (_db != null) {
      final ops = await _getOps();
      if (ops.isEmpty) {
        break;
      }
      await _applyOperations(ops);
      final success = await _pushDb();

      if (success == true) {
        // Push successful, clear applied operations and return true
        await _cleanOps();
        return true;
      } else if (success == false) {
        // Push failed due to etag mismatch
        if (await _pullDb() == true) {
          // Pull successful, retry the sync
          continue;
        }
        // Pull failed, break the loop
        break;
      }
      // Push failed due to other reasons, break the loop
      break;
    }
    // If we reach here, it means the sync was not successful
    return false;
  }

  Future<void> _applyAdd(Operation op, {Transaction? txn}) async {
    if (op.row == null) {
      throw ArgumentError('Operation row cannot be null for addOrUpdate');
    }
    await (txn ?? _db)?.execute(
      '''
          INSERT INTO remotefiles (
            key,
            etag,
            size,
            lastModified,
            created,
            original,
            contentType,
            metadata,
            present,
            deletedAt,
            count
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET
            etag = excluded.etag,
            size = excluded.size,
            lastModified = excluded.lastModified,
            created = excluded.created,
            original = excluded.original,
            contentType = excluded.contentType,
            metadata = excluded.metadata,
            present = excluded.present,
            deletedAt = excluded.deletedAt,
            count = excluded.count
          WHERE
            ? IS NULL
            OR remotefiles.etag = ?;
        ''',
      [
        ..._rowFromMetadata(op.row!),
        // WHERE parameters
        op.oldEtag,
        op.oldEtag,
      ],
    );
  }

  Future<void> _applyRemove(Operation op, {Transaction? txn}) async {
    await (txn ?? _db)?.execute(
      '''
          UPDATE remotefiles
          SET present = 0, deletedAt = ?
          WHERE key LIKE ? AND ( ? IS NULL OR etag = ?)
        ''',
      [
        DateTime.now().toUtc().millisecondsSinceEpoch,
        '${op.key}%',
        op.oldEtag,
        op.oldEtag,
      ],
    );
  }

  Future<void> _applyOperations(List<Operation> ops) async {
    await _db?.transaction((txn) async {
      await _localDb?.transaction((localTxn) async {
        for (final op in ops) {
          if (op.appliedToDBEtag != etag) {
            if (op.type == OpType.addOrUpdate && op.row != null) {
              await _applyAdd(op, txn: txn);
            } else if (op.type == OpType.remove) {
              await _applyRemove(op, txn: txn);
            }
            await _applyOp(op.key, txn: localTxn);
          }
        }
      });
    });
  }

  Future<bool?> _pullDb() async {
    try {
      Map<String, String>? headers;
      try {
        headers = await profile.fileManager?.headObject(_key);
      } catch (e) {
        if (e is S3Exception && e.code == 404) {
          return false;
        }
        rethrow;
      }

      if (headers?['key'] == null) {
        return false;
      }

      Job job = DownloadJob(
        localFile: _file,
        remoteKey: _key,
        bytes: int.tryParse(headers!['content-length'] ?? '0') ?? 0,
        md5: () {
          final hex = headers!['etag']!.replaceAll('"', '');

          if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hex)) {
            throw StateError('ETag is not a single-part MD5 digest');
          }

          final bytes = List<int>.generate(
            16,
            (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
          );

          return Digest(bytes);
        }(),
        profile: profile,
      );

      await job.start();
      job.dispose();

      await _openDb();

      return true;
    } catch (e) {
      return null;
    }
  }

  Future<bool?> _pushDb() async {
    Job job = UploadJob(
      localFile: _file,
      remoteKey: _key,
      bytes: _file.lengthSync(),
      md5: await HashUtil(_file).md5Hash(),
      profile: profile,
      ifMatch: etag,
    );
    final result = await job.start();
    job.dispose();
    if (result == null) {
      return null;
    }
    if (result.statusCode >= 200 && result.statusCode < 300) {
      etag = result.headers['etag']?[0].replaceAll('"', '');
      return true;
    } else if (result.statusCode == 412 || result.statusCode == 409) {
      return false;
    } else {
      return null;
    }
  }
}
