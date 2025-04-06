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

enum PlayerStatus {
  idle,        // 空闲状态
  loading,     // 加载中
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

  VideoPlayerState() {
    _initialize();
  }

  // Getters
  PlayerStatus get status => _status;
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
      _setStatus(PlayerStatus.loading);
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
      
      _setStatus(PlayerStatus.ready);
      
      // 开始播放
      player.state = PlaybackState.playing;
      _setStatus(PlayerStatus.playing);
      
    } catch (e, stackTrace) {
      _error = '初始化视频播放器时出错: $e';
      _setStatus(PlayerStatus.error);
    }
  }

  Future<void> resetPlayer() async {
    if (player.state != PlaybackState.stopped) {
      player.state = PlaybackState.stopped;
    }
    // 释放纹理
    if (player.textureId.value != null) {
      player.textureId.value = null;
    }
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
  }

  void _setStatus(PlayerStatus status) {
    _status = status;
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
      player.seek(position: position.inMilliseconds);
      _position = position;
      if (_duration.inMilliseconds > 0) {
        _progress = position.inMilliseconds / _duration.inMilliseconds;
      }
      Future.delayed(const Duration(milliseconds: 100), () {
        _isSeeking = false;
      });
      notifyListeners();
    } catch (e) {
      _error = '跳转时出错: $e';
      _setStatus(PlayerStatus.error);
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
        _position = Duration(milliseconds: player.position);
        _duration = Duration(milliseconds: player.mediaInfo.duration);
        if (_duration.inMilliseconds > 0) {
          _progress = _position.inMilliseconds / _duration.inMilliseconds;
          // 保存当前播放位置
          _saveVideoPosition(_currentVideoPath!, _position.inMilliseconds);
        }
        notifyListeners();
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
} 