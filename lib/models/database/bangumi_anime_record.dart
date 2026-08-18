

class DbBangumiAnimeRecord {
  const DbBangumiAnimeRecord({
    required this.bangumiAnimeId,
    this.airDate,
    this.title,
    this.titleCn,
    this.aliases,
    this.description,
    this.episodeCount,
    this.officialSiteUrl,
    this.coverImageUrl,
  });

  final int       bangumiAnimeId;
  final DateTime? airDate;
  final String?   title;
  final String?   titleCn;
  final String?   aliases;
  final String?   description;
  final int?      episodeCount;
  final String?   officialSiteUrl;
  final String?   coverImageUrl;

  Map<String, Object?> toMap() => <String, Object?>{
        'bangumi_anime_id': bangumiAnimeId,
        'air_date': airDate?.toIso8601String(),
        'title': title,
        'title_cn': titleCn,
        'aliases': aliases,
        'description': description,
        'episode_count': episodeCount,
        'url_official_site': officialSiteUrl,
        'url_cover': coverImageUrl,
      };

  factory DbBangumiAnimeRecord.fromMap(Map<String, Object?> map) {
    return DbBangumiAnimeRecord(
      bangumiAnimeId: (map['bangumi_anime_id'] as num).toInt(),
      airDate: _parseDateTime(map['air_date']),
      title: map['title'] as String?,
      titleCn: map['title_cn'] as String?,
      aliases: map['aliases'] as String?,
      description: map['description'] as String?,
      episodeCount: (map['episode_count'] as num?)?.toInt(),
      officialSiteUrl: map['url_official_site'] as String?,
      coverImageUrl: map['url_cover'] as String?,
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
