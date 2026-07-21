// lib/services/external_player_console_service.dart
// Linux 外部播放器控制台服务

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/danmaku/blocked_item.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/linux_session.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/external_player_danmaku_ass.dart';
import 'package:nipaplay/utils/utils.dart';


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

/// 控制台状态
class ConsoleState {

  final ExternalPlayerLaunchSession session;          // 外部播放器会话
  final EpisodeMetaData           ? episodeMetaData;  // 番剧元数据
  final List<DanmakuItem>         ? danmakuList;      // 弹幕列表
  final DanmakuStyle              ? danmakuStyle;     // 弹幕样式

  const ConsoleState({
    required this.session,
    this.episodeMetaData,
    this.danmakuList,
    this.danmakuStyle,
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

  // 平台支持
  static bool get isSupportedPlatform => !kIsWeb && Platform.isLinux;


  // ======================================================================== //
  // =========================== 内部状态字段 =============================== //
  // ======================================================================== //

  static int _stateTimestamp = 0; // 配置变更时间戳, 用于检测异步任务是否已过期

  static ExternalPlayerLaunchSession?  _session; // 外部播放器会话

  // 动漫元数据相关
  // ------------------------------------------------------------------------ //
  static String? _animeTitle;   // 番剧标题
  static String? _episodeTitle; // 剧集标题
  static int?    _episodeId;    // 剧集 ID


  // 弹幕资产相关
  // ------------------------------------------------------------------------ //

  // 弹幕列表和屏蔽规则
  static List<BlockedDanmakuItem> _blockedItems = const []; // 弹幕屏蔽项目列表
  static List<DisplayDanmakuItem> _displayDanmakuList = const []; // 弹幕列表, 包含源数据和显示状态

  /// 当前弹幕样式. 外部修改字段后调用 [queueDanmakuRefresh] 应用到 mpv.
  static final DanmakuStyle _danmakuStyle = DanmakuStyle();
  // 弹幕样式更新队列
  // 由于 ASS 样式更新可能涉及文件写入和 mpv IPC 通信, 为避免并发冲突, 使用队列顺序执行样式更新任务
  static Future<void> _danmakuStyleUpdateQueue = Future<void>.value();


  // ======================================================================== //
  // ========================= Getters & Setters ============================ //
  // ======================================================================== //

  static Listenable get instance => _instance;
  static bool       get hasActiveSession => _session != null;

  // 播放状态相关
  // ------------------------------------------------------------------------ //
  static String   ? get mediaPath => _session?.mediaPath;
  static int      ? get processId => _session?.processId;
  static String   ? get ipcPath   => _session?.ipcPath;

  // 播放控制相关
  // ------------------------------------------------------------------------ //
  static Duration   get duration  => _session?.duration ?? Duration.zero;
  static Duration ? get position  => _session?.position;
  static double   ? get fraction  => _session?.fraction;
  static bool     ? get isPaused  => _session?.isPaused;

  // 番剧信息相关
  // ------------------------------------------------------------------------ //
  static String ? get animeTitle   => _animeTitle;
  static String ? get episodeTitle => _episodeTitle;
  static int    ? get episodeId    => _episodeId;

  static DanmakuStyle get danmakuStyle => _danmakuStyle;

  static List<DisplayDanmakuItem> get displayDanmakuList => _displayDanmakuList;
  static List<BlockedDanmakuItem> get blockedItems => _blockedItems;
  static int get stateTimestamp => _stateTimestamp;

  // ======================================================================== //
  // ============================== 主要方法 ================================ //
  // ======================================================================== //


  // 会话创建和关闭
  // ------------------------------------------------------------------------ //

  /// 设置新的 mpv 会话和控制台展示信息.
  static void setState(ConsoleState state) {

    final session         = state.session;
    final episodeMetaData = state.episodeMetaData;
    final danmakuList     = state.danmakuList;
    final danmakuStyle    = state.danmakuStyle;

    // 先移除之前会话的监听器
    final previous = _session;
    previous?.removeListener(_handleSessionChanged);

    // 如果之前有会话且不是同一个实例, 先关闭之前的会话
    if (previous != null && !identical(previous, session)) previous.terminate();

    // 设置新的会话和媒体信息
    _session      = session;
    _animeTitle   = episodeMetaData?.animeTitle;
    _episodeTitle = episodeMetaData?.episodeTitle;
    _episodeId    = episodeMetaData?.episodeId;

    // 更新弹幕样式, 如果未提供则保持现有样式
    final style = danmakuStyle ?? DanmakuStyle();
    _danmakuStyle.opacity = style.opacity;
    _danmakuStyle.outlineWidth = style.outlineWidth;
    _danmakuStyle.danmakuFontSize = style.danmakuFontSize;
    _danmakuStyle.danmakuOffset = style.danmakuOffset;
    _danmakuStyle.danmakuAllowStacking = style.danmakuAllowStacking;

    // 按照时间戳排序弹幕列表, 并创建初始显示项目
    final sorted = List<DanmakuItem>.of(danmakuList ?? const []);
    sorted.sort((a, b) => a.time.compareTo(b.time));
    _displayDanmakuList = List<DisplayDanmakuItem>.unmodifiable(
      sorted.indexed.map((entry) {
        final (index, item) = entry;
        return DisplayDanmakuItem(
          item      : item,
          index     : index,
          startTime : item.time,
          duration  : Duration.zero,
          isBlocked : false,
          isActive  : false,
        );
      }),
    );

    // 更新用于显示的弹幕列表
    _updateDisplayDanmakuList();

    _markConfigurationChanged('showSession');
    session.addListener(_handleSessionChanged);

    // 通知监听器更新 UI
    _instance.notifyListeners();
  }

  /// 关闭当前会话和控制台
  static void closePlayerAndConsole() {
    final current = _session;
    if (current == null) return;

    current.removeListener(_handleSessionChanged);
    current.terminate();
    _session = null;

    // 清空媒体信息
    _animeTitle = null;
    _episodeTitle = null;
    _episodeId = null;

    // 清空弹幕状态, 包括源列表和屏蔽规则
    _displayDanmakuList = const [];
    _blockedItems = const [];

    _markConfigurationChanged('closePlayerAndConsole');
    _instance.notifyListeners();
  }


  // 视频控制
  // ------------------------------------------------------------------------ //

  /// 切换 mpv 的暂停状态
  static void togglePause() {
    _session?.togglePause();
  }

  /// 跳转到指定的播放位置, 以播放进度的百分比表示
  static void seekToFraction(double fraction) {
    _session?.seekToFraction(fraction);
  }

  /// 将时间戳解析为绝对位置并让 mpv 精确跳转.
  static bool seekToTimestamp(String timestamp) {
    final target = parseTimestamp(timestamp);
    if (target == null) return false;
    return _session?.seekToPosition(target) ?? false;
  }


  // 弹幕控制
  // ------------------------------------------------------------------------ //

  static void adjustDanmakuOffset(double seconds) {
    if (!seconds.isFinite) return;
    setDanmakuOffset(_danmakuStyle.danmakuOffset + seconds);
  }

  static void setDanmakuOffset(double seconds) {
    if (!seconds.isFinite) _danmakuStyle.danmakuOffset = 0.0;
    _danmakuStyle.danmakuOffset = seconds;
    queueDanmakuRefresh();
  }

  static void resetDanmakuOffset() {
    _danmakuStyle.danmakuOffset = 0.0;
    queueDanmakuRefresh();
  }

  /// 通知监听器并将当前弹幕配置加入刷新队列.
  ///
  /// 入队时复制 [danmakuStyle], 以避免后续修改影响正在执行的任务.
  static void queueDanmakuRefresh() {

    _updateDisplayDanmakuList();
    _markConfigurationChanged('queueDanmakuRefresh');
    _instance.notifyListeners();

    // 记录当前状态
    final currentSession  = _session;
    // 没有完整弹幕资产或 IPC 时只更新控制台状态, 无需生成 ASS
    if (currentSession is! LinuxSession ||
        currentSession.ipcPath == null ||
        currentSession.danmakuAssets == null ||
        _displayDanmakuList.isEmpty) {
      return;
    }

    // 保留当前样式和时间戳, 以便在异步任务中检查状态是否已过期
    final style     = danmakuStyle.copyWith();
    final timestamp = _stateTimestamp;

    Future<void> fun(_) async {

      // 如果在队列等待期间状态发生变化, 则跳过当前任务
      if (_configurationHasChanged(timestamp)) return;

      // 参数检查
      final assets = currentSession.danmakuAssets;
      if (assets == null) return;
      final assPath  = assets.assPath;
      final luaPath  = assets.luaPath;

      // 将当前弹幕样式应用到 ASS 导出设置
      final outlineStyle = assets.assSettings.outlineStyle == AssOutlineStyle.none
        ? AssOutlineStyle.stroke
        : assets.assSettings.outlineStyle;
      final AssExportSettings settings =  assets.assSettings.copyWith(
        fontSize: style.danmakuFontSize,
        opacity: style.opacity,
        timeOffsetSeconds: style.danmakuOffset,
        outlineStyle: style.outlineEnabled ? outlineStyle : AssOutlineStyle.none,
        outlineWidth: style.outlineWidth,
      );

      File? temporaryFile; // 临时文件, 用于在写入 ASS 文件时避免覆盖原文件
      try {

        // 生成 ASS 内容
        final assStr = await generateExternalPlayerDanmakuAss(
          _displayDanmakuList
              .where((item) => !item.isBlocked)
              .map((item) => item.item)
              .toList(growable: false),
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

    // 将任务加入队列
    _danmakuStyleUpdateQueue = _danmakuStyleUpdateQueue.then(fun);
  }

  /// 添加一条弹幕屏蔽规则.
  static bool addBlockedItem(String input, BlockedItemType type) {
    final value = input.trim();
    if (value.isEmpty) return false;
    if (type == BlockedItemType.regex) {
      try {
        RegExp(value, caseSensitive: false);
      } on FormatException {
        return false;
      }
    }
    if (_blockedItems.any(
      (item) => item.type == type &&
          item.value.toLowerCase() == value.toLowerCase(),
    )) {
      return false;
    }
    _blockedItems = List<BlockedDanmakuItem>.unmodifiable([
      ..._blockedItems,
      BlockedDanmakuItem(value: value, type: type),
    ]);
    queueDanmakuRefresh();
    return true;
  }

  /// 移除一条弹幕屏蔽规则.
  static void removeBlockedItem(BlockedDanmakuItem blockedItem) {
    final items = _blockedItems
        .where((item) => !identical(item, blockedItem))
        .toList(growable: false);
    if (items.length == _blockedItems.length) return;
    _blockedItems = List<BlockedDanmakuItem>.unmodifiable(items);
    queueDanmakuRefresh();
  }


  // ======================================================================== //
  // ============================== 私有方法 ================================ //
  // ======================================================================== //

  /// 标记配置已发生变化, 更新时间戳并打印调试信息
  static void _markConfigurationChanged(String reason) {
    final now = DateTime.now().microsecondsSinceEpoch;
    _stateTimestamp = now > _stateTimestamp ? now : _stateTimestamp + 1; // 确保时间戳单调递增
    debugPrint('[ExternalPlayerConsoleService] Configuration changed: $reason, timestamp=$_stateTimestamp');
  }

  /// 检查当前状态是否与给定时间戳不一致, 用于异步任务过期检查
  static bool _configurationHasChanged(int timestamp) {
    return _stateTimestamp != timestamp;
  }

  /// 处理会话状态变化的回调
  static void _handleSessionChanged() {

    final current = _session;

    // 如果当前会话已关闭, 则清空会话和媒体信息, 并通知监听器更新 UI
    if (current != null && current.isClosed) {

      current.removeListener(_handleSessionChanged);
      _session = null;
      _animeTitle = null;
      _episodeTitle = null;
      _episodeId = null;
      _displayDanmakuList = const [];
      _blockedItems = const [];

      _markConfigurationChanged('clearSession');
      _instance.notifyListeners();
      return;
    }

    // 如果会话仍然存在, 则更新用于显示的弹幕列表并通知监听器更新 UI
    _updateDisplayDanmakuList();
    _instance.notifyListeners();
  }

  /// 更新用于显示的弹幕列表
  static void _updateDisplayDanmakuList() {

    final sourceItems = _displayDanmakuList
      .map((item) => item.item)
      .toList(growable: false);

    final position = _session?.position; // 当前播放位置, 用于判断弹幕是否处于显示状态
    final currentSession = _session;
    final configuredScrollSeconds = currentSession is LinuxSession
      ? currentSession.danmakuAssets?.assSettings.scrollDurationSeconds ?? 10.0
      : 10.0;
    final scrollDuration = configuredScrollSeconds.isFinite && configuredScrollSeconds > 0
      ? Duration(microseconds: (configuredScrollSeconds * Duration.microsecondsPerSecond).round())
      : const Duration(seconds: 10);

    DisplayDanmakuItem function(entry) {

      // 解构索引和弹幕项
      final (index, item) = entry;

      // 计算弹幕的实际显示时间, 考虑了时间偏移
      final displayTime = item.time + Duration(microseconds:(_danmakuStyle.danmakuOffset * Duration.microsecondsPerSecond).round());

      // 设置弹幕的显示持续时间, 滚动弹幕和固定弹幕使用不同的默认值
      final duration = item.mode.isScrolling ? scrollDuration : const Duration(seconds: 5);

      // 判断弹幕是否被屏蔽
      bool isBlocked = false;
      // 根据屏蔽项目类型进行匹配
      final content = item.content.toLowerCase();
      for (final b in _blockedItems) {
        final blockedValue = b.value.toLowerCase();
        switch (b.type)
        {
        case BlockedItemType.keyword : if (content.contains(blockedValue)                              ) isBlocked = true; break;
        case BlockedItemType.regex   : if (RegExp(b.value,caseSensitive: false).hasMatch(item.content) ) isBlocked = true; break;
        case BlockedItemType.userId  : if (item.senderId?.toLowerCase() == blockedValue                ) isBlocked = true; break;
        }
      }

      // 判断弹幕是否在当前播放位置显示
      final isInRange = position != null && position >= displayTime && position < displayTime + duration;
      final isActive = !isBlocked && isInRange;

      // 创建用于显示的弹幕数据项
      return DisplayDanmakuItem(
        item      : item,
        index     : index,
        startTime : displayTime,
        duration  : duration,
        isBlocked : isBlocked,
        isActive  : isActive,
      );
    }

    _displayDanmakuList = List<DisplayDanmakuItem>.unmodifiable(sourceItems.indexed.map(function));
  }

}
