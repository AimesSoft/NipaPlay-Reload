
// lib/models/external_player_session.dart
// 外部播放器相关的模型

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/external_player_danmaku_item.dart';
import 'package:nipaplay/models/playable_item.dart';
// import 'package:nipaplay/constants/settings_keys.dart';
// import 'package:nipaplay/utils/settings_storage.dart';


/// 掌管外部播放器会话的神
class ExternalPlayerSession extends ChangeNotifier {

  /// 构造函数
  ExternalPlayerSession(
    this.type,
    this.playerPath,
    this.processId,
    this.ipcPath,
    this.duration,
    this.danmakuAssPath,
    PlayableItem playableItem,
    { List<ExternalPlayerDanmakuItem> danmakuItems = const [] }
  ) :
  danmakuItems  = _sortDanmakuItems(danmakuItems),
  _maxDanmakuDuration = _findMaxDanmakuDuration(danmakuItems),
  mediaPath    = playableItem.videoPath,
  animeTitle   = playableItem.title,
  episodeTitle = playableItem.subtitle,
  animeId      = playableItem.animeId,
  episodeId    = playableItem.episodeId;


  /// 初始化外部播放器会话的播放状态
  void initialize({
    double   danmakuOpacity = 1.0,
    double   danmakuOutlineWidth = 1.0,
    Duration position       = Duration.zero,
    bool     isPaused       = false,
  }) {
    this.danmakuOpacity = danmakuOpacity;
    this.danmakuOutlineWidth = danmakuOutlineWidth > 0.0
        ? danmakuOutlineWidth
        : 1.0;
    danmakuOutlineEnabled = danmakuOutlineWidth > 0.0;
    this.position       = position;
    this.isPaused       = isPaused;
  }

  // 外部播放器相关
  final ExternalPlayerType type;  // 外部播放器类型
  final String   playerPath;      // 外部播放器的路径
  final int      processId;       // 外部播放器进程 ID
  final String?  ipcPath;         // 外部播放器的 IPC 通道路径

  // 媒体文件相关
  final String   mediaPath;       // 媒体文件路径
  Duration       duration;        // 媒体文件总时长

  // 番剧相关
  final String?  animeTitle;      // 番剧标题
  final String?  episodeTitle;    // 剧集标题
  final int?     animeId;         // 番剧 ID
  final int?     episodeId;       // 剧集 ID

  // 弹幕相关
  final String?  danmakuAssPath;  // 弹幕 ASS 文件路径
  double?        danmakuOpacity;  // 弹幕透明度, 范围 0.0 ~ 1.0
  double         danmakuOutlineWidth = 1.0; // 启用时使用的 ASS 描边宽度
  bool           danmakuOutlineEnabled = true; // 是否显示弹幕描边
  final Duration _maxDanmakuDuration; // 弹幕中最长的显示时长, 用于二分查找优化
  final List<ExternalPlayerDanmakuItem> danmakuItems; // 实际加载的弹幕

  // 播放相关
  Duration?      position;        // 当前播放位置
  bool?          isPaused;        // 是否暂停

  // 进程轮询相关
  static const Duration _processPollingInterval = Duration(milliseconds: 250);
  Timer? _processPollingTimer;


  // --- Setters & Getters --- //

  set setPosition(Duration newPosition) { position = newPosition; }
  set setPaused  (bool paused)          { isPaused = paused;      }

  void togglePaused() { if (isPaused != null) isPaused = !isPaused!; }

  Duration? get getPosition => position;
  bool?     get getPaused   => isPaused;

  /// 获取播放进度的百分比, 范围 0.0 ~ 1.0
  double? get fraction {
    if (position == null || duration <= Duration.zero) return null;
    return (position!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }

  /// 获取指定播放位置正在显示的弹幕索引
  ///
  /// 弹幕已按开始时间排序. 先二分找到已开始的最后一条, 再只检查最长弹幕
  /// 显示时长覆盖的时间窗口, 避免播放状态刷新时扫描全部弹幕.
  List<int> activeDanmakuIndicesAt(Duration currentPosition) {
    if (danmakuItems.isEmpty || _maxDanmakuDuration <= Duration.zero) {
      return const [];
    }

    var low = 0;
    var high = danmakuItems.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (danmakuItems[middle].startTime <= currentPosition) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    final earliestPossibleStart = currentPosition - _maxDanmakuDuration;
    final active = <int>[];
    for (var index = low - 1; index >= 0; index--) {
      final item = danmakuItems[index];
      if (item.startTime < earliestPossibleStart) break;
      if (item.isActiveAt(currentPosition)) active.add(index);
    }
    return List<int>.unmodifiable(active.reversed);
  }

  /// 获取指定播放位置正在显示的弹幕
  List<ExternalPlayerDanmakuItem> activeDanmakuAt(Duration currentPosition) {
    return List<ExternalPlayerDanmakuItem>.unmodifiable(
      activeDanmakuIndicesAt(currentPosition).map((index) => danmakuItems[index]),
    );
  }

  /// 对弹幕进行排序, 以便后续二分查找
  /// 按照 startTime 升序排序
  static List<ExternalPlayerDanmakuItem> _sortDanmakuItems(List<ExternalPlayerDanmakuItem> items) {
    final sorted = List<ExternalPlayerDanmakuItem>.of(items);
    sorted.sort((a, b) => a.startTime.compareTo(b.startTime));
    return List<ExternalPlayerDanmakuItem>.unmodifiable(sorted);
  }

  static Duration _findMaxDanmakuDuration(
    List<ExternalPlayerDanmakuItem> items,
  ) {
    var maximum = Duration.zero;
    for (final item in items) {
      if (item.displayDuration > maximum) maximum = item.displayDuration;
    }
    return maximum;
  }


  // --- Process Polling --- //

  /// 开始轮询外部播放器进程和播放状态
  void startProcessPolling(VoidCallback onProcessExit) {
    stopProcessPolling();
    _scheduleNextProcessPoll(onProcessExit);
  }

  /// 停止轮询外部播放器进程和播放状态
  void stopProcessPolling() {
    _processPollingTimer?.cancel();
    _processPollingTimer = null;
  }

  /// 计划下一次轮询
  void _scheduleNextProcessPoll(VoidCallback onProcessExit) {
    late final Timer timer;
    timer = Timer(
      _processPollingInterval,
      () => unawaited(_pollProcessState(timer, onProcessExit)),
    );
    _processPollingTimer = timer;
  }

  /// 轮询外部播放器进程和播放状态
  Future<void> _pollProcessState(Timer timer, VoidCallback onProcessExit) async {
    bool running;
    try {
      running = await _refreshProcessState(timer);
    } catch (error) {
      debugPrint('[ExternalPlayerSession] Failed to refresh player state: $error');
      running = true;
    }

    if (!identical(_processPollingTimer, timer)) return;
    if (!running) {
      _processPollingTimer = null;
      onProcessExit();
      return;
    }

    // 继续轮询
    _scheduleNextProcessPoll(onProcessExit);
  }

  Future<bool> _refreshProcessState(Timer timer) async {
    final running = await _isLinuxProcessRunning();
    if (!identical(_processPollingTimer, timer) || !running) return running;

    final nextState = await _readMpvState();
    if (!identical(_processPollingTimer, timer) || nextState == null) {
      return true;
    }

    if (position == nextState.position &&
        duration == nextState.duration &&
        isPaused == nextState.isPaused) {
      return true;
    }

    position = nextState.position;
    duration = nextState.duration;
    isPaused = nextState.isPaused;
    notifyListeners();
    return true;
  }

  Future<bool> _isLinuxProcessRunning() async {
    if (processId <= 0) return false;

    try {
      final value = await File('/proc/$processId/stat').readAsString();
      final closingParen = value.lastIndexOf(')');
      if (closingParen < 0 || closingParen + 2 >= value.length) return true;
      return value.substring(closingParen + 2, closingParen + 3) != 'Z';
    } on FileSystemException {
      return false;
    }
  }

  Future<_ExternalPlayerPlaybackState?> _readMpvState() async {
    if (ipcPath == null || ipcPath!.isEmpty) return null;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(ipcPath!, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('${jsonEncode({
            'command': ['get_property', 'time-pos'],
            'request_id': 1,
          })}\n');
      socket.write('${jsonEncode({
            'command': ['get_property', 'duration'],
            'request_id': 2,
          })}\n');
      socket.write('${jsonEncode({
            'command': ['get_property', 'pause'],
            'request_id': 3,
          })}\n');
      await socket.flush();

      double? positionSeconds;
      double? durationSeconds;
      bool? paused;
      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800));
      await for (final line in lines) {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> || value['error'] != 'success') {
          continue;
        }

        final data = value['data'];
        switch (value['request_id']) {
          case 1 when data is num:
            positionSeconds = data.toDouble();
          case 2 when data is num:
            durationSeconds = data.toDouble();
          case 3 when data is bool:
            paused = data;
        }
        if (positionSeconds != null &&
            durationSeconds != null &&
            paused != null) {
          break;
        }
      }

      if (positionSeconds == null ||
          durationSeconds == null ||
          paused == null) {
        return null;
      }
      return _ExternalPlayerPlaybackState(
        position: Duration(milliseconds: (positionSeconds * 1000).round()),
        duration: Duration(milliseconds: (durationSeconds * 1000).round()),
        isPaused: paused,
      );
    } catch (error) {
      debugPrint('[ExternalPlayerSession] Failed to read mpv state: $error');
      return null;
    } finally {
      socket?.destroy();
    }
  }

  @override
  void dispose() {
    stopProcessPolling();
    super.dispose();
  }

}

/// 外部播放器本轮轮询得到的播放状态
class _ExternalPlayerPlaybackState {
  const _ExternalPlayerPlaybackState({
    required this.position,
    required this.duration,
    required this.isPaused,
  });

  final Duration position;
  final Duration duration;
  final bool isPaused;
}
