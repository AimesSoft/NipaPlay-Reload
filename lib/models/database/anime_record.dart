
// lib/models/database/anime_record.dart


class DbAnimeRecord {
  const DbAnimeRecord({
    required this.id,
    required this.title,
    this.coverImageUrl,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String title;
  final String? coverImageUrl;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'cover_image_url': coverImageUrl,
        'description': description,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbAnimeRecord.fromMap(Map<String, Object?> map) {
    return DbAnimeRecord(
      id: (map['id'] as num).toInt(),
      title: map['title'] as String,
      coverImageUrl: map['cover_image_url'] as String?,
      description: map['description'] as String?,
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
