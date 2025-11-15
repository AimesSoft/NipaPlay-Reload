part of video_player_state;

extension VideoPlayerStatePlaybackControls on VideoPlayerState {
  // 切换菜单栏显示/隐藏状态（仅用于平板设备）
  void toggleAppBarVisibility() async {
    if (isTablet) {
      _isAppBarHidden = !_isAppBarHidden;

      // 当切换到全屏状态时，同时隐藏系统状态栏
      if (_isAppBarHidden) {
        // 进入全屏状态，隐藏系统UI
        try {
          await SystemChrome.setEnabledSystemUIMode(
              SystemUiMode.immersiveSticky);
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

      notifyListeners();
    }
  }

  Future<void> resetPlayer() async {
    try {
      _isResetting = true; // 设置重置标志

      // 在停止播放前保存最后的观看记录
      if (_currentVideoPath != null) {
        await _updateWatchHistory();
      }

      // Jellyfin同步：如果是Jellyfin流媒体，停止同步
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('jellyfin://')) {
        try {
          final itemId = _currentVideoPath!.replaceFirst('jellyfin://', '');
          final syncService = JellyfinPlaybackSyncService();
          final historyItem =
              await WatchHistoryManager.getHistoryItem(_currentVideoPath!);
          if (historyItem != null) {
            await syncService.reportPlaybackStopped(itemId, historyItem,
                isCompleted: false);
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
          final historyItem =
              await WatchHistoryManager.getHistoryItem(_currentVideoPath!);
          if (historyItem != null) {
            await syncService.reportPlaybackStopped(itemId, historyItem,
                isCompleted: false);
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
        player.state = PlaybackState.stopped;
      }

      // 等待一小段时间确保播放器完全停止
      await Future.delayed(const Duration(milliseconds: 100));

      // 释放纹理，确保资源被正确释放
      if (player.textureId.value != null) {
        // Keep the null check for reading
        _disposeTextureResources();
        // player.textureId.value = null; // COMMENTED OUT
      }

      // 等待一小段时间确保纹理完全释放
      await Future.delayed(const Duration(milliseconds: 200));

      // 重置状态
      _currentVideoPath = null;
      _danmakuOverlayKey = 'idle'; // 重置弹幕覆盖层key
      _position = Duration.zero;
      _duration = Duration.zero;
      _progress = 0.0;
      _error = null;
      _animeTitle = null; // 清除动画标题
      _episodeTitle = null; // 清除集数标题
      _danmakuList = []; // 清除弹幕列表
      _danmakuTracks.clear();
      _danmakuTrackEnabled.clear();
      _subtitleManager.clearSubtitleTrackInfo();
      _isAppBarHidden = false; // 重置平板设备菜单栏隐藏状态

      // 重置系统UI显示状态
      if (globals.isPhone && globals.isTablet) {
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        } catch (e) {
          debugPrint('重置系统UI时出错: $e');
        }
      }

      _setStatus(PlayerStatus.idle);

      // 使用屏幕方向管理器重置屏幕方向
      if (globals.isPhone) {
        await ScreenOrientationManager.instance.resetOrientation();
      }

      // 关闭唤醒锁
      try {
        WakelockPlus.disable();
      } catch (e) {
        //debugPrint("Error disabling wakelock: $e");
      }

      notifyListeners();
    } catch (e) {
      //debugPrint('重置播放器时出错: $e');
      rethrow;
    } finally {
      _isResetting = false; // 清除重置标志
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

  void _setStatus(PlayerStatus newStatus,
      {String? message, bool clearPreviousMessages = false}) {
    // 在状态即将从loading或recognizing变为ready或playing时，设置最终加载阶段标志
    if ((_status == PlayerStatus.loading ||
            _status == PlayerStatus.recognizing) &&
        (newStatus == PlayerStatus.ready ||
            newStatus == PlayerStatus.playing)) {
      _isInFinalLoadingPhase = true;

      // 延迟通知UI刷新，给足够时间处理状态变更
      Future.microtask(() {
        notifyListeners();
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

      // 在播放开始后一小段时间重置最终加载阶段标志
      Future.delayed(const Duration(milliseconds: 200), () {
        _isInFinalLoadingPhase = false;
        notifyListeners();
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

    notifyListeners();
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
          AutoNextEpisodeService.instance
              .startAutoNextEpisode(_context!, _currentVideoPath!);
        }
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

  void pause() {
    if (_status == PlayerStatus.playing) {
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
      // 在暂停时触发截图
      _captureConditionalScreenshot("暂停时");
      // 停止UI更新Ticker，避免继续产帧
      _uiUpdateTicker?.stop();
      // WakelockPlus.disable(); // Already handled by _setStatus
    }
  }

  void play() {
    // <<< ADDED DEBUG LOG >>>
    debugPrint(
        '[VideoPlayerState] play() called. hasVideo: $hasVideo, _status: $_status, currentMedia: ${player.media}');
    if (hasVideo &&
        (_status == PlayerStatus.paused || _status == PlayerStatus.ready)) {
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
          '[VideoPlayerState] play() -> _status set to PlayerStatus.playing. Notifying listeners.');

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
    _danmakuOverlayKey = 'idle'; // 重置弹幕覆盖层key
    _currentVideoHash = null;
    _currentThumbnailPath = null;
    _animeTitle = null;
    _episodeTitle = null;
    _episodeId = null; // 清除弹幕ID
    _animeId = null; // 清除弹幕ID
    _initialHistoryItem = null;
    _danmakuList.clear();
    _danmakuTracks.clear();
    _danmakuTrackEnabled.clear();
    _subtitleManager.clearSubtitleTrackInfo();
    danmakuController
        ?.dispose(); // Assuming danmakuController has a dispose method
    danmakuController = null;
    _duration = Duration.zero;
    _position = Duration.zero;
    _progress = 0.0;
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
    _subtitleManager.clearExternalSubtitle(notifyListenersToo: false);
    _position = Duration.zero;
    _progress = 0.0;
    _duration = Duration.zero;
    _playbackTimeMs.value = 0;
    if (!_isErrorStopping) {
      // <<< MODIFIED HERE
      _error = null;
    }
    _currentVideoPath = null;
    _danmakuOverlayKey = 'idle'; // 重置弹幕覆盖层key
    _currentVideoHash = null;
    _currentThumbnailPath = null;
    _animeTitle = null;
    _episodeTitle = null;
    _episodeId = null; // 清除弹幕ID
    _animeId = null; // 清除弹幕ID
    _initialHistoryItem = null;
    _danmakuList.clear();
    _danmakuTracks.clear();
    _danmakuTrackEnabled.clear();
    _subtitleManager.clearSubtitleTrackInfo();
    danmakuController
        ?.dispose(); // Assuming danmakuController has a dispose method
    danmakuController = null;
    _videoDuration = Duration.zero;
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
          milliseconds:
              position.inMilliseconds.clamp(0, _duration.inMilliseconds));

      // 如果是暂停状态，先恢复播放
      if (_status == PlayerStatus.paused) {
        player.state = PlaybackState.playing;
        _setStatus(PlayerStatus.playing);
      }

      // 立即更新UI状态
      _position = clampedPosition;
      // 同步高频时间轴，确保弹幕立即跳转
      _playbackTimeMs.value = _position.inMilliseconds.toDouble();
      if (_duration.inMilliseconds > 0) {
        _progress = clampedPosition.inMilliseconds / _duration.inMilliseconds;
      }
      notifyListeners();

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

  void setShowRightMenu(bool value) {
    _showRightMenu = value;
    notifyListeners();
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

    notifyListeners();
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
    notifyListeners();
  }

  Widget _buildHoverSettingsMenu(BuildContext context) {
    // 这里会在后面的组件中实现
    return const SizedBox.shrink();
  }

  // 已移除 _startPositionUpdateTimer，功能已合并到 _startUiUpdateTimer

  bool shouldShowAppBar() {
    if (globals.isPhone) {
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

      notifyListeners();
    } finally {
      _isFullscreenTransitioning = false;
    }
  }

  // 设置上下文
  void setContext(BuildContext context) {
    _context = context;
  }

  // 更新状态消息的方法
  void _updateStatusMessages(List<String> messages) {
    _statusMessages = messages;
    notifyListeners();
  }

  // 添加单个状态消息的方法
  void _addStatusMessage(String message) {
    _statusMessages.add(message);
    notifyListeners();
  }

  // 清除所有状态消息的方法
  void _clearStatusMessages() {
    _statusMessages.clear();
    notifyListeners();
  }

  // Volume Drag Methods
  void startVolumeDrag() {
    if (!globals.isPhone) return;
    _initialDragVolume = _currentVolume;
    _showVolumeIndicator(); // We'll define this next
    debugPrint("Volume drag started. Initial drag volume: $_initialDragVolume");
  }

  Future<void> updateVolumeOnDrag(
      double verticalDragDelta, BuildContext context) async {
    if (!globals.isPhone) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final sensitivityFactor =
        screenHeight * 0.3; // Same sensitivity as brightness for now

    double change = -verticalDragDelta / sensitivityFactor;
    double newVolume = _initialDragVolume + change;
    newVolume = newVolume.clamp(0.0, 1.0);

    try {
      // Set system volume using MDK player.volume (0.0-1.0 range)
      // Check if volume property is available
      player.volume = newVolume;
      await _setSystemVolume(newVolume);
      _currentVolume = newVolume;
      _initialDragVolume = newVolume;
      _showVolumeIndicator();
      _scheduleVolumePersistence();
      notifyListeners();
    } catch (e) {
      //debugPrint("Failed to set system volume via player: $e");
    }
  }

  void endVolumeDrag() {
    if (!globals.isPhone) return;
    debugPrint("Volume drag ended. Current volume: $_currentVolume");
    _scheduleVolumePersistence(immediate: true);
  }

  static const int _textureIdCounter = 0;
  static const double _volumeStep = 0.05; // 5% volume change per key press

  void increaseVolume({double? step}) {
    if (globals.isPhone) return; // Only for PC

    try {
      // Prioritize actual player volume, fallback to _currentVolume
      double currentVolume = player.volume ?? _currentVolume;
      double newVolume =
          (currentVolume + (step ?? _volumeStep)).clamp(0.0, 1.0);

      player.volume = newVolume;
      unawaited(_setSystemVolume(newVolume));
      _currentVolume = newVolume;
      // Keep _initialDragVolume in sync in case a touch/mouse drag starts later
      _initialDragVolume = newVolume;
      _showVolumeIndicator();
      _scheduleVolumePersistence(immediate: true);
      notifyListeners();
      //debugPrint("Volume increased to: $_currentVolume via keyboard");
    } catch (e) {
      //debugPrint("Failed to increase volume via keyboard: $e");
    }
  }

  void decreaseVolume({double? step}) {
    if (globals.isPhone) return; // Only for PC

    try {
      // Prioritize actual player volume, fallback to _currentVolume
      double currentVolume = player.volume ?? _currentVolume;
      double newVolume =
          (currentVolume - (step ?? _volumeStep)).clamp(0.0, 1.0);

      player.volume = newVolume;
      unawaited(_setSystemVolume(newVolume));
      _currentVolume = newVolume;
      // Keep _initialDragVolume in sync in case a touch/mouse drag starts later
      _initialDragVolume = newVolume;
      _showVolumeIndicator();
      _scheduleVolumePersistence(immediate: true);
      notifyListeners();
      //debugPrint("Volume decreased to: $_currentVolume via keyboard");
    } catch (e) {
      //debugPrint("Failed to decrease volume via keyboard: $e");
    }
  }

  // Seek Drag Methods
  void startSeekDrag(BuildContext context) {
    if (!globals.isPhone) return; // Add platform check
    if (!hasVideo) return;
    _isSeekingViaDrag = true;
    _dragSeekStartPosition = _position;
    _accumulatedDragDx = 0.0;
    _dragSeekTargetPosition = _position;
    _showSeekIndicator(); // <<< CALL ADDED
    //debugPrint("Seek drag started. Start position: $_dragSeekStartPosition");
    notifyListeners();
  }

  void updateSeekDrag(double deltaDx, BuildContext context) {
    if (!globals.isPhone) return; // Add platform check
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
    notifyListeners(); // To update UI displaying _dragSeekTargetPosition
  }

  void endSeekDrag() {
    if (!globals.isPhone) return; // Add platform check
    if (!hasVideo || !_isSeekingViaDrag) return;

    seekTo(_dragSeekTargetPosition);
    _isSeekingViaDrag = false;
    _accumulatedDragDx = 0.0;
    _hideSeekIndicator(); // <<< CALL ADDED
    //debugPrint("Seek drag ended. Seeking to: $_dragSeekTargetPosition");
    notifyListeners();
  }

  // Seek Indicator Overlay Methods
  void _showSeekIndicator() {
    if (!globals.isPhone || _context == null) return;

    final uiThemeProvider =
        Provider.of<UIThemeProvider>(_context!, listen: false);
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
    notifyListeners(); // To trigger opacity animation in SeekIndicator

    // Optional: Timer to auto-hide if drag ends abruptly or no more updates
    _seekIndicatorTimer?.cancel();
    // _seekIndicatorTimer = Timer(const Duration(seconds: 2), () {
    //   _hideSeekIndicator();
    // });
  }

  void _hideSeekIndicator() {
    if (!globals.isPhone) return;
    _seekIndicatorTimer?.cancel();

    if (_isSeekIndicatorVisible) {
      _isSeekIndicatorVisible = false;
      notifyListeners(); // Trigger fade-out animation

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
}
