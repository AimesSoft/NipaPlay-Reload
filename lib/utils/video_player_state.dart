import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'keyboard_shortcuts.dart';
import 'globals.dart' as globals;
import 'dart:convert';
import '../services/dandanplay_service.dart';
import 'media_info_helper.dart';
import '../services/danmaku_cache_manager.dart';
import '../models/watch_history_model.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p; // Added import for path package
import 'package:crypto/crypto.dart';
import 'package:provider/provider.dart';
import '../providers/watch_history_provider.dart';
import 'package:flutter/foundation.dart';
import 'danmaku_parser.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart'; // Added screen_brightness
import '../widgets/brightness_indicator.dart'; // Added import for BrightnessIndicator widget
import '../widgets/volume_indicator.dart'; // Added import for VolumeIndicator widget
import '../widgets/seek_indicator.dart'; // Added import for SeekIndicator widget

enum PlayerStatus {
  idle, // 空闲状态
  loading, // 加载中
  recognizing, // 识别中
  ready, // 准备就绪
  playing, // 播放中
  paused, // 暂停
  error, // 错误
  disposed // 已释放
}

class VideoPlayerState extends ChangeNotifier implements WindowListener {
  Player player = Player();
  BuildContext? _context;
  PlayerStatus _status = PlayerStatus.idle;
  List<String> _statusMessages = []; // 修改为列表存储多个状态消息
  bool _showControls = true;
  bool _isFullscreen = false;
  double _progress = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;
  double _aspectRatio = 16 / 9; // 默认16:9，但会根据视频实际比例更新
  String? _currentVideoPath;
  Timer? _positionUpdateTimer;
  Timer? _hideControlsTimer;
  Timer? _hideMouseTimer;
  Timer? _autoHideTimer;
  Timer? _screenshotTimer; // 添加截图定时器
  bool _isControlsHovered = false;
  bool _isSeeking = false;
  final FocusNode _focusNode = FocusNode();
  static const String _lastVideoKey = 'last_video_path';
  static const String _lastPositionKey = 'last_video_position';
  static const String _videoPositionsKey = 'video_positions';
  static const int _textureIdCounter = 0;
  Duration? _lastSeekPosition; // 添加这个字段来记录最后一次seek的位置
  List<Map<String, dynamic>> _danmakuList = [];
  static const String _controlBarHeightKey = 'control_bar_height';
  double _controlBarHeight = 20.0; // 默认高度
  static const String _danmakuOpacityKey = 'danmaku_opacity';
  double _danmakuOpacity = 1.0; // 默认透明度
  static const String _danmakuVisibleKey = 'danmaku_visible';
  bool _danmakuVisible = true; // 默认显示弹幕
  static const String _mergeDanmakuKey = 'merge_danmaku';
  bool _mergeDanmaku = false; // 默认不合并弹幕
  static const String _danmakuStackingKey = 'danmaku_stacking';
  bool _danmakuStacking = false; // 默认不启用弹幕堆叠
  dynamic danmakuController; // 添加弹幕控制器属性
  Duration _videoDuration = Duration.zero; // 添加视频时长状态
  bool _isFullscreenTransitioning = false;
  String? _currentThumbnailPath; // 添加当前缩略图路径
  String? _currentVideoHash; // 缓存当前视频的哈希值，避免重复计算
  bool _isCapturingFrame = false; // 是否正在截图，避免并发截图
  final List<VoidCallback> _thumbnailUpdateListeners = []; // 缩略图更新监听器列表
  String? _animeTitle; // 添加动画标题属性
  String? _episodeTitle; // 添加集数标题属性

  // 存储弹幕轨道信息
  final Map<String, Map<String, dynamic>> _danmakuTrackInfo = {};

  // 获取弹幕轨道信息
  Map<String, Map<String, dynamic>> get danmakuTrackInfo => _danmakuTrackInfo;

  // 更新弹幕轨道信息
  void updateDanmakuTrackInfo(String key, Map<String, dynamic> info) {
    _danmakuTrackInfo[key] = info;
    notifyListeners();
  }

  // 清除弹幕轨道信息
  void clearDanmakuTrackInfo() {
    _danmakuTrackInfo.clear();
    notifyListeners();
  }

  // Screen Brightness Control
  double _currentBrightness =
      0.5; // Default, will be updated by _loadInitialBrightness
  double _initialDragBrightness = 0.5; // To store brightness when drag starts
  bool _isBrightnessIndicatorVisible = false;
  Timer? _brightnessIndicatorTimer;
  OverlayEntry? _brightnessOverlayEntry; // <<< ADDED THIS LINE

  // Volume Control State
  double _currentVolume = 0.5; // Default volume
  double _initialDragVolume = 0.5;
  bool _isVolumeIndicatorVisible = false;
  Timer? _volumeIndicatorTimer;
  OverlayEntry? _volumeOverlayEntry;

  // Horizontal Seek Drag State
  bool _isSeekingViaDrag = false;
  Duration _dragSeekStartPosition = Duration.zero;
  double _accumulatedDragDx = 0.0;
  Timer? _seekIndicatorTimer; // For showing a temporary seek UI (not implemented yet)
  OverlayEntry? _seekOverlayEntry; // For a temporary seek UI (not implemented yet)
  Duration _dragSeekTargetPosition = Duration.zero; // To show target position during drag
  bool _isSeekIndicatorVisible = false; // <<< ADDED THIS LINE

  VideoPlayerState() {
    _initialize();
  }

  // Getters
  PlayerStatus get status => _status;
  List<String> get statusMessages => _statusMessages;
  bool get showControls => _showControls;
  bool get isFullscreen => _isFullscreen;
  double get progress => _progress;
  Duration get duration => _duration;
  Duration get position => _position;
  String? get error => _error;
  double get aspectRatio => _aspectRatio;
  bool get hasVideo =>
      _status == PlayerStatus.ready ||
      _status == PlayerStatus.playing ||
      _status == PlayerStatus.paused;
  bool get isPaused => _status == PlayerStatus.paused;
  FocusNode get focusNode => _focusNode;
  List<Map<String, dynamic>> get danmakuList => _danmakuList;
  double get controlBarHeight => _controlBarHeight;
  double get danmakuOpacity => _danmakuOpacity;
  bool get danmakuVisible => _danmakuVisible;
  bool get mergeDanmaku => _mergeDanmaku;
  bool get danmakuStacking => _danmakuStacking;
  Duration get videoDuration => _videoDuration;
  String? get currentVideoPath => _currentVideoPath;
  String? get animeTitle => _animeTitle; // 添加动画标题getter
  String? get episodeTitle => _episodeTitle; // 添加集数标题getter

  // Brightness Getters
  double get currentScreenBrightness => _currentBrightness;
  bool get isBrightnessIndicatorVisible => _isBrightnessIndicatorVisible;

  // Volume Getters
  double get currentSystemVolume => _currentVolume;
  bool get isVolumeUIVisible => _isVolumeIndicatorVisible; // Renamed for clarity

  // Seek Indicator Getter
  bool get isSeekIndicatorVisible => _isSeekIndicatorVisible; // <<< ADDED THIS GETTER
  Duration get dragSeekTargetPosition => _dragSeekTargetPosition; // <<< ADDED THIS GETTER

  Future<void> _initialize() async {
    if (globals.isPhone) {
      await _setPortrait();
      await _loadInitialBrightness(); // Load initial brightness for phone
      await _loadInitialVolume(); // <<< CALL ADDED
    }
    _startPositionUpdateTimer();
    _setupWindowManagerListener();
    _focusNode.requestFocus();
    KeyboardShortcuts.loadShortcuts();
    await _loadLastVideo();
    await _loadControlBarHeight(); // 加载保存的控制栏高度
    await _loadDanmakuOpacity(); // 加载保存的弹幕透明度
    await _loadDanmakuVisible(); // 加载弹幕可见性
    await _loadMergeDanmaku(); // 加载弹幕合并设置
    await _loadDanmakuStacking(); // 加载弹幕堆叠设置

    // Ensure wakelock is disabled on initialization
    try {
      WakelockPlus.disable();
      //debugPrint("Wakelock disabled on VideoPlayerState initialization.");
    } catch (e) {
      //debugPrint("Error disabling wakelock on init: $e");
    }
  }

  Future<void> _loadInitialBrightness() async {
    if (!globals.isPhone) return;
    try {
      _currentBrightness = await ScreenBrightness().current;
      _initialDragBrightness =
          _currentBrightness; // Initialize drag brightness too
      //debugPrint("Initial screen brightness loaded: $_currentBrightness");
    } catch (e) {
      //debugPrint("Failed to get initial screen brightness: $e");
      // Keep default _currentBrightness if error occurs
    }
    notifyListeners();
  }

  // Load initial system volume (placeholder)
  Future<void> _loadInitialVolume() async {
    if (!globals.isPhone) return;
    try {
      // Get initial volume from the MDK player (0.0 - 1.0 range)
      if (player.volume != null) { 
         _currentVolume = player.volume!; 
      } else {
        _currentVolume = 0.5; 
      }
      _currentVolume = _currentVolume.clamp(0.0, 1.0); // Ensure it's within 0-1 range
      _initialDragVolume = _currentVolume;
      //debugPrint("Initial system volume loaded from player (0-1 range): $_currentVolume");
    } catch (e) {
      //debugPrint("Failed to get initial system volume from player: $e");
      _currentVolume = 0.5; // Fallback
      _initialDragVolume = _currentVolume;
    }
    notifyListeners();
  }

  void startBrightnessDrag() {
    if (!globals.isPhone) return;
    // Refresh _initialDragBrightness with the most up-to-date _currentBrightness
    // This handles cases where brightness might have been changed by other means
    // or if a previous drag was interrupted.
    _initialDragBrightness = _currentBrightness;
    _showBrightnessIndicator();
    debugPrint(
        "Brightness drag started. Initial drag brightness: $_initialDragBrightness");
  }

  Future<void> updateBrightnessOnDrag(
      double verticalDragDelta, BuildContext context) async {
    if (!globals.isPhone) return;

    final screenHeight = MediaQuery.of(context).size.height;
    // 修改灵敏度：拖动屏幕高度的 80% (0.8) 对应亮度从0到1的变化。
    final sensitivityFactor = screenHeight * 0.3; 

    double change = -verticalDragDelta / sensitivityFactor;
    // 使用 _initialDragBrightness 作为基准来计算变化量
    double newBrightness = _initialDragBrightness + change;
    newBrightness = newBrightness.clamp(0.0, 1.0);

    

    try {
      await ScreenBrightness().setScreenBrightness(newBrightness);
      _currentBrightness = newBrightness;
      // 更新 _initialDragBrightness 为当前成功设置的亮度，以确保下次拖拽的起点是连贯的
      _initialDragBrightness = newBrightness; 
      _showBrightnessIndicator(); 
      notifyListeners();
      ////debugPrint("[VideoPlayerState] Brightness updated. Current: $_currentBrightness, InitialDrag: $_initialDragBrightness");
    } catch (e) {
      //debugPrint("Failed to set screen brightness: $e");
    }
  }

  void endBrightnessDrag() {
    if (!globals.isPhone) return;
    // _initialDragBrightness is already updated at the start of the next drag.
    // The indicator will hide via its own timer.
    // No specific action needed here unless we want to immediately save or something.
    debugPrint(
        "Brightness drag ended. Current brightness: $_currentBrightness");
  }

  void _showBrightnessIndicator() {
    if (!globals.isPhone || _context == null) return;

    _isBrightnessIndicatorVisible = true;

    if (_brightnessOverlayEntry == null) {
      _brightnessOverlayEntry = OverlayEntry(
        builder: (context) {
          return ChangeNotifierProvider<VideoPlayerState>.value(
            value: this,
            child: Consumer<VideoPlayerState>(
              builder: (context, videoState, _) {
                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 150),
                  right: videoState.isBrightnessIndicatorVisible ? 20.0 : 0.0, 
                  top: globals.isPhone ? 100.0 : 250.0,
                  bottom: globals.isPhone ? 100.0 : 250.0,
                  // We need to import '../widgets/brightness_indicator.dart'
                  // Assuming it's available, otherwise this will fail.
                  // For the edit tool, I should ensure imports are handled if I introduce new types.
                  // However, BrightnessIndicator is an existing type.
                  child: const BrightnessIndicator(), 
                );
              },
            ),
          );
        },
      );
      Overlay.of(_context!)!.insert(_brightnessOverlayEntry!);
    }
    
    notifyListeners(); 

    _brightnessIndicatorTimer?.cancel();
    _brightnessIndicatorTimer = Timer(const Duration(seconds: 2), () {
      _hideBrightnessIndicator();
    });
    // The final notifyListeners() from the original method is already covered above.
  }

  void _hideBrightnessIndicator() {
    if (!globals.isPhone) return;
    _brightnessIndicatorTimer?.cancel();

    if (_isBrightnessIndicatorVisible) { 
      _isBrightnessIndicatorVisible = false;
      notifyListeners(); 

      Future.delayed(const Duration(milliseconds: 150), () { 
        if (_brightnessOverlayEntry != null) {
          _brightnessOverlayEntry!.remove();
          _brightnessOverlayEntry = null;
        }
      });
    } else {
      if (_brightnessOverlayEntry != null) {
          _brightnessOverlayEntry!.remove();
          _brightnessOverlayEntry = null;
      }
    }
  }

  // Volume Indicator Overlay Methods
  void _showVolumeIndicator() {
    // if (!globals.isPhone || _context == null) return; // 原始判断可能阻止PC
    debugPrint("[VideoPlayerState] _showVolumeIndicator: _context is ${_context == null ? 'null' : 'valid'}, globals.isPhone is ${globals.isPhone}");
    if (_context == null) return; // Context 是必须的

    _isVolumeIndicatorVisible = true; 

    if (_volumeOverlayEntry == null) {
      _volumeOverlayEntry = OverlayEntry(
        builder: (context) {
          return ChangeNotifierProvider<VideoPlayerState>.value(
            value: this,
            child: Consumer<VideoPlayerState>(
              builder: (context, videoState, _) {
                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 150),
                  left: videoState.isVolumeUIVisible ? 35.0 : 0.0, // Position on left, slide out left
                  top: globals.isPhone ? 100.0 : 250.0,
                  bottom: globals.isPhone ? 100.0 : 250.0,
                  child: const VolumeIndicator(), // Uses isVolumeUIVisible internally for opacity
                );
              },
            ),
          );
        },
      );
      Overlay.of(_context!)!.insert(_volumeOverlayEntry!);
    }
    notifyListeners();

    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(seconds: 2), () {
      _hideVolumeIndicator();
    });
  }

  void _hideVolumeIndicator() {
    // if (!globals.isPhone) return; // 原始判断可能阻止PC
    debugPrint("[VideoPlayerState] _hideVolumeIndicator: globals.isPhone is ${globals.isPhone}");

    _volumeIndicatorTimer?.cancel();

    if (_isVolumeIndicatorVisible) {
      _isVolumeIndicatorVisible = false;
      notifyListeners();

      Future.delayed(const Duration(milliseconds: 150), () {
        if (_volumeOverlayEntry != null) {
          _volumeOverlayEntry!.remove();
          _volumeOverlayEntry = null;
        }
      });
    } else {
      if (_volumeOverlayEntry != null) {
        _volumeOverlayEntry!.remove();
        _volumeOverlayEntry = null;
      }
    }
  }

  Future<void> _loadLastVideo() async {
    // 不再自动加载上次视频，让用户手动选择
    return;
  }

  Future<void> _saveLastVideo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastVideoKey, _currentVideoPath ?? '');
    await prefs.setInt(_lastPositionKey, _position.inMilliseconds);
  }

  // 保存视频播放位置
  Future<void> _saveVideoPosition(String path, int position) async {
    final prefs = await SharedPreferences.getInstance();
    final positions = prefs.getString(_videoPositionsKey) ?? '{}';
    final Map<String, dynamic> positionMap =
        Map<String, dynamic>.from(json.decode(positions));
    positionMap[path] = position;
    await prefs.setString(_videoPositionsKey, json.encode(positionMap));
  }

  // 获取视频播放位置
  Future<int> _getVideoPosition(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final positions = prefs.getString(_videoPositionsKey) ?? '{}';
    final Map<String, dynamic> positionMap =
        Map<String, dynamic>.from(json.decode(positions));
    return positionMap[path] ?? 0;
  }

  // 设置横屏
  Future<void> _setLandscape() async {
    debugPrint(
        'VideoPlayerState: _setLandscape CALLED. Current _isFullscreen: $_isFullscreen, globals.isPhone: ${globals.isPhone}');
    if (!globals.isPhone) return;

    try {
      _isFullscreenTransitioning = true;
      notifyListeners();

      // 记录当前播放状态
      final wasPlaying = _status == PlayerStatus.playing;

      // 如果正在播放，先暂停
      if (wasPlaying) {
        player.state = PlaybackState.paused;
      }

      // 先设置支持的方向
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);

      // 等待一小段时间
      await Future.delayed(const Duration(milliseconds: 100));

      // 再设置当前方向
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // 设置全屏模式
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // 等待方向切换完成
      await Future.delayed(const Duration(milliseconds: 500));

      // 重新初始化纹理
      //debugPrint('重新初始化纹理...');
      player.textureId.value = null;
      await Future.delayed(const Duration(milliseconds: 100));
      final textureId = await player.updateTexture();
      //debugPrint('新的纹理ID: $textureId');

      // 如果之前在播放，恢复播放
      if (wasPlaying) {
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing, message: '继续播放');
      }

      _isFullscreen = true;
      _isFullscreenTransitioning = false;
      notifyListeners();
    } catch (e) {
      //debugPrint('横屏切换出错: $e');
      _isFullscreenTransitioning = false;
      // 如果出错，尝试恢复到竖屏
      try {
        await _setPortrait();
      } catch (e2) {
        //debugPrint('恢复竖屏也失败: $e2');
      }
      notifyListeners();
    }
  }

  // 设置竖屏
  Future<void> _setPortrait() async {
    if (!globals.isPhone) return;

    try {
      _isFullscreenTransitioning = true;
      notifyListeners();

      // 记录当前播放状态
      final wasPlaying = _status == PlayerStatus.playing;

      // 如果正在播放，先暂停
      if (wasPlaying) {
        player.state = PlaybackState.paused;
      }

      // 先设置支持的方向
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);

      // 等待一小段时间
      await Future.delayed(const Duration(milliseconds: 100));

      // 再设置当前方向
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      // 恢复系统UI
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // 等待方向切换完成
      await Future.delayed(const Duration(milliseconds: 500));

      // 重新初始化纹理
      //debugPrint('重新初始化纹理...');
      player.textureId.value = null;
      await Future.delayed(const Duration(milliseconds: 100));
      final textureId = await player.updateTexture();
      //debugPrint('新的纹理ID: $textureId');

      // 如果之前在播放，恢复播放
      if (wasPlaying) {
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing, message: '继续播放');
      }

      _isFullscreen = false;
      _isFullscreenTransitioning = false;
      notifyListeners();
    } catch (e) {
      //debugPrint('竖屏切换出错: $e');
      _isFullscreenTransitioning = false;
      notifyListeners();
    }
  }

  Future<void> initializePlayer(String videoPath,
      {WatchHistoryItem? historyItem}) async {
    if (_status == PlayerStatus.loading ||
        _status == PlayerStatus.recognizing) {
      _setStatus(PlayerStatus.idle, message: "取消了之前的加载任务", clearPreviousMessages: true);
    }
    _clearPreviousVideoState(); // 清理旧状态
    _statusMessages.clear(); // <--- 新增行：确保消息列表在开始时是空的

    _currentVideoPath = videoPath;
    print('historyItem: $historyItem');
    _animeTitle = historyItem?.animeName; // 从历史记录获取动画标题
    _episodeTitle = historyItem?.episodeTitle; // 从历史记录获取集数标题
    String message = '正在初始化播放器: ${p.basename(videoPath)}';
    if (_animeTitle != null) {
      message = '正在初始化播放器: $_animeTitle $_episodeTitle';
    }
    _setStatus(PlayerStatus.loading, message: message);
    try {
      debugPrint(
          'VideoPlayerState: initializePlayer CALLED for path: $videoPath');
      //debugPrint('VideoPlayerState: globals.isPhone = ${globals.isPhone}');

      //debugPrint('1. 开始初始化播放器...');
      // 加载保存的token
      await DandanplayService.loadToken();

      _setStatus(PlayerStatus.loading, message: '正在初始化播放器...');
      _error = null;

      //debugPrint('2. 重置播放器状态...');
      // 完全重置播放器
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }
      // 释放旧纹理
      if (player.textureId.value != null) {
        player.textureId.value = null;
      }
      // 等待纹理完全释放
      await Future.delayed(const Duration(milliseconds: 500));
      // 重置播放器状态
      player.media = '';
      await Future.delayed(const Duration(milliseconds: 100));
      _currentVideoPath = null;
      _currentVideoHash = null; // 重置哈希值
      _currentThumbnailPath = null; // 重置缩略图路径
      _position = Duration.zero;
      _duration = Duration.zero;
      _progress = 0.0;
      _error = null;
      _setStatus(PlayerStatus.idle);

      //debugPrint('3. 设置媒体源...');
      // 设置媒体源
      player.media = videoPath;

      //debugPrint('4. 准备播放器...');
      // 准备播放器
      player.prepare();

      //debugPrint('5. 获取视频纹理...');
      // 获取视频纹理
      final textureId = await player.updateTexture();
      //debugPrint('获取到纹理ID: $textureId');

      // 等待纹理初始化完成
      await Future.delayed(const Duration(milliseconds: 200));

      //debugPrint('6. 分析媒体信息...');
      // 分析并打印媒体信息，特别是字幕轨道
      MediaInfoHelper.analyzeMediaInfo(player.mediaInfo);

      // 设置视频宽高比
      if (player.mediaInfo.video != null &&
          player.mediaInfo.video!.isNotEmpty) {
        final videoTrack = player.mediaInfo.video![0];
        if (videoTrack.codec.width > 0 && videoTrack.codec.height > 0) {
          _aspectRatio = videoTrack.codec.width / videoTrack.codec.height;
          //debugPrint('设置视频宽高比: $_aspectRatio');
        }
      }

      // 优先选择包含sm或中文相关的字幕轨道
      if (player.mediaInfo.subtitle != null) {
        final subtitles = player.mediaInfo.subtitle!;
        int? preferredSubtitleIndex;

        // 首先尝试查找包含sm或中文相关的字幕
        for (var i = 0; i < subtitles.length; i++) {
          final track = subtitles[i];
          final fullString = track.toString().toLowerCase();

          // 检查标题中是否包含sm或中文相关关键词
          if (fullString.contains('sm') ||
              fullString.contains('zh') ||
              fullString.contains('chi') ||
              fullString.contains('中文') ||
              fullString.contains('简体') ||
              fullString.contains('繁体')) {
            preferredSubtitleIndex = i;
            break;
          }
        }

        // 如果找到了优先的字幕轨道，就激活它
        if (preferredSubtitleIndex != null) {
          player.activeSubtitleTracks = [preferredSubtitleIndex];
        }
      }

      //debugPrint('7. 更新视频状态...');
      // 更新状态
      _currentVideoPath = videoPath;

      // 异步计算视频哈希值，不阻塞主要初始化流程
      _precomputeVideoHash(videoPath);

      _duration = Duration(milliseconds: player.mediaInfo.duration);

      // 获取上次播放位置
      final lastPosition = await _getVideoPosition(videoPath);
      debugPrint(
          'VideoPlayerState: lastPosition for $videoPath = $lastPosition (raw value from _getVideoPosition)');

      // 如果有上次的播放位置，恢复播放位置
      if (lastPosition > 0) {
        //debugPrint('8. 恢复上次播放位置...');
        // 先设置播放位置
        player.seek(position: lastPosition);
        // 等待一小段时间确保位置设置完成
        await Future.delayed(const Duration(milliseconds: 100));
        // 更新状态
        _position = Duration(milliseconds: lastPosition);
        _progress = lastPosition / _duration.inMilliseconds;
      } else {
        _position = Duration.zero;
        _progress = 0.0;
        player.seek(position: 0);
      }

      //debugPrint('9. 检查播放器实际状态...');
      // 检查播放器实际状态
      if (player.state == PlaybackState.playing) {
        _setStatus(PlayerStatus.playing, message: '正在播放');
      } else {
        // 如果播放器没有真正开始播放，设置为暂停状态
        player.state = PlaybackState.paused;
        _setStatus(PlayerStatus.paused, message: '已暂停');
      }

      // 初始化基础的观看记录（只在没有记录时创建新记录）
      await _initializeWatchHistory(videoPath);

      //debugPrint('10. 开始识别视频和加载弹幕...');
      // 尝试识别视频和加载弹幕
      try {
        await _recognizeVideo(videoPath);
      } catch (e) {
        //debugPrint('弹幕加载失败: $e');
        // 设置空弹幕列表，确保播放不受影响
        _danmakuList = [];
        _addStatusMessage('无法连接服务器，跳过加载弹幕');
      }

      //debugPrint('11. 设置准备就绪状态...');
      // 设置状态为准备就绪
      _setStatus(PlayerStatus.ready, message: '准备就绪');

      // 新逻辑：只要是手机，就尝试设置横屏，在确定播放状态之前
      if (globals.isPhone) {
        debugPrint(
            'VideoPlayerState: Device is phone. Attempting to call _setLandscape PRIOR to setting final playback state.');
        await _setLandscape();
      }

      //debugPrint('12. 设置最终播放状态 (在可能的横屏切换之后)...');
      if (lastPosition == 0) {
        // 从头播放
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing, message: '正在播放 (自动)');
        //debugPrint('VideoPlayerState: Setting to PLAYING (auto from start)');
      } else {
        // 从中间恢复
        // player 已经被 seek 到 lastPosition
        // 检查底层播放器在seek后是否已自行播放，或者我们是否应该强制播放/暂停
        if (player.state == PlaybackState.playing) {
          _setStatus(PlayerStatus.playing, message: '正在播放 (恢复)');
          //debugPrint('VideoPlayerState: Player is ALREADY PLAYING (resumed)');
        } else {
          // 对于恢复播放，可以选择默认播放或暂停。为了确保横屏后视频在动，先尝试设为播放。
          // 如果播放器seek后默认是暂停，并且我们希望它继续播放，则需要下一行。
          player.state = PlaybackState.playing; // 尝试恢复播放
          _setStatus(PlayerStatus.playing, message: '正在播放 (尝试恢复)');
          debugPrint(
              'VideoPlayerState: Attempting to RESUME PLAYING from lastPosition: $lastPosition');
        }
      }

      // 等待一小段时间确保播放器状态稳定
      await Future.delayed(const Duration(milliseconds: 300));

      // 再次检查播放器实际状态并同步 _status
      if (player.state == PlaybackState.playing) {
        if (_status != PlayerStatus.playing) {
          // 如果横屏操作导致状态变化，但最终是播放，则同步
          _setStatus(PlayerStatus.playing, message: '正在播放 (状态确认)');
        }
        //debugPrint('VideoPlayerState: Final check - Player IS PLAYING.');
      } else {
        debugPrint(
            'VideoPlayerState: Final check - Player IS NOT PLAYING. Current _status: $_status, player.state: ${player.state}');
        // 如果意图是播放 (无论是从头还是恢复)，但播放器最终没有播放，则设为暂停
        if (_status == PlayerStatus.playing) {
          // 如果我们之前的意图是播放
          player.state = PlaybackState.paused;
          _setStatus(PlayerStatus.paused, message: '已暂停 (播放失败后同步)');
          debugPrint(
              'VideoPlayerState: Corrected to PAUSED (sync after play attempt failed)');
        } else if (_status != PlayerStatus.paused) {
          // 对于其他非播放且非暂停的意外状态，也强制为暂停
          player.state = PlaybackState.paused;
          _setStatus(PlayerStatus.paused, message: '已暂停 (状态同步)');
          //debugPrint('VideoPlayerState: Corrected to PAUSED (general sync)');
        }
      }
    } catch (e) {
      //debugPrint('初始化视频播放器时出错: $e');
      _error = '初始化视频播放器时出错: $e';
      _setStatus(PlayerStatus.error, message: '播放器初始化失败');
      // 尝试恢复
      _tryRecoverFromError();
    }
  }

  // 预先计算视频哈希值
  Future<void> _precomputeVideoHash(String path) async {
    try {
      //debugPrint('开始计算视频哈希值...');
      _currentVideoHash = await _calculateFileHash(path);
      //debugPrint('视频哈希值计算完成: $_currentVideoHash');
    } catch (e) {
      //debugPrint('计算视频哈希值失败: $e');
      // 失败时将哈希值设为null，让后续操作重新计算
      _currentVideoHash = null;
    }
  }

  // 初始化观看记录
  Future<void> _initializeWatchHistory(String path) async {
    try {
      // 先检查是否已存在观看记录
      final existingHistory = await WatchHistoryManager.getHistoryItem(path);

      if (existingHistory != null) {
        // 如果已存在记录，只更新播放进度和时间相关信息，不更改动画信息
        debugPrint(
            '已有观看记录存在，只更新播放进度: 动画=${existingHistory.animeName}, 集数=${existingHistory.episodeTitle}');

        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: existingHistory.animeName,
          episodeTitle: existingHistory.episodeTitle,
          episodeId: existingHistory.episodeId,
          animeId: existingHistory.animeId,
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: existingHistory.thumbnailPath,
        );

        await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
        if (_context != null && _context!.mounted) {
          _context!.read<WatchHistoryProvider>().refresh();
        }
        return;
      }

      // 只有在没有现有记录时才创建全新记录
      final fileName = path.split('/').last;

      // 尝试从文件名中提取更好的初始动画名称
      String initialAnimeName = fileName;

      // 移除常见的文件扩展名
      initialAnimeName = initialAnimeName.replaceAll(
          RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$', caseSensitive: false), '');

      // 替换下划线、点和破折号为空格
      initialAnimeName =
          initialAnimeName.replaceAll(RegExp(r'[_\.-]'), ' ').trim();

      // 如果处理后为空，则给一个默认值
      if (initialAnimeName.isEmpty) {
        initialAnimeName = "未知动画";
      }

      // 创建初始观看记录
      final item = WatchHistoryItem(
        filePath: path,
        animeName: initialAnimeName,
        lastPosition: _position.inMilliseconds,
        duration: _duration.inMilliseconds,
        watchProgress: _progress,
        lastWatchTime: DateTime.now(),
      );

      //debugPrint('创建全新的观看记录: 动画=${item.animeName}');
      // 保存到历史记录
      await WatchHistoryManager.addOrUpdateHistory(item);
      if (_context != null && _context!.mounted) {
        _context!.read<WatchHistoryProvider>().refresh();
      }
    } catch (e, s) {
      //debugPrint('初始化观看记录时出错: $e\n$s');
    }
  }

  Future<void> resetPlayer() async {
    try {
      // 在停止播放前保存最后的观看记录
      if (_currentVideoPath != null) {
        await _updateWatchHistory();
      }

      // 先停止播放
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }

      // 等待一小段时间确保播放器完全停止
      await Future.delayed(const Duration(milliseconds: 100));

      // 释放纹理，确保资源被正确释放
      if (player.textureId.value != null) {
        // 强制转换为null前，先解除与Flutter部分的绑定
        _disposeTextureResources();
        // 释放播放器持有的纹理
        player.textureId.value = null;
      }

      // 等待一小段时间确保纹理完全释放
      await Future.delayed(const Duration(milliseconds: 200));

      // 重置状态
      _currentVideoPath = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _progress = 0.0;
      _error = null;
      _setStatus(PlayerStatus.idle);

      // 在手机平台上恢复竖屏
      if (globals.isPhone) {
        await _setPortrait();
      }
    } catch (e) {
      //debugPrint('重置播放器时出错: $e');
      rethrow;
    }
  }

  // 帮助释放纹理资源
  void _disposeTextureResources() {
    try {
      // 清空可能的缓冲内容
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }

      // 设置空媒体源，释放当前媒体相关资源
      player.media = '';

      // 通知垃圾回收
      if (Platform.isIOS || Platform.isMacOS) {
        Future.delayed(const Duration(milliseconds: 50), () {
          // 在iOS/macOS上可能需要额外步骤来释放资源
          player.media = '';
        });
      }
    } catch (e) {
      //debugPrint('释放纹理资源时出错: $e');
    }
  }

  void _setStatus(PlayerStatus newStatus,
      {String? message, bool clearPreviousMessages = false}) {
    if (clearPreviousMessages) {
      _statusMessages.clear();
    }
    if (message != null && message.isNotEmpty) {
      _statusMessages.add(message);
      // Optionally, limit the number of messages stored
      // if (_statusMessages.length > 10) {
      //   _statusMessages.removeAt(0);
      // }
    }

    _status = newStatus;

    // Wakelock logic
    if (_status == PlayerStatus.playing) {
      try {
        WakelockPlus.enable();
        ////debugPrint("Wakelock enabled: Playback started/resumed.");
      } catch (e) {
        ////debugPrint("Error enabling wakelock: $e");
      }
    } else {
      // Disable for any other status (paused, error, idle, disposed, ready, loading, recognizing)
      try {
        WakelockPlus.disable();
        ////debugPrint("Wakelock disabled. Status: $_status");
      } catch (e) {
        ////debugPrint("Error disabling wakelock: $e");
      }
    }

    notifyListeners();
  }

  void togglePlayPause() {
    if (_status == PlayerStatus.playing) {
      pause();
    } else {
      play();
    }
  }

  void pause() {
    if (_status == PlayerStatus.playing) {
      player.state = PlaybackState.paused;
      _setStatus(PlayerStatus.paused, message: '已暂停');
      _saveCurrentPositionToHistory();
      // WakelockPlus.disable(); // Already handled by _setStatus
    }
  }

  void play() {
    if (hasVideo &&
        (_status == PlayerStatus.paused || _status == PlayerStatus.ready)) {
      player.state = PlaybackState.playing;
      _setStatus(PlayerStatus.playing, message: '开始播放');
      // _resetHideControlsTimer(); // Temporarily commented out as the method name is uncertain.
      // Please provide the correct method if you want to show controls on play.
    }
  }

  Future<void> stop() async {
    if (_status != PlayerStatus.idle && _status != PlayerStatus.disposed) {
      _setStatus(PlayerStatus.idle, message: '播放已停止');
      _positionUpdateTimer?.cancel();
      player.state = PlaybackState.stopped; // Changed from player.stop()
      _resetVideoState();
    }
  }

  void _clearPreviousVideoState() {
    _currentVideoPath = null;
    _currentVideoHash = null;
    _currentThumbnailPath = null;
    _animeTitle = null;
    _episodeTitle = null;
    _danmakuList.clear();
    clearDanmakuTrackInfo();
    danmakuController
        ?.dispose(); // Assuming danmakuController has a dispose method
    danmakuController = null;
    _duration = Duration.zero;
    _position = Duration.zero;
    _progress = 0.0;
    _error = null;
    // Do NOT call WakelockPlus.disable() here directly, _setStatus will handle it
  }

  void _saveCurrentPositionToHistory() {
    if (_currentVideoPath != null) {
      _saveVideoPosition(_currentVideoPath!, _position.inMilliseconds);
    }
  }

  void _resetVideoState() {
    _position = Duration.zero;
    _progress = 0.0;
    _duration = Duration.zero;
    _error = null;
    _currentVideoPath = null;
    _currentVideoHash = null;
    _currentThumbnailPath = null;
    _animeTitle = null;
    _episodeTitle = null;
    _danmakuList.clear();
    clearDanmakuTrackInfo();
    danmakuController
        ?.dispose(); // Assuming danmakuController has a dispose method
    danmakuController = null;
    _videoDuration = Duration.zero;
  }

  void seekTo(Duration position) {
    if (!hasVideo) return;

    try {
      _isSeeking = true;
      bool wasPlayingBeforeSeek = _status == PlayerStatus.playing; // 记录当前播放状态

      // 确保位置在有效范围内（0 到视频总时长）
      Duration clampedPosition = Duration(
          milliseconds:
              position.inMilliseconds.clamp(0, _duration.inMilliseconds));

      // 如果是暂停状态，先恢复播放
      if (_status == PlayerStatus.paused) {
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing);
      }

      // 立即更新UI状态
      _position = clampedPosition;
      if (_duration.inMilliseconds > 0) {
        _progress = clampedPosition.inMilliseconds / _duration.inMilliseconds;
      }
      notifyListeners();

      // 更新播放器位置
      player.seek(position: clampedPosition.inMilliseconds);

      // 延迟结束seeking状态，并在需要时恢复暂停
      Future.delayed(const Duration(milliseconds: 100), () {
        _isSeeking = false;
        // 如果之前是暂停状态，恢复暂停
        if (!wasPlayingBeforeSeek && _status == PlayerStatus.playing) {
          player.state = PlaybackState.paused;
          _setStatus(PlayerStatus.paused);
        }
      });
    } catch (e) {
      //debugPrint('跳转时出错 (已静默处理): $e');
      _error = '跳转时出错: $e';
      _setStatus(PlayerStatus.idle);
      _isSeeking = false;
    }
  }

  void resetAutoHideTimer() {
    _autoHideTimer?.cancel();
    if (hasVideo && _showControls && !_isControlsHovered) {
      _autoHideTimer = Timer(const Duration(seconds: 5), () {
        if (!_isControlsHovered) {
          setShowControls(false);
        }
      });
    }
  }

  void setControlsHovered(bool value) {
    _isControlsHovered = value;
    if (value) {
      _hideControlsTimer?.cancel();
      _hideMouseTimer?.cancel();
      _autoHideTimer?.cancel();
      setShowControls(true);
    } else {
      resetHideControlsTimer();
      resetAutoHideTimer();
    }
  }

  void resetHideMouseTimer() {
    _hideMouseTimer?.cancel();
    if (hasVideo && !_isControlsHovered && !globals.isPhone) {
      _hideMouseTimer = Timer(const Duration(milliseconds: 1500), () {
        setShowControls(false);
      });
    }
  }

  void resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    setShowControls(true);
    if (hasVideo && !_isControlsHovered && !globals.isPhone) {
      _hideControlsTimer = Timer(const Duration(milliseconds: 1500), () {
        setShowControls(false);
      });
    }
  }

  void handleMouseMove(Offset position) {
    if (!_isControlsHovered && !globals.isPhone) {
      resetHideControlsTimer();
      resetHideMouseTimer();
    }
  }

  void toggleControls() {
    setShowControls(!_showControls);
    if (_showControls && hasVideo && !_isControlsHovered) {
      resetHideControlsTimer();
      resetAutoHideTimer();
    }
  }

  void setShowControls(bool value) {
    _showControls = value;
    if (value) {
      resetAutoHideTimer();
    } else {
      _autoHideTimer?.cancel();
    }
    notifyListeners();
  }

  void _startPositionUpdateTimer() {
    _positionUpdateTimer =
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_isSeeking && hasVideo) {
        if (_status == PlayerStatus.playing) {
          // 播放状态：从播放器获取位置
          _position = Duration(milliseconds: player.position);
          _duration = Duration(milliseconds: player.mediaInfo.duration);
          if (_duration.inMilliseconds > 0) {
            _progress = _position.inMilliseconds / _duration.inMilliseconds;
            // 保存当前播放位置
            _saveVideoPosition(_currentVideoPath!, _position.inMilliseconds);

            // 更新观看记录 - 每秒更新一次，避免频繁写入
            if (_position.inMilliseconds % 1000 < 20) {
              _updateWatchHistory();
            }

            // 检查是否播放结束
            if (_position.inMilliseconds >= _duration.inMilliseconds - 100) {
              // 播放结束，暂停播放器并跳转到开头
              player.state = PlaybackState.paused;
              _setStatus(PlayerStatus.paused, message: '播放结束');

              // 跳转到视频开头
              //seekTo(Duration.zero);

              // 更新状态以反映跳转后的位置
              //_position = Duration.zero;
              //_progress = 0.0;
              // 确保立即用0值保存，覆盖任何之前的播放位置
              if (_currentVideoPath != null) {
                _saveVideoPosition(_currentVideoPath!, 0);
                debugPrint(
                    'VideoPlayerState: Video ended, explicitly saved position 0 for $_currentVideoPath');
              }
              notifyListeners();
              // 可以在这里考虑停止 positionUpdateTimer，如果需要的话
              // _positionUpdateTimer?.cancel();
            }
          }
          _lastSeekPosition = null; // 清除最后seek位置
          notifyListeners();
        } else if (_status == PlayerStatus.paused &&
            _lastSeekPosition != null) {
          // 暂停状态：使用最后一次seek的位置
          _position = _lastSeekPosition!;
          if (_duration.inMilliseconds > 0) {
            _progress = _position.inMilliseconds / _duration.inMilliseconds;
            // 保存当前播放位置
            _saveVideoPosition(_currentVideoPath!, _position.inMilliseconds);

            // 暂停状态下，只在位置变化时更新观看记录
            _updateWatchHistory();
          }
          notifyListeners();
        }
      }
    });
  }

  bool shouldShowAppBar() {
    if (globals.isPhone) {
      return !hasVideo || !_isFullscreen;
    }
    return !_isFullscreen;
  }

  @override
  void dispose() {
    player.dispose();
    _positionUpdateTimer?.cancel();
    _hideControlsTimer?.cancel();
    _hideMouseTimer?.cancel();
    _focusNode.dispose();
    _screenshotTimer?.cancel();
    _brightnessIndicatorTimer?.cancel(); // Already cancelled here or in _hideBrightnessIndicator
    if (_brightnessOverlayEntry != null) { // ADDED THIS BLOCK
      _brightnessOverlayEntry!.remove();
      _brightnessOverlayEntry = null;
    }
    _volumeIndicatorTimer?.cancel(); // <<< ADDED
    if (_volumeOverlayEntry != null) { // <<< ADDED
      _volumeOverlayEntry!.remove();
      _volumeOverlayEntry = null;
    }
    _seekIndicatorTimer?.cancel(); // <<< ADDED
    if (_seekOverlayEntry != null) { // <<< ADDED
      _seekOverlayEntry!.remove();
      _seekOverlayEntry = null;
    }
    WakelockPlus.disable();
    //debugPrint("Wakelock disabled on dispose.");
    windowManager.removeListener(this);
    super.dispose();
  }

  // 设置窗口管理器监听器
  void _setupWindowManagerListener() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'enter-full-screen' || eventName == 'leave-full-screen') {
      windowManager.isFullScreen().then((isFullscreen) {
        if (isFullscreen != _isFullscreen) {
          _isFullscreen = isFullscreen;
          notifyListeners();
        }
      });
    }
  }

  @override
  void onWindowEnterFullScreen() {
    windowManager.isFullScreen().then((isFullscreen) {
      if (isFullscreen != _isFullscreen) {
        _isFullscreen = isFullscreen;
        notifyListeners();
      }
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    windowManager.isFullScreen().then((isFullscreen) {
      if (!isFullscreen && _isFullscreen) {
        _isFullscreen = false;
        notifyListeners();
      }
    });
  }

  @override
  void onWindowBlur() {}

  @override
  void onWindowClose() async {
    // Changed from onWindowClose() async
    //debugPrint("VideoPlayerState: onWindowClose called. Saving position.");
    _saveCurrentPositionToHistory(); // Removed await as the method likely returns void
  }

  @override
  void onWindowDocked() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowMoved() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowResized() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowUnDocked() {}

  @override
  void onWindowUndocked() {}

  @override
  void onWindowUnmaximize() {}

  // 切换全屏状态（仅用于桌面平台）
  Future<void> toggleFullscreen() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    if (_isFullscreenTransitioning) return;

    _isFullscreenTransitioning = true;
    try {
      if (!_isFullscreen) {
        await windowManager.setFullScreen(true);
        _isFullscreen = true;
      } else {
        await windowManager.setFullScreen(false);
        _isFullscreen = false;
        // 确保返回到主页面
        if (_context != null) {
          Navigator.of(_context!).popUntil((route) => route.isFirst);
        }
      }

      notifyListeners();
    } finally {
      _isFullscreenTransitioning = false;
    }
  }

  // 设置上下文
  void setContext(BuildContext context) {
    _context = context;
  }

  // 更新状态消息的方法
  void _updateStatusMessages(List<String> messages) {
    _statusMessages = messages;
    notifyListeners();
  }

  // 添加单个状态消息的方法
  void _addStatusMessage(String message) {
    _statusMessages.add(message);
    notifyListeners();
  }

  // 清除所有状态消息的方法
  void _clearStatusMessages() {
    _statusMessages.clear();
    notifyListeners();
  }

  Future<void> _recognizeVideo(String videoPath) async {
    try {
      //debugPrint('开始识别视频...');
      _setStatus(PlayerStatus.recognizing, message: '正在识别视频...');

      // 使用超时处理网络请求
      try {
        //debugPrint('尝试获取视频信息...');
        final videoInfo = await DandanplayService.getVideoInfo(videoPath)
            .timeout(const Duration(seconds: 15), onTimeout: () {
          //debugPrint('获取视频信息超时');
          throw TimeoutException('连接服务器超时');
        });

        if (videoInfo['isMatched'] == true) {
          //debugPrint('视频匹配成功，开始加载弹幕...');
          _setStatus(PlayerStatus.recognizing, message: '视频识别成功，正在加载弹幕...');

          // 更新观看记录的动画和集数信息
          await _updateWatchHistoryWithVideoInfo(videoPath, videoInfo);

          if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
            final match = videoInfo['matches'][0];
            if (match['episodeId'] != null && match['animeId'] != null) {
              try {
                //debugPrint('尝试加载弹幕...');
                _setStatus(PlayerStatus.recognizing, message: '正在加载弹幕...');
                final episodeId = match['episodeId'].toString();
                final animeId = match['animeId'] as int;

                // 从缓存加载弹幕
                //debugPrint('检查弹幕缓存...');
                final cachedDanmakuRaw =
                    await DanmakuCacheManager.getDanmakuFromCache(episodeId);
                if (cachedDanmakuRaw != null) {
                  //debugPrint('从缓存加载弹幕...');
                  _setStatus(PlayerStatus.recognizing, message: '正在从缓存解析弹幕...');
                  _danmakuList = await compute(parseDanmakuListInBackground,
                      cachedDanmakuRaw as List<dynamic>?);

                  // Sort the list immediately after parsing
                  _danmakuList.sort((a, b) {
                    final timeA = (a['time'] as double?) ?? 0.0;
                    final timeB = (b['time'] as double?) ?? 0.0;
                    return timeA.compareTo(timeB);
                  });
                  //debugPrint('缓存弹幕解析并排序完成');

                  notifyListeners();
                  _setStatus(PlayerStatus.recognizing,
                      message: '从缓存加载弹幕完成 (${_danmakuList.length}条)');
                  return; // Return early after loading from cache
                }

                //debugPrint('从网络加载弹幕...');
                // 从网络加载弹幕
                final danmakuData =
                    await DandanplayService.getDanmaku(episodeId, animeId)
                        .timeout(const Duration(seconds: 15), onTimeout: () {
                  //debugPrint('加载弹幕超时');
                  throw TimeoutException('加载弹幕超时');
                });

                _setStatus(PlayerStatus.recognizing, message: '正在解析网络弹幕...');
                if (danmakuData['comments'] != null &&
                    danmakuData['comments'] is List) {
                  // Use compute for parsing network danmaku, using the imported function
                  _danmakuList = await compute(parseDanmakuListInBackground,
                      danmakuData['comments'] as List<dynamic>?);

                  // Sort the list immediately after parsing
                  _danmakuList.sort((a, b) {
                    final timeA = (a['time'] as double?) ?? 0.0;
                    final timeB = (b['time'] as double?) ?? 0.0;
                    return timeA.compareTo(timeB);
                  });
                  //debugPrint('网络弹幕解析并排序完成');
                } else {
                  _danmakuList = [];
                }

                notifyListeners();
                _setStatus(PlayerStatus.recognizing,
                    message: '弹幕加载完成 (${_danmakuList.length}条)');
              } catch (e, s) {
                //debugPrint('弹幕加载/解析错误: $e\n$s');
                _danmakuList = [];
                _setStatus(PlayerStatus.recognizing, message: '弹幕加载失败，跳过');
              }
            }
          }
        } else {
          //debugPrint('视频未匹配到信息');
          _danmakuList = [];
          _setStatus(PlayerStatus.recognizing, message: '未匹配到视频信息，跳过弹幕');
        }
      } catch (e, s) {
        //debugPrint('视频识别网络错误: $e\n$s');
        _danmakuList = [];
        _setStatus(PlayerStatus.recognizing, message: '无法连接服务器，跳过加载弹幕');
      }
    } catch (e, s) {
      //debugPrint('识别视频或加载弹幕时发生严重错误: $e\n$s');
      rethrow;
    }
  }

  // 根据视频识别信息更新观看记录
  Future<void> _updateWatchHistoryWithVideoInfo(
      String path, Map<String, dynamic> videoInfo) async {
    try {
      //debugPrint('更新观看记录开始，视频路径: $path');
      // 获取现有记录
      final existingHistory = await WatchHistoryManager.getHistoryItem(path);
      if (existingHistory == null) {
        //debugPrint('未找到现有观看记录，跳过更新');
        return;
      }

      // 打印完整的视频信息以便调试
      //////debugPrint('视频信息: ${json.encode(videoInfo)}');

      // 获取识别到的动画信息
      String? apiAnimeName; // 从 videoInfo 或其 matches 中获取
      String? episodeTitle;
      int? animeId, episodeId;

      // 从videoInfo直接读取animeTitle和episodeTitle
      apiAnimeName = videoInfo['animeTitle'] as String?;
      episodeTitle = videoInfo['episodeTitle'] as String?;

      // 从匹配信息中获取animeId和episodeId
      if (videoInfo['matches'] != null &&
          videoInfo['matches'] is List &&
          videoInfo['matches'].isNotEmpty) {
        final match = videoInfo['matches'][0];
        // 如果直接字段为空，且匹配中有值，则使用匹配中的值
        if ((apiAnimeName == null || apiAnimeName.isEmpty) &&
            match['animeTitle'] != null) {
          apiAnimeName = match['animeTitle'] as String?;
        }

        episodeId = match['episodeId'] as int?;
        animeId = match['animeId'] as int?;
      }

      // 解析最终的 animeName，确保非空
      String resolvedAnimeName;
      if (apiAnimeName != null && apiAnimeName.isNotEmpty) {
        resolvedAnimeName = apiAnimeName;
      } else {
        // 如果 API 未提供有效名称，则使用现有记录中的名称，
        // 如果现有记录中的名称也为空（理论上不应发生，因为它是 String 类型），
        // 则最后从文件名保底。
        resolvedAnimeName =
            existingHistory.animeName; // existingHistory.animeName 是 String 类型
      }

      // 如果仍然没有动画名称（例如 existingHistory.animeName 为空字符串，虽然不太可能），从文件名提取
      if (resolvedAnimeName.isEmpty) {
        final fileName = path.split('/').last;
        String extractedName = fileName.replaceAll(
            RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$', caseSensitive: false), '');
        extractedName = extractedName.replaceAll(RegExp(r'[_\.-]'), ' ');
        resolvedAnimeName = extractedName.trim().isNotEmpty
            ? extractedName
            : "未知动画"; // 确保不会是空字符串
      }

      debugPrint(
          '识别到动画：$resolvedAnimeName，集数：${episodeTitle ?? '未知集数'}，animeId: $animeId, episodeId: $episodeId');

      // 更新当前动画标题和集数标题
      _animeTitle = resolvedAnimeName; // 使用 resolvedAnimeName
      _episodeTitle = episodeTitle;

      // 如果仍在加载/识别状态，并且成功识别出动画标题，则更新状态消息
        // _statusMessages.clear(); // 清除之前的加载消息 (L1579) - 注释掉这行以进行测试
        debugPrint('更新观看记录: $_animeTitle'); // (L1580)
        String message = '正在加载: $_animeTitle'; // (L1582)
        if (_episodeTitle != null && _episodeTitle!.isNotEmpty) {
          message += ' - $_episodeTitle';
        }
        // 直接设置状态和消息，但不改变PlayerStatus本身，除非需要
        // 这里我们假设 PlayerStatus.loading 或 PlayerStatus.recognizing 仍然是合适的状态
        _setStatus(_status, message: message);

      notifyListeners();

      // 创建更新后的观看记录
      final updatedHistory = WatchHistoryItem(
        filePath: existingHistory.filePath,
        animeName: resolvedAnimeName, // 使用确保非空的 resolvedAnimeName
        episodeTitle: (episodeTitle != null && episodeTitle.isNotEmpty)
            ? episodeTitle
            : existingHistory.episodeTitle,
        episodeId: episodeId ?? existingHistory.episodeId,
        animeId: animeId ?? existingHistory.animeId,
        watchProgress: existingHistory.watchProgress,
        lastPosition: existingHistory.lastPosition,
        duration: existingHistory.duration,
        lastWatchTime: existingHistory.lastWatchTime, // 保留上次观看时间，直到真正播放并更新进度
        thumbnailPath: existingHistory.thumbnailPath,
      );

      debugPrint(
          '准备保存更新后的观看记录，动画名: ${updatedHistory.animeName}, 集数: ${updatedHistory.episodeTitle}');
      // 保存更新后的记录
      await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
      if (_context != null && _context!.mounted) {
        // 添加 mounted 检查
        _context!.read<WatchHistoryProvider>().refresh();
      }
      //debugPrint('成功更新观看记录');
    } catch (e, s) {
      // 添加 stackTrace
      //debugPrint('更新观看记录时出错: $e\n$s'); // 打印堆栈信息
      // 错误不应阻止视频播放
    }
  }

  // 计算文件前16MB数据的MD5哈希值
  Future<String> _calculateFileHash(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('文件不存在: $filePath');
      }

      const int maxBytes = 16 * 1024 * 1024; // 16MB
      final bytes =
          await file.openRead(0, maxBytes).expand((chunk) => chunk).toList();
      return md5.convert(bytes).toString();
    } catch (e) {
      //debugPrint('计算文件哈希值失败: $e');
      // 返回一个基于文件名的备用哈希值
      return md5.convert(utf8.encode(filePath.split('/').last)).toString();
    }
  }

  // 添加缩略图更新监听器
  void addThumbnailUpdateListener(VoidCallback listener) {
    if (!_thumbnailUpdateListeners.contains(listener)) {
      _thumbnailUpdateListeners.add(listener);
    }
  }

  // 移除缩略图更新监听器
  void removeThumbnailUpdateListener(VoidCallback listener) {
    _thumbnailUpdateListeners.remove(listener);
  }

  // 通知所有缩略图更新监听器
  void _notifyThumbnailUpdateListeners() {
    for (final listener in _thumbnailUpdateListeners) {
      try {
        listener();
      } catch (e) {
        //debugPrint('缩略图更新监听器执行错误: $e');
      }
    }
  }

  // 立即更新观看记录中的缩略图
  Future<void> _updateWatchHistoryWithNewThumbnail(String thumbnailPath) async {
    if (_currentVideoPath == null) return;

    try {
      // 获取当前播放记录
      final existingHistory =
          await WatchHistoryManager.getHistoryItem(_currentVideoPath!);

      if (existingHistory != null) {
        // 仅更新缩略图和时间戳，保留其他所有字段
        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: existingHistory
              .animeName, // existingHistory.animeName 应该是可靠的 String
          episodeTitle: existingHistory.episodeTitle,
          episodeId: existingHistory.episodeId,
          animeId: existingHistory.animeId,
          watchProgress: _progress, // 更新当前进度
          lastPosition: _position.inMilliseconds, // 更新当前位置
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
        );

        await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
        if (_context != null && _context!.mounted) {
          // 添加 mounted 检查
          _context!.read<WatchHistoryProvider>().refresh();
        }
        ////debugPrint('观看记录缩略图已更新: $thumbnailPath');

        // 通知缩略图已更新，需要刷新UI
        _notifyThumbnailUpdateListeners();

        // 尝试刷新已显示的缩略图
        _triggerImageCacheRefresh(thumbnailPath);
      }
    } catch (e, s) {
      // 添加 stackTrace
      //debugPrint('更新观看记录缩略图时出错: $e\n$s'); // 打印堆栈信息
    }
  }

  // 触发图片缓存刷新，使新缩略图可见
  void _triggerImageCacheRefresh(String imagePath) {
    try {
      // 从图片缓存中移除该图片
      ////debugPrint('刷新图片缓存: $imagePath');
      // 清除特定图片的缓存
      final file = File(imagePath);
      if (file.existsSync()) {
        // 1. 先获取文件URI
        final uri = Uri.file(imagePath);
        // 2. 从缓存中驱逐此图像
        PaintingBinding.instance.imageCache.evict(FileImage(file));
        // 3. 也清除以NetworkImage方式缓存的图像
        PaintingBinding.instance.imageCache.evict(NetworkImage(uri.toString()));
        ////debugPrint('图片缓存已刷新');
      }
    } catch (e) {
      //debugPrint('刷新图片缓存失败: $e');
    }
  }

  // 启动截图定时器 - 每5秒截取一次视频帧
  void _startScreenshotTimer() {
    _stopScreenshotTimer(); // 先停止现有定时器

    if (_currentVideoPath != null && hasVideo) {
      _screenshotTimer =
          Timer.periodic(const Duration(seconds: 5), (timer) async {
        if (_status == PlayerStatus.playing && !_isCapturingFrame) {
          _isCapturingFrame = true; // 设置标志，防止并发截图
          try {
            // 使用异步操作减少主线程阻塞
            final newThumbnailPath =
                await Future(() => _captureVideoFrameWithoutPausing());

            if (newThumbnailPath != null) {
              _currentThumbnailPath = newThumbnailPath;
              ////debugPrint('5秒定时截图完成: $_currentThumbnailPath');

              // 立即更新观看记录中的缩略图
              await _updateWatchHistoryWithNewThumbnail(newThumbnailPath);
            }
          } catch (e) {
            //debugPrint('定时截图失败: $e');
          } finally {
            _isCapturingFrame = false; // 重置标志
          }
        }
      });
      ////debugPrint('启动5秒定时截图');
    }
  }

  // 停止截图定时器
  void _stopScreenshotTimer() {
    if (_screenshotTimer != null) {
      _screenshotTimer!.cancel();
      _screenshotTimer = null;
      ////debugPrint('停止定时截图');
    }
  }

  // 不暂停视频的截图方法
  Future<String?> _captureVideoFrameWithoutPausing() async {
    if (_currentVideoPath == null || !hasVideo) return null;

    try {
      // 计算保持原始宽高比的图像尺寸
      const int targetHeight = 256;
      int targetWidth = 256; // 默认值

      // 从视频媒体信息获取宽高比
      if (player.mediaInfo.video != null &&
          player.mediaInfo.video!.isNotEmpty) {
        final videoTrack = player.mediaInfo.video![0];
        if (videoTrack.codec.width > 0 && videoTrack.codec.height > 0) {
          final aspectRatio = videoTrack.codec.width / videoTrack.codec.height;
          targetWidth = (targetHeight * aspectRatio).round();
        }
      }

      // 使用Player的snapshot方法获取当前帧，保持宽高比，但不暂停视频
      final videoFrame =
          await player.snapshot(width: targetWidth, height: targetHeight);
      if (videoFrame == null) {
        return null;
      }

      // 直接使用image包将RGBA数据转换为PNG
      try {
        // 从RGBA字节数据创建图像
        final image = img.Image.fromBytes(
          width: targetWidth,
          height: targetHeight,
          bytes: videoFrame.buffer,
          numChannels: 4, // RGBA
        );

        // 编码为PNG格式
        final pngBytes = img.encodePng(image);

        // 使用缓存的哈希值或重新计算哈希值
        String videoFileHash;
        if (_currentVideoHash != null) {
          videoFileHash = _currentVideoHash!;
        } else {
          videoFileHash = await _calculateFileHash(_currentVideoPath!);
          _currentVideoHash = videoFileHash; // 缓存哈希值
        }

        // 创建缩略图目录
        final appDir = await getApplicationDocumentsDirectory();
        final thumbnailDir = Directory('${appDir.path}/thumbnails');
        if (!thumbnailDir.existsSync()) {
          thumbnailDir.createSync(recursive: true);
        }

        // 保存缩略图文件
        final thumbnailPath = '${thumbnailDir.path}/$videoFileHash.png';
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile.writeAsBytes(pngBytes);

        return thumbnailPath;
      } catch (e) {
        //debugPrint('处理图像数据时出错: $e');
        return null;
      }
    } catch (e) {
      //debugPrint('无暂停截图时出错: $e');
      return null;
    }
  }

  // 设置错误状态
  void _setError(String error) {
    //debugPrint('视频播放错误: $error');
    _error = error;
    _status = PlayerStatus.error;

    // 添加错误消息
    _statusMessages = ['播放出错，正在尝试恢复...'];
    notifyListeners();

    // 尝试恢复播放
    _tryRecoverFromError();
  }

  Future<void> _tryRecoverFromError() async {
    try {
      // 如果处于横屏状态，先切回竖屏
      if (_isFullscreen && globals.isPhone) {
        await _setPortrait();
      }

      // 重置播放器状态
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }

      // 如果有当前视频路径，尝试重新初始化
      if (_currentVideoPath != null) {
        final path = _currentVideoPath!;
        _currentVideoPath = null; // 清空路径，避免重复初始化
        await Future.delayed(const Duration(seconds: 1)); // 等待一秒
        await initializePlayer(path);
      } else {
        _setStatus(PlayerStatus.idle, message: '请重新选择视频');
      }
    } catch (e) {
      //debugPrint('恢复播放失败: $e');
      _setStatus(PlayerStatus.idle, message: '播放器恢复失败，请重新选择视频');
    }
  }

  // 加载控制栏高度
  Future<void> _loadControlBarHeight() async {
    final prefs = await SharedPreferences.getInstance();
    _controlBarHeight = prefs.getDouble(_controlBarHeightKey) ?? 20.0;
    notifyListeners();
  }

  // 保存控制栏高度
  Future<void> setControlBarHeight(double height) async {
    _controlBarHeight = height;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_controlBarHeightKey, height);
    notifyListeners();
  }

  // 加载弹幕透明度
  Future<void> _loadDanmakuOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakuOpacity = prefs.getDouble(_danmakuOpacityKey) ?? 1.0;
    notifyListeners();
  }

  // 保存弹幕透明度
  Future<void> setDanmakuOpacity(double opacity) async {
    _danmakuOpacity = opacity;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_danmakuOpacityKey, opacity);
    notifyListeners();
  }

  // 获取映射后的弹幕不透明度
  double get mappedDanmakuOpacity {
    // 使用平方函数进行映射，使低值区域变化更平缓
    return _danmakuOpacity * _danmakuOpacity;
  }

  // 加载弹幕可见性
  Future<void> _loadDanmakuVisible() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakuVisible = prefs.getBool(_danmakuVisibleKey) ?? true;
    notifyListeners();
  }

  void setDanmakuVisible(bool visible) async {
    if (_danmakuVisible != visible) {
      _danmakuVisible = visible;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_danmakuVisibleKey, visible);
      notifyListeners();
    }
  }

  void toggleDanmakuVisible() {
    setDanmakuVisible(!_danmakuVisible);
  }

  // 加载弹幕合并设置
  Future<void> _loadMergeDanmaku() async {
    final prefs = await SharedPreferences.getInstance();
    _mergeDanmaku = prefs.getBool(_mergeDanmakuKey) ?? false;
    notifyListeners();
  }

  // 设置弹幕合并
  Future<void> setMergeDanmaku(bool merge) async {
    if (_mergeDanmaku != merge) {
      _mergeDanmaku = merge;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mergeDanmakuKey, merge);
      notifyListeners();
    }
  }

  // 切换弹幕合并状态
  void toggleMergeDanmaku() {
    setMergeDanmaku(!_mergeDanmaku);
  }

  // 加载弹幕堆叠设置
  Future<void> _loadDanmakuStacking() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakuStacking = prefs.getBool(_danmakuStackingKey) ?? false;
    notifyListeners();
  }

  // 设置弹幕堆叠
  Future<void> setDanmakuStacking(bool stacking) async {
    if (_danmakuStacking != stacking) {
      _danmakuStacking = stacking;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_danmakuStackingKey, stacking);
      notifyListeners();
    }
  }

  // 切换弹幕堆叠状态
  void toggleDanmakuStacking() {
    setDanmakuStacking(!_danmakuStacking);
  }

  void loadDanmaku(String episodeId, String animeIdStr) async {
    try {
      _setStatus(PlayerStatus.recognizing, message: '正在加载弹幕...');

      // 从缓存加载弹幕
      final cachedDanmaku =
          await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (cachedDanmaku != null) {
        _setStatus(PlayerStatus.recognizing, message: '正在从缓存加载弹幕...');
        danmakuController?.loadDanmaku(cachedDanmaku);
        _setStatus(PlayerStatus.playing,
            message: '从缓存加载弹幕完成 (${cachedDanmaku.length}条)');
        return;
      }

      // 从网络加载弹幕
      final animeId = int.tryParse(animeIdStr) ?? 0;
      final danmakuData =
          await DandanplayService.getDanmaku(episodeId, animeId);
      danmakuController?.loadDanmaku(danmakuData['comments']);
      _setStatus(PlayerStatus.playing,
          message: '弹幕加载完成 (${danmakuData['count']}条)');
    } catch (e) {
      //////debugPrint('加载弹幕失败: $e');
      _setStatus(PlayerStatus.playing, message: '弹幕加载失败');
    }
  }

  // 在设置视频时长时更新状态
  void setVideoDuration(Duration duration) {
    _videoDuration = duration;
    notifyListeners();
  }

  // 更新观看记录
  Future<void> _updateWatchHistory() async {
    if (_currentVideoPath == null) return;

    try {
      // 获取当前播放记录
      final existingHistory =
          await WatchHistoryManager.getHistoryItem(_currentVideoPath!);

      if (existingHistory != null) {
        // 使用当前缩略图路径，如果没有则尝试捕获一个
        String? thumbnailPath = _currentThumbnailPath;
        if (thumbnailPath == null || thumbnailPath.isEmpty) {
          thumbnailPath = existingHistory.thumbnailPath;
          if ((thumbnailPath == null || thumbnailPath.isEmpty) &&
              player.state == PlaybackState.playing) {
            // 仅在播放时尝试捕获
            // 仅在没有缩略图时才尝试捕获
            try {
              thumbnailPath = await _captureVideoFrameWithoutPausing();
              if (thumbnailPath != null) {
                _currentThumbnailPath = thumbnailPath;
              }
            } catch (e) {
              //debugPrint('自动捕获缩略图失败: $e');
            }
          }
        }

        // 更新现有记录
        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: existingHistory
              .animeName, // existingHistory.animeName 应该是可靠的 String
          episodeTitle: existingHistory.episodeTitle,
          episodeId: existingHistory.episodeId,
          animeId: existingHistory.animeId,
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
        );

        await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
        if (_context != null && _context!.mounted) {
          // 添加 mounted 检查
          _context!.read<WatchHistoryProvider>().refresh();
        }
      } else {
        // 如果记录不存在，创建新记录 (这种情况理论上不常发生，因为 initializeWatchHistory 应该已经创建了)
        final fileName = _currentVideoPath!.split('/').last;

        // 尝试从文件名中提取初始动画名称
        String initialAnimeName = fileName.replaceAll(
            RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$', caseSensitive: false), '');
        initialAnimeName =
            initialAnimeName.replaceAll(RegExp(r'[_\.-]'), ' ').trim();

        if (initialAnimeName.isEmpty) {
          initialAnimeName = "未知动画"; // 确保非空
        }

        // 尝试获取缩略图
        String? thumbnailPath = _currentThumbnailPath;
        if (thumbnailPath == null && player.state == PlaybackState.playing) {
          // 仅在播放时尝试捕获
          try {
            thumbnailPath = await _captureVideoFrameWithoutPausing();
            if (thumbnailPath != null) {
              _currentThumbnailPath = thumbnailPath;
            }
          } catch (e) {
            //debugPrint('首次创建记录时捕获缩略图失败: $e');
          }
        }

        final newHistory = WatchHistoryItem(
          filePath: _currentVideoPath!,
          animeName: initialAnimeName, // initialAnimeName 已确保非空
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
        );

        await WatchHistoryManager.addOrUpdateHistory(newHistory);
        if (_context != null && _context!.mounted) {
          // 添加 mounted 检查
          _context!.read<WatchHistoryProvider>().refresh();
        }
      }
    } catch (e, s) {
      // 添加 stackTrace
      //debugPrint('更新观看记录时出错: $e\n$s'); // 打印堆栈信息
    }
  }

  // 捕获视频帧的方法（会暂停视频，用于手动截图）
  Future<String?> captureVideoFrame() async {
    if (_currentVideoPath == null || !hasVideo) return null;

    try {
      // 暂停播放，以便获取当前帧
      final isPlaying = player.state == PlaybackState.playing;
      if (isPlaying) {
        player.state = PlaybackState.paused;
      }

      // 等待一段时间确保暂停完成
      await Future.delayed(const Duration(milliseconds: 50));

      // 计算保持原始宽高比的图像尺寸
      const int targetHeight = 128;
      int targetWidth = 128; // 默认值

      // 从视频媒体信息获取宽高比
      if (player.mediaInfo.video != null &&
          player.mediaInfo.video!.isNotEmpty) {
        final videoTrack = player.mediaInfo.video![0];
        if (videoTrack.codec.width > 0 && videoTrack.codec.height > 0) {
          final aspectRatio = videoTrack.codec.width / videoTrack.codec.height;
          targetWidth = (targetHeight * aspectRatio).round();
        }
      }

      // 使用Player的snapshot方法获取当前帧，保持宽高比
      final videoFrame =
          await player.snapshot(width: targetWidth, height: targetHeight);
      if (videoFrame == null) {
        //debugPrint('无法捕获视频帧');

        // 恢复播放状态
        if (isPlaying) {
          player.state = PlaybackState.playing;
        }

        return null;
      }

      // 使用缓存的哈希值或重新计算哈希值
      String videoFileHash;
      if (_currentVideoHash != null) {
        videoFileHash = _currentVideoHash!;
      } else {
        videoFileHash = await _calculateFileHash(_currentVideoPath!);
        _currentVideoHash = videoFileHash; // 缓存哈希值
      }

      // 直接使用image包将RGBA数据转换为PNG
      try {
        // 从RGBA字节数据创建图像
        final image = img.Image.fromBytes(
          width: targetWidth,
          height: targetHeight,
          bytes: videoFrame.buffer,
          numChannels: 4, // RGBA
        );

        // 编码为PNG格式
        final pngBytes = img.encodePng(image);

        // 创建缩略图目录
        final appDir = await getApplicationDocumentsDirectory();
        final thumbnailDir = Directory('${appDir.path}/thumbnails');
        if (!thumbnailDir.existsSync()) {
          thumbnailDir.createSync(recursive: true);
        }

        // 保存缩略图文件
        final thumbnailPath = '${thumbnailDir.path}/$videoFileHash.png';
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile.writeAsBytes(pngBytes);

        // 恢复播放状态
        if (isPlaying) {
          player.state = PlaybackState.playing;
        }

        debugPrint(
            '视频帧缩略图已保存: $thumbnailPath, 尺寸: ${targetWidth}x$targetHeight');

        // 更新当前缩略图路径
        _currentThumbnailPath = thumbnailPath;

        return thumbnailPath;
      } catch (e) {
        //debugPrint('处理图像数据时出错: $e');

        // 恢复播放状态
        if (isPlaying) {
          player.state = PlaybackState.playing;
        }

        return null;
      }
    } catch (e) {
      //debugPrint('截取视频帧时出错: $e');

      // 恢复播放状态
      if (player.state == PlaybackState.paused &&
          _status == PlayerStatus.playing) {
        player.state = PlaybackState.playing;
      }

      return null;
    }
  }

  /// 获取当前时间窗口内的弹幕（分批加载/懒加载）
  List<Map<String, dynamic>> getActiveDanmakuList(double currentTime,
      {double window = 15.0}) {
    return _danmakuList.where((d) {
      final t = d['time'] as double? ?? 0.0;
      return t >= currentTime - window && t <= currentTime + window;
    }).toList();
  }

  // Volume Drag Methods
  void startVolumeDrag() {
    if (!globals.isPhone) return;
    _initialDragVolume = _currentVolume;
    _showVolumeIndicator(); // We'll define this next
    debugPrint(
        "Volume drag started. Initial drag volume: $_initialDragVolume");
  }

  Future<void> updateVolumeOnDrag(
      double verticalDragDelta, BuildContext context) async {
    if (!globals.isPhone) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final sensitivityFactor = screenHeight * 0.3; // Same sensitivity as brightness for now

    double change = -verticalDragDelta / sensitivityFactor;
    double newVolume = _initialDragVolume + change;
    newVolume = newVolume.clamp(0.0, 1.0);

    try {
      // Set system volume using MDK player.volume (0.0-1.0 range)
      if (player.volume != null) { // Check if volume property is available
        player.volume = newVolume; 
      }
      _currentVolume = newVolume; 
      _initialDragVolume = newVolume; 
      _showVolumeIndicator(); 
      notifyListeners();
    } catch (e) {
      //debugPrint("Failed to set system volume via player: $e");
    }
  }

  void endVolumeDrag() {
    if (!globals.isPhone) return;
    debugPrint(
        "Volume drag ended. Current volume: $_currentVolume");
  }

  static const double _volumeStep = 0.05; // 5% volume change per key press

  void increaseVolume({double? step}) {
    if (globals.isPhone) return; // Only for PC

    try {
      // Prioritize actual player volume, fallback to _currentVolume
      double currentVolume = player.volume ?? _currentVolume;
      double newVolume = (currentVolume + (step ?? _volumeStep)).clamp(0.0, 1.0);
      
      if (player.volume != null) {
        player.volume = newVolume;
      }
      _currentVolume = newVolume;
      // Keep _initialDragVolume in sync in case a touch/mouse drag starts later
      _initialDragVolume = newVolume; 
      _showVolumeIndicator();
      notifyListeners();
      //debugPrint("Volume increased to: $_currentVolume via keyboard");
    } catch (e) {
      //debugPrint("Failed to increase volume via keyboard: $e");
    }
  }

  void decreaseVolume({double? step}) {
    if (globals.isPhone) return; // Only for PC

    try {
      // Prioritize actual player volume, fallback to _currentVolume
      double currentVolume = player.volume ?? _currentVolume;
      double newVolume = (currentVolume - (step ?? _volumeStep)).clamp(0.0, 1.0);

      if (player.volume != null) {
        player.volume = newVolume;
      }
      _currentVolume = newVolume;
      // Keep _initialDragVolume in sync in case a touch/mouse drag starts later
      _initialDragVolume = newVolume;
      _showVolumeIndicator();
      notifyListeners();
      //debugPrint("Volume decreased to: $_currentVolume via keyboard");
    } catch (e) {
      //debugPrint("Failed to decrease volume via keyboard: $e");
    }
  }
  
  // Seek Drag Methods
  void startSeekDrag(BuildContext context) {
    if (!globals.isPhone) return; // Add platform check
    if (!hasVideo) return;
    _isSeekingViaDrag = true;
    _dragSeekStartPosition = _position;
    _accumulatedDragDx = 0.0;
    _dragSeekTargetPosition = _position;
    _showSeekIndicator(); // <<< CALL ADDED
    //debugPrint("Seek drag started. Start position: $_dragSeekStartPosition");
    notifyListeners(); 
  }

  void updateSeekDrag(double deltaDx, BuildContext context) {
    if (!globals.isPhone) return; // Add platform check
    if (!hasVideo || !_isSeekingViaDrag) return;

    _accumulatedDragDx += deltaDx;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Sensitivity: 滑动整个屏幕宽度对应总时长的N分之一，例如1/3或者一个固定时长如60秒
    // Let's say sliding half the screen width seeks 60 seconds.
    const double pixelsPerSecond = 1.0; // Smaller value = more sensitive, e.g. screenWidth / 60.0 for 60s per screen
    double seekOffsetSeconds = _accumulatedDragDx / pixelsPerSecond; 

    Duration newPositionDuration = _dragSeekStartPosition + Duration(seconds: seekOffsetSeconds.round());
    
    // Clamp newPosition between Duration.zero and video duration
    int newPositionMillis = newPositionDuration.inMilliseconds;
    if (_duration > Duration.zero) {
      newPositionMillis = newPositionMillis.clamp(0, _duration.inMilliseconds);
    }
    _dragSeekTargetPosition = Duration(milliseconds: newPositionMillis);

    // TODO: Update seek indicator UI with _dragSeekTargetPosition
    // For now, just print.
    // //debugPrint("Seek drag update. Target: $_dragSeekTargetPosition, DeltaDx: $deltaDx, AccumulatedDx: $_accumulatedDragDx");
    notifyListeners(); // To update UI displaying _dragSeekTargetPosition
  }

  void endSeekDrag() {
    if (!globals.isPhone) return; // Add platform check
    if (!hasVideo || !_isSeekingViaDrag) return;
    
    seekTo(_dragSeekTargetPosition);
    _isSeekingViaDrag = false;
    _accumulatedDragDx = 0.0;
    _hideSeekIndicator(); // <<< CALL ADDED
    //debugPrint("Seek drag ended. Seeking to: $_dragSeekTargetPosition");
    notifyListeners();
  }

  // Seek Indicator Overlay Methods
  void _showSeekIndicator() {
    if (!globals.isPhone || _context == null) return; // Ensure context is available
    _isSeekIndicatorVisible = true;

    if (_seekOverlayEntry == null) {
      _seekOverlayEntry = OverlayEntry(
        builder: (context) {
          // SeekIndicator uses Consumer<VideoPlayerState> internally
          // It needs to be wrapped in a provider if this OverlayEntry's context
          // is different or doesn't have VideoPlayerState high up.
          // Providing it directly here is safest.
          return ChangeNotifierProvider<VideoPlayerState>.value(
            value: this,
            child: const SeekIndicator(),
          );
        },
      );
      Overlay.of(_context!)!.insert(_seekOverlayEntry!); 
    }
    notifyListeners(); // To trigger opacity animation in SeekIndicator

    // Optional: Timer to auto-hide if drag ends abruptly or no more updates
    _seekIndicatorTimer?.cancel();
    // _seekIndicatorTimer = Timer(const Duration(seconds: 2), () { 
    //   _hideSeekIndicator();
    // });
  }

  void _hideSeekIndicator() {
    if (!globals.isPhone) return;
    _seekIndicatorTimer?.cancel();

    if (_isSeekIndicatorVisible) {
      _isSeekIndicatorVisible = false;
      notifyListeners(); // Trigger fade-out animation

      // Wait for fade-out animation to complete before removing
      Future.delayed(const Duration(milliseconds: 200), () { // Match SeekIndicator fade duration
        if (_seekOverlayEntry != null) {
          _seekOverlayEntry!.remove();
          _seekOverlayEntry = null;
        }
      });
    } else {
      // Ensure entry is removed if it somehow exists while not visible
      if (_seekOverlayEntry != null) {
        _seekOverlayEntry!.remove();
        _seekOverlayEntry = null;
      }
    }
  }
}
