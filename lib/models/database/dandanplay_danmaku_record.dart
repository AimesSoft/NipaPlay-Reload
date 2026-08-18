

class DbDandanplayDanmakuRecord {

  const DbDandanplayDanmakuRecord({
    required this.dandanplayEpisodeId,
    this.danmakuJson,
  });

  final int     dandanplayEpisodeId;
  final String? danmakuJson;

  Map<String, Object?> toMap() => <String, Object?>{
        'dandanplay_episode_id': dandanplayEpisodeId,
        'danmaku_json': danmakuJson,
      };

  factory DbDandanplayDanmakuRecord.fromMap(Map<String, Object?> map) {
    return DbDandanplayDanmakuRecord(
      dandanplayEpisodeId: (map['dandanplay_episode_id'] as num).toInt(),
      danmakuJson: map['danmaku_json'] as String?,
    );
  }
}
