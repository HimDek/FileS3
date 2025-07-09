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
