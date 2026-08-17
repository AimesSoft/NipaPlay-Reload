
// lib/models/database/anime_record.dart


class DbDandanplayAnimeRecord {

  const DbDandanplayAnimeRecord({
    this.dandanplayAnimeId,
    required this.title,
    this.coverImageUrl,
    this.description,
    this.updatedAt,
  });

  final int?      dandanplayAnimeId;
  final String?   title;
  final String?   coverImageUrl;
  final String?   description;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
        'dandanplay_anime_id': dandanplayAnimeId,
        'title': title,
        'cover_image_url': coverImageUrl,
        'description': description,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbDandanplayAnimeRecord.fromMap(Map<String, Object?> map) {
    return DbDandanplayAnimeRecord(
      dandanplayAnimeId: (map['dandanplay_anime_id'] as num?)?.toInt(),
      title: map['title'] as String?,
      coverImageUrl: map['cover_image_url'] as String?,
      description: map['description'] as String?,
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
