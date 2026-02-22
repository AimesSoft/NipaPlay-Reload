part of video_player_state;

extension VideoPlayerStatePreferences on VideoPlayerState {
  // 设置错误状态
  void _setError(String error) {
    //debugPrint('视频播放错误: $error');
    _error = error;
    _status = PlayerStatus.error;

    // 添加错误消息
    _statusMessages = ['播放出错，正在尝试恢复...'];
    notifyListeners();

    // 尝试恢复播放
    _tryRecoverFromError();
  }

  Future<void> _tryRecoverFromError() async {
    try {
      // 使用屏幕方向管理器重置屏幕方向
      if (globals.isPhone) {
        await ScreenOrientationManager.instance.resetOrientation();
      }

      // 重置播放器状态
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }

      // 如果有当前视频路径，尝试重新初始化
      if (_currentVideoPath != null) {
        final path = _currentVideoPath!;
        final actualUrl = _currentActualPlayUrl;
        _currentVideoPath = null; // 清空路径，避免重复初始化
        _danmakuOverlayKey = 'idle'; // 临时重置弹幕覆盖层key
        await Future.delayed(const Duration(seconds: 1)); // 等待一秒
        await initializePlayer(
          path,
          actualPlayUrl: actualUrl,
          resetManualDanmakuOffset: false,
        );
      } else {
        _setStatus(PlayerStatus.idle, message: '请重新选择视频');
      }
    } catch (e) {
      //debugPrint('恢复播放失败: $e');
      _setStatus(PlayerStatus.idle, message: '播放器恢复失败，请重新选择视频');
    }
  }

  // 加载最小化进度条设置
  Future<void> _loadMinimalProgressBarSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _minimalProgressBarEnabled =
        prefs.getBool(_minimalProgressBarEnabledKey) ?? false;
    _minimalProgressBarColor =
        prefs.getInt(_minimalProgressBarColorKey) ?? 0xFFFF7274;
    _showDanmakuDensityChart =
        prefs.getBool(_showDanmakuDensityChartKey) ?? false;
    notifyListeners();
  }

  Future<void> _loadPlaybackEndAction() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getString(_playbackEndActionKey);
    final action = PlaybackEndActionDisplay.fromPrefs(storedValue);
    final bool changed = action != _playbackEndAction;
    _playbackEndAction = action;
    AutoNextEpisodeService.instance
        .updateAutoPlayEnabled(action == PlaybackEndAction.autoNext);
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> setPlaybackEndAction(PlaybackEndAction action) async {
    if (_playbackEndAction == action) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playbackEndActionKey, action.prefsValue);
    _playbackEndAction = action;
    AutoNextEpisodeService.instance
        .updateAutoPlayEnabled(action == PlaybackEndAction.autoNext);
    if (action != PlaybackEndAction.autoNext) {
      AutoNextEpisodeService.instance.cancelAutoNext();
    }
    notifyListeners();
  }

  Future<void> _loadAutoNextCountdownSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getInt(_autoNextCountdownSecondsKey);
    final resolved = (storedValue ??
            AutoNextEpisodeService.defaultCountdownSeconds)
        .clamp(
          AutoNextEpisodeService.minCountdownSeconds,
          AutoNextEpisodeService.maxCountdownSeconds,
        )
        .toInt();
    final bool changed = resolved != _autoNextCountdownSeconds;
    _autoNextCountdownSeconds = resolved;
    AutoNextEpisodeService.instance.updateCountdownDuration(resolved);
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> setAutoNextCountdownSeconds(int seconds) async {
    final resolved = seconds
        .clamp(
          AutoNextEpisodeService.minCountdownSeconds,
          AutoNextEpisodeService.maxCountdownSeconds,
        )
        .toInt();
    if (_autoNextCountdownSeconds == resolved) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoNextCountdownSecondsKey, resolved);
    _autoNextCountdownSeconds = resolved;
    AutoNextEpisodeService.instance.updateCountdownDuration(resolved);
    notifyListeners();
  }

  Future<void> _loadPauseOnBackgroundSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getBool(_pauseOnBackgroundKey);
    final bool resolvedValue = storedValue ?? globals.isPhone;
    if (_pauseOnBackground != resolvedValue) {
      _pauseOnBackground = resolvedValue;
      notifyListeners();
    } else {
      _pauseOnBackground = resolvedValue;
    }
  }

  Future<void> setPauseOnBackground(bool enabled) async {
    if (_pauseOnBackground == enabled) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pauseOnBackgroundKey, enabled);
    _pauseOnBackground = enabled;
    notifyListeners();
  }

  Future<void> _loadDesktopHoverSettingsMenuEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = prefs.getBool(_desktopHoverSettingsMenuEnabledKey) ?? false;
    if (_desktopHoverSettingsMenuEnabled != resolved) {
      _desktopHoverSettingsMenuEnabled = resolved;
      notifyListeners();
    } else {
      _desktopHoverSettingsMenuEnabled = resolved;
    }
  }

  Future<void> setDesktopHoverSettingsMenuEnabled(bool enabled) async {
    if (_desktopHoverSettingsMenuEnabled == enabled) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_desktopHoverSettingsMenuEnabledKey, enabled);
    _desktopHoverSettingsMenuEnabled = enabled;
    if (!enabled) {
      setShowRightMenu(false);
    }
    notifyListeners();
  }

  // 保存最小化进度条启用状态
  Future<void> setMinimalProgressBarEnabled(bool enabled) async {
    _minimalProgressBarEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_minimalProgressBarEnabledKey, enabled);
    notifyListeners();
  }

  // 保存最小化进度条颜色
  Future<void> setMinimalProgressBarColor(int color) async {
    _minimalProgressBarColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minimalProgressBarColorKey, color);
    notifyListeners();
  }

  // 设置弹幕密度图显示状态
  Future<void> setShowDanmakuDensityChart(bool show) async {
    _showDanmakuDensityChart = show;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showDanmakuDensityChartKey, show);
    notifyListeners();
  }

  // 加载弹幕不透明度
  Future<void> _loadDanmakuOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakuOpacity = prefs.getDouble(_danmakuOpacityKey) ?? 1.0;
    notifyListeners();
  }

  // 保存弹幕不透明度
  Future<void> setDanmakuOpacity(double opacity) async {
    _danmakuOpacity = opacity;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_danmakuOpacityKey, opacity);
    notifyListeners();
  }

  // 获取映射后的弹幕不透明度
  double get mappedDanmakuOpacity {
    // 使用平方函数进行映射，使低值区域变化更平缓
    return _danmakuOpacity * _danmakuOpacity;
  }

  // 加载弹幕可见性
  Future<void> _loadDanmakuVisible() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakuVisible = prefs.getBool(_danmakuVisibleKey) ?? true;
    notifyListeners();
  }

  void setDanmakuVisible(bool visible) async {
    if (_danmakuVisible != visible) {
      _danmakuVisible = visible;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_danmakuVisibleKey, visible);
      notifyListeners();
    }
  }

  void toggleDanmakuVisible() {
    setDanmakuVisible(!_danmakuVisible);
  }

  // 加载弹幕合并设置
  Future<void> _loadMergeDanmaku() async {
    final prefs = await SharedPreferences.getInstance();
    _mergeDanmaku = prefs.getBool(_mergeDanmakuKey) ?? false;
    notifyListeners();
  }

  // 设置弹幕合并
  Future<void> setMergeDanmaku(bool merge) async {
    if (_mergeDanmaku != merge) {
      _mergeDanmaku = merge;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mergeDanmakuKey, merge);
      notifyListeners();
    }
  }

  // 切换弹幕合并状态
  void toggleMergeDanmaku() {
    setMergeDanmaku(!_mergeDanmaku);
  }

  // 加载弹幕堆叠设置
  Future<void> _loadDanmakuStacking() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakuStacking = prefs.getBool(_danmakuStackingKey) ?? false;
    notifyListeners();
  }

  // 加载时间轴告知弹幕轨道开关
  Future<void> _loadTimelineDanmakuEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _isTimelineDanmakuEnabled =
        prefs.getBool(_timelineDanmakuEnabledKey) ?? true;
    notifyListeners();
  }

  Future<void> _loadHardwareDecoderSetting() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final resolved = prefs.getBool(_useHardwareDecoderKey) ?? true;
    final bool changed = resolved != _useHardwareDecoder;
    _useHardwareDecoder = resolved;
    await applyHardwareDecoderPreference();
    if (changed) {
      notifyListeners();
    }
  }

  // 设置弹幕堆叠
  Future<void> setDanmakuStacking(bool stacking) async {
    if (_danmakuStacking != stacking) {
      _danmakuStacking = stacking;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_danmakuStackingKey, stacking);
      notifyListeners();
    }
  }

  // 切换弹幕堆叠状态
  void toggleDanmakuStacking() {
    setDanmakuStacking(!_danmakuStacking);
  }

  // 在文件选择后立即设置加载状态，显示加载界面
  void setPreInitLoadingState(String message) {
    _statusMessages.clear(); // 清除之前的状态消息
    _setStatus(PlayerStatus.loading, message: message);
    // 确保状态变更立即生效
    notifyListeners();
  }

  // 更新解码器设置，代理到解码器管理器
  void updateDecoders(List<String> decoders) {
    _decoderManager.updateDecoders(decoders);
    notifyListeners();
  }

  Future<void> setHardwareDecoderEnabled(bool enabled) async {
    if (_useHardwareDecoder == enabled) {
      return;
    }
    _useHardwareDecoder = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useHardwareDecoderKey, enabled);
    await applyHardwareDecoderPreference();
    notifyListeners();
  }

  String _resolveMpvHwdecValue() {
    if (Platform.isAndroid) {
      return 'mediacodec-copy';
    }
    return 'auto-copy';
  }

  Future<void> applyHardwareDecoderPreference() async {
    if (kIsWeb || _isDisposed) return;
    final kernelName = player.getPlayerKernelName();
    if (kernelName == 'MDK') {
      await _decoderManager.applyHardwareDecodingPreference(_useHardwareDecoder);
    } else if (kernelName == 'Media Kit') {
      final hwdecValue =
          _useHardwareDecoder ? _resolveMpvHwdecValue() : 'no';
      player.setProperty('hwdec', hwdecValue);
    }
  }

  // 播放速度相关方法

  // 加载播放速度设置
  Future<void> _loadPlaybackRate() async {
    final prefs = await SharedPreferences.getInstance();
    _playbackRate = prefs.getDouble(_playbackRateKey) ?? 1.0; // 默认1倍速
    _speedBoostRate = prefs.getDouble(_speedBoostRateKey) ?? 2.0; // 默认2倍速
    _normalPlaybackRate = 1.0; // 始终重置为1.0
    notifyListeners();
  }

  Future<void> _loadPrecacheBufferSize() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getInt(_precacheBufferSizeMbKey);
    final resolved = storedValue == null
        ? PlayerFactory.defaultPrecacheBufferSizeMb
        : storedValue
            .clamp(
              PlayerFactory.minPrecacheBufferSizeMb,
              PlayerFactory.maxPrecacheBufferSizeMb,
            )
            .toInt();
    _precacheBufferSizeMb = resolved;
    notifyListeners();
  }

  Future<void> _loadPrecacheBufferDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getInt(_precacheBufferDurationSecondsKey);
    final resolved = (storedValue ?? _precacheBufferDurationSeconds)
        .clamp(1, 120)
        .toInt();
    _precacheBufferDurationSeconds = resolved;
    notifyListeners();
  }

  Future<void> setPrecacheBufferSizeMb(int value) async {
    final resolved = value
        .clamp(
          PlayerFactory.minPrecacheBufferSizeMb,
          PlayerFactory.maxPrecacheBufferSizeMb,
        )
        .toInt();
    if (_precacheBufferSizeMb == resolved) {
      return;
    }
    _precacheBufferSizeMb = resolved;
    await PlayerFactory.savePrecacheBufferSizeMb(resolved);
    notifyListeners();
  }

  Future<void> setPrecacheBufferDurationSeconds(int value) async {
    final resolved = value.clamp(1, 120).toInt();
    if (_precacheBufferDurationSeconds == resolved) {
      return;
    }
    _precacheBufferDurationSeconds = resolved;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_precacheBufferDurationSecondsKey, resolved);
    await applyPrecacheBufferSettings();
    notifyListeners();
  }

  Future<void> applyPrecacheBufferSettings() async {
    if (_isDisposed) return;
    final kernelName = player.getPlayerKernelName();
    if (kernelName == 'MDK') {
      final maxMs = _precacheBufferDurationSeconds * 1000;
      player.setBufferRange(minMs: 1000, maxMs: maxMs, drop: false);
    }
  }

  // 保存播放速度设置
  Future<void> setPlaybackRate(double rate) async {
    _playbackRate = rate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playbackRateKey, rate);

    // 立即应用新的播放速度
    if (hasVideo) {
      player.setPlaybackRate(rate);
      debugPrint('设置播放速度: ${rate}x');
    }
    notifyListeners();
  }

  // 设置长按倍速播放的倍率
  Future<void> setSpeedBoostRate(double rate) async {
    _speedBoostRate = rate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedBoostRateKey, rate);
    notifyListeners();
  }

  // 开始倍速播放（长按开始）
  void startSpeedBoost() {
    if (!hasVideo || _isSpeedBoostActive) return;

    // 保存当前播放速度，以便长按结束时恢复
    _normalPlaybackRate = _playbackRate;
    _isSpeedBoostActive = true;

    // 使用配置的倍速
    player.setPlaybackRate(_speedBoostRate);
    debugPrint('开始长按倍速播放: ${_speedBoostRate}x (之前: ${_normalPlaybackRate}x)');

    notifyListeners();
  }

  // 结束倍速播放（长按结束）
  void stopSpeedBoost() {
    if (!hasVideo || !_isSpeedBoostActive) return;

    _isSpeedBoostActive = false;
    // 恢复到长按前的播放速度
    player.setPlaybackRate(_normalPlaybackRate);
    debugPrint('结束长按倍速播放，恢复到: ${_normalPlaybackRate}x');

    notifyListeners();
  }

  // 切换播放速度按钮功能
  void togglePlaybackRate() {
    if (!hasVideo) return;

    if (_isSpeedBoostActive) {
      // 如果正在长按倍速播放，结束长按
      stopSpeedBoost();
    } else {
      // 智能切换播放速度：在1倍速和2倍速之间切换
      if (_playbackRate == 1.0) {
        // 当前是1倍速，切换到2倍速
        setPlaybackRate(2.0);
      } else {
        // 当前是其他倍速，切换到1倍速
        setPlaybackRate(1.0);
      }
    }
  }

  // 快进快退时间设置相关方法

  // 加载快进快退时间设置
  Future<void> _loadSeekStepSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    _seekStepSeconds = prefs.getInt(_seekStepSecondsKey) ?? 10; // 默认10秒
    notifyListeners();
  }

  // 保存快进快退时间设置
  Future<void> setSeekStepSeconds(int seconds) async {
    _seekStepSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seekStepSecondsKey, seconds);
    notifyListeners();
  }

  // 加载跳过时间设置
  Future<void> _loadSkipSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    _skipSeconds = prefs.getInt(_skipSecondsKey) ?? 90; // 默认90秒
    notifyListeners();
  }

  // 保存跳过时间设置
  Future<void> setSkipSeconds(int seconds) async {
    _skipSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_skipSecondsKey, seconds);
    notifyListeners();
  }

  Future<void> _loadDoubleResolutionPlayback() async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = prefs.getBool(_doubleResolutionPlaybackKey) ?? false;
    if (_doubleResolutionPlaybackEnabled != resolved) {
      _doubleResolutionPlaybackEnabled = resolved;
      notifyListeners();
    } else {
      _doubleResolutionPlaybackEnabled = resolved;
    }
    await applyAnime4KProfileToCurrentPlayer();
  }

  Future<void> setDoubleResolutionPlaybackEnabled(bool enabled) async {
    if (_doubleResolutionPlaybackEnabled == enabled) {
      if (!hasVideo) {
        await applyAnime4KProfileToCurrentPlayer();
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_doubleResolutionPlaybackKey, enabled);
    _doubleResolutionPlaybackEnabled = enabled;
    if (!hasVideo) {
      await applyAnime4KProfileToCurrentPlayer();
    }
    notifyListeners();
  }

  Future<void> _loadAnime4KProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int stored =
          prefs.getInt(_anime4kProfileKey) ?? Anime4KProfile.off.index;
      if (stored >= 0 && stored < Anime4KProfile.values.length) {
        _anime4kProfile = Anime4KProfile.values[stored];
      } else {
        _anime4kProfile = Anime4KProfile.off;
      }
    } catch (e) {
      debugPrint('[VideoPlayerState] 读取 Anime4K 设置失败: $e');
      _anime4kProfile = Anime4KProfile.off;
    }

    await applyAnime4KProfileToCurrentPlayer();
    notifyListeners();
  }

  Future<void> setAnime4KProfile(Anime4KProfile profile) async {
    if (_anime4kProfile == profile) {
      // 仍然确保当前播放器应用该配置，便于热切换后快速生效。
      if (!hasVideo) {
        await applyAnime4KProfileToCurrentPlayer();
      }
      return;
    }

    _anime4kProfile = profile;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_anime4kProfileKey, profile.index);
    } catch (e) {
      debugPrint('[VideoPlayerState] 保存 Anime4K 设置失败: $e');
    }

    if (!hasVideo) {
      await applyAnime4KProfileToCurrentPlayer();
    }
    notifyListeners();
  }

  Future<void> _loadCrtProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int stored = prefs.getInt(_crtProfileKey) ?? CrtProfile.off.index;
      if (stored >= 0 && stored < CrtProfile.values.length) {
        _crtProfile = CrtProfile.values[stored];
      } else {
        _crtProfile = CrtProfile.off;
      }
    } catch (e) {
      debugPrint('[VideoPlayerState] 读取 CRT 设置失败: $e');
      _crtProfile = CrtProfile.off;
    }

    await applyAnime4KProfileToCurrentPlayer();
    notifyListeners();
  }

  Future<void> setCrtProfile(CrtProfile profile) async {
    if (_crtProfile == profile) {
      await applyAnime4KProfileToCurrentPlayer();
      return;
    }

    _crtProfile = profile;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_crtProfileKey, profile.index);
    } catch (e) {
      debugPrint('[VideoPlayerState] 保存 CRT 设置失败: $e');
    }

    await applyAnime4KProfileToCurrentPlayer();
    notifyListeners();
  }

  Future<void> applyAnime4KProfileToCurrentPlayer() async {
    if (!_supportsAnime4KForCurrentPlayer()) {
      _anime4kShaderPaths = const <String>[];
      _crtShaderPaths = const <String>[];
      _needsAnime4KSurfaceScaleRefresh = false;
      _anime4kSurfaceScaleRequestId++;
      return;
    }

    final bool anime4kEnabled = _anime4kProfile != Anime4KProfile.off;
    final bool crtEnabled = _crtProfile != CrtProfile.off;
    final bool upscaleEnabled =
        _doubleResolutionPlaybackEnabled || anime4kEnabled;
    final bool canAdjustSurface = hasVideo;

    try {
      final List<String> shaderPaths = <String>[];
      if (anime4kEnabled) {
        final List<String> anime4kPaths =
            await Anime4KShaderManager.getShaderPathsForProfile(
          _anime4kProfile,
        );
        _anime4kShaderPaths = List.unmodifiable(anime4kPaths);
        shaderPaths.addAll(anime4kPaths);
      } else {
        _anime4kShaderPaths = const <String>[];
      }

      if (crtEnabled) {
        final List<String> crtPaths =
            await CrtShaderManager.getShaderPathsForProfile(_crtProfile);
        _crtShaderPaths = List.unmodifiable(crtPaths);
        shaderPaths.addAll(crtPaths);
      } else {
        _crtShaderPaths = const <String>[];
      }

      if (shaderPaths.isEmpty) {
        _applyAnime4KMpvTuning(enable: false);
        try {
          player.setProperty('glsl-shaders', '');
        } catch (e) {
          debugPrint('[VideoPlayerState] 清除着色器失败: $e');
        }
        if (canAdjustSurface) {
          await _updateAnime4KSurfaceScale(enable: upscaleEnabled);
          await _logCurrentVideoDimensions(context: 'Shaders off');
          _requestAnime4KSurfaceScaleRefreshIfNeeded(upscaleEnabled);
        } else {
          _needsAnime4KSurfaceScaleRefresh = upscaleEnabled;
          _anime4kSurfaceScaleRequestId++;
        }
        return;
      }

      final String propertyValue =
          Anime4KShaderManager.buildMpvShaderList(shaderPaths);
      _applyAnime4KMpvTuning(enable: anime4kEnabled);
      player.setProperty('glsl-shaders', propertyValue);
      debugPrint(
        '[VideoPlayerState] mpv 着色器已应用: $propertyValue',
      );
      try {
        final String? currentValue = player.getProperty('glsl-shaders');
        debugPrint(
          '[VideoPlayerState] mpv 当前播放器属性: ${currentValue ?? '<null>'}',
        );
      } catch (e) {
        debugPrint('[VideoPlayerState] 读取 mpv 属性失败: $e');
      }
      if (canAdjustSurface) {
        await _updateAnime4KSurfaceScale(enable: upscaleEnabled);
        if (anime4kEnabled) {
          await _logCurrentVideoDimensions(
            context: 'Anime4K ${_anime4kProfile.name}',
          );
        }
        _requestAnime4KSurfaceScaleRefreshIfNeeded(upscaleEnabled);
      } else {
        _needsAnime4KSurfaceScaleRefresh = upscaleEnabled;
        _anime4kSurfaceScaleRequestId++;
      }
    } catch (e) {
      debugPrint('[VideoPlayerState] 应用着色器失败: $e');
    }
  }

  bool _supportsAnime4KForCurrentPlayer() {
    if (kIsWeb) {
      return false;
    }
    try {
      return player.getPlayerKernelName() == 'Media Kit';
    } catch (_) {
      return false;
    }
  }

  void _applyAnime4KMpvTuning({required bool enable}) {
    final Map<String, String> options = Map<String, String>.from(
      enable ? _anime4kRecommendedMpvOptions : _anime4kDefaultMpvOptions,
    );
    if (!kIsWeb && Platform.isWindows) {
      options['gpu-api'] = enable ? 'opengl' : 'auto';
    }
    options.forEach((String key, String value) {
      try {
        player.setProperty(key, value);
      } catch (e) {
        debugPrint('[VideoPlayerState] 设置 $key=$value 失败: $e');
      }
    });
  }

  Future<void> _logCurrentVideoDimensions({String context = ''}) async {
    try {
      final _VideoDimensionSnapshot snapshot = await _collectVideoDimensions();

      final String contextLabel = context.isEmpty ? '' : ' [$context]';
      final String srcLabel = snapshot.hasSource
          ? '${snapshot.srcWidth}x${snapshot.srcHeight}'
          : '未知';
      final String dispLabel = snapshot.hasDisplay
          ? '${snapshot.displayWidth}x${snapshot.displayHeight}'
          : '未知';

    } catch (e) {
      debugPrint('[VideoPlayerState] Anime4K 分辨率日志失败: $e');
    }
  }

  double _resolveVideoSurfaceScaleFactor() {
    if (_anime4kProfile != Anime4KProfile.off) {
      return _anime4kScaleFactorForProfile(_anime4kProfile);
    }
    return _doubleResolutionPlaybackEnabled ? 2.0 : 1.0;
  }

  Future<void> _updateAnime4KSurfaceScale({
    required bool enable,
    int retry = 0,
  }) async {
    const int maxRetry = 10;

    try {
      if (!hasVideo) {
        return;
      }
      if (!enable) {
        await player.setVideoSurfaceSize();
        return;
      }

      final double factor = _resolveVideoSurfaceScaleFactor();
      if (factor <= 1.0) {
        await player.setVideoSurfaceSize();
        return;
      }

      final _VideoDimensionSnapshot snapshot = await _collectVideoDimensions();
      if (!snapshot.hasSource) {
        if (retry < maxRetry) {
          await Future.delayed(const Duration(milliseconds: 200));
          await _updateAnime4KSurfaceScale(enable: enable, retry: retry + 1);
        } else {
          debugPrint(
              '[VideoPlayerState] Anime4K 源分辨率未知，无法调整纹理尺寸 (已重试${maxRetry}次)');
        }
        return;
      }

      final int targetWidth = (snapshot.srcWidth! * factor).round();
      final int targetHeight = (snapshot.srcHeight! * factor).round();

      if (!kIsWeb && Platform.isWindows) {
        const int maxDimension = 4096;
        if (targetWidth > maxDimension || targetHeight > maxDimension) {
          debugPrint(
              '[VideoPlayerState] Windows Anime4K 目标尺寸过大，跳过放大以避免黑屏: ${targetWidth}x${targetHeight}');
          await player.setVideoSurfaceSize();
          return;
        }
      }

      if (snapshot.displayWidth == targetWidth &&
          snapshot.displayHeight == targetHeight) {
        // 已经是目标尺寸
        return;
      }

      await player.setVideoSurfaceSize(
        width: targetWidth,
        height: targetHeight,
      );
    } catch (e) {
      if (retry < maxRetry) {
        await Future.delayed(const Duration(milliseconds: 200));
        await _updateAnime4KSurfaceScale(enable: enable, retry: retry + 1);
      } else {
        debugPrint('[VideoPlayerState] 调整 Anime4K 纹理尺寸失败: $e');
      }
    }
  }

  void _requestAnime4KSurfaceScaleRefreshIfNeeded(bool upscaleEnabled) {
    if (!upscaleEnabled || !_supportsAnime4KForCurrentPlayer() || !hasVideo) {
      _needsAnime4KSurfaceScaleRefresh = false;
      _anime4kSurfaceScaleRequestId++;
      return;
    }
    if (_status == PlayerStatus.playing) {
      _needsAnime4KSurfaceScaleRefresh = false;
      _scheduleAnime4KSurfaceScaleRefresh();
    } else {
      _needsAnime4KSurfaceScaleRefresh = true;
    }
  }

  void _scheduleAnime4KSurfaceScaleRefresh({
    int attempt = 0,
    int? requestId,
    String? videoPath,
  }) {
    if (_isDisposed || !_supportsAnime4KForCurrentPlayer()) {
      return;
    }

    final bool upscaleEnabled =
        _doubleResolutionPlaybackEnabled || _anime4kProfile != Anime4KProfile.off;
    if (!upscaleEnabled || !hasVideo) {
      return;
    }

    final int token = requestId ?? ++_anime4kSurfaceScaleRequestId;
    final String? targetPath = videoPath ?? _currentVideoPath;

    Future.delayed(const Duration(milliseconds: 400), () {
      if (_isDisposed || token != _anime4kSurfaceScaleRequestId) {
        return;
      }
      if (!hasVideo || _currentVideoPath != targetPath) {
        return;
      }

      final bool playbackReady = player.state == PlaybackState.playing ||
          player.state == PlaybackState.paused;
      if (!playbackReady) {
        if (attempt < 6) {
          _scheduleAnime4KSurfaceScaleRefresh(
            attempt: attempt + 1,
            requestId: token,
            videoPath: targetPath,
          );
        }
        return;
      }

      unawaited(_updateAnime4KSurfaceScale(enable: upscaleEnabled));
    });
  }

  Future<_VideoDimensionSnapshot> _collectVideoDimensions({
    int attempts = 6,
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    int? srcWidth;
    int? srcHeight;
    int? dispWidth;
    int? dispHeight;

    Map<String, dynamic> _toStringKeyedMap(dynamic raw) {
      if (raw is Map) {
        return raw.map(
            (dynamic key, dynamic value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    }

    int? _toInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.round();
      if (value is String) {
        final String trimmed = value.trim();
        final int? parsedInt = int.tryParse(trimmed);
        if (parsedInt != null) {
          return parsedInt;
        }
        final double? parsedDouble = double.tryParse(trimmed);
        if (parsedDouble != null) {
          return parsedDouble.round();
        }
        final String digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9.-]'), '');
        final int? fallbackInt = int.tryParse(digitsOnly);
        if (fallbackInt != null) {
          return fallbackInt;
        }
        final double? fallbackDouble = double.tryParse(digitsOnly);
        if (fallbackDouble != null) {
          return fallbackDouble.round();
        }
      }
      return null;
    }

    for (int attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await Future.delayed(interval);
      }

      final Map<String, dynamic> info =
          await player.getDetailedMediaInfoAsync();

      final Map<String, dynamic> mpvProps =
          _toStringKeyedMap(info['mpvProperties']);
      final Map<String, dynamic> videoParams =
          _toStringKeyedMap(info['videoParams']);

      srcWidth = _toInt(mpvProps['video-params/w']) ??
          _toInt(videoParams['width']) ??
          srcWidth;
      srcHeight = _toInt(mpvProps['video-params/h']) ??
          _toInt(videoParams['height']) ??
          srcHeight;

      dispWidth = _toInt(mpvProps['dwidth']) ??
          _toInt(mpvProps['video-out-params/w']) ??
          _toInt(mpvProps['video-params/dw']) ??
          dispWidth;
      dispHeight = _toInt(mpvProps['dheight']) ??
          _toInt(mpvProps['video-out-params/h']) ??
          _toInt(mpvProps['video-params/dh']) ??
          dispHeight;

      if (srcWidth != null &&
          srcHeight != null &&
          dispWidth != null &&
          dispHeight != null) {
        break;
      }
    }

    if ((srcWidth == null || srcHeight == null) &&
        player.mediaInfo.video != null &&
        player.mediaInfo.video!.isNotEmpty) {
      final codec = player.mediaInfo.video!.first.codec;
      srcWidth ??= codec.width;
      srcHeight ??= codec.height;
    }

    return _VideoDimensionSnapshot(
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      displayWidth: dispWidth,
      displayHeight: dispHeight,
    );
  }

  double _anime4kScaleFactorForProfile(Anime4KProfile profile) {
    switch (profile) {
      case Anime4KProfile.off:
        return 1.0;
      case Anime4KProfile.lite:
      case Anime4KProfile.standard:
      case Anime4KProfile.high:
        return 2.0;
    }
  }

  // 跳过功能
  void skip() {
    final currentPosition = position;
    final newPosition = currentPosition + Duration(seconds: _skipSeconds);
    seekTo(newPosition);
  }

  // 弹幕字体大小和显示区域相关方法

  // 加载弹幕字体大小
  Future<void> _loadDanmakuFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakuFontSize = prefs.getDouble(_danmakuFontSizeKey) ?? 0.0;
    notifyListeners();
  }

  // 设置弹幕字体大小
  Future<void> setDanmakuFontSize(double fontSize) async {
    if (_danmakuFontSize != fontSize) {
      _danmakuFontSize = fontSize;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_danmakuFontSizeKey, fontSize);
      notifyListeners();
    }
  }

  // 获取实际使用的弹幕字体大小
  double get actualDanmakuFontSize {
    if (_danmakuFontSize <= 0) {
      // 使用默认值
      return globals.isPhone ? 20.0 : 30.0;
    }
    return _danmakuFontSize;
  }

  double _clampSubtitleScale(double value) {
    return value
        .clamp(VideoPlayerState.minSubtitleScale,
            VideoPlayerState.maxSubtitleScale)
        .toDouble();
  }

  double _clampSubtitlePosition(double value) {
    return value
        .clamp(VideoPlayerState.minSubtitlePosition,
            VideoPlayerState.maxSubtitlePosition)
        .toDouble();
  }

  double _clampSubtitleOpacity(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _clampSubtitleBorderSize(double value) {
    return value.clamp(0.0, 10.0).toDouble();
  }

  double _clampSubtitleShadowOffset(double value) {
    return value.clamp(0.0, 10.0).toDouble();
  }

  int _subtitleOpacityToMpv(double value) {
    return (_clampSubtitleOpacity(value) * 255).round();
  }

  String _colorToMpvHex(Color color) {
    final rgb = color.value & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  String _subtitleAlignXToMpv(SubtitleAlignX align) {
    switch (align) {
      case SubtitleAlignX.left:
        return 'left';
      case SubtitleAlignX.center:
        return 'center';
      case SubtitleAlignX.right:
        return 'right';
    }
  }

  String _subtitleAlignYToMpv(SubtitleAlignY align) {
    switch (align) {
      case SubtitleAlignY.top:
        return 'top';
      case SubtitleAlignY.center:
        return 'center';
      case SubtitleAlignY.bottom:
        return 'bottom';
    }
  }

  String _subtitleOverrideModeToMpv(SubtitleStyleOverrideMode mode) {
    switch (mode) {
      case SubtitleStyleOverrideMode.none:
        return 'no';
      case SubtitleStyleOverrideMode.scale:
        return 'scale';
      case SubtitleStyleOverrideMode.force:
        return 'force';
      case SubtitleStyleOverrideMode.auto:
        final bool needsScaleOverride = (_subtitleScale - 1.0).abs() >= 0.001;
        return needsScaleOverride ? 'scale' : 'no';
    }
  }

  Future<void> _loadSubtitleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _subtitleScale = _clampSubtitleScale(
      prefs.getDouble(_subtitleScaleKey) ??
          VideoPlayerState.defaultSubtitleScale,
    );
    _subtitleDelaySeconds = prefs.getDouble(_subtitleDelayKey) ??
        VideoPlayerState.defaultSubtitleDelaySeconds;
    _subtitlePosition = _clampSubtitlePosition(
      prefs.getDouble(_subtitlePositionKey) ??
          VideoPlayerState.defaultSubtitlePosition,
    );
    _subtitleAlignX = SubtitleAlignX.values[
        (prefs.getInt(_subtitleAlignXKey) ??
                VideoPlayerState.defaultSubtitleAlignX.index)
            .clamp(0, SubtitleAlignX.values.length - 1)];
    _subtitleAlignY = SubtitleAlignY.values[
        (prefs.getInt(_subtitleAlignYKey) ??
                VideoPlayerState.defaultSubtitleAlignY.index)
            .clamp(0, SubtitleAlignY.values.length - 1)];
    _subtitleMarginX =
        prefs.getDouble(_subtitleMarginXKey) ??
            VideoPlayerState.defaultSubtitleMarginX;
    _subtitleMarginY =
        prefs.getDouble(_subtitleMarginYKey) ??
            VideoPlayerState.defaultSubtitleMarginY;
    _subtitleOpacity = _clampSubtitleOpacity(
      prefs.getDouble(_subtitleOpacityKey) ??
          VideoPlayerState.defaultSubtitleOpacity,
    );
    _subtitleBorderSize = _clampSubtitleBorderSize(
      prefs.getDouble(_subtitleBorderSizeKey) ??
          VideoPlayerState.defaultSubtitleBorderSize,
    );
    _subtitleShadowOffset = _clampSubtitleShadowOffset(
      prefs.getDouble(_subtitleShadowOffsetKey) ??
          VideoPlayerState.defaultSubtitleShadowOffset,
    );
    _subtitleBold = prefs.getBool(_subtitleBoldKey) ?? false;
    _subtitleItalic = prefs.getBool(_subtitleItalicKey) ?? false;
    _subtitleColorValue = prefs.getInt(_subtitleColorKey) ??
        VideoPlayerState.defaultSubtitleColorValue;
    _subtitleBorderColorValue = prefs.getInt(_subtitleBorderColorKey) ??
        VideoPlayerState.defaultSubtitleBorderColorValue;
    _subtitleShadowColorValue = prefs.getInt(_subtitleShadowColorKey) ??
        VideoPlayerState.defaultSubtitleShadowColorValue;
    _subtitleFontName = prefs.getString(_subtitleFontNameKey) ?? '';
    _subtitleFontDir = prefs.getString(_subtitleFontDirKey) ?? '';
    _subtitleOverrideMode = SubtitleStyleOverrideMode.values[
        (prefs.getInt(_subtitleOverrideModeKey) ??
                VideoPlayerState.defaultSubtitleOverrideMode.index)
            .clamp(0, SubtitleStyleOverrideMode.values.length - 1)];
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleScale(double scale) async {
    final resolved = _clampSubtitleScale(scale);
    if ((_subtitleScale - resolved).abs() < 0.0001) {
      return;
    }
    _subtitleScale = resolved;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleScaleKey, resolved);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleDelaySeconds(double seconds) async {
    if ((_subtitleDelaySeconds - seconds).abs() < 0.0001) {
      return;
    }
    _subtitleDelaySeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleDelayKey, seconds);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitlePosition(double position) async {
    final resolved = _clampSubtitlePosition(position);
    if ((_subtitlePosition - resolved).abs() < 0.0001) {
      return;
    }
    _subtitlePosition = resolved;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitlePositionKey, resolved);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleAlignX(SubtitleAlignX align) async {
    if (_subtitleAlignX == align) return;
    _subtitleAlignX = align;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_subtitleAlignXKey, align.index);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleAlignY(SubtitleAlignY align) async {
    if (_subtitleAlignY == align) return;
    _subtitleAlignY = align;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_subtitleAlignYKey, align.index);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleMarginX(double value) async {
    if ((_subtitleMarginX - value).abs() < 0.0001) return;
    _subtitleMarginX = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleMarginXKey, value);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleMarginY(double value) async {
    if ((_subtitleMarginY - value).abs() < 0.0001) return;
    _subtitleMarginY = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleMarginYKey, value);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleOpacity(double value) async {
    final resolved = _clampSubtitleOpacity(value);
    if ((_subtitleOpacity - resolved).abs() < 0.0001) return;
    _subtitleOpacity = resolved;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleOpacityKey, resolved);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleBorderSize(double value) async {
    final resolved = _clampSubtitleBorderSize(value);
    if ((_subtitleBorderSize - resolved).abs() < 0.0001) return;
    _subtitleBorderSize = resolved;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleBorderSizeKey, resolved);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleShadowOffset(double value) async {
    final resolved = _clampSubtitleShadowOffset(value);
    if ((_subtitleShadowOffset - resolved).abs() < 0.0001) return;
    _subtitleShadowOffset = resolved;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleShadowOffsetKey, resolved);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleBold(bool value) async {
    if (_subtitleBold == value) return;
    _subtitleBold = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_subtitleBoldKey, value);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleItalic(bool value) async {
    if (_subtitleItalic == value) return;
    _subtitleItalic = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_subtitleItalicKey, value);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleColor(Color color) async {
    if (_subtitleColorValue == color.value) return;
    _subtitleColorValue = color.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_subtitleColorKey, color.value);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleBorderColor(Color color) async {
    if (_subtitleBorderColorValue == color.value) return;
    _subtitleBorderColorValue = color.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_subtitleBorderColorKey, color.value);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleShadowColor(Color color) async {
    if (_subtitleShadowColorValue == color.value) return;
    _subtitleShadowColorValue = color.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_subtitleShadowColorKey, color.value);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleFontName(String name) async {
    final trimmed = name.trim();
    if (_subtitleFontName == trimmed) return;
    _subtitleFontName = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleFontNameKey, trimmed);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> setSubtitleFontDir(String dir) async {
    if (_subtitleFontDir == dir) return;
    _subtitleFontDir = dir;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleFontDirKey, dir);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> importSubtitleFontFile(String sourcePath) async {
    if (sourcePath.isEmpty) return;
    try {
      final baseDir = await StorageService.getAppStorageDirectory();
      final fontsDir = Directory(p.join(baseDir.path, 'subtitle_fonts'));
      await fontsDir.create(recursive: true);
      final fileName = p.basename(sourcePath);
      final destPath = p.join(fontsDir.path, fileName);
      await File(sourcePath).copy(destPath);
      _subtitleFontDir = fontsDir.path;
      _subtitleFontName = p.basenameWithoutExtension(destPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_subtitleFontDirKey, _subtitleFontDir);
      await prefs.setString(_subtitleFontNameKey, _subtitleFontName);
      await applySubtitleStylePreference();
      notifyListeners();
    } catch (e) {
      debugPrint('[VideoPlayerState] 导入字幕字体失败: $e');
    }
  }

  Future<void> setSubtitleOverrideMode(
    SubtitleStyleOverrideMode mode,
  ) async {
    if (_subtitleOverrideMode == mode) return;
    _subtitleOverrideMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_subtitleOverrideModeKey, mode.index);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> resetSubtitleSettings() async {
    _subtitleScale = VideoPlayerState.defaultSubtitleScale;
    _subtitleDelaySeconds = VideoPlayerState.defaultSubtitleDelaySeconds;
    _subtitlePosition = VideoPlayerState.defaultSubtitlePosition;
    _subtitleAlignX = VideoPlayerState.defaultSubtitleAlignX;
    _subtitleAlignY = VideoPlayerState.defaultSubtitleAlignY;
    _subtitleMarginX = VideoPlayerState.defaultSubtitleMarginX;
    _subtitleMarginY = VideoPlayerState.defaultSubtitleMarginY;
    _subtitleOpacity = VideoPlayerState.defaultSubtitleOpacity;
    _subtitleBorderSize = VideoPlayerState.defaultSubtitleBorderSize;
    _subtitleShadowOffset = VideoPlayerState.defaultSubtitleShadowOffset;
    _subtitleBold = false;
    _subtitleItalic = false;
    _subtitleColorValue = VideoPlayerState.defaultSubtitleColorValue;
    _subtitleBorderColorValue = VideoPlayerState.defaultSubtitleBorderColorValue;
    _subtitleShadowColorValue = VideoPlayerState.defaultSubtitleShadowColorValue;
    _subtitleFontName = '';
    _subtitleFontDir = '';
    _subtitleOverrideMode = VideoPlayerState.defaultSubtitleOverrideMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subtitleScaleKey, _subtitleScale);
    await prefs.setDouble(_subtitleDelayKey, _subtitleDelaySeconds);
    await prefs.setDouble(_subtitlePositionKey, _subtitlePosition);
    await prefs.setInt(_subtitleAlignXKey, _subtitleAlignX.index);
    await prefs.setInt(_subtitleAlignYKey, _subtitleAlignY.index);
    await prefs.setDouble(_subtitleMarginXKey, _subtitleMarginX);
    await prefs.setDouble(_subtitleMarginYKey, _subtitleMarginY);
    await prefs.setDouble(_subtitleOpacityKey, _subtitleOpacity);
    await prefs.setDouble(_subtitleBorderSizeKey, _subtitleBorderSize);
    await prefs.setDouble(_subtitleShadowOffsetKey, _subtitleShadowOffset);
    await prefs.setBool(_subtitleBoldKey, _subtitleBold);
    await prefs.setBool(_subtitleItalicKey, _subtitleItalic);
    await prefs.setInt(_subtitleColorKey, _subtitleColorValue);
    await prefs.setInt(_subtitleBorderColorKey, _subtitleBorderColorValue);
    await prefs.setInt(_subtitleShadowColorKey, _subtitleShadowColorValue);
    await prefs.setString(_subtitleFontNameKey, _subtitleFontName);
    await prefs.setString(_subtitleFontDirKey, _subtitleFontDir);
    await prefs.setInt(_subtitleOverrideModeKey, _subtitleOverrideMode.index);
    await applySubtitleStylePreference();
    notifyListeners();
  }

  Future<void> applySubtitleStylePreference() async {
    if (kIsWeb || _isDisposed) return;
    try {
      if (player.getPlayerKernelName() != 'Media Kit') {
        return;
      }
      player.setProperty('sub-scale', _subtitleScale.toStringAsFixed(2));
      player.setProperty('sub-delay', _subtitleDelaySeconds.toStringAsFixed(2));
      player.setProperty('sub-pos', _subtitlePosition.toStringAsFixed(0));
      player.setProperty('sub-align-x', _subtitleAlignXToMpv(_subtitleAlignX));
      player.setProperty('sub-align-y', _subtitleAlignYToMpv(_subtitleAlignY));
      player.setProperty(
        'sub-margin-x',
        _subtitleMarginX.round().toString(),
      );
      player.setProperty(
        'sub-margin-y',
        _subtitleMarginY.round().toString(),
      );
      player.setProperty(
        'sub-opacity',
        _subtitleOpacityToMpv(_subtitleOpacity).toString(),
      );
      player.setProperty(
        'sub-border-size',
        _subtitleBorderSize.toStringAsFixed(1),
      );
      player.setProperty(
        'sub-shadow-offset',
        _subtitleShadowOffset.toStringAsFixed(1),
      );
      player.setProperty('sub-color', _colorToMpvHex(subtitleColor));
      player.setProperty(
        'sub-border-color',
        _colorToMpvHex(subtitleBorderColor),
      );
      player.setProperty(
        'sub-shadow-color',
        _colorToMpvHex(subtitleShadowColor),
      );
      player.setProperty('sub-bold', _subtitleBold ? 'yes' : 'no');
      player.setProperty('sub-italic', _subtitleItalic ? 'yes' : 'no');
      if (_subtitleFontDir.isNotEmpty) {
        player.setProperty('sub-fonts-dir', _subtitleFontDir);
      } else {
        player.setProperty('sub-fonts-dir', '');
      }
      if (_subtitleFontName.isNotEmpty) {
        player.setProperty('sub-font', _subtitleFontName);
      } else {
        player.setProperty('sub-font', '');
      }
      player.setProperty(
        'sub-ass-override',
        _subtitleOverrideModeToMpv(_subtitleOverrideMode),
      );
    } catch (e) {
      debugPrint('[VideoPlayerState] 设置字幕样式失败: $e');
    }
  }

  // 加载弹幕轨道显示区域
  Future<void> _loadDanmakuDisplayArea() async {
    final prefs = await SharedPreferences.getInstance();
    _danmakuDisplayArea = prefs.getDouble(_danmakuDisplayAreaKey) ?? 1.0;
    notifyListeners();
  }

  // 设置弹幕轨道显示区域
  Future<void> setDanmakuDisplayArea(double area) async {
    if (_danmakuDisplayArea != area) {
      _danmakuDisplayArea = area;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_danmakuDisplayAreaKey, area);
      notifyListeners();
    }
  }

  double _normalizeDanmakuSpeed(double value) {
    if (value < _minDanmakuSpeedMultiplier) {
      return _minDanmakuSpeedMultiplier;
    }
    if (value > _maxDanmakuSpeedMultiplier) {
      return _maxDanmakuSpeedMultiplier;
    }
    return value;
  }

  Future<void> _loadDanmakuSpeedMultiplier() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(_danmakuSpeedMultiplierKey);
    _danmakuSpeedMultiplier = _normalizeDanmakuSpeed(stored ?? 1.0);
    notifyListeners();
  }

  Future<void> _loadRememberDanmakuOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = prefs.getBool(_rememberDanmakuOffsetKey) ?? false;
    if (_rememberDanmakuOffset != resolved) {
      _rememberDanmakuOffset = resolved;
      notifyListeners();
    } else {
      _rememberDanmakuOffset = resolved;
    }
  }

  Future<void> setRememberDanmakuOffset(bool remember) async {
    if (_rememberDanmakuOffset == remember) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberDanmakuOffsetKey, remember);
    _rememberDanmakuOffset = remember;
    notifyListeners();
  }

  Future<void> setDanmakuSpeedMultiplier(double multiplier) async {
    final normalized = _normalizeDanmakuSpeed(multiplier);
    if ((_danmakuSpeedMultiplier - normalized).abs() < 0.0001) {
      return;
    }
    _danmakuSpeedMultiplier = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_danmakuSpeedMultiplierKey, normalized);
    notifyListeners();
  }

  // 获取弹幕轨道间距倍数（基于字体大小计算）
  double get danmakuTrackHeightMultiplier {
    // 使用默认的轨道高度倍数1.5，根据字体大小的比例调整
    const double baseMultiplier = 1.5;
    const double baseFontSize = 30.0; // 基准字体大小
    final double currentFontSize = actualDanmakuFontSize;

    // 保持轨道间距与字体大小的比例关系
    return baseMultiplier * (currentFontSize / baseFontSize);
  }

  // 获取当前活跃解码器，代理到解码器管理器
  Future<String> getActiveDecoder() async {
    final decoder = await _decoderManager.getActiveDecoder();
    // 更新系统资源监视器的解码器信息
    SystemResourceMonitor().setActiveDecoder(decoder);
    return decoder;
  }

  // 更新当前活跃解码器信息，代理到解码器管理器
  Future<void> _updateCurrentActiveDecoder() async {
    if (_status == PlayerStatus.playing || _status == PlayerStatus.paused) {
      await _decoderManager.updateCurrentActiveDecoder();
      // 由于DecoderManager的updateCurrentActiveDecoder已经会更新系统资源监视器的解码器信息，这里不需要重复
    }
  }

  // 强制启用硬件解码，代理到解码器管理器
  Future<void> forceEnableHardwareDecoder() async {
    if (_status == PlayerStatus.playing || _status == PlayerStatus.paused) {
      if (!_useHardwareDecoder) {
        return;
      }
      await _decoderManager.forceEnableHardwareDecoder();
      // 稍后检查解码器状态
      await Future.delayed(const Duration(seconds: 1));
      await _updateCurrentActiveDecoder();
    }
  }

  Future<void> _loadScreenshotSaveTarget() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_screenshotSaveTargetKey);
      _screenshotSaveTarget = ScreenshotSaveTargetDisplay.fromPrefs(stored);
      notifyListeners();
    } catch (e) {
      debugPrint('加载截图默认保存位置失败: $e');
    }
  }

  Future<void> setScreenshotSaveTarget(
    ScreenshotSaveTarget target,
  ) async {
    if (kIsWeb) return;
    if (_screenshotSaveTarget == target) return;
    _screenshotSaveTarget = target;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_screenshotSaveTargetKey, target.prefsValue);
    } catch (e) {
      debugPrint('保存截图默认保存位置失败: $e');
    }
    notifyListeners();
  }

  Future<Directory> _getDefaultScreenshotSaveDirectory() async {
    if (!kIsWeb && Platform.isMacOS) {
      // macOS 沙盒默认使用应用内部 downloads 目录，避免权限/签名问题。
      return StorageService.getDownloadsDirectory();
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      try {
        final dir = await path_provider.getDownloadsDirectory();
        if (dir != null) return dir;
      } catch (e) {
        debugPrint('获取系统下载目录失败，将回退到应用下载目录: $e');
      }
    }

    return StorageService.getDownloadsDirectory();
  }

  Future<void> _loadScreenshotSaveDirectory() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_screenshotSaveDirectoryKey)?.trim();

      String? resolved = saved;
      if (resolved != null && resolved.isNotEmpty && Platform.isMacOS) {
        resolved = await SecurityBookmarkService.resolveBookmark(resolved) ??
            resolved;
      }

      if (resolved == null || resolved.isEmpty) {
        final defaultDir = await _getDefaultScreenshotSaveDirectory();
        resolved = defaultDir.path;
      }

      try {
        final directory = Directory(resolved);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
      } catch (e) {
        debugPrint('创建截图目录失败，将回退到默认下载目录: $e');
        resolved = (await StorageService.getDownloadsDirectory()).path;
      }

      _screenshotSaveDirectory = resolved;
      notifyListeners();
    } catch (e) {
      debugPrint('加载截图保存位置失败: $e');
    }
  }

  Future<void> setScreenshotSaveDirectory(String? directoryPath) async {
    if (kIsWeb) return;

    final String? trimmed = directoryPath?.trim();
    final prefs = await SharedPreferences.getInstance();

    if (trimmed == null || trimmed.isEmpty) {
      await prefs.remove(_screenshotSaveDirectoryKey);
      final defaultDir = await _getDefaultScreenshotSaveDirectory();
      _screenshotSaveDirectory = defaultDir.path;
      notifyListeners();
      return;
    }

    String resolvedPath = trimmed;
    if (Platform.isMacOS) {
      // 确保创建书签，且当前会话开始访问该目录
      await SecurityBookmarkService.createBookmark(resolvedPath);
      resolvedPath =
          await SecurityBookmarkService.resolveBookmark(resolvedPath) ??
              resolvedPath;
    }

    try {
      final directory = Directory(resolvedPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } catch (e) {
      debugPrint('创建截图目录失败: $e');
    }

    await prefs.setString(_screenshotSaveDirectoryKey, resolvedPath);
    _screenshotSaveDirectory = resolvedPath;
    notifyListeners();
  }
}
