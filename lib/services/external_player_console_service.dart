// lib/services/external_player_console_service.dart
// Linux 外部播放器控制台服务

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/linux_session.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/external_player_danmaku_ass.dart';


/// 弹幕屏蔽规则类型.
enum ItemType {
  keyword,
  regex,
  userId,
}


/// 弹幕屏蔽项目
class BlockedDanmakuItem {

  final String value;
  final ItemType type;

  const BlockedDanmakuItem({
    required this.value,
    required this.type,
  });
}

/// 番剧元数据
class EpisodeMetaData {
  final String? animeTitle;
  final String? episodeTitle;
  final int? episodeId;

  const EpisodeMetaData({
    this.animeTitle,
    this.episodeTitle,
    this.episodeId,
  });
}


/// 管理外部播放器控制台, 当前番剧信息和弹幕渲染状态.
///
/// 本服务维护弹幕源列表和 ASS 设置, 样式变化时重新生成 ASS;
/// 外部播放器进程交互统一委托给 [ExternalPlayerLaunchSession].
class ExternalPlayerConsoleService extends ChangeNotifier {

  // 单例
  ExternalPlayerConsoleService._();
  static final ExternalPlayerConsoleService _instance = ExternalPlayerConsoleService._();
  static ExternalPlayerConsoleService get instance => _instance;

  // 平台支持
  static bool get isSupportedPlatform => !kIsWeb && Platform.isLinux;


  // ======================================================================== //
  // =========================== 内部状态字段 =============================== //
  // ======================================================================== //

  static int _stateTimestamp = 0; // 配置变更时间戳, 用于检测异步任务是否已过期

  ExternalPlayerLaunchSession?  _session; // 外部播放器会话

  // 动漫元数据相关
  String? _animeTitle;   // 番剧标题
  String? _episodeTitle; // 剧集标题
  int?    _episodeId;    // 剧集 ID

  // 弹幕资产相关
  List<DanmakuItem>        _danmakuList = const []; // 弹幕列表
  List<BlockedDanmakuItem> _blockedItems = const []; // 弹幕屏蔽项目列表
  /// 当前弹幕样式. 外部修改字段后调用 [queueDanmakuRefresh] 应用到 mpv.
  final DanmakuStyle _danmakuStyle = DanmakuStyle();
  // 弹幕样式更新队列
  // 由于 ASS 样式更新可能涉及文件写入和 mpv IPC 通信, 为避免并发冲突, 使用队列顺序执行样式更新任务
  Future<void> _danmakuStyleUpdateQueue = Future<void>.value();


  // ======================================================================== //
  // ========================= Getters & Setters ============================ //
  // ======================================================================== //

  DanmakuStyle get danmakuStyle => _danmakuStyle;

  ExternalPlayerLaunchSession? get session => _session;
  bool get hasActiveSession => _session != null;

  String? get animeTitle => _animeTitle;
  String? get episodeTitle => _episodeTitle;
  int? get episodeId => _episodeId;
  List<DanmakuItem> get danmakuList => _danmakuList;
  List<BlockedDanmakuItem> get blockedItems => _blockedItems;
  static int get stateTimestamp => _stateTimestamp;

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

  /// 获取弹幕的实际显示时间, 考虑了时间偏移
  Duration danmakuStartTime(DanmakuItem item) {
    final offsetSeconds = _danmakuStyle.danmakuOffset;
    return item.time + Duration(microseconds:(offsetSeconds * Duration.microsecondsPerSecond).round());
  }


  // ======================================================================== //
  // ============================== 主要方法 ================================ //
  // ======================================================================== //


  // 会话创建和关闭
  // ------------------------------------------------------------------------ //

  /// 设置新的 mpv 会话和控制台展示信息.
  static void showSession({
    required ExternalPlayerLaunchSession session, // 外部播放器会话
    EpisodeMetaData   ? episodeMetaData,  // 番剧元数据
    List<DanmakuItem> ? danmakuList,      // 弹幕列表
    DanmakuStyle      ? danmakuStyle,     // 弹幕样式
  }) {

    // 先移除之前会话的监听器
    final previous = _instance._session;
    previous?.removeListener(_handleSessionChanged);

    // 如果之前有会话且不是同一个实例, 先关闭之前的会话
    if (previous != null && !identical(previous, session)) previous.terminate();

    // 设置新的会话和媒体信息
    _instance._session      = session;
    _instance._animeTitle   = episodeMetaData?.animeTitle;
    _instance._episodeTitle = episodeMetaData?.episodeTitle;
    _instance._episodeId    = episodeMetaData?.episodeId;

    _instance._setDanmakuState(danmakuList: danmakuList, danmakuStyle: danmakuStyle);

    _markConfigurationChanged('showSession');
    session.addListener(_handleSessionChanged);

    // 如果新会话已经关闭, 立即清理
    if (session.isClosed) {
      _clearSession(session);
      return;
    }

    // 通知监听器更新 UI
    _instance.notifyListeners();
  }

  /// 关闭当前会话和控制台
  static void closePlayerAndConsole() {
    final current = _instance._session;
    if (current == null) return;

    current.removeListener(_handleSessionChanged);
    current.terminate();
    _instance._session = null;
    _instance._clearMediaInfo();
    _instance._clearDanmakuState();
    _markConfigurationChanged('closePlayerAndConsole');
    _instance.notifyListeners();
  }


  // 视频控制
  // ------------------------------------------------------------------------ //

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


  // 弹幕控制
  // ------------------------------------------------------------------------ //

  /// 通知监听器并将当前弹幕配置加入刷新队列.
  ///
  /// 入队时复制 [danmakuStyle], 以避免后续修改影响正在执行的任务.
  void queueDanmakuRefresh() {

    _markConfigurationChanged('queueDanmakuRefresh');
    notifyListeners();

    // 记录当前状态
    final currentSession  = _session;
    // 没有完整弹幕资产或 IPC 时只更新控制台状态, 无需生成 ASS
    if (currentSession is! LinuxSession ||
        currentSession.ipcPath == null ||
        currentSession.danmakuAssets == null ||
        _danmakuList.isEmpty) {
      return;
    }

    // 保留当前样式和时间戳, 以便在异步任务中检查状态是否已过期
    final style     = danmakuStyle.copyWith();
    final timestamp = _stateTimestamp;

    Future<void> fun(_) async {
      // 如果在队列等待期间状态发生变化, 则跳过当前任务
      if (_configurationHasChanged(timestamp)) return;
      await _regenerateDanmakuAss(currentSession, style, timestamp);
    }

    // 将任务加入队列
    _danmakuStyleUpdateQueue = _danmakuStyleUpdateQueue.then(fun);
  }

  /// 设置单条弹幕是否参与渲染.
  static bool setDanmakuVisible(DanmakuItem item, bool visible) {

    // 检查弹幕是否属于当前列表, 并且状态是否发生变化
    if (!_instance._danmakuList.any((candidate) => identical(candidate, item))) return false;
    if (item.visible == visible) return false;

    item.visible = visible;
    _instance.queueDanmakuRefresh();
    return true;
  }

  /// 添加一条弹幕屏蔽规则.
  static bool addBlockedItem(String input, ItemType type) {
    final value = input.trim();
    if (value.isEmpty) return false;
    if (type == ItemType.regex) {
      try {
        RegExp(value, caseSensitive: false);
      } on FormatException {
        return false;
      }
    }
    if (_instance._blockedItems.any(
      (item) => item.type == type &&
          item.value.toLowerCase() == value.toLowerCase(),
    )) {
      return false;
    }
    _instance._blockedItems = List<BlockedDanmakuItem>.unmodifiable([
      ..._instance._blockedItems,
      BlockedDanmakuItem(value: value, type: type),
    ]);
    _instance._applyBlockedItems();
    _instance.queueDanmakuRefresh();
    return true;
  }

  /// 移除一条弹幕屏蔽规则.
  static void removeBlockedItem(BlockedDanmakuItem blockedItem) {
    final items = _instance._blockedItems
        .where((item) => !identical(item, blockedItem))
        .toList(growable: false);
    if (items.length == _instance._blockedItems.length) return;
    _instance._blockedItems = List<BlockedDanmakuItem>.unmodifiable(items);
    _instance._applyBlockedItems();
    _instance.queueDanmakuRefresh();
  }


  // ======================================================================== //
  // ============================== 私有方法 ================================ //
  // ======================================================================== //

  static void _markConfigurationChanged(String reason) {
    final now = DateTime.now().microsecondsSinceEpoch;
    _stateTimestamp = now > _stateTimestamp ? now : _stateTimestamp + 1; // 确保时间戳单调递增
    debugPrint('[ExternalPlayerConsoleService] Configuration changed: $reason, timestamp=$_stateTimestamp');
  }

  static bool _configurationHasChanged(int timestamp) {
    return _stateTimestamp != timestamp;
  }

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

  AssExportSettings _danmakuAssSettingsFor(
    AssExportSettings settings,
    DanmakuStyle style,
  ) {
    final outlineStyle = settings.outlineStyle == AssOutlineStyle.none
        ? AssOutlineStyle.stroke
        : settings.outlineStyle;
    return settings.copyWith(
      fontSize: style.danmakuFontSize,
      opacity: style.opacity,
      timeOffsetSeconds: style.danmakuOffset,
      outlineStyle: style.outlineEnabled ? outlineStyle : AssOutlineStyle.none,
      outlineWidth: style.outlineWidth,
    );
  }

  Duration _danmakuDisplayDuration(DanmakuItem item) {
    final current = _session;
    final settings = current is LinuxSession
        ? current.danmakuAssets?.assSettings
        : null;
    final seconds = item.mode.isScrolling
        ? settings?.scrollDurationSeconds ?? 10.0
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

    // 根据屏蔽项目类型进行匹配
    for (final blockedItem in _blockedItems) {
      final blockedValue = blockedItem.value.toLowerCase();
      switch (blockedItem.type) {
        case ItemType.keyword:
          if (content.contains(blockedValue)) return true;
          break;
        case ItemType.regex:
          if (RegExp(
            blockedItem.value,
            caseSensitive: false,
          ).hasMatch(item.content)) {
            return true;
          }
          break;
        case ItemType.userId:
          if (item.senderId?.toLowerCase() == blockedValue) return true;
          break;
      }
    }
    return false;
  }

  void _applyBlockedItems() {
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

  /// 重新生成 ASS 文件并刷新 mpv 弹幕, 仅在状态未发生变化时执行
  Future<void> _regenerateDanmakuAss(
    ExternalPlayerLaunchSession? currentSession,
    DanmakuStyle style,
    int timestamp,
  ) async {

    // 参数检查
    if (currentSession is! LinuxSession) return;
    final assets = currentSession.danmakuAssets;
    if (assets == null) return;
    final assPath  = assets.assPath;
    final luaPath  = assets.luaPath;
    final settings = _danmakuAssSettingsFor(assets.assSettings, style);

    File? temporaryFile; // 临时文件, 用于在写入 ASS 文件时避免覆盖原文件
    try {

      // 生成 ASS 内容
      final assStr = await generateExternalPlayerDanmakuAss(
        _danmakuList,
        settings,
        allowStacking: style.danmakuAllowStacking,
      );

      // 如果在生成 ASS 期间状态发生变化, 则跳过当前任务
      if (_configurationHasChanged(timestamp)) return;

      // 写入临时文件
      temporaryFile = File('$assPath.nipaplay.tmp');
      await temporaryFile.writeAsString(assStr, encoding: utf8, flush: true);

      // 如果在写入临时文件期间状态发生变化, 则跳过当前任务
      if (_configurationHasChanged(timestamp)) return;

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

  static void _clearSession(ExternalPlayerLaunchSession session) {
    if (!identical(_instance._session, session)) return;

    session.removeListener(_handleSessionChanged);
    _instance._session = null;
    _instance._clearMediaInfo();
    _instance._clearDanmakuState();
    _markConfigurationChanged('clearSession');
    _instance.notifyListeners();
  }

  void _clearMediaInfo() {
    _animeTitle = null;
    _episodeTitle = null;
    _episodeId = null;
  }

  void _setDanmakuState({
    List<DanmakuItem>? danmakuList,
    DanmakuStyle? danmakuStyle,
  }) {
    _danmakuList = _sortDanmakuItems(danmakuList ?? const []);
    _applyBlockedItems();
    final style = danmakuStyle ?? DanmakuStyle();
    _danmakuStyle.opacity = style.opacity;
    _danmakuStyle.outlineWidth = style.outlineWidth;
    _danmakuStyle.danmakuFontSize = style.danmakuFontSize;
    _danmakuStyle.danmakuOffset = style.danmakuOffset;
    _danmakuStyle.danmakuAllowStacking = style.danmakuAllowStacking;
  }

  void _clearDanmakuState() {
    _setDanmakuState();
    _blockedItems = const [];
  }

  static List<DanmakuItem> _sortDanmakuItems(List<DanmakuItem> items) {
    final sorted = List<DanmakuItem>.of(items);
    sorted.sort((a, b) => a.time.compareTo(b.time));
    return List<DanmakuItem>.unmodifiable(sorted);
  }
}
