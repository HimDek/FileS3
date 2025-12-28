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
