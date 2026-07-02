import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:files3/models.dart';
import 'package:flutter/foundation.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/hash_util.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/s3_file_manager.dart';

Future<void> _lastOperation = Future.value();

Future<T> _enqueue<T>(String name, Future<T> Function() action) async {
  // if (kDebugMode) {
  //   debugPrint("Enqueuing operation: $name");
  // }
  await _lastOperation;

  final future = action();

  _lastOperation = future.then<void>(
    (_) {
      // if (kDebugMode) {
      //   debugPrint("Operation completed: $name");
      // }
    },
    onError: (e) {
      // if (kDebugMode) {
      //   debugPrint("Operation failed: $name Error: $e");
      // }
    },
  );

  return await future;
}

enum OpType { addOrUpdate, remove }

enum OpStatus { pending, applied }

typedef Operation = ({
  String key,
  OpType type,
  Map<String, Object?>? metadata,
  String? oldEtag,
  String? appliedToDBEtag,
  bool ifPresent,
  List<String>? fields,
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
  Future<bool>? _initializing;

  MetaDB({required this.profile}) {
    _init();
  }

  static String profileNamePlaceholder = '\$s3_files_profile_name';

  String get keyColumn => "'${profile.name}' || substr(key, 23) AS key";

  List<String> get remoteFileFields => [
    keyColumn,
    'key as s3_key',
    'etag',
    'size',
    'lastModified',
    'created',
    'original',
    'contentType',
    'metadata',
    'present',
    'deletedAt',
    'count',
  ];

  String s3KeyFromKey(String key) {
    final s3Key = p.s3.equals(key, profile.name)
        ? p.asDir(profileNamePlaceholder)
        : key.isEmpty
        ? ''
        : p.s3.join(
            profileNamePlaceholder,
            p.s3.relative(key, from: profile.name),
          );
    return s3Key;
  }

  Future<bool> _init() => _enqueue("init", () async {
    if (isInitialized) {
      return true;
    }
    if (_initializing != null) {
      return _initializing!;
    }

    Future<bool> body() async {
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
      return isInitialized;
    }

    _initializing = body().whenComplete(() {
      _initializing = null;
    });

    return _initializing!;
  });

  Future<void> sync() => _enqueue("sync", () async => await _sync());

  /// Only use for Read operations, not for Write operations.
  Future<T> withDB<T>(Future<T> Function(Database db) callback) =>
      _db != null && _db!.isOpen
      ? callback(_db!)
      : () async {
          await _init();
          return _enqueue<T>("withDB", () async {
            return callback(_db!);
          });
        }();

  /// Only use for Read operations, not for Write operations.
  Future<T> withLocalDb<T>(Future<T> Function(Database db) callback) =>
      _localDb != null && _localDb!.isOpen
      ? callback(_localDb!)
      : () async {
          await _init();
          return _enqueue<T>("withLocalDb", () async {
            return callback(_localDb!);
          });
        }();

  Future<T> withTransaction<T>(Future<T> Function(Transaction txn) callback) =>
      _db != null && _db!.isOpen
      ? _enqueue<T>("dbTransaction", () async {
          return await _db!.transaction((txn) async {
            return await callback(txn);
          });
        })
      : () async {
          await _init();
          return _enqueue<T>("withTransaction", () async {
            return await _db!.transaction((txn) async {
              return await callback(txn);
            });
          });
        }();

  Future<T> withLocalTransaction<T>(
    Future<T> Function(Transaction localTxn) callback,
  ) => _localDb != null && _localDb!.isOpen
      ? _enqueue<T>("localDbTransaction", () async {
          return await _localDb!.transaction((localTxn) async {
            return await callback(localTxn);
          });
        })
      : () async {
          await _init();
          return _enqueue<T>("withLocalTransaction", () async {
            return await _localDb!.transaction((localTxn) async {
              return await callback(localTxn);
            });
          });
        }();

  Future<T> withNestedTransaction<T>(
    Future<T> Function(Transaction txn, Transaction localTxn) callback,
  ) => _db != null && _db!.isOpen && _localDb != null && _localDb!.isOpen
      ? _enqueue<T>("nestedTransaction", () async {
          return await _db!.transaction((txn) async {
            return await _localDb!.transaction((localTxn) async {
              return await callback(txn, localTxn);
            });
          });
        })
      : () async {
          await _init();
          return _enqueue<T>("withNestedTransaction", () async {
            return await _db!.transaction((txn) async {
              return await _localDb!.transaction((localTxn) async {
                return await callback(txn, localTxn);
              });
            });
          });
        }();

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
          RemoteFileMeta(key: dirKey, etag: ''),
          txn: txn,
          localTxn: localTxn,
          fields: ['key', 'etag'],
        );
      }
    }
  }

  /// Add or update a file in the database, marking it as present in the remote.
  Future<RemoteFile?> addOrUpdateFile(
    RemoteFileMeta file, {
    String? oldEtag,
    required Transaction txn,
    required Transaction localTxn,
    bool ifPresent = false,
    List<String>? fields,
  }) async {
    Future<RemoteFile?> body() async {
      final data = file.toRow();
      data['present'] = 1;
      final op = (
        key: file.key,
        type: OpType.addOrUpdate,
        metadata: data,
        oldEtag: oldEtag,
        appliedToDBEtag: null,
        ifPresent: ifPresent,
        fields: fields,
      );

      Future<RemoteFile?> callback(
        Operation op,
        Transaction? txn,
        Transaction localTxn,
      ) async {
        await _addOrUpdateOp(op, txn: localTxn);
        final remoteFile = await _applyAddOrUpdate(op, txn: txn);
        await _applyOp(file.key, txn: localTxn);
        return remoteFile;
      }

      return await callback(op, txn, localTxn);
    }

    return await body();
  }

  /// Delete a file from the database, marking it as not present in the remote.
  Future<void> deleteFile(
    String key, {
    String? oldEtag,
    required Transaction txn,
    required Transaction localTxn,
  }) async {
    Future<void> body() async {
      final op = (
        key: key,
        type: OpType.remove,
        metadata: null,
        oldEtag: oldEtag,
        appliedToDBEtag: null,
        ifPresent: true,
        fields: null,
      );

      Future<void> callback(
        Operation op,
        Transaction txn,
        Transaction localTxn,
      ) async {
        await _addOrUpdateOp(op, txn: localTxn);
        await _applyRemove(op, txn: txn);
        await _applyOp(key, txn: localTxn);
      }

      return await callback(op, txn, localTxn);
    }

    return await body();
  }

  ({String where, List<Object?> whereArgs}) filesByDirQueryArgs(
    String dir, {
    bool includeSelf = false,
    bool recursive = true,
    bool ifPresent = true,
    bool includeDirs = true,
    bool includeFiles = true,
  }) {
    String where;
    List<Object?> whereArgs;

    final actualDir = s3KeyFromKey(dir);

    if (recursive) {
      if (dir.isEmpty) {
        // Recursive, root
        where = '(1)';
        whereArgs = [];
      } else {
        // Recursive, non-root
        where = '(key LIKE ?)';
        whereArgs = ['$actualDir%'];
      }
    } else {
      if (dir.isEmpty) {
        // Non-recursive, root
        where = '''
          (
            instr(key, '/') = 0
            OR (
              substr(key, -1) = '/'
              AND length(key) - length(replace(key, '/', '')) = 1
            )
          )
          ''';
        whereArgs = [];
      } else {
        // Non-recursive, non-root
        where = '''
          (
            key LIKE ?
            AND (
              instr(substr(key, length(?) + 1), '/') = 0
              OR
              instr(substr(key, length(?) + 1), '/') =
                length(substr(key, length(?) + 1))
            )
          )
          ''';
        whereArgs = ['$actualDir%', actualDir, actualDir, actualDir];
      }
    }

    // Additional filters

    if (ifPresent) {
      where += ' AND present = 1';
    }

    if (!includeSelf) {
      where += ' AND key != ?';
      whereArgs.add(actualDir);
    }

    if (!includeDirs && !includeFiles) {
      return (where: '0', whereArgs: []);
    }

    if (includeDirs != includeFiles) {
      where += includeDirs
          ? " AND substr(key, -1) = '/'"
          : " AND substr(key, -1) != '/'";
    }

    return (where: where, whereArgs: whereArgs);
  }

  /// Clean up old deleted entries that are no longer needed
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

  /// Clear all present files in the database, marking them as deleted, to be added back later if they are still present on the remote.
  /// This is used when a full refresh of the remote files is needed.
  Future<void> clear() => _enqueue("clear", () async {
    await _db?.update('remotefiles', {
      'present': 0,
      'deletedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
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
            CREATE INDEX IF NOT EXISTS idx_remotefiles_key
            ON remotefiles (key)
          ''');
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

  Future<void> _addOrUpdateOp(Operation op, {Transaction? txn}) async {
    await (txn ?? _localDb)?.execute(
      '''INSERT OR REPLACE INTO operations
        (key, type, row, oldEtag, appliedToDBEtag)
        VALUES (?, ?, ?, ?, ?)''',
      [
        op.key,
        op.type.name,
        op.metadata == null ? null : jsonEncode(op.metadata!),
        op.oldEtag,
        op.appliedToDBEtag,
      ],
    );
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
      return (
        key: rowJson['key'] as String,
        type: OpType.values.firstWhere(
          (e) => e.name == (rowJson['type'] as String),
        ),
        metadata: (rowJson['row'] as Map<String, dynamic>?) != null
            ? jsonDecode(rowJson['row'] as String) as Map<String, dynamic>
            : null,
        oldEtag: rowJson['oldEtag'] as String?,
        appliedToDBEtag: rowJson['appliedToDBEtag'] as String?,
        ifPresent: rowJson['ifPresent'] as bool? ?? false,
        fields: (rowJson['fields'] as List<dynamic>?)?.cast<String>(),
      );
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

  Future<RemoteFile?> _applyAddOrUpdate(
    Operation op, {
    Transaction? txn,
  }) async {
    if (op.metadata == null) {
      throw ArgumentError('Operation metadata cannot be null for addOrUpdate');
    }

    String key = p.s3.join(
      profileNamePlaceholder,
      p.s3.relative(op.metadata!['key'] as String, from: profile.name),
    );
    key = key == profileNamePlaceholder ? p.asDir(profileNamePlaceholder) : key;
    final values = {
      for (final field in remoteFileFields)
        if (field == keyColumn)
          'key': key
        else if (op.metadata!.containsKey(field) && op.metadata![field] != null)
          field: op.metadata![field] ?? (field == 'present' ? 1 : null),
    };
    final updateFields = values.keys.toList();
    final conflictUpdateClause = updateFields
        .map((field) => '$field = excluded.$field')
        .join(', ');

    if (!op.ifPresent) {
      await (txn ?? _db)?.execute(
        '''
          INSERT INTO remotefiles (
            ${updateFields.join(', ')}
          )
          VALUES (
            ${List.filled(values.length, '?').join(', ')}
          )
          ON CONFLICT(key) DO UPDATE SET
            $conflictUpdateClause
          WHERE
            ? IS NULL
            OR remotefiles.etag = ?;
        ''',
        [
          ...values.values,
          // WHERE parameters
          op.oldEtag,
          op.oldEtag,
        ],
      );
    } else {
      await (txn ?? _db)?.update(
        'remotefiles',
        values,
        where: 'key = ? AND ( ? IS NULL OR etag = ?)',
        whereArgs: [
          p.s3.join(
            profileNamePlaceholder,
            p.s3.relative(op.key, from: profile.name),
          ),
          op.oldEtag,
          op.oldEtag,
        ],
      );
    }
    return await (txn ?? _db)
        ?.query(
          'remotefiles',
          where: 'key = ?',
          whereArgs: [
            p.s3.join(
              profileNamePlaceholder,
              p.s3.relative(op.key, from: profile.name),
            ),
          ],
          columns: remoteFileFields,
        )
        .then((rows) {
          if (rows.isEmpty) {
            return null;
          }
          return RemoteFile.fromRow(rows.first);
        });
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
        '${p.s3.join(profileNamePlaceholder, p.s3.relative(op.key, from: profile.name))}%',
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
            if (op.type == OpType.addOrUpdate && op.metadata != null) {
              await _applyAddOrUpdate(op, txn: txn);
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
      RemoteFile remote;
      try {
        remote = await profile.headObject(_key);
      } catch (e) {
        if (e is S3Exception && e.code == 404) {
          return false;
        }
        rethrow;
      }

      Job job = DownloadJob(
        localFile: _file,
        remoteKey: _key,
        bytes: remote.size,
        md5: () {
          final hex = remote.etag;

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
