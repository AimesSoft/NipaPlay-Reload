import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
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
  final double _aspectRatio = 16 / 9;
  String? _currentVideoPath;
  Timer? _positionUpdateTimer;
  Timer? _hideControlsTimer;
  Timer? _hideMouseTimer;
  Timer? _autoHideTimer;
  bool _isControlsHovered = false;
  bool _isSeeking = false;
  final FocusNode _focusNode = FocusNode();
  static const String _lastVideoKey = 'last_video_path';
  static const String _lastPositionKey = 'last_video_position';
  static const String _videoPositionsKey = 'video_positions';
  static final int _textureIdCounter = 0;
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
  bool _danmakuStacking = true;  // 默认启用弹幕堆叠
  dynamic danmakuController;  // 添加弹幕控制器属性
  Duration _videoDuration = Duration.zero; // 添加视频时长状态
  bool _isFullscreenTransitioning = false;
  
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
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _isFullscreen = true;
    notifyListeners();
  }

  // 设置竖屏
  Future<void> _setPortrait() async {
    if (!globals.isPhone) return;
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
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _isFullscreen = false;
    notifyListeners();
  }

  Future<void> initializePlayer(String path) async {
    try {
      print('1. 开始初始化播放器...');
      // 加载保存的token
      await DandanplayService.loadToken();
      
      _setStatus(PlayerStatus.loading, message: '正在初始化播放器...');
      _error = null;
      
      print('2. 重置播放器状态...');
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
      _position = Duration.zero;
      _duration = Duration.zero;
      _progress = 0.0;
      _error = null;
      _setStatus(PlayerStatus.idle);
      
      print('3. 设置媒体源...');
      // 设置媒体源
      player.media = path;
      
      print('4. 准备播放器...');
      // 准备播放器
      player.prepare();
      
      print('5. 获取视频纹理...');
      // 获取视频纹理
      final textureId = await player.updateTexture();
      
      print('6. 分析媒体信息...');
      // 分析并打印媒体信息，特别是字幕轨道
      MediaInfoHelper.analyzeMediaInfo(player.mediaInfo);
      
      // 优先选择包含sm或中文相关的字幕轨道
      if (player.mediaInfo?.subtitle != null) {
        final subtitles = player.mediaInfo!.subtitle!;
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
      
      print('7. 更新视频状态...');
      // 更新状态
      _currentVideoPath = path;
      _duration = Duration(milliseconds: player.mediaInfo.duration);
      
      // 获取上次播放位置
      final lastPosition = await _getVideoPosition(path);
      
      // 如果有上次的播放位置，恢复播放位置
      if (lastPosition > 0) {
        print('8. 恢复上次播放位置...');
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
      
      print('9. 检查播放器实际状态...');
      // 检查播放器实际状态
      if (player.state == PlaybackState.playing) {
        _setStatus(PlayerStatus.playing, message: '正在播放');
        // 只有在真正开始播放时才设置横屏
        if (globals.isPhone) {
          await _setLandscape();
        }
      } else {
        // 如果播放器没有真正开始播放，设置为暂停状态
        player.state = PlaybackState.paused;
        _setStatus(PlayerStatus.paused, message: '已暂停');
      }
      
      print('10. 开始识别视频和加载弹幕...');
      // 尝试识别视频和加载弹幕
      try {
        await _recognizeVideo(path);
      } catch (e) {
        print('弹幕加载失败: $e');
        // 设置空弹幕列表，确保播放不受影响
        _danmakuList = [];
        _addStatusMessage('无法连接服务器，跳过加载弹幕');
      }
      
      print('11. 设置准备就绪状态...');
      // 设置状态为准备就绪
      _setStatus(PlayerStatus.ready, message: '准备就绪');
      
      print('12. 开始播放视频...');
      // 开始播放
      player.state = PlaybackState.playing;
      _setStatus(PlayerStatus.playing, message: '正在播放');
      
      // 等待一小段时间确保播放器真正开始播放
      await Future.delayed(const Duration(milliseconds: 100));
      
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
      print('初始化播放器时出错: $e');
      _error = '初始化视频播放器时出错: $e';
      _setStatus(PlayerStatus.error, message: '加载失败: $e');
    }
  }

  Future<void> resetPlayer() async {
    try {
      // 先停止播放
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }
      
      // 等待一小段时间确保播放器完全停止
      await Future.delayed(const Duration(milliseconds: 50));
      
      // 释放纹理
      if (player.textureId.value != null) {
        player.textureId.value = null;
      }
      
      // 等待一小段时间确保纹理完全释放
      await Future.delayed(const Duration(milliseconds: 50));
      
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
      //print('重置播放器时出错: $e');
      rethrow;
    }
  }

  void _setStatus(PlayerStatus status, {String? message}) {
    _status = status;
    if (message != null) {
      _statusMessages = [message];
    } else {
      _statusMessages = [];
    }
    notifyListeners();
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
      _error = '播放控制时出错: $e';
      _setStatus(PlayerStatus.error);
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
      _error = '跳转时出错: $e';
      _setStatus(PlayerStatus.error);
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
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    _focusNode.dispose();
    _saveLastVideo();
    player.dispose();
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
      print('开始识别视频...');
      _setStatus(PlayerStatus.recognizing, message: '正在识别视频...');
      
      // 使用超时处理网络请求
      try {
        print('尝试获取视频信息...');
        final videoInfo = await DandanplayService.getVideoInfo(videoPath)
            .timeout(const Duration(seconds: 15), onTimeout: () {
          print('获取视频信息超时');
          throw TimeoutException('连接服务器超时');
        });
        
        if (videoInfo['isMatched'] == true) {
          print('视频匹配成功，开始加载弹幕...');
          _setStatus(PlayerStatus.recognizing, message: '视频识别成功，正在加载弹幕...');
          
          if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
            final match = videoInfo['matches'][0];
            if (match['episodeId'] != null && match['animeId'] != null) {
              try {
                print('尝试加载弹幕...');
                _setStatus(PlayerStatus.recognizing, message: '正在加载弹幕...');
                final episodeId = match['episodeId'].toString();
                final animeId = match['animeId'] as int;
                
                // 从缓存加载弹幕
                print('检查弹幕缓存...');
                final cachedDanmaku = await DanmakuCacheManager.getDanmakuFromCache(episodeId);
                if (cachedDanmaku != null) {
                  print('从缓存加载弹幕...');
                  _setStatus(PlayerStatus.recognizing, message: '正在从缓存加载弹幕...');
                  _danmakuList = List<Map<String, dynamic>>.from(cachedDanmaku);
                  notifyListeners();
                  _setStatus(PlayerStatus.recognizing, message: '从缓存加载弹幕完成 (${cachedDanmaku.length}条)');
                  return;
                }
                
                print('从网络加载弹幕...');
                // 从网络加载弹幕
                final danmakuData = await DandanplayService.getDanmaku(episodeId, animeId)
                  .timeout(const Duration(seconds: 15), onTimeout: () {
                    print('加载弹幕超时');
                    throw TimeoutException('加载弹幕超时');
                  });
                  
                _danmakuList = List<Map<String, dynamic>>.from(danmakuData['comments']);
                notifyListeners();
                _setStatus(PlayerStatus.recognizing, message: '弹幕加载完成 (${danmakuData['count']}条)');
              } catch (e) {
                print('弹幕加载错误: $e');
                // 弹幕加载错误不影响视频播放
                _danmakuList = [];
                _setStatus(PlayerStatus.recognizing, message: '弹幕加载失败，跳过');
              }
            }
          }
        } else {
          print('视频未匹配到信息');
          // 视频未匹配但仍继续播放
          _danmakuList = [];
          _setStatus(PlayerStatus.recognizing, message: '未匹配到视频信息，跳过弹幕');
        }
      } catch (e) {
        print('视频识别网络错误: $e');
        // 处理网络错误等
        _danmakuList = [];
        _setStatus(PlayerStatus.recognizing, message: '无法连接服务器，跳过加载弹幕');
        // 不抛出异常，允许视频继续播放
      }
    } catch (e) {
      print('严重错误: $e');
      // 这里只处理真正阻碍视频播放的严重错误
      rethrow; // 重新抛出异常，让initializePlayer捕获处理
    }
  }

  // 设置错误状态
  void _setError(String error) {
    _error = error;
    _status = PlayerStatus.error;
    _clearStatusMessages();
    _addStatusMessage(error);
    notifyListeners();
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
    _danmakuStacking = prefs.getBool(_danmakuStackingKey) ?? true;
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
      //print('加载弹幕失败: $e');
      _setStatus(PlayerStatus.playing, message: '弹幕加载失败');
    }
  }

  // 在设置视频时长时更新状态
  void setVideoDuration(Duration duration) {
    _videoDuration = duration;
    notifyListeners();
  }
} 