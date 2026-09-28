import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'subtitle_parser.dart';
import 'storage_service.dart';
import '../../player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/services/emby_track_application.dart' as emby_tracks;
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/utils/subtitle_language_utils.dart';

/// 字幕管理器类，负责处理与字幕相关的所有功能
class SubtitleManager extends ChangeNotifier {
  static const Duration _mdkSubtitleRetryInterval = Duration(
    milliseconds: 80,
  );
  static const int _mdkVisibilityRetryAttempts = 6;
  static const int _mdkTrackActivationRetryAttempts = 10;
  static const Duration _autoLoadPlayerReadyDelay = Duration(
    milliseconds: 500,
  );
  static const Duration _autoLoadStateSettleDelay = Duration(
    milliseconds: 300,
  );
  static const int _subtitlePreviewMaxChars = 80;
  static const bool _erikaSubtitleTraceEnabled =
      bool.fromEnvironment('NIPAPLAY_ERIKA_SUBTITLE_TRACE');

  Player _player;
  String? _currentVideoPath;
  String? _currentExternalSubtitlePath;
  final Map<String, Map<String, dynamic>> _subtitleTrackInfo = {};
  final Map<String, List<dynamic>> _subtitleCache = {};

  /// 缓存指纹：path -> "size:mtime"，用于检测字幕文件内容变化
  final Map<String, String> _subtitleCacheFingerprint = {};
  int _subtitleLoadToken = 0;
  Future<void> _pendingExternalSubtitleLoad = Future<void>.value();

  // 视频-字幕路径映射的持久化存储键
  static const String _videoSubtitleMapKey = 'video_subtitle_map';

  // 外部字幕自动加载回调
  Function(String path, String fileName)? onExternalSubtitleAutoLoaded;
  void Function(String message)? onUserNotification;

  // 构造函数
  SubtitleManager({required Player player}) : _player = player;

  // 更新播放器实例
  void updatePlayer(Player newPlayer) {
    _player = newPlayer;
    debugPrint('SubtitleManager: 播放器实例已更新');
  }

  // Getters
  Map<String, Map<String, dynamic>> get subtitleTrackInfo => _subtitleTrackInfo;
  String? get currentExternalSubtitlePath => _currentExternalSubtitlePath;

  // 设置播放器实例
  void setPlayer(Player player) {
    _player = player;
  }

  // 设置当前视频路径
  void setCurrentVideoPath(String? path) {
    if (_currentVideoPath != path) ++_subtitleLoadToken;
    _currentVideoPath = path;
  }

  // 更新字幕轨道信息
  void updateSubtitleTrackInfo(String key, Map<String, dynamic> info) {
    _subtitleTrackInfo[key] = info;
    notifyListeners();
  }

  // 清除字幕轨道信息
  void clearSubtitleTrackInfo() {
    _subtitleTrackInfo.clear();
    notifyListeners();
  }

  /// 所有活跃的外部字幕路径（支持多挂 SRT 叠层渲染）
  final List<String> _activeExternalSubtitlePaths = [];

  /// 用户最后一次手动选中的内嵌字幕轨索引（媒体轨道列表里的下标）。
  /// 移除外挂内核轨字幕（ASS/SSA 占 sid）后用它回退内嵌轨，
  /// 否则 sid=no 之后滑块/样式全部打到空轨道（BUG-A）。
  int _lastSelectedEmbeddedTrackIndex = 0;

  /// 获取全部活跃的外部字幕路径（多挂时叠加渲染）
  List<String> getAllActiveExternalSubtitlePaths() =>
      List.unmodifiable(_activeExternalSubtitlePaths);

  // ---- 每条字幕独立的显示状态（时轴延迟/垂直位置/水平边距） ----

  /// 路径 → 用户可读的显示名（挂载/自动加载时登记；缓存文件名是哈希，
  /// 界面展示必须用登记的原名）
  final Map<String, String> _pathDisplayNames = <String, String>{};

  void registerPathDisplayName(String path, String name) {
    final trimmed = name.trim();
    if (path.isEmpty || trimmed.isEmpty) return;
    _pathDisplayNames[path] = trimmed;
  }

  String displayNameForPath(String path) =>
      _pathDisplayNames[path] ?? p.basename(path);

  // 多字幕混挂（ASS+SRT/SRT+SRT）时逐条渲染，各条可独立调轴与摆位。
  // 状态按字幕文件记忆（跨视频生效：同一字幕文件的时轴/摆位不变），
  // 持久化在独立键 subtitle_display_<sha1(path)>，随激活写入/移除清理。
  final Map<String, Map<String, double>> _pathDisplayState =
      <String, Map<String, double>>{};

  static String _pathDisplayStateKey(String path) =>
      'subtitle_display_${sha1.convert(utf8.encode(path)).toString()}';

  // 全局字幕位置/边距的当前值（由 VideoPlayerState 桥接层在滑块变化时
  // 更新）：新激活的字幕块以此为初始位置，保证滑块对叠层立即生效。
  double globalPositionSeed = 90.0;
  double globalMarginSeed = 0.0;

  /// 新字幕块的默认显示状态（当前全局种子位置；延迟从 0 开始）。
  /// staggerDepth>0 时按叠加深度上移 20（90/70/50），避免完全重叠。
  Map<String, double> _defaultDisplayState({int staggerDepth = 0}) =>
      <String, double>{
        'delay': 0.0,
        'position': (globalPositionSeed - 20 * staggerDepth).clamp(30.0, 100.0),
        'marginX': globalMarginSeed,
      };

  Map<String, double> _ensurePathDisplayState(String path) {
    return _pathDisplayState.putIfAbsent(path, _defaultDisplayState);
  }

  /// 全局滑块变化时同步所有已激活字幕块（滑块=全局控制；
  /// 单块拖动=逐条微调，直至下次全局调整）。
  void applyGlobalDisplayPosition(double position, double marginX) {
    if (_activeExternalSubtitlePaths.isEmpty) return;
    for (final path in _activeExternalSubtitlePaths) {
      final state = _ensurePathDisplayState(path);
      state['position'] = position;
      state['marginX'] = marginX;
      unawaited(_savePathDisplayState(path));
    }
    notifyListeners();
  }

  /// 异步恢复某条字幕的显示状态（激活后调用；磁盘值优先于默认值）
  Future<void> _loadPathDisplayState(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_activeExternalSubtitlePaths.contains(path)) return;
      final raw = prefs.getString(_pathDisplayStateKey(path));
      if (raw == null || raw.isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final state = _ensurePathDisplayState(path);
      final delay = (decoded['delay'] as num?)?.toDouble();
      final position = (decoded['position'] as num?)?.toDouble();
      final marginX = (decoded['marginX'] as num?)?.toDouble();
      if (delay != null) state['delay'] = delay;
      if (position != null) state['position'] = position;
      if (marginX != null) state['marginX'] = marginX;
      notifyListeners();
    } catch (e) {
      debugPrint('SubtitleManager: 恢复字幕显示状态失败: $e');
    }
  }

  Future<void> _savePathDisplayState(String path) async {
    try {
      final state = _ensurePathDisplayState(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pathDisplayStateKey(path),
        json.encode(state),
      );
    } catch (e) {
      debugPrint('SubtitleManager: 保存字幕显示状态失败: $e');
    }
  }

  /// 某条字幕的时轴延迟（秒；正值延后，负值提前）
  double pathDelaySeconds(String path) =>
      _ensurePathDisplayState(path)['delay'] ?? 0.0;

  void setPathDelaySeconds(String path, double seconds) {
    final state = _ensurePathDisplayState(path);
    if ((state['delay']! - seconds).abs() < 0.0001) return;
    state['delay'] = seconds;
    unawaited(_savePathDisplayState(path));
    notifyListeners();
  }

  /// 某条字幕的垂直位置（0=屏幕顶 100=屏幕底）
  double pathPosition(String path) =>
      _ensurePathDisplayState(path)['position'] ?? 90.0;

  void setPathPosition(String path, double position) {
    final state = _ensurePathDisplayState(path);
    state['position'] = position;
    unawaited(_savePathDisplayState(path));
    // 内核轨字幕（libmpv ASS/SSA）：位置同步 mpv sub-pos（libass 渲染）
    if (!_shouldRenderExternalSubtitleInApp(path)) {
      try {
        _player.setProperty(
            'sub-pos', position.round().clamp(0, 100).toString());
      } catch (e) {
        debugPrint('SubtitleManager: 内核字幕位置同步失败: $e');
      }
    }
    notifyListeners();
  }

  /// 某条字幕的水平边距（逻辑像素）
  double pathMarginX(String path) =>
      _ensurePathDisplayState(path)['marginX'] ?? 0.0;

  void setPathMarginX(String path, double marginX) {
    final state = _ensurePathDisplayState(path);
    state['marginX'] = marginX;
    unawaited(_savePathDisplayState(path));
    notifyListeners();
  }

  /// 查询单条字幕在指定时间点的文本（多字幕分块渲染使用）
  String pathSubtitleTextAt(String path, int positionMs) {
    if (!_shouldRenderExternalSubtitleInApp(path)) return '';
    return _textAtPath(path, positionMs);
  }

  // 获取当前活跃的外部字幕文件路径
  String? getActiveExternalSubtitlePath() {
    // 检查是否是外部字幕
    final externalInfo = _subtitleTrackInfo['external_subtitle'];
    if (externalInfo is Map<String, dynamic> &&
        externalInfo['isActive'] == true) {
      final path = externalInfo['path'];
      if (path is String && path.isNotEmpty) {
        return path;
      }
    }

    // 回退：使用当前记录的外部字幕路径
    if (_currentExternalSubtitlePath != null &&
        _currentExternalSubtitlePath!.isNotEmpty) {
      return _currentExternalSubtitlePath;
    }

    return null;
  }

  // 获取已缓存的字幕内容
  List<dynamic>? getCachedSubtitle(String path) {
    return _subtitleCache[path];
  }

  // 保存视频与字幕路径的映射
  Future<void> saveVideoSubtitleMapping(
    String videoPath,
    String subtitlePath,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = prefs.getString(_videoSubtitleMapKey) ?? '{}';
      final Map<String, dynamic> mappingMap = Map<String, dynamic>.from(
        json.decode(mappingJson),
      );
      mappingMap[videoPath] = subtitlePath;
      await prefs.setString(_videoSubtitleMapKey, json.encode(mappingMap));
      debugPrint(
        'SubtitleManager: 保存视频字幕映射 - 视频: $videoPath, 字幕: $subtitlePath',
      );
    } catch (e) {
      debugPrint('SubtitleManager: 保存视频字幕映射失败: $e');
    }
  }

  // 获取视频对应的字幕路径
  Future<String?> getVideoSubtitlePath(String videoPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = prefs.getString(_videoSubtitleMapKey) ?? '{}';
      final Map<String, dynamic> mappingMap = Map<String, dynamic>.from(
        json.decode(mappingJson),
      );
      final subtitlePath = mappingMap[videoPath] as String?;
      debugPrint(
        'SubtitleManager: 获取视频对应的字幕路径 - 视频: $videoPath, 字幕: $subtitlePath',
      );

      // 检查字幕文件是否仍然存在
      if (subtitlePath != null && subtitlePath.isNotEmpty) {
        final subtitleFile = File(subtitlePath);
        if (!subtitleFile.existsSync()) {
          debugPrint('SubtitleManager: 记录的字幕文件不存在: $subtitlePath');
          return null;
        }
      }

      return subtitlePath;
    } catch (e) {
      debugPrint('SubtitleManager: 获取视频字幕映射失败: $e');
      return null;
    }
  }

  // 获取当前显示的字幕文本
  String getCurrentSubtitleText() {
    try {
      // 检查是否是外部字幕（外部字幕在 media_kit 内核下可能不会体现在 activeSubtitleTracks 中）
      String? externalSubtitlePath = getActiveExternalSubtitlePath();

      // 输出详细调试信息
      debugPrint(
        'SubtitleManager: getCurrentSubtitleText - 外部字幕路径: $externalSubtitlePath',
      );
      debugPrint(
        'SubtitleManager: getCurrentSubtitleText - 激活轨道: ${_player.activeSubtitleTracks}',
      );

      // 如果是外部字幕
      if (externalSubtitlePath != null && externalSubtitlePath.isNotEmpty) {
        final fileName = p.basename(externalSubtitlePath);
        return "正在使用外部字幕文件 - $fileName";
      }

      // 如果没有外部字幕且没有激活的字幕轨道
      if (_player.activeSubtitleTracks.isEmpty) {
        debugPrint('SubtitleManager: getCurrentSubtitleText - 没有激活的字幕轨道');
        return '';
      }

      // 如果是内嵌字幕
      final activeTrack = _player.activeSubtitleTracks.first;
      return "正在播放内嵌字幕轨道 $activeTrack";
    } catch (e) {
      debugPrint('SubtitleManager: 获取当前字幕内容失败: $e');
      return '';
    }
  }

  // 异步预加载字幕文件
  Future<void> preloadSubtitleFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      // 缓存指纹：文件大小+修改时间，字幕文件变化后强制重新解析
      final stat = await file.stat();
      final fingerprint =
          '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
      if (_subtitleCache.containsKey(path)) {
        if (_subtitleCacheFingerprint[path] == fingerprint) {
          return;
        }
        _subtitleCache.remove(path);
        debugPrint('SubtitleManager: 字幕文件已变化($path)，强制重新解析');
      }
      {
        // 仅对文本字幕进行预解析，图像字幕(.sup)与 VobSub 二进制(.sub 头部
        // 为 MPEG-PS)直接交给播放器，不做文本级解析
        final extension = p.extension(path).toLowerCase();
        if (extension == '.ass' || extension == '.srt' || extension == '.ssa') {
          final result = await SubtitleParser.parseSubtitleFile(
            path,
            allowUnknownFormat: true,
          );
          _subtitleCache[path] = result.entries;
          _subtitleCacheFingerprint[path] = fingerprint;
          notifyListeners();
        } else if (extension == '.sup' || extension == '.idx') {
          debugPrint('SubtitleManager: 检测到sup字幕，跳过文本解析');
        } else if (extension == '.sub') {
          // .sub 可能是 VobSub 二进制或 MicroDVD 文本：只读前 4 字节嗅探
          // MPEG-PS 头，避免把 12MB 位图流整段读进 Dart 堆（恢复/切换
          // 字幕时会重复调用，全量读取会让内存翻倍）。二进制结果也写入
          // 缓存指纹，防止重复嗅探。
          final raf = await file.open();
          try {
            final header = await raf.read(4);
            if (SubtitleParser.hasMpegPsPackHeader(header)) {
              _subtitleCache[path] = const [];
              _subtitleCacheFingerprint[path] = fingerprint;
              debugPrint('SubtitleManager: 检测到VobSub二进制字幕，跳过文本解析');
              return;
            }
          } finally {
            await raf.close();
          }
          final result = await SubtitleParser.parseSubtitleFile(
            path,
            allowUnknownFormat: true,
          );
          _subtitleCache[path] = result.entries;
          _subtitleCacheFingerprint[path] = fingerprint;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('预加载字幕文件失败: $e');
    }
  }

  // 当字幕轨道改变时调用
  void onSubtitleTrackChanged() {
    final subtitlePath = getActiveExternalSubtitlePath();
    if (subtitlePath != null) {
      preloadSubtitleFile(subtitlePath);
    }
  }

  // 设置当前外部字幕路径
  void setCurrentExternalSubtitlePath(String? path) {
    _currentExternalSubtitlePath = path;
    debugPrint('SubtitleManager: 设置当前外部字幕路径: $path');
  }

  String _getVideoHashKey(String videoPath) {
    final file = File(videoPath);
    if (file.existsSync()) {
      final size = file.lengthSync();
      final name = p.basename(videoPath);
      return '$name-$size';
    }
    return sha1.convert(utf8.encode(videoPath)).toString();
  }

  Future<void> _subtitlePersistence = Future<void>.value();

  Future<void> _persistExternalSubtitleSelection({
    required String videoPath,
    required String subtitlePath,
    required bool isActive,
    String? displayName,
    bool registerOnly = false,
  }) {
    final activePaths = Set<String>.from(_activeExternalSubtitlePaths);
    final primaryPath = _currentExternalSubtitlePath;
    return _subtitlePersistence = _subtitlePersistence.then((_) =>
        _writeExternalSubtitleSelection(
            videoPath: videoPath,
            subtitlePath: subtitlePath,
            isActive: isActive,
            displayName: displayName,
            registerOnly: registerOnly,
            activePaths: activePaths,
            primaryPath: primaryPath));
  }

  Future<void> _writeExternalSubtitleSelection({
    required String videoPath,
    required String subtitlePath,
    required bool isActive,
    required bool registerOnly,
    required Set<String> activePaths,
    required String? primaryPath,
    String? displayName,
  }) async {
    try {
      if (subtitlePath.isEmpty) return;
      if (!File(subtitlePath).existsSync()) return;

      final prefs = await SharedPreferences.getInstance();
      final videoHashKey = _getVideoHashKey(videoPath);
      final subtitlesKey = 'external_subtitles_$videoHashKey';

      final existingJson = prefs.getString(subtitlesKey);
      final List<Map<String, dynamic>> subtitles = [];
      if (existingJson != null && existingJson.isNotEmpty) {
        try {
          final decoded = json.decode(existingJson);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                subtitles.add(Map<String, dynamic>.from(item));
              }
            }
          }
        } catch (_) {
          // 忽略解析错误，回退为空列表
        }
      }

      final existingIndex =
          subtitles.indexWhere((s) => s['path'] == subtitlePath);
      final existing = existingIndex < 0
          ? <String, dynamic>{}
          : subtitles.removeAt(existingIndex);

      // 旧版本持久化过的条目可能存的是哈希文件名（远程缓存路径），
      // 用下载时登记的持久化注册表修正显示名（不依赖本次会话内存注册，
      // iOS/Windows 冷启动首次读取也能归正）。
      for (final s in subtitles) {
        final entryPath = s['path']?.toString() ?? '';
        if (entryPath.isEmpty) continue;
        final entryName = s['name']?.toString() ?? '';
        final isHashNamed = entryName.isEmpty ||
            (entryName == p.basename(entryPath) &&
                entryPath.contains('remote_subtitles'));
        if (!isHashNamed) continue;
        final registered = _pathDisplayNames[entryPath] ??
            await RemoteSubtitleService.instance.lookupDisplayName(entryPath);
        if (registered != null && registered.isNotEmpty) {
          s['name'] = registered;
        }
      }

      final entry = <String, dynamic>{
        ...existing,
        'path': subtitlePath,
        'name': displayName ?? existing['name'] ?? p.basename(subtitlePath),
        'type': p.extension(subtitlePath).toLowerCase().replaceFirst('.', ''),
        'addTime': existing['addTime'] ?? DateTime.now().millisecondsSinceEpoch,
        'isActive': registerOnly ? (existing['isActive'] ?? false) : isActive,
      };
      // Keep indices stable: menus may already be displaying this list.
      if (existingIndex < 0) {
        subtitles.add(entry);
      } else {
        subtitles.insert(existingIndex, entry);
      }
      if (!registerOnly) {
        for (final item in subtitles) {
          item['isActive'] = activePaths.contains(item['path']);
        }
      }
      await prefs.setString(subtitlesKey, json.encode(subtitles));
      final lastActiveKey = 'last_active_subtitle_$videoHashKey';
      var activeIndex = subtitles
          .indexWhere((s) => s['path'] == primaryPath && s['isActive'] == true);
      if (activeIndex < 0)
        activeIndex = subtitles.indexWhere((s) => s['isActive'] == true);
      if (activeIndex >= 0) {
        await prefs.setInt(lastActiveKey, activeIndex);
      } else {
        await prefs.remove(lastActiveKey);
      }
      // 此处直写 prefs 绕过了 SubtitleService 的内存缓存（Cupertino 面板
      // 经缓存读取），失效它避免面板看到陈旧列表、按索引删错条目。
      SubtitleService().clearCache(videoPath);
    } catch (e) {
      debugPrint('SubtitleManager: 持久化外部字幕选择失败: $e');
    }
  }

  /// 读取持久化 external_subtitles 列表中某条字幕的显示名。
  /// 远程缓存落盘文件名是哈希，界面展示必须用当初登记的原文件名。
  Future<String?> _lookupPersistedDisplayName({
    required String videoPath,
    required String subtitlePath,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final videoHashKey = _getVideoHashKey(videoPath);
      final raw = prefs.getString('external_subtitles_$videoHashKey');
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map && item['path'] == subtitlePath) {
              final name = item['name']?.toString();
              if (name != null && name.isNotEmpty) return name;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('SubtitleManager: 读取字幕显示名失败: $e');
    }
    // external_subtitles 里没有（或仍是哈希名）：查远程字幕下载时登记的
    // 持久化注册表（跨进程/跨平台可用，不依赖本次会话的内存注册）。
    try {
      final registered =
          await RemoteSubtitleService.instance.lookupDisplayName(subtitlePath);
      if (registered != null) return registered;
    } catch (_) {}
    return null;
  }

  // 清空外部字幕状态，同时通知播放器关闭外挂轨道
  void _clearExternalSubtitleState({
    bool resetManualFlag = true,
    bool clearPlayer = true,
  }) {
    ++_subtitleLoadToken;
    if (clearPlayer) {
      try {
        if (_player.supportsExternalSubtitles) {
          _player.setMedia("", MediaType.subtitle);
        }
      } catch (e) {
        debugPrint('SubtitleManager: 清除播放器外部字幕失败: $e');
      }

      try {
        if (_player.activeSubtitleTracks.isNotEmpty) {
          _player.activeSubtitleTracks = [];
        }
      } catch (e) {
        debugPrint('SubtitleManager: 重置字幕轨道选择失败: $e');
      }
    }

    _currentExternalSubtitlePath = null;
    // 多挂 SRT/VTT 路径列表也要清——否则切到无外挂字幕的视频时
    // ExternalSubtitleOverlay 仍按旧路径渲染（"外挂轨道还在"）。
    _activeExternalSubtitlePaths.clear();
    _pathDisplayState.clear();

    final existing = _subtitleTrackInfo['external_subtitle'];
    if (existing is Map<String, dynamic>) {
      final updated = Map<String, dynamic>.from(existing);
      updated['isActive'] = false;
      updated['path'] = null;
      if (resetManualFlag) {
        updated['isManualSet'] = false;
      }
      _subtitleTrackInfo['external_subtitle'] = updated;
    }
  }

  /// 对外暴露的清理接口，供播放器切集或重置时调用
  void clearExternalSubtitle({bool notifyListenersToo = true}) {
    _clearExternalSubtitleState();
    if (notifyListenersToo) {
      onSubtitleTrackChanged();
      notifyListeners();
    }
    debugPrint('SubtitleManager: 外部字幕状态已重置');
  }

  // 设置外部字幕并更新路径
  void setExternalSubtitle(String path,
      {bool isManualSetting = false,
      String? displayName,
      bool preserveStack = false}) {
    if (path.isNotEmpty && !isVobSubPairComplete(path)) {
      onUserNotification?.call('VobSub 字幕需要同名 .sub 与 .idx 文件');
      return;
    }
    path = canonicalSubtitlePath(path);
    if (path.isNotEmpty && displayName != null) {
      registerPathDisplayName(path, displayName);
    }
    try {
      final loadToken = ++_subtitleLoadToken;
      final previousSubtitleTrackSignatures =
          _isMdkKernel() ? _snapshotCurrentSubtitleTrackSignatures() : null;
      // NEW: Check if player supports external subtitles.
      // SRT/VTT 走 App 内叠层渲染（与内核无关），不受此限制；仅占内核字幕轨的
      // ASS/SSA 等才需要内核支持外挂字幕。
      if (!_player.supportsExternalSubtitles &&
          path.isNotEmpty &&
          !_shouldRenderExternalSubtitleInApp(path)) {
        debugPrint('SubtitleManager: 当前播放器内核不支持加载外部字幕');
        onUserNotification?.call('当前播放器内核不支持加载外部字幕');
        return;
      }

      debugPrint('SubtitleManager: 设置外部字幕: $path, 手动设置: $isManualSetting');
      _erikaSubtitleTrace(
        'setExternalSubtitle token=$loadToken kernel=${_player.getPlayerKernelName()} '
        'path=${_describeSubtitlePath(path)} manual=$isManualSetting '
        'supportsExternal=${_player.supportsExternalSubtitles}',
      );

      // 如果字幕文件存在
      if (path.isNotEmpty && File(path).existsSync()) {
        final shouldRenderInApp = _shouldRenderExternalSubtitleInApp(path);
        final shouldFixEncoding = _shouldFixExternalSubtitleEncoding();
        _currentExternalSubtitlePath = path;
        if (shouldRenderInApp) {
          _activateAppRenderedExternalSubtitle(path);
        } else if (!shouldFixEncoding) {
          // 设置外部字幕文件
          _loadExternalSubtitleIntoPlayer(
            path,
            loadToken,
            previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
          );
        } else {
          // 对 MDK / Media Kit 预处理字幕编码，避免 UTF-16 直接喂给内核导致崩溃
          unawaited(
            _pendingExternalSubtitleLoad = _loadExternalSubtitleWithEncodingFix(
              path,
              loadToken,
              previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
            ),
          );
        }

        // 字体预取后的 ASS 重载不应丢掉已叠加的 SRT/VTT。
        if (!preserveStack) _activeExternalSubtitlePaths.clear();
        if (!shouldRenderInApp) {
          _activeExternalSubtitlePaths.removeWhere((other) =>
              other != path && !_shouldRenderExternalSubtitleInApp(other));
        }
        if (!_activeExternalSubtitlePaths.contains(path)) {
          _activeExternalSubtitlePaths.add(path);
        }
        unawaited(_loadPathDisplayState(path));

        // 更新轨道信息（title 用登记的显示名；远程缓存文件名是哈希）
        updateSubtitleTrackInfo('external_subtitle', {
          'path': path,
          'title': displayNameForPath(path),
          'isActive': true,
          'isManualSet': isManualSetting, // 添加是否手动设置的标记
        });

        // 预加载字幕文件
        preloadSubtitleFile(path);

        // 如果是手动设置的或者是视频首次使用外部字幕，保存映射关系
        if (isManualSetting && _currentVideoPath != null) {
          saveVideoSubtitleMapping(_currentVideoPath!, path);
        }

        if (_currentVideoPath != null && _currentVideoPath!.isNotEmpty) {
          unawaited(
            _persistExternalSubtitleSelection(
              videoPath: _currentVideoPath!,
              subtitlePath: path,
              displayName: displayName ?? displayNameForPath(path),
              isActive: true,
            ),
          );
        }

        debugPrint('SubtitleManager: 外部字幕设置成功');
      } else if (path.isEmpty) {
        _activeExternalSubtitlePaths.clear();
        _pathDisplayState.clear();
        _clearExternalSubtitleState();
        debugPrint('SubtitleManager: 外部字幕已清除');
      } else {
        debugPrint('SubtitleManager: 字幕文件不存在: $path');
      }

      // 通知字幕轨道变化
      onSubtitleTrackChanged();
      notifyListeners();
    } catch (e) {
      debugPrint('设置外部字幕失败: $e');
    }
  }

  /// 取消挂载一条外部字幕（从叠层/堆栈移除 + 清内核轨）
  Future<void> removeExternalSubtitleFromStack(String path) async {
    if (path.isEmpty) return;
    path = canonicalSubtitlePath(path);
    if (!_shouldRenderExternalSubtitleInApp(path)) ++_subtitleLoadToken;
    _activeExternalSubtitlePaths.remove(path);
    _pathDisplayState.remove(path);
    if (_currentExternalSubtitlePath == path) {
      _currentExternalSubtitlePath = _activeExternalSubtitlePaths.isEmpty
          ? null
          : _activeExternalSubtitlePaths.last;
    }
    // 只有非叠层（占内核轨的 ASS/SSA）才清内核轨；叠层 SRT 移除不动内嵌轨
    if (!_shouldRenderExternalSubtitleInApp(path)) {
      try {
        if (_player.activeSubtitleTracks.isNotEmpty) {
          _player.activeSubtitleTracks = [];
        }
        // activeSubtitleTracks 只管内嵌轨索引，外挂 ASS 轨（setSubtitleTrack(uri)
        // 挂的 mpv sid）必须显式 sid=no 才能真正关闭，否则取消后字幕仍显示。
        _player.setProperty('sid', 'no');
        // BUG-A：外挂（占 sid 的 ASS/SSA）移除后必须回退内嵌轨——
        // 之前 sid=no 就结束，只剩内嵌时位置滑块/延迟全打在空轨道上，
        // 用户感知为「移除外挂后滑块拖不动内嵌」。
        final stillKernelExternal = _activeExternalSubtitlePaths
            .any((p) => !_shouldRenderExternalSubtitleInApp(p));
        final embeddedTracks = _player.mediaInfo.subtitle;
        if (!stillKernelExternal &&
            embeddedTracks != null &&
            embeddedTracks.isNotEmpty) {
          final restore = _lastSelectedEmbeddedTrackIndex.clamp(
              0, embeddedTracks.length - 1);
          try {
            _player.activeSubtitleTracks = [restore];
            debugPrint('SubtitleManager: 移除外挂后回退内嵌轨 index=$restore');
          } catch (e) {
            debugPrint('SubtitleManager: 回退内嵌轨失败: $e');
          }
        }
      } catch (e) {
        debugPrint('SubtitleManager: 清除字幕轨失败: $e');
      }
    }
    final primary = _currentExternalSubtitlePath;
    updateSubtitleTrackInfo('external_subtitle', <String, dynamic>{
      'path': primary,
      'title': primary == null ? '' : displayNameForPath(primary),
      'isActive': primary != null,
      'isManualSet': true,
    });
    if (_currentVideoPath != null) {
      await _persistExternalSubtitleSelection(
          videoPath: _currentVideoPath!, subtitlePath: path, isActive: false);
    }
    onSubtitleTrackChanged();
    notifyListeners();
  }

  /// Add a choice to the menu without changing playback or the saved primary.
  Future<void> registerExternalSubtitleCandidate(String path,
      {String? displayName}) async {
    final videoPath = _currentVideoPath;
    if (videoPath == null || path.isEmpty || !isVobSubPairComplete(path))
      return;
    path = canonicalSubtitlePath(path);
    if (displayName != null) registerPathDisplayName(path, displayName);
    await _persistExternalSubtitleSelection(
      videoPath: videoPath,
      subtitlePath: path,
      isActive: false,
      displayName: displayName ?? displayNameForPath(path),
      registerOnly: true,
    );
  }

  /// Explicit user activation: app-rendered tracks stack; native tracks replace
  /// the previous native track while retaining all app-rendered tracks.
  Future<void> addExternalSubtitleToStack(String path,
      {String? displayName}) async {
    if (path.isEmpty || !isVobSubPairComplete(path)) return;
    path = canonicalSubtitlePath(path);
    final loadToken = _subtitleLoadToken;
    if (!await File(path).exists() || loadToken != _subtitleLoadToken) return;
    if (_activeExternalSubtitlePaths.contains(path)) return;
    _pathDisplayState.putIfAbsent(
        path,
        () => _defaultDisplayState(
            staggerDepth: _activeExternalSubtitlePaths.length));
    if (_shouldRenderExternalSubtitleInApp(path)) {
      if (displayName != null) registerPathDisplayName(path, displayName);
      _activeExternalSubtitlePaths.add(path);
      unawaited(_loadPathDisplayState(path));
      _activateAppRenderedExternalSubtitle(path);
      if (!_activeExternalSubtitlePaths
          .contains(_currentExternalSubtitlePath)) {
        _currentExternalSubtitlePath = path;
      }
      final primary = _currentExternalSubtitlePath!;
      updateSubtitleTrackInfo('external_subtitle', {
        'path': primary,
        'title': displayNameForPath(primary),
        'isActive': true,
        'isManualSet': true,
      });
      if (_currentVideoPath != null) {
        await _persistExternalSubtitleSelection(
            videoPath: _currentVideoPath!,
            subtitlePath: path,
            isActive: true,
            displayName: displayName ?? displayNameForPath(path));
        await saveVideoSubtitleMapping(_currentVideoPath!, primary);
      }
      onSubtitleTrackChanged();
      notifyListeners();
    } else {
      setExternalSubtitle(path,
          isManualSetting: true, displayName: displayName, preserveStack: true);
      await _pendingExternalSubtitleLoad;
      await _subtitlePersistence;
    }
  }

  Future<void> activateEmbyExternalSubtitle(
    String path, {
    bool isManualSetting = false,
  }) async {
    // SRT/VTT（及 Windows ASS/SSA）走 App 内叠层渲染，与内核无关；
    // 统一复用主路径，避免 Erika 分支把 SRT 塞给原生内核导致播放异常
    if (_shouldRenderExternalSubtitleInApp(path)) {
      setExternalSubtitle(path, isManualSetting: isManualSetting);
      return;
    }
    if (_player.getPlayerKernelName() != 'Erika') {
      setExternalSubtitle(path, isManualSetting: isManualSetting);
      return;
    }

    final loadToken = ++_subtitleLoadToken;
    // SRT/VTT 走 App 内叠层渲染（与内核无关），不受内核外挂字幕能力限制
    if (!_player.supportsExternalSubtitles &&
        path.isNotEmpty &&
        !_shouldRenderExternalSubtitleInApp(path)) {
      throw StateError(
        'The current player does not support external subtitles.',
      );
    }
    if (path.isNotEmpty && !File(path).existsSync()) {
      throw FileSystemException('Subtitle file does not exist.', path);
    }

    await emby_tracks.activateEmbyExternalSubtitle(
      player: _player,
      subtitlePath: path,
    );
    if (loadToken != _subtitleLoadToken) return;

    if (path.isEmpty) {
      _clearExternalSubtitleState(clearPlayer: false);
    } else {
      _currentExternalSubtitlePath = path;
      updateSubtitleTrackInfo('external_subtitle', <String, dynamic>{
        'path': path,
        'title': displayNameForPath(path),
        'isActive': true,
        'isManualSet': isManualSetting,
      });
      unawaited(preloadSubtitleFile(path));
      if (isManualSetting && _currentVideoPath != null) {
        saveVideoSubtitleMapping(_currentVideoPath!, path);
      }
    }

    onSubtitleTrackChanged();
    notifyListeners();
  }

  bool _isMdkKernel() => _player.getPlayerKernelName() == 'MDK';
  bool _isMediaKitKernel() => _player.getPlayerKernelName() == 'Media Kit';
  bool _shouldFixExternalSubtitleEncoding() =>
      !kIsWeb && (_isMdkKernel() || _isMediaKitKernel());
  bool _shouldRenderExternalSubtitleInApp(String path) {
    if (kIsWeb) return false;

    final extension = p.extension(path).toLowerCase();
    // SRT/VTT 无特效，全平台 App 内叠层渲染（与内核无关）：
    // 不占内核字幕轨 -> 可与 mkv 内嵌轨共存、可热切换、可拖动
    if (extension == '.srt' || extension == '.vtt') return true;
    // ASS/SSA：libmpv(Media Kit) 内核走内核轨由 libass 渲染，保留特效样式
    // （滚动/卡拉OK/渐变等，adapter 已设 sub-ass-override=no）。
    // 其他内核（Erika 等）对外挂 ASS 支持差 -> 走 App 叠层纯文本保证可显示。
    if (extension == '.ass' || extension == '.ssa') {
      try {
        final kernel = _player.getPlayerKernelName();
        // libmpv(Media Kit)/MDK 内核走内核轨由 libass 渲染，保留特效样式；
        // Erika 等内核挂载不了外挂 ASS 轨 -> 走 App 叠层纯文本保证可显示。
        return kernel != 'Media Kit' && kernel != 'MDK';
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  void _activateAppRenderedExternalSubtitle(String path) {
    // 多字幕分块渲染：外挂字幕（SRT/ASS）走 Flutter 叠层，与内嵌轨共存，
    // 不再清内核字幕轨/选择——否则挂载外挂会顶掉用户选好的内嵌轨。
    unawaited(preloadSubtitleFile(path));
    debugPrint('SubtitleManager: 使用应用内叠层渲染外挂字幕: $path');
  }

  /// 该外挂字幕是否走 App 叠层渲染（false = 内核轨，如 libmpv 的 ASS/SSA）
  bool externalSubtitleRenderedInApp(String path) =>
      _shouldRenderExternalSubtitleInApp(path);

  bool shouldRenderCurrentExternalSubtitleInApp() {
    // 多字幕分块渲染：以激活路径集合为准——取消其中一条不能让
    // 其他仍在叠加的字幕块跟着消失（旧实现读单条当前路径）。
    if (_activeExternalSubtitlePaths.any(_shouldRenderExternalSubtitleInApp)) {
      return true;
    }
    // 旧单路径回退（集合为空时保持旧行为：无激活则隐藏）
    final path = getActiveExternalSubtitlePath();
    if (path == null || path.isEmpty) {
      return false;
    }

    return _shouldRenderExternalSubtitleInApp(path);
  }

  String getCurrentExternalSubtitleTextAt(int positionMs) {
    final single = getActiveExternalSubtitlePath();
    if (single == null || single.isEmpty) return '';
    final paths = _activeExternalSubtitlePaths.isNotEmpty
        ? _activeExternalSubtitlePaths
        : <String>[single];
    final merged = <String>[];
    for (final path in paths) {
      if (!_shouldRenderExternalSubtitleInApp(path)) continue;
      final text = _textAtPath(path, positionMs);
      if (text.isNotEmpty && !merged.contains(text)) merged.add(text);
    }
    return merged.join('\n');
  }

  String _textAtPath(String path, int positionMs) {
    if (!_shouldRenderExternalSubtitleInApp(path)) return '';

    final cachedEntries = _subtitleCache[path];
    if (cachedEntries == null || cachedEntries.isEmpty) {
      unawaited(preloadSubtitleFile(path));
      return '';
    }

    final activeContents = <String>[];
    for (final entry in cachedEntries) {
      if (entry is! SubtitleEntry) {
        continue;
      }
      if (positionMs < entry.startTimeMs || positionMs > entry.endTimeMs) {
        continue;
      }

      final content = entry.content.trim();
      if (content.isEmpty || activeContents.contains(content)) {
        continue;
      }
      activeContents.add(content);
    }

    return activeContents.join('\n');
  }

  List<String> _snapshotCurrentSubtitleTrackSignatures() {
    final tracks = _player.mediaInfo.subtitle;
    if (tracks == null || tracks.isEmpty) {
      return const [];
    }

    return tracks.map(_buildSubtitleTrackSignature).toList();
  }

  String _buildSubtitleTrackSignature(PlayerSubtitleStreamInfo track) {
    final raw = track.rawRepresentation.trim();
    if (raw.isNotEmpty) {
      return raw;
    }

    final title = track.title?.trim() ?? '';
    final language = track.language?.trim() ?? '';
    return '$title|$language';
  }

  void _loadExternalSubtitleIntoPlayer(
    String path,
    int loadToken, {
    List<String>? previousSubtitleTrackSignatures,
  }) {
    _erikaSubtitleTrace(
      'loadExternalSubtitleIntoPlayer token=$loadToken '
      'kernel=${_player.getPlayerKernelName()} path=${_describeSubtitlePath(path)}',
    );
    if (_isMdkKernel()) {
      try {
        _player.setProperty('subtitle', '1');
        _player.activeSubtitleTracks = [];
      } catch (e) {
        debugPrint('SubtitleManager: MDK 清理旧字幕轨失败: $e');
      }
    }

    _player.setMedia(path, MediaType.subtitle);
    // libmpv 内核轨：挂载后应用持久化的全局字幕位置（sub-pos），
    // 否则内核 ASS 用 mpv 默认位置，滑块设置的 0-100 不生效。
    if (_player.getPlayerKernelName() == 'Media Kit') {
      try {
        _player.setProperty(
            'sub-pos', globalPositionSeed.round().clamp(0, 100).toString());
      } catch (e) {
        debugPrint('SubtitleManager: 内核字幕初始位置应用失败: $e');
      }
    }
    _erikaSubtitleTrace(
      'loadExternalSubtitleIntoPlayer setMedia returned token=$loadToken '
      'active=${_player.activeSubtitleTracks} '
      'subtitle_count=${_player.mediaInfo.subtitle?.length ?? 0}',
    );

    if (_isMdkKernel()) {
      unawaited(
        _ensureMdkExternalSubtitleVisible(
          subtitlePath: path,
          loadToken: loadToken,
        ),
      );
      unawaited(
        _activateMdkExternalSubtitleTrack(
          subtitlePath: path,
          loadToken: loadToken,
          previousSubtitleTrackSignatures:
              previousSubtitleTrackSignatures ?? const [],
        ),
      );
    }
  }

  Future<void> _ensureMdkExternalSubtitleVisible({
    required String subtitlePath,
    required int loadToken,
  }) async {
    if (!_isMdkKernel()) return;

    for (var attempt = 0; attempt < _mdkVisibilityRetryAttempts; attempt++) {
      await Future.delayed(_mdkSubtitleRetryInterval);

      if (loadToken != _subtitleLoadToken) return;
      if (_currentExternalSubtitlePath != subtitlePath) return;

      try {
        _player.setProperty('subtitle', '1');
        _player.activeSubtitleTracks = [0];
        debugPrint(
          'SubtitleManager: MDK 已请求显示外挂字幕，attempt=$attempt active=${_player.activeSubtitleTracks}',
        );
      } catch (e) {
        debugPrint('SubtitleManager: MDK 请求显示外挂字幕失败: $e');
      }
    }
  }

  Future<void> _activateMdkExternalSubtitleTrack({
    required String subtitlePath,
    required int loadToken,
    required List<String> previousSubtitleTrackSignatures,
  }) async {
    if (!_isMdkKernel()) return;

    final subtitleName = p.basenameWithoutExtension(subtitlePath).toLowerCase();
    final previousTrackSet = previousSubtitleTrackSignatures.toSet();

    for (var attempt = 0;
        attempt < _mdkTrackActivationRetryAttempts;
        attempt++) {
      await Future.delayed(_mdkSubtitleRetryInterval);

      if (loadToken != _subtitleLoadToken) return;
      if (_currentExternalSubtitlePath != subtitlePath) return;

      final currentTracks = _player.mediaInfo.subtitle;
      if (currentTracks == null || currentTracks.isEmpty) {
        continue;
      }

      int? targetIndex;
      for (var i = 0; i < currentTracks.length; i++) {
        final signature = _buildSubtitleTrackSignature(currentTracks[i]);
        if (!previousTrackSet.contains(signature)) {
          targetIndex = i;
          break;
        }
      }

      if (targetIndex == null) {
        final matchedIndex = currentTracks.indexWhere((track) {
          final title = track.title?.toLowerCase() ?? '';
          final raw = track.rawRepresentation.toLowerCase();
          return title.contains(subtitleName) || raw.contains(subtitleName);
        });
        if (matchedIndex >= 0) {
          targetIndex = matchedIndex;
        }
      }

      if (targetIndex == null &&
          currentTracks.length > previousSubtitleTrackSignatures.length) {
        targetIndex = currentTracks.length - 1;
      }

      if (targetIndex == null && currentTracks.length == 1) {
        targetIndex = 0;
      }

      if (targetIndex == null) {
        continue;
      }

      try {
        _player.setProperty('subtitle', '1');
        _player.activeSubtitleTracks = [targetIndex];
        debugPrint(
          'SubtitleManager: MDK 外部字幕轨已激活，索引: $targetIndex, 字幕: $subtitlePath',
        );
        return;
      } catch (e) {
        debugPrint('SubtitleManager: MDK 激活外部字幕轨失败: $e');
      }
    }

    debugPrint('SubtitleManager: MDK 外部字幕轨激活超时: $subtitlePath');
  }

  Future<void> _loadExternalSubtitleWithEncodingFix(
    String sourcePath,
    int loadToken, {
    List<String>? previousSubtitleTrackSignatures,
  }) async {
    try {
      if (kIsWeb) return;

      final extension = p.extension(sourcePath).toLowerCase();
      if (extension == '.sup' || extension == '.idx') {
        if (loadToken != _subtitleLoadToken) return;
        if (_currentExternalSubtitlePath != sourcePath) return;
        _loadExternalSubtitleIntoPlayer(
          sourcePath,
          loadToken,
          previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
        );
        return;
      }

      final decoded = await SubtitleParser.decodeSubtitleFile(
        sourcePath,
        allowUnknownFormat: true,
      );
      if (decoded == null) {
        if (extension == '.sub') {
          final idxPath = p.setExtension(sourcePath, '.idx');
          final idxFile = File(idxPath);
          if (await idxFile.exists()) {
            if (loadToken != _subtitleLoadToken) return;
            if (_currentExternalSubtitlePath != sourcePath) return;
            _loadExternalSubtitleIntoPlayer(
              idxPath,
              loadToken,
              previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
            );
            debugPrint('SubtitleManager: 检测到VobSub，改用IDX加载字幕: $idxPath');
            return;
          }
        }
        // 解码失败且无 IDX 配对，回退直接加载原文件（避免完全无字幕）
        if (loadToken != _subtitleLoadToken) return;
        if (_currentExternalSubtitlePath != sourcePath) return;
        _loadExternalSubtitleIntoPlayer(
          sourcePath,
          loadToken,
          previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
        );
        return;
      }

      final encoding = decoded.encoding.toLowerCase();
      final preview = _extractSubtitlePreview(decoded.text);
      final format = SubtitleParser.detectFormat(decoded.text, sourcePath);
      debugPrint(
        'SubtitleManager: 检测到字幕编码: ${decoded.encoding}, 格式: $format, 预览: $preview',
      );
      if (encoding.startsWith('utf-8')) {
        if (loadToken != _subtitleLoadToken) return;
        if (_currentExternalSubtitlePath != sourcePath) return;
        _loadExternalSubtitleIntoPlayer(
          sourcePath,
          loadToken,
          previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
        );
        return;
      }

      final file = File(sourcePath);
      if (!await file.exists()) return;
      final stat = await file.stat();
      if (stat.size <= 0) return;

      final cacheDir = await _getSubtitleCacheDirectory();
      const cacheVersion = 'v2';
      final cacheKey =
          '$cacheVersion|$sourcePath|${stat.modified.millisecondsSinceEpoch}|${stat.size}|${decoded.encoding}';
      final hash = sha1.convert(utf8.encode(cacheKey)).toString();
      final targetExtension = _resolveSubtitleExtension(format, extension);
      final targetPath = p.join(cacheDir.path, '$hash$targetExtension');

      final targetFile = File(targetPath);
      if (!await targetFile.exists()) {
        await targetFile.writeAsString(decoded.text, encoding: utf8);
      }

      if (loadToken != _subtitleLoadToken) return;
      if (_currentExternalSubtitlePath != sourcePath) return;

      _loadExternalSubtitleIntoPlayer(
        targetPath,
        loadToken,
        previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
      );
      debugPrint('SubtitleManager: 已转换字幕编码并重新加载: $targetPath');
    } catch (e) {
      debugPrint('SubtitleManager: 转换字幕编码失败: $e');
    }
  }

  Future<Directory> _getSubtitleCacheDirectory() async {
    final baseDir = await StorageService.getAppStorageDirectory();
    final cacheDir = Directory(p.join(baseDir.path, 'subtitle_transcoded'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String _resolveSubtitleExtension(
    SubtitleFormat format,
    String originalExtension,
  ) {
    if (format == SubtitleFormat.ass) return '.ass';
    if (format == SubtitleFormat.srt) return '.srt';
    if (format == SubtitleFormat.subViewer) return '.sub';
    if (format == SubtitleFormat.microdvd) return '.sub';
    if (originalExtension.isNotEmpty) return originalExtension;
    return '.sub';
  }

  String _extractSubtitlePreview(String text) {
    final lines = LineSplitter.split(text);
    String? firstNonEmpty;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      firstNonEmpty ??= trimmed;
      if (_containsCjk(trimmed)) {
        return _trimPreview(trimmed);
      }
    }

    if (firstNonEmpty == null) return '';
    return _trimPreview(firstNonEmpty);
  }

  bool _containsCjk(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0xF900 && rune <= 0xFAFF) ||
          (rune >= 0x3040 && rune <= 0x30FF) ||
          (rune >= 0xAC00 && rune <= 0xD7AF)) {
        return true;
      }
    }
    return false;
  }

  String _trimPreview(String text) {
    final cleaned = text.replaceAll('\n', ' ').trim();
    if (cleaned.length <= _subtitlePreviewMaxChars) return cleaned;
    return '${cleaned.substring(0, _subtitlePreviewMaxChars)}...';
  }

  // 强制设置外部字幕（手动操作）
  void forceSetExternalSubtitle(String path) {
    // 调用setExternalSubtitle，并标记为手动设置
    setExternalSubtitle(path, isManualSetting: true);
  }

  // 自动检测并加载同名字幕文件
  Future<void> autoDetectAndLoadSubtitle(String videoPath) async {
    if (kIsWeb) {
      debugPrint('SubtitleManager: Web平台跳过自动检测字幕文件');
      return;
    }
    if (MediaSourceUtils.isContentUri(videoPath)) {
      return;
    }
    var detectionToken = _subtitleLoadToken;
    bool isCurrent() =>
        _currentVideoPath == videoPath && detectionToken == _subtitleLoadToken;
    if (!isCurrent()) return;
    try {
      debugPrint('SubtitleManager: 自动检测字幕文件...');

      // 首先检查是否有保存的字幕路径
      String? savedSubtitlePath = await getVideoSubtitlePath(videoPath);
      if (!isCurrent()) return;
      if (savedSubtitlePath != null && savedSubtitlePath.isNotEmpty) {
        // 恢复持久化时登记的显示名（缓存文件名是哈希，不能用 basename）
        var savedDisplayName = await _lookupPersistedDisplayName(
          videoPath: videoPath,
          subtitlePath: savedSubtitlePath,
        );

        // 用户要求：VobSub（.sub/.idx）不作为自动恢复的主字幕——位图字幕
        // 内存重、日文为主。保存的映射是 sub/idx 时改选候选中的文本字幕
        // （SC/简中优先，TC 次选），sub/idx 转为叠挂候选。
        final savedExt = p.extension(savedSubtitlePath).toLowerCase();
        if (isVobSubBinaryFile(savedSubtitlePath) || savedExt == '.idx') {
          debugPrint('SubtitleManager: 保存的字幕是 VobSub($savedExt)，改选文本字幕为主');
          final replacement = _pickTextSubtitleReplacement(
            videoPath: videoPath,
            excludePath: savedSubtitlePath,
          );
          if (replacement != null) {
            debugPrint('SubtitleManager: VobSub 主字幕替换为: $replacement');
            saveVideoSubtitleMapping(videoPath, replacement);
            savedSubtitlePath = replacement;
            savedDisplayName = p.basename(replacement);
          }
        }
        debugPrint('SubtitleManager: 找到保存的字幕映射: $savedSubtitlePath');

        // 检查字幕文件是否存在
        final subtitleFile = File(savedSubtitlePath);
        if (subtitleFile.existsSync() &&
            isVobSubPairComplete(savedSubtitlePath)) {
          debugPrint('SubtitleManager: 加载上次使用的外部字幕: $savedSubtitlePath');

          // 等待一段时间确保播放器准备好
          await Future.delayed(_autoLoadPlayerReadyDelay);

          if (!isCurrent()) return;
          // 设置外部字幕（标记为手动设置，因为这是用户曾经手动选择过的）
          setExternalSubtitle(savedSubtitlePath,
              isManualSetting: true, displayName: savedDisplayName);
          detectionToken = _subtitleLoadToken;

          // Restore the menu choices without activating additional subtitles.
          await _registerRemainingSubtitlesAfterRestore(
            videoPath: videoPath,
            savedSubtitlePath: savedSubtitlePath,
          );

          // 设置完成后强制刷新状态
          await Future.delayed(_autoLoadStateSettleDelay);

          if (!isCurrent()) return;
          // 触发自动加载字幕回调
          if (onExternalSubtitleAutoLoaded != null) {
            final fileName = p.basename(savedSubtitlePath);
            onExternalSubtitleAutoLoaded!(savedSubtitlePath, fileName);
          }

          return;
        } else {
          debugPrint('SubtitleManager: 保存的字幕文件不存在，尝试寻找新的字幕文件');
        }
      }

      // 远程媒体库字幕（含弹弹play远程流）
      if (!kIsWeb &&
          RemoteSubtitleService.instance.isPotentialRemoteVideoPath(
            videoPath,
          )) {
        try {
          if (kDebugMode)
            debugPrint(
                '[FONT_DEBUG] autoDetectAndLoadSubtitle: 检测到远程视频路径: $videoPath');
          final candidates = await RemoteSubtitleService.instance
              .listCandidatesForVideo(videoPath);
          if (kDebugMode)
            debugPrint(
                '[FONT_DEBUG] listCandidatesForVideo 返回 ${candidates.length} 个字幕候选');
          if (candidates.isNotEmpty) {
            final resolvedMatchPath = RemoteSubtitleService.instance
                .resolveVideoPathForMatching(videoPath);
            final matchPath =
                resolvedMatchPath.isNotEmpty ? resolvedMatchPath : videoPath;
            if (!isCurrent()) return;
            final matching = candidates
                .where((c) => _remoteCandidateMatchesVideo(matchPath, c))
                .toList();
            if (matching.isEmpty) return;
            final selected = _pickRemoteSubtitleCandidate(matching, matchPath);
            if (kDebugMode)
              debugPrint(
                  '[FONT_DEBUG] 选中字幕: ${selected.name}, extension=${selected.extension}');
            final cachedPath =
                await RemoteSubtitleService.instance.ensureSubtitleCached(
              selected,
              allCandidates: candidates,
            );
            if (kDebugMode) debugPrint('[FONT_DEBUG] 字幕已缓存: $cachedPath');

            // 渐进式加载：先立即加载字幕（可能使用备用字体），再后台下载远程字体
            // 字体下载完成后重新加载字幕，使 libass 使用正确字体渲染
            if (kDebugMode) debugPrint('[FONT_DEBUG] 立即加载字幕，后台预取远程字体...');

            // 等待一段时间确保播放器准备好
            await Future.delayed(_autoLoadPlayerReadyDelay);

            // 设置外部字幕（不标记为手动设置，因为是自动检测的）
            if (!isCurrent()) return;
            setExternalSubtitle(cachedPath,
                isManualSetting: false, displayName: selected.name);
            detectionToken = _subtitleLoadToken;
            await _persistExternalSubtitleSelection(
              videoPath: videoPath,
              subtitlePath: cachedPath,
              isActive: true,
              displayName: selected.name,
            );

            // 保存这个自动找到的字幕路径，下次可以直接使用
            saveVideoSubtitleMapping(videoPath, cachedPath);

            // Register same-video alternatives without changing playback.
            final registeredPaths = <String>{cachedPath};
            for (final other in matching) {
              if (!isCurrent()) return;
              if (identical(other, selected)) continue;
              try {
                final otherPath =
                    await RemoteSubtitleService.instance.ensureSubtitleCached(
                  other,
                  allCandidates: candidates,
                );
                if (!isCurrent()) return;
                if (!registeredPaths.add(otherPath)) continue;
                await registerExternalSubtitleCandidate(otherPath,
                    displayName: other.name);
                debugPrint('SubtitleManager: 登记候选字幕 ${other.name}');
              } catch (e) {
                debugPrint('SubtitleManager: 登记候选字幕 ${other.name} 失败: $e');
              }
            }

            // 设置完成后强制刷新状态
            await Future.delayed(_autoLoadStateSettleDelay);

            if (!isCurrent()) return;
            // 触发自动加载字幕回调
            if (onExternalSubtitleAutoLoaded != null) {
              onExternalSubtitleAutoLoaded!(cachedPath, selected.name);
            }

            // 后台下载远程字体，完成后重新加载字幕使字体生效
            _prefetchRemoteFontsForSubtitle(videoPath, cachedPath).then((_) {
              // 只有 ASS/SSA 需要重新交给内核加载字体。异步完成时视频或
              // 字幕选择可能已变，不能恢复旧字幕，也不能清除已叠加的字幕。
              final extension = p.extension(cachedPath).toLowerCase();
              if (extension != '.ass' && extension != '.ssa') {
                return;
              }
              if (_currentVideoPath != videoPath ||
                  _shouldRenderExternalSubtitleInApp(cachedPath) ||
                  !_activeExternalSubtitlePaths.contains(cachedPath) ||
                  _activeExternalSubtitlePaths.any((path) =>
                      path != cachedPath &&
                      !_shouldRenderExternalSubtitleInApp(path))) {
                return;
              }
              if (kDebugMode) {
                debugPrint('[FONT_DEBUG] 远程字体预取完成，重新加载字幕以应用字体');
              }
              setExternalSubtitle(
                cachedPath,
                isManualSetting: false,
                displayName: selected.name,
                preserveStack: true,
              );
            }).catchError((e) {
              if (kDebugMode) {
                debugPrint('[FONT_DEBUG] 远程字体预取失败（字幕仍可用备用字体）: $e');
              }
            });

            return;
          } else {
            debugPrint('SubtitleManager: 远程目录未找到字幕文件');
          }
        } catch (e) {
          debugPrint('SubtitleManager: 远程字幕检测失败: $e');
        }

        final streamUri = Uri.tryParse(videoPath);
        final scheme = streamUri?.scheme.toLowerCase();
        if (scheme == 'http' ||
            scheme == 'https' ||
            MediaSourceUtils.isNewWebDavPath(videoPath) ||
            MediaSourceUtils.isNewSmbPath(videoPath)) {
          debugPrint('SubtitleManager: 远程流字幕检测结束，跳过本地文件系统检测');
          return;
        }
      }

      // 需求：即使存在内嵌字幕，也应优先尝试自动加载外挂字幕。

      if (!isCurrent()) return;
      // 检查视频文件是否存在
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        debugPrint('SubtitleManager: 视频文件不存在，无法检测字幕');
        return;
      }

      // 以下是正常的字幕检测和加载过程

      // 获取视频文件目录和文件名（不含扩展名）
      final videoDir = videoFile.parent.path;
      final videoName = p.basenameWithoutExtension(videoPath);

      // 从视频文件名中提取数字（可能的集数）
      final videoNumberMatch = RegExp(r'(\d+)').allMatches(videoName).toList();
      List<String> videoNumbers = [];
      if (videoNumberMatch.isNotEmpty) {
        videoNumbers =
            videoNumberMatch.map((match) => match.group(0)!).toList();
        debugPrint('SubtitleManager: 从视频文件名中提取的数字: $videoNumbers');
      }

      // 提取最可能是集数的数字
      String? episodeNumber;
      if (videoNumbers.isNotEmpty) {
        episodeNumber = pickLikelyEpisodeNumber(videoNumbers);
        debugPrint('SubtitleManager: 提取的可能集数: $episodeNumber');
      }

      // 常见字幕文件扩展名按优先级排序
      final subtitleExts = subtitleExtensionMatchScore.keys.toList();

      // 扫描所有同集候选，统一选主字幕并登记其余选项。
      // 收集目录内候选，再根据视频名称与集数过滤。
      final videoDirectory = Directory(videoDir);
      if (videoDirectory.existsSync()) {
        try {
          final files = videoDirectory.listSync();

          // 收集所有字幕文件
          List<File> subtitleFiles = [];
          for (final file in files) {
            if (file is File) {
              final ext = p.extension(file.path).toLowerCase();
              if (subtitleExts.contains(ext) &&
                  isVobSubPairComplete(file.path)) {
                subtitleFiles.add(file);
              }
            }
          }

          if (subtitleFiles.isEmpty) {
            debugPrint('SubtitleManager: 目录中没有找到任何字幕文件');
            return;
          }

          await _autoLoadLocalSubtitleGroup(
            videoPath: videoPath,
            subtitleFiles: subtitleFiles,
            videoName: videoName,
            videoNumbers: videoNumbers,
            episodeNumber: episodeNumber,
            requireReliableMatch: true,
          );
          return;
        } catch (e) {
          debugPrint('SubtitleManager: 目录搜索错误: $e');
        }
      }

      debugPrint('SubtitleManager: 未找到匹配的字幕文件');
    } catch (e) {
      debugPrint('SubtitleManager: 自动检测字幕文件失败: $e');
    }
  }

  /// 本地自动加载最佳一条，其余匹配候选保存在菜单中供手动选择。
  Future<void> _autoLoadLocalSubtitleGroup({
    required String videoPath,
    required List<File> subtitleFiles,
    required String videoName,
    required List<String> videoNumbers,
    String? episodeNumber,
    bool requireReliableMatch = false,
  }) async {
    final detectionToken = _subtitleLoadToken;
    bool isCurrent() =>
        _currentVideoPath == videoPath && detectionToken == _subtitleLoadToken;
    subtitleFiles = subtitleFiles
        .where((file) => subtitleMatchesVideo(
            videoName, p.basenameWithoutExtension(file.path)))
        .map((file) => canonicalSubtitlePath(file.path))
        .toSet()
        .map(File.new)
        .toList();
    if (subtitleFiles.isEmpty || !isCurrent()) return;
    final scored = subtitleFiles.map((file) {
      final subtitleName = p.basenameWithoutExtension(file.path);
      final extension = p.extension(file.path).toLowerCase();
      final score = computeLocalSubtitleMatchScore(
        videoName: videoName,
        subtitleName: subtitleName,
        extension: extension,
        videoNumbers: videoNumbers,
        episodeNumber: episodeNumber,
      );
      return (file: file, score: score);
    }).toList()
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        return a.file.path.compareTo(b.file.path);
      });

    for (final candidate in scored) {
      debugPrint(
        'SubtitleManager: 本地字幕候选 ${candidate.file.path} 得分: ${candidate.score}',
      );
    }

    var best = scored.first;
    if (requireReliableMatch &&
        best.score < minReliableLocalSubtitleMatchScore) {
      debugPrint('SubtitleManager: 没有找到足够可靠的本地字幕匹配结果');
      return;
    }

    // 等待一段时间确保播放器准备好
    await Future.delayed(_autoLoadPlayerReadyDelay);

    if (!isCurrent()) return;
    // 设置外部字幕（不标记为手动设置，因为是自动检测的）
    setExternalSubtitle(best.file.path, isManualSetting: false);
    final activeToken = _subtitleLoadToken;

    // 保存这个自动找到的字幕路径，下次可以直接使用
    saveVideoSubtitleMapping(videoPath, best.file.path);

    // 写入 external_subtitles 列表，让字幕轨道菜单能看到
    await _persistExternalSubtitleSelection(
      videoPath: videoPath,
      subtitlePath: best.file.path,
      isActive: true,
    );

    // Available candidates never enter the active display stack automatically.
    for (final candidate in scored.skip(1)) {
      try {
        if (_currentVideoPath != videoPath || activeToken != _subtitleLoadToken)
          return;
        await registerExternalSubtitleCandidate(candidate.file.path,
            displayName: p.basename(candidate.file.path));
        debugPrint(
            'SubtitleManager: 登记候选字幕 ${p.basename(candidate.file.path)}');
      } catch (e) {
        debugPrint(
            'SubtitleManager: 登记候选字幕 ${p.basename(candidate.file.path)} 失败: $e');
      }
    }

    // 设置完成后强制刷新状态
    await Future.delayed(_autoLoadStateSettleDelay);

    if (_currentVideoPath != videoPath || activeToken != _subtitleLoadToken)
      return;
    // 触发自动加载字幕回调
    if (onExternalSubtitleAutoLoaded != null) {
      final fileName = p.basename(best.file.path);
      onExternalSubtitleAutoLoaded!(best.file.path, fileName);
    }
  }

  /// 保存的映射是 VobSub（.sub/.idx）时的主字幕替换：在视频目录中按现有
  /// 评分挑一条文本字幕（SC/简中优先，TC 次选），排除 VobSub 自身。
  String? _pickTextSubtitleReplacement({
    required String videoPath,
    required String excludePath,
  }) {
    if (kIsWeb) return null;
    try {
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) return null;
      final videoDir = videoFile.parent.path;
      final videoName = p.basenameWithoutExtension(videoPath);
      final subtitleExts = subtitleExtensionMatchScore.keys
          .toList()
          .where((ext) => ext != '.sup' && ext != '.idx')
          .toList();

      final files = <File>{};
      // 同名精确匹配优先入集
      for (final ext in subtitleExts) {
        final potentialPath = p.join(videoDir, '$videoName$ext');
        if (File(potentialPath).existsSync()) {
          files.add(File(potentialPath));
        }
      }
      // 目录模糊匹配
      for (final entity in Directory(videoDir).listSync()) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (subtitleExts.contains(ext)) {
          files.add(entity);
        }
      }
      if (files.isEmpty) return null;

      final videoNumberMatch = RegExp(r'(\d+)').allMatches(videoName).toList();
      final videoNumbers =
          videoNumberMatch.map((match) => match.group(0)!).toList();
      final episodeNumber = videoNumbers.isNotEmpty
          ? pickLikelyEpisodeNumber(videoNumbers)
          : null;

      String? bestPath;
      int bestScore = -0x7fffffff;
      for (final file in files) {
        if (p.normalize(file.path) == p.normalize(excludePath)) continue;
        if (isVobSubBinaryFile(file.path) ||
            !subtitleMatchesVideo(
                videoName, p.basenameWithoutExtension(file.path))) continue;
        final score = computeLocalSubtitleMatchScore(
          videoName: videoName,
          subtitleName: p.basenameWithoutExtension(file.path),
          extension: p.extension(file.path).toLowerCase(),
          videoNumbers: videoNumbers,
          episodeNumber: episodeNumber,
        );
        if (score > bestScore) {
          bestScore = score;
          bestPath = file.path;
        }
      }
      return bestPath;
    } catch (e) {
      debugPrint('SubtitleManager: 挑选 VobSub 替换主字幕失败: $e');
      return null;
    }
  }

  /// Restore matching candidates to the menu while keeping the saved selection.
  Future<void> _registerRemainingSubtitlesAfterRestore({
    required String videoPath,
    required String savedSubtitlePath,
  }) async {
    if (kIsWeb) return;
    final token = _subtitleLoadToken;
    bool isCurrent() =>
        _currentVideoPath == videoPath && token == _subtitleLoadToken;
    final candidates = <_StackCandidate>[];

    try {
      if (RemoteSubtitleService.instance
          .isPotentialRemoteVideoPath(videoPath)) {
        final remote = await RemoteSubtitleService.instance
            .listCandidatesForVideo(videoPath);
        for (final other in remote) {
          candidates.add(_StackCandidate(
            path: null,
            name: other.name,
            remote: other,
          ));
        }
      } else {
        final videoFile = File(videoPath);
        if (!videoFile.existsSync()) return;
        final videoDir = videoFile.parent.path;
        final subtitleExts = subtitleExtensionMatchScore.keys.toList();
        final seen = <String>{};
        for (final ext in subtitleExts) {
          final potentialPath =
              p.join(videoDir, '${p.basenameWithoutExtension(videoPath)}$ext');
          if (File(potentialPath).existsSync() &&
              isVobSubPairComplete(potentialPath) &&
              seen.add(potentialPath.toLowerCase())) {
            candidates.add(_StackCandidate(
              path: potentialPath,
              name: p.basename(potentialPath),
            ));
          }
        }
        final dirFiles = Directory(videoDir).listSync();
        for (final entity in dirFiles) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (!subtitleExts.contains(ext)) continue;
          if (!isVobSubPairComplete(entity.path)) continue;
          if (seen.add(entity.path.toLowerCase())) {
            candidates.add(_StackCandidate(
              path: entity.path,
              name: p.basename(entity.path),
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('SubtitleManager: 恢复时收集字幕候选失败: $e');
      return;
    }

    for (final candidate in candidates) {
      try {
        if (!isCurrent()) return;
        if (candidate.remote != null
            ? !_remoteCandidateMatchesVideo(videoPath, candidate.remote!)
            : !_candidateMatchesVideo(videoPath, candidate.name)) continue;
        String stackPath;
        if (candidate.path != null) {
          stackPath = canonicalSubtitlePath(candidate.path!);
        } else {
          stackPath = await RemoteSubtitleService.instance.ensureSubtitleCached(
            candidate.remote!,
            allCandidates: candidates
                .map((c) => c.remote)
                .whereType<RemoteSubtitleCandidate>()
                .toList(),
          );
        }
        if (_activeExternalSubtitlePaths.contains(stackPath) ||
            stackPath == savedSubtitlePath) {
          continue;
        }
        if (!isCurrent()) return;
        await registerExternalSubtitleCandidate(stackPath,
            displayName: candidate.name);
        debugPrint('SubtitleManager: 恢复时登记候选字幕 ${candidate.name}');
      } catch (e) {
        debugPrint('SubtitleManager: 恢复候选字幕 ${candidate.name} 失败: $e');
      }
    }
  }

  bool _remoteCandidateMatchesVideo(
      String videoPath, RemoteSubtitleCandidate candidate) {
    // These endpoints identify a video by ID, not by its filename. Use their
    // per-video metadata rather than matching the literal "stream"/hash name.
    if (candidate is DandanplayRemoteSubtitleCandidate) return true;
    final uri = Uri.tryParse(videoPath);
    if (candidate is SharedRemoteSubtitleCandidate &&
        uri != null &&
        RegExp(r'/api/media/local/share/episodes/[^/]+/stream$')
            .hasMatch(uri.path)) {
      return candidate.isLikelyMatch;
    }
    return _candidateMatchesVideo(videoPath, candidate.name);
  }

  bool _candidateMatchesVideo(String videoPath, String subtitleName) {
    final resolved =
        RemoteSubtitleService.instance.resolveVideoPathForMatching(videoPath);
    final path = resolved.isEmpty ? videoPath : resolved;
    final uri = Uri.tryParse(path);
    final name = uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : p.basename(path);
    return subtitleMatchesVideo(p.basenameWithoutExtension(name),
        p.basenameWithoutExtension(subtitleName));
  }

  RemoteSubtitleCandidate _pickRemoteSubtitleCandidate(
    List<RemoteSubtitleCandidate> candidates,
    String videoPath,
  ) {
    String? baseName;
    try {
      final uri = Uri.tryParse(videoPath);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        baseName = p.basenameWithoutExtension(uri.pathSegments.last);
      }
    } catch (_) {}

    int scoreCandidate(RemoteSubtitleCandidate candidate) {
      final ext = candidate.extension.toLowerCase();
      int score = switch (ext) {
        '.ass' => 40,
        '.ssa' => 35,
        '.srt' => 30,
        '.sub' => 25,
        '.sup' => 10,
        '.idx' => 20,
        _ => 0,
      };

      if (baseName != null && baseName.isNotEmpty) {
        final lowerName = candidate.name.toLowerCase();
        if (lowerName.contains(baseName.toLowerCase())) {
          score += 15;
        }
      }

      if (candidate is SharedRemoteSubtitleCandidate &&
          candidate.isLikelyMatch) {
        score += 25;
      }
      return score;
    }

    final sorted = List<RemoteSubtitleCandidate>.from(candidates)
      ..sort((a, b) {
        final scoreCompare = scoreCandidate(b).compareTo(scoreCandidate(a));
        if (scoreCompare != 0) return scoreCompare;
        return a.name.compareTo(b.name);
      });

    return sorted.first;
  }

  // 获取语言名称
  String getLanguageName(String language) {
    final mapped = getSubtitleLanguageName(language);
    debugPrint('SubtitleManager: getLanguageName "$language" -> "$mapped"');
    return mapped;
  }

  // 更新指定的字幕轨道信息
  void updateEmbeddedSubtitleTrack(int trackIndex) {
    if (_player.mediaInfo.subtitle == null ||
        trackIndex >= _player.mediaInfo.subtitle!.length) {
      return;
    }

    final playerSubInfo = _player.mediaInfo.subtitle![trackIndex];
    _lastSelectedEmbeddedTrackIndex = trackIndex;
    debugPrint(
      'SubtitleManager: updateEmbeddedSubtitleTrack - Called for trackIndex: $trackIndex',
    );
    debugPrint(
      '  - playerSubInfo.title (from Adapter): "${playerSubInfo.title}"',
    );
    debugPrint(
      '  - playerSubInfo.language (from Adapter): "${playerSubInfo.language}"',
    );
    debugPrint(
      '  - playerSubInfo.metadata (from Adapter): ${playerSubInfo.metadata}',
    );

    String originalTitleFromAdapter = playerSubInfo.title ?? '';
    String originalLanguageCodeFromAdapter = playerSubInfo.language ?? '';
    debugPrint(
      '  - Initial originalTitleFromAdapter: "$originalTitleFromAdapter"',
    );
    debugPrint(
      '  - Initial originalLanguageCodeFromAdapter: "$originalLanguageCodeFromAdapter"',
    );

    String displayTitle = originalTitleFromAdapter;
    String determinedLanguage = "未知";
    debugPrint(
      '  - Initial displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"',
    );

    // 1. Try to determine language using the language code from adapter first
    if (originalLanguageCodeFromAdapter.isNotEmpty) {
      determinedLanguage = getLanguageName(originalLanguageCodeFromAdapter);
      debugPrint(
        '  - After step 1 (from lang code): determinedLanguage: "$determinedLanguage"',
      );
    }

    // 2. If language code didn't yield a good name (or was empty), try with the title from adapter
    if (determinedLanguage == "未知" ||
        determinedLanguage == originalLanguageCodeFromAdapter) {
      String langFromTitle = getLanguageName(originalTitleFromAdapter);
      debugPrint(
        '  - Step 2 (from title "$originalTitleFromAdapter"): langFromTitle: "$langFromTitle"',
      );
      if (langFromTitle != originalTitleFromAdapter) {
        determinedLanguage = langFromTitle;
      }
      debugPrint('  - After step 2: determinedLanguage: "$determinedLanguage"');
    }

    // 3. Determine final display title based on the determinedLanguage
    if (determinedLanguage != "未知" &&
        determinedLanguage != originalTitleFromAdapter &&
        determinedLanguage != originalLanguageCodeFromAdapter) {
      displayTitle = determinedLanguage;
      if (originalTitleFromAdapter.isNotEmpty &&
          originalTitleFromAdapter.toLowerCase() != 'n/a' &&
          originalTitleFromAdapter != displayTitle &&
          !displayTitle.contains(originalTitleFromAdapter) &&
          getLanguageName(originalTitleFromAdapter) != displayTitle) {
        displayTitle += " ($originalTitleFromAdapter)";
      }
    } else if (originalTitleFromAdapter.isNotEmpty &&
        originalTitleFromAdapter.toLowerCase() != 'n/a') {
      String langFromOrigTitle = getLanguageName(originalTitleFromAdapter);
      if (langFromOrigTitle != originalTitleFromAdapter) {
        displayTitle = langFromOrigTitle;
        determinedLanguage = langFromOrigTitle;
      } else {
        displayTitle = originalTitleFromAdapter;
        if (determinedLanguage == "未知") {
          determinedLanguage = originalTitleFromAdapter;
        }
      }
    } else {
      displayTitle = "轨道 ${trackIndex + 1}";
      if (determinedLanguage == "未知") determinedLanguage = displayTitle;
    }
    debugPrint(
      '  - After step 3 (display title construction): displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"',
    );

    // Ensure determinedLanguage itself is a "final" friendly name
    String finalDeterminedLanguage = getLanguageName(determinedLanguage);
    if (finalDeterminedLanguage != determinedLanguage) {
      determinedLanguage = finalDeterminedLanguage;
    }
    debugPrint(
      '  - After final determinedLanguage refinement: determinedLanguage: "$determinedLanguage"',
    );

    // If displayTitle is generic but determinedLanguage is more specific, use determinedLanguage for displayTitle
    if ((displayTitle == "未知" ||
            displayTitle.startsWith("轨道 ") ||
            displayTitle.isEmpty) &&
        determinedLanguage != "未知" &&
        !determinedLanguage.startsWith("轨道 ") &&
        determinedLanguage.isNotEmpty) {
      displayTitle = determinedLanguage;
    }
    // If displayTitle ended up being empty (e.g. original title was empty and no language match), use a fallback for title
    if (displayTitle.isEmpty) {
      displayTitle = "轨道 ${trackIndex + 1}";
    }
    // If determinedLanguage ended up empty, and display title is not generic, use display title for language
    if (determinedLanguage.isEmpty &&
        displayTitle.isNotEmpty &&
        !displayTitle.startsWith("轨道 ")) {
      determinedLanguage = displayTitle;
    } else if (determinedLanguage.isEmpty) {
      // If still empty, use fallback for language
      determinedLanguage = "未知";
    }
    debugPrint(
      '  - After displayTitle/determinedLanguage final fallbacks: displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"',
    );

    debugPrint(
      'SubtitleManager: updateEmbeddedSubtitleTrack - FINAL values before updateSubtitleTrackInfo for trackIndex $trackIndex:',
    );
    debugPrint('  - FINAL title for UI: "$displayTitle"');
    debugPrint('  - FINAL language for UI: "$determinedLanguage"');

    updateSubtitleTrackInfo('embedded_subtitle_$trackIndex', {
      'index': trackIndex,
      'title': displayTitle,
      'language': determinedLanguage,
      'isActive': _player.activeSubtitleTracks.contains(trackIndex),
      'original_media_kit_title':
          playerSubInfo.metadata['title'] ?? originalTitleFromAdapter,
      'original_media_kit_lang_code':
          playerSubInfo.metadata['language'] ?? originalLanguageCodeFromAdapter,
    });

    // 清除外部字幕信息的激活状态
    if (_currentExternalSubtitlePath == null &&
        _player.activeSubtitleTracks.contains(trackIndex) &&
        _subtitleTrackInfo.containsKey('external_subtitle')) {
      updateSubtitleTrackInfo('external_subtitle', {'isActive': false});
    }
  }

  // 更新所有字幕轨道信息
  void updateAllSubtitleTracksInfo() {
    if (_player.mediaInfo.subtitle == null) {
      return;
    }

    // 清除之前的内嵌字幕轨道信息
    for (final key in List.from(_subtitleTrackInfo.keys)) {
      if (key.startsWith('embedded_subtitle_')) {
        _subtitleTrackInfo.remove(key);
      }
    }

    // 更新所有内嵌字幕轨道信息
    for (var i = 0; i < _player.mediaInfo.subtitle!.length; i++) {
      updateEmbeddedSubtitleTrack(i);
    }

    // 在更新完成后检查当前激活的字幕轨道并确保相应的信息被更新
    if (_player.activeSubtitleTracks.isNotEmpty &&
        _currentExternalSubtitlePath == null) {
      final activeIndex = _player.activeSubtitleTracks.first;
      if (activeIndex >= 0 &&
          activeIndex < _player.mediaInfo.subtitle!.length) {
        // 激活的是内嵌字幕轨道
        updateSubtitleTrackInfo('embedded_subtitle', {
          'index': activeIndex,
          'title': _player.mediaInfo.subtitle![activeIndex].toString(),
          'isActive': true,
        });

        // 通知字幕轨道变化
        onSubtitleTrackChanged();
      }
    }

    notifyListeners();
  }

  /// 异步预取远程媒体库中的字体文件到本地 subtitle_fonts 缓存
  /// 当远程 ASS/SSA 字幕被缓存后，从服务端下载所有关联的字体文件，
  /// 并将 sub-fonts-dir 设置为 subtitle_fonts 目录，使 libass 渲染时能自动找到字体
  Future<void> _prefetchRemoteFontsForSubtitle(
    String videoPath,
    String cachedSubtitlePath,
  ) async {
    if (kIsWeb) return;

    try {
      // 仅对 ASS/SSA 字幕检查字体引用
      final ext = p.extension(cachedSubtitlePath).toLowerCase();
      if (kDebugMode)
        debugPrint(
            '[FONT_DEBUG] _prefetchRemoteFontsForSubtitle: videoPath=$videoPath, subtitle=$cachedSubtitlePath, ext=$ext');
      if (ext != '.ass' && ext != '.ssa') {
        if (kDebugMode) debugPrint('[FONT_DEBUG] 非ASS/SSA字幕，跳过字体预取');
        return;
      }

      // 获取远程字体候选列表
      // 服务端在检测到 ASS/SSA 字幕时已将同目录下所有字体标记为 isLikelyMatch，
      // 因此直接下载全部候选字体，而非仅按 ASS Fontname 匹配
      // （ASS 中的 Fontname 可能是中文名如"思源黑体 CN"，而文件名是英文如
      //  "SourceHanSansCN-Regular.ttf"，按名称匹配几乎不可能成功）
      if (kDebugMode) debugPrint('[FONT_DEBUG] 正在调用 listFontsForVideo...');
      final fontCandidates =
          await RemoteSubtitleService.instance.listFontsForVideo(videoPath);
      if (kDebugMode)
        debugPrint(
            '[FONT_DEBUG] listFontsForVideo 返回 ${fontCandidates.length} 个候选');
      for (int i = 0; i < fontCandidates.length; i++) {
        final c = fontCandidates[i];
        if (kDebugMode)
          debugPrint(
              '[FONT_DEBUG] 候选[$i]: name=${c.name}, ext=${c.extension}, isLikelyMatch=${c.isLikelyMatch}, fontUri=${c.fontUri}');
      }
      if (fontCandidates.isEmpty) {
        if (kDebugMode) debugPrint('[FONT_DEBUG] 远程媒体库未提供字体文件，跳过');
        return;
      }

      bool anyFontCached = false;
      for (final candidate in fontCandidates) {
        try {
          if (kDebugMode)
            debugPrint(
                '[FONT_DEBUG] 开始下载字体: ${candidate.name} from ${candidate.fontUri}');
          final cachedFontPath =
              await RemoteSubtitleService.instance.ensureFontCached(candidate);
          anyFontCached = true;
          // 验证文件确实存在且大小正确
          final cachedFile = File(cachedFontPath);
          if (await cachedFile.exists()) {
            final size = await cachedFile.length();
            if (kDebugMode)
              debugPrint(
                  '[FONT_DEBUG] 字体已缓存: $cachedFontPath (size=$size bytes)');
          } else {
            if (kDebugMode)
              debugPrint('[FONT_DEBUG] 字体缓存路径返回但文件不存在: $cachedFontPath');
          }
        } catch (e) {
          if (kDebugMode)
            debugPrint('[FONT_DEBUG] 下载远程字体 ${candidate.name} 失败: $e');
        }
      }

      // 字体下载完成后，立即更新播放器的 sub-fonts-dir 指向 subtitle_fonts 目录，
      // 确保 libass 能在当前播放会话中找到新下载的字体
      if (anyFontCached) {
        try {
          final baseDir = await StorageService.getAppStorageDirectory();
          final fontsDir = p.join(baseDir.path, 'subtitle_fonts');
          if (kDebugMode)
            debugPrint('[FONT_DEBUG] 准备设置 sub-fonts-dir=$fontsDir');
          _player.setProperty('sub-fonts-dir', fontsDir);
          if (kDebugMode)
            debugPrint('[FONT_DEBUG] 已设置 sub-fonts-dir=$fontsDir');

          // 列出 subtitle_fonts 目录下所有文件
          final fontsDirectory = Directory(fontsDir);
          if (await fontsDirectory.exists()) {
            await for (final entity in fontsDirectory.list()) {
              if (entity is File) {
                if (kDebugMode)
                  debugPrint(
                      '[FONT_DEBUG] subtitle_fonts 内文件: ${p.basename(entity.path)} (${await entity.length()} bytes)');
              }
            }
          } else {
            if (kDebugMode)
              debugPrint('[FONT_DEBUG] subtitle_fonts 目录不存在: $fontsDir');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[FONT_DEBUG] 更新 sub-fonts-dir 失败: $e');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('[FONT_DEBUG] 预取远程字体失败: $e\n$stackTrace');
    }
  }

  static void _erikaSubtitleTrace(String message) {
    if (_erikaSubtitleTraceEnabled) {
      debugPrint('[nipa-erika-subtitle-trace] manager $message');
    }
  }

  static String _describeSubtitlePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '<empty>';
    }
    try {
      final file = File(trimmed);
      final stat = file.statSync();
      return '$trimmed exists=${stat.type != FileSystemEntityType.notFound} '
          'size=${stat.size} modified=${stat.modified.toIso8601String()}';
    } catch (error) {
      return '$trimmed stat_error=$error';
    }
  }
}

/// 恢复叠挂用的统一候选：本地路径直接用，远程候选需先下载缓存。
class _StackCandidate {
  const _StackCandidate({
    required this.name,
    this.path,
    this.remote,
  });

  final String name;
  final String? path;
  final RemoteSubtitleCandidate? remote;
}
