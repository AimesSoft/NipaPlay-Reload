
// lib/models/database/file_record.dart


class DbFileRecord {

  const DbFileRecord({
    required this.fileHash,
    this.animeId,
    this.episodeId,
    this.fileName,
    this.fileSize,
    this.duration,
    this.createdAt,
    this.updatedAt,
  });

  final String fileHash;
  final int? animeId;
  final int? episodeId;
  final String? fileName;
  final int? fileSize;
  final int? duration;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
        'file_hash': fileHash,
        'dandanplay_anime_id': animeId,
        'episode_id': episodeId,
        'file_name': fileName,
        'file_size': fileSize,
        'duration': duration,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbFileRecord.fromMap(Map<String, Object?> map) {
    return DbFileRecord(
      fileHash: map['file_hash'] as String,
      animeId: (map['dandanplay_anime_id'] as num?)?.toInt(),
      episodeId: (map['episode_id'] as num?)?.toInt(),
      fileName: map['file_name'] as String?,
      fileSize: (map['file_size'] as num?)?.toInt(),
      duration: (map['duration'] as num?)?.toInt(),
      createdAt: _parseDateTime(map['created_at']),
      updatedAt: _parseDateTime(map['updated_at']),
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
