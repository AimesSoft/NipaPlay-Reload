part of video_player_state;

extension VideoPlayerStatePlaybackControls on VideoPlayerState {
  Future<void> _restoreSystemUiOverlayStyleIfNeeded() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return;

    final context = _context;
    final brightness = (context != null && context.mounted)
        ? Theme.of(context).brightness
        : WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final isDark = brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        // iOS 使用 statusBarBrightness 控制图标颜色，值与期望颜色相反
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  void _logMacOSHdrResetTrace(String message) {
    if (!kIsWeb &&
        Platform.isMacOS &&
        Platform.environment['NIPAPLAY_MACOS_HDR_EXIT_TRACE'] == '1') {
      debugPrint('[HDRExit][Reset] $message');
    }
  }

  // 切换菜单栏显示/隐藏状态（仅用于平板设备）
  void toggleAppBarVisibility() async {
    if (isTablet) {
      _isAppBarHidden = !_isAppBarHidden;

      // 当切换到全屏状态时，同时隐藏系统状态栏
      if (_isAppBarHidden) {
        // 进入全屏状态，隐藏系统UI
        try {
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
        } catch (e) {
          debugPrint('隐藏系统UI时出错: $e');
        }
      } else {
        // 退出全屏状态，显示系统UI
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        } catch (e) {
          debugPrint('显示系统UI时出错: $e');
        }
      }
      await _restoreSystemUiOverlayStyleIfNeeded();

      _notifyListeners();
    }
  }

  Future<void> resetPlayer() async {
    try {
      _isResetting = true; // 设置重置标志
      _logMacOSHdrResetTrace(
        'resetPlayer start path=$_currentVideoPath status=$_status hasVideo=$hasVideo playerState=${player.state}',
      );

      // 立即重置屏幕方向，不受后续等待阻塞，避免用户被卡在横屏状态
      if (globals.isMobilePlatform) {
        await ScreenOrientationManager.instance.resetOrientation();
        await _restoreSystemUiOverlayStyleIfNeeded();
      }

      // 等待退出截图完成后再保存观看记录和停止播放器
      // 截图依赖 player.snapshot()，播放器停止后截图会失败
      // 须先等截图完成，_currentThumbnailPath 才是最新值，_updateWatchHistory 才能写入正确缩略图
      if (_isCapturingFrame) {
        _logMacOSHdrResetTrace('waiting for exit screenshot to complete');
        try {
          await Future.any([
            _waitForScreenshotComplete(),
            Future.delayed(const Duration(seconds: 4)),
          ]);
          _logMacOSHdrResetTrace(
            'exit screenshot wait done, isCapturing=$_isCapturingFrame',
          );
        } catch (e) {
          debugPrint('等待截图完成异常: $e');
        } finally {
          // 超时后强制重置截图状态，避免影响后续操作
          if (_isCapturingFrame) {
            _isCapturingFrame = false;
            _screenshotCompleter = null;
            _logMacOSHdrResetTrace('force reset screenshot state after timeout');
          }
        }
      }

      // 恢复播放器音量（handleBackButton 中可能静音了播放器）
      // 移动端使用系统音量，player.volume 不需要改，但标志位需要重置
      if (_mutedForExit) {
        if (!_useSystemVolume) {
          player.volume = _currentVolume;
          _logMacOSHdrResetTrace('restored player volume to $_currentVolume');
        }
        _mutedForExit = false;
      }

      // 在停止播放前保存最后的观看记录
      // 截图已完成，_currentThumbnailPath 是最新值，不会被旧缩略图覆盖
      if (_currentVideoPath != null) {
        await _updateWatchHistory(forceRemoteSync: true);
      }

      // Jellyfin同步：如果是Jellyfin流媒体，停止同步
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('jellyfin://')) {
        try {
          final itemId = _currentVideoPath!.replaceFirst('jellyfin://', '');
          final syncService = JellyfinPlaybackSyncService();
          final historyItem = await WatchHistoryManager.getHistoryItem(
            _currentVideoPath!,
          );
          if (historyItem != null) {
            await syncService.reportPlaybackStopped(
              itemId,
              historyItem,
              isCompleted: false,
            );
          }
        } catch (e) {
          debugPrint('Jellyfin播放停止同步失败: $e');
        }
      }

      // Emby同步：如果是Emby流媒体，停止同步
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('emby://')) {
        try {
          final itemId = _currentVideoPath!.replaceFirst('emby://', '');
          final syncService = EmbyPlaybackSyncService();
          final historyItem = await WatchHistoryManager.getHistoryItem(
            _currentVideoPath!,
          );
          if (historyItem != null) {
            await syncService.reportPlaybackStopped(
              itemId,
              historyItem,
              isCompleted: false,
            );
          }
        } catch (e) {
          debugPrint('Emby播放停止同步失败: $e');
        }
      }

      // 重置解码器信息
      SystemResourceMonitor().setActiveDecoder("未知");

      // 先停止UI更新Ticker，防止错误检测在重置过程中运行
      if (_uiUpdateTicker != null) {
        _uiUpdateTicker!.stop();
        _uiUpdateTicker!.dispose();
        _uiUpdateTicker = null;
      }

      // 清除字幕设置（同时更新SubtitleManager状态）
      _subtitleManager.clearExternalSubtitle();

      // 先停止播放
      if (player.state != PlaybackState.stopped) {
        _logMacOSHdrResetTrace('set player.state=stopped');
        player.state = PlaybackState.stopped;
      }

      // 释放纹理，确保资源被正确释放
      if (player.textureId.value != null) {
        // Keep the null check for reading
        _disposeTextureResources();
        // player.textureId.value = null; // COMMENTED OUT
      }

      // 重置状态
      await _clearTimelinePreviewFiles();
      _currentVideoPath = null;
      _macOSWindowHostedVideoRect = null;
      _danmakuOverlayKey = 'idle'; // 重置弹幕覆盖层key
      _position = Duration.zero;
      _duration = Duration.zero;
      _progress = 0.0;
      _bufferedPositionMs = 0;
      _error = null;
      _animeTitle = null; // 清除动画标题
      _episodeTitle = null; // 清除集数标题
      _danmakuList = []; // 清除弹幕列表
      _danmakuListVersion++;
      _danmakuTracks.clear();
      _danmakuTrackEnabled.clear();
      _isSpoilerDanmakuAnalyzing = false;
      _spoilerDanmakuAnalysisHash = null;
      _spoilerDanmakuRunningAnalysisHash = null;
      _spoilerDanmakuTexts = <String>{};
      _spoilerDanmakuAnalysisDebounceTimer?.cancel();
      _spoilerDanmakuAnalysisDebounceTimer = null;
      _spoilerDanmakuPendingAnalysisHash = null;
      _spoilerDanmakuPendingRequestConfig = null;
      _spoilerDanmakuPendingTexts = null;
      _spoilerDanmakuPendingTargetVideoPath = null;
      _subtitleManager.clearSubtitleTrackInfo();
      _resetTimelinePreviewState();
      _isAppBarHidden = false; // 重置平板设备菜单栏隐藏状态

      // 重置系统UI显示状态
      if (globals.isTabletLikeMobile) {
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        } catch (e) {
          debugPrint('重置系统UI时出错: $e');
        }
        await _restoreSystemUiOverlayStyleIfNeeded();
      }

      _setStatus(PlayerStatus.idle);
      _logMacOSHdrResetTrace(
        'status set idle path=$_currentVideoPath status=$_status playerState=${player.state}',
      );

      // 关闭唤醒锁
      try {
        WakelockPlus.disable();
      } catch (e) {
        //debugPrint("Error disabling wakelock: $e");
      }

      _notifyListeners();
      _logMacOSHdrResetTrace(
        'resetPlayer notifyListeners path=$_currentVideoPath status=$_status hasVideo=$hasVideo playerState=${player.state}',
      );
    } catch (e) {
      _logMacOSHdrResetTrace('resetPlayer error error=$e');
      //debugPrint('重置播放器时出错: $e');
      rethrow;
    } finally {
      _isResetting = false; // 清除重置标志
      _logMacOSHdrResetTrace(
        'resetPlayer finally path=$_currentVideoPath status=$_status hasVideo=$hasVideo playerState=${player.state}',
      );
    }
  }

  // 帮助释放纹理资源
  void _disposeTextureResources() {
    try {
      // 清空可能的缓冲内容
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }

      // 设置空媒体源，释放当前媒体相关资源
      player.media = '';

      if (!kIsWeb) {
        // 通知垃圾回收
        if (Platform.isIOS || Platform.isMacOS) {
          Future.delayed(const Duration(milliseconds: 50), () {
            // 在iOS/macOS上可能需要额外步骤来释放资源
            player.media = '';
          });
        }
      }
    } catch (e) {
      //debugPrint('释放纹理资源时出错: $e');
    }
  }

  void _setStatus(
    PlayerStatus newStatus, {
    String? message,
    bool clearPreviousMessages = false,
    bool resetState = false,
  }) {
    if (newStatus == PlayerStatus.idle || resetState) {
      _resetVideoState();
    }
    // 在状态即将从loading或recognizing变为ready或playing时，设置最终加载阶段标志
    if ((_status == PlayerStatus.loading ||
            _status == PlayerStatus.recognizing) &&
        (newStatus == PlayerStatus.ready ||
            newStatus == PlayerStatus.playing)) {
      _isInFinalLoadingPhase = true;

      // 延迟通知UI刷新，给足够时间处理状态变更
      Future.microtask(() {
        _notifyListeners();
      });
    }

    if (clearPreviousMessages) {
      _statusMessages.clear();
    }
    if (message != null && message.isNotEmpty) {
      _statusMessages.add(message);
      // Optionally, limit the number of messages stored
      // if (_statusMessages.length > 10) {
      //   _statusMessages.removeAt(0);
      // }
    }

    _status = newStatus;

    // Wakelock logic
    if (_status == PlayerStatus.playing) {
      try {
        WakelockPlus.enable();
        ////debugPrint("Wakelock enabled: Playback started/resumed.");
      } catch (e) {
        ////debugPrint("Error enabling wakelock: $e");
      }

      if (_needsAnime4KSurfaceScaleRefresh) {
        _needsAnime4KSurfaceScaleRefresh = false;
        _scheduleAnime4KSurfaceScaleRefresh();
      }

      // 在播放开始后一小段时间重置最终加载阶段标志
      Future.delayed(const Duration(milliseconds: 200), () {
        _isInFinalLoadingPhase = false;
        _notifyListeners();
      });
    } else {
      // Disable for any other status (paused, error, idle, disposed, ready, loading, recognizing)
      try {
        WakelockPlus.disable();
        ////debugPrint("Wakelock disabled. Status: $_status");
      } catch (e) {
        ////debugPrint("Error disabling wakelock: $e");
      }
    }

    if (newStatus == PlayerStatus.ready || newStatus == PlayerStatus.playing) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _logCurrentVideoDimensions(context: 'status ${newStatus.name}');
      });
    }

    _notifyListeners();
  }

  void togglePlayPause() {
    if (_status == PlayerStatus.playing) {
      pause();
    } else {
      play();
    }
  }

  // 取消自动播放下一话
  void cancelAutoNextEpisode() {
    AutoNextEpisodeService.instance.cancelAutoNext();
  }

  Future<void> _handlePlaybackEndAction() async {
    if (_currentVideoPath == null) {
      return;
    }

    switch (_playbackEndAction) {
      case PlaybackEndAction.autoNext:
        if (_context != null && _context!.mounted) {
          AutoNextEpisodeService.instance.startAutoNextEpisode(
            _context!,
            _currentVideoPath!,
          );
        }
        break;
      case PlaybackEndAction.loop:
        AutoNextEpisodeService.instance.cancelAutoNext();
        await _restartPlaybackFromBeginning();
        break;
      case PlaybackEndAction.pause:
        AutoNextEpisodeService.instance.cancelAutoNext();
        break;
      case PlaybackEndAction.exitPlayer:
        AutoNextEpisodeService.instance.cancelAutoNext();
        if (_context != null && _context!.mounted) {
          final currentContext = _context!;
          Future.microtask(() {
            if (_context != null &&
                _context!.mounted &&
                identical(currentContext, _context)) {
              Navigator.of(currentContext).maybePop();
            }
          });
        }
        break;
    }
  }

  Future<void> _restartPlaybackFromBeginning() async {
    if (!hasVideo) {
      return;
    }
    try {
      _isSeeking = true;
      _position = Duration.zero;
      _progress = 0.0;
      _bufferedPositionMs = 0;
      _playbackTimeMs.value = 0;
      _lastRawPlayerMs = -1; // 重置平滑时钟，下次 Ticker 重新对齐
      // ✅ P2-LOOP-RESTART 修复：补齐 seekTo() 中正确设置的三个锚点字段
      // 根因：缺少 _smoothAnchorMs/_smoothAnchorElapsedUs/_seekTargetMs 设置
      // → Ticker callback 下一帧从旧 player.position 重新锚定
      // → playbackTimeMs 被覆盖回末尾 → 弹幕/视频跳回 → 鬼畜
      // 参照：seekTo() (line 670-674) 正确设置了这三个字段
      _smoothAnchorMs = 0.0;
      _smoothAnchorElapsedUs = _lastElapsedUs;
      _seekTargetMs = 0.0; // 启用 seek 保护，而非清除
      _anchorSetBySeek = true; // 标记锚点由 seek/loop 设置
      // [LOOP-RESTART-DIAG] 诊断：记录重置后的锚点状态
      if (!kReleaseMode) {
        debugPrint('[LOOP-RESTART-DIAG] AFTER RESET: '
            'smoothAnchorMs=${_smoothAnchorMs.toStringAsFixed(1)} '
            'smoothAnchorElapsedUs=$_smoothAnchorElapsedUs '
            'lastElapsedUs=$_lastElapsedUs '
            'seekTargetMs=$_seekTargetMs '
            'lastRawPlayerMs=$_lastRawPlayerMs');
      }
      _notifyListeners();
      player.seek(position: 0);
      if (_status != PlayerStatus.playing) {
        play();
      }
    } catch (e) {
      debugPrint('[循环播放] 重新开始失败: ' + e.toString());
    } finally {
      _isSeeking = false;
    }
  }

  void pause() {
    if (_status == PlayerStatus.playing) {
      final bool isWindowsMediaKit = !kIsWeb &&
          Platform.isWindows &&
          player.getPlayerKernelName() == 'Media Kit';
      if (isWindowsMediaKit) {
        try {
          // Hint mpv to pause immediately on Windows to reduce control latency.
          player.setProperty('pause', 'yes');
        } catch (_) {}
      }

      // 使用直接暂停方法，确保VideoPlayer插件能够暂停视频
      player.pauseDirectly().then((_) {
        //debugPrint('[VideoPlayerState] pauseDirectly() 调用成功');
        _setStatus(PlayerStatus.paused, message: '已暂停');
      }).catchError((e) {
        debugPrint('[VideoPlayerState] pauseDirectly() 调用失败: $e');
        // 尝试使用传统方法
        player.state = PlaybackState.paused;
        _setStatus(PlayerStatus.paused, message: '已暂停');
      });

      // Jellyfin同步：如果是Jellyfin流媒体，报告暂停状态
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('jellyfin://')) {
        try {
          final syncService = JellyfinPlaybackSyncService();
          syncService.reportPlaybackPaused(_position.inMilliseconds);
        } catch (e) {
          debugPrint('Jellyfin暂停状态报告失败: $e');
        }
      }

      // Emby同步：如果是Emby流媒体，报告暂停状态
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('emby://')) {
        try {
          final syncService = EmbyPlaybackSyncService();
          syncService.reportPlaybackPaused(_position.inMilliseconds);
        } catch (e) {
          debugPrint('Emby暂停状态报告失败: $e');
        }
      }

      _saveCurrentPositionToHistory();
      // 在暂停时触发截图（Windows+MediaKit 延迟，避免与 mpv 暂停竞争）
      if (isWindowsMediaKit) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (_status == PlayerStatus.paused) {
            _captureConditionalScreenshot("暂停时");
          }
        });
      } else {
        _captureConditionalScreenshot("暂停时");
      }
      // 保存暂停时的 playbackTimeMs，用于恢复时平滑衔接
      _pausedPlaybackTimeMs = _playbackTimeMs.value;
      // 停止UI更新Ticker，避免继续产帧
      _uiUpdateTicker?.stop();
      // WakelockPlus.disable(); // Already handled by _setStatus
    }
  }

  void play() {
    // <<< ADDED DEBUG LOG >>>
    debugPrint(
      '[VideoPlayerState] play() called. hasVideo: $hasVideo, _status: $_status, currentMedia: ${player.media}',
    );
    final bool isWindowsMediaKit = !kIsWeb &&
        Platform.isWindows &&
        player.getPlayerKernelName() == 'Media Kit';
    if (isWindowsMediaKit) {
      try {
        // Ensure mpv is unpaused immediately on Windows.
        player.setProperty('pause', 'no');
      } catch (_) {}
    }
    _ensurePlayerVolumeMatchesPlatformPolicy();
    // 兜底恢复：若 handleBackButton 静音后未经 resetPlayer 进入新一轮播放（如错误弹窗流程）
    if (_mutedForExit) {
      if (!_useSystemVolume) {
        player.volume = _currentVolume;
      }
      _mutedForExit = false;
    }
    if (hasVideo &&
        (_status == PlayerStatus.paused || _status == PlayerStatus.ready)) {
      _lastPlaybackStartMs = DateTime.now().millisecondsSinceEpoch;
      // 使用直接播放方法，确保VideoPlayer插件能够播放视频
      player.playDirectly().then((_) {
        //debugPrint('[VideoPlayerState] playDirectly() 调用成功');
        // 设置状态
        _setStatus(PlayerStatus.playing, message: '开始播放');

        // 播放开始时提交观看记录到弹弹play
        _submitWatchHistoryToDandanplay();
      }).catchError((e) {
        debugPrint('[VideoPlayerState] playDirectly() 调用失败: $e');
        // 尝试使用传统方法
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing, message: '开始播放');

        // 播放开始时提交观看记录到弹弹play
        _submitWatchHistoryToDandanplay();
      });

      // <<< ADDED DEBUG LOG >>>
      debugPrint(
        '[VideoPlayerState] play() -> _status set to PlayerStatus.playing. Notifying listeners.',
      );

      // 在首次播放时进行截图
      if (!_hasInitialScreenshot) {
        _hasInitialScreenshot = true;
        // 延迟一秒再截图，确保视频已经开始显示
        Future.delayed(const Duration(seconds: 1), () {
          _captureConditionalScreenshot("首次播放时");
        });
      }
      // 视频开始播放后更新解码器信息
      Future.delayed(const Duration(seconds: 1), () {
        _updateCurrentActiveDecoder();
      });
      // _resetHideControlsTimer(); // Temporarily commented out as the method name is uncertain.
      // Please provide the correct method if you want to show controls on play.

      // 确保UI更新Ticker在播放时启动
      if (_uiUpdateTicker == null) {
        _startUiUpdateTimer();
      }
      if (!(_uiUpdateTicker?.isActive ?? false)) {
        // ✅ P2 修复：恢复播放时重设锚点，避免 Ticker elapsed 重置导致 elapsedDeltaUs 负值
        // Flutter Ticker stop()+start() 后 elapsed 从 0 重新开始，
        // 但 _smoothAnchorElapsedUs 保留暂停前的值（如 5,000,000μs），
        // 导致恢复首帧 elapsedDeltaUs = 16,667 - 5,000,000 = 负数 → smoothMs 大幅落后
        //
        // ✅ P3 修复：使用暂停时保存的 playbackTimeMs 作为锚点，
        // 而不是让首帧走"重锚到 player.position"路径。
        // mpv 恢复后 player.position 可能回退（比暂停前小几十ms），
        // 直接锚定到 playerMs 会导致弹幕跳变到错误时间点。
        // 使用暂停时的精确值确保弹幕从暂停位置无缝继续。
        if (_pausedPlaybackTimeMs != null) {
          _smoothAnchorMs = _pausedPlaybackTimeMs!;
          _smoothAnchorElapsedUs = 0; // Ticker 重启后 elapsed 从 0 开始
          _lastRawPlayerMs = -1; // 保持 -1，让漂移修正自然校准
          _pausedPlaybackTimeMs = null;
        } else {
          _lastRawPlayerMs = -1;
        }
        _lastElapsedUs = 0; // Ticker elapsed 重置后基线也要重置
        _uiUpdateTicker!.start();
      }
    }
  }

  Future<void> stop() async {
    if (_status != PlayerStatus.idle && _status != PlayerStatus.disposed) {
      _setStatus(PlayerStatus.idle, message: '播放已停止');

      // 停止UI更新定时器和Ticker
      _uiUpdateTimer?.cancel();
      if (_uiUpdateTicker != null) {
        _uiUpdateTicker!.stop();
      }

      player.state = PlaybackState.stopped; // Changed from player.stop()
      _resetVideoState();
    }
  }

  void _clearPreviousVideoState() {
    _subtitleManager.clearExternalSubtitle(notifyListenersToo: false);
    _currentVideoPath = null;
    _currentActualPlayUrl = null; // 清除实际播放URL
    _currentPlaybackSession = null;
    _lastPlaybackStartMs = 0;
    _danmakuOverlayKey = 'idle'; // 重置弹幕覆盖层key
    _currentVideoHash = null;
    _currentThumbnailPath = null;
    _animeTitle = null;
    _episodeTitle = null;
    _episodeId = null; // 清除弹幕ID
    _animeId = null; // 清除弹幕ID
    _initialHistoryItem = null;
    _danmakuList.clear();
    _danmakuListVersion++;
    _danmakuTracks.clear();
    _danmakuTrackEnabled.clear();
    _isSpoilerDanmakuAnalyzing = false;
    _spoilerDanmakuAnalysisHash = null;
    _spoilerDanmakuRunningAnalysisHash = null;
    _spoilerDanmakuTexts = <String>{};
    _spoilerDanmakuAnalysisDebounceTimer?.cancel();
    _spoilerDanmakuAnalysisDebounceTimer = null;
    _spoilerDanmakuPendingAnalysisHash = null;
    _spoilerDanmakuPendingRequestConfig = null;
    _spoilerDanmakuPendingTexts = null;
    _spoilerDanmakuPendingTargetVideoPath = null;
    _subtitleManager.clearSubtitleTrackInfo();
    danmakuController
        ?.dispose(); // Assuming danmakuController has a dispose method
    danmakuController = null;
    _setAutoDanmakuOffset(0.0);
    _duration = Duration.zero;
    _position = Duration.zero;
    _progress = 0.0;
    _bufferedPositionMs = 0;
    _needsAnime4KSurfaceScaleRefresh = false;
    _anime4kSurfaceScaleRequestId++;
    _error = null;
    _isAppBarHidden = false; // 重置平板设备菜单栏隐藏状态
    // Do NOT call WakelockPlus.disable() here directly, _setStatus will handle it
  }

  void _saveCurrentPositionToHistory() {
    if (_currentVideoPath != null) {
      _saveVideoPosition(_currentVideoPath!, _position.inMilliseconds);
    }
  }

  void _resetVideoState() {
    if (!kReleaseMode) {
      debugPrint('[LOOP-RESTART-DIAG] _resetVideoState() CALLED: '
          '_status=$_status _seekTargetMs=$_seekTargetMs '
          '_currentVideoPath=$_currentVideoPath');
    }
    _subtitleManager.clearExternalSubtitle(notifyListenersToo: false);
    _position = Duration.zero;
    _progress = 0.0;
    _duration = Duration.zero;
    _bufferedPositionMs = 0;
      _playbackTimeMs.value = 0;
      _lastRawPlayerMs = -1; // 重置平滑时钟
      // ✅ P2-LOOP-RESTART 一致性修复：补齐锚点字段（与 seekTo() 保持一致）
      _smoothAnchorMs = 0.0;
      _smoothAnchorElapsedUs = 0;
      _seekTargetMs = null; // [SEEK-TRACE] source=RESET-VIDEO-STATE — idle/stop 场景无需 seek 保护
      _anchorSetBySeek = false; // idle/stop 场景锚点非 seek 设置
      _lastPlaybackStartMs = 0;
    if (!_isErrorStopping) {
      // <<< MODIFIED HERE
      _error = null;
    }
    _currentVideoPath = null;
    _currentActualPlayUrl = null;
    _currentPlaybackSession = null;
    _danmakuOverlayKey = 'idle'; // 重置弹幕覆盖层key
    _currentVideoHash = null;
    _currentThumbnailPath = null;
    _needsAnime4KSurfaceScaleRefresh = false;
    _anime4kSurfaceScaleRequestId++;
    _animeTitle = null;
    _episodeTitle = null;
    _episodeId = null; // 清除弹幕ID
    _animeId = null; // 清除弹幕ID
    _initialHistoryItem = null;
    _danmakuList.clear();
    _danmakuListVersion++;
    _danmakuTracks.clear();
    _danmakuTrackEnabled.clear();
    _isSpoilerDanmakuAnalyzing = false;
    _spoilerDanmakuAnalysisHash = null;
    _spoilerDanmakuRunningAnalysisHash = null;
    _spoilerDanmakuTexts = <String>{};
    _spoilerDanmakuAnalysisDebounceTimer?.cancel();
    _spoilerDanmakuAnalysisDebounceTimer = null;
    _spoilerDanmakuPendingAnalysisHash = null;
    _spoilerDanmakuPendingRequestConfig = null;
    _spoilerDanmakuPendingTexts = null;
    _spoilerDanmakuPendingTargetVideoPath = null;
    _subtitleManager.clearSubtitleTrackInfo();
    danmakuController
        ?.dispose(); // Assuming danmakuController has a dispose method
    danmakuController = null;
    _setAutoDanmakuOffset(0.0);
    _videoDuration = Duration.zero;
    _seekStepFrameRateEstimate = null;
  }

  void seekBackwardByStep() {
    seekTo(position - seekStepDuration);
  }

  void seekForwardByStep() {
    seekTo(position + seekStepDuration);
  }

  void seekTo(Duration position) {
    // 仅在自动连播倒计时期间，用户seek才取消自动连播
    try {
      if (AutoNextEpisodeService.instance.isCountingDown) {
        AutoNextEpisodeService.instance.cancelAutoNext();
        debugPrint('[自动连播] 用户seek时取消自动连播倒计时');
      }
    } catch (e) {
      debugPrint('[自动连播] seekTo时取消自动播放失败: $e');
    }
    if (!hasVideo) return;

    try {
      _isSeeking = true;
      bool wasPlayingBeforeSeek = _status == PlayerStatus.playing; // 记录当前播放状态

      // 确保位置在有效范围内（0 到视频总时长）
      Duration clampedPosition = Duration(
        milliseconds: position.inMilliseconds.clamp(
          0,
          _duration.inMilliseconds,
        ),
      );

      // 如果是暂停状态，先恢复播放
      if (_status == PlayerStatus.paused) {
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing);
      }

      // 立即更新UI状态
      _position = clampedPosition;
      // 同步高频时间轴，确保弹幕立即跳转
      _playbackTimeMs.value = _position.inMilliseconds.toDouble();
      // 锚定到 seek 目标位置，避免 player.position 延迟导致弹幕闪回
      _smoothAnchorMs = _position.inMilliseconds.toDouble();
      _smoothAnchorElapsedUs = _lastElapsedUs;
      _seekTargetMs = _position.inMilliseconds.toDouble();
      _anchorSetBySeek = true; // 标记锚点由 seek 设置
      if (_duration.inMilliseconds > 0) {
        _progress = clampedPosition.inMilliseconds / _duration.inMilliseconds;
      }
      _notifyListeners();

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
      //debugPrint('跳转时出错 (已静默处理): $e');
      _error = '跳转时出错: $e';
      _setStatus(PlayerStatus.idle);
      _isSeeking = false;
    }
  }

  void resetAutoHideTimer() {
    if (_controlsVisibilityLocked) {
      return;
    }
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
    if (_controlsVisibilityLocked && !value) {
      return;
    }
    _isControlsHovered = value || _controlsVisibilityLocked;
    if (value) {
      _hideControlsTimer?.cancel();
      _hideMouseTimer?.cancel();
      _autoHideTimer?.cancel();
      setShowControls(true);
    } else {
      if (_instantHidePlayerUiEnabled && !globals.isMobilePlatform) {
        _hideControlsTimer?.cancel();
        _hideMouseTimer?.cancel();
        _autoHideTimer?.cancel();
        setShowControls(false);
        return;
      }
      resetHideControlsTimer();
      resetAutoHideTimer();
    }
  }

  void resetHideMouseTimer() {
    if (_controlsVisibilityLocked) {
      return;
    }
    _hideMouseTimer?.cancel();
    if (hasVideo && !_isControlsHovered && !globals.isMobilePlatform) {
      _hideMouseTimer = Timer(const Duration(milliseconds: 1500), () {
        setShowControls(false);
      });
    }
  }

  void resetHideControlsTimer() {
    if (_controlsVisibilityLocked) {
      return;
    }
    _hideControlsTimer?.cancel();
    setShowControls(true);
    if (hasVideo && !_isControlsHovered && !globals.isMobilePlatform) {
      _hideControlsTimer = Timer(const Duration(milliseconds: 1500), () {
        setShowControls(false);
      });
    }
  }

  void handleMouseMove(Offset position) {
    if (_controlsVisibilityLocked) {
      return;
    }
    if (!_isControlsHovered && !globals.isMobilePlatform) {
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
    if (_controlsVisibilityLocked && !value) {
      return;
    }
    _showControls = value;
    if (value) {
      resetAutoHideTimer();
    } else {
      _autoHideTimer?.cancel();
    }
    _notifyListeners();
  }

  void setShowRightMenu(bool value) {
    _showRightMenu = value;
    _notifyListeners();
  }

  bool get hotkeysSuppressed => _controlsVisibilityLocked;

  void setControlsVisibilityLocked(bool value) {
    if (_controlsVisibilityLocked == value) {
      return;
    }
    _controlsVisibilityLocked = value;
    if (value) {
      _hideControlsTimer?.cancel();
      _hideMouseTimer?.cancel();
      _autoHideTimer?.cancel();
      _isControlsHovered = true;
      setShowControls(true);
    } else {
      _isControlsHovered = false;
      resetHideControlsTimer();
      resetAutoHideTimer();
    }
  }

  void toggleRightMenu() {
    setShowRightMenu(!_showRightMenu);
  }

  // 右边缘悬浮菜单管理方法
  void setRightEdgeHovered(bool hovered) {
    if (_isRightEdgeHovered == hovered) return;

    _isRightEdgeHovered = hovered;
    _rightEdgeHoverTimer?.cancel();

    if (hovered) {
      // 鼠标进入右边缘，显示悬浮菜单
      _showHoverSettingsMenu();
    } else {
      // 鼠标离开右边缘，延迟隐藏菜单
      _rightEdgeHoverTimer = Timer(const Duration(milliseconds: 300), () {
        _hideHoverSettingsMenu();
      });
    }

    _notifyListeners();
  }

  void _showHoverSettingsMenu() {
    if (_hoverSettingsMenuOverlay != null || _context == null) return;

    // 导入设置菜单组件，这里需要延迟导入避免循环依赖
    Future.microtask(() {
      if (_context != null && _context!.mounted) {
        _hoverSettingsMenuOverlay = OverlayEntry(
          builder: (context) {
            return _buildHoverSettingsMenu(context);
          },
        );

        Overlay.of(_context!).insert(_hoverSettingsMenuOverlay!);
      }
    });
  }

  void _hideHoverSettingsMenu() {
    _hoverSettingsMenuOverlay?.remove();
    _hoverSettingsMenuOverlay = null;
    _isRightEdgeHovered = false;
    _notifyListeners();
  }

  Widget _buildHoverSettingsMenu(BuildContext context) {
    // 这里会在后面的组件中实现
    return const SizedBox.shrink();
  }

  // 已移除 _startPositionUpdateTimer，功能已合并到 _startUiUpdateTimer

  bool shouldShowAppBar() {
    if (globals.isMobilePlatform) {
      if (isTablet) {
        // 平板设备：根据 _isAppBarHidden 状态决定是否显示菜单栏
        return !hasVideo || !_isAppBarHidden;
      } else {
        // 手机设备：按原有逻辑
        return !hasVideo || !_isFullscreen;
      }
    }
    return !_isFullscreen;
  }

  // 切换全屏状态（仅用于桌面平台）
  Future<void> toggleFullscreen() async {
    if (kIsWeb) return;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    if (_isFullscreenTransitioning) return;

    _isFullscreenTransitioning = true;
    try {
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

      _notifyListeners();
    } finally {
      _isFullscreenTransitioning = false;
    }
  }

  // 设置上下文
  void setContext(BuildContext context) {
    _context = context;
    _attachPluginDanmakuFilter();
    PluginService.setBuildContext(context);
    _subtitleManager.onUserNotification = (message) {
      final currentContext = _context;
      if (currentContext == null || !currentContext.mounted) {
        debugPrint('SubtitleManager提示被忽略（无可用上下文）: $message');
        return;
      }
      BlurSnackBar.show(currentContext, message);
    };
  }

  // 更新状态消息的方法
  void _updateStatusMessages(List<String> messages) {
    _statusMessages = messages;
    _notifyListeners();
  }

  // 添加单个状态消息的方法
  void _addStatusMessage(String message) {
    _statusMessages.add(message);
    _notifyListeners();
  }

  // 清除所有状态消息的方法
  void _clearStatusMessages() {
    _statusMessages.clear();
    _notifyListeners();
  }

  // Volume Drag Methods
  void startVolumeDrag() {
    if (!globals.isMobilePlatform) return;
    _initialDragVolume = _currentVolume;
    _showVolumeIndicator(); // We'll define this next
    debugPrint("Volume drag started. Initial drag volume: $_initialDragVolume");
  }

  Future<void> updateVolumeOnDrag(
    double verticalDragDelta,
    BuildContext context,
  ) async {
    if (!globals.isMobilePlatform) return;

    final screenHeight = MediaQuery.of(context).size.height;
    // 拖动约 60% 屏幕高度对应 0~100% 音量变化，便于慢速微调。
    final sensitivityFactor = screenHeight * 0.6;

    final double change = -verticalDragDelta / sensitivityFactor;
    double newVolume = _initialDragVolume + change;
    newVolume = newVolume.clamp(0.0, 1.0);

    // 先更新前端状态，避免系统音量设置慢导致手势“粘滞/阻尼”。
    _currentVolume = newVolume;
    _initialDragVolume = newVolume;
    _showVolumeIndicator();
    _scheduleVolumePersistence();
    _notifyListeners();

    try {
      if (_useSystemVolume) {
        _ensurePlayerVolumeMatchesPlatformPolicy();
        _queueSystemVolumeUpdate(newVolume);
      } else {
        // Web 等不支持系统音量时：使用播放器内部音量
        player.volume = newVolume;
      }
    } catch (e) {
      //debugPrint("Failed to set system volume via player: $e");
    }
  }

  void endVolumeDrag() {
    if (!globals.isMobilePlatform) return;
    debugPrint("Volume drag ended. Current volume: $_currentVolume");
    _scheduleVolumePersistence(immediate: true);
  }

  static const int _textureIdCounter = 0;
  static const double _volumeStep = 0.05; // 5% volume change per key press

  void increaseVolume({double? step}) {
    try {
      final double baseStep = step ?? _volumeStep;
      // 使用整数百分比运算避免浮点精度问题（100%→95%→90% 而非 100%→94.9%→89.9%）
      final int currentPercent = (_currentVolume * 100).round();
      final int stepPercent = (baseStep * 100).round();
      final int newPercent = (currentPercent + stepPercent).clamp(0, 100);
      final double newVolume = newPercent / 100.0;

      _currentVolume = newVolume;
      _initialDragVolume = newVolume;
      _showVolumeIndicator();
      _scheduleVolumePersistence(immediate: true);
      _notifyListeners();

      if (_useSystemVolume) {
        _ensurePlayerVolumeMatchesPlatformPolicy();
        _queueSystemVolumeUpdate(newVolume);
      } else {
        player.volume = newVolume;
      }

      if (globals.isDesktop) {
        // 桌面端允许尽快同步系统音量，保持与既有行为一致。
        unawaited(_setSystemVolume(newVolume));
      }

      //debugPrint("Volume increased to: $_currentVolume via keyboard");
    } catch (e) {
      //debugPrint("Failed to increase volume via keyboard: $e");
    }
  }

  void decreaseVolume({double? step}) {
    try {
      final double baseStep = step ?? _volumeStep;
      // 使用整数百分比运算避免浮点精度问题（100%→95%→90% 而非 100%→94.9%→89.9%）
      final int currentPercent = (_currentVolume * 100).round();
      final int stepPercent = (baseStep * 100).round();
      final int newPercent = (currentPercent - stepPercent).clamp(0, 100);
      final double newVolume = newPercent / 100.0;

      _currentVolume = newVolume;
      _initialDragVolume = newVolume;
      _showVolumeIndicator();
      _scheduleVolumePersistence(immediate: true);
      _notifyListeners();

      if (_useSystemVolume) {
        _ensurePlayerVolumeMatchesPlatformPolicy();
        _queueSystemVolumeUpdate(newVolume);
      } else {
        player.volume = newVolume;
      }

      if (globals.isDesktop) {
        // 桌面端允许尽快同步系统音量，保持与既有行为一致。
        unawaited(_setSystemVolume(newVolume));
      }

      //debugPrint("Volume decreased to: $_currentVolume via keyboard");
    } catch (e) {
      //debugPrint("Failed to decrease volume via keyboard: $e");
    }
  }

  // Seek Drag Methods
  void startSeekDrag(BuildContext context) {
    if (!globals.isMobilePlatform) return; // Add platform check
    if (!hasVideo) return;
    _isSeekingViaDrag = true;
    _dragSeekStartPosition = _position;
    _accumulatedDragDx = 0.0;
    _dragSeekTargetPosition = _position;
    _showSeekIndicator(); // <<< CALL ADDED
    //debugPrint("Seek drag started. Start position: $_dragSeekStartPosition");
    _notifyListeners();
  }

  void updateSeekDrag(double deltaDx, BuildContext context) {
    if (!globals.isMobilePlatform) return; // Add platform check
    if (!hasVideo || !_isSeekingViaDrag) return;

    _accumulatedDragDx += deltaDx;
    final screenWidth = MediaQuery.of(context).size.width;

    // Sensitivity: 滑动整个屏幕宽度对应总时长的N分之一，例如1/3或者一个固定时长如60秒
    // 修改灵敏度：1像素约等于6秒，这样轻滑动大约10-15像素就是10秒左右
    const double pixelsPerSecond = 6.0; // 增大数值以减少灵敏度(原来是1.0)
    double seekOffsetSeconds = _accumulatedDragDx / pixelsPerSecond;

    Duration newPositionDuration =
        _dragSeekStartPosition + Duration(seconds: seekOffsetSeconds.round());

    // Clamp newPosition between Duration.zero and video duration
    int newPositionMillis = newPositionDuration.inMilliseconds;
    if (_duration > Duration.zero) {
      newPositionMillis = newPositionMillis.clamp(0, _duration.inMilliseconds);
    }
    _dragSeekTargetPosition = Duration(milliseconds: newPositionMillis);

    // TODO: Update seek indicator UI with _dragSeekTargetPosition
    // For now, just print.
    // //debugPrint("Seek drag update. Target: $_dragSeekTargetPosition, DeltaDx: $deltaDx, AccumulatedDx: $_accumulatedDragDx");
    _notifyListeners(); // To update UI displaying _dragSeekTargetPosition
  }

  void endSeekDrag() {
    if (!globals.isMobilePlatform) return; // Add platform check
    if (!hasVideo || !_isSeekingViaDrag) return;

    seekTo(_dragSeekTargetPosition);
    _isSeekingViaDrag = false;
    _accumulatedDragDx = 0.0;
    _hideSeekIndicator(); // <<< CALL ADDED
    //debugPrint("Seek drag ended. Seeking to: $_dragSeekTargetPosition");
    _notifyListeners();
  }

  // Seek Indicator Overlay Methods
  void _showSeekIndicator() {
    if (!globals.isMobilePlatform || _context == null) return;

    final uiThemeProvider = Provider.of<UIThemeProvider>(
      _context!,
      listen: false,
    );
    final bool useCupertinoStyle =
        uiThemeProvider.isCupertinoTheme && globals.isPhone;

    _isSeekIndicatorVisible = true;

    if (_seekOverlayEntry == null) {
      _seekOverlayEntry = OverlayEntry(
        builder: (context) {
          final seekWidget = useCupertinoStyle
              ? const CupertinoSeekIndicator()
              : const SeekIndicator();
          Widget overlayChild = ChangeNotifierProvider<VideoPlayerState>.value(
            value: this,
            child: seekWidget,
          );
          if (useCupertinoStyle) {
            overlayChild = ChangeNotifierProvider<UIThemeProvider>.value(
              value: uiThemeProvider,
              child: overlayChild,
            );
          }
          return overlayChild;
        },
      );
      Overlay.of(_context!).insert(_seekOverlayEntry!);
    }
    _notifyListeners(); // To trigger opacity animation in SeekIndicator

    // Optional: Timer to auto-hide if drag ends abruptly or no more updates
    _seekIndicatorTimer?.cancel();
    // _seekIndicatorTimer = Timer(const Duration(seconds: 2), () {
    //   _hideSeekIndicator();
    // });
  }

  void _hideSeekIndicator() {
    if (!globals.isMobilePlatform) return;
    _seekIndicatorTimer?.cancel();

    if (_isSeekIndicatorVisible) {
      _isSeekIndicatorVisible = false;
      _notifyListeners(); // Trigger fade-out animation

      // Wait for fade-out animation to complete before removing
      Future.delayed(const Duration(milliseconds: 200), () {
        // Match SeekIndicator fade duration
        if (_seekOverlayEntry != null) {
          _seekOverlayEntry!.remove();
          _seekOverlayEntry = null;
        }
      });
    } else {
      // Ensure entry is removed if it somehow exists while not visible
      if (_seekOverlayEntry != null) {
        _seekOverlayEntry!.remove();
        _seekOverlayEntry = null;
      }
    }
  }

  // ── 逐帧跳转 ──

  /// 逐帧前进：暂停后前进一帧
  void stepForward() {
    if (!hasVideo) return;
    // 先暂停
    if (_status == PlayerStatus.playing) {
      togglePlayPause();
    }
    player.stepForward();
  }

  /// 逐帧后退：暂停后后退一帧
  void stepBackward() {
    if (!hasVideo) return;
    // 先暂停
    if (_status == PlayerStatus.playing) {
      togglePlayPause();
    }
    player.stepBackward();
  }

  // ── 窗口适配视频分辨率 ──

  /// 将桌面窗口大小调整为视频原始分辨率（窗口 >= 视频大小，视频不拉伸）
  Future<void> resizeWindowToVideoSize() async {
    if (!globals.isDesktop || !hasVideo) return;
    try {
      final info = player.mediaInfo;
      final videoStreams = info.video;
      if (videoStreams == null || videoStreams.isEmpty) return;
      final videoWidth = videoStreams.first.codec.width;
      final videoHeight = videoStreams.first.codec.height;
      if (videoWidth <= 0 || videoHeight <= 0) return;

      final windowManager = WindowManager.instance;

      // 如果窗口处于全屏或最大化状态，先退出才能设置大小
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // 解除之前的宽高比锁定，以便自由设置窗口大小
      await windowManager.setAspectRatio(0);

      final devicePixelRatio =
          WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

      // 动态测量窗口偏移量：窗口尺寸(WINDOW RECT) - 内容区(CLIENT AREA)
      // 偏移量包含透明调整边框、标题栏、窗口chrome等，无需硬编码
      final currentWindowSize = await windowManager.getSize();
      final currentViewSize = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
      final offsetW = currentWindowSize.width - currentViewSize.width / devicePixelRatio;
      final offsetH = currentWindowSize.height - currentViewSize.height / devicePixelRatio;

      // 测量内容区中非视频UI元素（如AppBar/TabBar）的高度
      // 需要遍历所有祖先Scaffold，因为_context在VideoPlayerWidget内，
      // 最近的是PlayVideoPage的Scaffold(无appBar)，外层才是CustomScaffold的Scaffold(有appBar)
      double inContentUIHeight = 0;
      final context = _context;
      if (context != null && context.mounted) {
        context.visitAncestorElements((element) {
          if (element is StatefulElement && element.state is ScaffoldState) {
            final scaffoldState = element.state as ScaffoldState;
            final appBarHeight = scaffoldState.appBarMaxHeight ?? 0;
            if (appBarHeight > 0) {
              inContentUIHeight += appBarHeight;
            }
          }
          return true; // 继续遍历所有祖先
        });
      }

      // 目标窗口尺寸 = 视频逻辑尺寸 + 窗口边框偏移 + 内容区UI高度
      double logicalWidth = videoWidth / devicePixelRatio + offsetW;
      double logicalHeight = videoHeight / devicePixelRatio + offsetH + inContentUIHeight;

      // 最小尺寸保护
      logicalWidth = logicalWidth.clamp(320.0, 7680.0);
      logicalHeight = logicalHeight.clamp(240.0, 4320.0);

      await windowManager.setSize(Size(logicalWidth, logicalHeight));
    } catch (e) {
      debugPrint('调整窗口大小失败: $e');
    }
  }
}
