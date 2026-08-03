import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/trending_bangumi.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/utils/chinese_converter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrendingBangumiService {
  TrendingBangumiService._({http.Client? client})
      : _client = client ?? http.Client(),
        _delay = Future<void>.delayed;

  @visibleForTesting
  TrendingBangumiService.forTesting({
    required http.Client client,
    Future<void> Function(Duration duration)? delay,
  })  : _client = client,
        _delay = delay ?? Future<void>.delayed;

  static final TrendingBangumiService instance = TrendingBangumiService._();

  static const Duration _cacheDuration = Duration(hours: 1);
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const int _maxNetworkAttempts = 3;
  static const String _cacheKeyPrefix = 'dandanplay_trending_cache_';

  final http.Client _client;
  final Future<void> Function(Duration duration) _delay;
  final Map<String, TrendingBangumiResult> _memoryCache = {};
  final Map<String, DateTime> _memoryCacheTimes = {};

  Future<TrendingBangumiResult> fetch(
    TrendingBangumiQuery query, {
    bool forceRefresh = false,
    bool filterAdultContent = true,
    int limit = 20,
    ValueChanged<TrendingRetryProgress>? onRetry,
  }) async {
    final safeLimit = limit.clamp(1, 50);
    final cacheId = '${query.cacheKey}_${filterAdultContent}_$safeLimit';

    if (!forceRefresh) {
      final memory = _readMemoryCache(cacheId);
      if (memory != null) return memory;

      final disk = await _readDiskCache(cacheId, allowExpired: false);
      if (disk != null) {
        _remember(cacheId, disk.result, disk.timestamp);
        return disk.result;
      }
    }

    try {
      final result = await _fetchFromNetworkWithRetry(
        query,
        filterAdultContent: filterAdultContent,
        limit: safeLimit,
        onRetry: onRetry,
      );
      final timestamp = DateTime.now();
      _remember(cacheId, result, timestamp);
      await _writeDiskCache(cacheId, result, timestamp);
      return result;
    } catch (error) {
      debugPrint('[TrendingBangumiService] 排行榜请求失败，尝试旧缓存: $error');
      final stale = await _readDiskCache(cacheId, allowExpired: true);
      if (stale != null) {
        _remember(cacheId, stale.result, stale.timestamp);
        return stale.result;
      }
      rethrow;
    }
  }

  Future<TrendingBangumiResult> _fetchFromNetworkWithRetry(
    TrendingBangumiQuery query, {
    required bool filterAdultContent,
    required int limit,
    ValueChanged<TrendingRetryProgress>? onRetry,
  }) async {
    for (var attempt = 1; attempt <= _maxNetworkAttempts; attempt++) {
      try {
        return await _fetchFromNetwork(
          query,
          filterAdultContent: filterAdultContent,
          limit: limit,
        );
      } catch (error) {
        final canRetry = attempt < _maxNetworkAttempts && _isRetryable(error);
        if (!canRetry) rethrow;

        final retryNumber = attempt;
        final delay = _retryDelay(retryNumber);
        debugPrint(
          '[TrendingBangumiService] 请求失败，${delay.inMilliseconds}ms 后自动重试 '
          '$retryNumber/${_maxNetworkAttempts - 1}: $error',
        );
        onRetry?.call(
          TrendingRetryProgress(
            retryNumber: retryNumber,
            maxRetries: _maxNetworkAttempts - 1,
            delay: delay,
          ),
        );
        await _delay(delay);
      }
    }
    throw StateError('排行榜请求重试状态异常');
  }

  bool _isRetryable(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }
    if (error is FormatException || error is _TrendingApiException) {
      return true;
    }
    if (error is _TrendingHttpException) {
      return error.statusCode == 408 ||
          error.statusCode == 425 ||
          error.statusCode == 429 ||
          error.statusCode >= 500;
    }
    return false;
  }

  Duration _retryDelay(int retryNumber) {
    return switch (retryNumber) {
      1 => const Duration(milliseconds: 500),
      _ => const Duration(milliseconds: 1200),
    };
  }

  TrendingBangumiResult? _readMemoryCache(String cacheId) {
    final result = _memoryCache[cacheId];
    final timestamp = _memoryCacheTimes[cacheId];
    if (result == null || timestamp == null) return null;
    if (DateTime.now().difference(timestamp) > _cacheDuration) return null;
    return result;
  }

  void _remember(
    String cacheId,
    TrendingBangumiResult result,
    DateTime timestamp,
  ) {
    _memoryCache[cacheId] = result;
    _memoryCacheTimes[cacheId] = timestamp;
  }

  Future<TrendingBangumiResult> _fetchFromNetwork(
    TrendingBangumiQuery query, {
    required bool filterAdultContent,
    required int limit,
  }) async {
    final baseUrl = await DandanplayService.getApiBaseUrl();
    final uri = Uri.parse('$baseUrl${query.apiPath}').replace(
      queryParameters: {
        'filterAdultContent': '$filterAdultContent',
        'limit': '$limit',
      },
    );
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    final appSecret = await DandanplayService.getAppSecret();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('dandanplay_token');
    final response = await _client.get(
      WebRemoteAccessService.proxyUri(uri),
      headers: {
        'Accept': 'application/json',
        'User-Agent': DandanplayService.userAgent,
        'X-AppId': DandanplayService.appId,
        'X-Timestamp': '$timestamp',
        'X-Signature': DandanplayService.generateSignature(
          DandanplayService.appId,
          timestamp,
          query.apiPath,
          appSecret,
        ),
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw _TrendingHttpException(response.statusCode);
    }
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      final message =
          decoded is Map ? decoded['errorMessage']?.toString() : null;
      throw _TrendingApiException(message ?? 'Invalid trending payload');
    }

    final parsed = TrendingBangumiResult.fromJson(decoded);
    final convertedItems = <TrendingBangumiItem>[];
    for (final item in parsed.items) {
      convertedItems.add(
        item.copyWith(anime: await ChineseConverter.convertAnime(item.anime)),
      );
    }
    return TrendingBangumiResult(
      summary: parsed.summary,
      items: convertedItems,
    );
  }

  Future<void> _writeDiskCache(
    String cacheId,
    TrendingBangumiResult result,
    DateTime timestamp,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_cacheKeyPrefix$cacheId',
        json.encode({
          'timestamp': timestamp.millisecondsSinceEpoch,
          'result': result.toJson(),
        }),
      );
    } catch (error) {
      debugPrint('[TrendingBangumiService] 写入缓存失败: $error');
    }
  }

  Future<_CachedTrendingResult?> _readDiskCache(
    String cacheId, {
    required bool allowExpired,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cacheKeyPrefix$cacheId');
      if (raw == null || raw.isEmpty) return null;
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final timestampMs = (decoded['timestamp'] as num?)?.toInt();
      final rawResult = decoded['result'];
      if (timestampMs == null || rawResult is! Map) return null;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      if (!allowExpired &&
          DateTime.now().difference(timestamp) > _cacheDuration) {
        return null;
      }
      return _CachedTrendingResult(
        result: TrendingBangumiResult.fromJson(
          rawResult.cast<String, dynamic>(),
        ),
        timestamp: timestamp,
      );
    } catch (_) {
      return null;
    }
  }
}

class TrendingRetryProgress {
  const TrendingRetryProgress({
    required this.retryNumber,
    required this.maxRetries,
    required this.delay,
  });

  final int retryNumber;
  final int maxRetries;
  final Duration delay;
}

class _TrendingHttpException implements Exception {
  const _TrendingHttpException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode';
}

class _TrendingApiException implements Exception {
  const _TrendingApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CachedTrendingResult {
  const _CachedTrendingResult({
    required this.result,
    required this.timestamp,
  });

  final TrendingBangumiResult result;
  final DateTime timestamp;
}
