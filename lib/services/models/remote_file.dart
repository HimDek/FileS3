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
}
