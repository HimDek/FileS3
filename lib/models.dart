import 'dart:io';
import 'dart:convert';
import 'package:mime/mime.dart';
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

abstract interface class RemoteFileFields {
  String get key;
  int get size;
  String get etag;
  DateTime? get lastModified;
}

class RemoteFile implements RemoteFileFields {
  @override
  final String key;
  int _size;
  @override
  final String etag;
  DateTime? _lastModified;
  (int, int) _count = (0, 1);
  bool? downloaded;
  bool? cached;

  RemoteFile({
    required this.key,
    int size = 0,
    required this.etag,
    lastModified,
  }) : _size = size,
       _lastModified = lastModified;

  @override
  int get size => _size;

  @override
  DateTime? get lastModified => _lastModified;

  (int, int) get count => _count;

  Future<int> getSize() async {
    if (!p.isDir(key)) {
      return _size;
    }
    int size = 0;
    for (final file in Main.remoteFilesByDir(
      key,
      recursive: true,
    ).where((file) => !p.isDir(file.key))) {
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
    for (final file in Main.remoteFilesByDir(
      key,
      recursive: true,
    ).where((file) => !p.isDir(file.key))) {
      if (file.lastModified?.isAfter(latest) ?? false) {
        latest = file.lastModified!;
      }
    }
    _lastModified = latest == DateTime.fromMillisecondsSinceEpoch(0)
        ? null
        : latest;
    return _lastModified;
  }

  Future<(int, int)> getCount({
    bool recursive = false,
    List<RegExp>? mimeTypes,
  }) async {
    if (!p.isDir(key)) {
      return (0, 1);
    }
    int dirCount = 0;
    int fileCount = 0;
    for (final file in Main.remoteFilesByDir(key, recursive: recursive)) {
      if (p.isDir(file.key)) {
        dirCount += 1;
      } else {
        if ((mimeTypes ?? [allMimePattern]).any(
          (mime) => mime.hasMatch(lookupMimeType(file.key) ?? ''),
        )) {
          fileCount += 1;
        }
      }
    }
    _count = (dirCount, fileCount);
    return (dirCount, fileCount);
  }

  Future<bool> getDownloaded() async {
    if (p.isDir(key)) {
      bool downloaded = true;
      for (var file in Main.remoteFilesByDir(
        key,
        recursive: true,
      ).where((file) => !p.isDir(file.key))) {
        file.downloaded = await File(Main.pathFromKey(file.key)).exists();
        if (!file.downloaded!) {
          downloaded = false;
          break;
        }
      }
      this.downloaded = downloaded;
    } else {
      downloaded = await File(Main.pathFromKey(key)).exists();
    }
    return downloaded!;
  }

  Future<bool> getCached() async {
    if (p.isDir(key)) {
      bool cached = true;
      for (var file in Main.remoteFilesByDir(
        key,
        recursive: true,
      ).where((file) => !p.isDir(file.key))) {
        file.cached = await File(Main.cachePathFromKey(file.key)).exists();
        if (!file.cached!) {
          cached = false;
          break;
        }
      }
      this.cached = cached;
    } else {
      cached = await File(Main.cachePathFromKey(key)).exists();
    }
    return cached!;
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
      'lastModified': !p.isDir(key) ? lastModified?.toIso8601String() : null,
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
