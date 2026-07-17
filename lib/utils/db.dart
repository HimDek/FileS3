import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:files3/models/models.dart';
import 'package:files3/helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/hash_util.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/s3_file_manager.dart';

Future<void> _lastOperation = Future.value();

// int id = 0;
Future<T> _enqueue<T>(String name, Future<T> Function() action) async {
  final waitingFor = _lastOperation;
  // id++;

  // debugPrint('QUEUE: $id [$name] waiting for previous');

  await waitingFor;

  // debugPrint('QUEUE: $id [$name] previous completed');

  final future = () async {
    // debugPrint('QUEUE: $id [$name] ACTION START');
    try {
      final result = await action();
      // debugPrint('QUEUE: $id [$name] ACTION END');
      return result;
    } catch (e) {
      // debugPrint('QUEUE: $id [$name] ACTION ERROR: $e');
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
  final Profile profile;
  final ValueNotifier<String?> etag = ValueNotifier<String?>(null);
  late final String _key = p.s3.join(profile.name, 'metadata.json');
  late final File _file = File(
    p.context.joinAll([
      Main.documentsDir,
      'profiles',
      profile.name,
      'metadata',
      'metadata.json',
    ]),
  );
  late final File _localFile = File(
    p.context.joinAll([
      Main.documentsDir,
      'profiles',
      profile.name,
      'metadata',
      'metadata.db',
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
      if (!await _file.exists()) {
        bool pooled = await _pullDb();
        if (pooled == false) {
          // No remote DB exists, so we can proceed
          await _openDb();
        }
      } else {
        // Local DB exists, so we can open it
        await _openDb();
      }
      if (_db != null) {
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

  Future<T> withTransaction<T>(
    Future<T> Function(Transaction txn) callback, {
    String? debugLabel,
  }) => _db != null && _db!.isOpen
      ? _enqueue<T>(debugLabel ?? "dbTransaction", () async {
          return await _db!.transaction((txn) async {
            return await callback(txn);
          });
        })
      : () async {
          await _init();
          return _enqueue<T>(debugLabel ?? "withTransaction", () async {
            return await _db!.transaction((txn) async {
              return await callback(txn);
            });
          });
        }();

  Future<void> addIntermediateDirectories(
    String key,
    Set<String> addedDirs, {
    required Transaction txn,
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
          fields: ['key', 'etag'],
        );
      }
    }
  }

  /// Add or update a file in the database, marking it as present in the remote.
  Future<bool> addOrUpdateFile(
    RemoteFileMeta file, {
    String? oldEtag,
    required Transaction txn,
    bool ifPresent = false,
    List<String>? fields,
  }) async {
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
    final addedExisting = await _applyAddOrUpdate(
      op,
      txn: txn,
      ifNotDeleted: true,
    );
    if (addedExisting == 0) {
      final addedNew = await _applyAddOrUpdate(
        op,
        txn: txn,
        ifNotDeleted: false,
      );
      if (addedNew > 0) {
        await _addOrUpdateOp(op, txn: txn);
        await _applyOp(op, txn: txn);
      }
      return addedNew > 0;
    }
    return addedExisting > 0;
  }

  /// Delete a file from the database, marking it as not present in the remote.
  Future<bool> deleteFile(
    String key, {
    String? oldEtag,
    required Transaction txn,
  }) async {
    final op = (
      key: key,
      type: OpType.remove,
      metadata: null,
      oldEtag: oldEtag,
      appliedToDBEtag: null,
      ifPresent: true,
      fields: null,
    );
    final changed = await _applyRemove(op, txn: txn);
    if (changed > 0) {
      await _addOrUpdateOp(op, txn: txn);
      await _applyOp(op, txn: txn);
    }
    return changed > 0;
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
        " AND remotefiles.key NOT LIKE '$profileNamePlaceholder/metadata.json'";

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
      'WHERE remotefiles.key NOT LIKE \'$profileNamePlaceholder/metadata.json\'',
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

  Future<Iterable<RemoteFile>> getDeleted() async {
    final rows = await _db?.query(
      'remotefiles',
      columns: [keyColumn, remoteFileFields.sublist(1).join(', ')],
      where: 'present = 0 AND deletedAt IS NOT NULL',
    );
    if (rows == null) {
      return Iterable.empty();
    }
    return rows.map((row) => RemoteFile.fromRow(row));
  }

  /// Delete all files in the database that are not present in the remote, marking them as deleted.
  Future<bool> clean({required Transaction txn}) async {
    final keys = await txn.query(
      'remotefiles',
      columns: ['key'],
      where: 'present = 0 AND deletedAt IS NULL',
    );
    bool deletedAny = false;
    for (final row in keys) {
      final key = row['key'] as String;
      bool deleted = await deleteFile(key, txn: txn);
      if (deleted) {
        deletedAny = true;
      }
    }
    return deletedAny;
  }

  /// Clear all present files in the database, marking them as not present but not as deleted
  /// to be added back later if they are still present on the remote.
  /// This is used when a full refresh of the remote files is needed.
  Future<int?> clear(String dir, {required Transaction txn}) async {
    final args = filesByDirQueryArgs(
      dir,
      includeSelf: true,
      recursive: true,
      ifPresent: true,
      includeDirs: true,
      includeFiles: true,
    );
    return await txn.update(
      'remotefiles',
      {'present': 0, 'deletedAt': null},
      where: args.where,
      whereArgs: args.whereArgs,
    );
  }

  /// Clean up old deleted entries that are no longer needed
  Future<int?> clearDeleted() => _enqueue("clearDeleted", () async {
    return await _db?.delete(
      'remotefiles',
      where: 'present = 0 AND deletedAt IS NOT NULL AND deletedAt < ?',
      whereArgs: [
        DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch,
      ],
    );
  });

  /// Delete the database files and close the connections. This is used when a profile is deleted or reset.
  Future<void> deleteDB() async {
    await _db?.close();
    await _file.delete();
    await _localFile.delete();
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
              CONSTRAINT present_deletedAt CHECK (present = 0 OR deletedAt IS NULL)
            )
          ''');
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
      onOpen: (db) async {
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
    await (txn ?? _db)?.execute(
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

  Future<void> _applyOp(Operation op, {Transaction? txn}) async {
    await (txn ?? _db)?.update(
      'operations',
      {
        'key': op.key,
        'type': op.type.name,
        'row': op.type == OpType.remove
            ? null
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

  Future<int?> _deleteOp(String key, {Transaction? txn}) async {
    return await (txn ?? _db)?.delete(
      'operations',
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  Future<List<Operation>> _getOps() async {
    final rows = await _db?.query('operations');
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
    await _db?.execute(
      'DELETE FROM operations WHERE appliedToDBEtag is NOT NULL',
    );
  }

  Future<bool> _sync() async {
    while (_db != null) {
      bool pulled = await _pullDb();
      if (!pulled) {
        return false;
      }

      final ops = await _getOps();
      if (ops.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[MetaDB._sync] ${profile.name} ${ops.length} local changes to apply',
          );
        }
        await _applyOperations(ops);
      }
      final applied =
          await _db?.transaction((txn) async {
            return await txn.query(
              'operations',
              where: 'appliedToDBEtag IS NOT NULL',
            );
          }) ??
          [];
      if (applied.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[MetaDB._sync] ${profile.name} ${applied.length} local changes to push',
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint('[MetaDB._sync] ${profile.name} No local changes to push');
        }
        return true;
      }

      final pushed = await _pushDb();

      if (pushed == true) {
        if (kDebugMode) {
          debugPrint(
            '[MetaDB._sync] ${profile.name} Push successful, cleaning up operations',
          );
        }
        await _cleanOps();
        return true;
      } else if (pushed == false) {
        continue;
      }
      break;
    }
    return false;
  }

  Future<int> _applyAddOrUpdate(
    Operation op, {
    Transaction? txn,
    bool ifNotDeleted = false,
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
        else if (field == 'deletedAt')
          'deletedAt': op.metadata![field]
        else if (op.metadata![field] != null)
          field: op.metadata![field] ?? (field == 'present' ? 1 : null),
    };
    final updateFields = values.keys.toList();
    final conflictUpdateClause = updateFields
        .map((field) => '$field = excluded.$field')
        .join(', ');

    int? changed = 0;
    if (!op.ifPresent) {
      final changedCondition = updateFields
          .map((c) => 'remotefiles.$c IS NOT excluded.$c')
          .join(' OR ');
      changed = await (txn ?? _db)?.rawUpdate(
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
            (? IS NULL OR remotefiles.etag = ?) AND ($changedCondition)
            ${ifNotDeleted ? 'AND remotefiles.deletedAt IS NULL' : ''}
        ''',
        [
          ...values.values,
          // WHERE parameters
          op.oldEtag,
          op.oldEtag,
        ],
      );
    } else {
      final changedCondition = updateFields
          .map((c) => '$c IS NOT ?')
          .join(' OR ');
      changed = await (txn ?? _db)?.update(
        'remotefiles',
        values,
        where:
            'key = ? AND ( ? IS NULL OR etag = ?) AND ($changedCondition) ${ifNotDeleted ? 'AND remotefiles.deletedAt IS NULL' : ''}',
        whereArgs: [
          p.s3.join(
            profileNamePlaceholder,
            p.s3.relative(op.key, from: profile.name),
          ),
          op.oldEtag,
          op.oldEtag,
          ...updateFields.map((c) => values[c]),
        ],
      );
    }
    return changed ?? 0;
  }

  Future<int> _applyRemove(Operation op, {Transaction? txn}) async {
    final time = DateTime.now().toUtc().millisecondsSinceEpoch;
    return (await (txn ?? _db)?.update(
          'remotefiles',
          {'present': 0, 'deletedAt': time},
          where:
              'key LIKE ? AND ( ? IS NULL OR etag = ?) AND (present IS NOT 0 OR deletedAt IS NOT ?)',
          whereArgs: [
            '${p.s3.join(profileNamePlaceholder, p.s3.relative(op.key, from: profile.name))}%',
            op.oldEtag,
            op.oldEtag,
            time,
          ],
        )) ??
        0;
  }

  Future<void> _applyOperations(List<Operation> ops) async {
    return await _db?.transaction((txn) async {
      return await _db?.transaction((txn) async {
        for (final op in ops) {
          if (op.appliedToDBEtag != etag.value) {
            int changed = 0;
            if (op.type == OpType.addOrUpdate && op.metadata != null) {
              changed = await _applyAddOrUpdate(op, txn: txn);
            } else if (op.type == OpType.remove) {
              changed = await _applyRemove(op, txn: txn);
            }
            if (changed > 0) {
              await _applyOp(op, txn: txn);
            } else {
              await _deleteOp(op.key, txn: txn);
            }
          }
        }
      });
    });
  }

  /// Pull if any remote changes exist or if the local DB does not exist.
  /// Returns true if the pull was successful or if no pull was needed, false if the pull failed.
  Future<bool> _pullDb() async {
    try {
      RemoteFile remote;
      try {
        remote = await profile.headObject(_key, nosave: true);
      } catch (e) {
        if (e is S3Exception && e.code == 404) {
          if (kDebugMode) {
            debugPrint(
              '[MetaDB._pullDb] ${profile.name} Remote DB does not exist',
            );
          }
          return true;
        }
        rethrow;
      }

      if (remote.etag == etag.value) {
        if (kDebugMode) {
          debugPrint(
            '[MetaDB._pullDb] ${profile.name} Local DB is up to date with remote DB',
          );
        }
        return true;
      }

      if (kDebugMode) {
        debugPrint(
          '[MetaDB._pullDb] ${profile.name} Pulling remote DB with etag: ${remote.etag}',
        );
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
            final result = await job.start();
            job.dispose();
            if (result != null &&
                result.statusCode >= 200 &&
                result.statusCode < 300) {
              etag.value = result.headers['etag']?[0].replaceAll('"', '');
            } else {
              if (kDebugMode) {
                debugPrint(
                  '[MetaDB._pullDb] ${profile.name} Pull failed with status code: ${result?.statusCode}',
                );
              }
            }
            if (kDebugMode) {
              debugPrint('[MetaDB._pullDb] ${profile.name} Pull completed');
            }
            await withTransaction((txn) async {
              final json =
                  jsonDecode(await _file.readAsString())
                      as List<Map<String, Object?>>;
              txn.delete('remotefiles');
              for (final entry in json) {
                await txn.insert(
                  'remotefiles',
                  entry,
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              }
            });
            isInitialized = true;
            return true;
          }().catchError((e) {
            job.dispose();
            throw e;
          });

      return await _initializing!;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[MetaDB._pullDb] ${profile.name} Pull failed with error: $e',
        );
      }
      if (await _file.exists()) {
        _openDb();
      }
      return false;
    }
  }

  /// Push local changes to the remote DB.
  /// Returns true if the push was successful, false if the push failed due to etag mismatch, and null if the push failed due to other reasons.
  Future<bool?> _pushDb() async {
    final md5 = await HashUtil(_file).md5Hash();

    bool canPush = true;
    try {
      final remote = await profile.headObject(_key, nosave: true);
      canPush = remote.etag != etag.value ? false : true;
    } catch (e) {
      if (e is S3Exception && e.code == 404) {
        canPush = true;
        etag.value = null;
        if (kDebugMode) {
          debugPrint(
            '[MetaDB._pushDb] ${profile.name} Remote DB does not exist, proceeding with push',
          );
        }
      }
      if (kDebugMode) {
        debugPrint(
          '[MetaDB._pushDb] ${profile.name} Push failed with error: $e',
        );
      }
      return null;
    }

    if (canPush != true) {
      if (kDebugMode) {
        debugPrint(
          '[MetaDB._pushDb] ${profile.name} Push failed: Remote DB has changed since last pull. ETag mismatch.',
        );
      }
      return false;
    }

    final rows = await _db?.query('remotefiles');
    await _file.writeAsString(jsonEncode(rows ?? []));

    Job job = UploadJob(
      localFile: _file,
      remoteKey: _key,
      bytes: await _file.length(),
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
        debugPrint(
          '[MetaDB._pushDb] ${profile.name} Push failed: Server did not return a response',
        );
      }
      profile.accessible.value = false;
      return null;
    }
    if (result.statusCode >= 200 && result.statusCode < 300) {
      etag.value = result.headers['etag']?[0].replaceAll('"', '');
      return true;
    } else if (result.statusCode == 412 || result.statusCode == 409) {
      if (kDebugMode) {
        debugPrint(
          '[MetaDB._pushDb] ${profile.name} Push failed due to etag mismatch.',
        );
      }
      return false;
    } else {
      if (kDebugMode) {
        debugPrint(
          '[MetaDB._pushDb] ${profile.name} Push failed with status code: ${result.statusCode}',
        );
      }
      return null;
    }
  }
}
