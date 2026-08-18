
// lib/models/database/file_record.dart


class DbFileRecord {

  const DbFileRecord({
    required this.fileHash,
    this.fileName,
    this.fileSize,
    this.duration,
    this.createdAt,
  });

  final String fileHash;
  final String? fileName;
  final int? fileSize;
  final int? duration;
  final DateTime? createdAt;

  Map<String, Object?> toMap() => {
        'file_hash': fileHash,
        'file_name': fileName,
        'file_size': fileSize,
        'duration': duration,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbFileRecord.fromMap(Map<String, Object?> map) {
    return DbFileRecord(
      fileHash: map['file_hash'] as String,
      fileName: map['file_name'] as String?,
      fileSize: (map['file_size'] as num?)?.toInt(),
      duration: (map['duration'] as num?)?.toInt(),
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
