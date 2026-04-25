part of video_player_state;

extension VideoPlayerStateSubtitles on VideoPlayerState {
  // 更新指定的字幕轨道信息
  void _updateSubtitleTracksInfo(int trackIndex) {
    if (player.mediaInfo.subtitle == null ||
        trackIndex >= player.mediaInfo.subtitle!.length) {
      return;
    }

    final track = player.mediaInfo.subtitle![trackIndex];
    // 尝试从track中提取title和language
    String title = '轨道 $trackIndex';
    String language = '未知';

    final fullString = track.toString();
    if (fullString.contains('metadata: {')) {
      final metadataStart =
          fullString.indexOf('metadata: {') + 'metadata: {'.length;
      final metadataEnd = fullString.indexOf('}', metadataStart);

      if (metadataEnd > metadataStart) {
        final metadataStr = fullString.substring(metadataStart, metadataEnd);

        // 提取title
        final titleMatch = RegExp(r'title: ([^,}]+)').firstMatch(metadataStr);
        if (titleMatch != null) {
          title = titleMatch.group(1)?.trim() ?? title;
        }

        // 提取language
        final languageMatch =
            RegExp(r'language: ([^,}]+)').firstMatch(metadataStr);
        if (languageMatch != null) {
          language = languageMatch.group(1)?.trim() ?? language;
          // 获取映射后的语言名称
          language = getSubtitleLanguageName(language);
        }
      }
    }

    // 更新VideoPlayerState的字幕轨道信息
    _subtitleManager.updateSubtitleTrackInfo('embedded_subtitle_$trackIndex', {
      'index': trackIndex,
      'title': title,
      'language': language,
      'isActive': player.activeSubtitleTracks.contains(trackIndex)
    });

    // 清除外部字幕信息的激活状态
    if (_subtitleManager.currentExternalSubtitlePath == null &&
        player.activeSubtitleTracks.contains(trackIndex) &&
        _subtitleManager.subtitleTrackInfo.containsKey('external_subtitle')) {
      _subtitleManager
          .updateSubtitleTrackInfo('external_subtitle', {'isActive': false});
    }
  }

  // 更新所有字幕轨道信息
  void _updateAllSubtitleTracksInfo() {
    if (player.mediaInfo.subtitle == null) {
      return;
    }

    // 清除之前的内嵌字幕轨道信息
    for (final key in List.from(_subtitleManager.subtitleTrackInfo.keys)) {
      if (key.startsWith('embedded_subtitle_')) {
        _subtitleManager.subtitleTrackInfo.remove(key);
      }
    }

    // 更新所有内嵌字幕轨道信息
    for (var i = 0; i < player.mediaInfo.subtitle!.length; i++) {
      _updateSubtitleTracksInfo(i);
    }

    // 在更新完成后检查当前激活的字幕轨道并确保相应的信息被更新
    if (player.activeSubtitleTracks.isNotEmpty &&
        _subtitleManager.currentExternalSubtitlePath == null) {
      final activeIndex = player.activeSubtitleTracks.first;
      if (activeIndex >= 0 && activeIndex < player.mediaInfo.subtitle!.length) {
        // 激活的是内嵌字幕轨道
        _subtitleManager.updateSubtitleTrackInfo('embedded_subtitle', {
          'index': activeIndex,
          'title': player.mediaInfo.subtitle![activeIndex].toString(),
          'isActive': true,
        });

        // 通知字幕轨道变化
        _subtitleManager.onSubtitleTrackChanged();
      }
    }

    _notifyListeners();
  }

  // 设置当前外部字幕路径
  void setCurrentExternalSubtitlePath(String path) {
    _subtitleManager.setCurrentExternalSubtitlePath(path);
    //debugPrint('设置当前外部字幕路径: $path');
  }

  // 设置外部字幕并更新路径
  void setExternalSubtitle(String path, {bool isManualSetting = false}) {
    _subtitleManager.setExternalSubtitle(path,
        isManualSetting: isManualSetting);
    _notifyListeners();
  }

  // 强制设置外部字幕（手动操作）
  void forceSetExternalSubtitle(String path) {
    _subtitleManager.forceSetExternalSubtitle(path);
    _notifyListeners();
  }

  // 桥接方法：预加载字幕文件
  Future<void> preloadSubtitleFile(String path) async {
    await _subtitleManager.preloadSubtitleFile(path);
  }

  // 桥接方法：获取当前活跃的外部字幕文件路径
  String? getActiveExternalSubtitlePath() {
    return _subtitleManager.getActiveExternalSubtitlePath();
  }

  // 桥接方法：获取当前显示的字幕文本
  String getCurrentSubtitleText() {
    return _subtitleManager.getCurrentSubtitleText();
  }

  // 桥接方法：判断当前外挂字幕是否使用应用内叠层渲染
  bool shouldRenderCurrentExternalSubtitleInApp() {
    return _subtitleManager.shouldRenderCurrentExternalSubtitleInApp();
  }

  // 桥接方法：获取指定时间点的外挂字幕文本
  String getCurrentExternalSubtitleTextAt(int positionMs) {
    return _subtitleManager.getCurrentExternalSubtitleTextAt(positionMs);
  }

  // 桥接方法：当字幕轨道改变时调用
  void onSubtitleTrackChanged() {
    _subtitleManager.onSubtitleTrackChanged();
  }

  // 桥接方法：获取缓存的字幕内容
  List<dynamic>? getCachedSubtitle(String path) {
    return _subtitleManager.getCachedSubtitle(path);
  }

  // 桥接方法：获取弹幕/字幕轨道信息
  Map<String, Map<String, dynamic>> get danmakuTrackInfo =>
      _subtitleManager.subtitleTrackInfo;

  // 桥接方法：更新弹幕/字幕轨道信息
  void updateDanmakuTrackInfo(String key, Map<String, dynamic> info) {
    _subtitleManager.updateSubtitleTrackInfo(key, info);
  }

  // 桥接方法：清除弹幕/字幕轨道信息
  void clearDanmakuTrackInfo() {
    _subtitleManager.clearSubtitleTrackInfo();
  }

  // 自动检测并加载同名字幕文件
  Future<void> _autoDetectAndLoadSubtitle(String videoPath) async {
    // 此方法不再需要，我们使用subtitleManager的方法代替
    await _subtitleManager.autoDetectAndLoadSubtitle(videoPath);
  }

  // 加载顶部弹幕屏蔽设置
  Future<void> _loadBlockTopDanmaku() async {
    final prefs = await SharedPreferences.getInstance();
    _blockTopDanmaku = prefs.getBool(_blockTopDanmakuKey) ?? false;
    _notifyListeners();
  }

  // 设置顶部弹幕屏蔽
  Future<void> setBlockTopDanmaku(bool block) async {
    if (_blockTopDanmaku != block) {
      _blockTopDanmaku = block;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_blockTopDanmakuKey, block);
      _updateMergedDanmakuList();
    }
  }

  // 加载底部弹幕屏蔽设置
  Future<void> _loadBlockBottomDanmaku() async {
    final prefs = await SharedPreferences.getInstance();
    _blockBottomDanmaku = prefs.getBool(_blockBottomDanmakuKey) ?? false;
    _notifyListeners();
  }

  // 设置底部弹幕屏蔽
  Future<void> setBlockBottomDanmaku(bool block) async {
    if (_blockBottomDanmaku != block) {
      _blockBottomDanmaku = block;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_blockBottomDanmakuKey, block);
      _updateMergedDanmakuList();
    }
  }

  // 加载滚动弹幕屏蔽设置
  Future<void> _loadBlockScrollDanmaku() async {
    final prefs = await SharedPreferences.getInstance();
    _blockScrollDanmaku = prefs.getBool(_blockScrollDanmakuKey) ?? false;
    _notifyListeners();
  }

  // 设置滚动弹幕屏蔽
  Future<void> setBlockScrollDanmaku(bool block) async {
    if (_blockScrollDanmaku != block) {
      _blockScrollDanmaku = block;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_blockScrollDanmakuKey, block);
      _updateMergedDanmakuList();
    }
  }

  // 加载弹幕屏蔽词列表
  Future<void> _loadDanmakuBlockWords() async {
    final prefs = await SharedPreferences.getInstance();
    final blockWordsJson = prefs.getString(_danmakuBlockWordsKey);
    if (blockWordsJson != null && blockWordsJson.isNotEmpty) {
      try {
        final List<dynamic> decodedList = json.decode(blockWordsJson);
        _danmakuBlockWords = decodedList.map((e) => e.toString()).toList();
      } catch (e) {
        debugPrint('加载弹幕屏蔽词失败: $e');
        _danmakuBlockWords = [];
      }
    } else {
      _danmakuBlockWords = [];
    }
    _notifyListeners();
  }

  String _normalizeSpoilerMatchText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _loadSpoilerPreventionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _spoilerPreventionEnabled =
        prefs.getBool(_spoilerPreventionEnabledKey) ?? false;
    _notifyListeners();
  }

  Future<void> setSpoilerPreventionEnabled(bool enabled) async {
    if (_spoilerPreventionEnabled == enabled) {
      return;
    }
    if (enabled && !spoilerAiConfigReady) {
      debugPrint('[防剧透] 未配置AI接口，无法启用防剧透模式');
      return;
    }
    _spoilerPreventionEnabled = enabled;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_spoilerPreventionEnabledKey, enabled);

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

    _updateMergedDanmakuList();
  }

  SpoilerAiApiFormat _parseSpoilerAiApiFormat(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'gemini':
        return SpoilerAiApiFormat.gemini;
      case 'openai':
      default:
        return SpoilerAiApiFormat.openai;
    }
  }

  String _spoilerAiApiFormatToPrefs(SpoilerAiApiFormat format) {
    switch (format) {
      case SpoilerAiApiFormat.gemini:
        return 'gemini';
      case SpoilerAiApiFormat.openai:
        return 'openai';
    }
  }

  void _resetSpoilerDanmakuAnalysisForConfigChange() {
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
  }

  Future<void> _loadSpoilerAiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUseCustomKey = prefs.getBool(_spoilerAiUseCustomKeyKey);
    if (storedUseCustomKey != true) {
      _spoilerAiUseCustomKey = true;
      await prefs.setBool(_spoilerAiUseCustomKeyKey, true);
    } else {
      _spoilerAiUseCustomKey = true;
    }
    _spoilerAiApiFormat =
        _parseSpoilerAiApiFormat(prefs.getString(_spoilerAiApiFormatKey));
    _spoilerAiApiUrl = prefs.getString(_spoilerAiApiUrlKey) ?? '';
    _spoilerAiApiKey = prefs.getString(_spoilerAiApiKeyKey) ?? '';
    _spoilerAiModel = prefs.getString(_spoilerAiModelKey) ?? 'gpt-5';
    final temp = prefs.getDouble(_spoilerAiTemperatureKey) ?? 0.5;
    _spoilerAiTemperature = temp.clamp(0.0, 2.0).toDouble();
    _spoilerAiDebugPrintResponse =
        prefs.getBool(_spoilerAiDebugPrintResponseKey) ?? false;
    if (_spoilerPreventionEnabled && !spoilerAiConfigReady) {
      _spoilerPreventionEnabled = false;
      await prefs.setBool(_spoilerPreventionEnabledKey, false);
    }
    _notifyListeners();
  }

  Future<void> updateSpoilerAiSettings({
    bool? useCustomKey,
    SpoilerAiApiFormat? apiFormat,
    String? apiUrl,
    String? apiKey,
    String? model,
    double? temperature,
    bool? debugPrintResponse,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    bool shouldRestartAnalysis = false;
    bool changed = false;

    if (useCustomKey != null && _spoilerAiUseCustomKey != true) {
      _spoilerAiUseCustomKey = true;
      await prefs.setBool(_spoilerAiUseCustomKeyKey, true);
      changed = true;
      shouldRestartAnalysis = true;
    }

    if (apiFormat != null && _spoilerAiApiFormat != apiFormat) {
      _spoilerAiApiFormat = apiFormat;
      await prefs.setString(
        _spoilerAiApiFormatKey,
        _spoilerAiApiFormatToPrefs(apiFormat),
      );
      changed = true;
      shouldRestartAnalysis = true;
    }

    if (apiUrl != null && _spoilerAiApiUrl != apiUrl) {
      _spoilerAiApiUrl = apiUrl;
      await prefs.setString(_spoilerAiApiUrlKey, apiUrl);
      changed = true;
      shouldRestartAnalysis = true;
    }

    if (apiKey != null && _spoilerAiApiKey != apiKey) {
      _spoilerAiApiKey = apiKey;
      await prefs.setString(_spoilerAiApiKeyKey, apiKey);
      changed = true;
      shouldRestartAnalysis = true;
    }

    if (model != null && _spoilerAiModel != model) {
      _spoilerAiModel = model;
      await prefs.setString(_spoilerAiModelKey, model);
      changed = true;
      shouldRestartAnalysis = true;
    }

    if (temperature != null) {
      final resolved = temperature.clamp(0.0, 2.0).toDouble();
      if ((_spoilerAiTemperature - resolved).abs() > 0.0001) {
        _spoilerAiTemperature = resolved;
        await prefs.setDouble(_spoilerAiTemperatureKey, resolved);
        changed = true;
        shouldRestartAnalysis = true;
      }
    }

    if (debugPrintResponse != null &&
        _spoilerAiDebugPrintResponse != debugPrintResponse) {
      _spoilerAiDebugPrintResponse = debugPrintResponse;
      await prefs.setBool(_spoilerAiDebugPrintResponseKey, debugPrintResponse);
      changed = true;
    }

    if (!changed) {
      return;
    }

    if (shouldRestartAnalysis) {
      _resetSpoilerDanmakuAnalysisForConfigChange();
      if (_spoilerPreventionEnabled) {
        _updateMergedDanmakuList();
        return;
      }
    }

    _notifyListeners();
  }

  Future<void> setSpoilerAiUseCustomKey(bool enabled) async {
    await updateSpoilerAiSettings(useCustomKey: true);
  }

  Future<void> setSpoilerAiApiFormat(SpoilerAiApiFormat format) async {
    await updateSpoilerAiSettings(apiFormat: format);
  }

  Future<void> setSpoilerAiApiUrl(String url) async {
    await updateSpoilerAiSettings(apiUrl: url);
  }

  Future<void> setSpoilerAiApiKey(String apiKey) async {
    await updateSpoilerAiSettings(apiKey: apiKey);
  }

  Future<void> setSpoilerAiModel(String model) async {
    await updateSpoilerAiSettings(model: model);
  }

  Future<void> setSpoilerAiTemperature(double temperature) async {
    await updateSpoilerAiSettings(temperature: temperature);
  }

  Future<void> setSpoilerAiDebugPrintResponse(bool enabled) async {
    await updateSpoilerAiSettings(debugPrintResponse: enabled);
  }

  // 添加弹幕屏蔽词
  Future<void> addDanmakuBlockWord(String word) async {
    if (word.isNotEmpty && !_danmakuBlockWords.contains(word)) {
      _danmakuBlockWords.add(word);
      await _saveDanmakuBlockWords();
      _updateMergedDanmakuList();
    }
  }

  // 移除弹幕屏蔽词
  Future<void> removeDanmakuBlockWord(String word) async {
    if (_danmakuBlockWords.contains(word)) {
      _danmakuBlockWords.remove(word);
      await _saveDanmakuBlockWords();
      _updateMergedDanmakuList();
    }
  }

  // 保存弹幕屏蔽词列表
  Future<void> _saveDanmakuBlockWords() async {
    final prefs = await SharedPreferences.getInstance();
    final blockWordsJson = json.encode(_danmakuBlockWords);
    await prefs.setString(_danmakuBlockWordsKey, blockWordsJson);
  }

  // 检查是否是正则表达式规则格式: 规则名称/表达式/
  bool _isRegexRule(String word) {
    if (!word.contains('/')) return false;
    final parts = word.split('/');
    return parts.length >= 3 && parts.first.isNotEmpty && parts.last.isEmpty;
  }

  // 解析正则表达式规则，返回 (规则名称, 正则表达式)
  (String, String)? _parseRegexRule(String word) {
    if (!_isRegexRule(word)) return null;
    final firstSlash = word.indexOf('/');
    final name = word.substring(0, firstSlash);
    final pattern = word.substring(firstSlash + 1, word.length - 1);
    return (name, pattern);
  }

  // 检查弹幕是否应该被屏蔽
  bool shouldBlockDanmaku(Map<String, dynamic> danmaku) {
    final String type = danmaku['type']?.toString() ?? '';
    final String content = danmaku['content']?.toString() ?? '';

    if (_blockTopDanmaku && type == 'top') return true;
    if (_blockBottomDanmaku && type == 'bottom') return true;
    if (_blockScrollDanmaku && type == 'scroll') return true;

    if (_spoilerPreventionEnabled && _spoilerDanmakuTexts.isNotEmpty) {
      final normalizedContent = _normalizeSpoilerMatchText(content);
      if (normalizedContent.isNotEmpty &&
          _spoilerDanmakuTexts.contains(normalizedContent)) {
        return true;
      }
    }

    for (final word in _danmakuBlockWords) {
      if (_isRegexRule(word)) {
        final parsed = _parseRegexRule(word);
        if (parsed != null) {
          final (_, pattern) = parsed;
          try {
            final regex = RegExp(pattern);
            if (regex.hasMatch(content)) {
              return true;
            }
          } catch (e) {
            debugPrint('正则表达式规则无效: $pattern, 错误: $e');
          }
        }
      } else {
        if (content.contains(word)) {
          return true;
        }
      }
    }
    return false;
  }
}
