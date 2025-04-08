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
  double _aspectRatio = 16 / 9;
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
  static int _textureIdCounter = 0;
  Duration? _lastSeekPosition;  // 添加这个字段来记录最后一次seek的位置
  List<Map<String, dynamic>> _danmakuList = [];

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
  FocusNode get focusNode => _focusNode;
  List<Map<String, dynamic>> get danmakuList => _danmakuList;

  Future<void> _initialize() async {
    if (globals.isPhone) {
      await _setPortrait();
    }
    _startPositionUpdateTimer();
    _setupWindowManagerListener();
    _focusNode.requestFocus();
    KeyboardShortcuts.loadShortcuts();
    await _loadLastVideo();
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
      // 加载保存的token
      await DandanplayService.loadToken();
      
      _setStatus(PlayerStatus.loading, message: '正在初始化播放器...');
      _error = null;
      
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
      
      // 在手机平台上强制横屏
      if (globals.isPhone) {
        await _setLandscape();
      }

      // 使用新的视频识别和弹幕加载逻辑
      await _recognizeVideo(path);
      
      // 设置回加载状态
      _setStatus(PlayerStatus.loading, message: '正在加载视频...');
      
      // 获取上次播放位置
      final lastPosition = await _getVideoPosition(path);
      
      // 设置媒体源
      player.media = path;
      
      // 准备播放器
      player.prepare();
      
      // 获取视频纹理
      final textureId = await player.updateTexture();
      
      if (textureId == null) {
        throw Exception('无法获取视频纹理');
      }
      
      // 更新状态
      _currentVideoPath = path;
      _duration = Duration(milliseconds: player.mediaInfo.duration);
      
      // 如果有上次的播放位置，恢复播放位置
      if (lastPosition > 0) {
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
      
      _setStatus(PlayerStatus.ready, message: '准备就绪');
      
      // 开始播放
      player.state = PlaybackState.playing;
      _setStatus(PlayerStatus.playing, message: '正在播放');
      
    } catch (e) {
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
      print('重置播放器时出错: $e');
      rethrow;
    }
  }

  void _setStatus(PlayerStatus status, {String message = ''}) {
    _status = status;
    _updateStatusMessages([message]);
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
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isSeeking && hasVideo) {
        if (_status == PlayerStatus.playing) {
          // 播放状态：从播放器获取位置
          _position = Duration(milliseconds: player.position);
          _duration = Duration(milliseconds: player.mediaInfo.duration);
          if (_duration.inMilliseconds > 0) {
            _progress = _position.inMilliseconds / _duration.inMilliseconds;
            // 保存当前播放位置
            _saveVideoPosition(_currentVideoPath!, _position.inMilliseconds);
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
      _setStatus(PlayerStatus.recognizing, message: '正在识别视频...');
      
      final videoInfo = await DandanplayService.getVideoInfo(videoPath);
      
      if (videoInfo['isMatched'] == true) {
        _setStatus(PlayerStatus.recognizing, message: '视频识别成功，正在加载弹幕...');
        
        if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
          final match = videoInfo['matches'][0];
          if (match['episodeId'] != null) {
            try {
              final danmakuData = await DandanplayService.getDanmaku(videoPath, match['episodeId'].toString());
              if (danmakuData['comments'] != null) {
                final comments = danmakuData['comments'] as List;
                _danmakuList = List<Map<String, dynamic>>.from(comments);
                notifyListeners();
              }
              _setStatus(PlayerStatus.ready, message: '弹幕加载完成');
            } catch (e) {
              print('弹幕加载错误: $e');
              _setStatus(PlayerStatus.error, message: '弹幕加载失败: $e');
            }
          }
        }
      } else {
        throw Exception('无法识别该视频');
      }
    } catch (e) {
      print('视频识别错误: $e');
      _setError('视频识别失败: $e');
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
} 