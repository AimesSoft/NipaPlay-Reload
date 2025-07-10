import 'package:flutter/material.dart';
// import 'package:fvp/mdk.dart';  // Commented out
import '../player_abstraction/player_abstraction.dart'; // <-- NEW IMPORT
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
// Added import for subtitle parser
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'keyboard_shortcuts.dart';
import 'globals.dart' as globals;
import 'dart:convert';
import '../services/dandanplay_service.dart';
import '../services/jellyfin_service.dart';
import '../services/emby_service.dart';
import 'media_info_helper.dart';
import '../services/danmaku_cache_manager.dart';
import '../models/watch_history_model.dart';
import '../models/watch_history_database.dart'; // 导入观看记录数据库
import 'package:image/image.dart' as img;

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
import '../widgets/speed_boost_indicator.dart'; // Added import for SpeedBoostIndicator widget

import 'subtitle_manager.dart'; // 导入字幕管理器
import '../services/file_picker_service.dart'; // Added import for FilePickerService
import 'package:nipaplay/utils/system_resource_monitor.dart';
import 'decoder_manager.dart'; // 导入解码器管理器
import '../services/episode_navigation_service.dart'; // 导入剧集导航服务
import '../services/auto_next_episode_service.dart';
import 'storage_service.dart'; // Added import for StorageService
import 'screen_orientation_manager.dart';
import '../player_abstraction/media_kit_player_adapter.dart'; // 导入MediaKitPlayerAdapter

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
  late Player player; // 改为 late 修饰，使用 Player.create() 方法创建
  BuildContext? _context;
  PlayerStatus _status = PlayerStatus.idle;
  List<String> _statusMessages = []; // 修改为列表存储多个状态消息
  bool _showControls = true;
  bool _isFullscreen = false;
  double _progress = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;
  final bool _isErrorStopping = false; // <<< ADDED THIS FIELD
  double _aspectRatio = 16 / 9; // 默认16:9，但会根据视频实际比例更新
  String? _currentVideoPath;
  Timer? _uiUpdateTimer; // UI更新定时器（包含位置保存和数据持久化功能）
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

  Duration? _lastSeekPosition; // 添加这个字段来记录最后一次seek的位置
  List<Map<String, dynamic>> _danmakuList = [];
  
  // 多轨道弹幕系统
  Map<String, Map<String, dynamic>> _danmakuTracks = {};
  Map<String, bool> _danmakuTrackEnabled = {};
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
  
  // 弹幕类型屏蔽
  static const String _blockTopDanmakuKey = 'block_top_danmaku';
  static const String _blockBottomDanmakuKey = 'block_bottom_danmaku';
  static const String _blockScrollDanmakuKey = 'block_scroll_danmaku';
  bool _blockTopDanmaku = false; // 默认不屏蔽顶部弹幕
  bool _blockBottomDanmaku = false; // 默认不屏蔽底部弹幕
  bool _blockScrollDanmaku = false; // 默认不屏蔽滚动弹幕
  
  // 弹幕屏蔽词
  static const String _danmakuBlockWordsKey = 'danmaku_block_words';
  List<String> _danmakuBlockWords = []; // 弹幕屏蔽词列表
  
  // 添加播放速度相关状态
  static const String _playbackRateKey = 'playback_rate';
  double _playbackRate = 2.0; // 默认2倍速
  bool _isSpeedBoostActive = false; // 是否正在倍速播放（长按状态）
  double _normalPlaybackRate = 1.0; // 正常播放速度
  
  dynamic danmakuController; // 添加弹幕控制器属性
  Duration _videoDuration = Duration.zero; // 添加视频时长状态
  bool _isFullscreenTransitioning = false;
  String? _currentThumbnailPath; // 添加当前缩略图路径
  String? _currentVideoHash; // 缓存当前视频的哈希值，避免重复计算
  bool _isCapturingFrame = false; // 是否正在截图，避免并发截图
  final List<VoidCallback> _thumbnailUpdateListeners = []; // 缩略图更新监听器列表
  String? _animeTitle; // 添加动画标题属性
  String? _episodeTitle; // 添加集数标题属性
  
  // 从 historyItem 传入的弹幕 ID（用于保持弹幕关联）
  int? _episodeId; // 存储从 historyItem 传入的 episodeId
  int? _animeId; // 存储从 historyItem 传入的 animeId
  
  // 字幕管理器
  late SubtitleManager _subtitleManager;

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

  // 倍速指示器状态
  OverlayEntry? _speedBoostOverlayEntry;

  // 右边缘悬浮菜单状态
  bool _isRightEdgeHovered = false;
  Timer? _rightEdgeHoverTimer;
  OverlayEntry? _hoverSettingsMenuOverlay;

  // 加载状态相关
  bool _isInFinalLoadingPhase = false; // 是否处于最终加载阶段，用于优化动画性能
  
  // 解码器管理器
  late DecoderManager _decoderManager;

  bool _hasInitialScreenshot = false; // 添加标记跟踪是否已进行第一次播放截图
  
  // 平板设备菜单栏隐藏状态
  bool _isAppBarHidden = false;

  // 新增回调：当发生严重播放错误且应弹出时调用
  Function()? onSeriousPlaybackErrorAndShouldPop;

  // 获取菜单栏隐藏状态
  bool get isAppBarHidden => _isAppBarHidden;

  // 检查是否为平板设备（使用globals中的判定逻辑）
  bool get isTablet => globals.isTablet;

  // 切换菜单栏显示/隐藏状态（仅用于平板设备）
  void toggleAppBarVisibility() async {
    if (isTablet) {
      _isAppBarHidden = !_isAppBarHidden;
      
      // 当切换到全屏状态时，同时隐藏系统状态栏
      if (_isAppBarHidden) {
        // 进入全屏状态，隐藏系统UI
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } catch (e) {
          debugPrint('隐藏系统UI时出错: $e');
        }
      } else {
        // 退出全屏状态，显示系统UI
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        } catch (e) {
          debugPrint('显示系统UI时出错: $e');
        }
      }
      
      notifyListeners();
    }
  }

  VideoPlayerState() {
    // 创建临时播放器实例，后续会被 _initialize 中的异步创建替换
    player = Player();
    _subtitleManager = SubtitleManager(player: player);
    _decoderManager = DecoderManager(player: player);
    onExternalSubtitleAutoLoaded = _onExternalSubtitleAutoLoaded;
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
  Map<String, Map<String, dynamic>> get danmakuTracks => _danmakuTracks;
  Map<String, bool> get danmakuTrackEnabled => _danmakuTrackEnabled;
  double get controlBarHeight => _controlBarHeight;
  double get danmakuOpacity => _danmakuOpacity;
  bool get danmakuVisible => _danmakuVisible;
  bool get mergeDanmaku => _mergeDanmaku;
  bool get danmakuStacking => _danmakuStacking;
  Duration get videoDuration => _videoDuration;
  String? get currentVideoPath => _currentVideoPath;
  String? get animeTitle => _animeTitle; // 添加动画标题getter
  String? get episodeTitle => _episodeTitle; // 添加集数标题getter
  int? get animeId => _animeId; // 添加动画ID getter
  int? get episodeId => _episodeId; // 添加剧集ID getter
  
  // 添加setter方法以支持手动匹配后立即更新标题
  void setAnimeTitle(String? title) {
    _animeTitle = title;
    notifyListeners();
    
    // 立即更新历史记录，确保历史记录卡片显示正确的动画名称
    _updateHistoryWithNewTitles();
  }
  
  void setEpisodeTitle(String? title) {
    _episodeTitle = title;
    notifyListeners();
    
    // 立即更新历史记录，确保历史记录卡片显示正确的动画名称
    _updateHistoryWithNewTitles();
  }
  
  /// 使用新的标题更新历史记录
  Future<void> _updateHistoryWithNewTitles() async {
    if (_currentVideoPath == null) return;
    
    // 只有当两个标题都有值时才更新
    if (_animeTitle == null || _animeTitle!.isEmpty) return;
    
    try {
      debugPrint('[VideoPlayerState] 使用新标题更新历史记录: $_animeTitle - $_episodeTitle');
      
      // 获取现有历史记录
      final existingHistory = await WatchHistoryDatabase.instance.getHistoryByFilePath(_currentVideoPath!);
      if (existingHistory == null) {
        debugPrint('[VideoPlayerState] 未找到现有历史记录，跳过更新');
        return;
      }
      
      // 创建更新后的历史记录
      final updatedHistory = WatchHistoryItem(
        filePath: existingHistory.filePath,
        animeName: _animeTitle!,
        episodeTitle: _episodeTitle ?? existingHistory.episodeTitle,
        episodeId: _episodeId ?? existingHistory.episodeId,
        animeId: _animeId ?? existingHistory.animeId,
        watchProgress: existingHistory.watchProgress,
        lastPosition: existingHistory.lastPosition,
        duration: existingHistory.duration,
        lastWatchTime: DateTime.now(),
        thumbnailPath: existingHistory.thumbnailPath,
        isFromScan: existingHistory.isFromScan,
      );
      
      // 保存更新后的记录
      await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(updatedHistory);
      
      debugPrint('[VideoPlayerState] 成功更新历史记录: ${updatedHistory.animeName} - ${updatedHistory.episodeTitle}');
      
      // 通知UI刷新历史记录
      if (_context != null && _context!.mounted) {
        _context!.read<WatchHistoryProvider>().refresh();
      }
      
    } catch (e) {
      debugPrint('[VideoPlayerState] 更新历史记录时出错: $e');
    }
  }
  
  // 字幕管理器相关的getter
  SubtitleManager get subtitleManager => _subtitleManager;
  String? get currentExternalSubtitlePath => _subtitleManager.currentExternalSubtitlePath;
  Map<String, Map<String, dynamic>> get subtitleTrackInfo => _subtitleManager.subtitleTrackInfo;

  // Brightness Getters
  double get currentScreenBrightness => _currentBrightness;
  bool get isBrightnessIndicatorVisible => _isBrightnessIndicatorVisible;

  // Volume Getters
  double get currentSystemVolume => _currentVolume;
  bool get isVolumeUIVisible => _isVolumeIndicatorVisible; // Renamed for clarity

  // Seek Indicator Getter
  bool get isSeekIndicatorVisible => _isSeekIndicatorVisible; // <<< ADDED THIS GETTER
  Duration get dragSeekTargetPosition => _dragSeekTargetPosition; // <<< ADDED THIS GETTER

  // 弹幕类型屏蔽Getters
  bool get blockTopDanmaku => _blockTopDanmaku;
  bool get blockBottomDanmaku => _blockBottomDanmaku;
  bool get blockScrollDanmaku => _blockScrollDanmaku;
  List<String> get danmakuBlockWords => _danmakuBlockWords;

  // 获取是否处于最终加载阶段
  bool get isInFinalLoadingPhase => _isInFinalLoadingPhase;

  // 解码器管理器相关的getter
  DecoderManager get decoderManager => _decoderManager;

  // 获取播放器内核名称
  String get playerCoreName => player.getPlayerKernelName();
  
  // 播放速度相关的getter
  double get playbackRate => _playbackRate;
  bool get isSpeedBoostActive => _isSpeedBoostActive;

  // 右边缘悬浮菜单的getter
  bool get isRightEdgeHovered => _isRightEdgeHovered;

  Future<void> _initialize() async {
    if (globals.isPhone) {
      // 使用新的屏幕方向管理器设置初始方向
      await ScreenOrientationManager.instance.setInitialOrientation();
      await _loadInitialBrightness(); // Load initial brightness for phone
      await _loadInitialVolume(); // <<< CALL ADDED
    }
    _startUiUpdateTimer(); // 启动UI更新定时器（已包含位置保存功能）
    _setupWindowManagerListener();
    _focusNode.requestFocus();
    KeyboardShortcuts.loadShortcuts();
    await _loadLastVideo();
    await _loadControlBarHeight(); // 加载保存的控制栏高度
    await _loadDanmakuOpacity(); // 加载保存的弹幕透明度
    await _loadDanmakuVisible(); // 加载弹幕可见性
    await _loadMergeDanmaku(); // 加载弹幕合并设置
    await _loadDanmakuStacking(); // 加载弹幕堆叠设置
    
    // 加载弹幕类型屏蔽设置
    await _loadBlockTopDanmaku();
    await _loadBlockBottomDanmaku();
    await _loadBlockScrollDanmaku();
    
    // 加载弹幕屏蔽词
    await _loadDanmakuBlockWords();
    
    // 加载播放速度设置
    await _loadPlaybackRate();

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
 
       _currentVolume = player.volume; 
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
      Overlay.of(_context!).insert(_brightnessOverlayEntry!);
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
                  bottom: globals.isPhone ? 100.0 : null,
                  child: const VolumeIndicator(), // Uses isVolumeUIVisible internally for opacity
                );
              },
            ),
          );
        },
      );
      Overlay.of(_context!).insert(_volumeOverlayEntry!);
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



  Future<void> initializePlayer(String videoPath,
      {WatchHistoryItem? historyItem, String? historyFilePath, String? actualPlayUrl}) async {
    if (_status == PlayerStatus.loading ||
        _status == PlayerStatus.recognizing) {
      _setStatus(PlayerStatus.idle, message: "取消了之前的加载任务", clearPreviousMessages: true);
    }
    _clearPreviousVideoState(); // 清理旧状态
    _statusMessages.clear(); // <--- 新增行：确保消息列表在开始时是空的
    
    // 从 historyItem 中获取弹幕 ID
    if (historyItem != null) {
      _episodeId = historyItem.episodeId;
      _animeId = historyItem.animeId;
      debugPrint('VideoPlayerState: 从 historyItem 获取弹幕 ID - episodeId: $_episodeId, animeId: $_animeId');
    } else {
      _episodeId = null;
      _animeId = null;
      debugPrint('VideoPlayerState: 没有 historyItem，重置弹幕 ID');
    }
    
    // 检查是否为网络URL (HTTP或HTTPS)
    bool isNetworkUrl = videoPath.startsWith('http://') || videoPath.startsWith('https://');
    
    // 检查是否是流媒体（jellyfin://协议、emby://协议）
    bool isJellyfinStream = videoPath.startsWith('jellyfin://');
    bool isEmbyStream = videoPath.startsWith('emby://');
    
    // 对于本地文件才检查存在性，网络URL和流媒体默认认为"存在"
    bool fileExists = isNetworkUrl || isJellyfinStream || isEmbyStream;
    
    // 为网络URL添加特定日志
    if (isNetworkUrl) {
      debugPrint('检测到流媒体URL: $videoPath');
      _statusMessages.add('正在准备流媒体播放...');
      notifyListeners();
    } else if (isJellyfinStream) {
      debugPrint('检测到Jellyfin流媒体: videoPath=$videoPath, actualPlayUrl=$actualPlayUrl');
      _statusMessages.add('正在准备Jellyfin流媒体播放...');
      notifyListeners();
    } else if (isEmbyStream) {
      debugPrint('检测到Emby流媒体: videoPath=$videoPath, actualPlayUrl=$actualPlayUrl');
      _statusMessages.add('正在准备Emby流媒体播放...');
      notifyListeners();
    }
    
    if (!isNetworkUrl && !isJellyfinStream && !isEmbyStream) {
      // 使用FilePickerService处理文件路径问题
      if (Platform.isIOS) {
        final filePickerService = FilePickerService();
        
        // 首先检查文件是否存在
        fileExists = filePickerService.checkFileExists(videoPath);
        
        // 如果文件不存在，尝试获取有效的文件路径
        if (!fileExists) {
          final validPath = await filePickerService.getValidFilePath(videoPath);
          if (validPath != null) {
            debugPrint('找到有效路径: $validPath (原路径: $videoPath)');
            videoPath = validPath;
            fileExists = true;
          } else {
            // 检查是否是iOS临时文件路径
            if (videoPath.contains('/tmp/') || 
                videoPath.contains('-Inbox/') || 
                videoPath.contains('/Inbox/')) {
              debugPrint('检测到iOS临时文件路径: $videoPath');
              // 尝试从原始路径获取文件名，然后检查是否在持久化目录中
              final fileName = p.basename(videoPath);
              final docDir = await StorageService.getAppStorageDirectory();
              final persistentPath = '${docDir.path}/Videos/$fileName';
              
              if (File(persistentPath).existsSync()) {
                debugPrint('找到持久化存储中的文件: $persistentPath');
                videoPath = persistentPath;
                fileExists = true;
              }
            }
          }
        }
      } else {
        // 非iOS平台直接检查文件是否存在
        final File videoFile = File(videoPath);
        fileExists = videoFile.existsSync();
      }
    } else {
      debugPrint('检测到网络URL或流媒体: $videoPath');
    }
    
    if (!fileExists) {
      debugPrint('VideoPlayerState: 文件不存在或无法访问: $videoPath');
      _setStatus(PlayerStatus.error, message: '找不到文件或无法访问: ${p.basename(videoPath)}');
      _error = '文件不存在或无法访问';
      return;
    }
    
    // 对网络URL和Jellyfin流媒体进行特殊处理
    if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
      debugPrint('VideoPlayerState: 准备流媒体URL: $videoPath');
      // 添加网络错误处理的尝试/捕获块
      try {
        // 测试网络连接
        await http.head(Uri.parse(videoPath));
      } catch (e) {
        // 如果网络请求失败，使用专门的错误处理逻辑
        await _handleStreamUrlLoadingError(videoPath, e is Exception ? e : Exception(e.toString()));
        return; // 避免继续处理
      }
    } else if ((isJellyfinStream || isEmbyStream) && actualPlayUrl != null) {
      debugPrint('VideoPlayerState: 准备流媒体URL: $actualPlayUrl');
      // 对Jellyfin流媒体测试实际播放URL的连接
      try {
        await http.head(Uri.parse(actualPlayUrl));
      } catch (e) {
        // 如果网络请求失败，使用专门的错误处理逻辑
        await _handleStreamUrlLoadingError(actualPlayUrl, e is Exception ? e : Exception(e.toString()));
        return; // 避免继续处理
      }
    }
    
    // 更新字幕管理器的视频路径
    _subtitleManager.setCurrentVideoPath(videoPath);

    _currentVideoPath = videoPath;
    print('historyItem: $historyItem');
    _animeTitle = historyItem?.animeName; // 从历史记录获取动画标题
    _episodeTitle = historyItem?.episodeTitle; // 从历史记录获取集数标题
    _episodeId = historyItem?.episodeId; // 保存从历史记录传入的 episodeId
    _animeId = historyItem?.animeId; // 保存从历史记录传入的 animeId
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
      // 清除视频资源
      player.state = PlaybackState.stopped;
      player.setMedia("", MediaType.video); // 使用空字符串和视频类型清除媒体
      
      // 释放旧纹理
      if (player.textureId.value != null) { // Keep the null check for reading
        // player.textureId.value = null; // COMMENTED OUT - ValueListenable has no setter
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
      // 设置媒体源 - 如果提供了actualPlayUrl则使用它，否则使用videoPath
      String playUrl = actualPlayUrl ?? videoPath;
      player.media = playUrl;

      //debugPrint('4. 准备播放器...');
      // 准备播放器
      player.prepare();

      // 针对Jellyfin流媒体，给予更长的初始化时间
      final bool isJellyfinStreaming = videoPath.contains('jellyfin://') || videoPath.contains('emby://');
      final int initializationTimeout = isJellyfinStreaming ? 30000 : 15000; // Jellyfin: 30秒, 其他: 15秒
      
      debugPrint('VideoPlayerState: 播放器初始化超时设置: ${initializationTimeout}ms (${isJellyfinStreaming ? 'Jellyfin流媒体' : '本地文件'})');

      // 等待播放器准备完成，设置超时
      int waitCount = 0;
      const int maxWaitCount = 100; // 最大等待次数
      const int waitInterval = 100; // 每次等待100毫秒
      
      while (waitCount < maxWaitCount) {
        await Future.delayed(const Duration(milliseconds: waitInterval));
        waitCount++;
        
        // 检查播放器状态
        if (player.state == PlaybackState.playing || 
            player.state == PlaybackState.paused ||
            (player.mediaInfo.duration > 0 && player.textureId.value != null)) {
          debugPrint('VideoPlayerState: 播放器准备完成，等待时间: ${waitCount * waitInterval}ms');
          break;
        }
        
        // 检查是否超时
        if (waitCount * waitInterval >= initializationTimeout) {
          debugPrint('VideoPlayerState: 播放器初始化超时 (${initializationTimeout}ms)');
          if (isJellyfinStreaming) {
            debugPrint('VideoPlayerState: Jellyfin流媒体初始化超时，但继续尝试播放');
            // 对于Jellyfin流媒体，即使超时也继续尝试
            break;
          } else {
            throw Exception('播放器初始化超时');
          }
        }
      }

      //debugPrint('5. 获取视频纹理...');
      // 获取视频纹理
      final textureId = await player.updateTexture();
      //debugPrint('获取到纹理ID: $textureId');

      // !!!!! 在这里启动或重启UI更新定时器（已包含位置保存功能）!!!!!
      _startUiUpdateTimer(); // 启动UI更新定时器（已包含位置保存功能）
      // !!!!! ------------------------------------------- !!!!!

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
          debugPrint('VideoPlayerState: 从mediaInfo设置视频宽高比: $_aspectRatio (${videoTrack.codec.width}x${videoTrack.codec.height})');
        } else {
          // 备用方案：从播放器状态获取视频尺寸
          debugPrint('VideoPlayerState: mediaInfo中视频尺寸为0，尝试从播放器状态获取');
          // 延迟获取，因为播放器状态可能还没有准备好
          Future.delayed(const Duration(milliseconds: 1000), () {
            // 尝试从播放器的snapshot方法获取视频尺寸
            try {
              player.snapshot().then((frame) {
                if (frame != null && frame.width > 0 && frame.height > 0) {
                  _aspectRatio = frame.width / frame.height;
                  debugPrint('VideoPlayerState: 从snapshot设置视频宽高比: $_aspectRatio (${frame.width}x${frame.height})');
                  notifyListeners(); // 通知UI更新
                }
              });
            } catch (e) {
              debugPrint('VideoPlayerState: 从snapshot获取视频尺寸失败: $e');
            }
          });
        }
        
        // 更新当前解码器信息
        // 获取解码器信息（异步方式）
        final activeDecoder = await getActiveDecoder();
        SystemResourceMonitor().setActiveDecoder(activeDecoder);
        debugPrint('当前视频解码器: $activeDecoder');
        
        // 如果检测到使用软解，但硬件解码开关已打开，尝试强制启用硬件解码
        if (activeDecoder.contains("软解")) {
          final prefs = await SharedPreferences.getInstance();
          final useHardwareDecoder = prefs.getBool('use_hardware_decoder') ?? true;
          
          if (useHardwareDecoder) {
            debugPrint('检测到使用软解但硬件解码已启用，尝试强制启用硬件解码...');
            // 延迟执行以避免干扰视频初始化
            Future.delayed(const Duration(seconds: 2), () async {
              await forceEnableHardwareDecoder();
            });
          }
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
          player.activeSubtitleTracks = [preferredSubtitleIndex + 1]; // MDK 字幕轨道从 1 开始
          
          // 更新字幕轨道信息
          if (player.mediaInfo.subtitle != null && 
              preferredSubtitleIndex < player.mediaInfo.subtitle!.length) {
            final track = player.mediaInfo.subtitle![preferredSubtitleIndex];
            _subtitleManager.updateSubtitleTrackInfo('embedded_subtitle', {
              'index': preferredSubtitleIndex,
              'title': track.toString(),
              'isActive': true,
            });
          }
        }
        
        // 无论是否有优先字幕轨道，都更新所有字幕轨道信息
        _subtitleManager.updateAllSubtitleTracksInfo();
        
        // 通知字幕轨道变化
        _subtitleManager.onSubtitleTrackChanged();
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
      // 针对Jellyfin流媒体视频的特殊处理
      bool jellyfinDanmakuHandled = false;
      try {
        // 检查是否是Jellyfin视频并尝试使用historyItem中的IDs直接加载弹幕
        jellyfinDanmakuHandled = await _checkAndLoadStreamingDanmaku(videoPath, historyItem);
      } catch (e) {
        debugPrint('检查Jellyfin弹幕时出错: $e');
        // 错误处理时不设置jellyfinDanmakuHandled为true，下面会继续常规处理
      }
      
      // 如果不是Jellyfin视频或者Jellyfin视频没有预设的弹幕IDs，则检查是否有手动匹配的弹幕
      if (!jellyfinDanmakuHandled) {
        // 检查是否有手动匹配的弹幕ID
        if (_episodeId != null && _animeId != null && _episodeId! > 0 && _animeId! > 0) {
          debugPrint('检测到手动匹配的弹幕ID，直接加载: episodeId=$_episodeId, animeId=$_animeId');
          try {
            _setStatus(PlayerStatus.recognizing, message: '正在加载手动匹配的弹幕...');
            loadDanmaku(_episodeId.toString(), _animeId.toString());
          } catch (e) {
            debugPrint('加载手动匹配的弹幕失败: $e');
            // 如果手动匹配的弹幕加载失败，清空弹幕列表但不重新识别
            _danmakuList = [];
            _danmakuTracks.clear();
            _danmakuTrackEnabled.clear();
            _addStatusMessage('手动匹配的弹幕加载失败');
          }
        } else {
          // 没有手动匹配的弹幕ID，使用常规方式识别和加载弹幕
          try {
            await _recognizeVideo(videoPath);
          } catch (e) {
            //debugPrint('弹幕加载失败: $e');
            // 设置空弹幕列表，确保播放不受影响
            _danmakuList = [];
            _danmakuTracks.clear();
            _danmakuTrackEnabled.clear();
            _addStatusMessage('无法连接服务器，跳过加载弹幕');
          }
        }
      }
      
      // 设置进入最终加载阶段，以优化动画性能
      _isInFinalLoadingPhase = true;
      notifyListeners();
      
      //debugPrint('11. 设置准备就绪状态...');
      // 设置状态为准备就绪
      _setStatus(PlayerStatus.ready, message: '准备就绪');
      
      // 使用屏幕方向管理器设置播放时的屏幕方向
      if (globals.isPhone) {
        debugPrint(
            'VideoPlayerState: Device is phone. Setting video playing orientation.');
        await ScreenOrientationManager.instance.setVideoPlayingOrientation();
        
        // 平板设备默认隐藏菜单栏（全屏状态）
        if (globals.isTablet) {
          _isAppBarHidden = true;
          debugPrint('VideoPlayerState: Tablet detected, hiding app bar by default.');
          
          // 同时隐藏系统UI
          try {
            await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          } catch (e) {
            debugPrint('隐藏系统UI时出错: $e');
          }
        }
      }

      //debugPrint('12. 设置最终播放状态 (在可能的横屏切换之后)...');
      if (lastPosition == 0) {
        // 从头播放
        // debugPrint('VideoPlayerState: Initializing playback from start, calling play().'); // <--- REMOVED PRINT
        play(); // Call our central play method
      } else {
        // 从中间恢复
        if (player.state == PlaybackState.playing) {
          // Player is already playing after seek (e.g., underlying engine auto-resumed)
          _setStatus(PlayerStatus.playing, message: '正在播放 (恢复)'); // Sync our status
          // debugPrint('VideoPlayerState: Player already playing on resume. Directly starting screenshot timer.'); // <--- REMOVED PRINT
          _startScreenshotTimer(); // Start timer directly
        } else {
          // Player did not auto-play after seek, or was paused. We need to start it.
          // _status should be 'ready' from earlier _setStatus call in initializePlayer
          // debugPrint('VideoPlayerState: Resuming playback (player was not auto-playing), calling play().'); // <--- REMOVED PRINT
          play(); // Call our central play method
        }
      }

      // 尝试自动检测和加载字幕
      await _subtitleManager.autoDetectAndLoadSubtitle(videoPath);

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

  // 外部字幕自动加载回调处理
  void _onExternalSubtitleAutoLoaded(String path, String fileName) {
    // 这里可以处理回调，例如显示提示或更新UI
    debugPrint('VideoPlayerState: 外部字幕自动加载: $fileName');
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
        // 如果已存在记录，只更新播放进度和时间相关信息
        // 对于Jellyfin流媒体，如果有友好名称，则使用友好名称
        String finalAnimeName = existingHistory.animeName;
        String? finalEpisodeTitle = existingHistory.episodeTitle;
        
        bool isJellyfinStream = path.startsWith('jellyfin://');
        bool isEmbyStream = path.startsWith('emby://');
        if ((isJellyfinStream || isEmbyStream) && _animeTitle != null && _animeTitle!.isNotEmpty) {
          finalAnimeName = _animeTitle!;
          if (_episodeTitle != null && _episodeTitle!.isNotEmpty) {
            finalEpisodeTitle = _episodeTitle!;
          }
          debugPrint('_initializeWatchHistory: 使用流媒体友好名称: $finalAnimeName - $finalEpisodeTitle');
        }
        
        debugPrint(
            '已有观看记录存在，只更新播放进度: 动画=$finalAnimeName, 集数=$finalEpisodeTitle');

        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: finalAnimeName,
          episodeTitle: finalEpisodeTitle,
          episodeId: existingHistory.episodeId,
          animeId: existingHistory.animeId,
          watchProgress: existingHistory.watchProgress,
          lastPosition: existingHistory.lastPosition,
          duration: existingHistory.duration,
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
        episodeId: _episodeId, // 使用从 historyItem 传入的 episodeId
        animeId: _animeId, // 使用从 historyItem 传入的 animeId
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
    } catch (e) {
      //debugPrint('初始化观看记录时出错: $e\n$s');
    }
  }

  Future<void> resetPlayer() async {
    try {
      // 在停止播放前保存最后的观看记录
      if (_currentVideoPath != null) {
        await _updateWatchHistory();
      }
      
      // 重置解码器信息
      SystemResourceMonitor().setActiveDecoder("未知");

      // 清除字幕设置（使用空字符串表示清除外部字幕）
      player.setMedia("", MediaType.subtitle);
      player.activeSubtitleTracks = [];

      // 先停止播放
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }

      // 等待一小段时间确保播放器完全停止
      await Future.delayed(const Duration(milliseconds: 100));

      // 释放纹理，确保资源被正确释放
      if (player.textureId.value != null) { // Keep the null check for reading
        _disposeTextureResources();
        // player.textureId.value = null; // COMMENTED OUT
      }

      // 等待一小段时间确保纹理完全释放
      await Future.delayed(const Duration(milliseconds: 200));

      // 重置状态
      _currentVideoPath = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _progress = 0.0;
      _error = null;
      _animeTitle = null;  // 清除动画标题
      _episodeTitle = null; // 清除集数标题
      _danmakuList = []; // 清除弹幕列表
      _danmakuTracks.clear();
      _danmakuTrackEnabled.clear();
      _subtitleManager.clearSubtitleTrackInfo();
      _isAppBarHidden = false; // 重置平板设备菜单栏隐藏状态
      
      // 重置系统UI显示状态
      if (globals.isPhone && globals.isTablet) {
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        } catch (e) {
          debugPrint('重置系统UI时出错: $e');
        }
      }
      
      _setStatus(PlayerStatus.idle);

      // 使用屏幕方向管理器重置屏幕方向
      if (globals.isPhone) {
        await ScreenOrientationManager.instance.resetOrientation();
      }
      
      // 关闭唤醒锁
      try {
        WakelockPlus.disable();
      } catch (e) {
        //debugPrint("Error disabling wakelock: $e");
      }
      
      notifyListeners();
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
    // 在状态即将从loading或recognizing变为ready或playing时，设置最终加载阶段标志
    if ((_status == PlayerStatus.loading || _status == PlayerStatus.recognizing) && 
        (newStatus == PlayerStatus.ready || newStatus == PlayerStatus.playing)) {
      _isInFinalLoadingPhase = true;
      
      // 延迟通知UI刷新，给足够时间处理状态变更
      Future.microtask(() {
        notifyListeners();
      });
    }
    
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
      
      // 在播放开始后一小段时间重置最终加载阶段标志
      Future.delayed(const Duration(milliseconds: 200), () {
        _isInFinalLoadingPhase = false;
        notifyListeners();
      });
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

  // 取消自动播放下一话
  void cancelAutoNextEpisode() {
    AutoNextEpisodeService.instance.cancelAutoNext();
  }

  void pause() {
    if (_status == PlayerStatus.playing) {
      // 使用直接暂停方法，确保VideoPlayer插件能够暂停视频
      player.pauseDirectly().then((_) {
        debugPrint('[VideoPlayerState] pauseDirectly() 调用成功');
        _setStatus(PlayerStatus.paused, message: '已暂停');
      }).catchError((e) {
        debugPrint('[VideoPlayerState] pauseDirectly() 调用失败: $e');
        // 尝试使用传统方法
        player.state = PlaybackState.paused;
        _setStatus(PlayerStatus.paused, message: '已暂停');
      });
      
      _saveCurrentPositionToHistory();
      // 在暂停时触发截图
      _captureConditionalScreenshot("暂停时");
      // WakelockPlus.disable(); // Already handled by _setStatus
    }
  }

  void play() {
    // <<< ADDED DEBUG LOG >>>
    debugPrint('[VideoPlayerState] play() called. hasVideo: $hasVideo, _status: $_status, currentMedia: ${player.media}');
    if (hasVideo &&
        (_status == PlayerStatus.paused || _status == PlayerStatus.ready)) {
      
      // 使用直接播放方法，确保VideoPlayer插件能够播放视频
      player.playDirectly().then((_) {
        debugPrint('[VideoPlayerState] playDirectly() 调用成功');
        // 设置状态
        _setStatus(PlayerStatus.playing, message: '开始播放');
        
        // 播放开始时提交观看记录到弹弹play
        _submitWatchHistoryToDandanplay();
      }).catchError((e) {
        debugPrint('[VideoPlayerState] playDirectly() 调用失败: $e');
        // 尝试使用传统方法
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing, message: '开始播放');
        
        // 播放开始时提交观看记录到弹弹play
        _submitWatchHistoryToDandanplay();
      });
      
      // <<< ADDED DEBUG LOG >>>
      debugPrint('[VideoPlayerState] play() -> _status set to PlayerStatus.playing. Notifying listeners.');
      
      // 在首次播放时进行截图
      if (!_hasInitialScreenshot) {
        _hasInitialScreenshot = true;
        // 延迟一秒再截图，确保视频已经开始显示
        Future.delayed(const Duration(seconds: 1), () {
          _captureConditionalScreenshot("首次播放时");
        });
      }
      // 视频开始播放后更新解码器信息
      Future.delayed(const Duration(seconds: 1), () {
        _updateCurrentActiveDecoder();
      });
      // _resetHideControlsTimer(); // Temporarily commented out as the method name is uncertain.
      // Please provide the correct method if you want to show controls on play.
    }
  }

  Future<void> stop() async {
    if (_status != PlayerStatus.idle && _status != PlayerStatus.disposed) {
      _setStatus(PlayerStatus.idle, message: '播放已停止');
      _uiUpdateTimer?.cancel(); // 停止UI更新定时器
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
    _episodeId = null; // 清除弹幕ID
    _animeId = null; // 清除弹幕ID
    _danmakuList.clear();
    _danmakuTracks.clear();
    _danmakuTrackEnabled.clear();
    _subtitleManager.clearSubtitleTrackInfo();
    danmakuController
        ?.dispose(); // Assuming danmakuController has a dispose method
    danmakuController = null;
    _duration = Duration.zero;
    _position = Duration.zero;
    _progress = 0.0;
    _error = null;
    _isAppBarHidden = false; // 重置平板设备菜单栏隐藏状态
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
    if (!_isErrorStopping) { // <<< MODIFIED HERE
      _error = null;
    }
    _currentVideoPath = null;
    _currentVideoHash = null;
    _currentThumbnailPath = null;
    _animeTitle = null;
    _episodeTitle = null;
    _episodeId = null; // 清除弹幕ID
    _animeId = null; // 清除弹幕ID
    _danmakuList.clear();
    _danmakuTracks.clear();
    _danmakuTrackEnabled.clear();
    _subtitleManager.clearSubtitleTrackInfo();
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

  // 右边缘悬浮菜单管理方法
  void setRightEdgeHovered(bool hovered) {
    if (_isRightEdgeHovered == hovered) return;
    
    _isRightEdgeHovered = hovered;
    _rightEdgeHoverTimer?.cancel();
    
    if (hovered) {
      // 鼠标进入右边缘，显示悬浮菜单
      _showHoverSettingsMenu();
    } else {
      // 鼠标离开右边缘，延迟隐藏菜单
      _rightEdgeHoverTimer = Timer(const Duration(milliseconds: 300), () {
        _hideHoverSettingsMenu();
      });
    }
    
    notifyListeners();
  }

  void _showHoverSettingsMenu() {
    if (_hoverSettingsMenuOverlay != null || _context == null) return;
    
    // 导入设置菜单组件，这里需要延迟导入避免循环依赖
    Future.microtask(() {
      if (_context != null && _context!.mounted) {
        _hoverSettingsMenuOverlay = OverlayEntry(
          builder: (context) {
            return _buildHoverSettingsMenu(context);
          },
        );
        
        Overlay.of(_context!).insert(_hoverSettingsMenuOverlay!);
      }
    });
  }

  void _hideHoverSettingsMenu() {
    _hoverSettingsMenuOverlay?.remove();
    _hoverSettingsMenuOverlay = null;
    _isRightEdgeHovered = false;
    notifyListeners();
  }

  Widget _buildHoverSettingsMenu(BuildContext context) {
    // 这里会在后面的组件中实现
    return const SizedBox.shrink();
  }

  // 已移除 _startPositionUpdateTimer，功能已合并到 _startUiUpdateTimer

  bool shouldShowAppBar() {
    if (globals.isPhone) {
      if (isTablet) {
        // 平板设备：根据 _isAppBarHidden 状态决定是否显示菜单栏
        return !hasVideo || !_isAppBarHidden;
      } else {
        // 手机设备：按原有逻辑
        return !hasVideo || !_isFullscreen;
      }
    }
    return !_isFullscreen;
  }

  @override
  void dispose() {
    // 在销毁前进行一次截图
    if (hasVideo) {
      _captureConditionalScreenshot("销毁前");
    }
    
    player.dispose();
    _focusNode.dispose();
    _uiUpdateTimer?.cancel(); // 清理UI更新定时器
    _hideControlsTimer?.cancel();
    _hideMouseTimer?.cancel();
    _autoHideTimer?.cancel();
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
    if (_speedBoostOverlayEntry != null) { // 清理倍速指示器
      _speedBoostOverlayEntry!.remove();
      _speedBoostOverlayEntry = null;
    }
    _rightEdgeHoverTimer?.cancel(); // 清理右边缘悬浮定时器
    if (_hoverSettingsMenuOverlay != null) { // 清理悬浮设置菜单
      _hoverSettingsMenuOverlay!.remove();
      _hoverSettingsMenuOverlay = null;
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
    if (videoPath.isEmpty) return;

    try {
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
                  
                  // 设置最终加载阶段标志，减少动画性能消耗
                  _isInFinalLoadingPhase = true;
                  notifyListeners();
                  
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

                // 设置最终加载阶段标志，减少动画性能消耗
                _isInFinalLoadingPhase = true;
                notifyListeners();
                
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
                  _danmakuTracks.clear();
                  _danmakuTrackEnabled.clear();
                }

                notifyListeners();
                _setStatus(PlayerStatus.recognizing, message: '弹幕加载完成 (${_danmakuList.length}条)');
              } catch (e) {
                //debugPrint('弹幕加载/解析错误: $e\n$s');
                _danmakuList = [];
                _danmakuTracks.clear();
                _danmakuTrackEnabled.clear();
                _setStatus(PlayerStatus.recognizing, message: '弹幕加载失败，跳过');
              }
            }
          } else {
            //debugPrint('视频未匹配到信息');
            _danmakuList = [];
            _danmakuTracks.clear();
            _danmakuTrackEnabled.clear();
            _setStatus(PlayerStatus.recognizing, message: '未匹配到视频信息，跳过弹幕');
          }
        }
      } catch (e) {
        //debugPrint('视频识别网络错误: $e\n$s');
        _danmakuList = [];
        _danmakuTracks.clear();
        _danmakuTrackEnabled.clear();
        _setStatus(PlayerStatus.recognizing, message: '无法连接服务器，跳过加载弹幕');
      }
    } catch (e) {
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
      WatchHistoryItem? existingHistory;
      
      if (_context != null && _context!.mounted) {
        final watchHistoryProvider = _context!.read<WatchHistoryProvider>();
        existingHistory = await watchHistoryProvider.getHistoryItem(path);
      } else {
        existingHistory = await WatchHistoryDatabase.instance.getHistoryByFilePath(path);
      }
      
      if (existingHistory == null) {
        //debugPrint('未找到现有观看记录，跳过更新');
        return;
      }

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
        // 如果 API 未提供有效名称，则使用现有记录中的名称
        resolvedAnimeName = existingHistory.animeName;
      }

      // 如果仍然没有动画名称，从文件名提取
      if (resolvedAnimeName.isEmpty) {
        final fileName = path.split('/').last;
        String extractedName = fileName.replaceAll(
            RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$', caseSensitive: false), '');
        extractedName = extractedName.replaceAll(RegExp(r'[_\.-]'), ' ').trim();

        resolvedAnimeName = extractedName.trim().isNotEmpty
            ? extractedName
            : "未知动画"; // 确保不会是空字符串
      }

      debugPrint(
          '识别到动画：$resolvedAnimeName，集数：${episodeTitle ?? '未知集数'}，animeId: $animeId, episodeId: $episodeId');

      // 更新当前动画标题和集数标题
      _animeTitle = resolvedAnimeName;
      _episodeTitle = episodeTitle;

      // 如果仍在加载/识别状态，并且成功识别出动画标题，则更新状态消息
      debugPrint('更新观看记录: $_animeTitle');
      String message = '正在加载: $_animeTitle';
      if (_episodeTitle != null && _episodeTitle!.isNotEmpty) {
        message += ' - $_episodeTitle';
      }
      // 直接设置状态和消息，但不改变PlayerStatus本身
      _setStatus(_status, message: message);

      notifyListeners();

      // 创建更新后的观看记录
      final updatedHistory = WatchHistoryItem(
        filePath: existingHistory.filePath,
        animeName: resolvedAnimeName,
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
        isFromScan: existingHistory.isFromScan,
      );

      debugPrint(
          '准备保存更新后的观看记录，动画名: ${updatedHistory.animeName}, 集数: ${updatedHistory.episodeTitle}');
      
      // 保存更新后的记录
      if (_context != null && _context!.mounted) {
        await _context!.read<WatchHistoryProvider>().addOrUpdateHistory(updatedHistory);
      } else {
        await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(updatedHistory);
      }
      
      debugPrint('成功更新观看记录');
    } catch (e) {
      debugPrint('更新观看记录时出错: $e');
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
      WatchHistoryItem? existingHistory;
      
      if (_context != null && _context!.mounted) {
        final watchHistoryProvider = _context!.read<WatchHistoryProvider>();
        existingHistory = await watchHistoryProvider.getHistoryItem(_currentVideoPath!);
      } else {
        existingHistory = await WatchHistoryDatabase.instance.getHistoryByFilePath(_currentVideoPath!);
      }

      if (existingHistory != null) {
        // 仅更新缩略图和时间戳，保留其他所有字段
        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: existingHistory.animeName,
          episodeTitle: existingHistory.episodeTitle,
          episodeId: _episodeId ?? existingHistory.episodeId, // 优先使用存储的 episodeId
          animeId: _animeId ?? existingHistory.animeId, // 优先使用存储的 animeId
          watchProgress: _progress, // 更新当前进度
          lastPosition: _position.inMilliseconds, // 更新当前位置
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
          isFromScan: existingHistory.isFromScan,
        );

        // 保存更新后的记录
        if (_context != null && _context!.mounted) {
          await _context!.read<WatchHistoryProvider>().addOrUpdateHistory(updatedHistory);
        } else {
          await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(updatedHistory);
        }
        
        debugPrint('观看记录缩略图已更新: $thumbnailPath');

        // 通知缩略图已更新，需要刷新UI
        _notifyThumbnailUpdateListeners();

        // 尝试刷新已显示的缩略图
        _triggerImageCacheRefresh(thumbnailPath);
      }
    } catch (e) {
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
    // 移除定时截图功能，改为条件性截图
    // 原先的定时截图代码已被删除
  }

  // 停止截图定时器
  void _stopScreenshotTimer() {
    // 不再需要停止定时器，但保留方法以避免其他地方调用出错
  }

  // 不暂停视频的截图方法
  Future<String?> _captureVideoFrameWithoutPausing() async {
    if (_currentVideoPath == null || !hasVideo) return null;

    try {
      // 使用适当的宽高比计算图像尺寸
      const int targetWidth = 0; // 使用0表示使用原始宽度
      const int targetHeight = 0; // 使用0表示使用原始高度

      // 使用Player的snapshot方法获取当前帧，保留原始宽高比
      final videoFrame = await player.snapshot(width: targetWidth, height: targetHeight);
      if (videoFrame == null) {
        debugPrint('截图失败: 播放器返回了null');
        return null;
      }
      
      // 检查截图尺寸
      debugPrint('获取到的截图尺寸: ${videoFrame.width}x${videoFrame.height}, 字节数: ${videoFrame.bytes.length}');

      // 使用缓存的哈希值或重新计算哈希值
      String videoFileHash;
      if (_currentVideoHash != null) {
        videoFileHash = _currentVideoHash!;
      } else {
        videoFileHash = await _calculateFileHash(_currentVideoPath!);
        _currentVideoHash = videoFileHash; // 缓存哈希值
      }

      // 创建缩略图目录
      final appDir = await StorageService.getAppStorageDirectory();
      final thumbnailDir = Directory('${appDir.path}/thumbnails');
      if (!thumbnailDir.existsSync()) {
        thumbnailDir.createSync(recursive: true);
      }

      // 保存缩略图文件路径
      final thumbnailPath = '${thumbnailDir.path}/$videoFileHash.png';
      final thumbnailFile = File(thumbnailPath);

      // 检查截图数据是否已经是PNG格式 (检查PNG文件头 - 89 50 4E 47)
      bool isPngFormat = false;
      if (videoFrame.bytes.length > 8) {
        isPngFormat = videoFrame.bytes[0] == 0x89 && 
                      videoFrame.bytes[1] == 0x50 && 
                      videoFrame.bytes[2] == 0x4E && 
                      videoFrame.bytes[3] == 0x47;
      }

      if (isPngFormat) {
        // 如果已经是PNG格式，直接保存
        debugPrint('检测到PNG格式的截图数据，直接保存');
        await thumbnailFile.writeAsBytes(videoFrame.bytes);
        debugPrint('成功保存PNG截图，大小: ${videoFrame.bytes.length} 字节');
        return thumbnailPath;
      } else {
        // 如果不是PNG格式，使用原有处理逻辑
        debugPrint('检测到非PNG格式的截图数据，进行转换处理');
        try {
          // 确定图像尺寸
          final width = videoFrame.width > 0 ? videoFrame.width : 1920; // 如果宽度为0，使用默认宽度
          final height = videoFrame.height > 0 ? videoFrame.height : 1080; // 如果高度为0，使用默认高度
          
          debugPrint('创建图像使用尺寸: ${width}x$height');
          
          // 从bytes创建图像
          final image = img.Image.fromBytes(
            width: width,
            height: height,
            bytes: videoFrame.bytes.buffer,
            numChannels: 4, // RGBA
          );

          // 检查图像是否成功创建
          if (image.width != width || image.height != height) {
            debugPrint('警告: 创建的图像尺寸(${image.width}x${image.height})与预期(${width}x$height)不符');
          }

          // 编码为PNG格式
          final pngBytes = img.encodePng(image);
          await thumbnailFile.writeAsBytes(pngBytes);
          
          debugPrint('成功保存转换后的截图，保留了${width}x$height的原始比例');
          return thumbnailPath;
        } catch (e) {
          debugPrint('处理图像数据时出错: $e');
          
          // 转换失败，尝试直接保存原始数据
          try {
            debugPrint('尝试直接保存原始截图数据');
            await thumbnailFile.writeAsBytes(videoFrame.bytes);
            debugPrint('成功保存原始截图数据');
            return thumbnailPath;
          } catch (e2) {
            debugPrint('直接保存原始数据也失败: $e2');
            return null;
          }
        }
      }
    } catch (e) {
      debugPrint('无暂停截图时出错: $e');
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
      // 使用屏幕方向管理器重置屏幕方向
      if (globals.isPhone) {
        await ScreenOrientationManager.instance.resetOrientation();
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
      debugPrint('尝试为episodeId=$episodeId, animeId=$animeIdStr加载弹幕');
      _setStatus(PlayerStatus.recognizing, message: '正在加载弹幕...');

      if (episodeId.isEmpty) {
        debugPrint('无效的episodeId，无法加载弹幕');
        _setStatus(PlayerStatus.recognizing, message: '无效的弹幕ID，跳过加载');
        return;
      }

      // 清除之前的弹幕数据
      debugPrint('清除之前的弹幕数据');
      _danmakuList.clear();
      danmakuController?.clearDanmaku();
      notifyListeners();

      // 更新内部状态变量，确保新的弹幕ID被保存
      final parsedAnimeId = int.tryParse(animeIdStr) ?? 0;
      final episodeIdInt = int.tryParse(episodeId) ?? 0;
      
      if (episodeIdInt > 0 && parsedAnimeId > 0) {
        _episodeId = episodeIdInt;
        _animeId = parsedAnimeId;
        debugPrint('更新内部弹幕ID状态: episodeId=$_episodeId, animeId=$_animeId');
      }

      // 从缓存加载弹幕
      final cachedDanmaku =
          await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (cachedDanmaku != null) {
        debugPrint('从缓存中找到弹幕数据，共${cachedDanmaku.length}条');
        _setStatus(PlayerStatus.recognizing, message: '正在从缓存加载弹幕...');
        
        // 设置最终加载阶段标志，减少动画性能消耗
        _isInFinalLoadingPhase = true;
        notifyListeners();
        
        // 加载弹幕到控制器
        danmakuController?.loadDanmaku(cachedDanmaku);
        _setStatus(PlayerStatus.playing,
            message: '从缓存加载弹幕完成 (${cachedDanmaku.length}条)');
        
        // 解析弹幕数据并添加到弹弹play轨道
        final parsedDanmaku = await compute(parseDanmakuListInBackground, cachedDanmaku as List<dynamic>?);
        
        _danmakuTracks['dandanplay'] = {
          'name': '弹弹play',
          'source': 'dandanplay',
          'episodeId': episodeId,
          'animeId': animeIdStr,
          'danmakuList': parsedDanmaku,
          'count': parsedDanmaku.length,
        };
        _danmakuTrackEnabled['dandanplay'] = true;
        
        // 重新计算合并后的弹幕列表
        _updateMergedDanmakuList();
        notifyListeners();
        return;
      }

      debugPrint('缓存中没有找到弹幕，从网络加载中...');
      // 从网络加载弹幕
      final animeId = int.tryParse(animeIdStr) ?? 0;
      
      // 设置最终加载阶段标志，减少动画性能消耗
      _isInFinalLoadingPhase = true;
      notifyListeners();
      
      final danmakuData = await DandanplayService.getDanmaku(episodeId, animeId)
                              .timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('加载弹幕超时');
      });
      
      if (danmakuData['comments'] != null && danmakuData['comments'] is List) {
        debugPrint('成功从网络加载弹幕，共${danmakuData['count']}条');
        
        // 加载弹幕到控制器
        danmakuController?.loadDanmaku(danmakuData['comments']);
        
        // 解析弹幕数据并添加到弹弹play轨道
        final parsedDanmaku = await compute(parseDanmakuListInBackground, danmakuData['comments'] as List<dynamic>?);
        
        _danmakuTracks['dandanplay'] = {
          'name': '弹弹play',
          'source': 'dandanplay',
          'episodeId': episodeId,
          'animeId': animeId.toString(),
          'danmakuList': parsedDanmaku,
          'count': parsedDanmaku.length,
        };
        _danmakuTrackEnabled['dandanplay'] = true;
        
        // 重新计算合并后的弹幕列表
        _updateMergedDanmakuList();
        
        _setStatus(PlayerStatus.playing,
            message: '弹幕加载完成 (${danmakuData['count']}条)');
        notifyListeners();
      } else {
        debugPrint('网络返回的弹幕数据无效');
        _setStatus(PlayerStatus.playing, message: '弹幕数据无效，跳过加载');
      }
    } catch (e) {
      debugPrint('加载弹幕失败: $e');
      _setStatus(PlayerStatus.playing, message: '弹幕加载失败');
    }
  }

  // 从本地JSON数据加载弹幕（多轨道模式）
  Future<void> loadDanmakuFromLocal(Map<String, dynamic> jsonData, {String? trackName}) async {
    try {
      debugPrint('开始从本地JSON加载弹幕...');
      
      // 解析弹幕数据，支持多种格式
      List<dynamic> comments = [];
      
      if (jsonData.containsKey('comments') && jsonData['comments'] is List) {
        // 标准格式：comments字段包含数组
        comments = jsonData['comments'];
      } else if (jsonData.containsKey('data')) {
        // 兼容格式：data字段
        final data = jsonData['data'];
        if (data is List) {
          // data是数组
          comments = data;
        } else if (data is String) {
          // data是字符串，需要解析
          try {
            final parsedData = json.decode(data);
            if (parsedData is List) {
              comments = parsedData;
            } else {
              throw Exception('data字段的JSON字符串不是数组格式');
            }
          } catch (e) {
            throw Exception('data字段的JSON字符串解析失败: $e');
          }
        } else {
          throw Exception('data字段格式不正确，应为数组或JSON字符串');
        }
      } else {
        throw Exception('JSON文件格式不正确，必须包含comments数组或data字段');
      }

      if (comments.isEmpty) {
        throw Exception('弹幕文件中没有弹幕数据');
      }

      // 解析弹幕数据
      final parsedDanmaku = await compute(parseDanmakuListInBackground, comments);
      
      // 生成轨道名称
      final String finalTrackName = trackName ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
      
      // 添加到本地轨道
      _danmakuTracks[finalTrackName] = {
        'name': trackName ?? '本地轨道${_danmakuTracks.length}',
        'source': 'local',
        'danmakuList': parsedDanmaku,
        'count': parsedDanmaku.length,
        'loadTime': DateTime.now(),
      };
      _danmakuTrackEnabled[finalTrackName] = true;
      
      // 重新计算合并后的弹幕列表
      _updateMergedDanmakuList();
      
      debugPrint('本地弹幕轨道添加完成: $finalTrackName，共${comments.length}条');
      _setStatus(PlayerStatus.playing, message: '本地弹幕轨道添加完成 (${comments.length}条)');
      notifyListeners();
      
    } catch (e) {
      debugPrint('加载本地弹幕失败: $e');
      _setStatus(PlayerStatus.playing, message: '本地弹幕加载失败');
      rethrow;
    }
  }

  // 更新合并后的弹幕列表
  void _updateMergedDanmakuList() {
    _danmakuList.clear();
    
    // 合并所有启用的轨道
    for (final trackId in _danmakuTracks.keys) {
      if (_danmakuTrackEnabled[trackId] == true) {
        final trackData = _danmakuTracks[trackId]!;
        final trackDanmaku = trackData['danmakuList'] as List<Map<String, dynamic>>;
        _danmakuList.addAll(trackDanmaku);
      }
    }
    
    // 重新排序
    _danmakuList.sort((a, b) {
      final timeA = (a['time'] as double?) ?? 0.0;
      final timeB = (b['time'] as double?) ?? 0.0;
      return timeA.compareTo(timeB);
    });
    
    // 更新到弹幕控制器
    danmakuController?.loadDanmaku(_danmakuList.map((e) => e).toList());
    
    debugPrint('弹幕轨道合并完成，总计${_danmakuList.length}条弹幕');
  }

  // 切换轨道启用状态
  void toggleDanmakuTrack(String trackId, bool enabled) {
    if (_danmakuTracks.containsKey(trackId)) {
      _danmakuTrackEnabled[trackId] = enabled;
      _updateMergedDanmakuList();
      notifyListeners();
      debugPrint('弹幕轨道 $trackId ${enabled ? "启用" : "禁用"}');
    }
  }

  // 删除弹幕轨道
  void removeDanmakuTrack(String trackId) {
    if (trackId == 'dandanplay') {
      debugPrint('不能删除弹弹play轨道');
      return;
    }
    
    if (_danmakuTracks.containsKey(trackId)) {
      _danmakuTracks.remove(trackId);
      _danmakuTrackEnabled.remove(trackId);
      _updateMergedDanmakuList();
      notifyListeners();
      debugPrint('删除弹幕轨道: $trackId');
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
      // 使用 Provider 获取播放记录
      WatchHistoryItem? existingHistory;
      
      if (_context != null && _context!.mounted) {
        final watchHistoryProvider = _context!.read<WatchHistoryProvider>();
        existingHistory = await watchHistoryProvider.getHistoryItem(_currentVideoPath!);
      } else {
        // 不使用 Provider 更新状态，避免不必要的 UI 刷新
        existingHistory = await WatchHistoryDatabase.instance.getHistoryByFilePath(_currentVideoPath!);
      }

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
        // 对于Jellyfin流媒体，优先使用当前实例变量中的友好名称（如果有的话）
        String finalAnimeName = existingHistory.animeName;
        String? finalEpisodeTitle = existingHistory.episodeTitle;
        
        // 检查是否是流媒体并且当前有更好的名称
        bool isJellyfinStream = _currentVideoPath!.startsWith('jellyfin://');
        bool isEmbyStream = _currentVideoPath!.startsWith('emby://');
        if ((isJellyfinStream || isEmbyStream) && _animeTitle != null && _animeTitle!.isNotEmpty) {
          // 对于流媒体，如果有友好名称，则使用友好名称
          finalAnimeName = _animeTitle!;
          if (_episodeTitle != null && _episodeTitle!.isNotEmpty) {
            finalEpisodeTitle = _episodeTitle!;
          }
          debugPrint('VideoPlayerState: 使用流媒体友好名称更新记录: $finalAnimeName - $finalEpisodeTitle');
        }
        
        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: finalAnimeName,
          episodeTitle: finalEpisodeTitle,
          episodeId: _episodeId ?? existingHistory.episodeId, // 优先使用存储的 episodeId
          animeId: _animeId ?? existingHistory.animeId, // 优先使用存储的 animeId
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
          isFromScan: existingHistory.isFromScan,
        );

        // 通过 Provider 更新记录
        if (_context != null && _context!.mounted) {
          await _context!.read<WatchHistoryProvider>().addOrUpdateHistory(updatedHistory);
        } else {
          // 直接使用数据库更新
          await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(updatedHistory);
        }
      } else {
        // 如果记录不存在，创建新记录
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
          animeName: initialAnimeName,
          episodeId: _episodeId, // 使用从 historyItem 传入的 episodeId
          animeId: _animeId, // 使用从 historyItem 传入的 animeId
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
          isFromScan: false,
        );

        // 通过 Provider 添加记录
        if (_context != null && _context!.mounted) {
          await _context!.read<WatchHistoryProvider>().addOrUpdateHistory(newHistory);
        } else {
          // 直接使用数据库添加
          await WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(newHistory);
        }
      }
    } catch (e) {
      debugPrint('更新观看记录时出错: $e');
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
          width: targetWidth, // Should be videoFrame.width
          height: targetHeight, // Should be videoFrame.height
          bytes: videoFrame.bytes.buffer, // CHANGED to get ByteBuffer
          numChannels: 4, 
        );

        // 编码为PNG格式
        final pngBytes = img.encodePng(image);

        // 创建缩略图目录
        final appDir = await StorageService.getAppStorageDirectory();
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
    // 先过滤掉被屏蔽的弹幕
    final filteredDanmakuList = getFilteredDanmakuList();
    
    // 然后在过滤后的列表中查找时间窗口内的弹幕
    return filteredDanmakuList.where((d) {
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
 // Check if volume property is available
      player.volume = newVolume; 
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

  static const int _textureIdCounter = 0;
  static const double _volumeStep = 0.05; // 5% volume change per key press

  void increaseVolume({double? step}) {
    if (globals.isPhone) return; // Only for PC

    try {
      // Prioritize actual player volume, fallback to _currentVolume
      double currentVolume = player.volume ?? _currentVolume;
      double newVolume = (currentVolume + (step ?? _volumeStep)).clamp(0.0, 1.0);
      
      player.volume = newVolume;
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

      player.volume = newVolume;
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
    // 修改灵敏度：1像素约等于6秒，这样轻滑动大约10-15像素就是10秒左右
    const double pixelsPerSecond = 6.0; // 增大数值以减少灵敏度(原来是1.0)
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
      Overlay.of(_context!).insert(_seekOverlayEntry!); 
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

  // 显示倍速指示器
  void _showSpeedBoostIndicator() {
    if (!globals.isPhone || _context == null) return;

    if (_speedBoostOverlayEntry == null) {
      _speedBoostOverlayEntry = OverlayEntry(
        builder: (context) {
          return ChangeNotifierProvider<VideoPlayerState>.value(
            value: this,
            child: const SpeedBoostIndicator(),
          );
        },
      );
      Overlay.of(_context!).insert(_speedBoostOverlayEntry!);
    }
  }

  // 隐藏倍速指示器
  void _hideSpeedBoostIndicator() {
    if (!globals.isPhone) return;

    // Wait for fade-out animation to complete before removing
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_speedBoostOverlayEntry != null) {
        _speedBoostOverlayEntry!.remove();
        _speedBoostOverlayEntry = null;
      }
    });
  }

  // 获取字幕轨道的语言名称
  String _getLanguageName(String language) {
    // 语言代码映射
    final Map<String, String> languageCodes = {
      'chi': '中文',
      'eng': '英文',
      'jpn': '日语',
      'kor': '韩语',
      'fra': '法语',
      'deu': '德语',
      'spa': '西班牙语',
      'ita': '意大利语',
      'rus': '俄语',
    };
    
    // 常见的语言标识符
    final Map<String, String> languagePatterns = {
      r'chi|chs|zh|中文|简体|繁体|chi.*?simplified|chinese': '中文',
      r'eng|en|英文|english': '英文',
      r'jpn|ja|日文|japanese': '日语',
      r'kor|ko|韩文|korean': '韩语',
      r'fra|fr|法文|french': '法语',
      r'ger|de|德文|german': '德语',
      r'spa|es|西班牙文|spanish': '西班牙语',
      r'ita|it|意大利文|italian': '意大利语',
      r'rus|ru|俄文|russian': '俄语',
    };

    // 首先检查语言代码映射
    final mappedLanguage = languageCodes[language.toLowerCase()];
    if (mappedLanguage != null) {
      return mappedLanguage;
    }

    // 然后检查语言标识符
    for (final entry in languagePatterns.entries) {
      final pattern = RegExp(entry.key, caseSensitive: false);
      if (pattern.hasMatch(language.toLowerCase())) {
        return entry.value;
      }
    }

    return language;
  }

  // 更新指定的字幕轨道信息
  void _updateSubtitleTracksInfo(int trackIndex) {
    if (player.mediaInfo.subtitle == null || 
        trackIndex >= player.mediaInfo.subtitle!.length) {
      return;
    }
    
    final track = player.mediaInfo.subtitle![trackIndex];
    // 尝试从track中提取title和language
    String title = '轨道 $trackIndex';
    String language = '未知';
    
    final fullString = track.toString();
    if (fullString.contains('metadata: {')) {
      final metadataStart = fullString.indexOf('metadata: {') + 'metadata: {'.length;
      final metadataEnd = fullString.indexOf('}', metadataStart);
      
      if (metadataEnd > metadataStart) {
        final metadataStr = fullString.substring(metadataStart, metadataEnd);
        
        // 提取title
        final titleMatch = RegExp(r'title: ([^,}]+)').firstMatch(metadataStr);
        if (titleMatch != null) {
          title = titleMatch.group(1)?.trim() ?? title;
        }
        
        // 提取language
        final languageMatch = RegExp(r'language: ([^,}]+)').firstMatch(metadataStr);
        if (languageMatch != null) {
          language = languageMatch.group(1)?.trim() ?? language;
          // 获取映射后的语言名称
          language = _getLanguageName(language);
        }
      }
    }
    
    // 更新VideoPlayerState的字幕轨道信息
    _subtitleManager.updateSubtitleTrackInfo('embedded_subtitle_$trackIndex', {
      'index': trackIndex,
      'title': title,
      'language': language,
      'isActive': player.activeSubtitleTracks.contains(trackIndex)
    });
    
    // 清除外部字幕信息的激活状态
    if (player.activeSubtitleTracks.contains(trackIndex) && 
        _subtitleManager.subtitleTrackInfo.containsKey('external_subtitle')) {
      _subtitleManager.updateSubtitleTrackInfo('external_subtitle', {
        'isActive': false
      });
    }
  }
  
  // 更新所有字幕轨道信息
  void _updateAllSubtitleTracksInfo() {
    if (player.mediaInfo.subtitle == null) {
      return;
    }
    
    // 清除之前的内嵌字幕轨道信息
    for (final key in List.from(_subtitleManager.subtitleTrackInfo.keys)) {
      if (key.startsWith('embedded_subtitle_')) {
        _subtitleManager.subtitleTrackInfo.remove(key);
      }
    }
    
    // 更新所有内嵌字幕轨道信息
    for (var i = 0; i < player.mediaInfo.subtitle!.length; i++) {
      _updateSubtitleTracksInfo(i);
    }
    
    // 在更新完成后检查当前激活的字幕轨道并确保相应的信息被更新
    if (player.activeSubtitleTracks.isNotEmpty) {
      final activeIndex = player.activeSubtitleTracks.first;
      if (activeIndex > 0 && activeIndex <= player.mediaInfo.subtitle!.length) {
        // 激活的是内嵌字幕轨道
        _subtitleManager.updateSubtitleTrackInfo('embedded_subtitle', {
          'index': activeIndex - 1, // MDK 字幕轨道从 1 开始，而我们的索引从 0 开始
          'title': player.mediaInfo.subtitle![activeIndex - 1].toString(),
          'isActive': true,
        });
        
        // 通知字幕轨道变化
        _subtitleManager.onSubtitleTrackChanged();
      }
    }
    
    notifyListeners();
  }

  // 设置当前外部字幕路径
  void setCurrentExternalSubtitlePath(String path) {
    _subtitleManager.setCurrentExternalSubtitlePath(path);
    //debugPrint('设置当前外部字幕路径: $path');
  }

  // 设置外部字幕并更新路径
  void setExternalSubtitle(String path, {bool isManualSetting = false}) {
    _subtitleManager.setExternalSubtitle(path, isManualSetting: isManualSetting);
  }

  // 强制设置外部字幕（手动操作）
  void forceSetExternalSubtitle(String path) {
    _subtitleManager.forceSetExternalSubtitle(path);
  }
  
  // 桥接方法：预加载字幕文件
  Future<void> preloadSubtitleFile(String path) async {
    await _subtitleManager.preloadSubtitleFile(path);
  }
  
  // 桥接方法：获取当前活跃的外部字幕文件路径
  String? getActiveExternalSubtitlePath() {
    return _subtitleManager.getActiveExternalSubtitlePath();
  }
  
  // 桥接方法：获取当前显示的字幕文本
  String getCurrentSubtitleText() {
    return _subtitleManager.getCurrentSubtitleText();
  }
  
  // 桥接方法：当字幕轨道改变时调用
  void onSubtitleTrackChanged() {
    _subtitleManager.onSubtitleTrackChanged();
  }
  
  // 桥接方法：获取缓存的字幕内容
  List<dynamic>? getCachedSubtitle(String path) {
    return _subtitleManager.getCachedSubtitle(path);
  }
  
  // 桥接方法：获取弹幕/字幕轨道信息
  Map<String, Map<String, dynamic>> get danmakuTrackInfo => _subtitleManager.subtitleTrackInfo;
  
  // 桥接方法：更新弹幕/字幕轨道信息
  void updateDanmakuTrackInfo(String key, Map<String, dynamic> info) {
    _subtitleManager.updateSubtitleTrackInfo(key, info);
  }
  
  // 桥接方法：清除弹幕/字幕轨道信息
  void clearDanmakuTrackInfo() {
    _subtitleManager.clearSubtitleTrackInfo();
  }

  // 自动检测并加载同名字幕文件
  Future<void> _autoDetectAndLoadSubtitle(String videoPath) async {
    // 此方法不再需要，我们使用subtitleManager的方法代替
    await _subtitleManager.autoDetectAndLoadSubtitle(videoPath);
  }

  // 加载顶部弹幕屏蔽设置
  Future<void> _loadBlockTopDanmaku() async {
    final prefs = await SharedPreferences.getInstance();
    _blockTopDanmaku = prefs.getBool(_blockTopDanmakuKey) ?? false;
    notifyListeners();
  }
  
  // 设置顶部弹幕屏蔽
  Future<void> setBlockTopDanmaku(bool block) async {
    if (_blockTopDanmaku != block) {
      _blockTopDanmaku = block;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_blockTopDanmakuKey, block);
      notifyListeners();
    }
  }
  
  // 加载底部弹幕屏蔽设置
  Future<void> _loadBlockBottomDanmaku() async {
    final prefs = await SharedPreferences.getInstance();
    _blockBottomDanmaku = prefs.getBool(_blockBottomDanmakuKey) ?? false;
    notifyListeners();
  }
  
  // 设置底部弹幕屏蔽
  Future<void> setBlockBottomDanmaku(bool block) async {
    if (_blockBottomDanmaku != block) {
      _blockBottomDanmaku = block;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_blockBottomDanmakuKey, block);
      notifyListeners();
    }
  }
  
  // 加载滚动弹幕屏蔽设置
  Future<void> _loadBlockScrollDanmaku() async {
    final prefs = await SharedPreferences.getInstance();
    _blockScrollDanmaku = prefs.getBool(_blockScrollDanmakuKey) ?? false;
    notifyListeners();
  }
  
  // 设置滚动弹幕屏蔽
  Future<void> setBlockScrollDanmaku(bool block) async {
    if (_blockScrollDanmaku != block) {
      _blockScrollDanmaku = block;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_blockScrollDanmakuKey, block);
      notifyListeners();
    }
  }
  
  // 加载弹幕屏蔽词列表
  Future<void> _loadDanmakuBlockWords() async {
    final prefs = await SharedPreferences.getInstance();
    final blockWordsJson = prefs.getString(_danmakuBlockWordsKey);
    if (blockWordsJson != null && blockWordsJson.isNotEmpty) {
      try {
        final List<dynamic> decodedList = json.decode(blockWordsJson);
        _danmakuBlockWords = decodedList.map((e) => e.toString()).toList();
      } catch (e) {
        debugPrint('加载弹幕屏蔽词失败: $e');
        _danmakuBlockWords = [];
      }
    } else {
      _danmakuBlockWords = [];
    }
    notifyListeners();
  }
  
  // 添加弹幕屏蔽词
  Future<void> addDanmakuBlockWord(String word) async {
    if (word.isNotEmpty && !_danmakuBlockWords.contains(word)) {
      _danmakuBlockWords.add(word);
      await _saveDanmakuBlockWords();
      notifyListeners();
    }
  }
  
  // 移除弹幕屏蔽词
  Future<void> removeDanmakuBlockWord(String word) async {
    if (_danmakuBlockWords.contains(word)) {
      _danmakuBlockWords.remove(word);
      await _saveDanmakuBlockWords();
      notifyListeners();
    }
  }
  
  // 保存弹幕屏蔽词列表
  Future<void> _saveDanmakuBlockWords() async {
    final prefs = await SharedPreferences.getInstance();
    final blockWordsJson = json.encode(_danmakuBlockWords);
    await prefs.setString(_danmakuBlockWordsKey, blockWordsJson);
  }
  
  // 检查弹幕是否应该被屏蔽
  bool shouldBlockDanmaku(Map<String, dynamic> danmaku) {
    // 检查弹幕类型是否应该被屏蔽
    final type = danmaku['type'] as String? ?? 'scroll';
    if (_blockTopDanmaku && type == 'top') return true;
    if (_blockBottomDanmaku && type == 'bottom') return true;
    if (_blockScrollDanmaku && type == 'scroll') return true;
    
    // 检查弹幕内容是否包含屏蔽词
    final content = danmaku['content'] as String? ?? '';
    for (final word in _danmakuBlockWords) {
      if (content.contains(word)) return true;
    }
    
    return false;
  }
  
  // 获取过滤后的弹幕列表
  List<Map<String, dynamic>> getFilteredDanmakuList() {
    return _danmakuList.where((danmaku) => !shouldBlockDanmaku(danmaku)).toList();
  }

  // 添加setter用于设置外部字幕自动加载回调
  set onExternalSubtitleAutoLoaded(Function(String, String)? callback) {
    _subtitleManager.onExternalSubtitleAutoLoaded = callback;
  }

  // 在文件选择后立即设置加载状态，显示加载界面
  void setPreInitLoadingState(String message) {
    _statusMessages.clear(); // 清除之前的状态消息
    _setStatus(PlayerStatus.loading, message: message);
    // 确保状态变更立即生效
    notifyListeners();
  }

  // 更新解码器设置，代理到解码器管理器
  void updateDecoders(List<String> decoders) {
    _decoderManager.updateDecoders(decoders);
    notifyListeners();
  }
  
  // 播放速度相关方法
  
  // 加载播放速度设置
  Future<void> _loadPlaybackRate() async {
    final prefs = await SharedPreferences.getInstance();
    _playbackRate = prefs.getDouble(_playbackRateKey) ?? 2.0;
    _normalPlaybackRate = 1.0; // 始终重置为1.0
    notifyListeners();
  }
  
  // 保存播放速度设置
  Future<void> setPlaybackRate(double rate) async {
    _playbackRate = rate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playbackRateKey, rate);
    
    // 立即应用新的播放速度
    if (hasVideo) {
      player.setPlaybackRate(rate);
      debugPrint('设置播放速度: ${rate}x');
    }
    notifyListeners();
  }
  
  // 开始倍速播放（长按开始）
  void startSpeedBoost() {
    if (!hasVideo || _isSpeedBoostActive) return;
    
    // 保存当前播放速度，以便长按结束时恢复
    _normalPlaybackRate = _playbackRate;
    _isSpeedBoostActive = true;
    
    // 固定使用2倍速
    player.setPlaybackRate(2.0);
    debugPrint('开始长按倍速播放: 2.0x (之前: ${_normalPlaybackRate}x)');
    
    // 显示倍速指示器
    _showSpeedBoostIndicator();
    
    notifyListeners();
  }
  
  // 结束倍速播放（长按结束）
  void stopSpeedBoost() {
    if (!hasVideo || !_isSpeedBoostActive) return;
    
    _isSpeedBoostActive = false;
    // 恢复到长按前的播放速度
    player.setPlaybackRate(_normalPlaybackRate);
    debugPrint('结束长按倍速播放，恢复到: ${_normalPlaybackRate}x');
    
    // 隐藏倍速指示器
    _hideSpeedBoostIndicator();
    
    notifyListeners();
  }
  
  // 切换播放速度按钮功能
  void togglePlaybackRate() {
    if (!hasVideo) return;
    
    if (_isSpeedBoostActive) {
      // 如果正在长按倍速播放，结束长按
      stopSpeedBoost();
    } else {
      // 智能切换播放速度：在1倍速和2倍速之间切换
      if (_playbackRate == 1.0) {
        // 当前是1倍速，切换到2倍速
        setPlaybackRate(2.0);
      } else {
        // 当前是其他倍速，切换到1倍速
        setPlaybackRate(1.0);
      }
    }
  }
  
  // 获取当前活跃解码器，代理到解码器管理器
  Future<String> getActiveDecoder() async {
    final decoder = await _decoderManager.getActiveDecoder();
    // 更新系统资源监视器的解码器信息
    SystemResourceMonitor().setActiveDecoder(decoder);
    return decoder;
  }

  // 更新当前活跃解码器信息，代理到解码器管理器
  Future<void> _updateCurrentActiveDecoder() async {
    if (_status == PlayerStatus.playing || _status == PlayerStatus.paused) {
      await _decoderManager.updateCurrentActiveDecoder();
      // 由于DecoderManager的updateCurrentActiveDecoder已经会更新系统资源监视器的解码器信息，这里不需要重复
    }
  }

  // 强制启用硬件解码，代理到解码器管理器
  Future<void> forceEnableHardwareDecoder() async {
        if (_status == PlayerStatus.playing || _status == PlayerStatus.paused) {
      await _decoderManager.forceEnableHardwareDecoder();
      // 稍后检查解码器状态
      await Future.delayed(const Duration(seconds: 1));
      await _updateCurrentActiveDecoder();
    }
  }

  // 添加返回按钮处理
  Future<bool> handleBackButton() async {
    if (_isFullscreen) {
      await toggleFullscreen();
      return false; // 不退出应用
    } else {
      // 在返回按钮点击时进行截图
      _captureConditionalScreenshot("返回按钮时");
      
      // 等待截图完成
      await Future.delayed(const Duration(milliseconds: 200));
      
      return true; // 允许返回
    }
  }

  // 条件性截图方法
  Future<void> _captureConditionalScreenshot(String triggerEvent) async {
    if (_currentVideoPath == null || !hasVideo || _isCapturingFrame) return;
    
    _isCapturingFrame = true;
    try {
      final newThumbnailPath = await _captureVideoFrameWithoutPausing();
      if (newThumbnailPath != null) {
        _currentThumbnailPath = newThumbnailPath;
        debugPrint('条件截图完成($triggerEvent): $_currentThumbnailPath');
        
        // 更新观看记录中的缩略图
        await _updateWatchHistoryWithNewThumbnail(newThumbnailPath);
        
        // 截图后检查解码器状态
        await _decoderManager.checkDecoderAfterScreenshot();
      }
    } catch (e) {
      debugPrint('条件截图失败($triggerEvent): $e');
    } finally {
      _isCapturingFrame = false;
    }
  }

  // 处理流媒体URL的加载错误
  Future<void> _handleStreamUrlLoadingError(String videoPath, Exception e) async {
    debugPrint('流媒体URL加载失败: $videoPath, 错误: $e');
    
    // 检查是否为流媒体 URL
    if (videoPath.contains('jellyfin') || videoPath.contains('/Videos/')) {
      _setStatus(PlayerStatus.error, message: 'Jellyfin流媒体加载失败，请检查网络连接');
      _error = '无法连接到Jellyfin服务器，请确保网络连接正常';
    } else if (videoPath.contains('emby') || videoPath.contains('/emby/Videos/')) {
      _setStatus(PlayerStatus.error, message: 'Emby流媒体加载失败，请检查网络连接');
      _error = '无法连接到Emby服务器，请确保网络连接正常';
    } else {
      _setStatus(PlayerStatus.error, message: '流媒体加载失败，请检查网络连接');
      _error = '无法加载流媒体，请检查URL和网络连接';
    }
    
    // 通知监听器
    notifyListeners();
  }

  // 检查是否是流媒体视频并使用现有的IDs直接加载弹幕
  Future<bool> _checkAndLoadStreamingDanmaku(String videoPath, WatchHistoryItem? historyItem) async {
    // 检查是否是Jellyfin视频URL (多种可能格式)
    bool isJellyfinStream = videoPath.startsWith('jellyfin://') || 
                           (videoPath.contains('jellyfin') && videoPath.startsWith('http')) ||
                           (videoPath.contains('/Videos/') && videoPath.contains('/stream')) ||
                           (videoPath.contains('MediaSourceId=') && videoPath.contains('api_key='));
    
    // 检查是否是Emby视频URL (多种可能格式)
    bool isEmbyStream = videoPath.startsWith('emby://') || 
                       (videoPath.contains('emby') && videoPath.startsWith('http')) ||
                       (videoPath.contains('/emby/Videos/') && videoPath.contains('/stream')) ||
                       (videoPath.contains('api_key=') && videoPath.contains('emby'));
                           
    if ((isJellyfinStream || isEmbyStream) && historyItem != null) {
      debugPrint('检测到流媒体视频URL: $videoPath (Jellyfin: $isJellyfinStream, Emby: $isEmbyStream)');
      
      // 检查historyItem是否包含所需的danmaku IDs
      if (historyItem.episodeId != null && historyItem.animeId != null) {
        debugPrint('使用historyItem的IDs直接加载Jellyfin弹幕: episodeId=${historyItem.episodeId}, animeId=${historyItem.animeId}');
        
        try {
          // 使用已有的episodeId和animeId直接加载弹幕，跳过文件哈希计算
          _setStatus(PlayerStatus.recognizing, message: '正在为Jellyfin流媒体加载弹幕...');
          loadDanmaku(historyItem.episodeId.toString(), historyItem.animeId.toString());
          
          // 更新当前实例的弹幕ID
          _episodeId = historyItem.episodeId;
          _animeId = historyItem.animeId;
          
          // 如果历史记录中有正确的动画名称和剧集标题，立即更新当前实例
          if (historyItem.animeName.isNotEmpty && historyItem.animeName != 'Unknown') {
            _animeTitle = historyItem.animeName;
            _episodeTitle = historyItem.episodeTitle;
            debugPrint('[流媒体弹幕] 从历史记录更新标题: $_animeTitle - $_episodeTitle');
            
            // 立即更新历史记录，确保UI显示正确的信息
            await _updateHistoryWithNewTitles();
          }
          
          return true; // 表示已处理
        } catch (e) {
          debugPrint('Jellyfin流媒体弹幕加载失败: $e');
          _danmakuList = [];
          _danmakuTracks.clear();
          _danmakuTrackEnabled.clear();
          _setStatus(PlayerStatus.recognizing, message: 'Jellyfin弹幕加载失败，跳过');
          return true; // 尽管失败，但仍标记为已处理
        }
      } else {
        debugPrint('Jellyfin流媒体historyItem缺少弹幕IDs: episodeId=${historyItem.episodeId}, animeId=${historyItem.animeId}');
        _setStatus(PlayerStatus.recognizing, message: 'Jellyfin视频匹配数据不完整，跳过弹幕');
      }
    }
    return false; // 表示未处理
  }

  // 播放完成时回传观看记录到弹弹play
  Future<void> _submitWatchHistoryToDandanplay() async {
    // 检查是否已登录弹弹play账号
    if (!DandanplayService.isLoggedIn) {
      debugPrint('[观看记录] 未登录弹弹play账号，跳过回传观看记录');
      return;
    }
    
    if (_currentVideoPath == null || _episodeId == null) {
      debugPrint('[观看记录] 缺少必要信息（视频路径或episodeId），跳过回传观看记录');
      return;
    }

    try {
      debugPrint('[观看记录] 开始向弹弹play提交观看记录: episodeId=$_episodeId');
      
      final result = await DandanplayService.addPlayHistory(
        episodeIdList: [_episodeId!],
        addToFavorite: false,
        rating: 0,
      );
      
      if (result['success'] == true) {
        debugPrint('[观看记录] 观看记录提交成功');
      } else {
        debugPrint('[观看记录] 观看记录提交失败: ${result['errorMessage']}');
      }
    } catch (e) {
      debugPrint('[观看记录] 提交观看记录时出错: $e');
    }
  }
  
  // 检查是否可以播放上一话
  bool get canPlayPreviousEpisode {
    if (_currentVideoPath == null) return false;
    
    final navigationService = EpisodeNavigationService.instance;
    
    // 如果有剧集信息，可以使用数据库导航
    if (navigationService.canUseDatabaseNavigation(_animeId, _episodeId)) {
      return true;
    }
    
    // 如果是本地文件，可以使用文件系统导航
    if (navigationService.canUseFileSystemNavigation(_currentVideoPath!)) {
      return true;
    }
    
    return false;
  }
  
  // 检查是否可以播放下一话
  bool get canPlayNextEpisode {
    if (_currentVideoPath == null) return false;
    
    final navigationService = EpisodeNavigationService.instance;
    
    // 如果有剧集信息，可以使用数据库导航
    if (navigationService.canUseDatabaseNavigation(_animeId, _episodeId)) {
      return true;
    }
    
    // 如果是本地文件，可以使用文件系统导航
    if (navigationService.canUseFileSystemNavigation(_currentVideoPath!)) {
      return true;
    }
    
    return false;
  }
  
  // 播放上一话
  Future<void> playPreviousEpisode() async {
    if (!canPlayPreviousEpisode || _currentVideoPath == null) {
      debugPrint('[上一话] 无法播放上一话：检查条件不满足');
      return;
    }
    
    try {
      debugPrint('[上一话] 开始使用剧集导航服务查找上一话');
      
      // 暂停当前视频
      if (_status == PlayerStatus.playing) {
        togglePlayPause();
      }
      
      // 使用剧集导航服务
      final navigationService = EpisodeNavigationService.instance;
      final result = await navigationService.getPreviousEpisode(
        currentFilePath: _currentVideoPath!,
        animeId: _animeId,
        episodeId: _episodeId,
      );
      
      if (result.success) {
        debugPrint('[上一话] ${result.message}');
        
        // 根据结果类型调用不同的播放逻辑
        if (result.historyItem != null) {
          // 从数据库找到的剧集，包含完整的历史信息
          final historyItem = result.historyItem!;
          
          // 检查是否为Jellyfin或Emby流媒体，如果是则需要获取实际的HTTP URL
          if (historyItem.filePath.startsWith('jellyfin://')) {
            try {
              // 从jellyfin://协议URL中提取episodeId（简单格式：jellyfin://episodeId）
              final episodeId = historyItem.filePath.replaceFirst('jellyfin://', '');
              // 获取实际的HTTP流媒体URL
              final actualPlayUrl = JellyfinService.instance.getStreamUrl(episodeId);
              debugPrint('[上一话] 获取Jellyfin流媒体URL: $actualPlayUrl');
              
              // 使用Jellyfin协议URL作为标识符，HTTP URL作为实际播放源
              await initializePlayer(
                historyItem.filePath, 
                historyItem: historyItem, 
                actualPlayUrl: actualPlayUrl
              );
            } catch (e) {
              debugPrint('[上一话] 获取Jellyfin流媒体URL失败: $e');
              _showEpisodeErrorMessage('上一话', '获取流媒体URL失败: $e');
              return;
            }
          } else if (historyItem.filePath.startsWith('emby://')) {
            try {
              // 从emby://协议URL中提取episodeId（只取最后一部分）
              final embyPath = historyItem.filePath.replaceFirst('emby://', '');
              final pathParts = embyPath.split('/');
              final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
              // 获取实际的HTTP流媒体URL
              final actualPlayUrl = EmbyService.instance.getStreamUrl(episodeId);
              debugPrint('[上一话] 获取Emby流媒体URL: $actualPlayUrl');
              
              // 使用Emby协议URL作为标识符，HTTP URL作为实际播放源
              await initializePlayer(
                historyItem.filePath, 
                historyItem: historyItem, 
                actualPlayUrl: actualPlayUrl
              );
            } catch (e) {
              debugPrint('[上一话] 获取Emby流媒体URL失败: $e');
              _showEpisodeErrorMessage('上一话', '获取流媒体URL失败: $e');
              return;
            }
          } else {
            // 本地文件或其他类型
            await initializePlayer(historyItem.filePath, historyItem: historyItem);
          }
        } else if (result.filePath != null) {
          // 从文件系统找到的文件，需要创建基本的历史记录
          await initializePlayer(result.filePath!);
        }
      } else {
        debugPrint('[上一话] ${result.message}');
        _showEpisodeNotFoundMessage('上一话');
      }
    } catch (e) {
      debugPrint('[上一话] 播放上一话时出错：$e');
      _showEpisodeErrorMessage('上一话', e.toString());
    }
  }
  
  // 播放下一话
  Future<void> playNextEpisode() async {
    if (!canPlayNextEpisode || _currentVideoPath == null) {
      debugPrint('[下一话] 无法播放下一话：检查条件不满足');
      return;
    }
    
    try {
      debugPrint('[下一话] 开始使用剧集导航服务查找下一话');
      
      // 暂停当前视频
      if (_status == PlayerStatus.playing) {
        togglePlayPause();
      }
      
      // 使用剧集导航服务
      final navigationService = EpisodeNavigationService.instance;
      final result = await navigationService.getNextEpisode(
        currentFilePath: _currentVideoPath!,
        animeId: _animeId,
        episodeId: _episodeId,
      );
      
      if (result.success) {
        debugPrint('[下一话] ${result.message}');
        
        // 根据结果类型调用不同的播放逻辑
        if (result.historyItem != null) {
          // 从数据库找到的剧集，包含完整的历史信息
          final historyItem = result.historyItem!;
          
          // 检查是否为Jellyfin或Emby流媒体，如果是则需要获取实际的HTTP URL
          if (historyItem.filePath.startsWith('jellyfin://')) {
            try {
              // 从jellyfin://协议URL中提取episodeId（简单格式：jellyfin://episodeId）
              final episodeId = historyItem.filePath.replaceFirst('jellyfin://', '');
              // 获取实际的HTTP流媒体URL
              final actualPlayUrl = JellyfinService.instance.getStreamUrl(episodeId);
              debugPrint('[下一话] 获取Jellyfin流媒体URL: $actualPlayUrl');
              
              // 使用Jellyfin协议URL作为标识符，HTTP URL作为实际播放源
              await initializePlayer(
                historyItem.filePath, 
                historyItem: historyItem, 
                actualPlayUrl: actualPlayUrl
              );
            } catch (e) {
              debugPrint('[下一话] 获取Jellyfin流媒体URL失败: $e');
              _showEpisodeErrorMessage('下一话', '获取流媒体URL失败: $e');
              return;
            }
          } else if (historyItem.filePath.startsWith('emby://')) {
            try {
              // 从emby://协议URL中提取episodeId（只取最后一部分）
              final embyPath = historyItem.filePath.replaceFirst('emby://', '');
              final pathParts = embyPath.split('/');
              final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
              // 获取实际的HTTP流媒体URL
              final actualPlayUrl = EmbyService.instance.getStreamUrl(episodeId);
              debugPrint('[下一话] 获取Emby流媒体URL: $actualPlayUrl');
              
              // 使用Emby协议URL作为标识符，HTTP URL作为实际播放源
              await initializePlayer(
                historyItem.filePath, 
                historyItem: historyItem, 
                actualPlayUrl: actualPlayUrl
              );
            } catch (e) {
              debugPrint('[下一话] 获取Emby流媒体URL失败: $e');
              _showEpisodeErrorMessage('下一话', '获取流媒体URL失败: $e');
              return;
            }
          } else {
            // 本地文件或其他类型
            await initializePlayer(historyItem.filePath, historyItem: historyItem);
          }
        } else if (result.filePath != null) {
          // 从文件系统找到的文件，需要创建基本的历史记录
          await initializePlayer(result.filePath!);
        }
      } else {
        debugPrint('[下一话] ${result.message}');
        _showEpisodeNotFoundMessage('下一话');
      }
    } catch (e) {
      debugPrint('[下一话] 播放下一话时出错：$e');
      _showEpisodeErrorMessage('下一话', e.toString());
    }
  }
  

  
  // 显示剧集未找到的消息
  void _showEpisodeNotFoundMessage(String episodeType) {
    if (_context != null) {
      final message = '没有找到可播放的$episodeType';
      debugPrint('[剧集切换] $message');
      // 这里可以添加SnackBar或其他UI提示
      // ScaffoldMessenger.of(_context!).showSnackBar(
      //   SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      // );
    }
  }
  
  // 显示剧集错误消息
  void _showEpisodeErrorMessage(String episodeType, String error) {
    if (_context != null) {
      final message = '播放$episodeType时出错：$error';
      debugPrint('[剧集切换] $message');
      // 这里可以添加SnackBar或其他UI提示
      // ScaffoldMessenger.of(_context!).showSnackBar(
      //   SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      // );
    }
  }

    // 启动UI更新定时器（500ms更新一次，同时处理数据保存）
  void _startUiUpdateTimer() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isSeeking && hasVideo) {
        if (_status == PlayerStatus.playing) {
          final playerPosition = player.position;
          final playerDuration = player.mediaInfo.duration;
          
          if (playerPosition >= 0 && playerDuration > 0) {
            // 更新UI显示
            _position = Duration(milliseconds: playerPosition);
            _duration = Duration(milliseconds: playerDuration);
            _progress = _position.inMilliseconds / _duration.inMilliseconds;
            
            // 保存播放位置（原来在10秒定时器中）
            _saveVideoPosition(_currentVideoPath!, _position.inMilliseconds);

            // 每10秒更新一次观看记录（减少数据库写入频率）
            if (_position.inMilliseconds % 10000 < 500) { 
              _updateWatchHistory();
            }

            // 检测播放结束
            if (_position.inMilliseconds >= _duration.inMilliseconds - 100) {
              player.state = PlaybackState.paused;
              _setStatus(PlayerStatus.paused, message: '播放结束');
              if (_currentVideoPath != null) {
                _saveVideoPosition(_currentVideoPath!, 0);
                debugPrint(
                    'VideoPlayerState: Video ended, explicitly saved position 0 for $_currentVideoPath');
                
                // 触发自动播放下一话
                if (_context != null && _context!.mounted) {
                  AutoNextEpisodeService.instance.startAutoNextEpisode(_context!, _currentVideoPath!);
                }
              }
            }
            
            notifyListeners();
          } else {
            // 错误处理逻辑（原来在10秒定时器中）
            // 当播放器返回无效的 position 或 duration 时
            // 增加额外检查以避免在字幕操作等特殊情况下误报
            
            // 如果之前已经有有效的时长信息，而现在临时返回0，可能是正常的操作过程
            final bool hasValidDurationBefore = _duration.inMilliseconds > 0;
            final bool isTemporaryInvalid = hasValidDurationBefore && playerPosition == 0 && playerDuration == 0;
            
            // 检查是否是Jellyfin流媒体正在初始化
            final bool isJellyfinInitializing = _currentVideoPath != null && 
                (_currentVideoPath!.contains('jellyfin://') || _currentVideoPath!.contains('emby://')) &&
                _status == PlayerStatus.loading;
            
            if (isTemporaryInvalid) {
              // 临时的无效状态，跳过本次更新，不报错
              debugPrint('VideoPlayerState: 检测到临时的无效播放器数据 (position: $playerPosition, duration: $playerDuration)，可能是字幕操作等导致，跳过本次更新');
              return;
            }
            
            if (isJellyfinInitializing) {
              // Jellyfin流媒体正在初始化，跳过错误检测
              debugPrint('VideoPlayerState: Jellyfin流媒体正在初始化中，跳过无效数据检测 (position: $playerPosition, duration: $playerDuration)');
              return;
            }
            
            final String pathForErrorLog = _currentVideoPath ?? "未知路径";
            final String baseName = p.basename(pathForErrorLog);
            
            // 优先使用来自播放器适配器的特定错误消息
            String userMessage;
            if (player.mediaInfo.specificErrorMessage != null && player.mediaInfo.specificErrorMessage!.isNotEmpty) {
              userMessage = player.mediaInfo.specificErrorMessage!;
            } else {
              final String technicalDetail = '(pos: $playerPosition, dur: $playerDuration)';
              userMessage = '视频文件 "$baseName" 可能已损坏或无法读取 $technicalDetail';
            }

            debugPrint('VideoPlayerState: 播放器返回无效的视频数据 (position: $playerPosition, duration: $playerDuration) 路径: $pathForErrorLog. 错误信息: $userMessage. 已停止播放并设置为错误状态.');
            
            _error = userMessage; 

            player.state = PlaybackState.stopped; 
            
            // 停止定时器
            if (_uiUpdateTimer?.isActive ?? false) { 
              _uiUpdateTimer!.cancel();
              _uiUpdateTimer = null; 
            }
            
            _setStatus(PlayerStatus.error, message: userMessage); 

            _position = Duration.zero;
            _progress = 0.0;
            _duration = Duration.zero; 
            
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              // 1. 执行 handleBackButton 逻辑 (处理全屏、截图等)
              await handleBackButton();
              
              // 2. DO NOT call resetPlayer() here. The dialog's action will call it.

              // 3. 通知UI层执行pop/显示对话框等
              onSeriousPlaybackErrorAndShouldPop?.call();
            });

            return; 
          }
        } else if (_status == PlayerStatus.paused && _lastSeekPosition != null) {
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
}
