import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart' show md5, sha256;
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import './abstract_player.dart';
import './player_enums.dart';
import './player_data_models.dart';
import '../models/watch_history_model.dart';
import '../models/watch_history_database.dart';

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
        if (e is PlatformException &&
            (e.message?.contains('无法打开: 不支持此媒体的格式') == true ||
             e.message?.contains('OSStatus错误-12847') == true ||
             e.message?.contains('无法打开: 此媒体可能已损坏') == true ||
             e.message?.contains('OSStatus错误-12848') == true 
            )) {
          String errMsg = "视频文件可能已损坏或无法读取。";
          if (e.message?.contains('不支持此媒体的格式') == true || e.message?.contains('OSStatus错误-12847') == true) {
            errMsg = "当前播放内核不支持此视频格式。";
          }
          print('[VideoPlayerAdapter] 特定视频错误(updateTexture). 设置mediaInfo.duration=0, specificErrorMessage: $errMsg, textureId=null.');
          _mediaInfo = PlayerMediaInfo(
            duration: 0,
            video: [PlayerVideoStreamInfo(codec: PlayerVideoCodecParams(width: 0, height: 0, name: 'video_error'), codecName: 'video_error')],
            audio: [],
            subtitle: [],
            specificErrorMessage: errMsg,
          );
          _textureIdNotifier.value = null;
          return null; // 返回null，不向上抛出此特定异常
        }
        // 对于其他初始化错误，保持原有行为（返回null）
        return null;
      }
    }
    
    return _controller!.textureId;
  }

  void _updateMediaInfo() {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[VideoPlayerAdapter] _updateMediaInfo: 控制器未初始化或为空');
      // 如果控制器未初始化，也应该重置 specificErrorMessage
      _mediaInfo = PlayerMediaInfo(duration: 0, specificErrorMessage: _mediaInfo.specificErrorMessage); // 保留可能已设置的错误信息
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
        specificErrorMessage: null, // <--- 成功获取信息时，清除特定错误信息
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
        specificErrorMessage: "更新媒体信息时出错", // <--- 可以考虑在这里也设置一个错误
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
      _disposeController();
      await Future.delayed(Duration(milliseconds: 200));
      if (!_createOrRebuildController()) {
        throw Exception('无法准备播放器: 控制器创建失败');
      }
      await Future.delayed(Duration(milliseconds: 300));
    }
    
    try {
      print('[VideoPlayerAdapter] 开始prepare控制器');
      if (_controller != null) {
        if (_controller!.value.isPlaying) {
          await _controller!.pause();
        }
        if (_controller!.value.isInitialized) {
          await _controller!.seekTo(Duration.zero);
        }
        await Future.delayed(Duration(milliseconds: 100));
        await _controller!.initialize().timeout(const Duration(seconds: 15), onTimeout: () {
          print('[VideoPlayerAdapter] 初始化超时');
          throw Exception('视频初始化超时');
        });
      } else {
        throw Exception('控制器为空，无法初始化');
      }
      
      _updateMediaInfo();
      _textureIdNotifier.value = _controller!.textureId;
      if (_controller != null) {
        await _controller!.pause();
        print('[VideoPlayerAdapter] 初始化后将视频设置为暂停状态');
      }
    } catch (e) {
      if (e is PlatformException &&
          (e.message?.contains('无法打开: 不支持此媒体的格式') == true ||
           e.message?.contains('OSStatus错误-12847') == true ||
           e.message?.contains('无法打开: 此媒体可能已损坏') == true ||
           e.message?.contains('OSStatus错误-12848') == true 
          )) {
        String errMsg = "视频文件可能已损坏或无法读取。";
        if (e.message?.contains('不支持此媒体的格式') == true || e.message?.contains('OSStatus错误-12847') == true) {
          errMsg = "当前播放内核不支持此视频格式。";
        }
        print('[VideoPlayerAdapter] 特定视频错误(prepare). 设置mediaInfo.duration=0, specificErrorMessage: $errMsg, textureId=null.');
        _mediaInfo = PlayerMediaInfo(
          duration: 0,
          video: [PlayerVideoStreamInfo(codec: PlayerVideoCodecParams(width: 0, height: 0, name: 'video_error'), codecName: 'video_error')],
          audio: [],
          subtitle: [],
          specificErrorMessage: errMsg,
        );
        _textureIdNotifier.value = null;
        return; // 直接返回，不向上抛出此特定异常，也不执行下面的恢复逻辑
      }
      
      print('[VideoPlayerAdapter] 准备失败: $e');
      _disposeController();
      await Future.delayed(Duration(milliseconds: 200));
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
    
    // video_player 不直接支持帧截取
    print("[VideoPlayerAdapter] 尝试查找媒体库缓存的封面图...");
    
    // 首先尝试查找与当前媒体文件关联的观看记录，看看是否有animeId
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final videoFileName = _mediaPath.split('/').last;
      
      // 1. 首先尝试从WatchHistoryDatabase获取animeId
      WatchHistoryItem? watchHistoryItem;
      try {
        watchHistoryItem = await WatchHistoryDatabase.instance.getHistoryByFilePath(_mediaPath);
      } catch (e) {
        print("[VideoPlayerAdapter] 获取观看记录时出错: $e");
      }
      
      // 2. 如果有animeId，尝试找到对应的番剧封面
      if (watchHistoryItem != null && watchHistoryItem.animeId != null) {
        final animeId = watchHistoryItem.animeId!;
        print("[VideoPlayerAdapter] 找到该视频的animeId: $animeId，尝试使用番剧封面");
        
        // 从SharedPreferences获取封面URL，使用MediaLibraryPage的键名格式
        final prefs = await SharedPreferences.getInstance();
        final String? imageUrl = prefs.getString('media_library_image_url_$animeId');
        
        if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
          print("[VideoPlayerAdapter] 找到番剧封面URL: $imageUrl");
          // 生成该URL的SHA-256哈希值
          final String imageHash = sha256.convert(utf8.encode(imageUrl)).toString();
          print("[VideoPlayerAdapter] 生成SHA-256哈希值: $imageHash");
          
          // 检查是否存在该哈希值对应的封面图文件
          final coverImagePath = '${appDir.path}/compressed_images/$imageHash.jpg';
          final coverImageFile = File(coverImagePath);
          
          if (coverImageFile.existsSync()) {
            print("[VideoPlayerAdapter] 找到番剧封面图: $coverImagePath");
            
            // 读取封面图并转换为PlayerFrame
            final Uint8List imageBytes = await coverImageFile.readAsBytes();
            
            // 解析图像获取尺寸
            final img.Image? image = img.decodeImage(imageBytes);
            if (image != null) {
              // 如果提供了目标尺寸，则调整图像大小并保持纵横比
              img.Image resizedImage;
              if (width > 0 && height > 0) {
                // 计算原始图像和目标尺寸的纵横比
                final double sourceRatio = image.width / image.height;
                final double targetRatio = width / height;
                
                if (sourceRatio > targetRatio) {
                  // 图像比目标更宽，基于高度调整尺寸并裁剪宽度
                  final int newWidth = (height * sourceRatio).toInt();
                  resizedImage = img.copyResize(image, width: newWidth, height: height);
                  
                  // 居中裁剪
                  final int cropStartX = (newWidth - width) ~/ 2;
                  resizedImage = img.copyCrop(resizedImage, 
                    x: cropStartX, y: 0, 
                    width: width, height: height);
                } else {
                  // 图像比目标更高，基于宽度调整尺寸并裁剪高度
                  final int newHeight = (width / sourceRatio).toInt();
                  resizedImage = img.copyResize(image, width: width, height: newHeight);
                  
                  // 居中裁剪
                  final int cropStartY = (newHeight - height) ~/ 2;
                  resizedImage = img.copyCrop(resizedImage, 
                    x: 0, y: cropStartY, 
                    width: width, height: height);
                }
              } else {
                width = image.width;
                height = image.height;
                resizedImage = image;
              }
              
              // 将图像转换为RGBA格式的字节
              final Uint8List rgbaBytes = Uint8List(width * height * 4);
              int byteIndex = 0;
              
              for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                  final pixel = resizedImage.getPixel(x, y);
                  rgbaBytes[byteIndex++] = pixel.r.toInt(); // R
                  rgbaBytes[byteIndex++] = pixel.g.toInt(); // G
                  rgbaBytes[byteIndex++] = pixel.b.toInt(); // B
                  rgbaBytes[byteIndex++] = pixel.a.toInt(); // A
                }
              }
              
              return PlayerFrame(width: width, height: height, bytes: rgbaBytes);
            }
          } else {
            print("[VideoPlayerAdapter] 找不到番剧封面图文件: $coverImagePath");
            print("[VideoPlayerAdapter] 尝试列出compressed_images目录内容...");
            try {
              final compressedImagesDir = Directory('${appDir.path}/compressed_images');
              if (compressedImagesDir.existsSync()) {
                final files = compressedImagesDir.listSync();
                print("[VideoPlayerAdapter] compressed_images目录中有 ${files.length} 个文件");
                if (files.length > 0) {
                  print("[VideoPlayerAdapter] 示例文件: ${files.first.path}");
                }
              } else {
                print("[VideoPlayerAdapter] compressed_images目录不存在");
              }
            } catch (e) {
              print("[VideoPlayerAdapter] 列出compressed_images目录出错: $e");
            }
          }
        } else {
          print("[VideoPlayerAdapter] 未找到番剧封面URL，键: 'media_library_image_url_$animeId'");
        }
      }
      
      // 3. 如果没有找到animeId或无法使用番剧封面，继续尝试使用观看记录缩略图
      // 计算当前视频文件的哈希值（与VideoPlayerState中_calculateFileHash相同逻辑）
      final String videoHash = md5.convert(utf8.encode(_mediaPath.split('/').last)).toString();
      
      // 查找可能存在的缩略图文件
      final thumbnailPath = '${appDir.path}/thumbnails/$videoHash.png';
      final thumbnailFile = File(thumbnailPath);
      
      if (thumbnailFile.existsSync()) {
        print("[VideoPlayerAdapter] 找到媒体库缓存的封面图: $thumbnailPath");
        
        // 读取封面图并转换为PlayerFrame
        final Uint8List imageBytes = await thumbnailFile.readAsBytes();
        
        // 解析图像获取尺寸
        final img.Image? image = img.decodeImage(imageBytes);
        if (image != null) {
          // 如果提供了目标尺寸，则调整图像大小并保持纵横比
          img.Image resizedImage;
          if (width > 0 && height > 0) {
            // 计算原始图像和目标尺寸的纵横比
            final double sourceRatio = image.width / image.height;
            final double targetRatio = width / height;
            
            if (sourceRatio > targetRatio) {
              // 图像比目标更宽，基于高度调整尺寸并裁剪宽度
              final int newWidth = (height * sourceRatio).toInt();
              resizedImage = img.copyResize(image, width: newWidth, height: height);
              
              // 居中裁剪
              final int cropStartX = (newWidth - width) ~/ 2;
              resizedImage = img.copyCrop(resizedImage, 
                x: cropStartX, y: 0, 
                width: width, height: height);
            } else {
              // 图像比目标更高，基于宽度调整尺寸并裁剪高度
              final int newHeight = (width / sourceRatio).toInt();
              resizedImage = img.copyResize(image, width: width, height: newHeight);
              
              // 居中裁剪
              final int cropStartY = (newHeight - height) ~/ 2;
              resizedImage = img.copyCrop(resizedImage, 
                x: 0, y: cropStartY, 
                width: width, height: height);
            }
          } else {
            width = image.width;
            height = image.height;
            resizedImage = image;
          }
          
          // 将图像转换为RGBA格式的字节
          final Uint8List rgbaBytes = Uint8List(width * height * 4);
          int byteIndex = 0;
          
          for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
              final pixel = resizedImage.getPixel(x, y);
              // 使用image包的颜色通道访问方法
              rgbaBytes[byteIndex++] = pixel.r.toInt(); // R
              rgbaBytes[byteIndex++] = pixel.g.toInt(); // G
              rgbaBytes[byteIndex++] = pixel.b.toInt(); // B
              rgbaBytes[byteIndex++] = pixel.a.toInt(); // A
            }
          }
          
          return PlayerFrame(width: width, height: height, bytes: rgbaBytes);
        }
      }
    } catch (e) {
      print("[VideoPlayerAdapter] 读取媒体库封面图失败: $e");
    }
    
    // 如果无法获取媒体库封面，则返回一个深灰色单色帧
    if (width <= 0) width = 128;
    if (height <= 0) height = 72;
    final int numBytes = width * height * 4; // RGBA
    final Uint8List grayBytes = Uint8List(numBytes);
    
    // 生成深灰色图像 (RGB: 64, 64, 64)
    for (int i = 0; i < numBytes; i += 4) {
      grayBytes[i] = 64;     // R = 64 (深灰色)
      grayBytes[i + 1] = 64; // G = 64
      grayBytes[i + 2] = 64; // B = 64
      grayBytes[i + 3] = 255; // Alpha = 完全不透明
    }
    
    return PlayerFrame(width: width, height: height, bytes: grayBytes);
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