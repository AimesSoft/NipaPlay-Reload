part of video_player_state;

extension VideoPlayerStateSubtitles on VideoPlayerState {
  // 获取字幕轨道的语言名称
  String _getLanguageName(String language) {
    // 语言代码映射
    final Map<String, String> languageCodes = {
      'chi': '中文',
      'eng': '英文',
      'jpn': '日语',
      'kor': '韩语',
      'fra': '法语',
      'deu': '德语',
      'spa': '西班牙语',
      'ita': '意大利语',
      'rus': '俄语',
    };

    // 常见的语言标识符
    final Map<String, String> languagePatterns = {
      r'chi|chs|zh|中文|简体|繁体|chi.*?simplified|chinese': '中文',
      r'eng|en|英文|english': '英文',
      r'jpn|ja|日文|japanese': '日语',
      r'kor|ko|韩文|korean': '韩语',
      r'fra|fr|法文|french': '法语',
      r'ger|de|德文|german': '德语',
      r'spa|es|西班牙文|spanish': '西班牙语',
      r'ita|it|意大利文|italian': '意大利语',
      r'rus|ru|俄文|russian': '俄语',
    };

    // 首先检查语言代码映射
    final mappedLanguage = languageCodes[language.toLowerCase()];
    if (mappedLanguage != null) {
      return mappedLanguage;
    }

    // 然后检查语言标识符
    for (final entry in languagePatterns.entries) {
      final pattern = RegExp(entry.key, caseSensitive: false);
      if (pattern.hasMatch(language.toLowerCase())) {
        return entry.value;
      }
    }

    return language;
  }

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
          language = _getLanguageName(language);
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
    if (player.activeSubtitleTracks.contains(trackIndex) &&
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
    if (player.activeSubtitleTracks.isNotEmpty) {
      final activeIndex = player.activeSubtitleTracks.first;
      if (activeIndex > 0 && activeIndex <= player.mediaInfo.subtitle!.length) {
        // 激活的是内嵌字幕轨道
        _subtitleManager.updateSubtitleTrackInfo('embedded_subtitle', {
          'index': activeIndex - 1, // MDK 字幕轨道从 1 开始，而我们的索引从 0 开始
          'title': player.mediaInfo.subtitle![activeIndex - 1].toString(),
          'isActive': true,
        });

        // 通知字幕轨道变化
        _subtitleManager.onSubtitleTrackChanged();
      }
    }

    notifyListeners();
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
  }

  // 强制设置外部字幕（手动操作）
  void forceSetExternalSubtitle(String path) {
    _subtitleManager.forceSetExternalSubtitle(path);
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
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

  // 检查弹幕是否应该被屏蔽
  bool shouldBlockDanmaku(Map<String, dynamic> danmaku) {
    final String type = danmaku['type']?.toString() ?? '';
    final String content = danmaku['content']?.toString() ?? '';

    if (_blockTopDanmaku && type == 'top') return true;
    if (_blockBottomDanmaku && type == 'bottom') return true;
    if (_blockScrollDanmaku && type == 'scroll') return true;

    for (final word in _danmakuBlockWords) {
      if (content.contains(word)) {
        return true;
      }
    }
    return false;
  }
}
