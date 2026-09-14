/// 从文件名 / 标题里提取集数 / 季度。
///
/// 这是全项目**唯一**一套片源命名解析：`webdav_browser_page.dart` 原先自带一份
/// 同源正则（含两处内联 SxxExx），已整体切到本类，不再各自维护。新增命名格式
/// 一律改这里，不要再起第二套。
///
/// 之所以要独立成工具：跳过片头需要在「播放开始时」就知道集数（AniSkip 以集数
/// 为键），而播放路径上拿到的往往是文件路径或剧集标题，不是弹弹play 的
/// `episodeNumber` 字段。
class EpisodeNumberExtractor {
  EpisodeNumberExtractor._();

  static final RegExp _seasonEpisodeRegex =
      RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})');
  static final RegExp _chineseEpisodeRegex = RegExp(r'第(\d{1,3})[话集]');
  static final RegExp _epNumberRegex = RegExp(r'[Ee][Pp]?(\d{1,3})');
  static final RegExp _bracketNumberRegex = RegExp(r'[\[【](\d{1,3})[\]】]');
  static final RegExp _delimiterNumberRegex = RegExp(r'[-_](\d{1,3})[-_\.\[]');

  /// 被空格或分隔符包围的独立数字，例如 `Show - 07 [1080p].mkv`。
  ///
  /// 这是 `_delimiterNumberRegex` 之外的补充：那个正则要求数字紧贴分隔符
  /// （`-07-`），而字幕组更常见的写法是 `- 07 [`（带空格）。
  ///
  /// 用 lookahead/lookbehind 保证数字两端都是「边界」，且**数字后方必须紧跟
  /// 空白、分隔符或方括号**——这样 `1080p` 这种「数字紧贴字母」的令牌不会被
  /// 抓成集数（这也是这条规则不能放宽成 `\d+` 的原因）。
  static final RegExp _spacedNumberRegex =
      RegExp(r'(?:^|[\s\-_])(\d{1,3})(?=[\s\-_\.\[]|$)');

  /// 按优先级依次尝试各种命名习惯，全不中则返回 null。
  ///
  /// 优先级是有讲究的：`S01E12` 最明确；`第12集` / `第12话` 次之；`EP12` 再次；
  /// `[12]` 常见于字幕组命名；`-12-` 最宽松、最容易误命中（比如年份、分辨率），
  /// 所以放最后。
  static int? extract(String? text) {
    if (text == null || text.isEmpty) return null;

    final seasonEpisodeMatch = _seasonEpisodeRegex.firstMatch(text);
    if (seasonEpisodeMatch != null) {
      final parsed = int.tryParse(seasonEpisodeMatch.group(2)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    final chineseMatch = _chineseEpisodeRegex.firstMatch(text);
    if (chineseMatch != null) {
      final parsed = int.tryParse(chineseMatch.group(1)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    final epMatch = _epNumberRegex.firstMatch(text);
    if (epMatch != null) {
      final parsed = int.tryParse(epMatch.group(1)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    final bracketMatch = _bracketNumberRegex.firstMatch(text);
    if (bracketMatch != null) {
      final parsed = int.tryParse(bracketMatch.group(1)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    final delimiterMatch = _delimiterNumberRegex.firstMatch(text);
    if (delimiterMatch != null) {
      final parsed = int.tryParse(delimiterMatch.group(1)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    // 最宽松的一条放最后：`- 07 [` / ` 07 ` 这类「空格包围的独立数字」。
    // 依然排除 `1080p`、`10bit` 这种「数字紧贴字母」的令牌（见该正则的注释）。
    final spacedMatch = _spacedNumberRegex.firstMatch(text);
    if (spacedMatch != null) {
      final parsed = int.tryParse(spacedMatch.group(1)!);
      if (parsed != null && parsed > 0) return parsed;
    }

    return null;
  }

  /// 依次尝试多个候选文本，返回第一个能解析出集数的结果。
  ///
  /// 调用方通常手上同时有「剧集标题」和「文件路径」，两者命中能力不同
  /// （标题可能是纯中文名，路径才带 `[12]` 这类标记），逐个试最省心。
  static int? extractFromAny(Iterable<String?> candidates) {
    for (final candidate in candidates) {
      final parsed = extract(candidate);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// 命中 `SxxExx` 时返回季/集的原始数字串（保留位数写法，供 UI 原样展示
  /// `S01E12` 徽标）；未命中返回 null。
  static ({String season, String episode})? seasonEpisode(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = _seasonEpisodeRegex.firstMatch(text);
    if (match == null) return null;
    return (season: match.group(1)!, episode: match.group(2)!);
  }

  /// 提取 `SxxExx` 里的季数（`S01E12` → 1）；未命中或非法值返回 null。
  static int? extractSeason(String? text) {
    final parts = seasonEpisode(text);
    if (parts == null) return null;
    final parsed = int.tryParse(parts.season);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}
