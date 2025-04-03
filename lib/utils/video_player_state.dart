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
  final Player player = Player();
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
  bool _isControlsHovered = false;
  bool _isSeeking = false;
  final FocusNode _focusNode = FocusNode();
  static const String _lastVideoKey = 'last_video_path';
  static const String _lastPositionKey = 'last_video_position';

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
    print('\n=== 初始化 VideoPlayerState ===');
    _startPositionUpdateTimer();
    _setupWindowManagerListener();
    _focusNode.requestFocus();
    KeyboardShortcuts.loadShortcuts();
    await _loadLastVideo();
    print('=== VideoPlayerState 初始化完成 ===\n');
  }

  Future<void> _loadLastVideo() async {
    final prefs = await SharedPreferences.getInstance();
    final lastVideoPath = prefs.getString(_lastVideoKey);
    final lastPosition = prefs.getInt(_lastPositionKey) ?? 0;

    if (lastVideoPath != null) {
      await initializePlayer(lastVideoPath);
      if (lastPosition > 0) {
        seekTo(Duration(milliseconds: lastPosition));
      }
    }
  }

  Future<void> _saveLastVideo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastVideoKey, _currentVideoPath ?? '');
    await prefs.setInt(_lastPositionKey, _position.inMilliseconds);
  }

  Future<void> initializePlayer(String path) async {
    try {
      print('=== 开始初始化视频播放器 ===');
      print('视频路径: $path');
      
      _setStatus(PlayerStatus.loading);
      _error = null;
      
      // 重置播放器
      await resetPlayer();
      
      // 设置媒体源
      print('设置播放器媒体源...');
      player.media = path;
      
      // 准备播放器
      print('准备播放器...');
      player.prepare();
      
      // 获取视频纹理
      print('获取视频纹理...');
      final textureId = await player.updateTexture();
      print('获取到的纹理ID: $textureId');
      
      if (textureId == null) {
        throw Exception('无法获取视频纹理');
      }
      
      // 更新状态
      _currentVideoPath = path;
      _duration = Duration(milliseconds: player.mediaInfo.duration);
      _position = Duration.zero;
      _progress = 0.0;
      _setStatus(PlayerStatus.ready);
      
      // 开始播放
      player.state = PlaybackState.playing;
      _setStatus(PlayerStatus.playing);
      
      // 保存状态
      await _saveLastVideo();
      
      print('=== 视频播放器初始化完成 ===');
    } catch (e, stackTrace) {
      print('\n=== 初始化视频播放器时出错 ===');
      print('错误信息: $e');
      print('错误堆栈: $stackTrace');
      print('=== 错误信息结束 ===\n');
      _error = '初始化视频播放器时出错: $e';
      _setStatus(PlayerStatus.error);
    }
  }

  Future<void> resetPlayer() async {
    try {
      print('重置播放器状态...');
      player.state = PlaybackState.stopped;
      player.media = '';
      if (player.textureId.value != null) {
        player.textureId.value = null;
      }
      _currentVideoPath = null;
      _duration = Duration.zero;
      _position = Duration.zero;
      _progress = 0.0;
      _error = null;
      _setStatus(PlayerStatus.idle);
    } catch (e) {
      print('重置播放器时出错: $e');
      throw e;
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

  void setControlsHovered(bool value) {
    _isControlsHovered = value;
    if (value) {
      _hideControlsTimer?.cancel();
      _hideMouseTimer?.cancel();
      setShowControls(true);
    } else {
      resetHideControlsTimer();
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
    if (_showControls && hasVideo && !_isControlsHovered && !globals.isPhone) {
      resetHideControlsTimer();
    }
  }

  void setShowControls(bool value) {
    _showControls = value;
    notifyListeners();
  }

  void _startPositionUpdateTimer() {
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isSeeking && hasVideo) {
        _position = Duration(milliseconds: player.position);
        _duration = Duration(milliseconds: player.mediaInfo.duration);
        if (_duration.inMilliseconds > 0) {
          _progress = _position.inMilliseconds / _duration.inMilliseconds;
        }
        notifyListeners();
      }
    });
  }

  bool shouldShowAppBar() {
    if (_isFullscreen) return false;
    if (globals.isPhone) return !hasVideo;
    return true;
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _hideControlsTimer?.cancel();
    _hideMouseTimer?.cancel();
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
        print('窗口管理器检测到全屏状态变化: $isFullscreen');
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
      print('窗口进入全屏: $isFullscreen');
      if (isFullscreen != _isFullscreen) {
        _isFullscreen = isFullscreen;
        notifyListeners();
      }
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    windowManager.isFullScreen().then((isFullscreen) {
      print('窗口退出全屏: $isFullscreen');
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

  // 处理键盘事件
  void handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      print('\n=== 键盘事件 ===');
      print('按键: ${event.logicalKey}');
      print('按键名称: ${event.logicalKey.keyLabel}');
      print('按键ID: ${event.logicalKey.keyId}');
      print('是否有视频: $hasVideo');
      
      // 每次按键事件时重新获取最新的快捷键绑定
      final playPauseKey = KeyboardShortcuts.getKeyBinding('play_pause');
      final fullscreenKey = KeyboardShortcuts.getKeyBinding('fullscreen');
      final rewindKey = KeyboardShortcuts.getKeyBinding('rewind');
      final forwardKey = KeyboardShortcuts.getKeyBinding('forward');
      
      print('当前快捷键绑定:');
      print('播放/暂停: $playPauseKey');
      print('全屏: $fullscreenKey');
      print('快退: $rewindKey');
      print('快进: $forwardKey');
      
      // 检查按键是否匹配任何快捷键
      print('按键匹配检查:');
      print('是否匹配播放/暂停: ${event.logicalKey == playPauseKey}');
      print('是否匹配全屏: ${event.logicalKey == fullscreenKey}');
      print('是否匹配快退: ${event.logicalKey == rewindKey}');
      print('是否匹配快进: ${event.logicalKey == forwardKey}');
      
      // 只处理已配置的快捷键
      if (event.logicalKey == playPauseKey) {
        print('播放/暂停键按下');
        if (hasVideo) {
          print('有视频，切换播放状态');
          togglePlayPause();
        } else {
          print('没有视频，忽略按键');
        }
      } else if (event.logicalKey == fullscreenKey) {
        print('全屏键按下');
        if (hasVideo) {
          print('有视频，切换全屏状态');
          toggleFullscreen();
        }
      } else if (event.logicalKey == rewindKey) {
        print('快退键按下');
        print('当前视频位置: ${_position.inSeconds}秒');
        if (hasVideo) {
          print('有视频，快退10秒');
          final newPosition = _position - const Duration(seconds: 10);
          print('新位置: ${newPosition.inSeconds}秒');
          seekTo(newPosition);
        }
      } else if (event.logicalKey == forwardKey) {
        print('快进键按下');
        print('当前视频位置: ${_position.inSeconds}秒');
        if (hasVideo) {
          print('有视频，快进10秒');
          final newPosition = _position + const Duration(seconds: 10);
          print('新位置: ${newPosition.inSeconds}秒');
          seekTo(newPosition);
        }
      } else {
        print('未处理的按键: ${event.logicalKey}');
        print('按键ID: ${event.logicalKey.keyId}');
      }
      print('=== 键盘事件处理完成 ===\n');
    }
  }

  // 切换全屏状态
  Future<void> toggleFullscreen() async {
    print('\n=== 手动切换全屏状态 ===');
    print('当前全屏状态: $_isFullscreen');
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面系统使用 window_manager
      print('桌面系统，使用 window_manager');
      if (!_isFullscreen) {
        print('设置全屏...');
        await windowManager.setFullScreen(true);
        _isFullscreen = true;
      } else {
        print('退出全屏...');
        await windowManager.setFullScreen(false);
        _isFullscreen = false;
        // 确保返回到主页面
        if (_context != null) {
          Navigator.of(_context!).popUntil((route) => route.isFirst);
        }
      }
    } else if (Platform.isAndroid || Platform.isIOS) {
      // 移动系统使用 orientation
      print('移动系统，使用 orientation');
      if (!_isFullscreen) {
        print('设置横屏...');
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        // 隐藏状态栏和导航栏
        print('隐藏状态栏和导航栏...');
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _isFullscreen = true;
      } else {
        print('设置竖屏...');
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        // 显示状态栏和导航栏
        print('显示状态栏和导航栏...');
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        _isFullscreen = false;
        // 确保返回到主页面
        if (_context != null) {
          Navigator.of(_context!).popUntil((route) => route.isFirst);
        }
      }
    }
    
    notifyListeners();
    print('=== 全屏状态切换完成 ===\n');
  }

  // 设置上下文
  void setContext(BuildContext context) {
    _context = context;
  }
} 