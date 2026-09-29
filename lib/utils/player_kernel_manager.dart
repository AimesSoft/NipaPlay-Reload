import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../player_abstraction/player_factory.dart';
import '../player_abstraction/player_abstraction.dart';
import '../danmaku_abstraction/danmaku_kernel_factory.dart';
import '../danmaku_next/next2_platform_support.dart';
import 'globals.dart' as globals;
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'video_player_state.dart';
import '../models/watch_history_model.dart';

/// 播放器内核管理器
/// 提供多内核支持的静态工具方法
class PlayerKernelManager {
  static const Duration defaultHotSwapPlayerDisposalTimeout =
      Duration(seconds: 10);

  // ── 热切换同步落盘 trace ────────────────────────────────────────────
  // FileLogService 每 1s 才从内存缓冲刷盘，主 isolate 被原生 FFI 阻塞或
  // 崩溃时缓冲全部丢失（用户实测：app 卡死后日志中断，无法定位卡死点）。
  // 这里在每个阶段【之前】同步 writeAsStringSync(flush:true)——app 卡死后
  // 日志文件的最后一行即精确卡死步骤。仅热切换期间写入，开销可忽略。
  static String? _hotSwapTraceFilePath;

  static Future<void> _prepareHotSwapTraceFile() async {
    if (_hotSwapTraceFilePath != null) return;
    try {
      final appDir = await StorageService.getAppStorageDirectory();
      final logDir = Directory(p.join(appDir.path, 'logs'));
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      _hotSwapTraceFilePath = p.join(logDir.path, 'kernel_swap_trace.txt');
    } catch (_) {
      // 落盘不可用时静默降级：trace 仍会输出到 debugPrint
    }
  }

  /// 同步写入一条热切换阶段 trace（可被各内核适配器调用）。
  static void traceHotSwapStage(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    debugPrint('[KernelSwapTrace] $line');
    final file = _hotSwapTraceFilePath;
    if (file == null) return;
    try {
      File(file).writeAsStringSync(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // trace 失败不影响热切换本身
    }
  }

  /// Serialize swaps and create a replacement only after native teardown succeeds.
  static Future<void> performPlayerKernelHotSwap(
    VideoPlayerState videoPlayerState, {
    Duration playerDisposalTimeout = defaultHotSwapPlayerDisposalTimeout,
  }) {
    final task = _hotSwapQueue.catchError((Object _) {}).then(
          (_) => _performPlayerKernelHotSwapLocked(
            videoPlayerState,
            playerDisposalTimeout: playerDisposalTimeout,
          ),
        );
    _hotSwapQueue = task;
    return task;
  }

  /// 热切换排队链：前一轮完成前，后续切换一律等待。
  static Future<void> _hotSwapQueue = Future<void>.value();

  static Future<void> _performPlayerKernelHotSwapLocked(
    VideoPlayerState videoPlayerState, {
    required Duration playerDisposalTimeout,
  }) async {
    if (videoPlayerState.isDisposed) {
      return;
    }
    await _prepareHotSwapTraceFile();
    traceHotSwapStage(
        'swap begin kernel=${videoPlayerState.player.getPlayerKernelName()}');
    // surface 代数自增 → 渲染层 ValueKey 变化 → 旧 Texture/PlatformView 子树
    // 被强制销毁重建（等效"关闭重开"）。必须在创建新 Player 之前发生，
    // 保证新 surface 挂载时平台线程上只有新内核实例。
    traceHotSwapStage('stage=surfaceSwap begin');
    videoPlayerState.beginKernelSurfaceSwap();
    traceHotSwapStage('stage=surfaceSwap done');
    await performPlayerKernelHotSwapSteps(
      videoPlayerState,
      playerDisposalTimeout: playerDisposalTimeout,
    );
  }

  static Future<void> _disposePlayerForHotSwap(
    Player player, {
    required Duration timeout,
  }) async {
    final kernelName = player.getPlayerKernelName();
    traceHotSwapStage('old teardown start kernel=$kernelName');
    try {
      await player.disposeAsync().timeout(timeout);
      traceHotSwapStage('old teardown completed kernel=$kernelName');
    } catch (error) {
      // A timeout does not cancel teardown. Leave the old player assigned so
      // retries await the same future instead of overlapping native instances.
      traceHotSwapStage('old teardown failed kernel=$kernelName $error');
      rethrow;
    }
  }

  /// Save playback state, release the old kernel, then initialize its replacement.
  static Future<void> performPlayerKernelHotSwapSteps(
    VideoPlayerState videoPlayerState, {
    required Duration playerDisposalTimeout,
  }) async {
    if (videoPlayerState.isDisposed) {
      return;
    }
    debugPrint('[PlayerKernelManager] 开始执行播放器内核热切换...');

    // 1. 保存当前播放状态
    final currentPath = videoPlayerState.currentVideoPath;
    final currentPosition = videoPlayerState.position;
    debugPrint(
        '[PlayerKernelManager] 切换捕获 position=${currentPosition.inMilliseconds}ms');
    final currentDuration = videoPlayerState.duration;
    final currentProgress = videoPlayerState.progress;
    final currentPlaybackRate = videoPlayerState.playbackRate;
    final wasPlaying = videoPlayerState.status == PlayerStatus.playing;

    // 1.1 主动写进度到 PlaybackPositionStore：initializePlayer 内部
    // _getVideoPosition 会 flush + 读同一个 store，确保切换后从精确
    // 位置恢复，不依赖周期性保存的 ~650ms 误差。
    if (currentPath != null && currentPath.isNotEmpty) {
      await videoPlayerState.persistCurrentPositionForHotSwap(
        path: currentPath,
        positionMs: currentPosition.inMilliseconds,
      );
    }

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
      await _disposePlayerForHotSwap(
        videoPlayerState.player,
        timeout: playerDisposalTimeout,
      );
      debugPrint('[PlayerKernelManager] 没有正在播放的视频，旧播放器已释放');
      // 如果没有视频在播放，只需要创建一个新的播放器实例以备后用
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

    // 2. 捕获旧播放器实例：resetPlayer 会置空状态，先持有引用以便随后强制退出。
    final previousPlayer = videoPlayerState.player;

    // 3. 停止旧播放器：resetPlayer 把内核置 stopped 空态、断开 media 与纹理，
    // 旧内核不再解码/占音频。
    await videoPlayerState.resetPlayer();
    if (videoPlayerState.isDisposed) {
      return;
    }

    // 3.1 强制退出旧内核：立即彻底销毁（stop + dispose），而不是留给 wrapper 在
    // 切换完成后延后销毁。播放中切换时若旧内核还活着，新内核随即创建并起播，
    // 新旧两个原生实例（解码线程、GL 上下文、音频输出）会在平台线程并存导致
    // 死锁卡死（实测播放中切 libmpv 冻死，而主页无视频怎么切都不闪退，正源于此）。
    // 此刻旧内核已 stopped + 媒体纹理已释放，同步 dispose 快速非阻塞。
    await _disposePlayerForHotSwap(
      previousPlayer,
      timeout: playerDisposalTimeout,
    );
    if (videoPlayerState.isDisposed) {
      return;
    }

    // 4. 创建新的播放器实例（Player()工厂会自动使用新的内核）
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
    if (videoPlayerState.isDisposed) return;

    // 5. 重新初始化播放（沿用上游流程：内部 _getVideoPosition 读
    // PlaybackPositionStore → seekAndWait(lastPosition) → play，
    // 媒体就绪后 seek 自然生效，不会丢进度）
    await videoPlayerState.initializePlayer(
      currentPath,
      historyItem: historyItem,
      resetManualDanmakuOffset: false,
      episodeFileSelectionHandled: true,
    );
    if (videoPlayerState.isDisposed) return;

    // 6. 恢复播放状态（initializePlayer 内部已 seek + play，
    // 不再外部 seekTo 避免双 seek 竞态；只处理暂停场景）
    if (videoPlayerState.hasVideo) {
      videoPlayerState.applyPlayerVolume();
      // 恢复播放速度设置
      if (currentPlaybackRate != 1.0) {
        videoPlayerState.player.setPlaybackRate(currentPlaybackRate);
        debugPrint('[PlayerKernelManager] 恢复播放速度设置: ${currentPlaybackRate}x');
      }
      if (!wasPlaying) {
        videoPlayerState.pause();
      }
      debugPrint(
          '[PlayerKernelManager] 播放器内核热切换完成，恢复状态 wasPlaying=$wasPlaying position=${videoPlayerState.position.inMilliseconds}ms 内核=${videoPlayerState.player.getPlayerKernelName()}');
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
