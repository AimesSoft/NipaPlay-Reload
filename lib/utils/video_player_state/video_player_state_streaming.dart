part of video_player_state;

extension VideoPlayerStateStreaming on VideoPlayerState {
  void _logMacOSHdrExitTrace(String message) {
    if (!kIsWeb &&
        Platform.isMacOS &&
        Platform.environment['NIPAPLAY_MACOS_HDR_EXIT_TRACE'] == '1') {
      debugPrint('[HDRExit][VideoState] $message');
    }
  }

  bool hasJellyfinServerSubtitleSelection(String itemId) {
    return _jellyfinServerSubtitleSelections.containsKey(itemId);
  }

  int? getJellyfinServerSubtitleSelection(String itemId) {
    if (!_jellyfinServerSubtitleSelections.containsKey(itemId)) {
      return null;
    }
    return _jellyfinServerSubtitleSelections[itemId];
  }

  bool getJellyfinServerSubtitleBurnIn(String itemId) {
    return _jellyfinServerSubtitleBurnInSelections[itemId] ?? false;
  }

  void setJellyfinServerSubtitleSelection(String itemId, int? subtitleIndex,
      {bool burnIn = false}) {
    _jellyfinServerSubtitleSelections[itemId] = subtitleIndex;
    _jellyfinServerSubtitleBurnInSelections[itemId] = burnIn;
  }

  bool hasEmbyServerSubtitleSelection(String itemId) {
    return _embyServerSubtitleSelections.containsKey(itemId);
  }

  int? getEmbyServerSubtitleSelection(String itemId) {
    if (!_embyServerSubtitleSelections.containsKey(itemId)) {
      return null;
    }
    return _embyServerSubtitleSelections[itemId];
  }

  bool getEmbyServerSubtitleBurnIn(String itemId) {
    return _embyServerSubtitleBurnInSelections[itemId] ?? false;
  }

  void setEmbyServerSubtitleSelection(String itemId, int? subtitleIndex,
      {bool burnIn = false}) {
    _embyServerSubtitleSelections[itemId] = subtitleIndex;
    _embyServerSubtitleBurnInSelections[itemId] = burnIn;
  }

  // 添加返回按钮处理
  Future<bool> handleBackButton() async {
    if (_isFullscreen) {
      _logMacOSHdrExitTrace('handleBackButton fullscreen=true');
      await toggleFullscreen();
      return false; // 不退出应用
    } else {
      _logMacOSHdrExitTrace(
        'handleBackButton start path=$_currentVideoPath status=$_status hasVideo=$hasVideo playerState=${player.state}',
      );
      // 在允许播放器重置前完成截图，避免截图与 native surface 拆除并发。
      await _captureConditionalScreenshot("返回按钮时");

      // 退出视频播放时触发自动云同步
      if (_currentVideoPath != null) {
        try {
          await AutoSyncService.instance.syncOnPlaybackEnd();
          debugPrint('退出视频播放时云同步成功');
        } catch (e) {
          debugPrint('退出视频播放时云同步失败: $e');
        }
      }

      _logMacOSHdrExitTrace(
        'handleBackButton done path=$_currentVideoPath status=$_status hasVideo=$hasVideo playerState=${player.state}',
      );
      return true; // 允许返回
    }
  }

  // 条件性截图方法
  Future<void> _captureConditionalScreenshot(String triggerEvent) async {
    if (_currentVideoPath == null || !hasVideo || _isCapturingFrame) {
      _logMacOSHdrExitTrace(
        'capture skip trigger=$triggerEvent path=$_currentVideoPath hasVideo=$hasVideo isCapturing=$_isCapturingFrame playerState=${player.state}',
      );
      return;
    }

    _isCapturingFrame = true;
    _logMacOSHdrExitTrace(
      'capture start trigger=$triggerEvent path=$_currentVideoPath status=$_status playerState=${player.state}',
    );
    try {
      String? newThumbnailPath = await _captureVideoFrameWithoutPausing();
      if (newThumbnailPath == null && player.state == PlaybackState.paused) {
        newThumbnailPath = await captureVideoFrame();
      }
      if (newThumbnailPath != null) {
        _currentThumbnailPath = newThumbnailPath;
        debugPrint('条件截图完成($triggerEvent): $_currentThumbnailPath');

        // 更新观看记录中的缩略图
        await _updateWatchHistoryWithNewThumbnail(newThumbnailPath);

        // 截图后检查解码器状态
        await _decoderManager.checkDecoderAfterScreenshot();
      }
      _logMacOSHdrExitTrace(
        'capture end trigger=$triggerEvent thumbnail=$newThumbnailPath status=$_status playerState=${player.state}',
      );
    } catch (e) {
      debugPrint('条件截图失败($triggerEvent): $e');
      _logMacOSHdrExitTrace(
        'capture error trigger=$triggerEvent error=$e status=$_status playerState=${player.state}',
      );
    } finally {
      _isCapturingFrame = false;
    }
  }

  // 处理流媒体URL的加载错误
  Future<void> _handleStreamUrlLoadingError(
      String videoPath, Exception e) async {
    debugPrint('流媒体URL加载失败: $videoPath, 错误: $e');

    // 检查是否为流媒体 URL
    if (videoPath.contains('jellyfin') || videoPath.contains('/Videos/')) {
      _setStatus(PlayerStatus.error, message: 'Jellyfin流媒体加载失败，请检查网络连接');
      _error = '无法连接到Jellyfin服务器，请确保网络连接正常';
    } else if (videoPath.contains('emby') ||
        videoPath.contains('/emby/Videos/')) {
      _setStatus(PlayerStatus.error, message: 'Emby流媒体加载失败，请检查网络连接');
      _error = '无法连接到Emby服务器，请确保网络连接正常';
    } else {
      _setStatus(PlayerStatus.error, message: '流媒体加载失败，请检查网络连接');
      _error = '无法加载流媒体，请检查URL和网络连接';
    }

    // 通知监听器
    _notifyListeners();
  }

  /// 加载Jellyfin外挂字幕
  Future<void> _loadJellyfinExternalSubtitles(String videoPath) async {
    try {
      final itemId = videoPath.replaceFirst('jellyfin://', '');
      debugPrint('[Jellyfin字幕] 开始加载外挂字幕，itemId: $itemId');
      final subtitleTracks =
          await JellyfinService.instance.getSubtitleTracks(itemId);
      if (subtitleTracks.isEmpty) {
        debugPrint('[Jellyfin字幕] 未找到字幕轨道');
        return;
      }
      final externalSubtitles = subtitleTracks
          .where((track) => track['type'] == 'external')
          .map((track) => Map<String, dynamic>.from(track))
          .toList();
      if (externalSubtitles.isEmpty) {
        debugPrint('[Jellyfin字幕] 未找到外挂字幕轨道');
        return;
      }
      await _loadStreamingExternalSubtitles(
        videoPath: videoPath,
        sourceLabel: 'Jellyfin字幕',
        itemId: itemId,
        externalSubtitles: externalSubtitles,
        subtitleDownloader: (subtitleIndex, subtitleCodec) => JellyfinService
            .instance
            .downloadSubtitleFile(itemId, subtitleIndex, subtitleCodec),
      );
    } catch (e) {
      debugPrint('[Jellyfin字幕] 加载外挂字幕时出错: $e');
    }
  }

  /// 加载Emby外挂字幕
  Future<void> _loadEmbyExternalSubtitles(String videoPath) async {
    try {
      final itemId = videoPath.replaceFirst('emby://', '');
      debugPrint('[Emby字幕] 开始加载外挂字幕，itemId: $itemId');
      final subtitleTracks =
          await EmbyService.instance.getSubtitleTracks(itemId);
      if (subtitleTracks.isEmpty) {
        debugPrint('[Emby字幕] 未找到字幕轨道');
        return;
      }
      final externalSubtitles = subtitleTracks
          .where((track) => track['type'] == 'external')
          .map((track) => Map<String, dynamic>.from(track))
          .toList();
      if (externalSubtitles.isEmpty) {
        debugPrint('[Emby字幕] 未找到外挂字幕轨道');
        return;
      }
      await _loadStreamingExternalSubtitles(
        videoPath: videoPath,
        sourceLabel: 'Emby字幕',
        itemId: itemId,
        externalSubtitles: externalSubtitles,
        subtitleDownloader: (subtitleIndex, subtitleCodec) => EmbyService
            .instance
            .downloadSubtitleFile(itemId, subtitleIndex, subtitleCodec),
      );
    } catch (e) {
      debugPrint('[Emby字幕] 加载外挂字幕时出错: $e');
    }
  }

  Future<void> _loadStreamingExternalSubtitles({
    required String videoPath,
    required String sourceLabel,
    required String itemId,
    required List<Map<String, dynamic>> externalSubtitles,
    required Future<String?> Function(int subtitleIndex, String subtitleCodec)
        subtitleDownloader,
  }) async {
    debugPrint('[$sourceLabel] 找到 ${externalSubtitles.length} 个外挂字幕轨道');

    final preferredSubtitle =
        _selectPreferredStreamingSubtitle(externalSubtitles);
    final preferredIndex = preferredSubtitle['index'];
    final preferredCodec = preferredSubtitle['codec']?.toString();
    final preferredTitle = preferredSubtitle['title'];
    debugPrint(
      '[$sourceLabel] 优先字幕轨道: $preferredTitle (索引: $preferredIndex, 格式: $preferredCodec)',
    );

    final downloadedSubtitles = <Map<String, dynamic>>[];
    String? activeSubtitlePath;

    for (final track in externalSubtitles) {
      final subtitleIndex = track['index'];
      final subtitleCodec = track['codec']?.toString().trim();
      if (subtitleIndex is! int ||
          subtitleCodec == null ||
          subtitleCodec.isEmpty) {
        debugPrint('[$sourceLabel] 跳过无效字幕轨道: $track');
        continue;
      }

      final subtitleFilePath =
          await subtitleDownloader(subtitleIndex, subtitleCodec);
      if (subtitleFilePath == null || subtitleFilePath.isEmpty) {
        debugPrint(
          '[$sourceLabel] 字幕轨道下载失败: ${track['title']} (索引: $subtitleIndex, 格式: $subtitleCodec)',
        );
        continue;
      }

      final subtitleInfo = <String, dynamic>{
        'path': subtitleFilePath,
        'name': _buildStreamingSubtitleName(track, subtitleFilePath),
        'type':
            p.extension(subtitleFilePath).replaceFirst('.', '').toLowerCase(),
        'addTime': DateTime.now().millisecondsSinceEpoch,
        'isActive': false,
        'remoteSource': sourceLabel,
        'serverSubtitleIndex': subtitleIndex,
        'language': track['language'],
        'title': track['title'],
        'isDefault': track['isDefault'] == true,
        'isForced': track['isForced'] == true,
      };
      downloadedSubtitles.add(subtitleInfo);

      if (subtitleIndex == preferredIndex &&
          subtitleCodec == preferredCodec &&
          activeSubtitlePath == null) {
        activeSubtitlePath = subtitleFilePath;
      }
    }

    if (downloadedSubtitles.isEmpty) {
      debugPrint('[$sourceLabel] 所有外挂字幕下载均失败，itemId: $itemId');
      return;
    }

    activeSubtitlePath ??= downloadedSubtitles.first['path'] as String?;

    final saveSucceeded = await SubtitleService().addExternalSubtitles(
      videoPath,
      downloadedSubtitles,
      activePath: activeSubtitlePath,
    );
    if (!saveSucceeded) {
      debugPrint('[$sourceLabel] 外挂字幕缓存列表保存失败');
    }

    if (activeSubtitlePath == null || activeSubtitlePath.isEmpty) {
      debugPrint('[$sourceLabel] 未找到可激活的外挂字幕');
      return;
    }

    // TODO: [技术债] 此处使用固定延迟等待播放器初始化，非常不可靠。
    // 在网络或设备性能较差时可能导致字幕加载失败。
    // 后续应重构为监听播放器的 isInitialized 状态。
    await Future.delayed(const Duration(milliseconds: 1000));
    _subtitleManager.setExternalSubtitle(
      activeSubtitlePath,
      isManualSetting: false,
    );
    debugPrint(
      '[$sourceLabel] 外挂字幕加载完成，已缓存 ${downloadedSubtitles.length} 条供切换',
    );
  }

  Map<String, dynamic> _selectPreferredStreamingSubtitle(
    List<Map<String, dynamic>> externalSubtitles,
  ) {
    for (final track in externalSubtitles) {
      if (_isPreferredChineseStreamingSubtitle(track)) {
        return track;
      }
    }
    for (final track in externalSubtitles) {
      if (track['isDefault'] == true) {
        return track;
      }
    }
    return externalSubtitles.first;
  }

  bool _isPreferredChineseStreamingSubtitle(Map<String, dynamic> track) {
    final title = track['title']?.toString().toLowerCase() ?? '';
    final language = track['language']?.toString().toLowerCase() ?? '';
    return language.contains('chi') ||
        language.contains('zh') ||
        title.contains('简体') ||
        title.contains('繁体') ||
        title.contains('中文') ||
        title.contains('sc') ||
        title.contains('tc') ||
        title.startsWith('scjp') ||
        title.startsWith('tcjp');
  }

  String _buildStreamingSubtitleName(
    Map<String, dynamic> track,
    String subtitleFilePath,
  ) {
    final display = track['display']?.toString().trim() ?? '';
    if (display.isNotEmpty) {
      return display;
    }

    final title = track['title']?.toString().trim() ?? '';
    final language = track['language']?.toString().trim() ?? '';
    final codec = track['codec']?.toString().trim().toUpperCase() ?? '';

    final parts = <String>[];
    if (title.isNotEmpty) {
      parts.add(title);
    }
    if (language.isNotEmpty && language.toLowerCase() != title.toLowerCase()) {
      parts.add(language);
    }
    if (codec.isNotEmpty) {
      parts.add(codec);
    }

    if (parts.isNotEmpty) {
      return parts.join(' · ');
    }
    return p.basename(subtitleFilePath);
  }

  // 检查是否是流媒体视频并使用现有的IDs直接加载弹幕
  Future<bool> _checkAndLoadStreamingDanmaku(
      String videoPath, WatchHistoryItem? historyItem) async {
    // 检查是否是Jellyfin视频URL (多种可能格式)
    bool isJellyfinStream = videoPath.startsWith('jellyfin://') ||
        (videoPath.contains('jellyfin') && videoPath.startsWith('http')) ||
        (videoPath.contains('/Videos/') && videoPath.contains('/stream')) ||
        (videoPath.contains('MediaSourceId=') &&
            videoPath.contains('api_key='));

    // 检查是否是Emby视频URL (多种可能格式)
    bool isEmbyStream = videoPath.startsWith('emby://') ||
        (videoPath.contains('emby') && videoPath.startsWith('http')) ||
        (videoPath.contains('/emby/Videos/') &&
            videoPath.contains('/stream')) ||
        (videoPath.contains('api_key=') && videoPath.contains('emby'));

    if ((isJellyfinStream || isEmbyStream) && historyItem != null) {
      debugPrint(
          '检测到流媒体视频URL: $videoPath (Jellyfin: $isJellyfinStream, Emby: $isEmbyStream)');

      // 检查historyItem是否包含所需的danmaku IDs
      if (historyItem.episodeId != null && historyItem.animeId != null) {
        debugPrint(
            '使用historyItem的IDs直接加载Jellyfin弹幕: episodeId=${historyItem.episodeId}, animeId=${historyItem.animeId}');

        try {
          // 使用已有的episodeId和animeId直接加载弹幕，跳过文件哈希计算
          _setStatus(PlayerStatus.recognizing,
              message: '正在为Jellyfin流媒体加载弹幕...');
          await loadDanmaku(
              historyItem.episodeId.toString(), historyItem.animeId.toString());

          // 更新当前实例的弹幕ID
          _episodeId = historyItem.episodeId;
          _animeId = historyItem.animeId;

          // 如果历史记录中有正确的动画名称和剧集标题，立即更新当前实例
          if (historyItem.animeName.isNotEmpty &&
              historyItem.animeName != 'Unknown') {
            _animeTitle = historyItem.animeName;
            _episodeTitle = historyItem.episodeTitle;
            debugPrint('[流媒体弹幕] 从历史记录更新标题: $_animeTitle - $_episodeTitle');

            // 立即更新历史记录，确保UI显示正确的信息
            await _updateHistoryWithNewTitles();
          }

          return true; // 表示已处理
        } catch (e) {
          debugPrint('Jellyfin流媒体弹幕加载失败: $e');
          _danmakuList = [];
          _danmakuTracks.clear();
          _danmakuTrackEnabled.clear();
          _setStatus(PlayerStatus.recognizing, message: 'Jellyfin弹幕加载失败，跳过');
          return true; // 尽管失败，但仍标记为已处理
        }
      } else {
        debugPrint(
            'Jellyfin流媒体historyItem缺少弹幕IDs: episodeId=${historyItem.episodeId}, animeId=${historyItem.animeId}');
        _setStatus(PlayerStatus.recognizing, message: 'Jellyfin视频匹配数据不完整，跳过弹幕');
      }
    }
    return false; // 表示未处理
  }

  // 播放完成时回传观看记录到弹弹play
  Future<void> _submitWatchHistoryToDandanplay() async {
    // 检查是否已登录弹弹play账号
    if (!DandanplayService.isLoggedIn) {
      debugPrint('[观看记录] 未登录弹弹play账号，跳过回传观看记录');
      return;
    }

    if (_currentVideoPath == null || _episodeId == null) {
      debugPrint('[观看记录] 缺少必要信息（视频路径或episodeId），跳过回传观看记录');
      return;
    }

    try {
      debugPrint('[观看记录] 开始向弹弹play提交观看记录: episodeId=$_episodeId');

      final result = await DandanplayService.addPlayHistory(
        episodeIdList: [_episodeId!],
        addToFavorite: false,
        rating: 0,
      );

      if (result['success'] == true) {
        debugPrint('[观看记录] 观看记录提交成功');
      } else {
        debugPrint('[观看记录] 观看记录提交失败: ${result['errorMessage']}');
      }
    } catch (e) {
      debugPrint('[观看记录] 提交观看记录时出错: $e');
    }
  }

  /// 处理Jellyfin播放结束的同步
  Future<void> _handleJellyfinPlaybackEnd(String videoPath) async {
    try {
      final itemId = videoPath.replaceFirst('jellyfin://', '');
      final syncService = JellyfinPlaybackSyncService();
      final historyItem = await WatchHistoryManager.getHistoryItem(videoPath);
      if (historyItem != null) {
        await syncService.reportPlaybackStopped(itemId, historyItem,
            isCompleted: true);
      }
    } catch (e) {
      debugPrint('Jellyfin播放结束同步失败: $e');
    }
  }

  /// 处理Emby播放结束的同步
  Future<void> _handleEmbyPlaybackEnd(String videoPath) async {
    try {
      final itemId = videoPath.replaceFirst('emby://', '');
      final syncService = EmbyPlaybackSyncService();
      final historyItem = await WatchHistoryManager.getHistoryItem(videoPath);
      if (historyItem != null) {
        await syncService.reportPlaybackStopped(itemId, historyItem,
            isCompleted: true);
      }
    } catch (e) {
      debugPrint('Emby播放结束同步失败: $e');
    }
  }
}

// ==== Jellyfin 清晰度切换：平滑重载当前流 ====
// 说明：当侧栏清晰度设置被更改时调用，保留当前位置、播放/暂停、音量、倍速等状态
extension JellyfinQualitySwitch on VideoPlayerState {
  Future<void> reloadCurrentJellyfinStream({
    required JellyfinVideoQuality quality,
    int? serverSubtitleIndex,
    bool burnInSubtitle = false,
    int? audioStreamIndex,
  }) async {
    try {
      if (_currentVideoPath == null ||
          !_currentVideoPath!.startsWith('jellyfin://')) {
        return;
      }

      // 快照当前播放状态
      final currentPath = _currentVideoPath!;
      final currentPosition = _position;
      final currentDuration = _duration;
      final currentProgress = _progress;
      final currentVolume = player.volume;
      final currentPlaybackRate = _playbackRate;
      final wasPlaying = _status == PlayerStatus.playing;

      // 构造临时历史项用于恢复进度
      final historyItem = WatchHistoryItem(
        filePath: currentPath,
        animeName: _animeTitle ?? '',
        episodeTitle: _episodeTitle,
        episodeId: _episodeId,
        animeId: _animeId,
        lastPosition: currentPosition.inMilliseconds,
        duration: currentDuration.inMilliseconds,
        watchProgress: currentProgress,
        lastWatchTime: DateTime.now(),
      );

      // 计算新的播放会话（应用清晰度 + 可选服务器字幕/烧录参数）
      final itemId = currentPath.replaceFirst('jellyfin://', '');
      final newSession = await JellyfinService.instance.createPlaybackSession(
        itemId: itemId,
        quality: quality,
        startPositionMs: currentPosition.inMilliseconds,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: serverSubtitleIndex,
        burnInSubtitle: burnInSubtitle,
        playSessionId: _currentPlaybackSession?.playSessionId,
        mediaSourceId: _currentPlaybackSession?.mediaSourceId,
      );
      _currentPlaybackSession = newSession;
      JellyfinPlaybackSyncService().updatePlaybackSession(newSession);

      // 重载播放器
      await initializePlayer(
        currentPath,
        historyItem: historyItem,
        playbackSession: newSession,
        resetManualDanmakuOffset: false,
      );

      // 恢复播放状态（等待状态稳定后再操作）
      if (hasVideo) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (_useSystemVolume) {
          _ensurePlayerVolumeMatchesPlatformPolicy();
        } else {
          player.volume = currentVolume;
        }
        if (currentPlaybackRate != 1.0) {
          player.setPlaybackRate(currentPlaybackRate);
        }
        seekTo(currentPosition);
        await Future.delayed(const Duration(milliseconds: 100));
        if (wasPlaying) {
          play();
        } else {
          pause();
        }
      }
    } catch (e) {
      debugPrint('Jellyfin 清晰度切换失败: $e');
    }
  }
}

// ==== Emby 清晰度切换：平滑重载当前流 ====
extension EmbyQualitySwitch on VideoPlayerState {
  Future<void> reloadCurrentEmbyStream({
    required JellyfinVideoQuality quality,
    int? serverSubtitleIndex,
    bool burnInSubtitle = false,
    int? audioStreamIndex,
  }) async {
    try {
      if (_currentVideoPath == null ||
          !_currentVideoPath!.startsWith('emby://')) {
        return;
      }

      final currentPath = _currentVideoPath!;
      final currentPosition = _position;
      final currentDuration = _duration;
      final currentProgress = _progress;
      final currentVolume = player.volume;
      final currentPlaybackRate = _playbackRate;
      final wasPlaying = _status == PlayerStatus.playing;

      final historyItem = WatchHistoryItem(
        filePath: currentPath,
        animeName: _animeTitle ?? '',
        episodeTitle: _episodeTitle,
        episodeId: _episodeId,
        animeId: _animeId,
        lastPosition: currentPosition.inMilliseconds,
        duration: currentDuration.inMilliseconds,
        watchProgress: currentProgress,
        lastWatchTime: DateTime.now(),
      );

      final embyPath = currentPath.replaceFirst('emby://', '');
      final parts = embyPath.split('/');
      final itemId = parts.isNotEmpty ? parts.last : embyPath;
      final newSession = await EmbyService.instance.createPlaybackSession(
        itemId: itemId,
        quality: quality,
        startPositionMs: currentPosition.inMilliseconds,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: serverSubtitleIndex,
        burnInSubtitle: burnInSubtitle,
        playSessionId: _currentPlaybackSession?.playSessionId,
        mediaSourceId: _currentPlaybackSession?.mediaSourceId,
      );
      _currentPlaybackSession = newSession;
      EmbyPlaybackSyncService().updatePlaybackSession(newSession);

      await initializePlayer(
        currentPath,
        historyItem: historyItem,
        playbackSession: newSession,
        resetManualDanmakuOffset: false,
      );

      if (hasVideo) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (_useSystemVolume) {
          _ensurePlayerVolumeMatchesPlatformPolicy();
        } else {
          player.volume = currentVolume;
        }
        if (currentPlaybackRate != 1.0) {
          player.setPlaybackRate(currentPlaybackRate);
        }
        seekTo(currentPosition);
        await Future.delayed(const Duration(milliseconds: 100));
        if (wasPlaying) {
          play();
        } else {
          pause();
        }
      }
    } catch (e) {
      debugPrint('Emby 清晰度切换失败: $e');
    }
  }
}
