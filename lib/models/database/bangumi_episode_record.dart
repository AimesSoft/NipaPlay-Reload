

class DbBangumiEpisodeRecord {
  const DbBangumiEpisodeRecord({
    required this.bangumiEpisodeId,
    required this.animeId,
    this.episodeNumber,
    this.sortOrder,
    this.airDate,
    this.durationSeconds,
    this.title,
    this.titleCn,
    this.description,
    this.updatedAt,
  });

  final int       bangumiEpisodeId;
  final int       animeId;
  final int?      episodeNumber;
  final double?   sortOrder;
  final DateTime? airDate;
  final int?      durationSeconds;
  final String?   title;
  final String?   titleCn;
  final String?   description;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'bangumi_episode_id': bangumiEpisodeId,
        'bangumi_anime_id': animeId,
        'episode_number': episodeNumber,
        'sort_order': sortOrder,
        'air_date': airDate?.toIso8601String(),
        'duration_seconds': durationSeconds,
        'title': title,
        'title_cn': titleCn,
        'description': description,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbBangumiEpisodeRecord.fromMap(Map<String, Object?> map) {
    return DbBangumiEpisodeRecord(
      bangumiEpisodeId: (map['bangumi_episode_id'] as num).toInt(),
      animeId: (map['bangumi_anime_id'] as num).toInt(),
      episodeNumber: (map['episode_number'] as num?)?.toInt(),
      sortOrder: (map['sort_order'] as num?)?.toDouble(),
      airDate: _parseDateTime(map['air_date']),
      durationSeconds: (map['duration_seconds'] as num?)?.toInt(),
      title: map['title'] as String?,
      titleCn: map['title_cn'] as String?,
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
