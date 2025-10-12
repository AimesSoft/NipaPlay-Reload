import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../player_abstraction/player_factory.dart';
import '../player_abstraction/player_abstraction.dart';
import '../danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_player_state.dart';
import '../models/watch_history_model.dart';

/// 播放器内核管理器
/// 提供多内核支持的静态工具方法
class PlayerKernelManager {
  /// 为VideoPlayerState执行播放器内核热切换
  static Future<void> performPlayerKernelHotSwap(
      VideoPlayerState videoPlayerState) async {
    debugPrint('[PlayerKernelManager] 开始执行播放器内核热切换...');

    // 1. 保存当前播放状态
    final currentPath = videoPlayerState.currentVideoPath;
    final currentPosition = videoPlayerState.position;
    final currentDuration = videoPlayerState.duration;
    final currentProgress = videoPlayerState.progress;
    final currentVolume = videoPlayerState.player.volume;
    final currentPlaybackRate = videoPlayerState.playbackRate;
    final wasPlaying = videoPlayerState.status == PlayerStatus.playing;
    final historyItem = WatchHistoryItem(
      filePath: currentPath ?? '',
      animeName: videoPlayerState.animeTitle ?? '',
      episodeTitle: videoPlayerState.episodeTitle,
      episodeId: videoPlayerState.episodeId,
      animeId: videoPlayerState.animeId,
      lastPosition: currentPosition.inMilliseconds,
      duration: currentDuration.inMilliseconds,
      watchProgress: currentProgress,
      lastWatchTime: DateTime.now(),
    );

    if (currentPath == null) {
      debugPrint('[PlayerKernelManager] 没有正在播放的视频，仅创建新播放器实例');
      // 如果没有视频在播放，只需要创建一个新的播放器实例以备后用
      videoPlayerState.player.dispose();
      videoPlayerState.player = Player();
      videoPlayerState.subtitleManager.updatePlayer(videoPlayerState.player);
      videoPlayerState.decoderManager.updatePlayer(videoPlayerState.player);
      await videoPlayerState.applyAnime4KProfileToCurrentPlayer();
      debugPrint('[PlayerKernelManager] 已创建新的空播放器实例');
      return;
    }

    // 2. 释放旧播放器资源
    await videoPlayerState.resetPlayer();

    // 3. 创建新的播放器实例（Player()工厂会自动使用新的内核）
    videoPlayerState.player = Player();
    videoPlayerState.subtitleManager.updatePlayer(videoPlayerState.player);
    videoPlayerState.decoderManager.updatePlayer(videoPlayerState.player);
    await videoPlayerState.applyAnime4KProfileToCurrentPlayer();

    // 4. 重新初始化播放
    await videoPlayerState.initializePlayer(currentPath,
        historyItem: historyItem);

    // 5. 恢复播放状态
    if (videoPlayerState.hasVideo) {
      videoPlayerState.player.volume = currentVolume;
      // 恢复播放速度设置
      if (currentPlaybackRate != 1.0) {
        videoPlayerState.player.setPlaybackRate(currentPlaybackRate);
        debugPrint('[PlayerKernelManager] 恢复播放速度设置: ${currentPlaybackRate}x');
      }
      videoPlayerState.seekTo(currentPosition);
      if (wasPlaying) {
        videoPlayerState.play();
      } else {
        videoPlayerState.pause();
      }
      debugPrint('[PlayerKernelManager] 播放器内核热切换完成，已恢复播放状态');
    } else {
      debugPrint('[PlayerKernelManager] 播放器内核热切换完成，但未能恢复播放（可能视频加载失败）');
    }
  }

  /// 为VideoPlayerState执行弹幕内核热切换
  static void performDanmakuKernelHotSwap(
      VideoPlayerState videoPlayerState, DanmakuRenderEngine newKernel) {
    debugPrint('[PlayerKernelManager] 执行弹幕内核热切换: $newKernel');

    // 重新创建弹幕控制器
    videoPlayerState.danmakuController = _createDanmakuController(newKernel);

    // 重新加载当前弹幕数据
    if (videoPlayerState.danmakuList.isNotEmpty) {
      videoPlayerState.danmakuController
          ?.loadDanmaku(videoPlayerState.danmakuList);
      debugPrint(
          '[PlayerKernelManager] 已将 ${videoPlayerState.danmakuList.length} 条弹幕重新加载到新的弹幕控制器');
    }

    // 通知UI刷新，以便DanmakuOverlay可以重建
    videoPlayerState.notifyListeners();
  }

  /// 创建弹幕控制器
  static dynamic _createDanmakuController(DanmakuRenderEngine kernelType) {
    // 根据内核类型创建不同的弹幕控制器
    switch (kernelType) {
      case DanmakuRenderEngine.cpu:
        // 返回CPU弹幕的控制器（如果需要）
        return null;
      case DanmakuRenderEngine.gpu:
        // GPU渲染在Widget层处理，这里不直接创建控制器
        return null;
      default:
        return null;
    }
  }

  /// 获取支持的播放器内核列表
  static List<String> getSupportedPlayerKernels() {
    List<String> kernels = ['FVP', 'Media Kit', 'Video Player'];

    // 根据平台过滤支持的内核
    if (kIsWeb) {
      // Web平台只支持特定内核
      return ['Video Player'];
    } else if (Platform.isIOS) {
      // iOS平台支持的内核
      return ['FVP', 'Video Player'];
    } else if (Platform.isAndroid) {
      // Android平台支持的内核
      return ['FVP', 'Media Kit', 'Video Player'];
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面平台支持所有内核
      return kernels;
    }

    return kernels;
  }

  /// 获取当前播放器内核
  static Future<String> getCurrentPlayerKernel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('player_kernel') ?? 'FVP';
  }

  /// 设置播放器内核
  static Future<void> setPlayerKernel(String kernel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_kernel', kernel);

    // 转换为枚举值
    PlayerKernelType kernelType;
    switch (kernel) {
      case 'FVP':
        kernelType = PlayerKernelType.mdk;
        break;
      case 'Media Kit':
        kernelType = PlayerKernelType.mediaKit;
        break;
      case 'Video Player':
        kernelType = PlayerKernelType.videoPlayer;
        break;
      default:
        kernelType = PlayerKernelType.mdk;
    }

    // 通知PlayerFactory内核已改变
    await PlayerFactory.saveKernelType(kernelType);
  }

  /// 获取支持的弹幕内核列表
  static List<String> getSupportedDanmakuKernels() {
    return ['GPU渲染', 'CPU渲染'];
  }

  /// 获取当前弹幕内核
  static Future<String> getCurrentDanmakuKernel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('danmaku_kernel') ?? 'GPU渲染';
  }

  /// 设置弹幕内核
  static Future<void> setDanmakuKernel(String kernel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('danmaku_kernel', kernel);

    // 转换为枚举值
    DanmakuRenderEngine engine;
    switch (kernel) {
      case 'GPU渲染':
        engine = DanmakuRenderEngine.gpu;
        break;
      case 'CPU渲染':
        engine = DanmakuRenderEngine.cpu;
        break;
      default:
        engine = DanmakuRenderEngine.gpu;
    }

    // 通知DanmakuKernelFactory内核已改变
    await DanmakuKernelFactory.saveKernelType(engine);
  }

  /// 获取内核性能信息
  static Map<String, dynamic> getKernelPerformanceInfo() {
    final playerKernelType = PlayerFactory.getKernelType();
    String playerKernelName;
    switch (playerKernelType) {
      case PlayerKernelType.mdk:
        playerKernelName = 'FVP';
        break;
      case PlayerKernelType.mediaKit:
        playerKernelName = 'Media Kit';
        break;
      case PlayerKernelType.videoPlayer:
        playerKernelName = 'Video Player';
        break;
      default:
        playerKernelName = 'Unknown';
    }

    return {
      'player_kernel': playerKernelName,
      'danmaku_kernel': DanmakuKernelFactory.getKernelType().toString(),
      'supports_hardware_decode': _supportsHardwareDecode(),
      'platform': _getPlatformInfo(),
    };
  }

  /// 获取当前内核信息
  static Future<Map<String, String>> getCurrentKernelInfo() async {
    return {
      'player': await getCurrentPlayerKernel(),
      'danmaku': await getCurrentDanmakuKernel(),
    };
  }

  /// 检查是否支持硬件解码
  static bool _supportsHardwareDecode() {
    if (kIsWeb) return false;

    if (Platform.isAndroid || Platform.isIOS) {
      return true; // 移动平台通常支持硬件解码
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return true; // 桌面平台需要具体检测，这里简化为true
    }

    return false;
  }

  /// 获取平台信息
  static String _getPlatformInfo() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}
