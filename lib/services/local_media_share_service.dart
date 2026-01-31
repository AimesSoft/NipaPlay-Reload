import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/utils/storage_service.dart';

class SharedEpisodeInfo {
  SharedEpisodeInfo({
    required this.shareId,
    required this.historyItem,
  });

  final String shareId;
  final WatchHistoryItem historyItem;

  Future<Map<String, dynamic>> toJson() async {
    bool exists = false;
    int? fileSize;
    DateTime? modifiedTime;
    String? streamPath;

    final lowerPath = historyItem.filePath.toLowerCase();
    final isNetwork = lowerPath.startsWith('http://') ||
        lowerPath.startsWith('https://') ||
        lowerPath.startsWith('jellyfin://') ||
        lowerPath.startsWith('emby://');

    if (!isNetwork) {
      final file = File(historyItem.filePath);
      try {
        exists = await file.exists();
        if (exists) {
          fileSize = await file.length();
          modifiedTime = await file.lastModified();
        }
      } catch (_) {
        exists = false;
        fileSize = null;
        modifiedTime = null;
      }
      streamPath = '/api/media/local/share/episodes/$shareId/stream';
    } else {
      exists = true; // Assume network resources exist if they are in history
      streamPath = null; // No direct stream path for network resources, client uses filePath
    }

    return {
      'shareId': shareId,
      'episodeId': historyItem.episodeId,
      'animeId': historyItem.animeId,
      'title': historyItem.episodeTitle ?? p.basenameWithoutExtension(historyItem.filePath),
      'fileName': p.basename(historyItem.filePath),
      'fileExists': exists,
      'fileSize': fileSize,
      'lastModified': modifiedTime?.toIso8601String(),
      'lastWatchTime': historyItem.lastWatchTime.toIso8601String(),
      'duration': historyItem.duration,
      'lastPosition': historyItem.lastPosition,
      'progress': historyItem.watchProgress,
      'streamPath': streamPath,
      'videoHash': historyItem.videoHash,
      'source': _detectSource(historyItem.filePath),
      'originalFilePath': historyItem.filePath, // Explicitly pass original path
    };
  }

  static String _detectSource(String path) {
    final lower = path.toLowerCase();
    if (lower.startsWith('jellyfin://')) return 'Jellyfin';
    if (lower.startsWith('emby://')) return 'Emby';
    if (lower.startsWith('http://') || lower.startsWith('https://')) return 'Network';
    if (lower.startsWith('smb://')) return 'SMB';
    return 'Local';
  }
}

class SharedAnimeBundle {
  SharedAnimeBundle({
    required this.animeId,
    required this.episodes,
  });

  final int animeId;
  final List<SharedEpisodeInfo> episodes;

  DateTime get latestWatchTime => episodes
      .map((e) => e.historyItem.lastWatchTime)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

class LocalMediaShareService {
  LocalMediaShareService._internal() {
    _initialize();
  }

  static final LocalMediaShareService instance = LocalMediaShareService._internal();

  final Map<String, SharedEpisodeInfo> _shareEpisodeMap = {};
  final Map<int, SharedAnimeBundle> _animeBundleMap = {};
  final Map<int, BangumiAnime?> _animeDetailCache = {};
  final Set<int> _animeDetailFetching = <int>{};
  DateTime? _lastCacheUpdate;
  bool _isListeningWatchHistory = false;

  void _initialize() {
    _rebuildCache();

    try {
      final watchHistory = ServiceProvider.watchHistoryProvider;
      if (!_isListeningWatchHistory) {
        watchHistory.addListener(_handleWatchHistoryChanged);
        _isListeningWatchHistory = true;
      }
    } catch (e) {
      // ignore: avoid_print
      print('LocalMediaShareService: failed to attach listener: $e');
    }
  }

  void _handleWatchHistoryChanged() {
    _rebuildCache();
  }

  void _rebuildCache() {
    final watchHistory = ServiceProvider.watchHistoryProvider;
    if (!watchHistory.isLoaded) {
      _shareEpisodeMap.clear();
      _animeBundleMap.clear();
      _lastCacheUpdate = DateTime.now();
      return;
    }

    final localItems = watchHistory.history.toList();

    final Map<String, SharedEpisodeInfo> shareIdMap = {};
    final Map<int, List<SharedEpisodeInfo>> animeMap = {};

    for (final item in localItems) {
      if (item.animeId == null) {
        continue;
      }
      final shareId = _generateShareId(item.filePath);
      final sharedEpisode = SharedEpisodeInfo(shareId: shareId, historyItem: item);
      shareIdMap[shareId] = sharedEpisode;
      animeMap.putIfAbsent(item.animeId!, () => <SharedEpisodeInfo>[]).add(sharedEpisode);
    }

    _shareEpisodeMap
      ..clear()
      ..addAll(shareIdMap);

    _animeBundleMap
      ..clear()
      ..addEntries(animeMap.entries.map((entry) {
        // 按最新观看时间排序，最新的在前
        entry.value.sort((a, b) => b.historyItem.lastWatchTime.compareTo(a.historyItem.lastWatchTime));
        return MapEntry(entry.key, SharedAnimeBundle(animeId: entry.key, episodes: entry.value));
      }));

    _lastCacheUpdate = DateTime.now();
  }

  String _generateShareId(String filePath) {
    final normalized = p.normalize(filePath);
    final bytes = utf8.encode(normalized);
    return sha1.convert(bytes).toString();
  }

  Future<List<Map<String, dynamic>>> getAnimeSummaries() async {
    if (_animeBundleMap.isEmpty) {
      _rebuildCache();
    }

    final bundles = _animeBundleMap.values.toList()
      ..sort((a, b) => b.latestWatchTime.compareTo(a.latestWatchTime));

    // 预取部分番剧详情（异步，不阻塞 API），避免一次性触发过多请求
    for (final bundle in bundles.take(24)) {
      _prefetchAnimeDetail(bundle.animeId);
    }

    final List<Map<String, dynamic>> summaries = [];
    for (final bundle in bundles) {
      final detail = _peekAnimeDetail(bundle.animeId);
      final fallbackName = bundle.episodes.first.historyItem.animeName;
      summaries.add({
        'animeId': bundle.animeId,
        'name': detail?.name ?? fallbackName,
        'nameCn': detail?.nameCn ?? fallbackName,
        'summary': detail?.summary ?? '',
        'imageUrl': detail?.imageUrl,
        'tags': detail?.tags ?? const <dynamic>[],
        'totalEpisodes': detail?.totalEpisodes,
        'lastWatchTime': bundle.latestWatchTime.toIso8601String(),
        'episodeCount': bundle.episodes.length,
        'source': bundle.episodes.first.historyItem.isFromScan ? 'Scan' : 'Local',
        'hasMissingFiles': bundle.episodes.any((ep) => !File(ep.historyItem.filePath).existsSync()),
        'lastShareUpdate': _lastCacheUpdate?.toIso8601String(),
      });
    }

    return summaries;
  }

  Future<Map<String, dynamic>?> getAnimeDetail(int animeId) async {
    final bundle = _animeBundleMap[animeId];
    if (bundle == null) {
      return null;
    }

    final detail = _peekAnimeDetail(animeId);
    _prefetchAnimeDetail(animeId);
    final fallbackName = bundle.episodes.first.historyItem.animeName;

    final episodeJsonList = <Map<String, dynamic>>[];
    for (final episode in bundle.episodes) {
      episodeJsonList.add(await episode.toJson());
    }

    return {
      'anime': {
        'animeId': animeId,
        'name': detail?.name ?? fallbackName,
        'nameCn': detail?.nameCn ?? fallbackName,
        'summary': detail?.summary ?? '',
        'imageUrl': detail?.imageUrl,
        'rating': detail?.rating,
        'ratingDetails': detail?.ratingDetails,
        'airDate': detail?.airDate,
        'airWeekday': detail?.airWeekday,
        'totalEpisodes': detail?.totalEpisodes,
        'tags': detail?.tags ?? const <dynamic>[],
        'lastWatchTime': bundle.latestWatchTime.toIso8601String(),
        'episodeCount': bundle.episodes.length,
        'lastShareUpdate': _lastCacheUpdate?.toIso8601String(),
      },
      'episodes': episodeJsonList,
    };
  }

  Future<List<Map<String, dynamic>>> getWatchHistory({int limit = 100}) async {
    if (_shareEpisodeMap.isEmpty) {
      _rebuildCache();
    }

    final int sanitizedLimit = limit.clamp(1, 500);

    final episodes = _shareEpisodeMap.values.toList()
      ..sort((a, b) => b.historyItem.lastWatchTime.compareTo(a.historyItem.lastWatchTime));

    // 预取部分番剧详情（异步，不阻塞 API）
    for (final entry in episodes.take(sanitizedLimit).take(24)) {
      final animeId = entry.historyItem.animeId;
      if (animeId != null) {
        _prefetchAnimeDetail(animeId);
      }
    }

    final List<Map<String, dynamic>> items = [];
    for (final entry in episodes.take(sanitizedLimit)) {
      final baseJson = await entry.toJson();
      final animeId = entry.historyItem.animeId;
      final detail = animeId != null ? _peekAnimeDetail(animeId) : null;

      final resolvedName = (detail?.nameCn ?? '').trim().isNotEmpty
          ? detail!.nameCn
          : (detail?.name ?? entry.historyItem.animeName);

      items.add({
        ...baseJson,
        'animeName': resolvedName,
        'imageUrl': detail?.imageUrl ?? entry.historyItem.thumbnailPath,
      });
    }

    return items;
  }

  SharedEpisodeInfo? getEpisodeByShareId(String shareId) {
    return _shareEpisodeMap[shareId];
  }

  BangumiAnime? _peekAnimeDetail(int animeId) {
    if (!_animeDetailCache.containsKey(animeId)) return null;
    return _animeDetailCache[animeId];
  }

  void _prefetchAnimeDetail(int animeId) {
    if (_animeDetailCache.containsKey(animeId)) {
      return;
    }
    if (_animeDetailFetching.contains(animeId)) {
      return;
    }

    _animeDetailFetching.add(animeId);
    BangumiService.instance.getAnimeDetails(animeId).then((detail) {
      _animeDetailCache[animeId] = detail;
    }).catchError((_) {
      _animeDetailCache[animeId] = null;
    }).whenComplete(() {
      _animeDetailFetching.remove(animeId);
    });
  }

  String determineContentType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.mkv':
        return 'video/x-matroska';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      case '.flv':
        return 'video/x-flv';
      case '.ts':
      case '.mpeg':
      case '.mpg':
        return 'video/mpeg';
      case '.webm':
        return 'video/webm';
      case '.mp3':
        return 'audio/mpeg';
      case '.flac':
        return 'audio/flac';
      case '.aac':
        return 'audio/aac';
      case '.wav':
        return 'audio/wav';
      case '.ass':
      case '.ssa':
        return 'text/plain';
      case '.srt':
        return 'application/x-subrip';
      default:
        return 'application/octet-stream';
    }
  }

  Future<Response> buildStreamResponse(
    Request request,
    SharedEpisodeInfo episode, {
    bool headOnly = false,
  }) async {
    final file = File(episode.historyItem.filePath);
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    final totalLength = await file.length();
    final contentType = determineContentType(file.path);
    final contentDisposition = _buildContentDispositionHeader(p.basename(file.path));
    final rangeHeader = request.headers['range'];

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        final startStr = match.group(1);
        final endStr = match.group(2);
        final start = startStr != null && startStr.isNotEmpty ? int.parse(startStr) : 0;
        final end = endStr != null && endStr.isNotEmpty ? int.parse(endStr) : totalLength - 1;
        if (start >= totalLength) {
          return Response(
            HttpStatus.requestedRangeNotSatisfiable,
            headers: {
              'Content-Range': 'bytes */$totalLength',
            },
          );
        }
        final adjustedEnd = end >= totalLength ? totalLength - 1 : end;
        final chunkSize = adjustedEnd - start + 1;
        final stream = headOnly ? null : file.openRead(start, adjustedEnd + 1);
        return Response(
          HttpStatus.partialContent,
          body: stream,
          headers: {
            'Content-Type': contentType,
            'Content-Length': '$chunkSize',
            'Accept-Ranges': 'bytes',
            'Content-Range': 'bytes $start-$adjustedEnd/$totalLength',
            'Cache-Control': 'no-cache',
            'Content-Disposition': contentDisposition,
          },
        );
      }
    }

    final stream = headOnly ? null : file.openRead();
    return Response.ok(
      stream,
      headers: {
        'Content-Type': contentType,
        'Content-Length': '$totalLength',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
        'Content-Disposition': contentDisposition,
      },
    );
  }

  String _buildContentDispositionHeader(String fileName) {
    String sanitizeAsciiFallback(String value) {
      if (value.isEmpty) return 'file';
      final buffer = StringBuffer();
      for (final codeUnit in value.codeUnits) {
        final bool isAsciiPrintable = codeUnit >= 0x20 && codeUnit <= 0x7E;
        final bool isForbidden = codeUnit == 0x22 /* " */ || codeUnit == 0x5C /* \\ */;
        buffer.writeCharCode(
          isAsciiPrintable && !isForbidden ? codeUnit : 0x5F /* _ */,
        );
      }
      final sanitized = buffer.toString().trim();
      return sanitized.isEmpty ? 'file' : sanitized;
    }

    final fallbackName = sanitizeAsciiFallback(fileName);
    final encodedName = Uri.encodeComponent(fileName);
    return 'inline; filename="$fallbackName"; filename*=UTF-8\'\'$encodedName';
  }

  Future<WatchHistoryItem?> updateEpisodeProgress({
    required String shareId,
    double? progress,
    int? positionMs,
    int? durationMs,
    DateTime? clientUpdatedAt,
  }) async {
    SharedEpisodeInfo? episode = _shareEpisodeMap[shareId];
    if (episode == null) {
      _rebuildCache();
      episode = _shareEpisodeMap[shareId];
      if (episode == null) {
        return null;
      }
    }

    final watchHistory = ServiceProvider.watchHistoryProvider;
    final filePath = episode.historyItem.filePath;
    WatchHistoryItem? existingHistory = await watchHistory.getHistoryItem(filePath);
    existingHistory ??= episode.historyItem;

    final double sanitizedProgress = progress == null || progress.isNaN
        ? 0.0
        : progress.clamp(0.0, 1.0);
    final int sanitizedPosition = math.max(0, positionMs ?? 0);
    final int? sanitizedDuration = durationMs != null && durationMs > 0 ? durationMs : null;

    double derivedProgress = sanitizedProgress;
    if (derivedProgress <= 0 && sanitizedDuration != null && sanitizedDuration > 0) {
      derivedProgress = (sanitizedPosition / sanitizedDuration).clamp(0.0, 1.0);
    }

    final double mergedProgress = math.min(
      1.0,
      math.max(existingHistory.watchProgress, derivedProgress),
    );
    final int mergedPosition = math.max(existingHistory.lastPosition, sanitizedPosition);
    final int mergedDuration = sanitizedDuration != null
        ? math.max(existingHistory.duration, sanitizedDuration)
        : existingHistory.duration;

    final bool shouldUpdate =
        (mergedProgress - existingHistory.watchProgress).abs() > 1e-4 ||
            mergedPosition != existingHistory.lastPosition ||
            mergedDuration != existingHistory.duration;

    if (!shouldUpdate) {
      return existingHistory;
    }

    final updatedHistory = existingHistory.copyWith(
      watchProgress: mergedProgress,
      lastPosition: mergedPosition,
      duration: mergedDuration,
      lastWatchTime: clientUpdatedAt ?? DateTime.now(),
    );

    await watchHistory.addOrUpdateHistory(updatedHistory);
    return updatedHistory;
  }

  Future<WatchHistoryItem?> updateEpisodeThumbnail({
    required String shareId,
    required Uint8List thumbnailBytes,
    DateTime? clientUpdatedAt,
    String? format,
  }) async {
    if (thumbnailBytes.isEmpty) {
      return null;
    }

    SharedEpisodeInfo? episode = _shareEpisodeMap[shareId];
    if (episode == null) {
      _rebuildCache();
      episode = _shareEpisodeMap[shareId];
      if (episode == null) {
        return null;
      }
    }

    final watchHistory = ServiceProvider.watchHistoryProvider;
    final filePath = episode.historyItem.filePath;
    WatchHistoryItem? existingHistory = await watchHistory.getHistoryItem(filePath);
    existingHistory ??= episode.historyItem;

    final resolvedPath = await _resolveThumbnailPath(
      existingHistory.thumbnailPath,
      shareId: shareId,
      format: format,
    );
    if (resolvedPath == null) {
      return existingHistory;
    }

    final thumbnailFile = File(resolvedPath);
    await thumbnailFile.writeAsBytes(thumbnailBytes, flush: true);

    final DateTime mergedWatchTime;
    if (clientUpdatedAt != null &&
        clientUpdatedAt.isAfter(existingHistory.lastWatchTime)) {
      mergedWatchTime = clientUpdatedAt;
    } else {
      mergedWatchTime = existingHistory.lastWatchTime;
    }

    final updatedHistory = existingHistory.copyWith(
      thumbnailPath: resolvedPath,
      lastWatchTime: mergedWatchTime,
    );

    await watchHistory.addOrUpdateHistory(updatedHistory);
    return updatedHistory;
  }

  Future<String?> _resolveThumbnailPath(
    String? existingPath, {
    required String shareId,
    String? format,
  }) async {
    final sanitizedExisting = _sanitizeLocalThumbnailPath(existingPath);
    if (sanitizedExisting != null) {
      final dir = Directory(p.dirname(sanitizedExisting));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return sanitizedExisting;
    }

    final appDir = await StorageService.getAppStorageDirectory();
    final thumbnailsDir = Directory(p.join(appDir.path, 'thumbnails'));
    if (!thumbnailsDir.existsSync()) {
      await thumbnailsDir.create(recursive: true);
    }

    final extension = _normalizeThumbnailExtension(format);
    return p.join(thumbnailsDir.path, 'shared_${shareId}_thumbnail.$extension');
  }

  String? _sanitizeLocalThumbnailPath(String? candidate) {
    if (candidate == null) {
      return null;
    }
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return null;
    }
    return trimmed;
  }

  String _normalizeThumbnailExtension(String? format) {
    if (format == null || format.trim().isEmpty) {
      return 'png';
    }
    final normalized = format.toLowerCase().trim();
    if (normalized.contains('jpeg') || normalized.contains('jpg')) {
      return 'jpg';
    }
    if (normalized.contains('png')) {
      return 'png';
    }
    return 'png';
  }
}
