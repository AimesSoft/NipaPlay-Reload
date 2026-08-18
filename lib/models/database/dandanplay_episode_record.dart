
// lib/models/database/episode_record.dart


class DbDandanplayEpisodeRecord {

  const DbDandanplayEpisodeRecord({
    required this.dandanplayEpisodeId,
    required this.dandanplayAnimeId,
    this.bangumiTvId,
    this.title,
    this.sortOrder,
    this.danmakuJson,
  });

  final int       dandanplayEpisodeId;
  final int       dandanplayAnimeId;
  final int?      bangumiTvId;
  final String?   title;
  final double?   sortOrder;
  final String?   danmakuJson;

  Map<String, Object?> toMap() => {
        'dandanplay_episode_id': dandanplayEpisodeId,
        'dandanplay_anime_id': dandanplayAnimeId,
        'title': title,
        'sort_order': sortOrder,
        'danmaku_json': danmakuJson,
      };

  factory DbDandanplayEpisodeRecord.fromMap(Map<String, Object?> map) {
    return DbDandanplayEpisodeRecord(
      dandanplayEpisodeId: (map['dandanplay_episode_id'] as num).toInt(),
      dandanplayAnimeId: (map['dandanplay_anime_id'] as num).toInt(),
      bangumiTvId: null,
      title: map['title'] as String?,
      sortOrder: (map['sort_order'] as num?)?.toDouble(),
      danmakuJson: map['danmaku_json'] as String?,
    );
  }
}
