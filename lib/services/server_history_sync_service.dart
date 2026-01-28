import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:path/path.dart' as p;

class ServerHistorySyncService {
  ServerHistorySyncService._internal();

  static final ServerHistorySyncService instance =
      ServerHistorySyncService._internal();

  final JellyfinService _jellyfinService = JellyfinService.instance;
  final EmbyService _embyService = EmbyService.instance;
  final WatchHistoryDatabase _historyDatabase = WatchHistoryDatabase.instance;
  Directory? _thumbnailDirectory;

  bool _initialized = false;
  bool _isSyncingJellyfin = false;
  bool _isSyncingEmby = false;
  Future<void> Function()? _onHistoryUpdated;

  static const _kTimeConflictThresholdSeconds = 30;
  static const _kResumeFetchLimit = 5;

  /// 初始化同步服务。传入的 [onHistoryUpdated] 在同步写入数据库后触发，
  /// 以便 UI Provider 重新拉取本地观看记录。
  void initialize({Future<void> Function()? onHistoryUpdated}) {
    if (_initialized) return;
    _initialized = true;
    _onHistoryUpdated = onHistoryUpdated;

    if (kIsWeb) {
      DebugLogService().addLog('ServerHistorySyncService: Web 环境跳过初始化');
      debugPrint('ServerHistorySyncService.initialize -> skip on web');
      return;
    }

    _jellyfinService.addReadyListener(_handleJellyfinReady);
    _embyService.addReadyListener(_handleEmbyReady);

    if (_jellyfinService.isReady) {
      debugPrint(
          'ServerHistorySyncService.initialize -> Jellyfin already ready, schedule sync');
      _scheduleJellyfinSync();
    }
    if (_embyService.isReady) {
      debugPrint(
          'ServerHistorySyncService.initialize -> Emby already ready, schedule sync');
      _scheduleEmbySync();
    }
  }

  /// 触发一次 Jellyfin Resume 拉取（对外接口，便于手动刷新）。
  Future<void> syncJellyfinResume() async {
    debugPrint(
        'ServerHistorySyncService.syncJellyfinResume -> start ready=${_jellyfinService.isReady} connected=${_jellyfinService.isConnected}');
    if (!_canSyncServer(
      isSyncing: _isSyncingJellyfin,
      isReady: _jellyfinService.isReady,
      isConnected: _jellyfinService.isConnected,
      serverLabel: 'Jellyfin',
    )) {
      return;
    }

    if (_jellyfinService.userId == null) {
      DebugLogService()
          .addLog('ServerHistorySyncService: Jellyfin 缺少 userId，无法同步');
      return;
    }

    _isSyncingJellyfin = true;
    try {
      final resumeItems =
          await _jellyfinService.fetchResumeItems(limit: _kResumeFetchLimit);
      debugPrint(
          'ServerHistorySyncService.syncJellyfinResume -> fetched ${resumeItems.length} items');
      final changed = await _processResumeItems(
        resumeItems: resumeItems,
        filePathPrefix: 'jellyfin://',
        serverLabel: 'Jellyfin',
      );
      if (changed && _onHistoryUpdated != null) {
        await _onHistoryUpdated!.call();
      }
    } catch (e, stack) {
      DebugLogService()
          .addLog('ServerHistorySyncService: Jellyfin 同步失败: $e\n$stack');
    } finally {
      _isSyncingJellyfin = false;
    }
  }

  /// 触发一次 Emby Resume 拉取。
  Future<void> syncEmbyResume() async {
    debugPrint(
        'ServerHistorySyncService.syncEmbyResume -> start ready=${_embyService.isReady} connected=${_embyService.isConnected}');
    if (!_canSyncServer(
      isSyncing: _isSyncingEmby,
      isReady: _embyService.isReady,
      isConnected: _embyService.isConnected,
      serverLabel: 'Emby',
    )) {
      return;
    }

    if (_embyService.userId == null) {
      DebugLogService().addLog('ServerHistorySyncService: Emby 缺少 userId，无法同步');
      return;
    }

    _isSyncingEmby = true;
    try {
      final resumeItems =
          await _embyService.fetchResumeItems(limit: _kResumeFetchLimit);
      debugPrint(
          'ServerHistorySyncService.syncEmbyResume -> fetched ${resumeItems.length} items');
      final changed = await _processResumeItems(
        resumeItems: resumeItems,
        filePathPrefix: 'emby://',
        serverLabel: 'Emby',
      );
      if (changed && _onHistoryUpdated != null) {
        await _onHistoryUpdated!.call();
      }
    } catch (e, stack) {
      DebugLogService()
          .addLog('ServerHistorySyncService: Emby 同步失败: $e\n$stack');
    } finally {
      _isSyncingEmby = false;
    }
  }

  void dispose() {
    _jellyfinService.removeReadyListener(_handleJellyfinReady);
    _embyService.removeReadyListener(_handleEmbyReady);
  }

  bool _canSyncServer({
    required bool isSyncing,
    required bool isReady,
    required bool isConnected,
    required String serverLabel,
  }) {
    if (kIsWeb) return false;
    if (isSyncing) {
      debugPrint(
          'ServerHistorySyncService: $serverLabel 正在同步中，忽略新的请求');
      return false;
    }
    if (!isConnected || !isReady) {
      final msg =
          'ServerHistorySyncService: $serverLabel 未就绪(ready=$isReady, connected=$isConnected)，跳过同步';
      DebugLogService().addLog(msg);
      debugPrint(msg);
      return false;
    }
    return true;
  }

  Future<bool> _processResumeItems({
    required List<Map<String, dynamic>> resumeItems,
    required String filePathPrefix,
    required String serverLabel,
  }) async {
    if (resumeItems.isEmpty) {
      DebugLogService()
          .addLog('ServerHistorySyncService: $serverLabel resume 列表为空');
      debugPrint(
          'ServerHistorySyncService._processResumeItems -> $serverLabel list empty');
      return false;
    }

    debugPrint(
      'ServerHistorySyncService._processResumeItems -> $serverLabel count=${resumeItems.length}');
    final DateTime syncTimestampUtc = DateTime.now().toUtc();
    int inserted = 0;
    int updated = 0;
    int skippedLocalNewer = 0;
    int skippedSameTimestamp = 0;
    int missingUserData = 0;
    int missingLastPlayed = 0;
  int invalidLastPlayedFormat = 0;
    int skippedInvalidItem = 0;
    int loggedMissingLastPlayed = 0;

    for (var index = 0; index < resumeItems.length; index++) {
      final item = resumeItems[index];
      final String? itemId = item['Id'] as String?;
      if (itemId == null) {
        continue;
      }

      final userData = item['UserData'] as Map<String, dynamic>?;
      if (userData == null) {
        missingUserData++;
        continue;
      }

      final lastPlayedRaw = userData['LastPlayedDate'];
      DateTime? lastPlayedUtc;
      if (lastPlayedRaw is String && lastPlayedRaw.isNotEmpty) {
        try {
          lastPlayedUtc = DateTime.parse(lastPlayedRaw).toUtc();
        } catch (_) {
          invalidLastPlayedFormat++;
        }
      }

      if (lastPlayedUtc == null) {
        missingLastPlayed++;
        lastPlayedUtc = syncTimestampUtc.subtract(Duration(seconds: index));
        if (loggedMissingLastPlayed < 3) {
          debugPrint(
              'ServerHistorySyncService: $serverLabel item $itemId 缺少可用 LastPlayedDate, fallback=now userData=$userData');
          loggedMissingLastPlayed++;
        }
      }

      var historyItem = _convertResumeItem(
        item: item,
        userData: userData,
        lastPlayedUtc: lastPlayedUtc,
        filePathPrefix: filePathPrefix,
        itemId: itemId,
      );
      if (historyItem == null) {
        skippedInvalidItem++;
        continue;
      }

      final thumbnailPath = await _resolveThumbnailPath(
        itemId: itemId,
        imageTags: item['ImageTags'] as Map<String, dynamic>?,
        isJellyfin: filePathPrefix == 'jellyfin://',
        serverLabel: serverLabel,
      );
      if (thumbnailPath != null) {
        historyItem = historyItem.copyWith(thumbnailPath: thumbnailPath);
      }

      final existing =
          await _historyDatabase.getHistoryByFilePath(historyItem.filePath);
      if (existing == null) {
        await _historyDatabase.insertOrUpdateWatchHistory(historyItem);
        inserted++;
        continue;
      }

      final int diffSeconds = historyItem.lastWatchTime
          .toUtc()
          .difference(existing.lastWatchTime.toUtc())
          .inSeconds;

      if (diffSeconds >= _kTimeConflictThresholdSeconds) {
        final merged =
            _mergeHistoryItems(incoming: historyItem, existing: existing);
        await _historyDatabase.insertOrUpdateWatchHistory(merged);
        updated++;
        continue;
      }

      if (diffSeconds <= -_kTimeConflictThresholdSeconds) {
        skippedLocalNewer++;
        continue;
      }

      if (diffSeconds > 0) {
        final merged =
            _mergeHistoryItems(incoming: historyItem, existing: existing);
        await _historyDatabase.insertOrUpdateWatchHistory(merged);
        updated++;
      } else {
        skippedSameTimestamp++;
      }
    }

    final summary =
    'ServerHistorySyncService: $serverLabel resume 同步完成 total=${resumeItems.length}, new=$inserted, updated=$updated, localAhead=$skippedLocalNewer, sameTs=$skippedSameTimestamp, missingUserData=$missingUserData, fallbackLastPlayed=$missingLastPlayed, invalidTs=$invalidLastPlayedFormat, invalid=$skippedInvalidItem';
    DebugLogService().addLog(summary);
    debugPrint(summary);
    return (inserted + updated) > 0;
  }

  void _handleJellyfinReady() {
    debugPrint('ServerHistorySyncService._handleJellyfinReady -> received');
    _scheduleJellyfinSync();
  }

  void _handleEmbyReady() {
    debugPrint('ServerHistorySyncService._handleEmbyReady -> received');
    _scheduleEmbySync();
  }

  void _scheduleJellyfinSync() {
    scheduleMicrotask(() {
      debugPrint(
          'ServerHistorySyncService._scheduleJellyfinSync -> microtask fired, isSyncing=$_isSyncingJellyfin');
      if (_isSyncingJellyfin) return;
      // ignore: discarded_futures
      syncJellyfinResume();
    });
  }

  void _scheduleEmbySync() {
    scheduleMicrotask(() {
      debugPrint(
          'ServerHistorySyncService._scheduleEmbySync -> microtask fired, isSyncing=$_isSyncingEmby');
      if (_isSyncingEmby) return;
      // ignore: discarded_futures
      syncEmbyResume();
    });
  }

  WatchHistoryItem? _convertResumeItem({
    required Map<String, dynamic> item,
    required Map<String, dynamic> userData,
    required DateTime lastPlayedUtc,
    required String filePathPrefix,
    required String itemId,
  }) {
    final runTimeTicks = _readTicks(item['RunTimeTicks']);
    final playbackTicks = _readTicks(userData['PlaybackPositionTicks']);

    final durationMs = _ticksToMilliseconds(runTimeTicks);
    final positionMsRaw = _ticksToMilliseconds(playbackTicks);
    final positionMs =
        durationMs > 0 ? min(positionMsRaw, durationMs) : positionMsRaw;
    final progress = _calculateProgress(positionMs, durationMs);

    final displayName = (item['SeriesName'] as String?)?.isNotEmpty == true
        ? item['SeriesName'] as String
        : (item['Name'] as String?) ?? 'Server Item';

    return WatchHistoryItem(
      filePath: '$filePathPrefix$itemId',
      animeName: displayName,
      episodeTitle: item['Name'] as String?,
      episodeId:
          (item['IndexNumber'] is int) ? item['IndexNumber'] as int : null,
      animeId: null,
      watchProgress: progress,
      lastPosition: positionMs,
      duration: durationMs,
      lastWatchTime: lastPlayedUtc.toLocal(),
      thumbnailPath: null,
      isFromScan: false,
    );
  }

  WatchHistoryItem _mergeHistoryItems({
    required WatchHistoryItem incoming,
    required WatchHistoryItem existing,
  }) {
    final bool incomingHasMeaningfulName =
        incoming.animeName.isNotEmpty && incoming.animeName != 'Server Item';

    return incoming.copyWith(
      animeName:
          incomingHasMeaningfulName ? incoming.animeName : existing.animeName,
      episodeTitle: existing.episodeTitle ?? incoming.episodeTitle,
      episodeId: existing.episodeId ?? incoming.episodeId,
      animeId: existing.animeId ?? incoming.animeId,
      thumbnailPath: incoming.thumbnailPath ?? existing.thumbnailPath,
      isFromScan: existing.isFromScan,
      videoHash: existing.videoHash ?? incoming.videoHash,
    );
  }

  int _ticksToMilliseconds(int ticks) {
    if (ticks <= 0) return 0;
    return (ticks / 10000).round();
  }

  double _calculateProgress(int positionMs, int durationMs) {
    if (durationMs <= 0) return 0.0;
    final ratio = positionMs / durationMs;
    if (ratio.isNaN || ratio.isInfinite) {
      return 0.0;
    }
    return ratio.clamp(0.0, 1.0).toDouble();
  }

  int _readTicks(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  Future<String?> _resolveThumbnailPath({
    required String itemId,
    required Map<String, dynamic>? imageTags,
    required bool isJellyfin,
    required String serverLabel,
  }) async {
    if (imageTags == null || imageTags.isEmpty) return null;
    final selected = _pickBestImageTag(imageTags);
    if (selected == null) return null;
    final imageType = selected.key;
    final imageTag = selected.value;

    try {
      final dir = await _ensureThumbnailDirectory();
      final prefix = isJellyfin ? 'jellyfin' : 'emby';
      final safeType = imageType.toLowerCase();
      final fileName = '${prefix}_${safeType}_${itemId}_$imageTag.jpg';
      final filePath = p.join(dir.path, fileName);
      final file = File(filePath);

      if (await file.exists()) {
        return filePath;
      }

      final bytes = await _downloadServerThumbnail(
        itemId: itemId,
        imageType: imageType,
        imageTag: imageTag,
        isJellyfin: isJellyfin,
      );
      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      await file.writeAsBytes(bytes, flush: true);
      return filePath;
    } catch (e, stack) {
      DebugLogService().addLog(
        'ServerHistorySyncService: $serverLabel 缩略图保存失败: $e\n$stack',
      );
      return null;
    }
  }

  Future<List<int>?> _downloadServerThumbnail({
    required String itemId,
    required String imageType,
    required String imageTag,
    required bool isJellyfin,
  }) async {
    try {
      if (isJellyfin) {
        return await _jellyfinService.downloadItemImage(
          itemId,
          type: imageType,
          width: 640,
          height: 360,
          quality: 90,
          tag: imageTag,
        );
      }

      return await _embyService.downloadItemImage(
        itemId,
        type: imageType,
        width: 640,
        height: 360,
        quality: 90,
        tag: imageTag,
      );
    } catch (e, stack) {
      DebugLogService().addLog(
        'ServerHistorySyncService: 下载缩略图失败 ($itemId): $e\n$stack',
      );
      return null;
    }
  }

  Future<Directory> _ensureThumbnailDirectory() async {
    if (_thumbnailDirectory != null && _thumbnailDirectory!.existsSync()) {
      return _thumbnailDirectory!;
    }

    final baseDir = await StorageService.getAppStorageDirectory();
    final dir = Directory(p.join(baseDir.path, 'server_thumbnails'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _thumbnailDirectory = dir;
    return dir;
  }

  MapEntry<String, String>? _pickBestImageTag(Map<String, dynamic> imageTags) {
    const preferredOrder = ['Thumb', 'Screenshot', 'Primary', 'Backdrop'];

    for (final type in preferredOrder) {
      final candidate = imageTags[type];
      if (candidate is String && candidate.isNotEmpty) {
        return MapEntry(type, candidate);
      }
    }

    for (final entry in imageTags.entries) {
      if (entry.value is String && (entry.value as String).isNotEmpty) {
        return MapEntry(entry.key, entry.value as String);
      }
    }
    return null;
  }
}
