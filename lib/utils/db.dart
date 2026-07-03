import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:files3/models.dart';
import 'package:files3/helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/hash_util.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/s3_file_manager.dart';

Future<void> _lastOperation = Future.value();

int id = 0;
Future<T> _enqueue<T>(String name, Future<T> Function() action) async {
  final waitingFor = _lastOperation;
  id++;

  debugPrint('QUEUE: $id [$name] waiting for previous');

  await waitingFor;

  // debugPrint('QUEUE: $id [$name] previous completed');

  final future = () async {
    debugPrint('QUEUE: $id [$name] ACTION START');
    try {
      final result = await action();
      debugPrint('QUEUE: $id [$name] ACTION END');
      return result;
    } catch (e) {
      debugPrint('QUEUE: $id [$name] ACTION ERROR: $e');
      rethrow;
    }
  }();

  // debugPrint('QUEUE: $id [$name] updating _lastOperation');

  _lastOperation = future.then<void>(
    (_) {
      // debugPrint('QUEUE: $id [$name] _lastOperation completed');
    },
    onError: (e) {
      // debugPrint('QUEUE: $id [$name] _lastOperation failed: $e');
    },
  );

  // debugPrint('QUEUE: $id [$name] returning');

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
  final ValueNotifier<String?> etag = ValueNotifier<String?>(null);
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
    etag.value = ConfigManager.getString('${profile.name}.dbETag');
    etag.addListener(() async {
      if (etag.value != null) {
        await ConfigManager.setString('${profile.name}.dbETag', etag.value!);
      }
    });
    _init();
  }

  static String profileNamePlaceholder = '\$s3_files_profile_name';

  String get keyColumn => "'${profile.name}' || substr(key, 23) AS key";

  String get filteredKeyColumn =>
      "'${profile.name}' || substr(filtered.key, 23) AS key";

  List<String> get remoteFileFields => [
    'key',
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
    'dirCount',
    'fileCount',
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

    return await _initializing!;
  });

  Future<void> sync() async {
    await _init();
    await _enqueue("sync", () async => await _sync());
  }

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
    String name,
  ) => _db != null && _db!.isOpen && _localDb != null && _localDb!.isOpen
      ? _enqueue<T>("nestedTransaction $name", () async {
          return await _db!.transaction((txn) async {
            return await _localDb!.transaction((localTxn) async {
              return await callback(txn, localTxn);
            });
          });
        })
      : () async {
          await _init();
          return _enqueue<T>("withNestedTransaction $name", () async {
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
        if (remoteFile != null) {
          await _applyOp(op, file: remoteFile, txn: localTxn);
        }
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
        await _applyOp(op, txn: localTxn);
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
    if (!p.isDir(dir)) {
      return (where: '0', whereArgs: []);
    }

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
        where = '(remotefiles.key LIKE ?)';
        whereArgs = ['$actualDir%'];
      }
    } else {
      if (dir.isEmpty) {
        // Non-recursive, root
        where = '''
          (
            instr(remotefiles.key, '/') = 0
            OR (
              substr(remotefiles.key, -1) = '/'
              AND length(remotefiles.key) - length(replace(remotefiles.key, '/', '')) = 1
            )
          )
          ''';
        whereArgs = [];
      } else {
        // Non-recursive, non-root
        where = '''
          (
            remotefiles.key LIKE ?
            AND (
              instr(substr(remotefiles.key, length(?) + 1), '/') = 0
              OR
              instr(substr(remotefiles.key, length(?) + 1), '/') =
                length(substr(remotefiles.key, length(?) + 1))
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
      where += ' AND remotefiles.key != ?';
      whereArgs.add(actualDir);
    }

    if (!includeDirs && !includeFiles) {
      return (where: '0', whereArgs: []);
    }

    if (includeDirs != includeFiles) {
      where += includeDirs
          ? " AND substr(remotefiles.key, -1) = '/'"
          : " AND substr(remotefiles.key, -1) != '/'";
    }

    where +=
        " AND remotefiles.key NOT LIKE '$profileNamePlaceholder/metadata.db'";

    return (where: where, whereArgs: whereArgs);
  }

  String makeQuery({
    List<String>? columns,
    List<String>? rawColumns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    columns ??= profile.metaDB.remoteFileFields;
    rawColumns ??= profile.metaDB.remoteFileFields;

    var i = 0;
    final whereClause =
        where?.replaceAllMapped(RegExp(r'\?'), (_) {
          if (i >= (whereArgs?.length ?? 0)) {
            throw ArgumentError('More ? placeholders than arguments');
          }
          return '${whereArgs?[i++] is String ? "'${whereArgs?[i - 1]}'" : whereArgs?[i - 1] ?? 'NULL'}';
        }) ??
        '';

    final aggColumnSet = {'size', 'lastModified', 'dirCount', 'fileCount'};

    final mergeColumns = {
      for (final col in columns.where(aggColumnSet.contains))
        col:
            "CASE WHEN substr(allrows.key, -1) = '/' THEN agg.$col ELSE allrows.$col END AS $col",
    };

    const aggregateExpressions = {
      'size':
          "COALESCE(SUM(CASE WHEN substr(allrows.key, -1) != '/' THEN allrows.size END), 0)",
      'lastModified':
          "COALESCE(MAX(CASE WHEN substr(allrows.key, -1) != '/' THEN allrows.lastModified END), 0)",
      'dirCount':
          "COALESCE(SUM(CASE WHEN substr(allrows.key, -1) = '/' AND allrows.key != dirs.key THEN 1 ELSE 0 END), 0)",
      'fileCount':
          "COALESCE(SUM(CASE WHEN substr(allrows.key, -1) != '/' THEN 1 ELSE 0 END), 0)",
    };

    final allRowsSubQueryLines = [
      'SELECT ${rawColumns.join(', ')}',
      'FROM remotefiles',
      'WHERE remotefiles.key NOT LIKE \'$profileNamePlaceholder/metadata.db\'',
    ];

    final filteredSubQueryLines = [
      'SELECT key FROM allrows AS remotefiles',
      if (whereClause.isNotEmpty) 'WHERE $whereClause',
    ];

    final aggSubQueryLines = [
      'SELECT',
      ...mergeColumns.keys.map(
        (col) => '\t${aggregateExpressions[col]} AS $col,',
      ),
      'dirs.key as key',
      'FROM filtered AS dirs',
      'LEFT JOIN allrows',
      '\tON allrows.present = 1',
      '\t\tAND allrows.key LIKE dirs.key || \'%\'',
      'WHERE substr(dirs.key,-1)=\'/\'',
      'GROUP BY dirs.key',
    ];

    final subQueryLines = [
      'WITH',
      'allrows AS (',
      ...allRowsSubQueryLines.map((l) => '\t$l'),
      '),',
      'filtered AS (',
      ...filteredSubQueryLines.map((l) => '\t$l'),
      '),',
      'agg AS (',
      ...aggSubQueryLines.map((l) => '\t$l'),
      ')',
      'SELECT',
      '${profile.metaDB.filteredKeyColumn},',
      [
        ...mergeColumns.values,
        ...profile.metaDB.remoteFileFields
            .sublist(1)
            .where((c) => !mergeColumns.containsKey(c))
            .map((c) => 'allrows.$c'),
      ].join(',\n\t'),
      'FROM filtered',
      'JOIN allrows ON filtered.key = allrows.key',
      'LEFT JOIN agg ON filtered.key = agg.key',
    ];

    final queryLines = [
      'SELECT ${columns.join(',\n\t')}',
      'FROM',
      if (mergeColumns.isEmpty) ...[
        'remotefiles',
        'WHERE $whereClause',
      ] else ...[
        '(',
        ...subQueryLines.map((l) => '\t$l'),
        ')',
      ],
      if (groupBy != null) 'GROUP BY $groupBy',
      if (having != null) 'HAVING $having',
      if (orderBy != null) 'ORDER BY $orderBy',
      if (limit != null) 'LIMIT $limit',
      if (offset != null) 'OFFSET $offset',
    ];

    final query = queryLines.join('\n');

    return query;
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
              ifPresent INT NOT NULL DEFAULT 0,
              fields TEXT DEFAULT NULL
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
              deletedAt INT,
              dirCount INTEGER DEFAULT 0,
              fileCount INTEGER DEFAULT 0,
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

  Future<void> _applyOp(
    Operation op, {
    RemoteFile? file,
    Transaction? txn,
  }) async {
    await (txn ?? _localDb)?.update(
      'operations',
      {
        'key': op.key,
        'type': op.type.name,
        'row': op.type == OpType.remove
            ? null
            : file != null
            ? jsonEncode(file.toRow())
            : op.metadata != null
            ? jsonEncode(op.metadata!)
            : null,
        'oldEtag': op.oldEtag,
        'appliedToDBEtag': etag.value,
      },
      where: 'key = ?',
      whereArgs: [op.key],
    );
  }

  Future<List<Operation>> _getOps() async {
    final rows = await _localDb?.query('operations');
    if (rows == null) {
      return [];
    }

    return rows.map((row) {
      final metadataJson = row['row'] as String?;
      final fieldsJson = row['fields'] as String?;

      return (
        key: row['key'] as String,
        type: OpType.values.byName(row['type'] as String),
        metadata: metadataJson != null
            ? (jsonDecode(metadataJson) as Map).cast<String, Object?>()
            : null,
        oldEtag: row['oldEtag'] as String?,
        appliedToDBEtag: row['appliedToDBEtag'] as String?,
        ifPresent: (row['ifPresent'] as int) != 0,
        fields: fieldsJson != null
            ? List<String>.from(jsonDecode(fieldsJson) as List)
            : null,
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
      for (final field in op.metadata!.keys)
        if (field == 'key')
          'key': key
        else if (op.metadata![field] != null)
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
          if (op.appliedToDBEtag != etag.value) {
            if (op.type == OpType.addOrUpdate && op.metadata != null) {
              final file = await _applyAddOrUpdate(op, txn: txn);
              await _applyOp(op, file: file, txn: localTxn);
            } else if (op.type == OpType.remove) {
              await _applyRemove(op, txn: txn);
              await _applyOp(op, txn: localTxn);
            }
          }
        }
      });
    });
  }

  Future<bool?> _pullDb() async {
    try {
      RemoteFile remote;
      try {
        remote = await profile.headObject(_key, nosave: true);
      } catch (e) {
        if (e is S3Exception && e.code == 404) {
          if (kDebugMode) {
            debugPrint('Remote DB does not exist, proceeding with local DB');
          }
          return false;
        }
        rethrow;
      }

      if (remote.etag == etag.value) {
        // No changes to pull, return true
        return true;
      }

      Job job = DownloadJob(
        localFile: _file,
        remoteKey: _key,
        bytes: remote.size,
        md5: etagToDigest(remote.etag),
        profile: profile,
        noUpdateMeta: true,
      );

      isInitialized = false;
      _initializing =
          () async {
            if (_db != null && _db!.isOpen) {
              await _db!.close();
            }
            final result = await job.start();
            job.dispose();
            await _openDb();
            if (result != null &&
                result.statusCode >= 200 &&
                result.statusCode < 300) {
              etag.value = result.headers['etag']?[0].replaceAll('"', '');
            } else {
              if (kDebugMode) {
                debugPrint(
                  'Pull failed with status code: ${result?.statusCode}',
                );
              }
            }
            isInitialized = true;
            return true;
          }().catchError((e) {
            job.dispose();
            throw e;
          });

      return await _initializing!;
    } catch (e) {
      if (await _file.exists()) {
        _openDb();
      }
      return null;
    }
  }

  Future<bool?> _pushDb() async {
    final md5 = await HashUtil(_file).md5Hash();
    if (etag.value != null && md5 == etagToDigest(etag.value!)) {
      // No changes to push, return true
      return true;
    }

    bool canPush = true;
    try {
      final remote = await profile.headObject(_key, nosave: true);
      canPush = remote.etag != etag.value ? false : true;
    } catch (e) {
      if (e is S3Exception && e.code == 404) {
        canPush = true;
        etag.value = null;
      }
    }

    if (canPush != true) {
      // ETag mismatch, return false
      return false;
    }

    Job job = UploadJob(
      localFile: _file,
      remoteKey: _key,
      bytes: _file.lengthSync(),
      md5: md5,
      profile: profile,
      noUpdateMeta: true,
      ifMatch: etag.value != null ? '"${etag.value}"' : null,
    );
    profile.accessible.value = true;
    final result = await job.start();
    job.dispose();
    if (result == null) {
      if (kDebugMode) {
        debugPrint('Push failed: Server did not return a response');
      }
      profile.accessible.value = false;
      return null;
    }
    if (result.statusCode >= 200 && result.statusCode < 300) {
      etag.value = result.headers['etag']?[0].replaceAll('"', '');
      return true;
    } else if (result.statusCode == 412 || result.statusCode == 409) {
      if (kDebugMode) {
        debugPrint('Push failed due to etag mismatch.');
      }
      return false;
    } else {
      if (kDebugMode) {
        debugPrint('Push failed with status code: ${result.statusCode}');
      }
      return null;
    }
  }
}
