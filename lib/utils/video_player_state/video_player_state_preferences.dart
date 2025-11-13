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
        _currentVideoPath = null; // 清空路径，避免重复初始化
        _danmakuOverlayKey = 'idle'; // 临时重置弹幕覆盖层key
        await Future.delayed(const Duration(seconds: 1)); // 等待一秒
        await initializePlayer(path);
      } else {
        _setStatus(PlayerStatus.idle, message: '请重新选择视频');
      }
    } catch (e) {
      //debugPrint('恢复播放失败: $e');
      _setStatus(PlayerStatus.idle, message: '播放器恢复失败，请重新选择视频');
    }
  }

  // 加载控制栏高度
  Future<void> _loadControlBarHeight() async {
    final prefs = await SharedPreferences.getInstance();
    _controlBarHeight = prefs.getDouble(_controlBarHeightKey) ?? 20.0;
    notifyListeners();
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

  // 保存控制栏高度
  Future<void> setControlBarHeight(double height) async {
    _controlBarHeight = height;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_controlBarHeightKey, height);
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

  // 播放速度相关方法

  // 加载播放速度设置
  Future<void> _loadPlaybackRate() async {
    final prefs = await SharedPreferences.getInstance();
    _playbackRate = prefs.getDouble(_playbackRateKey) ?? 1.0; // 默认1倍速
    _speedBoostRate = prefs.getDouble(_speedBoostRateKey) ?? 2.0; // 默认2倍速
    _normalPlaybackRate = 1.0; // 始终重置为1.0
    notifyListeners();
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
      await applyAnime4KProfileToCurrentPlayer();
      return;
    }

    _anime4kProfile = profile;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_anime4kProfileKey, profile.index);
    } catch (e) {
      debugPrint('[VideoPlayerState] 保存 Anime4K 设置失败: $e');
    }

    await applyAnime4KProfileToCurrentPlayer();
    notifyListeners();
  }

  Future<void> applyAnime4KProfileToCurrentPlayer() async {
    if (!_supportsAnime4KForCurrentPlayer()) {
      _anime4kShaderPaths = const <String>[];
      return;
    }

    if (_anime4kProfile == Anime4KProfile.off) {
      _anime4kShaderPaths = const <String>[];
      _applyAnime4KMpvTuning(enable: false);
      try {
        player.setProperty('glsl-shaders', '');
      } catch (e) {
        debugPrint('[VideoPlayerState] 清除 Anime4K 着色器失败: $e');
      }
      await _updateAnime4KSurfaceScale(enable: false);
      await _logCurrentVideoDimensions(context: 'Anime4K off');
      return;
    }

    try {
      final List<String> shaderPaths =
          await Anime4KShaderManager.getShaderPathsForProfile(
        _anime4kProfile,
      );
      _anime4kShaderPaths = List.unmodifiable(shaderPaths);
      final String propertyValue =
          Anime4KShaderManager.buildMpvShaderList(shaderPaths);
      _applyAnime4KMpvTuning(enable: true);
      player.setProperty('glsl-shaders', propertyValue);
      debugPrint(
        '[VideoPlayerState] Anime4K 着色器已应用: $propertyValue',
      );
      try {
        final String? currentValue = player.getProperty('glsl-shaders');
        debugPrint(
          '[VideoPlayerState] Anime4K 当前播放器属性: ${currentValue ?? '<null>'}',
        );
      } catch (e) {
        debugPrint('[VideoPlayerState] 读取 Anime4K 属性失败: $e');
      }
      await _updateAnime4KSurfaceScale(enable: true);
      await _logCurrentVideoDimensions(
        context: 'Anime4K ${_anime4kProfile.name}',
      );
    } catch (e) {
      debugPrint('[VideoPlayerState] 应用 Anime4K 着色器失败: $e');
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
    final Map<String, String> options =
        enable ? _anime4kRecommendedMpvOptions : _anime4kDefaultMpvOptions;
    options.forEach((String key, String value) {
      try {
        player.setProperty(key, value);
        debugPrint('[VideoPlayerState] Anime4K 调整 $key=$value');
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

      debugPrint(
        '[VideoPlayerState] Anime4K 分辨率$contextLabel 源=$srcLabel, 输出=$dispLabel',
      );
    } catch (e) {
      debugPrint('[VideoPlayerState] Anime4K 分辨率日志失败: $e');
    }
  }

  Future<void> _updateAnime4KSurfaceScale({
    required bool enable,
    int retry = 0,
  }) async {
    const int maxRetry = 10;

    try {
      if (!enable) {
        await player.setVideoSurfaceSize();
        debugPrint('[VideoPlayerState] Anime4K 纹理尺寸恢复为自动');
        return;
      }

      final double factor = _anime4kScaleFactorForProfile(_anime4kProfile);
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

      if (snapshot.displayWidth == targetWidth &&
          snapshot.displayHeight == targetHeight) {
        // 已经是目标尺寸
        return;
      }

      await player.setVideoSurfaceSize(
        width: targetWidth,
        height: targetHeight,
      );
      debugPrint(
        '[VideoPlayerState] Anime4K 纹理尺寸调整为 ${targetWidth}x$targetHeight',
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
      await _decoderManager.forceEnableHardwareDecoder();
      // 稍后检查解码器状态
      await Future.delayed(const Duration(seconds: 1));
      await _updateCurrentActiveDecoder();
    }
  }
}
