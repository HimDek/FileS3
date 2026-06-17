import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';

class FileProps {
  final String key;
  final int size;
  final RemoteFile? file;
  final Job? job;
  final String? url;

  FileProps({
    required this.key,
    required this.size,
    this.file,
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

class RemoteFile {
  final String key;
  int _size;
  final String etag;
  DateTime? _lastModified;
  (int, int) _count = (0, 1);

  RemoteFile({
    required this.key,
    int size = 0,
    required this.etag,
    lastModified,
  }) : _size = size,
       _lastModified = lastModified;

  int get size => _size;
  DateTime? get lastModified => _lastModified;
  (int, int) get count => _count;

  Future<int> getSize() async {
    if (!p.isDir(key)) {
      return _size;
    }
    int size = 0;
    for (final file in Main.remoteFiles.where(
      (file) => p.isWithin(key, file.key) && !p.isDir(file.key),
    )) {
      size += file.size;
    }
    _size = size;
    return size;
  }

  Future<DateTime?> getLastModified() async {
    if (!p.isDir(key)) {
      return _lastModified;
    }
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final file in Main.remoteFiles.where(
      (file) => p.isWithin(key, file.key) && !p.isDir(file.key),
    )) {
      if (file.lastModified!.isAfter(latest)) {
        latest = file.lastModified!;
      }
    }
    _lastModified = latest;
    return latest == DateTime.fromMillisecondsSinceEpoch(0) ? null : latest;
  }

  Future<(int, int)> getCount({bool recursive = false}) async {
    if (!p.isDir(key)) {
      return (0, 1);
    }
    int dirCount = 0;
    int fileCount = 0;
    for (final file in Main.remoteFiles.where(
      (file) =>
          p.isWithin(key, file.key) &&
          file.key != key &&
          (recursive || p.s3(p.dirname(file.key)) == p.s3(key)),
    )) {
      if (p.isDir(file.key)) {
        dirCount += 1;
      } else {
        fileCount += 1;
      }
    }
    _count = (dirCount, fileCount);
    return (dirCount, fileCount);
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
      'lastModified': lastModified?.toIso8601String(),
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

class UiConfig {
  ThemeMode colorMode;
  Color? accentColor;
  bool ultraDark;
  bool showDirectorySummary;
  bool showDirectoryBackupConfig;
  bool showTime;
  bool showSize;
  bool showDownloadStatus;
  bool showType;
  bool showContent;

  UiConfig({
    this.colorMode = ThemeMode.system,
    this.accentColor,
    this.ultraDark = false,
    this.showDirectorySummary = true,
    this.showDirectoryBackupConfig = true,
    this.showTime = true,
    this.showSize = true,
    this.showDownloadStatus = true,
    this.showType = true,
    this.showContent = true,
  });
}

class TransferConfig {
  final int maxConcurrentTransfers;

  TransferConfig({this.maxConcurrentTransfers = 5});
}
