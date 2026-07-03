import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/profile.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
import 'package:sqflite/sqlite_api.dart';

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
      if (count != null) 'dirCount': count!.$1,
      if (count != null) 'fileCount': count!.$2,
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

    /// Must be a Transaction of the appropriate profile's metaDB
    Transaction? txn,
  }) async {
    if (key.isEmpty && Main.profiles.isNotEmpty) {
      final List<RemoteFile> profiles = await Future.wait(
        Main.profiles.values.map(
          (profile) => RemoteFile.getByKey(profile.name),
        ),
      ).then((files) => files.whereType<RemoteFile>().toList());
      RemoteFile.root.lastModified = profiles
          .map((profile) => profile.lastModified)
          .reduce((v, e) => v.isAfter(e) ? v : e);
      RemoteFile.root.size = profiles
          .map((profile) => profile.size)
          .reduce((v, e) => v + e);
      RemoteFile.root.count = (
        profiles.map((profile) => profile.count.$1).reduce((v, e) => v + e),
        profiles.map((profile) => profile.count.$2).reduce((v, e) => v + e),
      );
      return RemoteFile.root;
    }

    final profile = Main.profileFromKey(key);

    Future<List<Map<String, Object?>>> query(DatabaseExecutor db) async {
      final rawQuery = profile?.metaDB.makeQuery(
        columns: profile.metaDB.remoteFileFields,
        where: ifPresent ? 'key = ? AND present = 1' : 'key = ?',
        whereArgs: [profile.metaDB.s3KeyFromKey(key)],
      );
      return await db.rawQuery(rawQuery!);
    }

    final result = txn != null
        ? await query(txn)
        : await profile?.metaDB.withDB<List<Map<String, Object?>>>(query);

    return result == null || result.isEmpty
        ? null
        : RemoteFile.fromRow(result.first);
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
    final Map<Profile, Set<String>> groupedDirs = {};
    for (String dir in keys) {
      if (dir.isEmpty) {
        for (var profile in Main.profiles.values) {
          groupedDirs.putIfAbsent(profile, () => {}).add(dir);
        }
        continue;
      }
      final profile = Main.profileFromKey(dir);
      if (profile != null) {
        groupedDirs.putIfAbsent(profile, () => {}).add(dir);
      }
    }

    final results = await Future.wait(
      groupedDirs.keys.map((profile) async {
        final args = groupedDirs[profile]!.map((dir) {
          return profile.metaDB.filesByDirQueryArgs(
            dir,
            recursive: recursive,
            ifPresent: ifPresent,
            includeDirs: includeDirs,
            includeFiles: includeFiles,
          );
        }).toList();

        final where =
            '(${args.map((arg) => arg.where).join(' OR ')}) ${andWhere.isEmpty ? '' : 'AND $andWhere'}';
        final whereArgs =
            args.expand((arg) => arg.whereArgs).toList() + andWhereArgs;

        final columnsToSelect = T == RemoteFile
            ? profile.metaDB.remoteFileFields
            : T == String
            ? [profile.metaDB.keyColumn]
            : columns ?? profile.metaDB.remoteFileFields;

        final rawColumnsToSelect = T == RemoteFile
            ? profile.metaDB.remoteFileFields
            : T == String
            ? [profile.metaDB.keyColumn]
            : columns ?? profile.metaDB.remoteFileFields;

        String rawQuery = profile.metaDB.makeQuery(
          columns: columnsToSelect,
          rawColumns: rawColumnsToSelect,
          where: where,
          whereArgs: whereArgs,
          groupBy: groupBy,
          having: having,
          orderBy: orderBy,
          limit: limit,
          offset: offset,
        );

        return await profile.metaDB.withDB<Iterable<T>>((db) async {
          final res = await db.rawQuery(rawQuery);
          return res.map(
            (row) => T == RemoteFile
                ? RemoteFile.fromRow(row) as T
                : T == String
                ? row['key'] as T
                : row as T,
          );
        });
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
    return await RemoteFile.getChildrenByKeys<T>(
      [key],
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
      for (var file in await RemoteFile.getChildrenByKeys<RemoteFile>([
        key,
      ], recursive: false)) {
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
      count: (json['dirCount'] as int? ?? 0, json['fileCount'] as int? ?? 0),
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
