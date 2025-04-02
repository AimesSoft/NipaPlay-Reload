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

class VideoPlayerState extends ChangeNotifier implements WindowListener {
  final Player player = Player();
  BuildContext? _context;  // 添加BuildContext
  bool _isPlaying = false;
  bool _showControls = true;  // 默认显示控制栏
  bool _isFullscreen = false;  // 添加全屏状态
  double _progress = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;
  double _aspectRatio = 16 / 9;
  bool _isLoading = false;
  bool _hasVideo = false;
  String? _lastVideoPath;
  static const String _lastVideoKey = 'last_video_path';
  static const String _lastPositionKey = 'last_video_position';
  Timer? _positionUpdateTimer;
  Timer? _hideControlsTimer;  // 添加控制栏隐藏计时器
  Timer? _hideMouseTimer;  // 添加鼠标隐藏计时器
  bool _isControlsHovered = false;
  bool _isSeeking = false;  // 添加一个标志来跟踪是否正在拖动
  final FocusNode _focusNode = FocusNode();
  FocusNode get focusNode => _focusNode;

  VideoPlayerState() {
    print('\n=== 初始化 VideoPlayerState ===');
    _startPositionUpdateTimer();
    _setupWindowManagerListener();  // 重新启用窗口管理器监听器
    setHasVideo(false);
    setPlaying(false);
    setShowControls(true);
    _loadLastVideo();  // 加载上次播放的视频
    _focusNode.requestFocus();  // 请求焦点
    KeyboardShortcuts.loadShortcuts();  // 加载快捷键设置
    print('=== VideoPlayerState 初始化完成 ===\n');
  }

  bool get isPlaying => _isPlaying;
  bool get showControls => _showControls;
  bool get isFullscreen => _isFullscreen;  // 添加全屏状态getter
  double get progress => _progress;
  Duration get duration => _duration;
  Duration get position => _position;
  String? get error => _error;
  double get aspectRatio => _aspectRatio;
  bool get isLoading => _isLoading;
  bool get hasVideo => _hasVideo;

  // 设置控件是否被悬停
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

  // 重置鼠标隐藏计时器
  void resetHideMouseTimer() {
    _hideMouseTimer?.cancel();
    if (_hasVideo && !_isControlsHovered && !globals.isPhone) {
      _hideMouseTimer = Timer(const Duration(milliseconds: 1500), () {
        setShowControls(false);
      });
    }
  }

  // 重置控制栏隐藏计时器
  void resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    setShowControls(true);
    if (_hasVideo && !_isControlsHovered && !globals.isPhone) {
      _hideControlsTimer = Timer(const Duration(milliseconds: 1500), () {
        setShowControls(false);
      });
    }
  }

  // 处理鼠标移动
  void handleMouseMove(Offset position) {
    if (!_isControlsHovered && !globals.isPhone) {
      resetHideControlsTimer();
      resetHideMouseTimer();
    }
  }

  // 切换控制栏显示状态
  void toggleControls() {
    setShowControls(!_showControls);
    if (_showControls && _hasVideo && !_isControlsHovered && !globals.isPhone) {
      resetHideControlsTimer();
    }
  }

  void setPlaying(bool value) {
    _isPlaying = value;
    if (value) {
      resetHideControlsTimer();
    }
    notifyListeners();
  }

  void setShowControls(bool value) {
    _showControls = value;
    notifyListeners();
  }

  void setProgress(double value) {
    _progress = value;
    notifyListeners();
  }

  void setDuration(Duration value) {
    _duration = value;
    notifyListeners();
  }

  void setPosition(Duration value) {
    _position = value;
    _saveLastVideo();  // 保存最后播放位置
    notifyListeners();
  }

  void setError(String? value) {
    _error = value;
    notifyListeners();
  }

  void setAspectRatio(double value) {
    _aspectRatio = value;
    notifyListeners();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setHasVideo(bool value) {
    _hasVideo = value;
    notifyListeners();
  }

  void _startPositionUpdateTimer() {
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isSeeking) {  // 只在非拖动状态下更新位置
        setPosition(Duration(milliseconds: player.position));
        setDuration(Duration(milliseconds: player.mediaInfo.duration));
        if (_duration.inMilliseconds > 0) {
          setProgress(_position.inMilliseconds / _duration.inMilliseconds);
        }
      }
    });
  }

  Future<void> _loadLastVideo() async {
    final prefs = await SharedPreferences.getInstance();
    _lastVideoPath = prefs.getString(_lastVideoKey);
    final lastPosition = prefs.getInt(_lastPositionKey) ?? 0;

    if (_lastVideoPath != null) {
      await initializePlayer(_lastVideoPath!);
      if (lastPosition > 0) {
        seekTo(Duration(milliseconds: lastPosition));
      }
    }
  }

  Future<void> _saveLastVideo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastVideoKey, _lastVideoPath ?? '');
    await prefs.setInt(_lastPositionKey, _position.inMilliseconds);
  }

  Future<void> initializePlayer(String path) async {
    try {
      print('=== 开始初始化视频播放器 ===');
      print('视频路径: $path');
      
      setLoading(true);
      setError(null);
      setHasVideo(false);
      
      // 重置播放器状态
      try {
        print('重置播放器状态...');
        player.state = PlaybackState.stopped;
        player.media = '';
      } catch (e) {
        print('重置播放器状态时出错: $e');
      }
      
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
      
      // 设置视频状态
      setHasVideo(true);
      setDuration(Duration(milliseconds: player.mediaInfo.duration));
      setPosition(Duration.zero);
      setProgress(0.0);
      setPlaying(true);
      player.state = PlaybackState.playing;
      setLoading(false);
      
      // 保存最后播放的视频路径
      _lastVideoPath = path;
      await _saveLastVideo();
      
      print('=== 视频播放器初始化完成 ===');
    } catch (e, stackTrace) {
      print('\n=== 初始化视频播放器时出错 ===');
      print('错误信息: $e');
      print('错误堆栈: $stackTrace');
      print('=== 错误信息结束 ===\n');
      setError('初始化视频播放器时出错: $e');
      setLoading(false);
      setHasVideo(false);
    }
  }

  void togglePlayPause() {
    if (!_hasVideo) {
      print('没有视频可播放');
      return;
    }

    try {
      print('=== 切换播放状态 ===');
      print('当前状态: ${player.state}');
      
      if (player.state == PlaybackState.playing) {
        print('暂停播放...');
        player.state = PlaybackState.paused;
        setPlaying(false);
      } else {
        print('开始播放...');
        player.state = PlaybackState.playing;
        setPlaying(true);
      }
      
      print('新状态: ${player.state}');
      print('=== 播放状态切换完成 ===');
    } catch (e) {
      print('播放控制时出错: $e');
      setError('播放控制时出错: $e');
    }
  }

  void seekTo(Duration position) {
    if (_hasVideo) {
      try {
        _isSeeking = true;  // 开始拖动
        player.seek(position: position.inMilliseconds);
        setPosition(position);
        if (_duration.inMilliseconds > 0) {
          setProgress(position.inMilliseconds / _duration.inMilliseconds);
        }
        // 延迟重置拖动状态，确保位置更新完成
        Future.delayed(const Duration(milliseconds: 100), () {
          _isSeeking = false;
        });
      } catch (e) {
        setError('跳转时出错: $e');
        _isSeeking = false;  // 确保出错时也重置状态
      }
    }
  }

  Future<void> pickVideo() async {
    try {
      print('\n=== 开始选择视频 ===');
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mkv'],
        allowMultiple: false,
      );

      if (result != null) {
        print('用户选择了文件: ${result.files.single.name}');
        print('文件路径: ${result.files.single.path}');
        final file = File(result.files.single.path!);
        print('文件是否存在: ${await file.exists()}');
        print('文件大小: ${await file.length()} bytes');
        
        // 检查是否是上次播放的视频
        if (file.path == _lastVideoPath) {
          print('检测到是上次播放的视频，恢复播放位置');
          final prefs = await SharedPreferences.getInstance();
          final lastPosition = prefs.getInt(_lastPositionKey) ?? 0;
          await initializePlayer(file.path);
          if (lastPosition > 0) {
            seekTo(Duration(milliseconds: lastPosition));
            // 自动开始播放
            player.state = PlaybackState.playing;
            setPlaying(true);
          }
        } else {
          print('新视频，从头开始播放');
          await initializePlayer(file.path);
        }
      } else {
        print('用户取消了文件选择');
      }
      print('=== 视频选择过程结束 ===\n');
    } catch (e, stackTrace) {
      print('\n=== 选择视频时出错 ===');
      print('错误信息: $e');
      print('错误堆栈: $stackTrace');
      print('=== 错误信息结束 ===\n');
      setError('选择视频时出错: $e');
    }
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
      print('是否有视频: $_hasVideo');
      
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
        if (_hasVideo) {
          print('有视频，切换播放状态');
          togglePlayPause();
        } else {
          print('没有视频，忽略按键');
        }
      } else if (event.logicalKey == fullscreenKey) {
        print('全屏键按下');
        if (_hasVideo) {
          print('有视频，切换全屏状态');
          toggleFullscreen();
        }
      } else if (event.logicalKey == rewindKey) {
        print('快退键按下');
        print('当前视频位置: ${_position.inSeconds}秒');
        if (_hasVideo) {
          print('有视频，快退10秒');
          final newPosition = _position - const Duration(seconds: 10);
          print('新位置: ${newPosition.inSeconds}秒');
          seekTo(newPosition);
        }
      } else if (event.logicalKey == forwardKey) {
        print('快进键按下');
        print('当前视频位置: ${_position.inSeconds}秒');
        if (_hasVideo) {
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

  // 添加一个方法来检查是否需要显示AppBar
  bool shouldShowAppBar() {
    if (_isFullscreen) {
      return false;
    }
    if (globals.isPhone) {
      return !_hasVideo;
    }
    return true;
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _hideControlsTimer?.cancel();
    _hideMouseTimer?.cancel();  // 取消鼠标隐藏计时器
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);  // 移除窗口管理器监听器
    }
    _focusNode.dispose();  // 清理焦点节点
    _saveLastVideo();  // 保存最后播放位置
    player.dispose();
    super.dispose();
  }
} 