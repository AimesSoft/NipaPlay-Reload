import 'dart:convert';

import 'package:nipaplay_core/utils/settings_storage.dart';

/// 最近播放记录（TV 版本地）。
///
/// 阶段四说明：正式实现应复用 core 的 watch_history 模型；该模型仍受依赖环
/// 阻塞（见 core-inventory.md §5），故 TV 侧先用轻量本地记录保证首页可用。
class TvRecentPlay {
  const TvRecentPlay({
    required this.title,
    required this.sourceUri,
    required this.playedAt,
    this.coverUrl = '',
    this.episodeLabel,
  });

  final String title;
  final String sourceUri;
  final DateTime playedAt;
  final String coverUrl;
  final String? episodeLabel;

  Map<String, dynamic> toJson() => {
        't': title,
        'u': sourceUri,
        'at': playedAt.millisecondsSinceEpoch,
        if (coverUrl.isNotEmpty) 'c': coverUrl,
        if (episodeLabel != null) 'e': episodeLabel,
      };

  static TvRecentPlay? fromJson(Map<String, dynamic> j) {
    final title = j['t'] as String?;
    final uri = j['u'] as String?;
    if (title == null || uri == null) return null;
    return TvRecentPlay(
      title: title,
      sourceUri: uri,
      playedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['at'] as num?)?.toInt() ?? 0),
      coverUrl: (j['c'] as String?) ?? '',
      episodeLabel: j['e'] as String?,
    );
  }
}

class TvRecentPlayStore {
  TvRecentPlayStore._();
  static const _key = 'tv.recent_play';
  static const _max = 20;

  static Future<List<TvRecentPlay>> load() async {
    final raw = await SettingsStorage.loadStringList(_key);
    final list = <TvRecentPlay>[];
    for (final line in raw) {
      try {
        final item = TvRecentPlay.fromJson(
            (jsonDecode(line) as Map).cast<String, dynamic>());
        if (item != null) list.add(item);
      } catch (_) {}
    }
    list.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return list;
  }

  /// 记录一次播放（同源去重后置顶）。
  static Future<void> record(TvRecentPlay entry) async {
    final list = await load();
    list.removeWhere((e) => e.sourceUri == entry.sourceUri);
    list.insert(0, entry);
    final trimmed = list.take(_max).toList();
    await SettingsStorage.saveStringList(
      _key,
      trimmed.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  static Future<void> clear() async {
    await SettingsStorage.saveStringList(_key, const []);
  }
}
