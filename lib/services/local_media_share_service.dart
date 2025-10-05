import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';

class SharedEpisodeInfo {
  SharedEpisodeInfo({
    required this.shareId,
    required this.historyItem,
  });

  final String shareId;
  final WatchHistoryItem historyItem;

  Future<Map<String, dynamic>> toJson() async {
    final file = File(historyItem.filePath);
    bool exists = false;
    int? fileSize;
    DateTime? modifiedTime;

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
      'progress': historyItem.watchProgress,
      'streamPath': '/api/media/local/share/episodes/$shareId/stream',
      'videoHash': historyItem.videoHash,
      'source': _detectSource(historyItem.filePath),
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

    final localItems = watchHistory.history.where((item) {
      final lower = item.filePath.toLowerCase();
      return !lower.startsWith('jellyfin://') &&
          !lower.startsWith('emby://') &&
          !lower.startsWith('http://') &&
          !lower.startsWith('https://');
    }).toList();

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

    final List<Map<String, dynamic>> summaries = [];
    for (final bundle in bundles) {
      final detail = await _getAnimeDetail(bundle.animeId);
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

    final detail = await _getAnimeDetail(animeId);
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

  SharedEpisodeInfo? getEpisodeByShareId(String shareId) {
    return _shareEpisodeMap[shareId];
  }

  Future<BangumiAnime?> _getAnimeDetail(int animeId) async {
    if (_animeDetailCache.containsKey(animeId)) {
      return _animeDetailCache[animeId];
    }

    try {
      final detail = await BangumiService.instance.getAnimeDetails(animeId);
      _animeDetailCache[animeId] = detail;
      return detail;
    } catch (e) {
      _animeDetailCache[animeId] = null;
      return null;
    }
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

  Future<Response> buildStreamResponse(Request request, SharedEpisodeInfo episode) async {
    final file = File(episode.historyItem.filePath);
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    final totalLength = await file.length();
    final contentType = determineContentType(file.path);
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
        final stream = file.openRead(start, adjustedEnd + 1);
        return Response(
          HttpStatus.partialContent,
          body: stream,
          headers: {
            'Content-Type': contentType,
            'Content-Length': '$chunkSize',
            'Accept-Ranges': 'bytes',
            'Content-Range': 'bytes $start-$adjustedEnd/$totalLength',
            'Cache-Control': 'no-cache',
          },
        );
      }
    }

    final stream = file.openRead();
    return Response.ok(
      stream,
      headers: {
        'Content-Type': contentType,
        'Content-Length': '$totalLength',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
      },
    );
  }
}
