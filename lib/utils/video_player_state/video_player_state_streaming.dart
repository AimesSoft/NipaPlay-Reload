part of video_player_state;

extension VideoPlayerStateStreaming on VideoPlayerState {
  // 添加返回按钮处理
  Future<bool> handleBackButton() async {
    if (_isFullscreen) {
      await toggleFullscreen();
      return false; // 不退出应用
    } else {
      // 在返回按钮点击时进行截图
      _captureConditionalScreenshot("返回按钮时");

      // 等待截图完成
      await Future.delayed(const Duration(milliseconds: 200));

      // 退出视频播放时触发自动云同步
      if (_currentVideoPath != null) {
        try {
          await AutoSyncService.instance.syncOnPlaybackEnd();
          debugPrint('退出视频播放时云同步成功');
        } catch (e) {
          debugPrint('退出视频播放时云同步失败: $e');
        }
      }

      return true; // 允许返回
    }
  }

  // 条件性截图方法
  Future<void> _captureConditionalScreenshot(String triggerEvent) async {
    if (_currentVideoPath == null || !hasVideo || _isCapturingFrame) return;

    _isCapturingFrame = true;
    try {
      final newThumbnailPath = await _captureVideoFrameWithoutPausing();
      if (newThumbnailPath != null) {
        _currentThumbnailPath = newThumbnailPath;
        debugPrint('条件截图完成($triggerEvent): $_currentThumbnailPath');

        // 更新观看记录中的缩略图
        await _updateWatchHistoryWithNewThumbnail(newThumbnailPath);

        // 截图后检查解码器状态
        await _decoderManager.checkDecoderAfterScreenshot();
      }
    } catch (e) {
      debugPrint('条件截图失败($triggerEvent): $e');
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
    notifyListeners();
  }

  /// 加载Jellyfin外挂字幕
  Future<void> _loadJellyfinExternalSubtitles(String videoPath) async {
    try {
      // 从jellyfin://协议URL中提取itemId
      final itemId = videoPath.replaceFirst('jellyfin://', '');
      debugPrint('[Jellyfin字幕] 开始加载外挂字幕，itemId: $itemId');

      // 获取字幕轨道信息
      final subtitleTracks =
          await JellyfinService.instance.getSubtitleTracks(itemId);

      if (subtitleTracks.isEmpty) {
        debugPrint('[Jellyfin字幕] 未找到字幕轨道');
        return;
      }

      // 查找外挂字幕轨道
      final externalSubtitles =
          subtitleTracks.where((track) => track['type'] == 'external').toList();

      if (externalSubtitles.isEmpty) {
        debugPrint('[Jellyfin字幕] 未找到外挂字幕轨道');
        return;
      }

      debugPrint('[Jellyfin字幕] 找到 ${externalSubtitles.length} 个外挂字幕轨道');

      // 优先选择中文字幕
      Map<String, dynamic>? preferredSubtitle;

      // 首先查找简体中文
      preferredSubtitle = externalSubtitles.firstWhere(
        (track) {
          final title = track['title']?.toLowerCase() ?? '';
          final language = track['language']?.toLowerCase() ?? '';
          return language.contains('chi') ||
              title.contains('简体') ||
              title.contains('中文') ||
              title.contains('sc') || // 支持scjp格式
              title.contains('tc') || // 支持tcjp格式
              title.startsWith('scjp') || // 精确匹配scjp开头
              title.startsWith('tcjp'); // 精确匹配tcjp开头
        },
        orElse: () => externalSubtitles.first,
      );

      // 如果没有中文，选择默认字幕或第一个
      preferredSubtitle ??= externalSubtitles.firstWhere(
        (track) => track['isDefault'] == true,
        orElse: () => externalSubtitles.first,
      );

      final subtitleIndex = preferredSubtitle['index'];
      final subtitleCodec = preferredSubtitle['codec'];
      final subtitleTitle = preferredSubtitle['title'];

      debugPrint(
          '[Jellyfin字幕] 选择字幕轨道: $subtitleTitle (索引: $subtitleIndex, 格式: $subtitleCodec)');

      // 下载字幕文件
      final subtitleFilePath = await JellyfinService.instance
          .downloadSubtitleFile(itemId, subtitleIndex, subtitleCodec);

      if (subtitleFilePath != null) {
        debugPrint('[Jellyfin字幕] 字幕文件下载成功: $subtitleFilePath');

        // 等待播放器完全初始化
        // TODO: [技术债] 此处使用固定延迟等待播放器初始化，非常不可靠。
        // 在网络或设备性能较差时可能导致字幕加载失败。
        // 后续应重构为监听播放器的 isInitialized 状态。
        await Future.delayed(const Duration(milliseconds: 1000));

        // 加载外挂字幕
        _subtitleManager.setExternalSubtitle(subtitleFilePath,
            isManualSetting: false);

        debugPrint('[Jellyfin字幕] 外挂字幕加载完成');
      } else {
        debugPrint('[Jellyfin字幕] 字幕文件下载失败');
      }
    } catch (e) {
      debugPrint('[Jellyfin字幕] 加载外挂字幕时出错: $e');
    }
  }

  /// 加载Emby外挂字幕
  Future<void> _loadEmbyExternalSubtitles(String videoPath) async {
    try {
      // 从emby://协议URL中提取itemId
      final itemId = videoPath.replaceFirst('emby://', '');
      debugPrint('[Emby字幕] 开始加载外挂字幕，itemId: $itemId');
      // 获取字幕轨道信息
      final subtitleTracks =
          await EmbyService.instance.getSubtitleTracks(itemId);
      if (subtitleTracks.isEmpty) {
        debugPrint('[Emby字幕] 未找到字幕轨道');
        return;
      }
      // 查找外挂字幕轨道
      final externalSubtitles =
          subtitleTracks.where((track) => track['type'] == 'external').toList();
      if (externalSubtitles.isEmpty) {
        debugPrint('[Emby字幕] 未找到外挂字幕轨道');
        return;
      }
      debugPrint('[Emby字幕] 找到 ${externalSubtitles.length} 个外挂字幕轨道');
      // 优先选择中文字幕
      Map<String, dynamic>? preferredSubtitle;
      // 首先查找简体中文
      preferredSubtitle = externalSubtitles.firstWhere(
        (track) {
          final title = track['title']?.toLowerCase() ?? '';
          final language = track['language']?.toLowerCase() ?? '';
          return language.contains('chi') ||
              title.contains('简体') ||
              title.contains('中文') ||
              title.contains('sc') || // 支持scjp格式
              title.contains('tc') || // 支持tcjp格式
              title.startsWith('scjp') || // 精确匹配scjp开头
              title.startsWith('tcjp'); // 精确匹配tcjp开头
        },
        orElse: () => externalSubtitles.first,
      );
      // 如果没有中文，选择默认字幕或第一个
      preferredSubtitle ??= externalSubtitles.firstWhere(
        (track) => track['isDefault'] == true,
        orElse: () => externalSubtitles.first,
      );
      final subtitleIndex = preferredSubtitle['index'];
      final subtitleCodec = preferredSubtitle['codec'];
      final subtitleTitle = preferredSubtitle['title'];
      debugPrint(
          '[Emby字幕] 选择字幕轨道: $subtitleTitle (索引: $subtitleIndex, 格式: $subtitleCodec)');
      // 下载字幕文件
      final subtitleFilePath = await EmbyService.instance.downloadSubtitleFile(
        itemId,
        subtitleIndex,
        subtitleCodec,
      );
      if (subtitleFilePath != null) {
        debugPrint('[Emby字幕] 字幕文件下载成功: $subtitleFilePath');
        // 等待播放器完全初始化
        // TODO: [技术债] 此处使用固定延迟等待播放器初始化，非常不可靠。
        // 在网络或设备性能较差时可能导致字幕加载失败。
        // 后续应重构为监听播放器的 isInitialized 状态。
        await Future.delayed(const Duration(milliseconds: 1000));
        // 加载外挂字幕
        _subtitleManager.setExternalSubtitle(subtitleFilePath,
            isManualSetting: false);
        debugPrint('[Emby字幕] 外挂字幕加载完成');
      } else {
        debugPrint('[Emby字幕] 字幕文件下载失败');
      }
    } catch (e) {
      debugPrint('[Emby字幕] 加载外挂字幕时出错: $e');
    }
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

      // 计算新的播放 URL（应用清晰度 + 可选服务器字幕/烧录参数）
      final itemId = currentPath.replaceFirst('jellyfin://', '');
      final newUrl = await JellyfinService.instance.buildHlsUrlWithOptions(
        itemId,
        quality: quality,
        subtitleStreamIndex: serverSubtitleIndex,
        alwaysBurnInSubtitleWhenTranscoding: burnInSubtitle,
      );

      // 重载播放器
      await initializePlayer(
        currentPath,
        historyItem: historyItem,
        actualPlayUrl: newUrl,
      );

      // 恢复播放状态（等待状态稳定后再操作）
      if (hasVideo) {
        await Future.delayed(const Duration(milliseconds: 150));
        player.volume = currentVolume;
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

      final itemId = currentPath.replaceFirst('emby://', '');
      final newUrl = await EmbyService.instance.buildHlsUrlWithOptions(
        itemId,
        quality: quality,
        subtitleStreamIndex: serverSubtitleIndex,
        alwaysBurnInSubtitleWhenTranscoding: burnInSubtitle,
      );

      await initializePlayer(
        currentPath,
        historyItem: historyItem,
        actualPlayUrl: newUrl,
      );

      if (hasVideo) {
        await Future.delayed(const Duration(milliseconds: 150));
        player.volume = currentVolume;
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
