import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:files3/utils/path_utils.dart' as p;
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

enum JobStatus { initialized, running, completed, failed, stopped }

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

sealed class RemoteFileFields {
  /// The unique key representing the file or directory in the remote storage profile.
  final String key;

  /// The size of the file in bytes.
  int size;

  /// The ETag of the file, which is a unique identifier for the file's content.
  final String etag;

  /// The last modified date of the file.
  DateTime lastModified;

  /// The creation date of the file.
  final DateTime created;

  /// The original date of the file.
  final DateTime original;

  final String contentType;

  final Map<String, dynamic> metadata;

  final DateTime? deletedAt;

  (int, int) count;

  RemoteFileFields({
    required this.key,
    this.size = 0,
    required this.etag,
    DateTime? lastModified,
    DateTime? created,
    DateTime? original,
    this.contentType = 'application/octet-stream',
    this.metadata = const {},
    this.deletedAt,
    this.count = const (0, 0),
  }) : lastModified = lastModified ?? DateTime.fromMicrosecondsSinceEpoch(0),
       created = created ?? DateTime.fromMicrosecondsSinceEpoch(0),
       original = original ?? DateTime.fromMicrosecondsSinceEpoch(0);
}

class RemoteFile extends RemoteFileFields {
  bool? get downloaded => isDownloaded[key];

  RemoteFile({
    required super.key,
    super.size,
    required super.etag,
    super.lastModified,
    super.created,
    super.original,
    super.contentType,
    super.metadata,
    super.deletedAt,
    super.count,
  });

  Future<int> getSize() async {
    if (!p.isDir(key)) {
      return this.size;
    }

    int? size;
    if (key.isEmpty) {
      for (var profile in Main.profiles.values) {
        final profileSize = await profile.metaDB.withDB<int>((db) async {
          final res = await db.query(
            'remotefiles',
            columns: ['SUM(size) AS totalSize'],
          );
          if (res.isNotEmpty) {
            final totalSize = res.first['totalSize'] as int?;
            return totalSize ?? 0;
          }
          return this.size;
        });
        size ??= 0;
        size += profileSize;
      }
      this.size = size ?? this.size;
      return this.size;
    }

    final profile = Main.profileFromKey(key);
    if (profile == null) {
      return this.size;
    }

    size = await profile.metaDB.withDB<int>((db) async {
      final args = profile.metaDB.filesByDirQueryArgs(
        key,
        recursive: true,
        ifPresent: true,
        includeDirs: false,
        includeFiles: true,
      );
      final res = await db.query(
        'remotefiles',
        columns: ['SUM(size) AS totalSize'],
        where: args.where,
        whereArgs: args.whereArgs,
      );
      if (res.isNotEmpty) {
        final totalSize = res.first['totalSize'] as int?;
        return totalSize ?? this.size;
      }
      return this.size;
    });

    if (size != this.size) {
      this.size = size;
      await profile.metaDB.withDB((db) async {
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

    if (key.isEmpty) {
      DateTime? overallLatest;
      for (var profile in Main.profiles.values) {
        final profileLatest = await profile.metaDB.withDB<DateTime?>((
          db,
        ) async {
          final res = await db.query(
            'remotefiles',
            columns: ['MAX(lastModified) AS latest'],
          );
          if (res.isNotEmpty) {
            final latestMillis = res.first['latest'] as int?;
            if (latestMillis != null) {
              return DateTime.fromMillisecondsSinceEpoch(latestMillis);
            }
          }
          return DateTime.fromMillisecondsSinceEpoch(0);
        });
        if (profileLatest != null &&
            (overallLatest == null || profileLatest.isAfter(overallLatest))) {
          overallLatest = profileLatest;
        }
      }
      return overallLatest ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    final profile = Main.profileFromKey(key);
    if (profile == null) {
      return lastModified;
    }

    final latest = await profile.metaDB.withDB<DateTime>((db) async {
      final args = profile.metaDB.filesByDirQueryArgs(
        key,
        recursive: false,
        ifPresent: true,
        includeDirs: false,
        includeFiles: true,
      );
      final res = await db.query(
        'remotefiles',
        columns: ['MAX(lastModified) AS latest'],
        where: args.where,
        whereArgs: args.whereArgs,
      );
      if (res.isNotEmpty) {
        final latestMillis = res.first['latest'] as int?;
        if (latestMillis != null) {
          return DateTime.fromMillisecondsSinceEpoch(latestMillis);
        }
      }
      return lastModified;
    });

    if (latest != lastModified) {
      lastModified = latest;
      await profile.metaDB.withDB((db) async {
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

    if (key.isEmpty) {
      int totalDirs = 0;
      int totalFiles = 0;
      for (var profile in Main.profiles.values) {
        final profileCounts = await profile.metaDB.withDB<(int, int)>((
          db,
        ) async {
          final dirCountFuture = db.query(
            'remotefiles',
            columns: ['COUNT(*) AS count'],
            where: 'key LIKE ? AND key != ?',
            whereArgs: ['%/', ''],
          );
          final fileCountFuture = db.query(
            'remotefiles',
            columns: ['COUNT(*) AS count'],
            where: 'key NOT LIKE ? AND key != ?',
            whereArgs: ['%/', ''],
          );

          final res = await Future.wait<List<Map<String, Object?>>>([
            dirCountFuture,
            fileCountFuture,
          ]);

          final dirCount = res[0].isNotEmpty
              ? res[0].first['count'] as int? ?? 0
              : 0;
          final fileCount = res[1].isNotEmpty
              ? res[1].first['count'] as int? ?? 0
              : 0;

          return (dirCount, fileCount);
        });

        totalDirs += profileCounts.$1;
        totalFiles += profileCounts.$2;
      }

      count = (totalDirs, totalFiles);
      return count;
    }

    final profile = Main.profileFromKey(key);
    if (profile == null) {
      return (0, 0);
    }

    final dirCountFuture = profile.metaDB.withDB<int>((db) async {
      final args = Main.profileFromKey(key)?.metaDB.filesByDirQueryArgs(
        key,
        recursive: recursive,
        ifPresent: true,
        includeDirs: true,
        includeFiles: false,
      );
      final res = await db.query(
        'remotefiles',
        columns: ['COUNT(*) AS count'],
        where: args?.where,
        whereArgs: args?.whereArgs,
      );
      if (res.isNotEmpty) {
        final count = res.first['count'] as int?;
        return count ?? 0;
      }
      return 0;
    });

    final fileCountFuture = profile.metaDB.withDB<int>((db) async {
      final args = Main.profileFromKey(key)?.metaDB.filesByDirQueryArgs(
        key,
        recursive: recursive,
        ifPresent: true,
        includeDirs: false,
        includeFiles: true,
      );
      final res = await db.query(
        'remotefiles',
        columns: ['COUNT(*) AS count'],
        where: args?.where,
        whereArgs: args?.whereArgs,
      );
      if (res.isNotEmpty) {
        final count = res.first['count'] as int?;
        return count ?? 0;
      }
      return 0;
    });

    final res = await Future.wait<int>([dirCountFuture, fileCountFuture]);

    if (count != (res[0], res[1])) {
      count = (res[0], res[1]);
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

    if (key.isEmpty) {
      for (var profile in Main.profiles.values) {
        final profileKeys = await profile.metaDB.withDB<Iterable<String>>((
          db,
        ) async {
          final res = await db.query(
            'remotefiles',
            columns: ['key'],
            where: 'key != ? AND key NOT LIKE ?',
            whereArgs: ['', '%/'],
          );
          return res.map((row) => row['key'] as String);
        });
        if (profileKeys.any(
          (k) =>
              (isDownloaded[k] != true && !refresh) ||
              (refresh && File(Main.pathFromKey(k)).existsSync() == false),
        )) {
          isDownloaded[key] = false;
          return false;
        }
      }
      isDownloaded[key] = true;
      return true;
    }

    final profile = Main.profileFromKey(key);
    if (profile == null) {
      return isDownloaded[key];
    }

    final res = await profile.metaDB.withDB((db) async {
      final args = profile.metaDB.filesByDirQueryArgs(
        key,
        recursive: true,
        ifPresent: true,
        includeDirs: false,
        includeFiles: true,
      );
      return await db
          .query(
            'remotefiles',
            columns: ['key'],
            where: args.where,
            whereArgs: args.whereArgs,
          )
          .then((rows) => rows.map((row) => row['key'] as String));
    });
    if (res.any(
      (k) =>
          (isDownloaded[k] != true && !refresh) ||
          (refresh && File(Main.pathFromKey(k)).existsSync() == false),
    )) {
      return isDownloaded[key];
    }
    isDownloaded[key] = true;
    return true;
  }

  Future<bool> getCached() async {
    if (p.isDir(key)) {
      bool cached = true;
      for (var file in await Main.remoteFilesByDir(key, recursive: false)) {
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

  @override
  String toString() {
    return key;
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
