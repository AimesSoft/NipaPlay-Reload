import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../player_abstraction/player_factory.dart';
import '../player_abstraction/player_abstraction.dart';
import '../danmaku_abstraction/danmaku_kernel_factory.dart';
import '../danmaku_next/next2_platform_support.dart';
import 'globals.dart' as globals;
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_player_state.dart';
import '../models/watch_history_model.dart';

/// 播放器内核管理器
/// 提供多内核支持的静态工具方法
class PlayerKernelManager {
  static const Duration defaultHotSwapPlayerDisposalTimeout =
      Duration(seconds: 5);

  /// 为VideoPlayerState执行播放器内核热切换
  static Future<void> performPlayerKernelHotSwap(
    VideoPlayerState videoPlayerState, {
    Duration playerDisposalTimeout = defaultHotSwapPlayerDisposalTimeout,
  }) async {
    if (videoPlayerState.isDisposed) {
      return;
    }
    debugPrint('[PlayerKernelManager] 开始执行播放器内核热切换...');

    // 1. 保存当前播放状态
    final currentPath = videoPlayerState.currentVideoPath;
    final currentPosition = videoPlayerState.position;
    debugPrint('[PlayerKernelManager] 切换捕获 position=${currentPosition.inMilliseconds}ms');
    final currentDuration = videoPlayerState.duration;
    final currentProgress = videoPlayerState.progress;
    final currentPlaybackRate = videoPlayerState.playbackRate;
        final previousPlayer = videoPlayerState.player;
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
      await _disposePlayerForHotSwap(
        previousPlayer,
        timeout: playerDisposalTimeout,
      );
      if (videoPlayerState.isDisposed) {
        return;
      }
      videoPlayerState.player = Player();
      videoPlayerState.subtitleManager.updatePlayer(videoPlayerState.player);
      videoPlayerState.audioTrackManager.updatePlayer(videoPlayerState.player);
      videoPlayerState.decoderManager.updatePlayer(videoPlayerState.player);
      await videoPlayerState.applyAnime4KProfileToCurrentPlayer();
      if (videoPlayerState.isDisposed) return;
      await videoPlayerState.applyHardwareDecoderPreference();
      if (videoPlayerState.isDisposed) return;
      await videoPlayerState.applyPrecacheBufferSettings();
      if (videoPlayerState.isDisposed) return;
      await videoPlayerState.applySubtitleStylePreference();
      // 恢复音量到新播放器，避免默认 1.0 导致下次播放音量异常
      videoPlayerState.applyPlayerVolume();
      debugPrint('[PlayerKernelManager] 已创建新的空播放器实例');
      return;
    }

    // 2. 释放旧播放器资源
    await videoPlayerState.resetPlayer();
    await _disposePlayerForHotSwap(
      previousPlayer,
      timeout: playerDisposalTimeout,
    );
    if (videoPlayerState.isDisposed) {
      return;
    }

    // 3. 创建新的播放器实例（Player()工厂会自动使用新的内核）
    videoPlayerState.player = Player();
    // mdk/libmpv 内核 setMedia 后会自动进入播放（erika 不自动）。
    // 切换初始化期间先静音，避免自动播放的 1 秒有声音；就绪后
    // seek+暂停，再由 applyPlayerVolume 恢复用户音量。
    videoPlayerState.player.volume = 0;
    videoPlayerState.subtitleManager.updatePlayer(videoPlayerState.player);
    videoPlayerState.audioTrackManager.updatePlayer(videoPlayerState.player);
    videoPlayerState.decoderManager.updatePlayer(videoPlayerState.player);
    await videoPlayerState.applyAnime4KProfileToCurrentPlayer();
    if (videoPlayerState.isDisposed) return;
    await videoPlayerState.applyHardwareDecoderPreference();
    if (videoPlayerState.isDisposed) return;
    await videoPlayerState.applyPrecacheBufferSettings();
    if (videoPlayerState.isDisposed) return;
    await videoPlayerState.applySubtitleStylePreference();
    if (videoPlayerState.isDisposed) return;

    // 4. 重新初始化播放（autoPlay=false：切换后保持暂停，避免"播一下又停"）
    await videoPlayerState.initializePlayer(
      currentPath,
      historyItem: historyItem,
      resetManualDanmakuOffset: false,
      autoPlay: false,
    );
    if (videoPlayerState.isDisposed) return;

    // 5. 恢复播放状态
    if (videoPlayerState.hasVideo) {
      videoPlayerState.applyPlayerVolume();
      // 恢复播放速度设置
      if (currentPlaybackRate != 1.0) {
        videoPlayerState.player.setPlaybackRate(currentPlaybackRate);
        debugPrint('[PlayerKernelManager] 恢复播放速度设置: ${currentPlaybackRate}x');
      }
      videoPlayerState.seekTo(currentPosition);
      debugPrint('[PlayerKernelManager] 切换后 seekTo=${currentPosition.inMilliseconds}ms 内核=${videoPlayerState.player.getPlayerKernelName()}');
            // 切换后不自动恢复播放：新内核刚创建，立即 play 会"播一下又暂停"
            // （内核未就绪状态机自动暂停），突兀且无意义。切完保持暂停，
            // 用户想继续播放时手动点播放即可。
            videoPlayerState.pause();
            debugPrint('[PlayerKernelManager] 播放器内核热切换完成（暂停态，等待用户播放）');
    } else {
      debugPrint('[PlayerKernelManager] 播放器内核热切换完成，但未能恢复播放（可能视频加载失败）');
    }
  }

  static Future<void> _disposePlayerForHotSwap(
      Player player, {
      required Duration timeout,
    }) async {
      final kernelName = player.getPlayerKernelName();
      debugPrint(
        '[PlayerKernelManager] Waiting for old player teardown before hot swap: '
        'kernel=$kernelName timeoutMs=${timeout.inMilliseconds}',
      );
      try {
        await player.disposeAsync().timeout(timeout);
        debugPrint(
          '[PlayerKernelManager] Old player teardown completed: '
          'kernel=$kernelName',
        );
      } on TimeoutException catch (_, stackTrace) {
        // 回退到上游 .6 逻辑：旧内核释放超时直接中止切换（throw），
        // 不再"继续创建新播放器"——旧资源未释放就建新的会造成资源重叠，
        // mdk 关软解看一半再切 libmpv 时 app 卡死（用户已复现）。
        // 切换失败但 UI 不卡，比静默卡死好；异常由调用方兜底提示。
        final error = TimeoutException(
          'Old player teardown timed out after ${timeout.inMilliseconds}ms; '
          'replacement creation was aborted to avoid overlapping resources.',
          timeout,
        );
        debugPrint(
          '[PlayerKernelManager] Native/backend player teardown timed out; '
          'replacement creation aborted: kernel=$kernelName '
          'timeoutMs=${timeout.inMilliseconds}\n$stackTrace',
        );
        Error.throwWithStackTrace(error, stackTrace);
      } catch (error, stackTrace) {
        debugPrint(
          '[PlayerKernelManager] Native/backend player teardown failed; '
          'replacement creation aborted: kernel=$kernelName '
          '$error\n$stackTrace',
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

  /// 为VideoPlayerState执行弹幕内核热切换
  static void performDanmakuKernelHotSwap(
      VideoPlayerState videoPlayerState, DanmakuRenderEngine newKernel) {
    debugPrint('[PlayerKernelManager] 执行弹幕内核热切换: $newKernel');

    // 重新创建弹幕控制器
    videoPlayerState.danmakuController = _createDanmakuController(newKernel);

    // 重新加载当前弹幕数据（Erika 内核下弹幕由播放内核原生渲染，
    // 不把数据喂回 Flutter 弹幕控制器，避免双画）
    if (videoPlayerState.danmakuList.isNotEmpty &&
        !videoPlayerState.isNativeDanmakuActive) {
      videoPlayerState.danmakuController
          ?.loadDanmaku(videoPlayerState.danmakuList);
      debugPrint(
          '[PlayerKernelManager] 已将 ${videoPlayerState.danmakuList.length} 条弹幕重新加载到新的弹幕控制器');
    }

    // 通知UI刷新，以便DanmakuOverlay可以重建
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
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
    } else if (globals.isTvOS) {
      return ['Erika'];
    } else if (PlayerFactory.isHarmonyOS) {
      return ['FVP', 'Erika'];
    } else if (Platform.isIOS) {
      // iOS平台支持的内核
      return ['FVP', 'Video Player', 'Erika'];
    } else if (Platform.isAndroid) {
      // Android平台支持的内核
      final androidKernels = ['FVP', 'Media Kit', 'Video Player'];
      if (PlayerFactory.isErikaKernelSupported) {
        androidKernels.add('Erika');
      }
      return androidKernels;
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // 桌面平台支持所有内核
      if (PlayerFactory.isErikaKernelSupported) {
        kernels.add('Erika');
      }
      return kernels;
    }

    return kernels;
  }

  /// 获取当前播放器内核
  static Future<String> getCurrentPlayerKernel() async {
    if (globals.isTvOS) return 'Erika';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('player_kernel') ?? 'FVP';
  }

  /// 设置播放器内核
  static Future<void> setPlayerKernel(String kernel) async {
    final resolvedKernel = globals.isTvOS ? 'Erika' : kernel;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_kernel', resolvedKernel);

    // 转换为枚举值
    PlayerKernelType kernelType;
    switch (resolvedKernel) {
      case 'FVP':
        kernelType = PlayerKernelType.mdk;
        break;
      case 'Media Kit':
        kernelType = PlayerKernelType.mediaKit;
        break;
      case 'Video Player':
        kernelType = PlayerKernelType.videoPlayer;
        break;
      case 'Erika':
        kernelType = PlayerKernelType.erika;
        break;
      default:
        kernelType = PlayerKernelType.mdk;
    }

    // 通知PlayerFactory内核已改变
    await PlayerFactory.saveKernelType(kernelType);
  }

  /// 获取支持的弹幕内核列表
  static List<String> getSupportedDanmakuKernels() {
    final kernels = <String>[
      'Canvas 弹幕',
      'GPU渲染',
      'CPU渲染',
      DanmakuKernelFactory.nipaplayNextDisplayName,
    ];
    if (Next2PlatformSupport.isKernelSupported) {
      kernels.add('NipaPlay Next2');
      kernels.add('DFM+');
    }
    return kernels;
  }

  /// 获取当前弹幕内核
  static Future<String> getCurrentDanmakuKernel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SettingsKeys.legacyDanmakuKernel) ??
        (Next2PlatformSupport.isKernelSupported
            ? 'NipaPlay Next2'
            : 'NipaPlay Next');
  }

  /// 设置弹幕内核
  static Future<void> setDanmakuKernel(String kernel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsKeys.legacyDanmakuKernel, kernel);

    // 转换为枚举值
    DanmakuRenderEngine engine;
    switch (kernel) {
      case 'GPU渲染':
        engine = DanmakuRenderEngine.gpu;
        break;
      case 'CPU渲染':
        engine = DanmakuRenderEngine.cpu;
        break;
      case 'NipaPlay Next':
      case 'NipaPlay Next++':
      case 'NipaPlay Next (实验性)':
        engine = DanmakuRenderEngine.nipaplayNext;
        break;
      case 'NipaPlay Next2':
      case 'NipaPlay Next2 (实验性)':
        engine = DanmakuRenderEngine.next2;
        break;
      case 'DFM+':
      case 'DFM+ (实验性)':
        engine = DanmakuRenderEngine.dfmPlus;
        break;
      case 'Canvas弹幕':
      case 'Canvas 弹幕':
        engine = DanmakuRenderEngine.canvas;
        break;
      default:
        engine = DanmakuRenderEngine.canvas;
    }

    if ((engine == DanmakuRenderEngine.next2 ||
            engine == DanmakuRenderEngine.dfmPlus) &&
        !Next2PlatformSupport.isKernelSupported) {
      engine = DanmakuRenderEngine.canvas;
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
      case PlayerKernelType.erika:
        playerKernelName = 'Erika';
        break;
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
    if (globals.isTelevision) {
      return globals.isAndroidTv ? 'Android TV' : 'tvOS';
    }
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}
