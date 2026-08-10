import 'package:flutter/material.dart';
import 'danmaku_screen.dart';
import 'danmaku_controller.dart';
import 'danmaku_timeline.dart';
import 'models/danmaku_option.dart';
import 'models/danmaku_content_item.dart' as canvas_models;

// Canvas弹幕渲染管理器
class CanvasDanmakuManager {
  // 创建Canvas弹幕渲染器
  static Widget createRenderer({
    required double fontSize,
    required double opacity,
    required double displayArea,
    required bool visible,
    required bool stacking,
    required bool mergeDanmaku,
    required bool blockTopDanmaku,
    required bool blockBottomDanmaku,
    required bool blockScrollDanmaku,
    required List<String> blockWords,
    required List<Map<String, dynamic>> danmakuList,
    required double currentTime,
    required bool isPlaying,
    required double playbackRate,
    required double scrollDurationSeconds,
    int seekRevision = -1,
    int danmakuListVersion = 0,
    double timeOffsetSeconds = 0,
  }) {
    return CanvasDanmakuRenderer(
      fontSize: fontSize,
      opacity: opacity,
      displayArea: displayArea,
      visible: visible,
      stacking: stacking,
      mergeDanmaku: mergeDanmaku,
      blockTopDanmaku: blockTopDanmaku,
      blockBottomDanmaku: blockBottomDanmaku,
      blockScrollDanmaku: blockScrollDanmaku,
      blockWords: blockWords,
      danmakuList: danmakuList,
      currentTime: currentTime,
      isPlaying: isPlaying,
      playbackRate: playbackRate,
      scrollDurationSeconds: scrollDurationSeconds,
      seekRevision: seekRevision,
      danmakuListVersion: danmakuListVersion,
      timeOffsetSeconds: timeOffsetSeconds,
    );
  }
}

// Canvas弹幕渲染器Widget
class CanvasDanmakuRenderer extends StatefulWidget {
  final double fontSize;
  final double opacity;
  final double displayArea;
  final bool visible;
  final bool stacking;
  final bool mergeDanmaku;
  final bool blockTopDanmaku;
  final bool blockBottomDanmaku;
  final bool blockScrollDanmaku;
  final List<String> blockWords;
  final List<Map<String, dynamic>> danmakuList;
  final double currentTime;
  final bool isPlaying;
  final double playbackRate;
  final double scrollDurationSeconds;
  final int seekRevision;
  final int danmakuListVersion;
  final double timeOffsetSeconds;

  const CanvasDanmakuRenderer({
    super.key,
    required this.fontSize,
    required this.opacity,
    required this.displayArea,
    required this.visible,
    required this.stacking,
    required this.mergeDanmaku,
    required this.blockTopDanmaku,
    required this.blockBottomDanmaku,
    required this.blockScrollDanmaku,
    required this.blockWords,
    required this.danmakuList,
    required this.currentTime,
    required this.isPlaying,
    required this.playbackRate,
    required this.scrollDurationSeconds,
    this.seekRevision = -1,
    this.danmakuListVersion = 0,
    this.timeOffsetSeconds = 0,
  });

  @override
  State<CanvasDanmakuRenderer> createState() => _CanvasDanmakuRendererState();
}

class _CanvasDanmakuRendererState extends State<CanvasDanmakuRenderer> {
  DanmakuController? _controller;
  List<Map<String, dynamic>>? _lastDanmakuList;
  int _lastDanmakuListVersion = -1;
  int _lastDanmakuListLength = -1;
  double _lastCurrentTime = double.nan;
  DanmakuScreen? _danmakuScreen;
  DanmakuOption? _currentOption;

  // 添加已添加弹幕的跟踪集合，避免重复添加
  final Map<Map<String, dynamic>, double> _addedDanmakuTimes = Map.identity();
  // 时间线恢复期因轨道冲突被丢弃的弹幕的重试次数（身份去重）
  final Map<Map<String, dynamic>, int> _restorationRetryCounts =
      Map.identity();
  List<Map<String, dynamic>> _pendingRestoration = const [];
  int _pendingRestorationIndex = 0;
  int _restorationGeneration = 0;
  bool _restorationDrainScheduled = false;
  bool _forceTimelineRestore = true;
  // 时间线恢复锚定的目标时刻：分批排空期间 currentTime 仍在推进，
  // 若逐条读取实时 currentTime，同一批内较老的弹幕会被误判为"已过
  // 窗口"而在进入画面前被过滤，导致 seek 后弹幕播完即不再显示。
  double? _restorationTime;
  static const double _historyWindowSeconds = 5.0;
  static const double _scrollLeadTimeSeconds = 1.0;
  static const double _staticLeadTimeSeconds = 0.0;
  static const int _restorationBatchSize = 20;
  // 恢复期同一条弹幕最多重试几次（等待已上屏弹幕离屏腾出轨道），
  // 超限直接放弃，避免暂停状态下轨道永不腾空导致排空死循环。
  static const int _maxRestorationRetries = 3;

  @override
  void initState() {
    super.initState();
    _initializeDanmakuScreen();
  }

  int _effectiveScrollDurationSeconds() {
    final duration = widget.scrollDurationSeconds;
    if (duration.isNaN || duration.isInfinite) {
      return 10;
    }
    if (duration < 1.0) {
      return 1;
    }
    if (duration > 30.0) {
      return 30;
    }
    return duration.round();
  }

  void _initializeDanmakuScreen() {
    final durationSeconds = _effectiveScrollDurationSeconds();
    _currentOption = DanmakuOption(
      fontSize: widget.fontSize,
      opacity: widget.opacity,
      area: widget.displayArea,
      duration: durationSeconds,
      hideTop: widget.blockTopDanmaku,
      hideBottom: widget.blockBottomDanmaku,
      hideScroll: widget.blockScrollDanmaku,
      showStroke: true, // 默认显示描边
      massiveMode: widget.stacking,
      safeArea: true, // 为字幕预留空间
      playbackRate: widget.playbackRate,
    );

    _danmakuScreen = DanmakuScreen(
      key: ValueKey(_currentOption.hashCode),
      option: _currentOption!,
      createdController: (controller) {
        _controller = controller;
        if (!widget.isPlaying) {
          controller.pause();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !identical(_controller, controller)) return;
          _processAndAddDanmaku(widget.danmakuList, widget.currentTime);
        });
      },
    );
  }

  void _prepareForScreenRecreation() {
    _restorationGeneration++;
    _pendingRestoration = const [];
    _pendingRestorationIndex = 0;
    _restorationDrainScheduled = false;
    _addedDanmakuTimes.clear();
    _restorationRetryCounts.clear();
    _restorationTime = null;
    _forceTimelineRestore = true;
    _controller = null;
  }

  bool _needsScreenRecreation() {
    if (_currentOption == null) return true;

    return _currentOption!.fontSize != widget.fontSize ||
        _currentOption!.opacity != widget.opacity ||
        _currentOption!.area != widget.displayArea ||
        _currentOption!.hideTop != widget.blockTopDanmaku ||
        _currentOption!.hideBottom != widget.blockBottomDanmaku ||
        _currentOption!.hideScroll != widget.blockScrollDanmaku ||
        _currentOption!.massiveMode != widget.stacking ||
        // 注意：playbackRate 不在此处参与重建判断——倍速变化应只更新动画时长，
        // 否则长按倍速/松手时整块 DanmakuScreen 被重建（ValueKey 变），
        // 已上屏弹幕全部清空重加。倍速同步走 _syncPlaybackRateOnly()。
        _currentOption!.duration != _effectiveScrollDurationSeconds();
  }

  /// 仅同步倍速：只更新动画控制器时长（ScrollDanmakuPainter 用
  /// duration/playbackRate 计算每 tick 位移），不重建 DanmakuScreen、不清空弹幕。
  /// 已上屏弹幕从当前位置平滑加速/减速，不瞬移不重载。
  void _syncPlaybackRateOnly() {
    if (_controller == null || _currentOption == null) return;
    if ((_currentOption!.playbackRate - widget.playbackRate).abs() < 0.0001) {
      return;
    }
    _currentOption =
        _currentOption!.copyWith(playbackRate: widget.playbackRate);
    _controller!.updateOption(_currentOption!);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return const SizedBox.shrink();
    }

    // 如果配置发生变化，重新创建DanmakuScreen；仅倍速变化则只同步动画时长，
    // 不重建屏幕（避免长按倍速/松手时弹幕闪没重滑入）。
    if (_needsScreenRecreation()) {
      _prepareForScreenRecreation();
      _initializeDanmakuScreen();
    } else {
      _syncPlaybackRateOnly();
    }

    // 确保弹幕播放状态与视频播放状态同步
    if (_controller != null) {
      if (widget.isPlaying && !_controller!.running) {
        //print('Canvas弹幕: Consumer检测到需要恢复播放');
        _controller!.resume();
      } else if (!widget.isPlaying && _controller!.running) {
        //print('Canvas弹幕: Consumer检测到需要暂停播放');
        _controller!.pause();
      }
    }

    return _danmakuScreen!;
  }

  @override
  void dispose() {
    _controller?.clear();
    _restorationGeneration++;
    _controller = null;
    _addedDanmakuTimes.clear();
    _restorationRetryCounts.clear();
    _restorationTime = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(CanvasDanmakuRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.visible && oldWidget.visible) {
      _restorationGeneration++;
      _pendingRestoration = const [];
      _pendingRestorationIndex = 0;
      _restorationDrainScheduled = false;
      _addedDanmakuTimes.clear();
      _restorationRetryCounts.clear();
      _restorationTime = null;
      _controller = null;
    } else if (widget.visible && !oldWidget.visible) {
      _prepareForScreenRecreation();
      _initializeDanmakuScreen();
    }

    // 处理播放/暂停状态变化
    if (widget.isPlaying != oldWidget.isPlaying && _controller != null) {
      //print('Canvas弹幕: 播放状态变化 ${oldWidget.isPlaying} -> ${widget.isPlaying}');
      if (widget.isPlaying) {
        _controller!.resume();
      } else {
        _controller!.pause();
      }
    }

    final seekDetected = CanvasDanmakuTimeline.didSeek(
      previousRevision: oldWidget.seekRevision,
      currentRevision: widget.seekRevision,
      previousTime: oldWidget.currentTime,
      currentTime: widget.currentTime,
    );
    final listReplaced = !identical(widget.danmakuList, oldWidget.danmakuList);
    final timelineShifted =
        (widget.timeOffsetSeconds - oldWidget.timeOffsetSeconds).abs() > 0.0001;
    if (seekDetected || listReplaced || timelineShifted) {
      _forceTimelineRestore = true;
      _restorationGeneration++;
      _pendingRestoration = const [];
      _pendingRestorationIndex = 0;
      _restorationDrainScheduled = false;
    }

    // 只在时间变化、播放状态变化或其他重要属性变化时处理弹幕
    bool shouldProcessDanmaku = widget.currentTime != oldWidget.currentTime ||
        widget.danmakuList != oldWidget.danmakuList ||
        widget.danmakuListVersion != oldWidget.danmakuListVersion ||
        widget.seekRevision != oldWidget.seekRevision ||
        widget.timeOffsetSeconds != oldWidget.timeOffsetSeconds ||
        widget.isPlaying != oldWidget.isPlaying ||
        widget.fontSize != oldWidget.fontSize ||
        widget.opacity != oldWidget.opacity ||
        widget.displayArea != oldWidget.displayArea ||
        widget.visible != oldWidget.visible ||
        (widget.scrollDurationSeconds - oldWidget.scrollDurationSeconds).abs() >
            0.001;

    if (shouldProcessDanmaku) {
      // 获取最新的弹幕列表并处理
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _processAndAddDanmaku(widget.danmakuList, widget.currentTime);
      });
    }
  }

  void _processAndAddDanmaku(
      List<Map<String, dynamic>> danmakuList, double currentTime) {
    if (_controller == null) return;

    final hasPreviousTime = !_lastCurrentTime.isNaN;
    final timeDiff = hasPreviousTime
        ? (currentTime - _lastCurrentTime).abs()
        : 0.0;
    final timeChanged = !hasPreviousTime || timeDiff > 0.1;
    final dataChanged = widget.danmakuListVersion != _lastDanmakuListVersion ||
        _lastDanmakuListLength != danmakuList.length;
    final entriesRemoved = _lastDanmakuListLength >= 0 &&
        danmakuList.length < _lastDanmakuListLength;
    final listReplaced = _lastDanmakuList != null &&
        !identical(_lastDanmakuList, danmakuList);
    final fallbackSeek = widget.seekRevision < 0 &&
        hasPreviousTime &&
        timeDiff > CanvasDanmakuTimeline.fallbackSeekThresholdSeconds;
    final shouldRestore = _forceTimelineRestore ||
        listReplaced ||
        entriesRemoved ||
        fallbackSeek;

    _lastDanmakuList = danmakuList;
    _lastDanmakuListVersion = widget.danmakuListVersion;
    _lastDanmakuListLength = danmakuList.length;

    // 注意：_lastCurrentTime 只在"真正处理"时更新（见下方两处），
    // 不能放在函数开头提前 return 之前更新，否则 timeDiff 永远只有
    // 上一帧的增量（<0.1s），timeChanged 恒为 false，正常播放时
    // 窗口处理被跳过，seek 恢复填充的弹幕播完后就不会再有新弹幕了。
    if (shouldRestore) {
      _lastCurrentTime = currentTime;
      _forceTimelineRestore = false;
      _beginTimelineRestoration(danmakuList, currentTime);
      return;
    }

    if (_pendingRestorationIndex < _pendingRestoration.length) {
      _scheduleRestorationDrain(_restorationGeneration);
      return;
    }
    if (!timeChanged && !dataChanged) return;

    _lastCurrentTime = currentTime;
    _processNormalWindow(danmakuList, currentTime);
  }

  void _beginTimelineRestoration(
      List<Map<String, dynamic>> danmakuList, double currentTime) {
    _restorationGeneration++;
    final generation = _restorationGeneration;
    _restorationDrainScheduled = false;
    _controller!.clear();
    _addedDanmakuTimes.clear();
    _restorationRetryCounts.clear();
    _pendingRestoration = CanvasDanmakuTimeline.activeEntries(
      danmakuList,
      timeOf: _danmakuTime,
      currentTime: currentTime,
      lookBackSeconds: _effectiveScrollDurationSeconds().toDouble(),
    );
    _pendingRestorationIndex = 0;
    _restorationTime = currentTime;
    _drainTimelineRestoration(generation);
  }

  void _drainTimelineRestoration(int generation) {
    if (!mounted ||
        generation != _restorationGeneration ||
        _controller == null) {
      return;
    }

    // 用锚定时刻而非实时 currentTime 计算每条弹幕的初始位置，
    // 保证同批恢复的弹幕处于同一时间基准，不会因排空期间的推进被丢弃。
    final anchorTime = _restorationTime;
    if (anchorTime == null) {
      _pendingRestoration = const [];
      _pendingRestorationIndex = 0;
      return;
    }

    var processed = 0;
    while (_pendingRestorationIndex < _pendingRestoration.length &&
        processed < _restorationBatchSize) {
      final data = _pendingRestoration[_pendingRestorationIndex++];
      final added = _tryAddDanmaku(data, anchorTime, isRestoration: true);
      if (!added) {
        final retries = (_restorationRetryCounts[data] ?? 0) + 1;
        if (retries <= _maxRestorationRetries) {
          _restorationRetryCounts[data] = retries;
          // 轨道冲突被丢弃：放回队尾稍后重试，等已上屏弹幕离屏腾出轨道
          _pendingRestoration.add(data);
        } else {
          _restorationRetryCounts.remove(data);
        }
      } else {
        _restorationRetryCounts.remove(data);
      }
      processed++;
    }

    if (_pendingRestorationIndex < _pendingRestoration.length) {
      _scheduleRestorationDrain(generation);
      return;
    }

    _pendingRestoration = const [];
    _pendingRestorationIndex = 0;
    _restorationTime = null;

    // 排空完成后清理跟踪表，避免排空期间已过期的弹幕占用去重窗口，
    // 导致其后续正常进入窗口时被误判为已添加而不再显示。
    _pruneAddedDanmakuTimes(widget.currentTime);
    _processNormalWindow(widget.danmakuList, widget.currentTime);
  }

  void _scheduleRestorationDrain(int generation) {
    if (_restorationDrainScheduled) return;
    _restorationDrainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _restorationGeneration) return;
      _restorationDrainScheduled = false;
      _drainTimelineRestoration(generation);
    });
  }

  void _processNormalWindow(
      List<Map<String, dynamic>> danmakuList, double currentTime) {
    // 弹幕列表按 time 升序（上游 _updateMergedDanmakuList 保证），
    // 用二分定位窗口起点，避免每帧从列表头扫描整个弹幕列表。
    final windowStart = currentTime - _historyWindowSeconds;
    final windowEnd = currentTime + _scrollLeadTimeSeconds;
    final startIndex = CanvasDanmakuTimeline.lowerBound(
      danmakuList,
      windowStart,
      timeOf: _danmakuTime,
    );
    var addedCount = 0;

    for (int i = startIndex; i < danmakuList.length; i++) {
      final danmakuData = danmakuList[i];
      final time = _danmakuTime(danmakuData);
      if (time > windowEnd) break;
      if (_tryAddDanmaku(danmakuData, currentTime,
          isRestoration: false)) {
        addedCount++;
        if (addedCount >= 10) break;
      }
    }
    _pruneAddedDanmakuTimes(currentTime);
  }

  bool _tryAddDanmaku(
    Map<String, dynamic> danmakuData,
    double currentTime, {
    required bool isRestoration,
  }) {
    final time = _danmakuTime(danmakuData);
    final text = danmakuData['content']?.toString() ?? '';
    if (text.isEmpty || _shouldBlockDanmaku(text)) return false;

    if (_addedDanmakuTimes.containsKey(danmakuData)) return false;

    final canvasDanmaku = _convertToCanvasDanmaku(danmakuData, text);
    if (canvasDanmaku == null) return false;
    if (!isRestoration &&
        !_isDanmakuReadyToDisplay(canvasDanmaku, time, currentTime)) {
      return false;
    }

    final duration = _effectiveScrollDurationSeconds().toDouble();
    final elapsedSeconds = (currentTime - time).clamp(0.0, duration);
    var initialProgress = 0.0;
    if (canvasDanmaku.type == canvas_models.DanmakuItemType.scroll) {
      initialProgress = CanvasDanmakuTimeline.scrollProgress(
        scheduledTime: time,
        currentTime: currentTime,
        durationSeconds: duration,
      );
      if (initialProgress >= 1.0) return false;
    } else {
      final remaining = CanvasDanmakuTimeline.remainingLifetime(
        scheduledTime: time,
        currentTime: currentTime,
        durationSeconds: duration,
      );
      if (remaining <= 0) return false;
    }

    // 只有真正上屏（轨道可用、类型未隐藏）才记录到跟踪表，
    // 避免被丢弃的弹幕占用去重窗口，导致其后续重放缺失。
    final added = _controller!.addDanmaku(
      canvasDanmaku,
      initialProgress: initialProgress,
      elapsedSeconds: elapsedSeconds,
    );
    if (!added) return false;

    _addedDanmakuTimes[danmakuData] = time;
    return true;
  }

  double _danmakuTime(Map<String, dynamic> data) =>
      (data['time'] as num?)?.toDouble() ?? 0.0;

  void _pruneAddedDanmakuTimes(double currentTime) {
    final duration = _effectiveScrollDurationSeconds();
    final retainSeconds = duration > _historyWindowSeconds
        ? duration.toDouble()
        : _historyWindowSeconds;
    final cutoff = currentTime - retainSeconds - 1.0;
    _addedDanmakuTimes.removeWhere(
      (_, scheduledTime) => scheduledTime < cutoff,
    );
  }

  bool _isDanmakuReadyToDisplay(
    canvas_models.DanmakuContentItem danmaku,
    double scheduledTime,
    double currentTime,
  ) {
    final baseLead = danmaku.type == canvas_models.DanmakuItemType.scroll
        ? _scrollLeadTimeSeconds
        : _staticLeadTimeSeconds;
    return scheduledTime - currentTime <= baseLead;
  }

  // 检查弹幕是否应该被屏蔽
  bool _shouldBlockDanmaku(String text) {
    for (String blockWord in widget.blockWords) {
      if (text.contains(blockWord)) {
        return true;
      }
    }
    return false;
  }

  // 将抽象弹幕模型转换为Canvas弹幕模型
  canvas_models.DanmakuContentItem? _convertToCanvasDanmaku(
      Map<String, dynamic> danmakuData, String text) {
    try {
      if (text.isEmpty) {
        //print('Canvas弹幕: 转换失败 - 空文本');
        return null;
      }

      // 解析弹幕类型 - 处理字符串类型
      final typeValue = danmakuData['type'];
      canvas_models.DanmakuItemType type;
      if (typeValue is String) {
        switch (typeValue.toLowerCase()) {
          case 'top':
            type = canvas_models.DanmakuItemType.top;
            break;
          case 'bottom':
            type = canvas_models.DanmakuItemType.bottom;
            break;
          case 'scroll':
          default:
            type = canvas_models.DanmakuItemType.scroll;
            break;
        }
      } else {
        // 处理数字类型（向后兼容）
        final intType = typeValue as int? ?? 1;
        switch (intType) {
          case 4:
            type = canvas_models.DanmakuItemType.bottom;
            break;
          case 5:
            type = canvas_models.DanmakuItemType.top;
            break;
          default:
            type = canvas_models.DanmakuItemType.scroll;
            break;
        }
      }

      // 解析颜色 - 处理RGB字符串格式
      Color color = Colors.white;
      final colorValue = danmakuData['color'];
      if (colorValue is String) {
        // 解析 "rgb(255,255,255)" 格式
        final rgbMatch =
            RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(colorValue);
        if (rgbMatch != null) {
          final r = int.parse(rgbMatch.group(1)!);
          final g = int.parse(rgbMatch.group(2)!);
          final b = int.parse(rgbMatch.group(3)!);
          color = Color.fromRGBO(r, g, b, 1.0);
        }
      } else if (colorValue is int) {
        // 处理整数颜色值（向后兼容）
        color = Color(0xFF000000 | colorValue);
      }

      // 检查是否自己发送
      final isMe = danmakuData['isMe'] as bool? ?? false;

      //print('Canvas弹幕: 转换成功 - 文本="$text", 类型=$typeValue->$type, 颜色=${color.value.toRadixString(16)}, 自己发送=$isMe');

      return canvas_models.DanmakuContentItem(
        text,
        color: color,
        type: type,
        selfSend: isMe,
      );
    } catch (e) {
      //print('Canvas弹幕: 转换异常 - $e, 数据: $danmakuData');
      return null;
    }
  }
}
