import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';

import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/constants/media_extensions.dart';
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
  static const String _mediaLibraryImagePrefsKeyPrefix =
      'media_library_image_url_';
  static const Map<String, int> _subtitleExtensionPriority = {
    '.ass': 0,
    '.ssa': 1,
    '.srt': 2,
    '.sub': 3,
    '.sup': 4,
  };

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

    // BangumiService 已在应用启动时将持久化详情载入内存。先复用这些
    // 缓存，再为确实缺失的条目后台补齐，避免首次共享时整页灰色封面。
    for (final bundle in bundles) {
      _prefetchAnimeDetail(bundle.animeId);
    }

    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> summaries = [];
    for (final bundle in bundles) {
      final detail = _peekAnimeDetail(bundle.animeId);
      final fallbackName = bundle.episodes.first.historyItem.animeName;
      final persistedImageUrl = prefs.getString(
        '$_mediaLibraryImagePrefsKeyPrefix${bundle.animeId}',
      );
      summaries.add({
        'animeId': bundle.animeId,
        'name': detail?.name ?? fallbackName,
        'nameCn': detail?.nameCn ?? fallbackName,
        'summary': detail?.summary ?? '',
        'imageUrl': _firstNonEmptyString([
          detail?.imageUrl,
          persistedImageUrl,
          bundle.episodes.first.historyItem.thumbnailPath,
        ]),
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

    // 与番剧摘要保持一致，预取本次返回范围内的全部详情，避免观看历史
    // 超过 24 项后封面永久停留在占位图。
    for (final entry in episodes.take(sanitizedLimit)) {
      final animeId = entry.historyItem.animeId;
      if (animeId != null) {
        _prefetchAnimeDetail(animeId);
      }
    }

    final prefs = await SharedPreferences.getInstance();
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
        'imageUrl': _firstNonEmptyString([
          detail?.imageUrl,
          animeId == null
              ? null
              : prefs.getString('$_mediaLibraryImagePrefsKeyPrefix$animeId'),
          entry.historyItem.thumbnailPath,
        ]),
      });
    }

    return items;
  }

  SharedEpisodeInfo? getEpisodeByShareId(String shareId) {
    return _shareEpisodeMap[shareId];
  }

  BangumiAnime? _peekAnimeDetail(int animeId) {
    if (_animeDetailCache.containsKey(animeId)) {
      return _animeDetailCache[animeId];
    }

    final sharedDetail =
        BangumiService.instance.getAnimeDetailsFromMemory(animeId);
    if (sharedDetail != null) {
      _animeDetailCache[animeId] = sharedDetail;
    }
    return sharedDetail;
  }

  String? _firstNonEmptyString(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  void _prefetchAnimeDetail(int animeId) {
    if (_peekAnimeDetail(animeId) != null ||
        _animeDetailCache.containsKey(animeId)) {
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
      case '.mka':
        return 'audio/x-matroska';
      case '.ttf':
        return 'font/ttf';
      case '.otf':
        return 'font/otf';
      case '.ttc':
        return 'font/collection';
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

  Future<List<Map<String, dynamic>>> listEpisodeSubtitles(
    SharedEpisodeInfo episode,
  ) async {
    final videoPath = episode.historyItem.filePath;
    if (!_isLocalFilesystemPath(videoPath)) {
      return const <Map<String, dynamic>>[];
    }

    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      return const <Map<String, dynamic>>[];
    }

    final videoDir = videoFile.parent;
    if (!await videoDir.exists()) {
      return const <Map<String, dynamic>>[];
    }

    final String videoBaseName = p.basenameWithoutExtension(videoPath).toLowerCase();
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    await for (final entry in videoDir.list(followLinks: false)) {
      if (entry is! File) continue;

      final filePath = entry.path;
      if (p.normalize(filePath) == p.normalize(videoPath)) {
        continue;
      }

      final ext = p.extension(filePath).toLowerCase();
      if (!subtitleExtensions.contains(ext)) {
        continue;
      }

      FileStat stat;
      try {
        stat = await entry.stat();
      } catch (_) {
        continue;
      }
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }

      final subtitleBaseName = p.basenameWithoutExtension(filePath).toLowerCase();
      final bool isLikelyMatch =
          subtitleBaseName == videoBaseName || subtitleBaseName.contains(videoBaseName);

      items.add({
        'name': p.basename(filePath),
        'extension': ext,
        'size': stat.size,
        'lastModified': stat.modified.toIso8601String(),
        'isLikelyMatch': isLikelyMatch,
      });
    }

    items.sort((a, b) {
      final bool aLikely = a['isLikelyMatch'] == true;
      final bool bLikely = b['isLikelyMatch'] == true;
      if (aLikely != bLikely) {
        return bLikely ? 1 : -1;
      }

      final String aExt = (a['extension'] as String? ?? '').toLowerCase();
      final String bExt = (b['extension'] as String? ?? '').toLowerCase();
      final int aExtOrder = _subtitleExtensionPriority[aExt] ?? 999;
      final int bExtOrder = _subtitleExtensionPriority[bExt] ?? 999;
      if (aExtOrder != bExtOrder) {
        return aExtOrder.compareTo(bExtOrder);
      }

      final String aName = (a['name'] as String? ?? '').toLowerCase();
      final String bName = (b['name'] as String? ?? '').toLowerCase();
      return aName.compareTo(bName);
    });

    return items;
  }

  Future<Response> buildSubtitleResponse(
    Request request,
    SharedEpisodeInfo episode, {
    required String subtitleName,
    bool headOnly = false,
  }) async {
    final videoPath = episode.historyItem.filePath;
    if (!_isLocalFilesystemPath(videoPath)) {
      return Response.notFound('Subtitle not found');
    }

    final subtitleFile = await _resolveSubtitleFileByName(
      videoPath: videoPath,
      subtitleName: subtitleName,
    );
    if (subtitleFile == null) {
      return Response.notFound('Subtitle not found');
    }

    final totalLength = await subtitleFile.length();
    final contentType = determineContentType(subtitleFile.path);
    final contentDisposition =
        _buildContentDispositionHeader(p.basename(subtitleFile.path));
    final stream = headOnly ? null : subtitleFile.openRead();

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

  Future<List<Map<String, dynamic>>> listEpisodeExternalAudio(
    SharedEpisodeInfo episode,
  ) async {
    final videoPath = episode.historyItem.filePath;
    if (!_isLocalFilesystemPath(videoPath)) {
      return const <Map<String, dynamic>>[];
    }

    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      return const <Map<String, dynamic>>[];
    }

    final videoDir = videoFile.parent;
    if (!await videoDir.exists()) {
      return const <Map<String, dynamic>>[];
    }

    final String videoBaseName = p.basenameWithoutExtension(videoPath).toLowerCase();
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    await for (final entry in videoDir.list(followLinks: false)) {
      if (entry is! File) continue;

      final filePath = entry.path;
      if (p.normalize(filePath) == p.normalize(videoPath)) {
        continue;
      }

      final ext = p.extension(filePath).toLowerCase();
      if (!audioExtensions.contains(ext)) {
        continue;
      }

      FileStat stat;
      try {
        stat = await entry.stat();
      } catch (_) {
        continue;
      }
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }

      final audioBaseName = p.basenameWithoutExtension(filePath).toLowerCase();
      // 使用精确匹配或分隔符边界匹配，避免 "ep1" 误匹配 "ep10" 等
      final bool isExactMatch = audioBaseName == videoBaseName;
      final bool isLikelyMatch = isExactMatch ||
          _isSeparatorBoundedContains(audioBaseName, videoBaseName);

      items.add({
        'name': p.basename(filePath),
        'extension': ext,
        'size': stat.size,
        'lastModified': stat.modified.toIso8601String(),
        'isLikelyMatch': isLikelyMatch,
      });
    }

    items.sort((a, b) {
      final bool aLikely = a['isLikelyMatch'] == true;
      final bool bLikely = b['isLikelyMatch'] == true;
      if (aLikely != bLikely) {
        return bLikely ? 1 : -1;
      }
      final String aName = (a['name'] as String? ?? '').toLowerCase();
      final String bName = (b['name'] as String? ?? '').toLowerCase();
      return aName.compareTo(bName);
    });

    return items;
  }

  Future<List<Map<String, dynamic>>> listEpisodeFonts(
    SharedEpisodeInfo episode,
  ) async {
    final videoPath = episode.historyItem.filePath;
    if (!_isLocalFilesystemPath(videoPath)) {
      return const <Map<String, dynamic>>[];
    }

    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      return const <Map<String, dynamic>>[];
    }

    final videoDir = videoFile.parent;
    if (!await videoDir.exists()) {
      return const <Map<String, dynamic>>[];
    }

    final String videoBaseName = p.basenameWithoutExtension(videoPath).toLowerCase();

    // 检查是否存在同名 ASS/SSA 字幕（如果有，则所有字体都标记为 isLikelyMatch）
    // 同时检查视频同级目录和子目录中的字幕
    bool hasAssSubtitle = false;
    await for (final entry in videoDir.list(followLinks: false)) {
      if (entry is! File) continue;
      final ext = p.extension(entry.path).toLowerCase();
      if (ext == '.ass' || ext == '.ssa') {
        final subBaseName = p.basenameWithoutExtension(entry.path).toLowerCase();
        if (subBaseName == videoBaseName || subBaseName.contains(videoBaseName)) {
          hasAssSubtitle = true;
          break;
        }
      }
    }

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    // 扫描视频同级目录中的字体文件
    await _collectFontFiles(videoDir, videoDir, hasAssSubtitle, items);

    // 扫描子目录中的字体文件（如 Fonts/、fonts/ 等常见子目录）
    // 许多字幕组（如 VCB-Studio）将字体放在 Fonts/ 子目录中
    await for (final entry in videoDir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final dirName = p.basename(entry.path);
      final dirNameLower = dirName.toLowerCase();
      // 只扫描可能的字体子目录，避免遍历不相关的深层目录
      if (dirNameLower == 'fonts' || dirNameLower == 'font') {
        await _collectFontFiles(entry, videoDir, hasAssSubtitle, items);
      }
    }

    items.sort((a, b) {
      final String aName = (a['name'] as String? ?? '').toLowerCase();
      final String bName = (b['name'] as String? ?? '').toLowerCase();
      return aName.compareTo(bName);
    });

    return items;
  }

  /// 递归收集目录中的字体文件，返回的 name 使用相对于 videoDir 的相对路径
  Future<void> _collectFontFiles(
    Directory scanDir,
    Directory videoDir,
    bool isLikelyMatch,
    List<Map<String, dynamic>> items,
  ) async {
    if (!await scanDir.exists()) return;

    await for (final entry in scanDir.list(followLinks: false)) {
      if (entry is File) {
        final filePath = entry.path;
        final ext = p.extension(filePath).toLowerCase();
        if (!fontExtensions.contains(ext)) continue;

        FileStat stat;
        try {
          stat = await entry.stat();
        } catch (_) {
          continue;
        }
        if (stat.type != FileSystemEntityType.file) continue;

        // 使用相对于 videoDir 的路径作为 name，以便客户端请求时能在子目录中找到文件
        final relativePath = p.relative(filePath, from: videoDir.path);
        // 统一使用正斜杠，兼容不同平台的路径分隔符
        final normalizedName = relativePath.replaceAll('\\', '/');

        items.add({
          'name': normalizedName,
          'extension': ext,
          'size': stat.size,
          'lastModified': stat.modified.toIso8601String(),
          'isLikelyMatch': isLikelyMatch,
        });
      } else if (entry is Directory) {
        // 对于 Fonts/ 等已知子目录下的进一步子目录也递归扫描
        final dirName = p.basename(entry.path).toLowerCase();
        if (dirName != 'fonts' && dirName != 'font') {
          // 只在已知字体目录内部递归，避免无限制遍历
          final parentName = p.basename(scanDir.path).toLowerCase();
          if (parentName == 'fonts' || parentName == 'font') {
            await _collectFontFiles(entry, videoDir, isLikelyMatch, items);
          }
        }
      }
    }
  }

  Future<Response> buildExternalAudioResponse(
    Request request,
    SharedEpisodeInfo episode, {
    required String audioName,
    bool headOnly = false,
  }) async {
    final videoPath = episode.historyItem.filePath;
    if (!_isLocalFilesystemPath(videoPath)) {
      return Response.notFound('Audio not found');
    }

    final audioFile = await _resolveFileByName(
      videoPath: videoPath,
      fileName: audioName,
      allowedExtensions: audioExtensions,
    );
    if (audioFile == null) {
      return Response.notFound('Audio not found');
    }

    final totalLength = await audioFile.length();
    final contentType = determineContentType(audioFile.path);
    final contentDisposition =
        _buildContentDispositionHeader(p.basename(audioFile.path));
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
        final stream = headOnly ? null : audioFile.openRead(start, adjustedEnd + 1);
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

    final stream = headOnly ? null : audioFile.openRead();
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

  Future<Response> buildFontResponse(
    Request request,
    SharedEpisodeInfo episode, {
    required String fontName,
    bool headOnly = false,
  }) async {
    final videoPath = episode.historyItem.filePath;
    if (!_isLocalFilesystemPath(videoPath)) {
      return Response.notFound('Font not found');
    }

    // 字体文件可能在视频同级目录或子目录（如 Fonts/）中
    final fontFile = await _resolveFontFileByName(
      videoPath: videoPath,
      fontName: fontName,
    );
    if (fontFile == null) {
      return Response.notFound('Font not found');
    }

    final totalLength = await fontFile.length();
    final contentType = determineContentType(fontFile.path);
    final contentDisposition =
        _buildContentDispositionHeader(p.basename(fontFile.path));
    final stream = headOnly ? null : fontFile.openRead();

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

  bool _isLocalFilesystemPath(String path) {
    final lower = path.toLowerCase();
    return !lower.startsWith('http://') &&
        !lower.startsWith('https://') &&
        !lower.startsWith('jellyfin://') &&
        !lower.startsWith('emby://');
  }

  Future<File?> _resolveSubtitleFileByName({
    required String videoPath,
    required String subtitleName,
  }) async {
    return _resolveFileByName(
      videoPath: videoPath,
      fileName: subtitleName,
      allowedExtensions: subtitleExtensions,
    );
  }

  Future<File?> _resolveFileByName({
    required String videoPath,
    required String fileName,
    required Set<String> allowedExtensions,
  }) async {
    final normalizedName = fileName.trim();
    if (normalizedName.isEmpty) {
      return null;
    }

    final sanitizedName = p.basename(normalizedName);
    if (sanitizedName != normalizedName) {
      return null;
    }

    final ext = p.extension(sanitizedName).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      return null;
    }

    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      return null;
    }

    final resolvedPath = p.join(videoFile.parent.path, sanitizedName);
    final resolvedFile = File(resolvedPath);
    if (!await resolvedFile.exists()) {
      return null;
    }

    return resolvedFile;
  }

  /// 解析字体文件路径，支持相对于视频目录的子目录路径（如 Fonts/xxx.ttf）
  /// 安全性：只允许在视频同级目录及其子目录内查找，防止路径遍历
  Future<File?> _resolveFontFileByName({
    required String videoPath,
    required String fontName,
  }) async {
    final normalizedName = fontName.trim();
    if (normalizedName.isEmpty) {
      return null;
    }

    // 统一使用正斜杠
    final normalizedSlash = normalizedName.replaceAll('\\', '/');

    // 验证扩展名
    final basename = p.basename(normalizedSlash);
    final ext = p.extension(basename).toLowerCase();
    if (!fontExtensions.contains(ext)) {
      return null;
    }

    // 安全检查：禁止路径遍历（..）和绝对路径
    final segments = normalizedSlash.split('/');
    for (final segment in segments) {
      if (segment == '..' || segment.isEmpty && segments.length > 1) {
        return null;
      }
    }

    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      return null;
    }

    final videoDir = videoFile.parent.path;
    final resolvedPath = p.join(videoDir, normalizedSlash);

    // 确保解析后的路径仍在视频目录内（安全边界检查）
    final canonicalVideoDir = await Directory(videoDir).resolveSymbolicLinks();
    final resolvedFile = File(resolvedPath);
    String canonicalResolvedPath;
    try {
      canonicalResolvedPath = await resolvedFile.resolveSymbolicLinks();
    } catch (_) {
      return null;
    }

    // 使用路径分隔符边界检查，防止 /media/show 匹配 /media/show-secret
    if (!canonicalResolvedPath.startsWith(canonicalVideoDir + p.separator) &&
        canonicalResolvedPath != canonicalVideoDir) {
      return null;
    }

    if (!await resolvedFile.exists()) {
      return null;
    }

    return resolvedFile;
  }

  /// 检查 [haystack] 是否包含 [needle]，但要求 [needle] 在 [haystack] 中的
  /// 边界处有非字母数字分隔符（如 '.', '-', '_', ' ', '[' 等），
  /// 避免 "ep1" 匹配 "ep10" 或 "ep12" 的情况。
  static bool _isSeparatorBoundedContains(String haystack, String needle) {
    int pos = 0;
    while (pos <= haystack.length - needle.length) {
      final idx = haystack.indexOf(needle, pos);
      if (idx < 0) break;
      // 检查 needle 前后的字符是否为分隔符或字符串边界
      final beforeOk =
          idx == 0 || _isSeparator(haystack.codeUnitAt(idx - 1));
      final afterOk = idx + needle.length == haystack.length ||
          _isSeparator(haystack.codeUnitAt(idx + needle.length));
      if (beforeOk && afterOk) return true;
      pos = idx + 1;
    }
    return false;
  }

  /// 判断字符是否为非字母数字的分隔符
  static bool _isSeparator(int charCode) {
    // 允许的分隔符: . - _ 空格 [ ] ( ) 以及非ASCII字符（如中文）
    if (charCode >= 0x80) return true; // 非ASCII视为分隔符
    final ch = String.fromCharCode(charCode);
    return RegExp(r'[^a-zA-Z0-9]').hasMatch(ch);
  }
}
