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
import 'package:crypto/crypto.dart';
import 'package:provider/provider.dart';
import '../providers/watch_history_provider.dart';

enum PlayerStatus {
  idle,        // 空闲状态
  loading,     // 加载中
  recognizing, // 识别中
  ready,       // 准备就绪
  playing,     // 播放中
  paused,      // 暂停
  error,       // 错误
  disposed     // 已释放
}

class VideoPlayerState extends ChangeNotifier implements WindowListener {
  Player player = Player();
  BuildContext? _context;
  PlayerStatus _status = PlayerStatus.idle;
  List<String> _statusMessages = [];  // 修改为列表存储多个状态消息
  bool _showControls = true;
  bool _isFullscreen = false;
  double _progress = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;
  double _aspectRatio = 16 / 9;  // 默认16:9，但会根据视频实际比例更新
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
  Duration? _lastSeekPosition;  // 添加这个字段来记录最后一次seek的位置
  List<Map<String, dynamic>> _danmakuList = [];
  static const String _controlBarHeightKey = 'control_bar_height';
  double _controlBarHeight = 20.0;  // 默认高度
  static const String _danmakuOpacityKey = 'danmaku_opacity';
  double _danmakuOpacity = 1.0;  // 默认透明度
  static const String _danmakuVisibleKey = 'danmaku_visible';
  bool _danmakuVisible = true;  // 默认显示弹幕
  static const String _mergeDanmakuKey = 'merge_danmaku';
  bool _mergeDanmaku = false;  // 默认不合并弹幕
  static const String _danmakuStackingKey = 'danmaku_stacking';
  bool _danmakuStacking = false;  // 默认不启用弹幕堆叠
  dynamic danmakuController;  // 添加弹幕控制器属性
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
  bool get hasVideo => _status == PlayerStatus.ready || 
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

  Future<void> _initialize() async {
    if (globals.isPhone) {
      await _setPortrait();
    }
    _startPositionUpdateTimer();
    _setupWindowManagerListener();
    _focusNode.requestFocus();
    KeyboardShortcuts.loadShortcuts();
    await _loadLastVideo();
    await _loadControlBarHeight();  // 加载保存的控制栏高度
    await _loadDanmakuOpacity();    // 加载保存的弹幕透明度
    await _loadDanmakuVisible();    // 加载弹幕可见性
    await _loadMergeDanmaku();      // 加载弹幕合并设置
    await _loadDanmakuStacking();   // 加载弹幕堆叠设置
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
    final Map<String, dynamic> positionMap = Map<String, dynamic>.from(json.decode(positions));
    positionMap[path] = position;
    await prefs.setString(_videoPositionsKey, json.encode(positionMap));
  }

  // 获取视频播放位置
  Future<int> _getVideoPosition(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final positions = prefs.getString(_videoPositionsKey) ?? '{}';
    final Map<String, dynamic> positionMap = Map<String, dynamic>.from(json.decode(positions));
    return positionMap[path] ?? 0;
  }

  // 设置横屏
  Future<void> _setLandscape() async {
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
      debugPrint('重新初始化纹理...');
      player.textureId.value = null;
      await Future.delayed(const Duration(milliseconds: 100));
      final textureId = await player.updateTexture();
      debugPrint('新的纹理ID: $textureId');
      
      // 如果之前在播放，恢复播放
      if (wasPlaying) {
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing, message: '继续播放');
      }
      
      _isFullscreen = true;
      _isFullscreenTransitioning = false;
      notifyListeners();
      
    } catch (e) {
      debugPrint('横屏切换出错: $e');
      _isFullscreenTransitioning = false;
      // 如果出错，尝试恢复到竖屏
      try {
        await _setPortrait();
      } catch (e2) {
        debugPrint('恢复竖屏也失败: $e2');
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
      debugPrint('重新初始化纹理...');
      player.textureId.value = null;
      await Future.delayed(const Duration(milliseconds: 100));
      final textureId = await player.updateTexture();
      debugPrint('新的纹理ID: $textureId');
      
      // 如果之前在播放，恢复播放
      if (wasPlaying) {
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing, message: '继续播放');
      }
      
      _isFullscreen = false;
      _isFullscreenTransitioning = false;
      notifyListeners();
      
    } catch (e) {
      debugPrint('竖屏切换出错: $e');
      _isFullscreenTransitioning = false;
      notifyListeners();
    }
  }

  Future<void> initializePlayer(String path) async {
    try {
      debugPrint('1. 开始初始化播放器...');
      // 加载保存的token
      await DandanplayService.loadToken();
      
      _setStatus(PlayerStatus.loading, message: '正在初始化播放器...');
      _error = null;
      
      debugPrint('2. 重置播放器状态...');
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
      
      debugPrint('3. 设置媒体源...');
      // 设置媒体源
      player.media = path;
      
      debugPrint('4. 准备播放器...');
      // 准备播放器
      player.prepare();
      
      debugPrint('5. 获取视频纹理...');
      // 获取视频纹理
      final textureId = await player.updateTexture();
      debugPrint('获取到纹理ID: $textureId');
      
      // 等待纹理初始化完成
      await Future.delayed(const Duration(milliseconds: 200));
      
      debugPrint('6. 分析媒体信息...');
      // 分析并打印媒体信息，特别是字幕轨道
      MediaInfoHelper.analyzeMediaInfo(player.mediaInfo);
      
      // 设置视频宽高比
      if (player.mediaInfo.video != null && player.mediaInfo.video!.isNotEmpty) {
        final videoTrack = player.mediaInfo.video![0];
        if (videoTrack.codec.width > 0 && videoTrack.codec.height > 0) {
          _aspectRatio = videoTrack.codec.width / videoTrack.codec.height;
          debugPrint('设置视频宽高比: $_aspectRatio');
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
      
      debugPrint('7. 更新视频状态...');
      // 更新状态
      _currentVideoPath = path;
      
      // 异步计算视频哈希值，不阻塞主要初始化流程
      _precomputeVideoHash(path);
      
      _duration = Duration(milliseconds: player.mediaInfo.duration);
      
      // 获取上次播放位置
      final lastPosition = await _getVideoPosition(path);
      
      // 如果有上次的播放位置，恢复播放位置
      if (lastPosition > 0) {
        debugPrint('8. 恢复上次播放位置...');
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
      
      debugPrint('9. 检查播放器实际状态...');
      // 检查播放器实际状态
      if (player.state == PlaybackState.playing) {
        _setStatus(PlayerStatus.playing, message: '正在播放');
      } else {
        // 如果播放器没有真正开始播放，设置为暂停状态
        player.state = PlaybackState.paused;
        _setStatus(PlayerStatus.paused, message: '已暂停');
      }
      
      // 初始化基础的观看记录（只在没有记录时创建新记录）
      await _initializeWatchHistory(path);
      
      debugPrint('10. 开始识别视频和加载弹幕...');
      // 尝试识别视频和加载弹幕
      try {
        await _recognizeVideo(path);
      } catch (e) {
        debugPrint('弹幕加载失败: $e');
        // 设置空弹幕列表，确保播放不受影响
        _danmakuList = [];
        _addStatusMessage('无法连接服务器，跳过加载弹幕');
      }
      
      debugPrint('11. 设置准备就绪状态...');
      // 设置状态为准备就绪
      _setStatus(PlayerStatus.ready, message: '准备就绪');
      
      debugPrint('12. 开始播放视频...');
      // 开始播放
      player.state = PlaybackState.playing;
      _setStatus(PlayerStatus.playing, message: '正在播放');
      
      // 等待一小段时间确保播放器真正开始播放
      await Future.delayed(const Duration(milliseconds: 300));
      
      // 检查播放器实际状态
      if (player.state == PlaybackState.playing) {
        // 状态已经设置，不需要重复设置
        // 确保在真正开始播放时设置横屏
        if (globals.isPhone) {
          await _setLandscape();
        }
      } else {
        // 如果播放器没有真正开始播放，设置为暂停状态
        player.state = PlaybackState.paused;
        _setStatus(PlayerStatus.paused, message: '已暂停');
      }
      
    } catch (e) {
      debugPrint('初始化视频播放器时出错: $e');
      _error = '初始化视频播放器时出错: $e';
      _setStatus(PlayerStatus.error, message: '播放器初始化失败');
      // 尝试恢复
      _tryRecoverFromError();
    }
  }

  // 预先计算视频哈希值
  Future<void> _precomputeVideoHash(String path) async {
    try {
      debugPrint('开始计算视频哈希值...');
      _currentVideoHash = await _calculateFileHash(path);
      debugPrint('视频哈希值计算完成: $_currentVideoHash');
    } catch (e) {
      debugPrint('计算视频哈希值失败: $e');
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
        debugPrint('已有观看记录存在，只更新播放进度: 动画=${existingHistory.animeName}, 集数=${existingHistory.episodeTitle}');
        
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
        if (_context != null) _context!.read<WatchHistoryProvider>().refresh();
        return;
      }
      
      // 只有在没有现有记录时才创建全新记录
      final fileName = path.split('/').last;
      
      // 尝试从文件名中提取更好的初始动画名称
      String initialAnimeName = fileName;
      
      // 移除常见的文件扩展名
      initialAnimeName = initialAnimeName.replaceAll(RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$'), '');
      
      // 替换下划线、点和破折号为空格
      initialAnimeName = initialAnimeName.replaceAll(RegExp(r'[_\.-]'), ' ');
      
      // 创建初始观看记录
      final item = WatchHistoryItem(
        filePath: path,
        animeName: initialAnimeName,
        lastPosition: _position.inMilliseconds,
        duration: _duration.inMilliseconds,
        watchProgress: _progress,
        lastWatchTime: DateTime.now(),
      );
      
      debugPrint('创建全新的观看记录: 动画=${item.animeName}');
      // 保存到历史记录
      await WatchHistoryManager.addOrUpdateHistory(item);
      if (_context != null) _context!.read<WatchHistoryProvider>().refresh();
    } catch (e) {
      debugPrint('初始化观看记录时出错: $e');
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
      debugPrint('重置播放器时出错: $e');
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
      debugPrint('释放纹理资源时出错: $e');
    }
  }

  void _setStatus(PlayerStatus status, {String? message}) {
    //debugPrint('播放器状态变化: ${_status.toString()} -> ${status.toString()}${message != null ? ' (message: $message)' : ''}');
    _status = status;
    if (message != null) {
      _statusMessages = [message];
    } else {
      _statusMessages = [];
    }
    notifyListeners();
    
    // 当状态变为播放时，启动截图定时器
    if (status == PlayerStatus.playing) {
      _startScreenshotTimer();
    } else if (status == PlayerStatus.paused || status == PlayerStatus.idle || status == PlayerStatus.error) {
      _stopScreenshotTimer();
    }
  }

  void togglePlayPause() {
    if (!hasVideo) return;

    try {
      if (_status == PlayerStatus.playing) {
        player.state = PlaybackState.paused;
        _setStatus(PlayerStatus.paused);
      } else {
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing);
      }
    } catch (e) {
      debugPrint('播放控制时出错 (已静默处理): $e');
      _error = '播放控制时出错: $e';
      _setStatus(PlayerStatus.idle);
    }
  }

  void seekTo(Duration position) {
    if (!hasVideo) return;

    try {
      _isSeeking = true;
      bool wasPlayingBeforeSeek = _status == PlayerStatus.playing;  // 记录当前播放状态
      
      // 确保位置在有效范围内（0 到视频总时长）
      Duration clampedPosition = Duration(milliseconds: 
        position.inMilliseconds.clamp(0, _duration.inMilliseconds)
      );
      
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
      debugPrint('跳转时出错 (已静默处理): $e');
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
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
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
              player.state = PlaybackState.paused;
              _setStatus(PlayerStatus.paused, message: '播放结束');
              _position = _duration; // 确保位置不会超过视频长度
              _progress = 1.0;
              notifyListeners();
            }
          }
          _lastSeekPosition = null;  // 清除最后seek位置
          notifyListeners();
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

  bool shouldShowAppBar() {
    if (globals.isPhone) {
      return !hasVideo || !_isFullscreen;
    }
    return !_isFullscreen;
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _hideControlsTimer?.cancel();
    _hideMouseTimer?.cancel();
    _autoHideTimer?.cancel();
    _screenshotTimer?.cancel(); // 清理截图定时器
    
    // 清空并释放播放器资源
    try {
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }
      
      // 释放纹理资源
      _disposeTextureResources();
      
      // 重置播放器媒体
      player.media = '';
      
      // 等待一小段时间确保资源释放
      Future.delayed(const Duration(milliseconds: 100), () {
        // 完全销毁播放器实例
        player.dispose();
      });
      
    } catch (e) {
      debugPrint('销毁播放器时出错: $e');
    }
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    _focusNode.dispose();
    _saveLastVideo();
    _setStatus(PlayerStatus.disposed);
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
  void onWindowClose() {}

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
      debugPrint('开始识别视频...');
      _setStatus(PlayerStatus.recognizing, message: '正在识别视频...');
      
      // 使用超时处理网络请求
      try {
        debugPrint('尝试获取视频信息...');
        final videoInfo = await DandanplayService.getVideoInfo(videoPath)
            .timeout(const Duration(seconds: 15), onTimeout: () {
          debugPrint('获取视频信息超时');
          throw TimeoutException('连接服务器超时');
        });
        
        if (videoInfo['isMatched'] == true) {
          debugPrint('视频匹配成功，开始加载弹幕...');
          _setStatus(PlayerStatus.recognizing, message: '视频识别成功，正在加载弹幕...');
          
          // 更新观看记录的动画和集数信息
          await _updateWatchHistoryWithVideoInfo(videoPath, videoInfo);
          
          if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
            final match = videoInfo['matches'][0];
            if (match['episodeId'] != null && match['animeId'] != null) {
              try {
                debugPrint('尝试加载弹幕...');
                _setStatus(PlayerStatus.recognizing, message: '正在加载弹幕...');
                final episodeId = match['episodeId'].toString();
                final animeId = match['animeId'] as int;
                
                // 从缓存加载弹幕
                debugPrint('检查弹幕缓存...');
                final cachedDanmaku = await DanmakuCacheManager.getDanmakuFromCache(episodeId);
                if (cachedDanmaku != null) {
                  debugPrint('从缓存加载弹幕...');
                  _setStatus(PlayerStatus.recognizing, message: '正在从缓存加载弹幕...');
                  _danmakuList = List<Map<String, dynamic>>.from(cachedDanmaku);
                  notifyListeners();
                  _setStatus(PlayerStatus.recognizing, message: '从缓存加载弹幕完成 (${cachedDanmaku.length}条)');
                  return;
                }
                
                debugPrint('从网络加载弹幕...');
                // 从网络加载弹幕
                final danmakuData = await DandanplayService.getDanmaku(episodeId, animeId)
                  .timeout(const Duration(seconds: 15), onTimeout: () {
                    debugPrint('加载弹幕超时');
                    throw TimeoutException('加载弹幕超时');
                  });
                  
                _danmakuList = List<Map<String, dynamic>>.from(danmakuData['comments']);
                notifyListeners();
                _setStatus(PlayerStatus.recognizing, message: '弹幕加载完成 (${danmakuData['count']}条)');
              } catch (e) {
                debugPrint('弹幕加载错误: $e');
                // 弹幕加载错误不影响视频播放
                _danmakuList = [];
                _setStatus(PlayerStatus.recognizing, message: '弹幕加载失败，跳过');
              }
            }
          }
        } else {
          debugPrint('视频未匹配到信息');
          // 视频未匹配但仍继续播放
          _danmakuList = [];
          _setStatus(PlayerStatus.recognizing, message: '未匹配到视频信息，跳过弹幕');
        }
      } catch (e) {
        debugPrint('视频识别网络错误: $e');
        // 处理网络错误等
        _danmakuList = [];
        _setStatus(PlayerStatus.recognizing, message: '无法连接服务器，跳过加载弹幕');
        // 不抛出异常，允许视频继续播放
      }
    } catch (e) {
      debugPrint('严重错误: $e');
      // 这里只处理真正阻碍视频播放的严重错误
      rethrow; // 重新抛出异常，让initializePlayer捕获处理
    }
  }

  // 根据视频识别信息更新观看记录
  Future<void> _updateWatchHistoryWithVideoInfo(String path, Map<String, dynamic> videoInfo) async {
    try {
      debugPrint('更新观看记录开始，视频路径: $path');
      // 获取现有记录
      final existingHistory = await WatchHistoryManager.getHistoryItem(path);
      if (existingHistory == null) {
        debugPrint('未找到现有观看记录，跳过更新');
        return;
      }
      
      // 打印完整的视频信息以便调试
      ////debugPrint('视频信息: ${json.encode(videoInfo)}');
      
      // 获取识别到的动画信息
      String? animeName;
      String? episodeTitle;
      int? animeId, episodeId;
      
      // 从videoInfo直接读取animeTitle和episodeTitle
      animeName = videoInfo['animeTitle'] as String?;
      episodeTitle = videoInfo['episodeTitle'] as String?;
      
      // 从匹配信息中获取animeId和episodeId
      if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
        final match = videoInfo['matches'][0];
        // 如果直接字段为空，从匹配中获取
        if (animeName == null || animeName.isEmpty) {
          animeName = match['animeTitle'] as String?;
        }
        
        // 从匹配中获取episodeId和animeId
        episodeId = match['episodeId'] as int?;
        animeId = match['animeId'] as int?;
      }
      
      // 如果仍然没有动画名称，使用文件名
      if (animeName == null || animeName.isEmpty) {
        final fileName = path.split('/').last;
        // 尝试从文件名提取格式化的名称
        String extractedName = fileName.replaceAll(RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$'), '');
        extractedName = extractedName.replaceAll(RegExp(r'[_\.-]'), ' ');
        animeName = extractedName;
      }
      
      debugPrint('识别到动画：${animeName ?? '未知'}，集数：${episodeTitle ?? '未知集数'}，animeId: $animeId, episodeId: $episodeId');
      
      // 更新当前动画标题和集数标题
      _animeTitle = animeName;
      _episodeTitle = episodeTitle;
      notifyListeners();
      
      // 创建更新后的观看记录
      final updatedHistory = WatchHistoryItem(
        filePath: existingHistory.filePath,
        // 使用识别到的动画名称
        animeName: animeName ?? existingHistory.animeName,
        // 使用识别到的集数标题，或保留原来的
        episodeTitle: (episodeTitle != null && episodeTitle.isNotEmpty) ? episodeTitle : existingHistory.episodeTitle,
        // 如果识别到了集数ID，使用识别到的ID，否则保留原来的
        episodeId: episodeId ?? existingHistory.episodeId,
        // 如果识别到了动画ID，使用识别到的ID，否则保留原来的
        animeId: animeId ?? existingHistory.animeId,
        watchProgress: existingHistory.watchProgress,
        lastPosition: existingHistory.lastPosition,
        duration: existingHistory.duration,
        lastWatchTime: existingHistory.lastWatchTime,
        thumbnailPath: existingHistory.thumbnailPath,
      );
      
      debugPrint('准备保存更新后的观看记录，动画名: ${updatedHistory.animeName}, 集数: ${updatedHistory.episodeTitle}');
      // 保存更新后的记录
      await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
      if (_context != null) _context!.read<WatchHistoryProvider>().refresh();
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
      final bytes = await file.openRead(0, maxBytes).expand((chunk) => chunk).toList();
      return md5.convert(bytes).toString();
    } catch (e) {
      debugPrint('计算文件哈希值失败: $e');
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
        debugPrint('缩略图更新监听器执行错误: $e');
      }
    }
  }

  // 立即更新观看记录中的缩略图
  Future<void> _updateWatchHistoryWithNewThumbnail(String thumbnailPath) async {
    if (_currentVideoPath == null) return;
    
    try {
      // 获取当前播放记录
      final existingHistory = await WatchHistoryManager.getHistoryItem(_currentVideoPath!);
      
      if (existingHistory != null) {
        // 仅更新缩略图和时间戳，保留其他所有字段
        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: existingHistory.animeName,
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
        if (_context != null) _context!.read<WatchHistoryProvider>().refresh();
        //debugPrint('观看记录缩略图已更新: $thumbnailPath');
        
        // 通知缩略图已更新，需要刷新UI
        _notifyThumbnailUpdateListeners();
        
        // 尝试刷新已显示的缩略图
        _triggerImageCacheRefresh(thumbnailPath);
      }
    } catch (e) {
      debugPrint('更新观看记录缩略图时出错: $e');
    }
  }
  
  // 触发图片缓存刷新，使新缩略图可见
  void _triggerImageCacheRefresh(String imagePath) {
    try {
      // 从图片缓存中移除该图片
      //debugPrint('刷新图片缓存: $imagePath');
      // 清除特定图片的缓存
      final file = File(imagePath);
      if (file.existsSync()) {
        // 1. 先获取文件URI
        final uri = Uri.file(imagePath);
        // 2. 从缓存中驱逐此图像
        PaintingBinding.instance.imageCache.evict(FileImage(file));
        // 3. 也清除以NetworkImage方式缓存的图像
        PaintingBinding.instance.imageCache.evict(NetworkImage(uri.toString()));
        //debugPrint('图片缓存已刷新');
      }
    } catch (e) {
      debugPrint('刷新图片缓存失败: $e');
    }
  }

  // 启动截图定时器 - 每5秒截取一次视频帧
  void _startScreenshotTimer() {
    _stopScreenshotTimer(); // 先停止现有定时器
    
    if (_currentVideoPath != null && hasVideo) {
      _screenshotTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        if (_status == PlayerStatus.playing && !_isCapturingFrame) {
          _isCapturingFrame = true; // 设置标志，防止并发截图
          try {
            // 使用异步操作减少主线程阻塞
            final newThumbnailPath = await Future(() => _captureVideoFrameWithoutPausing());
            
            if (newThumbnailPath != null) {
              _currentThumbnailPath = newThumbnailPath;
              //debugPrint('5秒定时截图完成: $_currentThumbnailPath');
              
              // 立即更新观看记录中的缩略图
              await _updateWatchHistoryWithNewThumbnail(newThumbnailPath);
            }
          } catch (e) {
            debugPrint('定时截图失败: $e');
          } finally {
            _isCapturingFrame = false; // 重置标志
          }
        }
      });
      //debugPrint('启动5秒定时截图');
    }
  }
  
  // 停止截图定时器
  void _stopScreenshotTimer() {
    if (_screenshotTimer != null) {
      _screenshotTimer!.cancel();
      _screenshotTimer = null;
      //debugPrint('停止定时截图');
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
      if (player.mediaInfo.video != null && player.mediaInfo.video!.isNotEmpty) {
        final videoTrack = player.mediaInfo.video![0];
        if (videoTrack.codec.width > 0 && videoTrack.codec.height > 0) {
          final aspectRatio = videoTrack.codec.width / videoTrack.codec.height;
          targetWidth = (targetHeight * aspectRatio).round();
        }
      }
      
      // 使用Player的snapshot方法获取当前帧，保持宽高比，但不暂停视频
      final videoFrame = await player.snapshot(width: targetWidth, height: targetHeight);
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
        debugPrint('处理图像数据时出错: $e');
        return null;
      }
    } catch (e) {
      debugPrint('无暂停截图时出错: $e');
      return null;
    }
  }

  // 设置错误状态
  void _setError(String error) {
    debugPrint('视频播放错误: $error');
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
      debugPrint('恢复播放失败: $e');
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
      final cachedDanmaku = await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (cachedDanmaku != null) {
        _setStatus(PlayerStatus.recognizing, message: '正在从缓存加载弹幕...');
        danmakuController?.loadDanmaku(cachedDanmaku);
        _setStatus(PlayerStatus.playing, message: '从缓存加载弹幕完成 (${cachedDanmaku.length}条)');
        return;
      }
      
      // 从网络加载弹幕
      final animeId = int.tryParse(animeIdStr) ?? 0;
      final danmakuData = await DandanplayService.getDanmaku(episodeId, animeId);
      danmakuController?.loadDanmaku(danmakuData['comments']);
      _setStatus(PlayerStatus.playing, message: '弹幕加载完成 (${danmakuData['count']}条)');
    } catch (e) {
      ////debugPrint('加载弹幕失败: $e');
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
      final existingHistory = await WatchHistoryManager.getHistoryItem(_currentVideoPath!);
      
      if (existingHistory != null) {
        // 使用当前缩略图路径，如果没有则尝试捕获一个
        String? thumbnailPath = _currentThumbnailPath;
        if (thumbnailPath == null || thumbnailPath.isEmpty) {
          thumbnailPath = existingHistory.thumbnailPath;
          if (thumbnailPath == null || thumbnailPath.isEmpty) {
            // 仅在没有缩略图时才尝试捕获
            try {
              thumbnailPath = await _captureVideoFrameWithoutPausing();
              if (thumbnailPath != null) {
                _currentThumbnailPath = thumbnailPath;
              }
            } catch (e) {
              debugPrint('自动捕获缩略图失败: $e');
            }
          }
        }
        
        // 更新现有记录
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
          thumbnailPath: thumbnailPath,
        );
        
        await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
        if (_context != null) _context!.read<WatchHistoryProvider>().refresh();
      } else {
        // 如果记录不存在，创建新记录
        final fileName = _currentVideoPath!.split('/').last;
        
        // 尝试从文件名中提取初始动画名称
        String initialAnimeName = fileName.replaceAll(RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$'), '');
        initialAnimeName = initialAnimeName.replaceAll(RegExp(r'[_\.-]'), ' ');
        
        // 尝试获取缩略图
        String? thumbnailPath = _currentThumbnailPath;
        if (thumbnailPath == null) {
          try {
            thumbnailPath = await _captureVideoFrameWithoutPausing();
            if (thumbnailPath != null) {
              _currentThumbnailPath = thumbnailPath;
            }
          } catch (e) {
            debugPrint('首次创建记录时捕获缩略图失败: $e');
          }
        }
        
        final newHistory = WatchHistoryItem(
          filePath: _currentVideoPath!,
          animeName: initialAnimeName,
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
        );
        
        await WatchHistoryManager.addOrUpdateHistory(newHistory);
        if (_context != null) _context!.read<WatchHistoryProvider>().refresh();
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
      if (player.mediaInfo.video != null && player.mediaInfo.video!.isNotEmpty) {
        final videoTrack = player.mediaInfo.video![0];
        if (videoTrack.codec.width > 0 && videoTrack.codec.height > 0) {
          final aspectRatio = videoTrack.codec.width / videoTrack.codec.height;
          targetWidth = (targetHeight * aspectRatio).round();
        }
      }
      
      // 使用Player的snapshot方法获取当前帧，保持宽高比
      final videoFrame = await player.snapshot(width: targetWidth, height: targetHeight);
      if (videoFrame == null) {
        debugPrint('无法捕获视频帧');
        
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
        
        debugPrint('视频帧缩略图已保存: $thumbnailPath, 尺寸: ${targetWidth}x$targetHeight');
        
        // 更新当前缩略图路径
        _currentThumbnailPath = thumbnailPath;
        
        return thumbnailPath;
      } catch (e) {
        debugPrint('处理图像数据时出错: $e');
        
        // 恢复播放状态
        if (isPlaying) {
          player.state = PlaybackState.playing;
        }
        
        return null;
      }
    } catch (e) {
      debugPrint('截取视频帧时出错: $e');
      
      // 恢复播放状态
      if (player.state == PlaybackState.paused && _status == PlayerStatus.playing) {
        player.state = PlaybackState.playing;
      }
      
      return null;
    }
  }

  /// 获取当前时间窗口内的弹幕（分批加载/懒加载）
  List<Map<String, dynamic>> getActiveDanmakuList(double currentTime, {double window = 15.0}) {
    return _danmakuList.where((d) {
      final t = d['time'] as double? ?? 0.0;
      return t >= currentTime - window && t <= currentTime + window;
    }).toList();
  }
} 