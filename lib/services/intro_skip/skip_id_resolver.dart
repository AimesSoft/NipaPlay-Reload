import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart' as http;
import 'package:nipaplay/services/web_remote_access_service.dart';

/// MAL ID 解析结果。
///
/// [malId] 为 null 时，[definitive] 区分「确定没有」与「请求失败」——只有
/// 确定性的结论才允许进 [_malFromTitleCache]。
typedef _ResolveOutcome = ({int? malId, bool definitive});

/// 把播放中的番剧信息换算成 AniSkip 需要的 **MAL ID**。
///
/// ## 为什么不能靠 Bangumi infobox
///
/// 最初的设想是「Bangumi 条目 → infobox 里的 MAL 外链」。实测（2026-09）
/// 取了碧蓝之海 S1/S3、鲁路修 R2、EVA 等一批**动画**条目，infobox 里全是
/// 制作人员表（导演/脚本/作画监督…），**没有任何 MAL / MyAnimeList 字段**。
/// 那个字段只在漫画、书籍类条目的少数条目上偶现。所以这条路对动画不成立。
///
/// ## 实际方案：AniList GraphQL 的 `idMal`
///
/// AniList 的 `Media` 上带 `idMal` 字段，且**完全免费、无需鉴权**。搜索命中后
/// 直接拿 `idMal` 即得 MAL ID。实测：
///
/// ```
/// search "Grand Blue"          → AniList 100922, idMal 37105   ✅
/// search "Grand Blue Season 3" → AniList 199111, idMal 62542   ✅
/// search "碧蓝之海"             → 404                            ❌
/// ```
///
/// **注意最后一条**：AniList 的搜索不认中文标题，只匹配罗马音 / 英文 / 日文原名。
/// 而 NipaPlay 手上的 `animeTitle` 通常是中文译名，所以调用方必须提供多个候选
/// 标题（原名、日文名、别名），本类会逐个试。
///
/// ## 季度消歧
///
/// 「Grand Blue」能搜到 S1，但「碧蓝之海 第二季」这种中文季度名搜不到。因此
/// 本类会从标题里识别季度后缀（`第二季` / `Season 2` / `2nd Season` / `S2`），
/// 换算成 AniList 上通用的 `Season N` 形式再搜一次。同时用 `startDate.year`
/// 与详情里的放送年份做交叉校验，年份对不上就宁可放弃——错跳片头比不跳更糟。
class SkipIdResolver {
  SkipIdResolver._();

  static const String _anilistEndpoint = 'https://graphql.anilist.co';

  /// AniList 偶尔会抖，给足超时但不要无限等。
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// `标题组合 + 年份 -> malId` 缓存，key 见 [_titleCacheKey]。
  ///
  /// 值允许为 null：AniList 确实搜不到（或年份校验不过）是稳定事实，缓存下来
  /// 省得反复打网。但**请求失败**（网络异常、非 200）的答案不缓存——否则一次
  /// 抖动会把这部番永久记成「无 MAL ID」，整个会话都错过 AniSkip 标注。
  static final Map<String, int?> _malFromTitleCache = {};

  /// 进行中的解析，合并并发调用。
  static final Map<String, Future<_ResolveOutcome>> _inflight = {};

  /// 缓存条目上限（按「番」计，比按集数少得多，所以阈值也小一些）。
  ///
  /// 同样是静态缓存、不重启不释放，必须设上限。128 部番远超一次会话的用量。
  static const int _maxCacheEntries = 128;

  /// 从弹弹play 剧集详情里取出 Bangumi 条目 ID。
  ///
  /// 复用首页缩略图那套已经跑通的解析方式：优先 `bangumiUrl` 里的
  /// `bangumi.tv/subject/<数字>`，其次直接读 `bangumiId` 字段（`'0'` 视为无）。
  static int? extractBangumiIdFromDetails(Map<String, dynamic> details) {
    if (details['success'] != true) return null;
    final bangumi = details['bangumi'];
    if (bangumi is! Map) return null;

    final bangumiUrl = bangumi['bangumiUrl']?.toString();
    if (bangumiUrl != null && bangumiUrl.contains('bangumi.tv/subject/')) {
      final match = RegExp(r'bangumi\.tv/subject/(\d+)').firstMatch(bangumiUrl);
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!);
        if (parsed != null && parsed > 0) return parsed;
      }
    }

    final direct = bangumi['bangumiId'];
    if (direct != null) {
      final parsed = int.tryParse(direct.toString());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  /// 通过候选标题解析 MAL ID。
  ///
  /// [titles] 按可信度从高到低排列（一般：番剧原名 > 日文名 > 中文译名 > 别名）。
  /// [premiereYear] 是本番的放送年份，若提供则用于交叉校验，年份不符的候选直接
  /// 丢弃——这是防「同名不同番」的最后一道闸。
  ///
  /// 所有候选都失败时返回 null（而不是抛异常），由调用方静默降级。
  static Future<int?> resolveMalIdFromTitles(
    Iterable<String?> titles, {
    int? premiereYear,
  }) async {
    final candidates = <String>[];
    final seen = <String>{};
    for (final title in titles) {
      final trimmed = title?.trim();
      if (trimmed == null || trimmed.isEmpty) continue;
      // 纯数字 / 过短的名字搜出来必然是噪声，直接跳过
      if (trimmed.length < 2) continue;
      if (seen.add(trimmed)) candidates.add(trimmed);
    }
    if (candidates.isEmpty) return null;

    final cacheKey = _titleCacheKey(candidates, premiereYear);
    if (_malFromTitleCache.containsKey(cacheKey)) {
      return _malFromTitleCache[cacheKey];
    }

    final inflight = _inflight[cacheKey];
    if (inflight != null) return (await inflight).malId;

    final request = _requestMalIdFromTitles(candidates, premiereYear);
    _inflight[cacheKey] = request;
    try {
      final outcome = await request;
      if (outcome.definitive) {
        _malFromTitleCache[cacheKey] = outcome.malId;
        _evictCacheIfNeeded();
      }
      return outcome.malId;
    } finally {
      if (identical(_inflight[cacheKey], request)) {
        _inflight.remove(cacheKey);
      }
    }
  }

  /// 淘汰最旧的缓存条目，把规模压回 [_maxCacheEntries] 以内。
  static void _evictCacheIfNeeded() {
    final excess = _malFromTitleCache.length - _maxCacheEntries;
    if (excess <= 0) return;
    final oldest = _malFromTitleCache.keys.take(excess).toList(growable: false);
    for (final key in oldest) {
      _malFromTitleCache.remove(key);
    }
  }

  static String _titleCacheKey(List<String> titles, int? year) =>
      '${titles.join('|')}#${year ?? 0}';

  static Future<_ResolveOutcome> _requestMalIdFromTitles(
    List<String> titles,
    int? premiereYear,
  ) async {
    // 每个候选标题展开成「原标题 + 带季度后缀的变体」，逐个试。
    // 只要有任何一跳是「请求失败」而非「确定没有」，最终结论就标记为不确定，
    // 调用方据此放弃入缓存（见 _malFromTitleCache 注释）。
    var definitive = true;
    for (final title in titles) {
      final variants = _searchVariants(title);
      for (final variant in variants) {
        final outcome = await _searchAniList(variant, premiereYear);
        if (outcome.malId != null) {
          debugPrint('[跳过片头] "$variant" → MAL ${outcome.malId}');
          return outcome;
        }
        if (!outcome.definitive) definitive = false;
      }
    }
    debugPrint('[跳过片头] 所有候选标题都没能在 AniList 上定位: $titles'
        '${definitive ? '' : '（含请求失败，结果不缓存）'}');
    return (malId: null, definitive: definitive);
  }

  /// 由标题生成搜索变体。
  ///
  /// 已经带 `Season N` 的原样返回；带中文季度后缀的换算成 `Season N`
  /// （因为 AniList 的条目名是罗马音的 `X Season 2`）；不带季度的补一个
  /// `Season 1` 变体，方便命中「第一季条目名带 Season 1」的情况。
  static List<String> _searchVariants(String title) {
    final variants = <String>[title];

    final chineseSeason = _chineseSeasonNumber(title);
    if (chineseSeason != null) {
      // 「碧蓝之海 第二季」→「碧蓝之海 Season 2」
      final base =
          title.replaceAll(RegExp(r'\s*第[一二三四五六七八九十\d]+[季期部]\s*'), ' ').trim();
      if (base.isNotEmpty) {
        variants.insert(0, '$base Season $chineseSeason');
        variants.add(base);
      }
    }

    // 带 `Season N` 的补一个去掉后缀的基础名（有些条目就是没有后缀）
    final seasonMatch = RegExp(r'\s*Season\s*(\d+)\s*$', caseSensitive: false)
        .firstMatch(title);
    if (seasonMatch != null) {
      final base = title.substring(0, seasonMatch.start).trim();
      if (base.length >= 2) variants.add(base);
    }

    // 什么季度信息都没有的，补一个 `Season 1` 变体：出了续季后，第一季条目名
    // 常被改成 "X Season 1"（如 "Grand Blue Season 1"），裸名会搜到合集条目或
    // 错季。放在原标题之后，只有原标题没命中才会用到，不拖累主路径。
    if (chineseSeason == null && seasonMatch == null) {
      variants.add('$title Season 1');
    }

    return variants;
  }

  static int? _chineseSeasonNumber(String title) {
    final arabic = RegExp(r'第\s*(\d{1,2})\s*[季期部]').firstMatch(title);
    if (arabic != null) {
      final parsed = int.tryParse(arabic.group(1)!);
      if (parsed != null && parsed > 1) return parsed;
    }
    final chinese =
        RegExp(r'第\s*([一二三四五六七八九十]{1,2})\s*[季期部]').firstMatch(title);
    if (chinese != null) {
      final parsed = _parseChineseNumber(chinese.group(1)!);
      if (parsed != null && parsed > 1) return parsed;
    }
    return null;
  }

  static int? _parseChineseNumber(String text) {
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (text == '十') return 10;
    if (text.length == 1) return digits[text];
    // 十一 ~ 十九 / 二十 / 二十一…
    if (text.startsWith('十')) {
      final rest = digits[text.substring(1)];
      return rest == null ? null : 10 + rest;
    }
    if (text.startsWith('二') && text.length == 2 && text[1] == '十') return 20;
    if (text.length == 2 && text[1] == '十') {
      final tens = digits[text[0]];
      return tens == null ? null : tens * 10;
    }
    return null;
  }

  /// 调 AniList 搜索单个标题，返回 `idMal`。
  ///
  /// 返回值语义（记录类型见 [_ResolveOutcome]）：
  /// - `(idMal, true)` 命中；
  /// - `(null, true)` 确定没有（无匹配条目 / 无 idMal / 年份校验不过）；
  /// - `(null, false)` 请求失败或响应异常（非 200、结构不可解析、抛异常），
  ///   结论不可信，不得缓存。
  static Future<_ResolveOutcome> _searchAniList(
      String title, int? premiereYear) async {
    const query = r'''
query ($search: String) {
  Media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
    id
    idMal
    format
    startDate { year }
    title { romaji native english }
  }
}''';

    try {
      final response = await http
          .post(
            WebRemoteAccessService.proxyUri(Uri.parse(_anilistEndpoint)),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query': query,
              'variables': {'search': title},
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        debugPrint('[跳过片头] AniList 搜索 "$title" 返回 HTTP ${response.statusCode}');
        return (malId: null, definitive: false);
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return (malId: null, definitive: false);
      }
      final data = decoded['data'];
      if (data is! Map) return (malId: null, definitive: false);
      final media = data['Media'];
      if (media is! Map) {
        // AniList 正常返回，只是没有匹配条目——这是确定答案。
        return (malId: null, definitive: true);
      }

      final idMal = _toInt(media['idMal']);
      if (idMal == null || idMal <= 0) {
        debugPrint('[跳过片头] AniList 命中 "$title" 但没有 idMal');
        return (malId: null, definitive: true);
      }

      // 年份交叉校验：只在我们确实知道年份、且 AniList 也给了年份时生效。
      final anilistYear = media['startDate'] is Map
          ? _toInt((media['startDate'] as Map)['year'])
          : null;
      if (premiereYear != null && anilistYear != null) {
        // 允许 1 年误差：跨年番 / 首播与放送年份记法不一致很常见。
        if ((anilistYear - premiereYear).abs() > 1) {
          debugPrint(
              '[跳过片头] AniList 命中 "$title" 年份不符（本地 $premiereYear vs $anilistYear），放弃');
          return (malId: null, definitive: true);
        }
      }

      return (malId: idMal, definitive: true);
    } catch (e) {
      debugPrint('[跳过片头] AniList 搜索 "$title" 失败: $e');
      return (malId: null, definitive: false);
    }
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// 清空内存缓存（测试用）。
  @visibleForTesting
  static void clearCache() {
    _malFromTitleCache.clear();
    _inflight.clear();
  }
}
