
// lib/models/database/episode_record.dart


class DbDandanplayEpisodeRecord {

  const DbDandanplayEpisodeRecord({
    this.dandanplayEpisodeId,
    this.animeId,
    this.bangumiTvId,
    this.title,
    this.sortOrder,
    this.updatedAt,
  });

  final int?      dandanplayEpisodeId;
  final int?      animeId;
  final int?      bangumiTvId;
  final String?   title;
  final double?   sortOrder;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
        'dandanplay_episode_id': dandanplayEpisodeId,
        'dandanplay_anime_id': animeId,
        'title': title,
        'sort_order': sortOrder,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbDandanplayEpisodeRecord.fromMap(Map<String, Object?> map) {
    return DbDandanplayEpisodeRecord(
      dandanplayEpisodeId: (map['dandanplay_episode_id'] as num?)?.toInt(),
      animeId: (map['dandanplay_anime_id'] as num?)?.toInt(),
      bangumiTvId: null,
      title: map['title'] as String?,
      sortOrder: (map['sort_order'] as num?)?.toDouble(),
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
