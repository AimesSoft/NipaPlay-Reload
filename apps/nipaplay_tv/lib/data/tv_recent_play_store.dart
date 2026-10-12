import 'dart:convert';

import 'package:nipaplay_core/utils/settings_storage.dart';

/// 播放偏好键空间（core SettingsStorage 之上）。
class TvPlaybackPrefs {
  TvPlaybackPrefs._();
  static const danmakuAreaKey = 'tv.danmaku.areaRatio';   // 0.1 - 1.0
  static const danmakuOnKey = 'tv.danmaku.on';
  static const upscalerKey = 'tv.player.upscaler';       // off / anime4k / etc
  static const videoFitKey = 'tv.player.videoFit';       // contain / cover / fill / 16:9 / 4:3

  static Future<double> danmakuArea() async {
    final raw = await SettingsStorage.loadString(danmakuAreaKey);
    final v = double.tryParse(raw);
    if (v == null || v < 0.1) return 0.5;
    return v.clamp(0.1, 1.0);
  }

  static Future<void> setDanmakuArea(double v) async {
    await SettingsStorage.saveString(danmakuAreaKey, v.toStringAsFixed(2));
  }

  static Future<bool> danmakuOn() async {
    return (await SettingsStorage.loadString(danmakuOnKey)) != 'off';
  }

  static Future<void> setDanmakuOn(bool v) async {
    await SettingsStorage.saveString(danmakuOnKey, v ? 'on' : 'off');
  }

  static Future<String> upscaler() async {
    return (await SettingsStorage.loadString(upscalerKey)) ;
  }

  static Future<void> setUpscaler(String v) async {
    await SettingsStorage.saveString(upscalerKey, v);
  }

  static Future<String> videoFit() async {
    return (await SettingsStorage.loadString(videoFitKey)) ;
  }

  static Future<void> setVideoFit(String v) async {
    await SettingsStorage.saveString(videoFitKey, v);
  }
}

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
    this.sourceLabel = '',
  });

  final String title;
  final String sourceUri;
  final DateTime playedAt;
  final String coverUrl;
  final String? episodeLabel;

  /// 来源媒体连接（弹弹远程 / WebDAV 等），用于最近播放标注。
  final String sourceLabel;

  Map<String, dynamic> toJson() => {
        't': title,
        'u': sourceUri,
        'at': playedAt.millisecondsSinceEpoch,
        if (coverUrl.isNotEmpty) 'c': coverUrl,
        if (episodeLabel != null) 'e': episodeLabel,
        if (sourceLabel.isNotEmpty) 'src': sourceLabel,
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
      sourceLabel: (j['src'] as String?) ?? '',
    );
  }
}

class TvRecentPlayStore {
  TvRecentPlayStore._();
  static const _key = 'tv.recent_play';
  static const _max = 20;

  /// 播放进度：key = 媒体地址（uri），value = 播放位置毫秒。
  static Future<int> progressOf(String sourceUri) async {
    final raw = await SettingsStorage.loadString('tv.progress.$sourceUri');
    return int.tryParse(raw) ?? 0;
  }

  static Future<void> saveProgress(String sourceUri, int millis) async {
    await SettingsStorage.saveString('tv.progress.$sourceUri', '$millis');
  }

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
