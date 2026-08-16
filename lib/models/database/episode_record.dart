
// lib/models/database/episode_record.dart


class DbEpisodeRecord {
  const DbEpisodeRecord({
    required this.id,
    required this.animeId,
    this.title,
    this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int animeId;
  final String? title;
  final double? sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'anime_id': animeId,
        'title': title,
        'sort_order': sortOrder,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbEpisodeRecord.fromMap(Map<String, Object?> map) {
    return DbEpisodeRecord(
      id: (map['id'] as num).toInt(),
      animeId: (map['anime_id'] as num).toInt(),
      title: map['title'] as String?,
      sortOrder: (map['sort_order'] as num?)?.toDouble(),
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
