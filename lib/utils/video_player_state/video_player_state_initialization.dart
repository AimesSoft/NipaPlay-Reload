part of video_player_state;

extension VideoPlayerStateInitialization on VideoPlayerState {
  Future<void> _initialize() async {
    if (globals.isPhone) {
      // 使用新的屏幕方向管理器设置初始方向
      await ScreenOrientationManager.instance.setInitialOrientation();
      await _initializeSystemVolumeController();
      await _loadInitialBrightness(); // Load initial brightness for phone
      await _loadInitialVolume(); // <<< CALL ADDED
    }
    // 不在初始化时启动帧级Ticker，避免空闲/非播放状态也持续产帧
    _startUiUpdateTimer(); // 仅创建/准备Ticker，是否启动由播放状态决定
    _setupWindowManagerListener();
    _focusNode.requestFocus();
    await _loadLastVideo();
    await _loadControlBarHeight(); // 加载保存的控制栏高度
    await _loadMinimalProgressBarSettings(); // 加载最小化进度条设置
    await _loadDanmakuOpacity(); // 加载保存的弹幕不透明度
    await _loadDanmakuVisible(); // 加载弹幕可见性
    await _loadMergeDanmaku(); // 加载弹幕合并设置
    await _loadDanmakuStacking(); // 加载弹幕堆叠设置

    // 加载弹幕类型屏蔽设置
    await _loadBlockTopDanmaku();
    await _loadBlockBottomDanmaku();
    await _loadBlockScrollDanmaku();

    // 加载弹幕屏蔽词
    await _loadDanmakuBlockWords();

    // 加载弹幕字体大小和显示区域
    await _loadDanmakuFontSize();
    await _loadDanmakuDisplayArea();
    await _loadDanmakuSpeedMultiplier();

    // 加载播放速度设置
    await _loadPlaybackRate();

    // 加载快进快退时间设置
    await _loadSeekStepSeconds();

    // 加载跳过时间设置
    await _loadSkipSeconds();

    // 加载 Anime4K 设置并尝试立即应用
    await _loadAnime4KProfile();

    // 加载播放结束行为设置
    await _loadPlaybackEndAction();

    // 订阅内核切换事件
    _subscribeToKernelChanges();

    // Ensure wakelock is disabled on initialization
    try {
      WakelockPlus.disable();
      //debugPrint("Wakelock disabled on VideoPlayerState initialization.");
    } catch (e) {
      //debugPrint("Error disabling wakelock on init: $e");
    }
  }

  /// 订阅内核切换事件
  void _subscribeToKernelChanges() {
    // 订阅播放器内核切换事件
    _playerKernelChangeSubscription = PlayerFactory.onKernelChanged.listen((_) {
      debugPrint('[VideoPlayerState] 收到播放器内核切换事件，执行热切换');
      PlayerKernelManager.performPlayerKernelHotSwap(this);
    });

    // 订阅弹幕内核切换事件
    _danmakuKernelChangeSubscription =
        DanmakuKernelFactory.onKernelChanged.listen((newKernel) {
      debugPrint('[VideoPlayerState] 收到弹幕内核切换事件: $newKernel');
      PlayerKernelManager.performDanmakuKernelHotSwap(this, newKernel);
    });
  }

  Future<void> _loadInitialBrightness() async {
    if (!globals.isPhone) return;
    try {
      _currentBrightness = await ScreenBrightness().current;
      _initialDragBrightness =
          _currentBrightness; // Initialize drag brightness too
      //debugPrint("Initial screen brightness loaded: $_currentBrightness");
    } catch (e) {
      //debugPrint("Failed to get initial screen brightness: $e");
      // Keep default _currentBrightness if error occurs
    }
    notifyListeners();
  }

  // Load initial system volume (placeholder)
  Future<void> _loadInitialVolume() async {
    if (!globals.isPhone) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVolume = prefs.getDouble(_playerVolumeKey);
      double initialVolume = savedVolume ?? player.volume;
      _currentVolume =
          initialVolume.clamp(0.0, 1.0); // Ensure it's within 0-1 range
      _initialDragVolume = _currentVolume;
      player.volume = _currentVolume;
      await _setSystemVolume(_currentVolume);
      //debugPrint("Initial volume loaded: $_currentVolume (saved: ${savedVolume != null})");
    } catch (e) {
      //debugPrint("Failed to get initial system volume from player: $e");
      _currentVolume = 0.5; // Fallback
      _initialDragVolume = _currentVolume;
    }
    notifyListeners();
  }

  void startBrightnessDrag() {
    if (!globals.isPhone) return;
    // Refresh _initialDragBrightness with the most up-to-date _currentBrightness
    // This handles cases where brightness might have been changed by other means
    // or if a previous drag was interrupted.
    _initialDragBrightness = _currentBrightness;
    _showBrightnessIndicator();
    debugPrint(
        "Brightness drag started. Initial drag brightness: $_initialDragBrightness");
  }

  Future<void> updateBrightnessOnDrag(
      double verticalDragDelta, BuildContext context) async {
    if (!globals.isPhone) return;

    final screenHeight = MediaQuery.of(context).size.height;
    // 修改灵敏度：拖动屏幕高度的 80% (0.8) 对应亮度从0到1的变化。
    final sensitivityFactor = screenHeight * 0.3;

    double change = -verticalDragDelta / sensitivityFactor;
    // 使用 _initialDragBrightness 作为基准来计算变化量
    double newBrightness = _initialDragBrightness + change;
    newBrightness = newBrightness.clamp(0.0, 1.0);

    try {
      await ScreenBrightness().setScreenBrightness(newBrightness);
      _currentBrightness = newBrightness;
      // 更新 _initialDragBrightness 为当前成功设置的亮度，以确保下次拖拽的起点是连贯的
      _initialDragBrightness = newBrightness;
      _showBrightnessIndicator();
      notifyListeners();
      ////debugPrint("[VideoPlayerState] Brightness updated. Current: $_currentBrightness, InitialDrag: $_initialDragBrightness");
    } catch (e) {
      //debugPrint("Failed to set screen brightness: $e");
    }
  }

  void endBrightnessDrag() {
    if (!globals.isPhone) return;
    // _initialDragBrightness is already updated at the start of the next drag.
    // The indicator will hide via its own timer.
    // No specific action needed here unless we want to immediately save or something.
    // debugPrint("Brightness drag ended. Current brightness: $_currentBrightness");
  }

  void _showBrightnessIndicator() {
    if (!globals.isPhone || _context == null) return;

    final uiThemeProvider =
        Provider.of<UIThemeProvider>(_context!, listen: false);
    final bool useCupertinoStyle =
        uiThemeProvider.isCupertinoTheme && globals.isPhone;

    _isBrightnessIndicatorVisible = true;

    if (_brightnessOverlayEntry == null) {
      _brightnessOverlayEntry = OverlayEntry(
        builder: (context) {
          final indicatorWidget = useCupertinoStyle
              ? const CupertinoBrightnessIndicator()
              : const BrightnessIndicator();
          Widget overlayChild = ChangeNotifierProvider<VideoPlayerState>.value(
            value: this,
            child: Consumer<VideoPlayerState>(
              builder: (context, videoState, _) {
                return Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      transform: Matrix4.translationValues(
                        videoState.isBrightnessIndicatorVisible ? -35.0 : 70.0,
                        0.0,
                        0.0,
                      ),
                      child: indicatorWidget,
                    ),
                  ),
                );
              },
            ),
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
      Overlay.of(_context!).insert(_brightnessOverlayEntry!);
    }

    notifyListeners();

    _brightnessIndicatorTimer?.cancel();
    _brightnessIndicatorTimer = Timer(const Duration(seconds: 2), () {
      _hideBrightnessIndicator();
    });
    // The final notifyListeners() from the original method is already covered above.
  }

  void _hideBrightnessIndicator() {
    if (!globals.isPhone) return;
    _brightnessIndicatorTimer?.cancel();

    if (_isBrightnessIndicatorVisible) {
      _isBrightnessIndicatorVisible = false;
      notifyListeners();

      Future.delayed(const Duration(milliseconds: 150), () {
        if (_brightnessOverlayEntry != null) {
          _brightnessOverlayEntry!.remove();
          _brightnessOverlayEntry = null;
        }
      });
    } else {
      if (_brightnessOverlayEntry != null) {
        _brightnessOverlayEntry!.remove();
        _brightnessOverlayEntry = null;
      }
    }
  }

  // Volume Indicator Overlay Methods
  void _showVolumeIndicator() {
    if (_context == null) return;

    final uiThemeProvider =
        Provider.of<UIThemeProvider>(_context!, listen: false);
    final bool useCupertinoStyle =
        uiThemeProvider.isCupertinoTheme && globals.isPhone;

    _isVolumeIndicatorVisible = true;

    if (_volumeOverlayEntry == null) {
      _volumeOverlayEntry = OverlayEntry(
        builder: (context) {
          final indicatorWidget = useCupertinoStyle
              ? const CupertinoVolumeIndicator()
              : const VolumeIndicator();
          Widget overlayChild = ChangeNotifierProvider<VideoPlayerState>.value(
            value: this,
            child: Consumer<VideoPlayerState>(
              builder: (context, videoState, _) {
                return Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      transform: Matrix4.translationValues(
                        videoState.isVolumeUIVisible ? 35.0 : -70.0,
                        0.0,
                        0.0,
                      ),
                      child: indicatorWidget,
                    ),
                  ),
                );
              },
            ),
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
      Overlay.of(_context!).insert(_volumeOverlayEntry!);
    }
    notifyListeners();

    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(seconds: 2), () {
      _hideVolumeIndicator();
    });
  }

  void _hideVolumeIndicator() {
    // if (!globals.isPhone) return; // 原始判断可能阻止PC
    _volumeIndicatorTimer?.cancel();

    if (_isVolumeIndicatorVisible) {
      _isVolumeIndicatorVisible = false;
      notifyListeners();

      Future.delayed(const Duration(milliseconds: 150), () {
        if (_volumeOverlayEntry != null) {
          _volumeOverlayEntry!.remove();
          _volumeOverlayEntry = null;
        }
      });
    } else {
      if (_volumeOverlayEntry != null) {
        _volumeOverlayEntry!.remove();
        _volumeOverlayEntry = null;
      }
    }
  }

  Future<void> _loadLastVideo() async {
    // 不再自动加载上次视频，让用户手动选择
    return;
  }

  Future<void> _saveLastVideo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastVideoKey, _currentVideoPath ?? '');
    await prefs.setInt(_lastPositionKey, _position.inMilliseconds);
  }

  // 保存视频播放位置
  Future<void> _saveVideoPosition(String path, int position) async {
    final prefs = await SharedPreferences.getInstance();
    final positions = prefs.getString(_videoPositionsKey) ?? '{}';
    final Map<String, dynamic> positionMap =
        Map<String, dynamic>.from(json.decode(positions));
    positionMap[path] = position;
    await prefs.setString(_videoPositionsKey, json.encode(positionMap));
  }

  // 获取视频播放位置（支持iOS容器路径修复和进度回退）
  Future<int> _getVideoPosition(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final positions = prefs.getString(_videoPositionsKey) ?? '{}';
    final Map<String, dynamic> positionMap =
        Map<String, dynamic>.from(json.decode(positions));

    // 1. 直接查找原路径
    int position = positionMap[path] ?? 0;
    if (position > 0) {
      return position;
    }

    // 2. iOS平台：尝试修复容器路径查找进度
    if (Platform.isIOS) {
      final fixedPath = await iOSContainerPathFixer.fixContainerPath(path);
      if (fixedPath != null) {
        position = positionMap[fixedPath] ?? 0;
        if (position > 0) {
          debugPrint('通过iOS路径修复找到播放进度: $position ms');
          // 同时更新新路径的进度记录
          positionMap[path] = position;
          await prefs.setString(_videoPositionsKey, json.encode(positionMap));
          return position;
        }
      }

      // 3. iOS进度回退：通过视频识别结果查询进度
      if (_animeId != null && _episodeId != null) {
        try {
          final historyByEpisode = await WatchHistoryDatabase.instance
              .getHistoryByEpisode(_animeId!, _episodeId!);
          if (historyByEpisode != null && historyByEpisode.lastPosition > 0) {
            debugPrint('通过视频识别回退查找到播放进度: ${historyByEpisode.lastPosition} ms');
            debugPrint(
                '匹配视频: ${historyByEpisode.animeName} - ${historyByEpisode.episodeTitle}');

            // 保存到新路径
            positionMap[path] = historyByEpisode.lastPosition;
            await prefs.setString(_videoPositionsKey, json.encode(positionMap));
            return historyByEpisode.lastPosition;
          }
        } catch (e) {
          debugPrint('通过视频识别查询进度失败: $e');
        }
      }
    }

    return 0;
  }
}
