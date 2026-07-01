import 'dart:io';
import 'dart:convert';
import 'package:files3/utils/db.dart';
import 'package:flutter/material.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';

class FileProps {
  final String key;
  final int size;
  final DateTime? lastModified;
  final Job? job;
  final String? url;

  FileProps({
    required this.key,
    required this.size,
    this.lastModified,
    this.job,
    this.url,
  });
}

enum SelectionAction { copy, cut, none }

enum JobStatus { ready, running, completed, failed, blocked }

enum SortMode {
  nameAsc,
  nameDesc,
  dateAsc,
  dateDesc,
  sizeAsc,
  sizeDesc,
  typeAsc,
  typeDesc,
}

enum ViewMode { list, grid }

class ListOptions {
  SortMode sortMode;
  ViewMode viewMode;
  bool foldersFirst;
  bool group;

  ListOptions({
    this.sortMode = SortMode.nameAsc,
    this.viewMode = ViewMode.list,
    this.foldersFirst = true,
    this.group = false,
  });

  factory ListOptions.fromJson(String json) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(
      jsonDecode(json) as Map,
    );
    try {
      return ListOptions(
        sortMode: SortMode.values[data['sortMode'] as int? ?? 0],
        viewMode: ViewMode.values[data['viewMode'] as int? ?? 0],
        foldersFirst: data['foldersFirst'] as bool? ?? true,
        group: data['group'] as bool? ?? false,
      );
    } catch (e) {
      return ListOptions();
    }
  }

  String toJson() {
    return jsonEncode({
      'sortMode': sortMode.index,
      'viewMode': viewMode.index,
      'foldersFirst': foldersFirst,
      'group': group,
    });
  }

  ListOptions copyWith({
    SortMode? sortMode,
    ViewMode? viewMode,
    bool? foldersFirst,
    bool? group,
  }) {
    return ListOptions(
      sortMode: sortMode ?? this.sortMode,
      viewMode: viewMode ?? this.viewMode,
      foldersFirst: foldersFirst ?? this.foldersFirst,
      group: group ?? this.group,
    );
  }
}

class BackupMode {
  final String name;
  final String description;
  final int value;

  BackupMode({
    required this.name,
    required this.description,
    required this.value,
  });

  static final BackupMode sync = BackupMode(
    name: 'Sync',
    description:
        'Syncs the local directory with the remote directory, maintaining a local copy.',
    value: 1,
  );

  static final BackupMode upload = BackupMode(
    name: 'Upload',
    description:
        'Uploads files from the local directory to the remote directory without syncing.',
    value: 2,
  );

  static BackupMode fromValue(int value) {
    switch (value) {
      case 1:
        return sync;
      case 2:
        return upload;
      default:
        throw ArgumentError('Invalid BackupMode value: $value');
    }
  }

  static BackupMode fromName(String name) {
    switch (name.toLowerCase()) {
      case 'sync':
        return sync;
      case 'upload':
        return upload;
      default:
        throw ArgumentError('Invalid BackupMode name: $name');
    }
  }
}

class RemoteFileMeta {
  /// The unique key representing the file or directory in the remote storage profile.
  final String key;

  /// The size of the file in bytes.
  int? size;

  /// The ETag of the file, which is a unique identifier for the file's content.
  String? etag;

  /// The last modified date of the file.
  DateTime? lastModified;

  /// The creation date of the file.
  DateTime? created;

  /// The original date of the file.
  DateTime? original;

  String? contentType;

  Map<String, dynamic>? metadata;

  DateTime? deletedAt;

  (int, int)? count;

  Profile? get profile => Main.profileFromKey(key);

  RemoteFileMeta({
    required this.key,
    this.size,
    this.etag,
    this.lastModified,
    this.created,
    this.original,
    this.contentType,
    this.metadata,
    this.deletedAt,
    this.count,
  });

  Future<RemoteFile?> getFile() async {
    final file = await RemoteFile.getByKey(key);
    if (file == null) {
      return null;
    }
    return file;
  }

  /// Save or update the RemoteFile in the appropriate profile's metaDB.
  Future<RemoteFile?> save({String? oldEtag}) async {
    final addedDirs = <String>{};
    return await profile?.metaDB.withNestedTransaction((txn, localTxn) async {
      await profile?.metaDB.addIntermediateDirectories(
        key,
        addedDirs,
        txn: txn,
        localTxn: localTxn,
      );
      return await profile?.metaDB.addOrUpdateFile(
        this,
        oldEtag: oldEtag,
        txn: txn,
        localTxn: localTxn,
      );
    });
  }

  /// Update specific fields of the RemoteFile in the appropriate profile's metaDB.
  Future<RemoteFile?> update({String? oldEtag, List<String>? fields}) async {
    return await profile?.metaDB.addOrUpdateFile(
      this,
      oldEtag: oldEtag,
      ifPresent: true,
      fields: fields,
    );
  }

  @override
  String toString() {
    return key;
  }

  Map<String, Object?> toRow() {
    return {
      'key': key,
      if (size != null) 'size': size,
      if (etag != null) 'etag': etag,
      if (lastModified != null)
        'lastModified': lastModified?.millisecondsSinceEpoch,
      if (created != null) 'created': created?.millisecondsSinceEpoch,
      if (original != null) 'original': original?.millisecondsSinceEpoch,
      if (contentType != null) 'contentType': contentType,
      if (metadata != null) 'metadata': jsonEncode(metadata),
      if (deletedAt != null) 'deletedAt': deletedAt?.millisecondsSinceEpoch,
      if (count != null) 'count': '(${count!.$1}, ${count!.$2})',
    };
  }
}

class RemoteFile extends RemoteFileMeta {
  bool? get downloaded => isDownloaded[key];
  int _size;
  String _etag;
  DateTime _lastModified;
  DateTime _created;
  DateTime _original;
  String _contentType;
  Map<String, dynamic> _metadata;
  (int, int) _count;

  @override
  int get size => _size;

  @override
  set size(int? value) {
    _size = value!;
  }

  @override
  String get etag => _etag;

  @override
  set etag(String? value) {
    _etag = value!;
  }

  @override
  DateTime get lastModified => _lastModified;

  @override
  set lastModified(DateTime? value) {
    _lastModified = value!;
  }

  @override
  DateTime get created => _created;

  @override
  set created(DateTime? value) {
    _created = value!;
  }

  @override
  DateTime get original => _original;

  @override
  set original(DateTime? value) {
    _original = value!;
  }

  @override
  String get contentType => _contentType;

  @override
  set contentType(String? value) {
    _contentType = value!;
  }

  @override
  Map<String, dynamic> get metadata => _metadata;

  @override
  set metadata(Map<String, dynamic>? value) {
    _metadata = value!;
  }

  @override
  (int, int) get count => _count;

  @override
  set count((int, int)? value) {
    _count = value!;
  }

  RemoteFile({
    required super.key,
    required int size,
    required String etag,
    required DateTime? lastModified,
    required DateTime? created,
    required DateTime? original,
    required String contentType,
    required Map<String, dynamic> metadata,
    required DateTime? deletedAt,
    (int, int) count = (0, 0),
  }) : _size = size,
       _etag = etag,
       _lastModified = lastModified ?? DateTime.fromMillisecondsSinceEpoch(0),
       _created = created ?? DateTime.fromMillisecondsSinceEpoch(0),
       _original = original ?? DateTime.fromMillisecondsSinceEpoch(0),
       _contentType = contentType,
       _metadata = metadata,
       _count = count;

  static RemoteFile root = RemoteFile(
    key: '',
    size: 0,
    etag: '',
    lastModified: DateTime.fromMillisecondsSinceEpoch(0),
    created: DateTime.fromMillisecondsSinceEpoch(0),
    original: DateTime.fromMillisecondsSinceEpoch(0),
    contentType: '',
    metadata: {},
    deletedAt: null,
  );

  /// Get a RemoteFile by its key from the appropriate profile's metaDB.
  static Future<RemoteFile?> getByKey(
    String key, {
    bool ifPresent = true,
  }) async {
    if (key.isEmpty) {
      return RemoteFile.root;
    }
    final result = await Main.profileFromKey(key)?.metaDB.withDB((db) async {
      return await db.query(
        'remotefiles',
        where: ifPresent ? 'key = ? AND present = 1' : 'key = ?',
        whereArgs: [key],
      );
    });
    return result == null || result.isEmpty
        ? null
        : RemoteFile.fromRow(result.first);
  }

  static Future<Iterable<T>> getByKeys<T>(
    List<String> keys, {
    bool ifPresent = true,
    bool? distinct,
    List<String>? columns,
    String andWhere = '',
    List<Object> andWhereArgs = const [],
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final Map<Profile, List<String>> groupedKeys = {};
    for (String dir in keys) {
      final profile = Main.profileFromKey(dir);
      if (profile != null) {
        groupedKeys.putIfAbsent(profile, () => []).add(dir);
      }
    }

    final results = await Future.wait(
      groupedKeys.keys.map((profile) async {
        final result = await profile.metaDB.withDB((db) async {
          String whereClause = ifPresent
              ? 'key IN (${List.filled(groupedKeys[profile]!.length, '?').join(',')}) AND present = 1'
              : 'key IN (${List.filled(groupedKeys[profile]!.length, '?').join(',')})';
          List<Object?> whereArgs = groupedKeys[profile]!;

          whereClause += andWhere.isNotEmpty ? ' AND ($andWhere)' : '';
          whereArgs.addAll(andWhereArgs);

          return await db.query(
            'remotefiles',
            where: whereClause,
            whereArgs: whereArgs,
            columns: T == RemoteFile ? null : columns,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
          );
        });
        return result.map(
              (row) => T == RemoteFile ? RemoteFile.fromRow(row) : row as T,
            )
            as Iterable<T>;
      }),
    );

    return results.expand((x) => x);
  }

  static Future<Iterable<T>> getChildrenByKey<T>(
    String key, {
    bool recursive = true,
    bool ifPresent = true,
    bool includeDirs = true,
    bool includeFiles = true,
    bool? distinct,
    List<String>? columns,
    String andWhere = '',
    List<Object> andWhereArgs = const [],
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (!p.isDir(key)) {
      return [];
    }

    if (key.isEmpty) {
      List<T> allChildren = [];
      for (var profile in Main.profiles.values) {
        final children = await profile.metaDB.withDB<Iterable<T>>((db) async {
          final args = MetaDB.filesByDirQueryArgs(
            key,
            recursive: recursive,
            ifPresent: ifPresent,
            includeDirs: includeDirs,
            includeFiles: includeFiles,
          );
          final res = await db.query(
            'remotefiles',
            where: args.where + (andWhere.isNotEmpty ? ' AND ($andWhere)' : ''),
            whereArgs: [...args.whereArgs, ...andWhereArgs],
            columns: T == RemoteFile
                ? null
                : T == String
                ? ['key']
                : columns,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
          );
          final result = res.map(
            (row) => T == RemoteFile
                ? RemoteFile.fromRow(row) as T
                : T == String
                ? row['key'] as T
                : row as T,
          );
          return result;
        });
        allChildren.addAll(children);
      }
      return allChildren;
    }

    final profile = Main.profileFromKey(key);
    if (profile == null) {
      return [];
    }

    final children = await profile.metaDB.withDB<Iterable<T>>((db) async {
      final args = MetaDB.filesByDirQueryArgs(
        key,
        recursive: recursive,
        ifPresent: ifPresent,
        includeDirs: includeDirs,
        includeFiles: includeFiles,
      );
      final res = await db.query(
        'remotefiles',
        where: args.where + (andWhere.isNotEmpty ? ' AND ($andWhere)' : ''),
        whereArgs: [...args.whereArgs, ...andWhereArgs],
        columns: T == RemoteFile
            ? null
            : T == String
            ? ['key']
            : columns,
      );
      final result = res.map(
        (row) => T == RemoteFile
            ? RemoteFile.fromRow(row) as T
            : T == String
            ? row['key'] as T
            : row as T,
      );
      return result;
    });

    return children;
  }

  static Future<Iterable<T>> getChildrenByKeys<T>(
    Iterable<String> keys, {
    bool recursive = true,
    bool ifPresent = true,
    bool includeDirs = true,
    bool includeFiles = true,
    bool? distinct,
    List<String>? columns,
    String andWhere = '',
    List<Object> andWhereArgs = const [],
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final Map<Profile, List<String>> groupedDirs = {};
    for (String dir in keys) {
      final profile = Main.profileFromKey(dir);
      if (profile != null) {
        groupedDirs.putIfAbsent(profile, () => []).add(dir);
      }
    }

    final results = await Future.wait(
      groupedDirs.keys.map((profile) async {
        final args = groupedDirs[profile]!.map((dir) {
          return MetaDB.filesByDirQueryArgs(
            dir,
            recursive: recursive,
            ifPresent: ifPresent,
            includeDirs: includeDirs,
            includeFiles: includeFiles,
          );
        }).toList();

        final where = args
            .map(
              (arg) =>
                  '(${arg.where} ${andWhere.isEmpty ? '' : 'AND'} $andWhere)',
            )
            .join(' OR ');
        final whereArgs = args.expand((arg) => arg.whereArgs).toList()
          ..addAll(andWhereArgs);

        final res = await profile.metaDB.withDB<Iterable<T>>((db) async {
          final result = await db.query(
            'remotefiles',
            where: where,
            whereArgs: whereArgs,
            columns: T == RemoteFile
                ? null
                : T == String
                ? ['key']
                : columns,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
          );
          return result.map(
            (row) => T == RemoteFile
                ? RemoteFile.fromRow(row) as T
                : T == String
                ? row['key'] as T
                : row as T,
          );
        });

        return res;
      }),
    );
    return results.expand((x) => x);
  }

  /// [T] can be [RemoteFile], [String], or [Map<String, Object?>].
  /// If [T] is [RemoteFile], it returns a list of [RemoteFile] objects.
  /// If [T] is [String], it returns a list of keys ([String]).
  /// If [T] is [Map<String, Object?>], it returns a list of maps representing the database rows.
  ///
  /// The [columns] parameter is used to specify which columns to retrieve when [T] is [Map<String, Object?>].
  /// If [columns] is null, all columns will be retrieved.
  /// [columns] is ignored when [T] is [RemoteFile] or [String].
  /// [columns] are passed directly to the database query, so aggregate functions like `SUM(size)` or `MAX(lastModified)` can be used.
  Future<Iterable<T>> getChildren<T>({
    bool recursive = true,
    bool ifPresent = true,
    bool includeDirs = true,
    bool includeFiles = true,
    bool? distinct,
    List<String>? columns,
    String andWhere = '',
    List<Object> andWhereArgs = const [],
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return RemoteFile.getChildrenByKey<T>(
      key,
      recursive: recursive,
      ifPresent: ifPresent,
      includeDirs: includeDirs,
      includeFiles: includeFiles,
      distinct: distinct,
      columns: columns,
      andWhere: andWhere,
      andWhereArgs: andWhereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  static Future<void> removeByKey(String key, {String? oldEtag}) async {
    final profile = Main.profileFromKey(key);
    await profile?.metaDB.withTransaction((txn) async {
      await profile.metaDB.deleteFile(key, txn: txn, oldEtag: oldEtag);
    });
  }

  static Future<void> removeByKeys(
    Iterable<String> keys, {
    Iterable<String?>? oldEtag,
  }) async {
    final Map<Profile, List<(String, String?)>> groupedKeys = {};
    final ikeys = keys.iterator;
    final iet = oldEtag?.iterator;
    while (ikeys.moveNext()) {
      final key = ikeys.current;
      final oldEtag = iet?.moveNext() == true ? iet!.current : null;
      final profile = Main.profileFromKey(key);
      if (profile != null) {
        groupedKeys.putIfAbsent(profile, () => []).add((key, oldEtag));
      }
    }
    await Future.wait(
      groupedKeys.entries.map((entry) async {
        final profile = entry.key;
        final keysForProfile = entry.value;
        await profile.metaDB.withTransaction((txn) async {
          for (final (key, oldEtag) in keysForProfile) {
            await profile.metaDB.deleteFile(key, txn: txn, oldEtag: oldEtag);
          }
        });
      }),
    );
  }

  static Future<void> removeByDir(String dir) async {
    final profile = Main.profileFromKey(dir);
    await profile?.metaDB.withTransaction((txn) async {
      final args = MetaDB.filesByDirQueryArgs(
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
    });
  }

  /// Clear all present files in the database, marking them as deleted, to be added back later if they are still present on the remote.
  /// This is used when a full refresh of the remote files is needed.
  static Future<void> clearAll() async {
    await Future.wait(
      Main.profiles.values.map((profile) async {
        await profile.metaDB.withTransaction((txn) async {
          await txn.execute(
            '''
              UPDATE remotefiles
              SET present = 0, deletedAt = ?
              WHERE present = 1
            ''',
            [DateTime.now().toUtc().millisecondsSinceEpoch],
          );
        });
      }),
    );
  }

  // Properties

  Future<int> getSize() async {
    if (!p.isDir(key)) {
      return this.size;
    }

    final size =
        (await getChildren<Map<String, Object?>>(
              recursive: true,
              ifPresent: true,
              includeDirs: false,
              includeFiles: true,
              columns: ['SUM(size) AS totalSize'],
            )).first['totalSize']
            as int? ??
        0;

    if (size != this.size) {
      this.size = size;
      await profile?.metaDB.withDB((db) async {
        await db.update(
          'remotefiles',
          {'size': this.size},
          where: 'key = ?',
          whereArgs: [key],
        );
      });
    }

    return this.size;
  }

  Future<DateTime> getLastModified() async {
    if (!p.isDir(key)) {
      return lastModified;
    }

    final latest = DateTime.fromMillisecondsSinceEpoch(
      (await getChildren<Map<String, Object?>>(
                recursive: true,
                ifPresent: true,
                includeDirs: false,
                includeFiles: true,
                columns: ['MAX(lastModified) AS latest'],
              )).first['latest']
              as int? ??
          0,
    );

    if (latest != lastModified) {
      lastModified = latest;
      await profile?.metaDB.withDB((db) async {
        await db.update(
          'remotefiles',
          {'lastModified': lastModified.millisecondsSinceEpoch},
          where: 'key = ?',
          whereArgs: [key],
        );
      });
    }

    return latest;
  }

  Future<(int, int)> getCount({bool recursive = true}) async {
    if (!p.isDir(key)) {
      return (0, 1);
    }

    final childCount = await getChildren<Map<String, Object?>>(
      recursive: recursive,
      ifPresent: true,
      includeDirs: true,
      includeFiles: true,
      columns: [
        "SUM(CASE WHEN key LIKE '%/' THEN 1 ELSE 0 END) AS dir_count",
        "SUM(CASE WHEN key NOT LIKE '%/' THEN 1 ELSE 0 END) AS file_count",
      ],
    );
    final res = childCount.isEmpty
        ? (0, 0)
        : (
            childCount.first['dir_count'] as int? ?? 0,
            childCount.first['file_count'] as int? ?? 0,
          );

    if (count != res) {
      count = res;
      for (var profile in Main.profiles.values) {
        await profile.metaDB.withDB((db) async {
          await db.update(
            'remotefiles',
            {'count': '(${count.$1}, ${count.$2})'},
            where: 'key = ?',
            whereArgs: [key],
          );
        });
      }
    }

    return count;
  }

  Future<bool?> getDownloaded({bool refresh = false}) async {
    if (!p.isDir(key)) {
      if (refresh) {
        final file = File(Main.pathFromKey(key));
        isDownloaded[key] = await file.exists();
      }
      return downloaded;
    }

    final childKeys = await getChildren<String>(
      recursive: true,
      ifPresent: true,
      includeDirs: false,
      includeFiles: true,
    );

    for (var childKey in childKeys) {
      if (refresh) {
        final file = File(Main.pathFromKey(childKey));
        isDownloaded[childKey] = await file.exists();
      }
      if (isDownloaded[childKey] != true) {
        isDownloaded[key] = isDownloaded[childKey];
        return isDownloaded[key];
      }
    }

    isDownloaded[key] = true;
    return true;
  }

  Future<bool> getCached() async {
    if (p.isDir(key)) {
      bool cached = true;
      for (var file in await RemoteFile.getChildrenByKey<RemoteFile>(
        key,
        recursive: false,
      )) {
        final fileCached = await file.getCached();
        if (!fileCached) {
          cached = false;
          break;
        }
      }
      return cached;
    } else {
      return await File(Main.cachePathFromKey(key)).exists();
    }
  }

  static RemoteFile fromRow(Map<String, Object?> row) {
    final Map<String, Object?> json = Map.from(row);
    json['metadata'] =
        jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
    json['count'] = (row['count'] as String)
        .substring(1, (row['count'] as String).length - 1)
        .split(',')
        .map((e) => int.parse(e.trim()))
        .toList();
    return RemoteFile(
      key: json['key'] as String,
      size: json['size'] as int? ?? 0,
      etag: json['etag'] as String? ?? '',
      lastModified: json['lastModified'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastModified'] as int)
          : null,
      created: json['created'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['created'] as int)
          : null,
      original: json['original'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['original'] as int)
          : null,
      contentType: json['contentType'] as String? ?? 'application/octet-stream',
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      deletedAt: json['deletedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['deletedAt'] as int)
          : null,
      count: (json['count'] as List<dynamic>?) != null
          ? (
              (json['count'] as List<dynamic>)[0] as int,
              (json['count'] as List<dynamic>)[1] as int,
            )
          : (0, 0),
    );
  }

  RemoteFile copyWith({
    String? key,
    int? size,
    String? etag,
    DateTime? lastModified,
    DateTime? created,
    DateTime? original,
    String? contentType,
    Map<String, dynamic>? metadata,
    DateTime? deletedAt,
    (int, int)? count,
  }) {
    return RemoteFile(
      key: key ?? this.key,
      size: size ?? this.size,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      created: created ?? this.created,
      original: original ?? this.original,
      contentType: contentType ?? this.contentType,
      metadata: metadata ?? this.metadata,
      deletedAt: deletedAt ?? this.deletedAt,
      count: count ?? this.count,
    );
  }
}

class S3Config {
  final String accessKey;
  final String secretKey;
  final String region;
  final String bucket;
  final String prefix;
  final String host;

  S3Config({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.bucket,
    this.prefix = '',
    this.host = '',
  });
}

enum DirOrFile { none, file, dir, both }

class UiConfig {
  ThemeMode colorMode;
  Color? accentColor;
  bool ultraDark;
  bool showDirectorySummary;
  bool showDirectoryBackupConfig;
  DirOrFile showTime;
  DirOrFile showSize;
  DirOrFile showDownloadStatus;
  bool showType;
  bool showContent;

  UiConfig({
    this.colorMode = ThemeMode.system,
    this.accentColor,
    this.ultraDark = false,
    this.showDirectorySummary = true,
    this.showDirectoryBackupConfig = true,
    this.showTime = DirOrFile.both,
    this.showSize = DirOrFile.both,
    this.showDownloadStatus = DirOrFile.both,
    this.showType = true,
    this.showContent = true,
  });
}

enum HashIgnoreMode { sizeChanged, optimistic, always }

class TransferConfig {
  int maxConcurrentTransfers;
  HashIgnoreMode hashIgnoreMode;

  TransferConfig({
    this.maxConcurrentTransfers = 5,
    this.hashIgnoreMode = HashIgnoreMode.sizeChanged,
  });

  TransferConfig copyWith({
    int? maxConcurrentTransfers,
    HashIgnoreMode? hashIgnoreMode,
  }) {
    return TransferConfig(
      maxConcurrentTransfers:
          maxConcurrentTransfers ?? this.maxConcurrentTransfers,
      hashIgnoreMode: hashIgnoreMode ?? this.hashIgnoreMode,
    );
  }
}
