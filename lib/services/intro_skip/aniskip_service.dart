import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart' as http;
import 'package:nipaplay/services/web_remote_access_service.dart';

import 'skip_segment.dart';

/// SkipType 到本项目区间类型的映射结果。
///
/// AniSkip 的 `skipType` 目前有 `op` / `ed` / `mixed-op` / `mixed-ed` / `recap`
/// 五种。`mixed-*` 是「混合了正片片段」的片头/片尾，跳过会丢内容，因此**刻意
/// 不采纳**——宁可少跳，不可错跳。`recap`（回顾）不是每集都有，跳过与否见仁见智，
/// 同样不采纳。
SkipSegmentKind? _kindFromSkipType(String skipType) {
  switch (skipType) {
    case 'op':
      return SkipSegmentKind.opening;
    case 'ed':
      return SkipSegmentKind.ending;
    default:
      return null;
  }
}

/// AniSkip（<https://aniskip.com>）社区标注库客户端。
///
/// 只做一件事：给定 MAL ID + 集数，取回该集的片头 / 片尾精确区间。
///
/// 与 NipaPlay 的关系：NipaPlay 手上只有弹弹play 的 `animeId`，而 AniSkip 以
/// **MAL ID** 为键。ID 之间的桥接由调用方完成（见 `VideoPlayerStateSkipSegments`
/// 里的 `_resolveMalId` 流程），本类只负责「拿到 MAL ID 之后的事」，保持职责单一。
///
/// 网络约定：AniSkip 是免鉴权的公开 API，因此走 `getSubjectComments` 那套
/// 直连 + [WebRemoteAccessService.proxyUri] 的模式，而不是 BangumiApiService
/// 里需要访问令牌的 `_makeRequest`。
class AniSkipService {
  AniSkipService._();

  static final AniSkipService instance = AniSkipService._();

  static const String _baseUrl = 'https://api.aniskip.com';

  /// 单次请求超时。AniSkip 偶发抖动，超时就当没数据，绝不阻塞播放。
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// 结果缓存：key 为 `malId:episode`。
  ///
  /// 一集的结果在一场播放里是常量，缓存可避免切集来回时重复打网络。
  /// 只做内存缓存，不做落盘——AniSkip 数据会更正，本地长期存一份反而会存到错值。
  static final Map<String, List<SkipSegment>> _cache = {};

  /// 进行中的请求，用于合并同一 key 的并发调用（切集抖动时会出现）。
  ///
  /// 值为 null 表示「请求失败」（可重试），区别于空列表的「确认无标注」；
  /// 只有非 null 结果才写入缓存，见 [fetchSkipTimes]。
  static final Map<String, Future<List<SkipSegment>?>> _inflight = {};

  /// 缓存条目上限。超出后按插入顺序淘汰最旧的（Dart 的 Map 保序）。
  ///
  /// 连看长篇动画时每集一个条目，几百集也就几十 KB，本来不值得淘汰；
  /// 但这是**静态**缓存，应用不重启就不会释放，不设上限等于让一个锦上添花
  /// 的功能无限期占用内存。256 条足够覆盖连播加来回切集。
  static const int _maxCacheEntries = 256;

  /// 取回指定集的跳过区间。
  ///
  /// - [malId]：MyAnimeList 的动画 ID，必须 > 0。
  /// - [episodeNumber]：集数，从 1 开始。
  /// - [episodeLengthSeconds]：本集时长（秒）。AniSkip 会用它来校验标注是否
  ///   与本集匹配——传 null 或 0 时服务端照常返回，但可能给出别的片长版本的区间，
  ///   因此调用方能拿到时长时应当尽量传。
  ///
  /// 结果分两类：**确认无标注**（`found == false`、无可用区间）缓存空列表；
  /// **请求失败**（网络异常、超时、非 200、响应不可解析）不缓存，下次调用可重试。
  /// 两类对外都表现为返回空列表，由调用方静默降级——跳过片头是锦上添花，
  /// 不许它影响播放。失败若不区分就会一次抖动把该集永久记成「无数据」，
  /// 与本文件「本地存久了会存到错值」的顾虑同理。
  Future<List<SkipSegment>> fetchSkipTimes({
    required int malId,
    required int episodeNumber,
    double? episodeLengthSeconds,
  }) async {
    if (malId <= 0 || episodeNumber <= 0) return const [];

    final cacheKey = '$malId:$episodeNumber';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final inflight = _inflight[cacheKey];
    if (inflight != null) return (await inflight) ?? const [];

    final request = _requestSkipTimes(
      malId: malId,
      episodeNumber: episodeNumber,
      episodeLengthSeconds: episodeLengthSeconds,
    );
    _inflight[cacheKey] = request;
    try {
      final segments = await request;
      if (segments != null) {
        _cache[cacheKey] = segments;
        _evictCacheIfNeeded();
        return segments;
      }
      return const [];
    } finally {
      if (identical(_inflight[cacheKey], request)) {
        _inflight.remove(cacheKey);
      }
    }
  }

  /// 淘汰最旧的缓存条目，把规模压回 [_maxCacheEntries] 以内。
  static void _evictCacheIfNeeded() {
    final excess = _cache.length - _maxCacheEntries;
    if (excess <= 0) return;
    final oldest = _cache.keys.take(excess).toList(growable: false);
    for (final key in oldest) {
      _cache.remove(key);
    }
  }

  /// 发一次真实请求。返回值语义：
  /// - 空/非空列表 = 请求成功，结果是**确定的**（可入缓存）；
  /// - null = 请求失败或响应不可信（超时、非 200、JSON 结构异常），**可重试**，
  ///   调用方不得缓存。
  Future<List<SkipSegment>?> _requestSkipTimes({
    required int malId,
    required int episodeNumber,
    double? episodeLengthSeconds,
  }) async {
    final query = <String>['types[]=op', 'types[]=ed'];
    if (episodeLengthSeconds != null && episodeLengthSeconds > 0) {
      query.add('episodeLength=${episodeLengthSeconds.round()}');
    }
    final uri = Uri.parse(
      '$_baseUrl/v2/skip-times/$malId/$episodeNumber?${query.join('&')}',
    );

    try {
      final response =
          await http.get(WebRemoteAccessService.proxyUri(uri), headers: {
        'Accept': 'application/json',
      }).timeout(_requestTimeout);

      if (response.statusCode != 200) {
        debugPrint('[跳过片头] AniSkip 返回 HTTP ${response.statusCode}（$uri）');
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;

      // found=false 是常态（新番、冷门番、剧场版），是确定答案，不算错误。
      if (decoded['found'] != true) {
        debugPrint('[跳过片头] AniSkip 无标注数据（MAL $malId 第 $episodeNumber 集）');
        return const [];
      }

      final results = decoded['results'];
      if (results is! List) return null;

      final segments = <SkipSegment>[];
      for (final raw in results) {
        if (raw is! Map) continue;
        final skipType = raw['skipType']?.toString() ?? '';
        final kind = _kindFromSkipType(skipType);
        if (kind == null) continue; // mixed-op / mixed-ed / recap 一律不采纳

        final interval = raw['interval'];
        if (interval is! Map) continue;
        final start = _toDouble(interval['startTime']);
        final end = _toDouble(interval['endTime']);
        if (start == null || end == null || end <= start) continue;

        segments.add(SkipSegment(
          kind: kind,
          source: SkipSegmentSource.aniskip,
          startSeconds: start,
          endSeconds: end,
        ));
      }

      debugPrint(
          '[跳过片头] AniSkip 命中 ${segments.length} 段（MAL $malId 第 $episodeNumber 集）: $segments');
      return List<SkipSegment>.unmodifiable(segments);
    } catch (e) {
      debugPrint('[跳过片头] AniSkip 请求失败，本次降级（不缓存，下次可重试）: $e');
      return null;
    }
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// 清空内存缓存（测试用）。
  @visibleForTesting
  void clearCache() {
    _cache.clear();
    _inflight.clear();
  }
}
