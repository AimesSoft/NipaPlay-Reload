import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import './abstract_player.dart';
import './player_enums.dart';
import './player_data_models.dart';

/// video_player 插件的适配器，实现 AbstractPlayer 接口
class VideoPlayerAdapter implements AbstractPlayer {
  VideoPlayerController? _controller;
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  String _mediaPath = '';
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  double _volume = 1.0;
  final List<int> _activeSubtitleTracks = [];
  final List<int> _activeAudioTracks = [];
  final Map<String, String> _properties = {};
  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: ['default'],
    PlayerMediaType.audio: ['default'],
    PlayerMediaType.subtitle: ['default'],
  };
  
  // 时间轴流式更新相关
  final ValueNotifier<int> _positionNotifier = ValueNotifier<int>(0);
  Timer? _positionTimer;
  int _lastKnownPosition = 0;
  DateTime _lastPositionUpdateTime = DateTime.now();
  bool _isPlaying = false;

  VideoPlayerAdapter() {
    print('[VideoPlayerAdapter] 初始化');
    _startPositionTimer();
  }

  /// 启动位置更新定时器，用于提供流式时间轴
  void _startPositionTimer() {
    // 每20毫秒更新一次位置，相当于50fps的更新率
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 12), (timer) {
      _updateInterpolatedPosition();
    });
  }
  
  /// 根据播放状态和时间流逝计算插值位置
  void _updateInterpolatedPosition() {
    if (_controller == null || !_controller!.value.isInitialized) {
      _positionNotifier.value = 0;
      return;
    }
    
    // 如果不是播放状态，直接使用实际位置
    if (!_isPlaying) {
      _positionNotifier.value = _controller!.value.position.inMilliseconds;
      return;
    }
    
    // 计算自上次更新以来经过的时间
    final now = DateTime.now();
    final elapsedSinceLastUpdate = now.difference(_lastPositionUpdateTime).inMilliseconds;
    
    // 根据播放状态和时间流逝计算插值位置
    if (_controller!.value.isPlaying) {
      // 实际位置 = 上次已知位置 + 经过的时间
      final interpolatedPosition = _lastKnownPosition + elapsedSinceLastUpdate;
      
      // 确保不超过视频总长度
      final duration = _controller!.value.duration.inMilliseconds;
      final clampedPosition = duration > 0 ? 
          interpolatedPosition.clamp(0, duration) : interpolatedPosition;
      
      _positionNotifier.value = clampedPosition;
    } else {
      // 如果播放器不是播放状态但我们的状态是播放中，可能是内部延迟，保持上次位置
      _positionNotifier.value = _lastKnownPosition;
    }
  }
  
  /// 从控制器更新实际位置信息
  void _updateActualPosition() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    _lastKnownPosition = _controller!.value.position.inMilliseconds;
    _lastPositionUpdateTime = DateTime.now();
    
    // 同步更新通知器值
    _positionNotifier.value = _lastKnownPosition;
  }

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _controller?.setVolume(_volume);
  }

  @override
  PlayerPlaybackState get state {
    if (_controller == null) {
      print('[VideoPlayerAdapter] state getter: 控制器为空，返回stopped');
      return PlayerPlaybackState.stopped;
    }
    
    try {
      if (_controller!.value.isPlaying) {
        return PlayerPlaybackState.playing;
      } else if (_controller!.value.isInitialized) {
        return PlayerPlaybackState.paused;
      } else {
        return PlayerPlaybackState.stopped;
      }
    } catch (e) {
      print('[VideoPlayerAdapter] 获取播放状态出错: $e');
      return PlayerPlaybackState.stopped;
    }
  }

  @override
  set state(PlayerPlaybackState value) {
    if (_controller == null) {
      print('[VideoPlayerAdapter] state setter: 控制器为空，忽略状态设置请求');
      return;
    }
    
    try {
      switch (value) {
        case PlayerPlaybackState.playing:
          if (!_controller!.value.isInitialized) {
            print('[VideoPlayerAdapter] 警告: 控制器未初始化，无法播放');
            return;
          }
          
          // 更新内部跟踪状态
          _isPlaying = true;
          
          // 更新初始位置基准点
          _updateActualPosition();
          
          // 直接调用内部方法，不使用异步
          // 否则VideoPlayerState可能无法识别状态变化
          _controller!.play();
          
          // 确保异步方法也被调用，以进行验证和重试
          playDirectly();
          break;
          
        case PlayerPlaybackState.paused:
          // 更新内部跟踪状态
          _isPlaying = false;
          
          _controller!.pause();
          pauseDirectly();
          
          // 暂停后更新一次准确位置
          Future.delayed(Duration(milliseconds: 50), () {
            _updateActualPosition();
          });
          break;
          
        case PlayerPlaybackState.stopped:
          // 更新内部跟踪状态
          _isPlaying = false;
          
          _controller!.pause();
          _controller!.seekTo(Duration.zero);
          
          // 停止后重置位置
          _lastKnownPosition = 0;
          _positionNotifier.value = 0;
          break;
      }
    } catch (e) {
      print('[VideoPlayerAdapter] 设置播放状态时出错: $e');
    }
  }

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  String get media => _mediaPath;

  @override
  set media(String value) {
    if (value == _mediaPath) return;
    
    // 释放旧控制器
    _disposeController();
    
    _mediaPath = value;
    if (value.isEmpty) return;
    
    print('[VideoPlayerAdapter] 设置媒体路径: $_mediaPath');
    
    // 使用通用方法创建控制器
    _createOrRebuildController();
  }

  void _disposeController() {
    try {
      if (_controller != null) {
        // 确保先停止播放
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        }
        
        // 更新内部状态
        _isPlaying = false;
        
        // 完全取消所有监听器
        _controller!.removeListener(_controllerListener);
        
        // 清空_textureId，这样UI会提前知道资源已释放
        _textureIdNotifier.value = null;
        
        print('[VideoPlayerAdapter] 开始释放控制器资源');
        _controller!.dispose();
        
        // 让它立即被标记为null，帮助垃圾回收
        final oldController = _controller;
        _controller = null;
        
        // 重置位置
        _lastKnownPosition = 0;
        _positionNotifier.value = 0;
        
        // 强制GC（Flutter没有直接调用GC的API，但可以用一些辅助操作）
        Future.delayed(Duration(milliseconds: 200), () {
          oldController?.dispose();
        });
      }
    } catch (e) {
      print('[VideoPlayerAdapter] 释放控制器时出错: $e');
      _controller = null;
      _textureIdNotifier.value = null;
      _lastKnownPosition = 0;
      _positionNotifier.value = 0;
    }
  }

  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;

  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> value) {
    _activeSubtitleTracks.clear();
    _activeSubtitleTracks.addAll(value);
    // video_player 不直接支持字幕管理
  }

  @override
  List<int> get activeAudioTracks => _activeAudioTracks;

  @override
  set activeAudioTracks(List<int> value) {
    _activeAudioTracks.clear();
    _activeAudioTracks.addAll(value);
    // video_player 不直接支持音轨选择
  }

  @override
  int get position {
    // 使用流式更新的位置而不是直接从控制器获取
    return _positionNotifier.value;
  }
  
  /// 获取位置通知器，用于UI绑定（如弹幕系统）
  ValueListenable<int> get positionNotifier => _positionNotifier;

  @override
  bool get supportsExternalSubtitles => false; // video_player 不支持外挂字幕

  @override
  Future<int?> updateTexture() async {
    if (_controller == null) {
      print('[VideoPlayerAdapter] updateTexture: 控制器为空，尝试重新创建');
      if (!_createOrRebuildController()) {
        return null;
      }
    }
    
    if (!_controller!.value.isInitialized) {
      try {
        print('[VideoPlayerAdapter] 开始初始化控制器');
        await _controller!.initialize().timeout(const Duration(seconds: 15), onTimeout: () {
          print('[VideoPlayerAdapter] 初始化超时');
          throw Exception('Video initialization timeout');
        });
        
        // 初始化成功后确保视频处于暂停状态
        await _controller!.pause();
        
        print('[VideoPlayerAdapter] 控制器初始化成功，更新媒体信息');
        _updateMediaInfo();
        _textureIdNotifier.value = _controller!.textureId;
        
        // 初始化后更新位置
        _updateActualPosition();
        
        print('[VideoPlayerAdapter] 纹理ID: ${_controller!.textureId}');
        return _controller!.textureId;
      } catch (e) {
        print('[VideoPlayerAdapter] 初始化失败: $e');
        return null;
      }
    }
    
    return _controller!.textureId;
  }

  void _updateMediaInfo() {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[VideoPlayerAdapter] _updateMediaInfo: 控制器未初始化或为空');
      return;
    }
    
    try {
      final videoSize = _controller!.value.size;
      // 确保视频尺寸有效
      if (videoSize.width <= 0 || videoSize.height <= 0) {
        print('[VideoPlayerAdapter] 视频尺寸无效: $videoSize');
      }
      
      final durationMs = _controller!.value.duration.inMilliseconds;
      // 确保视频时长有效
      if (durationMs <= 0) {
        print('[VideoPlayerAdapter] 警告: 视频持续时间为0或负值: $durationMs');
      }
      
      print('[VideoPlayerAdapter] 媒体信息: 尺寸=${videoSize.width}x${videoSize.height}, 时长=${durationMs}ms');
      
      // 创建基本的视频流信息
      final videoStreamInfo = PlayerVideoStreamInfo(
        codec: PlayerVideoCodecParams(
          width: videoSize.width > 0 ? videoSize.width.toInt() : 1920, 
          height: videoSize.height > 0 ? videoSize.height.toInt() : 1080,
          name: 'default'
        ),
        codecName: 'default',
      );
      
      // 创建基本的音频流信息
      final audioStreamInfo = PlayerAudioStreamInfo(
        codec: PlayerAudioCodecParams(
          name: 'default',
          bitRate: null,
          channels: null,
          sampleRate: null,
        ),
        title: 'Default Audio Track',
        language: 'unknown',
        metadata: const {},
        rawRepresentation: 'Default Audio Track',
      );
      
      _mediaInfo = PlayerMediaInfo(
        duration: durationMs > 0 ? durationMs : 0, // 确保时长不为负值
        video: [videoStreamInfo],
        audio: [audioStreamInfo],
        subtitle: [],
      );
    } catch (e) {
      print('[VideoPlayerAdapter] 更新媒体信息时出错: $e');
      // 创建默认媒体信息
      _mediaInfo = PlayerMediaInfo(
        duration: 0,
        video: [
          PlayerVideoStreamInfo(
            codec: PlayerVideoCodecParams(width: 1920, height: 1080, name: 'unknown'),
            codecName: 'unknown',
          )
        ],
        audio: [],
        subtitle: [],
      );
    }
  }

  @override
  void setMedia(String path, PlayerMediaType type) {
    if (path.isEmpty) {
      _disposeController();
      _mediaPath = '';
      return;
    }
    
    _mediaPath = path;
    
    // 不要立即创建控制器，使用Future.delayed确保前一个控制器完全释放
    Future.delayed(Duration(milliseconds: 200), () {
      _createOrRebuildController();
    });
  }

  @override
  Future<void> prepare() async {
    if (_controller == null) {
      print('[VideoPlayerAdapter] prepare方法中发现控制器为空，尝试重新创建');
      // 强制重新创建
      _disposeController();
      
      // 使用延迟确保资源完全释放
      await Future.delayed(Duration(milliseconds: 200));
      
      if (!_createOrRebuildController()) {
        throw Exception('无法准备播放器: 控制器创建失败');
      }
      
      // 等待控制器创建完成
      await Future.delayed(Duration(milliseconds: 300));
    }
    
    try {
      print('[VideoPlayerAdapter] 开始prepare控制器');
      
      if (_controller != null) {
        // 确保先暂停，重置状态
        if (_controller!.value.isPlaying) {
          await _controller!.pause();
        }
        
        // 强制重置内部状态
        if (_controller!.value.isInitialized) {
          // 尝试跳转到0位置重置内部状态
          await _controller!.seekTo(Duration.zero);
        }
        
        // 等待一段时间确保状态稳定
        await Future.delayed(Duration(milliseconds: 100));
        
        // 然后初始化
        await _controller!.initialize().timeout(const Duration(seconds: 15), onTimeout: () {
          print('[VideoPlayerAdapter] 初始化超时');
          throw Exception('视频初始化超时');
        });
      } else {
        throw Exception('控制器为空，无法初始化');
      }
      
      _updateMediaInfo();
      _textureIdNotifier.value = _controller!.textureId;
      
      // 初始化后确保视频处于暂停状态，这样UI可以正确显示
      if (_controller != null) {
        await _controller!.pause();
        print('[VideoPlayerAdapter] 初始化后将视频设置为暂停状态');
      }
      
    } catch (e) {
      print('[VideoPlayerAdapter] 准备失败: $e');
      
      // 尝试恢复 - 释放资源后重新创建
      _disposeController();
      await Future.delayed(Duration(milliseconds: 200));
      
      // 重建控制器并尝试再初始化一次
      if (_mediaPath.isNotEmpty && _createOrRebuildController()) {
        await Future.delayed(Duration(milliseconds: 300));
        
        try {
          if (_controller != null) {
            await _controller!.initialize();
            _updateMediaInfo();
            _textureIdNotifier.value = _controller!.textureId;
            await _controller!.pause();
            print('[VideoPlayerAdapter] 恢复成功: 控制器重建并初始化完成');
            return;
          }
        } catch (e2) {
          print('[VideoPlayerAdapter] 恢复失败: $e2');
          throw Exception('视频准备失败，恢复尝试也失败: $e2');
        }
      }
      
      throw Exception('视频准备失败: $e');
    }
  }

  @override
  void seek({required int position}) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    final duration = Duration(milliseconds: position);
    _controller!.seekTo(duration);
    
    // 立即更新本地位置，避免跳转延迟
    _lastKnownPosition = position;
    _positionNotifier.value = position;
    _lastPositionUpdateTime = DateTime.now();
    
    // 延迟更新一次以确保准确
    Future.delayed(Duration(milliseconds: 50), () {
      _updateActualPosition();
    });
  }

  @override
  void dispose() {
    // 停止位置更新定时器
    _positionTimer?.cancel();
    _positionTimer = null;
    
    _disposeController();
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      // 返回一个黑色帧
      if (width <= 0) width = 128;
      if (height <= 0) height = 72;
      final int numBytes = width * height * 4; // RGBA
      final Uint8List blackBytes = Uint8List(numBytes);
      // 设置透明度通道
      for (int i = 3; i < numBytes; i += 4) {
        blackBytes[i] = 255; // Alpha 通道设为完全不透明
      }
      print("[VideoPlayerAdapter] 截图失败，返回黑色帧 ${width}x${height}");
      return PlayerFrame(width: width, height: height, bytes: blackBytes);
    }
    
    // video_player 不直接支持帧截取，这里返回一个空实现
    // 实际应用中可以考虑使用其他方式实现截图功能
    print("[VideoPlayerAdapter] 不支持截图功能");
    
    // 返回一个彩色测试帧
    if (width <= 0) width = 128;
    if (height <= 0) height = 72;
    final int numBytes = width * height * 4; // RGBA
    final Uint8List colorBytes = Uint8List(numBytes);
    
    // 生成一个红色渐变测试图像
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int index = (y * width + x) * 4;
        colorBytes[index] = 255; // R
        colorBytes[index + 1] = (255 * x / width).toInt(); // G
        colorBytes[index + 2] = (255 * y / height).toInt(); // B
        colorBytes[index + 3] = 255; // Alpha
      }
    }
    
    return PlayerFrame(width: width, height: height, bytes: colorBytes);
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    if (decoders.isEmpty) return;
    _decoders[type] = List.from(decoders);
    // video_player 不支持解码器选择
  }

  @override
  List<String> getDecoders(PlayerMediaType type) {
    return _decoders[type] ?? ['default'];
  }

  @override
  String? getProperty(String key) {
    return _properties[key];
  }

  @override
  void setProperty(String key, String value) {
    _properties[key] = value;
  }

  /// 尝试创建或重建控制器
  /// 
  /// 如果媒体路径为空，返回false
  /// 如果创建成功，返回true
  /// 如果创建失败，返回false
  bool _createOrRebuildController() {
    if (_mediaPath.isEmpty) {
      print('[VideoPlayerAdapter] 无法创建控制器: 媒体路径为空');
      return false;
    }
    
    try {
      // 先确保释放旧控制器，并添加延迟确保彻底释放
      if (_controller != null) {
        _disposeController();
        
        // 添加延迟再创建新的，以确保资源释放
        Future.delayed(Duration(milliseconds: 300), () {
          _actuallyCreateController();
        });
        return true;
      } else {
        return _actuallyCreateController();
      }
    } catch (e) {
      print('[VideoPlayerAdapter] 创建控制器初始化流程出错: $e');
      return false;
    }
  }
  
  /// 实际执行控制器创建的方法
  bool _actuallyCreateController() {
    try {
      File file = File(_mediaPath);
      
      // 检查文件是否存在
      if (!file.existsSync() && !_mediaPath.startsWith('http')) {
        print('[VideoPlayerAdapter] 警告: 文件不存在: $_mediaPath');
      }
      
      if (_mediaPath.startsWith('http://') || _mediaPath.startsWith('https://')) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(_mediaPath));
      } else {
        _controller = VideoPlayerController.file(file);
      }
      
      // 设置音量
      _controller!.setVolume(_volume);
      
      // 添加详细的状态监听器
      _controller!.addListener(_controllerListener);
      
      // 等待一小段时间让控制器准备好
      Future.delayed(Duration(milliseconds: 50), () {
        if (_controller != null && !_controller!.value.isInitialized) {
          // 尝试预初始化但不等待结果，以提高用户体验
          _controller!.initialize().then((_) {
            _textureIdNotifier.value = _controller!.textureId;
            _updateMediaInfo();
          }).catchError((e) {
            print('[VideoPlayerAdapter] 控制器后台初始化失败: $e');
          });
        }
      });
      
      return true;
    } catch (e) {
      print('[VideoPlayerAdapter] 创建控制器失败: $e');
      
      // 特殊处理：如果由于某种原因创建失败，尝试不同的方法
      try {
        if (_mediaPath.startsWith('http://') || _mediaPath.startsWith('https://')) {
          _controller = VideoPlayerController.network(_mediaPath);
        } else {
          // 获取文件的规范路径
          File file = File(_mediaPath);
          String canonicalPath = file.absolute.path;
          _controller = VideoPlayerController.file(File(canonicalPath));
        }
        
        // 设置音量
        _controller!.setVolume(_volume);
        
        // 添加详细的状态监听器
        _controller!.addListener(_controllerListener);
        
        return true;
      } catch (e2) {
        print('[VideoPlayerAdapter] 替代方法创建控制器仍然失败: $e2');
        _controller = null;
        return false;
      }
    }
  }
  
  /// 控制器状态变化监听器
  void _controllerListener() {
    if (_controller == null) return;
    
    try {
      final value = _controller!.value;
      
      // 更新实际位置
      _updateActualPosition();
      
      // 处理播放状态变化
      if (_isPlaying != value.isPlaying) {
        _isPlaying = value.isPlaying;
        print('[VideoPlayerAdapter] 播放状态变化检测: $_isPlaying');
      }
      
      // 报告错误
      if (value.hasError) {
        print('[VideoPlayerAdapter] 控制器报告错误: ${value.errorDescription}');
      }
    } catch (e) {
      print('[VideoPlayerAdapter] 监听器处理状态变化时出错: $e');
    }
  }

  /// 直接播放视频
  Future<void> _playDirectly() async {
    // 检查是否有控制器和初始化状态
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[VideoPlayerAdapter] _playDirectly: 控制器为空或未初始化');
      return;
    }
    
    try {
      // 实际执行播放
      await _controller!.play();
      
      // 必须的延迟确认
      bool playStarted = false;
      for (int i = 0; i < 5; i++) {
        await Future.delayed(Duration(milliseconds: 200));
        if (_controller != null && _controller!.value.isPlaying) {
          playStarted = true;
          break;
        }
        
        // 重试执行播放
        try {
          if (_controller != null && _controller!.value.isInitialized) {
            await _controller!.play();
          }
        } catch (e) {
          // 忽略重试错误
        }
      }
      
      // 最后检查
      if (!playStarted && _controller != null && _controller!.value.isInitialized) {
        // 视频没有开始播放，尝试最后手段 - 先seek然后再播放
        try {
          final currentPosition = _controller!.value.position.inMilliseconds;
          // 先seek到当前位置附近
          await _controller!.seekTo(Duration(milliseconds: currentPosition));
          // 然后再次尝试播放
          await _controller!.play();
        } catch (e) {
          print('[VideoPlayerAdapter] 最终播放尝试失败: $e');
        }
      }
    } catch (e) {
      print('[VideoPlayerAdapter] 播放出错: $e');
      
      try {
        // 尝试一种替代方式播放
        if (_controller != null && _controller!.value.isInitialized) {
          // 先暂停再播放，完全重置状态
          await _controller!.pause();
          await Future.delayed(Duration(milliseconds: 200));
          await _controller!.play();
        }
      } catch (e2) {
        print('[VideoPlayerAdapter] 替代播放方法失败: $e2');
      }
    }
  }
  
  /// 直接暂停视频
  Future<void> _pauseDirectly() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[VideoPlayerAdapter] _pauseDirectly: 控制器为空或未初始化');
      return;
    }
    
    try {
      // 检查是否真的需要暂停
      if (!_controller!.value.isPlaying) {
        return;
      }
      
      await _controller!.pause();
      
      // 验证暂停是否生效
      await Future.delayed(Duration(milliseconds: 200), () async {
        if (_controller != null && _controller!.value.isPlaying) {
          print('[VideoPlayerAdapter] 暂停验证失败，重试');
          try {
            await _controller!.pause();
          } catch (e) {
            print('[VideoPlayerAdapter] 重试暂停出错: $e');
          }
          
          // 再次检查
          await Future.delayed(Duration(milliseconds: 100));
          if (_controller != null && _controller!.value.isPlaying) {
            print('[VideoPlayerAdapter] 警告: 多次尝试后暂停仍未生效');
          }
        }
      });
    } catch (e) {
      print('[VideoPlayerAdapter] 暂停出错: $e');
      
      // 尝试恢复
      if (_controller != null && _controller!.value.isInitialized) {
        try {
          await Future.delayed(Duration(milliseconds: 300));
          await _controller!.pause();
        } catch (e2) {
          print('[VideoPlayerAdapter] 错误恢复后重试暂停仍然失败: $e2');
        }
      }
    }
  }

  @override
  Future<void> playDirectly() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[VideoPlayerAdapter] playDirectly: 控制器为空或未初始化');
      return;
    }
    
    // 立即更新内部状态
    _isPlaying = true;
    _updateActualPosition();
    
    // 立即同步调用播放
    try {
      _controller!.play();
    } catch (e) {
      print('[VideoPlayerAdapter] 同步play调用出错: $e');
    }
    
    // 然后在后台异步进行验证和重试
    _playDirectly();
  }
  
  @override
  Future<void> pauseDirectly() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[VideoPlayerAdapter] pauseDirectly: 控制器为空或未初始化');
      return;
    }
    
    // 立即更新内部状态
    _isPlaying = false;
    
    // 立即同步调用暂停
    try {
      _controller!.pause();
    } catch (e) {
      print('[VideoPlayerAdapter] 同步pause调用出错: $e');
    }
    
    // 然后在后台异步进行验证和重试
    _pauseDirectly();
    
    // 暂停后更新一次准确位置
    Future.delayed(Duration(milliseconds: 50), () {
      _updateActualPosition();
    });
  }
} 