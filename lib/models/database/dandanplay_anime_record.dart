
// lib/models/database/anime_record.dart


class DbDandanplayAnimeRecord {

  const DbDandanplayAnimeRecord({
    required this.dandanplayAnimeId,
    this.bangumiAnimeId,
    required this.title,
    this.coverImageUrl,
    this.description,
  });

  final int       dandanplayAnimeId;
  final int?      bangumiAnimeId;
  final String?   title;
  final String?   coverImageUrl;
  final String?   description;

  Map<String, Object?> toMap() => {
        'dandanplay_anime_id': dandanplayAnimeId,
        'bangumi_anime_id': bangumiAnimeId,
        'title': title,
        'cover_image_url': coverImageUrl,
        'description': description,
      };

  factory DbDandanplayAnimeRecord.fromMap(Map<String, Object?> map) {
    return DbDandanplayAnimeRecord(
      dandanplayAnimeId: (map['dandanplay_anime_id'] as num).toInt(),
      bangumiAnimeId: (map['bangumi_anime_id'] as num?)?.toInt(),
      title: map['title'] as String?,
      coverImageUrl: map['cover_image_url'] as String?,
      description: map['description'] as String?,
    );
  }
}
