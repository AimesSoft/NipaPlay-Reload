// lib/services/external_player_console_service.dart
// Linux 外部播放器控制台服务

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/linux_session.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/utils/danmaku/assets.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/external_player_danmaku_ass.dart';


/// 管理外部播放器控制台, 当前番剧信息和弹幕渲染状态.
///
/// 本服务维护弹幕源列表和 ASS 设置, 样式变化时重新生成 ASS;
/// mpv 进程交互统一委托给 [LinuxSession].
class ExternalPlayerConsoleService extends ChangeNotifier {

  // 单例
  ExternalPlayerConsoleService._();
  static final ExternalPlayerConsoleService _instance = ExternalPlayerConsoleService._();
  static ExternalPlayerConsoleService get instance => _instance;

  // 平台支持
  static bool get isSupportedPlatform => !kIsWeb && Platform.isLinux;

  // ------------------------------ //
  // -------- 内部状态字段 -------- //
  // ------------------------------ //

  LinuxSession?  _session; // 外部播放器会话

  // 动漫元数据相关
  String? _mediaPath;    // 播放的媒体文件路径
  String? _animeTitle;   // 番剧标题
  String? _episodeTitle; // 剧集标题
  int?    _episodeId;    // 剧集 ID

  // 弹幕资产相关
  String? _danmakuAssPath;
  String? _danmakuLuaPath;
  List<DanmakuItem>   _danmakuList = const []; // 弹幕列表
  AssExportSettings?  _danmakuAssSettings;
  List<String>        _blockedKeywords = const []; // 弹幕屏蔽关键词列表

  // 弹幕样式相关
  DanmakuStyle _danmakuStyle = DanmakuStyle();
  // 弹幕样式更新队列
  // 由于 ASS 样式更新可能涉及文件写入和 mpv IPC 通信, 为避免并发冲突, 使用队列顺序执行样式更新任务
  Future<void> _danmakuStyleUpdateQueue = Future<void>.value();


  // ------------------------------ //
  // -------- 公共访问接口 -------- //
  // ------------------------------ //

  LinuxSession? get session => _session;
  bool get hasActiveSession => _session != null;
  bool get supportsDanmakuOpacity =>
      _session?.ipcPath != null &&
      _danmakuAssPath != null &&
      _danmakuLuaPath != null &&
      _danmakuAssSettings != null;
  bool get supportsDanmakuOutline => supportsDanmakuOpacity;

  String? get mediaPath => _mediaPath;
  String? get animeTitle => _animeTitle;
  String? get episodeTitle => _episodeTitle;
  int? get episodeId => _episodeId;
  List<DanmakuItem> get danmakuList => _danmakuList;
  List<String> get blockedKeywords => _blockedKeywords;
  double get danmakuOpacity => _danmakuStyle.opacity;
  double get danmakuOutlineWidth => _danmakuStyle.outlineWidth;

  /// 获取当前播放位置正在显示的弹幕索引列表.
  List<int> get activeDanmakuIndices {
    final current = _session;
    final position = current?.position;
    if (current == null || position == null) return const [];
    final items = _danmakuList;
    final maximumDuration = _maxDanmakuDuration();
    if (items.isEmpty || maximumDuration <= Duration.zero) return const [];

    var low = 0;
    var high = items.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (danmakuStartTime(items[middle]) <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    final earliestPossibleStart = position - maximumDuration;
    final active = <int>[];
    for (var index = low - 1; index >= 0; index--) {
      final item = items[index];
      if (!item.visible) continue;
      final startTime = danmakuStartTime(item);
      if (startTime < earliestPossibleStart) break;
      if (position >= startTime &&
          position < startTime + _danmakuDisplayDuration(item)) {
        active.add(index);
      }
    }
    return List<int>.unmodifiable(active.reversed);
  }

  /// 获取弹幕的实际显示时间, 考虑了 ASS 设置中的时间偏移
  Duration danmakuStartTime(DanmakuItem item) {
    final offsetSeconds = _danmakuAssSettings?.timeOffsetSeconds ?? 0.0;
    return item.time + Duration(microseconds:(offsetSeconds * Duration.microsecondsPerSecond).round());
  }

  /// 设置新的 mpv 会话和控制台展示信息.
  static void showSession(
    ExternalPlayerLaunchSession session, {
    PlayableItem? playableItem,
    DanmakuLaunchAssets? danmakuAssets,
  }) {

    // 目前仅支持 Linux + mpv, 其他平台直接忽略
    if (!isSupportedPlatform || session is! LinuxSession) return;

    // 先移除之前会话的监听器
    final previous = _instance._session;
    previous?.removeListener(_handleSessionChanged);

    // 如果之前有会话且不是同一个实例, 先关闭之前的会话
    if (previous != null && !identical(previous, session)) {
      previous.terminate();
    }

    // 设置新的会话和媒体信息
    _instance._session = session;
    _instance._mediaPath = playableItem?.videoPath;
    _instance._animeTitle = playableItem?.title;
    _instance._episodeTitle = playableItem?.subtitle;
    _instance._episodeId = playableItem?.episodeId;
    _instance._setDanmakuAssets(danmakuAssets);
    session.addListener(_handleSessionChanged);

    // 如果新会话已经关闭, 立即清理
    if (session.isClosed) {
      _clearSession(session);
      return;
    }

    // 通知监听器更新 UI
    _instance.notifyListeners();
  }

  /// 关闭当前 mpv 会话和控制台
  static void closePlayerAndConsole() {
    final current = _instance._session;
    if (current == null) return;

    current.removeListener(_handleSessionChanged);
    current.terminate();
    _instance._session = null;
    _instance._clearMediaInfo();
    _instance._clearDanmakuState();
    _instance.notifyListeners();
  }

  /// 切换 mpv 的暂停状态
  static void togglePause() {
    _instance._session?.togglePause();
  }

  /// 跳转到指定的播放位置, 以播放进度的百分比表示
  static void seekToFraction(double fraction) {
    _instance._session?.seekToFraction(fraction);
  }

  /// 将时间戳解析为绝对位置并让 mpv 精确跳转.
  static bool seekToTimestamp(String timestamp) {
    final target = _parseTimestamp(timestamp);
    if (target == null) return false;
    return _instance._session?.seekToPosition(target) ?? false;
  }

  /// 设置弹幕的不透明度, 范围为 0.0 到 1.0
  static void setDanmakuOpacity(double opacity) {
    if (!_instance.supportsDanmakuOpacity) return;
    _instance._updateDanmakuStyle((style) => style.opacity = opacity);
  }

  /// 设置弹幕描边宽度:
  /// [width] 的范围为 0.5 到 5.0, 超出范围将被限制在有效范围内
  static void setDanmakuOutlineWidth(double width) {

    // 支持检查
    if (!_instance.supportsDanmakuOutline) return;

    // 刷新控制台
    _instance._updateDanmakuStyle((style) => style.outlineWidth = width);
  }

  /// 添加一个按内容匹配的弹幕屏蔽关键词.
  static bool addBlockedKeyword(String keyword) {
    final value = keyword.trim();
    if (value.isEmpty) return false;
    if (_instance._blockedKeywords.any(
      (item) => item.toLowerCase() == value.toLowerCase(),
    )) {
      return false;
    }
    _instance._blockedKeywords = List<String>.unmodifiable([
      ..._instance._blockedKeywords,
      value,
    ]);
    _instance._applyBlockedKeywords();
    _instance.notifyListeners();
    _instance._queueDanmakuRefresh();
    return true;
  }

  /// 移除一个弹幕屏蔽关键词.
  static void removeBlockedKeyword(String keyword) {
    final keywords = _instance._blockedKeywords
        .where((item) => item != keyword)
        .toList(growable: false);
    if (keywords.length == _instance._blockedKeywords.length) return;
    _instance._blockedKeywords = List<String>.unmodifiable(keywords);
    _instance._applyBlockedKeywords();
    _instance.notifyListeners();
    _instance._queueDanmakuRefresh();
  }

  // ------------------------------ //
  // -------- 私有实现方法 -------- //
  // ------------------------------ //

  static Duration? _parseTimestamp(String timestamp) {
    final value = timestamp.trim();
    if (value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.isEmpty || parts.length > 3) return null;

    final secondsPattern = RegExp(r'^\d+(?:\.\d{1,3})?$');
    if (!secondsPattern.hasMatch(parts.last)) return null;
    final seconds = double.tryParse(parts.last);
    if (seconds == null || !seconds.isFinite) return null;

    var hours = 0;
    var minutes = 0;
    if (parts.length >= 2) {
      minutes = int.tryParse(parts[parts.length - 2]) ?? -1;
      if (minutes < 0) return null;
    }
    if (parts.length == 3) {
      hours = int.tryParse(parts.first) ?? -1;
      if (hours < 0 || minutes >= 60) return null;
    }
    if (parts.length > 1 && seconds >= 60) return null;

    final totalMilliseconds = ((hours * 3600 + minutes * 60 + seconds) * 1000).round();
    return Duration(milliseconds: totalMilliseconds);
  }

  AssExportSettings? _danmakuAssSettingsFor(DanmakuStyle style) {
    final settings = _danmakuAssSettings;
    if (settings == null) return null;
    final outlineStyle = settings.outlineStyle == AssOutlineStyle.none
        ? AssOutlineStyle.stroke
        : settings.outlineStyle;
    return settings.copyWith(
      opacity: style.opacity,
      outlineStyle: style.outlineEnabled ? outlineStyle : AssOutlineStyle.none,
      outlineWidth: style.outlineWidth,
    );
  }

  void _updateDanmakuStyle(void Function(DanmakuStyle style) update) {
    final style = _danmakuStyle.copyWith();
    update(style);
    _danmakuStyle = style;
    notifyListeners();
    _queueDanmakuRefresh();
  }

  Duration _danmakuDisplayDuration(DanmakuItem item) {
    final seconds = item.mode.isScrolling
        ? _danmakuAssSettings?.scrollDurationSeconds ?? 10.0
        : kAssFixedDanmakuDurationSeconds;
    if (!seconds.isFinite || seconds <= 0) {
      return item.mode.isScrolling
          ? const Duration(seconds: 10)
          : const Duration(seconds: 5);
    }
    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  bool _isDanmakuBlocked(DanmakuItem item) {
    final content = item.content.toLowerCase();
    return _blockedKeywords.any(
      (keyword) => content.contains(keyword.toLowerCase()),
    );
  }

  void _applyBlockedKeywords() {
    for (final item in _danmakuList) {
      item.visible = !_isDanmakuBlocked(item);
    }
  }

  Duration _maxDanmakuDuration() {
    var maximum = Duration.zero;
    for (final item in _danmakuList) {
      if (!item.visible) continue;
      final duration = _danmakuDisplayDuration(item);
      if (duration > maximum) maximum = duration;
    }
    return maximum;
  }

  /// 将弹幕样式更新任务加入队列, 以顺序执行样式更新
  void _queueDanmakuRefresh() {

    // 记录当前状态
    final currentSession  = _session;
    final style           = _danmakuStyle;
    final blockedKeywords = _blockedKeywords;

    Future<void> fun(_) async {
      // 如果在队列等待期间状态发生变化, 则跳过当前任务
      if (!identical(_session, currentSession) ||
          !identical(_danmakuStyle, style) ||
          !identical(_blockedKeywords, blockedKeywords)) {
        return;
      }
      await _regenerateDanmakuAss(
        currentSession,
        style,
        blockedKeywords,
      );
    }

    // 将任务加入队列
    _danmakuStyleUpdateQueue = _danmakuStyleUpdateQueue.then(fun);
  }

  /// 重新生成 ASS 文件并刷新 mpv 弹幕, 仅在状态未发生变化时执行
  Future<void> _regenerateDanmakuAss(
    LinuxSession? currentSession,
    DanmakuStyle style,
    List<String> blockedKeywords,
  ) async {

    // 参数检查
    final assPath  = _danmakuAssPath;
    final luaPath  = _danmakuLuaPath;
    final settings = _danmakuAssSettingsFor(style);
    if (currentSession == null || assPath == null || luaPath == null || settings == null) return;

    File? temporaryFile; // 临时文件, 用于在写入 ASS 文件时避免覆盖原文件
    try {

      // 生成 ASS 内容
      final assStr = await generateExternalPlayerDanmakuAss(
        _danmakuList,
        settings,
        allowStacking: style.danmakuAllowStacking,
      );

      // 如果在生成 ASS 期间状态发生变化, 则跳过当前任务
      if (!identical(_session, currentSession) ||
          !identical(_danmakuStyle, style) ||
          !identical(_blockedKeywords, blockedKeywords)) {
        return;
      }

      // 写入临时文件
      temporaryFile = File('$assPath.nipaplay.tmp');
      await temporaryFile.writeAsString(assStr, encoding: utf8, flush: true);

      // 如果在写入临时文件期间状态发生变化, 则跳过当前任务
      if (!identical(_session, currentSession) ||
          !identical(_danmakuStyle, style) ||
          !identical(_blockedKeywords, blockedKeywords)) {
        return;
      }

      // 将临时文件重命名为目标 ASS 文件路径, 覆盖原文件
      temporaryFile.renameSync(assPath);
      temporaryFile = null;

      // 刷新 mpv 弹幕
      final refreshed = await currentSession.refreshDanmaku(assPath, luaPath);
      if (!refreshed) debugPrint('[ExternalPlayerConsoleService] Failed to refresh danmaku');

    } catch (error) {
      debugPrint('[ExternalPlayerConsoleService] Failed to regenerate ASS: $error');
    }
    finally {
      // 删除临时文件, 如果存在的话
      if (temporaryFile?.existsSync() == true) temporaryFile?.deleteSync();
    }
  }

  static void _handleSessionChanged() {
    final current = _instance._session;
    if (current != null && current.isClosed) {
      _clearSession(current);
      return;
    }
    _instance.notifyListeners();
  }

  static void _clearSession(LinuxSession session) {
    if (!identical(_instance._session, session)) return;

    session.removeListener(_handleSessionChanged);
    _instance._session = null;
    _instance._clearMediaInfo();
    _instance._clearDanmakuState();
    _instance.notifyListeners();
  }

  void _clearMediaInfo() {
    _mediaPath = null;
    _animeTitle = null;
    _episodeTitle = null;
    _episodeId = null;
  }

  void _setDanmakuAssets(DanmakuLaunchAssets? assets) {
    _danmakuAssPath = assets?.assPath;
    _danmakuLuaPath = assets?.luaPath;
    _danmakuList = _sortDanmakuItems(assets?.danmakuList ?? const []);
    _applyBlockedKeywords();
    _danmakuAssSettings = assets?.assSettings;
    final settings = assets?.assSettings;
    final outlineWidth = settings?.outlineWidth ?? 1.0;
    final outlineEnabled = settings != null &&
        settings.outlineStyle != AssOutlineStyle.none &&
        outlineWidth > 0.0;
    _danmakuStyle = DanmakuStyle(
      opacity: assets?.opacity ?? DanmakuStyle.maxOpacity,
      outlineWidth: outlineEnabled ? outlineWidth : 0.0,
      danmakuAllowStacking: assets?.allowStacking ?? true,
    );
  }

  void _clearDanmakuState() {
    _setDanmakuAssets(null);
    _blockedKeywords = const [];
  }

  static List<DanmakuItem> _sortDanmakuItems(List<DanmakuItem> items) {
    final sorted = List<DanmakuItem>.of(items);
    sorted.sort((a, b) => a.time.compareTo(b.time));
    return List<DanmakuItem>.unmodifiable(sorted);
  }
}
