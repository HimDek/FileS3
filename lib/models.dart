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
  final int size;

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
  }) : lastModified = lastModified ?? DateTime.fromMicrosecondsSinceEpoch(0),
       created = created ?? DateTime.fromMicrosecondsSinceEpoch(0),
       original = original ?? DateTime.fromMicrosecondsSinceEpoch(0);
}

class RemoteFile extends RemoteFileFields {
  (int, int) _count = (0, 1);
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
  });

  (int, int) get count => _count;

  Future<int> getSize() async {
    if (!p.isDir(key)) {
      return this.size;
    }
    int size = 0;
    for (final file in await Main.remoteFilesByDir(key, recursive: false)) {
      await file.getSize();
      size += file.size;
    }
    size = size;
    return size;
  }

  Future<DateTime?> getLastModified() async {
    if (!p.isDir(key)) {
      return lastModified;
    }
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    final children = await Main.remoteFilesByDir(key, recursive: false);
    for (final file in children) {
      await file.getLastModified();
      if (file.lastModified.isAfter(latest)) {
        latest = file.lastModified;
      }
    }
    lastModified = latest;
    return lastModified;
  }

  Future<(int, int)> getCount({bool recursive = false}) async {
    if (!p.isDir(key)) {
      return (0, 1);
    }
    int dirCount = 0;
    int fileCount = 0;
    final children = await Main.remoteFilesByDir(key, recursive: false);
    for (final file in children) {
      if (p.isDir(file.key)) {
        if (recursive) {
          final subCount = await file.getCount(recursive: true);
          dirCount += subCount.$1;
          fileCount += subCount.$2;
        }
        dirCount += 1;
      } else {
        fileCount += 1;
      }
    }
    _count = (dirCount, fileCount);
    return (dirCount, fileCount);
  }

  Future<bool?> getDownloaded({bool refresh = false}) async {
    if (p.isDir(key)) {
      bool? downloaded = true;
      for (var file in await Main.remoteFilesByDir(key, recursive: false)) {
        file.getDownloaded(refresh: refresh);
        if (file.downloaded == false) {
          downloaded = false;
          break;
        }
        if (file.downloaded == null) {
          downloaded = null;
          break;
        }
      }
      isDownloaded[key] = downloaded;
    } else if (refresh) {
      isDownloaded[key] = File(Main.pathFromKey(key)).existsSync();
    }
    return isDownloaded[key];
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

  Future<void> refresh() async {
    await Future.wait([
      getSize(),
      getLastModified(),
      getCount(recursive: true),
    ]);
  }

  @override
  String toString() {
    return key;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'size': size,
      'etag': etag,
      'lastModified': !p.isDir(key) ? lastModified.toIso8601String() : null,
    };
  }

  factory RemoteFile.fromJson(Map<String, dynamic> json) {
    return RemoteFile(
      key: json['key'] as String,
      size: json['size'] as int,
      etag: json['etag'] as String,
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'] as String)
          : null,
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
