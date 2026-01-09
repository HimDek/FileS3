import 'package:flutter/material.dart';
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
  final int size;
  final String etag;
  final DateTime? lastModified;
  RemoteFile({
    required this.key,
    required this.size,
    required this.etag,
    this.lastModified,
  });

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
  final ThemeMode colorMode;
  final bool ultraDark;

  UiConfig({required this.colorMode, required this.ultraDark});
}

class TransferConfig {
  final int maxConcurrentTransfers;

  TransferConfig({this.maxConcurrentTransfers = 5});
}
