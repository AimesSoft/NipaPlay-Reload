import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import './abstract_player.dart';
import './player_enums.dart';
import './player_data_models.dart';

/// MediaKit播放器适配器 - 简化版
/// 实现AbstractPlayer接口，提供对media_kit播放器的封装
class MediaKitPlayerAdapter implements AbstractPlayer {
  // 核心组件
  final Player _player;
  late final VideoController _controller;
  
  // 纹理ID通知
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  
  // 状态数据
  String _currentMedia = '';
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  List<int> _activeSubtitleTracks = [];
  List<int> _activeAudioTracks = [];
  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: [],
    PlayerMediaType.audio: [],
    PlayerMediaType.subtitle: [],
    PlayerMediaType.unknown: [],
  };
  final Map<String, String> _properties = {};
  
  /// 创建一个MediaKit播放器适配器
  MediaKitPlayerAdapter() : _player = Player(
    configuration: PlayerConfiguration(
      // 基础配置
      libass: true,  // 支持ASS/SSA字幕
      bufferSize: 32 * 1024 * 1024,  // 设置合理的缓冲区大小以减少内存占用
      logLevel: MPVLogLevel.warn,  // 设置日志级别
    )
  ) {
    // 初始化视频控制器 - 添加硬件加速配置
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,  // 确保启用硬件加速
      ),
    );
    
    // 设置平台特定配置
    _setPlatformSpecificConfiguration();
    
    // 设置纹理ID
    _updateTextureId();
    
    // 添加状态监听
    _addEventListeners();
  }
  
  /// 设置平台特定配置
  void _setPlatformSpecificConfiguration() {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      // macOS平台特定配置
      try {
        // 使用Media对象的extras设置硬件解码参数
        final mediaOptions = {
          'videotoolbox.format': 'nv12',
          'vt.async': '1',
          'vt.hardware': '1',
        };
        
        // 保存设置到内部属性，以便在打开媒体时使用
        _properties.addAll(mediaOptions.map((key, value) => MapEntry(key, value)));
        
        // 优先使用VideoToolbox
        final videoDecoders = ['vt', 'hap', 'dav1d', 'ffmpeg'];
        setDecoders(PlayerMediaType.video, videoDecoders);
      } catch (e) {
        debugPrint('设置macOS特定配置失败: $e');
      }
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      // Windows平台特定配置
      try {
        // 使用Media对象的extras设置硬件解码参数
        final mediaOptions = {
          'hwdec': 'auto-copy',
          'gpu-api': 'auto',
        };
        
        // 保存设置到内部属性
        _properties.addAll(mediaOptions.map((key, value) => MapEntry(key, value)));
        
        // Windows平台优先使用Direct3D和MFT
        final videoDecoders = ['mft:d3d=11', 'd3d11', 'dxva', 'cuda', 'ffmpeg'];
        setDecoders(PlayerMediaType.video, videoDecoders);
      } catch (e) {
        debugPrint('设置Windows特定配置失败: $e');
      }
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      // Linux平台特定配置
      try {
        // 使用Media对象的extras设置硬件解码参数
        final mediaOptions = {
          'hwdec': 'auto-copy',
        };
        
        // 保存设置到内部属性
        _properties.addAll(mediaOptions.map((key, value) => MapEntry(key, value)));
        
        // Linux平台优先使用VAAPI和VDPAU
        final videoDecoders = ['vaapi', 'vdpau', 'nvdec', 'ffmpeg'];
        setDecoders(PlayerMediaType.video, videoDecoders);
      } catch (e) {
        debugPrint('设置Linux特定配置失败: $e');
      }
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      // Android平台特定配置
      try {
        // 使用Media对象的extras设置硬件解码参数
        final mediaOptions = {
          'hwdec': 'mediacodec',
        };
        
        // 保存设置到内部属性
        _properties.addAll(mediaOptions.map((key, value) => MapEntry(key, value)));
        
        // Android平台使用MediaCodec
        final videoDecoders = ['mediacodec', 'ffmpeg'];
        setDecoders(PlayerMediaType.video, videoDecoders);
      } catch (e) {
        debugPrint('设置Android特定配置失败: $e');
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS平台特定配置
      try {
        // 使用Media对象的extras设置硬件解码参数
        final mediaOptions = {
          'videotoolbox.format': 'nv12',
          'vt.async': '1',
          'vt.hardware': '1',
        };
        
        // 保存设置到内部属性
        _properties.addAll(mediaOptions.map((key, value) => MapEntry(key, value)));
        
        // 优先使用VideoToolbox
        final videoDecoders = ['vt', 'hap', 'dav1d', 'ffmpeg'];
        setDecoders(PlayerMediaType.video, videoDecoders);
      } catch (e) {
        debugPrint('设置iOS特定配置失败: $e');
      }
    }
  }
  
  /// 添加各种事件监听器
  void _addEventListeners() {
    // 播放状态监听
    _player.stream.playing.listen((playing) {
      _state = playing 
          ? PlayerPlaybackState.playing 
          : (_player.state.position.inMilliseconds > 0 
              ? PlayerPlaybackState.paused 
              : PlayerPlaybackState.stopped);
    });
    
    // 轨道监听
    _player.stream.tracks.listen(_updateMediaInfo);
    
    // 错误监听
    _player.stream.error.listen((error) {
      debugPrint('MediaKit错误: $error');
    });
    
    // 时长监听
    _player.stream.duration.listen((duration) {
      if (duration.inMilliseconds > 0 && _mediaInfo.duration != duration.inMilliseconds) {
        _mediaInfo = _mediaInfo.copyWith(duration: duration.inMilliseconds);
      }
    });
  }
  
  /// 更新纹理ID
  void _updateTextureId() {
    try {
      _textureIdNotifier.value = _controller.hashCode;
    } catch (e) {
      debugPrint('更新纹理ID失败: $e');
    }
  }
  
  /// 从MediaKit轨道更新媒体信息
  void _updateMediaInfo(Tracks tracks) {
    // 处理视频轨道
    List<PlayerVideoStreamInfo>? videoStreams;
    if (tracks.video.isNotEmpty) {
      videoStreams = tracks.video.map((track) => 
        PlayerVideoStreamInfo(
          codec: PlayerVideoCodecParams(
            width: 0,
            height: 0,
            name: track.title ?? track.language ?? 'Unknown',
          ),
          codecName: track.codec ?? 'Unknown',
        )
      ).toList();
    }
    
    // 处理音频轨道
    List<PlayerAudioStreamInfo>? audioStreams;
    if (tracks.audio.isNotEmpty) {
      audioStreams = tracks.audio.map((track) => 
        PlayerAudioStreamInfo(
          codec: PlayerAudioCodecParams(
            name: track.title ?? track.language ?? 'Unknown',
            channels: 0,
            sampleRate: 0,
            bitRate: null,
          ),
          title: track.title,
          language: track.language,
          metadata: {'id': track.id.toString()},
          rawRepresentation: 'Audio: ${track.title ?? track.language ?? 'Unknown'}',
        )
      ).toList();
    }
    
    // 处理字幕轨道
    List<PlayerSubtitleStreamInfo>? subtitleStreams;
    if (tracks.subtitle.isNotEmpty) {
      subtitleStreams = tracks.subtitle.map((track) => 
        PlayerSubtitleStreamInfo(
          title: track.title,
          language: track.language,
          metadata: {'id': track.id.toString()},
          rawRepresentation: 'Subtitle: ${track.title ?? track.language ?? 'Unknown'}',
        )
      ).toList();
    }
    
    // 更新媒体信息，保留已知的持续时间
    final currentDuration = _mediaInfo.duration > 0 
        ? _mediaInfo.duration 
        : _player.state.duration.inMilliseconds;
    
    _mediaInfo = PlayerMediaInfo(
      duration: currentDuration,
      video: videoStreams,
      audio: audioStreams,
      subtitle: subtitleStreams,
    );
  }
  
  // AbstractPlayer接口实现
  
  @override
  double get volume => _player.state.volume / 100.0;
  
  @override
  set volume(double value) {
    _player.setVolume(value.clamp(0.0, 1.0) * 100);
  }
  
  @override
  PlayerPlaybackState get state => _state;
  
  @override
  set state(PlayerPlaybackState value) {
    switch (value) {
      case PlayerPlaybackState.stopped:
        _player.stop();
        break;
      case PlayerPlaybackState.paused:
        _player.pause();
        break;
      case PlayerPlaybackState.playing:
        _player.play();
        break;
    }
    _state = value;
  }
  
  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;
  
  @override
  String get media => _currentMedia;
  
  @override
  set media(String value) {
    setMedia(value, PlayerMediaType.video);
  }
  
  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;
  
  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;
  
  @override
  set activeSubtitleTracks(List<int> value) {
    _activeSubtitleTracks = value;
    if (value.isNotEmpty && _player.state.tracks.subtitle.length > value.first) {
      _player.setSubtitleTrack(_player.state.tracks.subtitle[value.first]);
    } else {
      _player.setSubtitleTrack(SubtitleTrack.no());
    }
  }
  
  @override
  List<int> get activeAudioTracks => _activeAudioTracks;
  
  @override
  set activeAudioTracks(List<int> value) {
    _activeAudioTracks = value;
    if (value.isNotEmpty && _player.state.tracks.audio.length > value.first) {
      _player.setAudioTrack(_player.state.tracks.audio[value.first]);
    } else if (_player.state.tracks.audio.isNotEmpty) {
      _player.setAudioTrack(_player.state.tracks.audio.first);
    }
  }
  
  @override
  int get position => _player.state.position.inMilliseconds;
  
  @override
  bool get supportsExternalSubtitles => true;
  
  @override
  Future<int?> updateTexture() async {
    _updateTextureId();
    return _controller.hashCode;
  }
  
  @override
  void setMedia(String path, PlayerMediaType type) {
    _currentMedia = path;
    
    // 重置状态
    _activeSubtitleTracks = [];
    _activeAudioTracks = [];
    _mediaInfo = PlayerMediaInfo(duration: 0);
    
    // 构建媒体选项，包含平台特定配置
    final mediaOptions = <String, dynamic>{};
    
    // 添加所有保存的属性
    _properties.forEach((key, value) {
      mediaOptions[key] = value;
    });
    
    // 打开媒体，应用所有配置
    _player.open(Media(path, extras: mediaOptions), play: false);
  }
  
  @override
  Future<void> prepare() async {
    await updateTexture();
  }
  
  @override
  void seek({required int position}) {
    _player.seek(Duration(milliseconds: position));
  }
  
  @override
  void dispose() {
    _player.dispose();
    _textureIdNotifier.dispose();
  }
  
  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    try {
      final bytes = await _player.screenshot();
      if (bytes != null) {
        return PlayerFrame(
          bytes: bytes,
          width: width > 0 ? width : 0,
          height: height > 0 ? height : 0,
        );
      }
    } catch (e) {
      debugPrint('截图失败: $e');
    }
    return null;
  }
  
  @override
  void setDecoders(PlayerMediaType type, List<String> names) {
    _decoders[type] = names;
  }
  
  @override
  List<String> getDecoders(PlayerMediaType type) {
    return _decoders[type] ?? [];
  }
  
  @override
  String? getProperty(String name) {
    return _properties[name];
  }
  
  @override
  void setProperty(String name, String value) {
    _properties[name] = value;
  }
  
  @override
  Future<void> playDirectly() async {
    await _player.play();
  }
  
  @override
  Future<void> pauseDirectly() async {
    await _player.pause();
  }
} 