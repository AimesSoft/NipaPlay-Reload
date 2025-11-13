part of video_player_state;

extension VideoPlayerStatePlayerSetup on VideoPlayerState {
  Future<void> initializePlayer(String videoPath,
      {WatchHistoryItem? historyItem,
      String? historyFilePath,
      String? actualPlayUrl}) async {
    // 每次切换新视频时，重置自动连播倒计时状态，防止高强度测试下卡死
    try {
      AutoNextEpisodeService.instance.cancelAutoNext();
    } catch (e) {
      debugPrint('[自动连播] 重置AutoNextEpisodeService状态失败: $e');
    }
    if (_status == PlayerStatus.loading ||
        _status == PlayerStatus.recognizing) {
      _setStatus(PlayerStatus.idle,
          message: "取消了之前的加载任务", clearPreviousMessages: true);
    }
    _clearPreviousVideoState(); // 清理旧状态
    _statusMessages.clear(); // <--- 新增行：确保消息列表在开始时是空的
    _initialHistoryItem = historyItem;

    // 从 historyItem 中获取弹幕 ID
    if (historyItem != null) {
      _episodeId = historyItem.episodeId;
      _animeId = historyItem.animeId;
      debugPrint(
          'VideoPlayerState: 从 historyItem 获取弹幕 ID - episodeId: $_episodeId, animeId: $_animeId');
    } else {
      _episodeId = null;
      _animeId = null;
      debugPrint('VideoPlayerState: 没有 historyItem，重置弹幕 ID');
    }

    // 检查是否为网络URL (HTTP或HTTPS)
    bool isNetworkUrl =
        videoPath.startsWith('http://') || videoPath.startsWith('https://');

    // 检查是否是流媒体（jellyfin://协议、emby://协议）
    bool isJellyfinStream = videoPath.startsWith('jellyfin://');
    bool isEmbyStream = videoPath.startsWith('emby://');

    // 对于本地文件才检查存在性，网络URL和流媒体默认认为"存在"
    bool fileExists =
        isNetworkUrl || isJellyfinStream || isEmbyStream || kIsWeb;

    // 为网络URL添加特定日志
    if (isNetworkUrl) {
      debugPrint('检测到流媒体URL: $videoPath');
      _statusMessages.add('正在准备流媒体播放...');
      notifyListeners();
    } else if (isJellyfinStream) {
      debugPrint(
          '检测到Jellyfin流媒体: videoPath=$videoPath, actualPlayUrl=$actualPlayUrl');
      _statusMessages.add('正在准备Jellyfin流媒体播放...');
      notifyListeners();
    } else if (isEmbyStream) {
      debugPrint(
          '检测到Emby流媒体: videoPath=$videoPath, actualPlayUrl=$actualPlayUrl');
      _statusMessages.add('正在准备Emby流媒体播放...');
      notifyListeners();
    }

    if (!kIsWeb && !isNetworkUrl && !isJellyfinStream && !isEmbyStream) {
      // 使用FilePickerService处理文件路径问题
      if (Platform.isIOS) {
        final filePickerService = FilePickerService();

        // 首先检查文件是否存在
        fileExists = filePickerService.checkFileExists(videoPath);

        // 如果文件不存在，尝试获取有效的文件路径
        if (!fileExists) {
          final validPath = await filePickerService.getValidFilePath(videoPath);
          if (validPath != null) {
            debugPrint('找到有效路径: $validPath (原路径: $videoPath)');
            videoPath = validPath;
            fileExists = true;
          } else {
            // 检查是否是iOS临时文件路径
            if (videoPath.contains('/tmp/') ||
                videoPath.contains('-Inbox/') ||
                videoPath.contains('/Inbox/')) {
              debugPrint('检测到iOS临时文件路径: $videoPath');
              // 尝试从原始路径获取文件名，然后检查是否在持久化目录中
              final fileName = p.basename(videoPath);
              final docDir = await StorageService.getAppStorageDirectory();
              final persistentPath = '${docDir.path}/Videos/$fileName';

              if (File(persistentPath).existsSync()) {
                debugPrint('找到持久化存储中的文件: $persistentPath');
                videoPath = persistentPath;
                fileExists = true;
              }
            }
          }
        }
      } else {
        // 非iOS平台直接检查文件是否存在
        final File videoFile = File(videoPath);
        fileExists = videoFile.existsSync();
      }
    } else if (kIsWeb) {
      // Web平台，我们相信传入的blob URL是有效的
      debugPrint('Web平台，跳过文件存在性检查');
    } else {
      debugPrint('检测到网络URL或流媒体: $videoPath');
    }

    if (!fileExists) {
      debugPrint('VideoPlayerState: 文件不存在或无法访问: $videoPath');
      _setStatus(PlayerStatus.error,
          message: '找不到文件或无法访问: ${p.basename(videoPath)}');
      _error = '文件不存在或无法访问';
      return;
    }

    // 对网络URL和Jellyfin流媒体进行特殊处理
    if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
      debugPrint('VideoPlayerState: 准备流媒体URL: $videoPath');
      // 添加网络错误处理的尝试/捕获块
      try {
        // 测试网络连接
        await http.head(Uri.parse(videoPath));
      } catch (e) {
        // 如果网络请求失败，使用专门的错误处理逻辑
        await _handleStreamUrlLoadingError(
            videoPath, e is Exception ? e : Exception(e.toString()));
        return; // 避免继续处理
      }
    } else if ((isJellyfinStream || isEmbyStream) && actualPlayUrl != null) {
      debugPrint('VideoPlayerState: 准备流媒体URL: $actualPlayUrl');
      // 对Jellyfin流媒体测试实际播放URL的连接
      try {
        await http.head(Uri.parse(actualPlayUrl));
      } catch (e) {
        // 如果网络请求失败，使用专门的错误处理逻辑
        await _handleStreamUrlLoadingError(
            actualPlayUrl, e is Exception ? e : Exception(e.toString()));
        return; // 避免继续处理
      }
    }

    // 更新字幕管理器的视频路径
    _subtitleManager.setCurrentVideoPath(videoPath);

    _currentVideoPath = videoPath;
    _currentActualPlayUrl = actualPlayUrl; // 存储实际播放URL
    print('historyItem: $historyItem');
    _animeTitle = historyItem?.animeName; // 从历史记录获取动画标题
    _episodeTitle = historyItem?.episodeTitle; // 从历史记录获取集数标题
    _episodeId = historyItem?.episodeId; // 保存从历史记录传入的 episodeId
    _animeId = historyItem?.animeId; // 保存从历史记录传入的 animeId
    String message = '正在初始化播放器: ${p.basename(videoPath)}';
    if (_animeTitle != null) {
      message = '正在初始化播放器: $_animeTitle $_episodeTitle';
    }
    _setStatus(PlayerStatus.loading, message: message);
    try {
      debugPrint(
          'VideoPlayerState: initializePlayer CALLED for path: $videoPath');
      //debugPrint('VideoPlayerState: globals.isPhone = ${globals.isPhone}');

      //debugPrint('1. 开始初始化播放器...');
      // 加载保存的token
      await DandanplayService.loadToken();

      _setStatus(PlayerStatus.loading, message: '正在初始化播放器...');
      _error = null;

      //debugPrint('2. 重置播放器状态...');
      // 完全重置播放器
      if (player.state != PlaybackState.stopped) {
        player.state = PlaybackState.stopped;
      }
      // 清除视频资源
      player.state = PlaybackState.stopped;
      player.setMedia("", MediaType.video); // 使用空字符串和视频类型清除媒体

      // 释放旧纹理
      if (player.textureId.value != null) {
        // Keep the null check for reading
        // player.textureId.value = null; // COMMENTED OUT - ValueListenable has no setter
      }
      // 等待纹理完全释放
      await Future.delayed(const Duration(milliseconds: 500));
      // 重置播放器状态
      player.media = '';
      await Future.delayed(const Duration(milliseconds: 100));
      _currentVideoPath = null;
      _danmakuOverlayKey = 'idle'; // 临时重置弹幕覆盖层key
      _currentVideoHash = null; // 重置哈希值
      _currentThumbnailPath = null; // 重置缩略图路径
      _position = Duration.zero;
      _duration = Duration.zero;
      _progress = 0.0;
      _error = null;
      _setStatus(PlayerStatus.idle);

      //debugPrint('3. 设置媒体源...');
      // 设置媒体源 - 如果提供了actualPlayUrl则使用它，否则使用videoPath
      String playUrl = actualPlayUrl ?? videoPath;
      player.media = playUrl;

      //debugPrint('4. 准备播放器...');
      // 准备播放器
      player.prepare();

      // 针对Jellyfin流媒体，给予更长的初始化时间
      final bool isJellyfinStreaming =
          videoPath.contains('jellyfin://') || videoPath.contains('emby://');
      final int initializationTimeout =
          isJellyfinStreaming ? 30000 : 15000; // Jellyfin: 30秒, 其他: 15秒

      debugPrint(
          'VideoPlayerState: 播放器初始化超时设置: ${initializationTimeout}ms (${isJellyfinStreaming ? 'Jellyfin流媒体' : '本地文件'})');

      // 等待播放器准备完成，设置超时
      int waitCount = 0;
      const int maxWaitCount = 100; // 最大等待次数
      const int waitInterval = 100; // 每次等待100毫秒

      while (waitCount < maxWaitCount) {
        await Future.delayed(const Duration(milliseconds: waitInterval));
        waitCount++;

        // 检查播放器状态
        if (player.state == PlaybackState.playing ||
            player.state == PlaybackState.paused ||
            (player.mediaInfo.duration > 0 && player.textureId.value != null)) {
          debugPrint(
              'VideoPlayerState: 播放器准备完成，等待时间: ${waitCount * waitInterval}ms');
          break;
        }

        // 检查是否超时
        if (waitCount * waitInterval >= initializationTimeout) {
          debugPrint('VideoPlayerState: 播放器初始化超时 (${initializationTimeout}ms)');
          if (isJellyfinStreaming) {
            debugPrint('VideoPlayerState: Jellyfin流媒体初始化超时，但继续尝试播放');
            // 对于Jellyfin流媒体，即使超时也继续尝试
            break;
          } else {
            throw Exception('播放器初始化超时');
          }
        }
      }

      //debugPrint('5. 获取视频纹理...');
      // 获取视频纹理
      final textureId = await player.updateTexture();
      //debugPrint('获取到纹理ID: $textureId');

      // !!!!! 在这里启动或重启UI更新定时器（已包含位置保存功能）!!!!!
      _startUiUpdateTimer(); // 启动UI更新定时器（已包含位置保存功能）
      // !!!!! ------------------------------------------- !!!!!

      // 等待纹理初始化完成
      await Future.delayed(const Duration(milliseconds: 200));

      //debugPrint('6. 分析媒体信息...');
      // 分析并打印媒体信息，特别是字幕轨道
      MediaInfoHelper.analyzeMediaInfo(player.mediaInfo);

      // 设置视频宽高比
      if (player.mediaInfo.video != null &&
          player.mediaInfo.video!.isNotEmpty) {
        final videoTrack = player.mediaInfo.video![0];
        if (videoTrack.codec.width > 0 && videoTrack.codec.height > 0) {
          _aspectRatio = videoTrack.codec.width / videoTrack.codec.height;
          debugPrint(
              'VideoPlayerState: 从mediaInfo设置视频宽高比: $_aspectRatio (${videoTrack.codec.width}x${videoTrack.codec.height})');
        } else {
          // 备用方案：从播放器状态获取视频尺寸
          debugPrint('VideoPlayerState: mediaInfo中视频尺寸为0，尝试从播放器状态获取');
          // 延迟获取，因为播放器状态可能还没有准备好
          Future.delayed(const Duration(milliseconds: 1000), () {
            // 尝试从播放器的snapshot方法获取视频尺寸
            try {
              player.snapshot().then((frame) {
                if (frame != null && frame.width > 0 && frame.height > 0) {
                  _aspectRatio = frame.width / frame.height;
                  debugPrint(
                      'VideoPlayerState: 从snapshot设置视频宽高比: $_aspectRatio (${frame.width}x${frame.height})');
                  notifyListeners(); // 通知UI更新
                }
              });
            } catch (e) {
              debugPrint('VideoPlayerState: 从snapshot获取视频尺寸失败: $e');
            }
          });
        }

        // 更新当前解码器信息
        // 获取解码器信息（异步方式）
        final activeDecoder = await getActiveDecoder();
        SystemResourceMonitor().setActiveDecoder(activeDecoder);
        debugPrint('当前视频解码器: $activeDecoder');

        // 如果检测到使用软解，但硬件解码开关已打开，尝试强制启用硬件解码
        if (activeDecoder.contains("软解")) {
          final prefs = await SharedPreferences.getInstance();
          final useHardwareDecoder =
              prefs.getBool('use_hardware_decoder') ?? true;

          if (useHardwareDecoder) {
            debugPrint('检测到使用软解但硬件解码已启用，尝试强制启用硬件解码...');
            // 延迟执行以避免干扰视频初始化
            Future.delayed(const Duration(seconds: 2), () async {
              await forceEnableHardwareDecoder();
            });
          }
        }
      }

      // 优先选择简体中文相关的字幕轨道
      if (player.mediaInfo.subtitle != null) {
        final subtitles = player.mediaInfo.subtitle!;
        int? preferredSubtitleIndex;

        // 定义简体和繁体中文的关键字
        const simplifiedKeywords = ['简体', '简中', 'chs', 'sc', 'simplified'];
        const traditionalKeywords = ['繁體', '繁体', 'cht', 'tc', 'traditional'];

        // 优先级 1: 查找简体中文轨道
        for (var i = 0; i < subtitles.length; i++) {
          final track = subtitles[i];
          final fullString = track.toString().toLowerCase();
          if (simplifiedKeywords.any((kw) => fullString.contains(kw))) {
            preferredSubtitleIndex = i;
            debugPrint(
                'VideoPlayerState: 自动选择简体中文字幕: ${track.title ?? fullString}');
            break; // 找到最佳匹配，跳出循环
          }
        }

        // 优先级 2: 如果没有找到简体，则查找繁体中文轨道
        if (preferredSubtitleIndex == null) {
          for (var i = 0; i < subtitles.length; i++) {
            final track = subtitles[i];
            final fullString = track.toString().toLowerCase();
            if (traditionalKeywords.any((kw) => fullString.contains(kw))) {
              preferredSubtitleIndex = i;
              debugPrint(
                  'VideoPlayerState: 自动选择繁体中文字幕: ${track.title ?? fullString}');
              break;
            }
          }
        }

        // 优先级 3: 如果还没有，则查找任何语言代码为中文的轨道 (chi/zho)
        if (preferredSubtitleIndex == null) {
          for (var i = 0; i < subtitles.length; i++) {
            final track = subtitles[i];
            if (track.language == 'chi' || track.language == 'zho') {
              preferredSubtitleIndex = i;
              debugPrint(
                  'VideoPlayerState: 自动选择语言代码为中文的字幕: ${track.title ?? track.toString().toLowerCase()}');
              break;
            }
          }
        }

        // 如果找到了优先的字幕轨道，就激活它
        if (preferredSubtitleIndex != null) {
          player.activeSubtitleTracks = [preferredSubtitleIndex];

          // 更新字幕轨道信息
          if (player.mediaInfo.subtitle != null &&
              preferredSubtitleIndex < player.mediaInfo.subtitle!.length) {
            final track = player.mediaInfo.subtitle![preferredSubtitleIndex];
            _subtitleManager.updateSubtitleTrackInfo('embedded_subtitle', {
              'index': preferredSubtitleIndex,
              'title': track.toString(),
              'isActive': true,
            });
          }
        } else {
          debugPrint('VideoPlayerState: 未找到符合条件的中文字幕轨道，将使用播放器默认设置。');
        }

        // 无论是否有优先字幕轨道，都更新所有字幕轨道信息
        _subtitleManager.updateAllSubtitleTracksInfo();

        // 通知字幕轨道变化
        _subtitleManager.onSubtitleTrackChanged();
      }

      // 针对Jellyfin流媒体，自动加载外挂字幕
      if (videoPath.startsWith('jellyfin://')) {
        await _loadJellyfinExternalSubtitles(videoPath);
      }
      // 针对Emby流媒体，自动加载外挂字幕
      if (videoPath.startsWith('emby://')) {
        await _loadEmbyExternalSubtitles(videoPath);
      }

      //debugPrint('7. 更新视频状态...');
      // 更新状态
      _currentVideoPath = videoPath;
      _danmakuOverlayKey = 'video_${videoPath.hashCode}'; // 为每个视频生成唯一的稳定key

      // 异步计算视频哈希值，不阻塞主要初始化流程
      _precomputeVideoHash(videoPath);

      _duration = Duration(milliseconds: player.mediaInfo.duration);

      // 对于Jellyfin流媒体，先进行同步，再获取播放位置
      bool isJellyfinStream = videoPath.startsWith('jellyfin://');
      bool isEmbyStream = videoPath.startsWith('emby://');
      if (isJellyfinStream || isEmbyStream) {
        await _initializeWatchHistory(videoPath);
      }

      // 获取上次播放位置
      final lastPosition = await _getVideoPosition(videoPath);
      debugPrint(
          'VideoPlayerState: lastPosition for $videoPath = $lastPosition (raw value from _getVideoPosition)');

      // 如果有上次的播放位置，恢复播放位置
      if (lastPosition > 0) {
        //debugPrint('8. 恢复上次播放位置...');
        // 先设置播放位置
        player.seek(position: lastPosition);
        // 等待一小段时间确保位置设置完成
        await Future.delayed(const Duration(milliseconds: 100));
        // 更新状态
        _position = Duration(milliseconds: lastPosition);
        _progress = lastPosition / _duration.inMilliseconds;
      } else {
        _position = Duration.zero;
        _progress = 0.0;
        player.seek(position: 0);
      }

      //debugPrint('9. 检查播放器实际状态...');
      // 检查播放器实际状态
      if (player.state == PlaybackState.playing) {
        _setStatus(PlayerStatus.playing, message: '正在播放');
      } else {
        // 如果播放器没有真正开始播放，设置为暂停状态
        player.state = PlaybackState.paused;
        _setStatus(PlayerStatus.paused, message: '已暂停');
      }

      // 对于非流媒体，在获取播放位置后初始化观看记录
      if (!isJellyfinStream && !isEmbyStream) {
        await _initializeWatchHistory(videoPath);
      }

      //debugPrint('10. 开始识别视频和加载弹幕...');
      // 针对Jellyfin流媒体视频的特殊处理
      bool jellyfinDanmakuHandled = false;
      try {
        // 检查是否是Jellyfin视频并尝试使用historyItem中的IDs直接加载弹幕
        jellyfinDanmakuHandled =
            await _checkAndLoadStreamingDanmaku(videoPath, historyItem);
      } catch (e) {
        debugPrint('检查Jellyfin弹幕时出错: $e');
        // 错误处理时不设置jellyfinDanmakuHandled为true，下面会继续常规处理
      }

      // 如果不是Jellyfin视频或者Jellyfin视频没有预设的弹幕IDs，则检查是否有手动匹配的弹幕
      if (!jellyfinDanmakuHandled) {
        // 检查是否有手动匹配的弹幕ID
        if (_episodeId != null &&
            _animeId != null &&
            _episodeId! > 0 &&
            _animeId! > 0) {
          debugPrint(
              '检测到手动匹配的弹幕ID，直接加载: episodeId=$_episodeId, animeId=$_animeId');
          try {
            _setStatus(PlayerStatus.recognizing, message: '正在加载手动匹配的弹幕...');
            await loadDanmaku(_episodeId.toString(), _animeId.toString());
          } catch (e) {
            debugPrint('加载手动匹配的弹幕失败: $e');
            // 如果手动匹配的弹幕加载失败，清空弹幕列表但不重新识别
            _danmakuList = [];
            _danmakuTracks.clear();
            _danmakuTrackEnabled.clear();
            _addStatusMessage('手动匹配的弹幕加载失败');
          }
        } else {
          // 没有手动匹配的弹幕ID，使用常规方式识别和加载弹幕
          try {
            await _recognizeVideo(videoPath);
          } catch (e) {
            //debugPrint('弹幕加载失败: $e');
            // 设置空弹幕列表，确保播放不受影响
            _danmakuList = [];
            _danmakuTracks.clear();
            _danmakuTrackEnabled.clear();
            _addStatusMessage('无法连接服务器，跳过加载弹幕');
          }
        }
      }

      // 设置进入最终加载阶段，以优化动画性能
      _isInFinalLoadingPhase = true;
      notifyListeners();

      //debugPrint('11. 设置准备就绪状态...');
      // 设置状态为准备就绪
      _setStatus(PlayerStatus.ready, message: '准备就绪');

      // 使用屏幕方向管理器设置播放时的屏幕方向
      if (globals.isPhone) {
        debugPrint(
            'VideoPlayerState: Device is phone. Setting video playing orientation.');
        await ScreenOrientationManager.instance.setVideoPlayingOrientation();

        // 平板设备默认隐藏菜单栏（全屏状态）
        if (globals.isTablet) {
          _isAppBarHidden = true;
          debugPrint(
              'VideoPlayerState: Tablet detected, hiding app bar by default.');

          // 同时隐藏系统UI
          try {
            await SystemChrome.setEnabledSystemUIMode(
                SystemUiMode.immersiveSticky);
          } catch (e) {
            debugPrint('隐藏系统UI时出错: $e');
          }
        }
      }

      //debugPrint('12. 设置最终播放状态 (在可能的横屏切换之后)...');
      if (lastPosition == 0) {
        // 从头播放
        // debugPrint('VideoPlayerState: Initializing playback from start, calling play().'); // <--- REMOVED PRINT
        play(); // Call our central play method
      } else {
        // 从中间恢复
        if (player.state == PlaybackState.playing) {
          // Player is already playing after seek (e.g., underlying engine auto-resumed)
          _setStatus(PlayerStatus.playing,
              message: '正在播放 (恢复)'); // Sync our status
          // debugPrint('VideoPlayerState: Player already playing on resume. Directly starting screenshot timer.'); // <--- REMOVED PRINT
          _startScreenshotTimer(); // Start timer directly
        } else {
          // Player did not auto-play after seek, or was paused. We need to start it.
          // _status should be 'ready' from earlier _setStatus call in initializePlayer
          // debugPrint('VideoPlayerState: Resuming playback (player was not auto-playing), calling play().'); // <--- REMOVED PRINT
          play(); // Call our central play method
        }
      }

      // 尝试自动检测和加载字幕
      await _subtitleManager.autoDetectAndLoadSubtitle(videoPath);

      // 不在此处注册热键，由main.dart的_manageHotkeys统一管理
      debugPrint('[VideoPlayerState] 跳过热键注册，由主页面统一管理');

      // 等待一小段时间确保播放器状态稳定
      await Future.delayed(const Duration(milliseconds: 300));

      // 应用保存的播放速度设置
      if (hasVideo && _playbackRate != 1.0) {
        player.setPlaybackRate(_playbackRate);
        debugPrint('VideoPlayerState: 应用保存的播放速度设置: ${_playbackRate}x');
      }

      // 再次检查播放器实际状态并同步 _status
      if (player.state == PlaybackState.playing) {
        if (_status != PlayerStatus.playing) {
          // 如果横屏操作导致状态变化，但最终是播放，则同步
          _setStatus(PlayerStatus.playing, message: '正在播放 (状态确认)');
        }
        //debugPrint('VideoPlayerState: Final check - Player IS PLAYING.');
      } else {
        debugPrint(
            'VideoPlayerState: Final check - Player IS NOT PLAYING. Current _status: $_status, player.state: ${player.state}');
        // 如果意图是播放 (无论是从头还是恢复)，但播放器最终没有播放，则设为暂停
        if (_status == PlayerStatus.playing) {
          // 如果我们之前的意图是播放
          player.state = PlaybackState.paused;
          _setStatus(PlayerStatus.paused, message: '已暂停 (播放失败后同步)');
          debugPrint(
              'VideoPlayerState: Corrected to PAUSED (sync after play attempt failed)');
        } else if (_status != PlayerStatus.paused) {
          // 对于其他非播放且非暂停的意外状态，也强制为暂停
          player.state = PlaybackState.paused;
          _setStatus(PlayerStatus.paused, message: '已暂停 (状态同步)');
          //debugPrint('VideoPlayerState: Corrected to PAUSED (general sync)');
        }
      }
    } catch (e) {
      //debugPrint('初始化视频播放器时出错: $e');
      _error = '初始化视频播放器时出错: $e';
      _setStatus(PlayerStatus.error, message: '播放器初始化失败');
      // 尝试恢复
      _tryRecoverFromError();
    }
  }

  // 外部字幕自动加载回调处理
  void _onExternalSubtitleAutoLoaded(String path, String fileName) {
    // 这里可以处理回调，例如显示提示或更新UI
    debugPrint('VideoPlayerState: 外部字幕自动加载: $fileName');
  }

  // 预先计算视频哈希值
  Future<void> _precomputeVideoHash(String path) async {
    try {
      //debugPrint('开始计算视频哈希值...');
      _currentVideoHash = await _calculateFileHash(path);
      //debugPrint('视频哈希值计算完成: $_currentVideoHash');
    } catch (e) {
      //debugPrint('计算视频哈希值失败: $e');
      // 失败时将哈希值设为null，让后续操作重新计算
      _currentVideoHash = null;
    }
  }

  // 初始化观看记录
  Future<void> _initializeWatchHistory(String path) async {
    try {
      final sharedEpisodeId =
          SharedRemoteHistoryHelper.extractSharedEpisodeId(path);
      final sharedEpisodeHistories =
          await SharedRemoteHistoryHelper.loadHistoriesBySharedEpisodeId(
              sharedEpisodeId);

      WatchHistoryItem? existingHistory =
          await WatchHistoryManager.getHistoryItem(path);

      if (existingHistory == null && sharedEpisodeHistories.isNotEmpty) {
        try {
          existingHistory = sharedEpisodeHistories.firstWhere(
            (item) => item.filePath == path,
          );
        } catch (_) {
          existingHistory = sharedEpisodeHistories.first;
        }
        debugPrint(
            '_initializeWatchHistory: 通过共享媒体EpisodeId匹配到已有记录: ${existingHistory.filePath}');
      }

      final duplicatesToRemove = <String>{};
      for (final history in sharedEpisodeHistories) {
        if (history.filePath != path) {
          duplicatesToRemove.add(history.filePath);
        }
      }

      for (final duplicatePath in duplicatesToRemove) {
        debugPrint('_initializeWatchHistory: 移除重复的共享媒体历史记录: $duplicatePath');
        await _removeHistoryEntry(duplicatePath);
      }

      if (existingHistory != null) {
        String finalAnimeName = existingHistory.animeName;
        String? finalEpisodeTitle = existingHistory.episodeTitle;

        final bool isJellyfinStream = path.startsWith('jellyfin://');
        final bool isEmbyStream = path.startsWith('emby://');
        final bool isSharedRemoteStream =
            SharedRemoteHistoryHelper.isSharedRemoteStreamPath(path);

        if (isJellyfinStream || isEmbyStream || isSharedRemoteStream) {
          final animeNameCandidate =
              SharedRemoteHistoryHelper.firstNonEmptyString([
            SharedRemoteHistoryHelper.normalizeHistoryName(_animeTitle),
            SharedRemoteHistoryHelper.normalizeHistoryName(
                _initialHistoryItem?.animeName),
            SharedRemoteHistoryHelper.normalizeHistoryName(finalAnimeName),
          ]);
          if (animeNameCandidate != null) {
            finalAnimeName = animeNameCandidate;
          }

          final episodeTitleCandidate =
              SharedRemoteHistoryHelper.firstNonEmptyString([
            _episodeTitle,
            _initialHistoryItem?.episodeTitle,
            finalEpisodeTitle,
          ]);
          if (episodeTitleCandidate != null) {
            finalEpisodeTitle = episodeTitleCandidate;
          }

          debugPrint(
              '_initializeWatchHistory: 使用友好名称: $finalAnimeName - $finalEpisodeTitle');
        }

        debugPrint(
            '已有观看记录存在，只更新播放进度: 动画=$finalAnimeName, 集数=$finalEpisodeTitle');

        final updatedHistory = WatchHistoryItem(
          filePath: path,
          animeName: finalAnimeName,
          episodeTitle: finalEpisodeTitle,
          episodeId: _episodeId ??
              existingHistory.episodeId ??
              _initialHistoryItem?.episodeId,
          animeId: _animeId ??
              existingHistory.animeId ??
              _initialHistoryItem?.animeId,
          watchProgress: existingHistory.watchProgress,
          lastPosition: existingHistory.lastPosition,
          duration: existingHistory.duration,
          lastWatchTime: DateTime.now(),
          thumbnailPath: existingHistory.thumbnailPath ??
              _initialHistoryItem?.thumbnailPath,
          isFromScan: existingHistory.isFromScan,
        );

        if (isJellyfinStream) {
          try {
            final itemId = path.replaceFirst('jellyfin://', '');
            final syncService = JellyfinPlaybackSyncService();
            final syncedHistory =
                await syncService.syncOnPlayStart(itemId, existingHistory);
            if (syncedHistory != null) {
              await WatchHistoryManager.addOrUpdateHistory(syncedHistory);
              await _saveVideoPosition(path, syncedHistory.lastPosition);
              debugPrint(
                  'Jellyfin同步成功，更新SharedPreferences位置: ${syncedHistory.lastPosition}ms');
              await syncService.reportPlaybackStart(itemId, syncedHistory);
            } else {
              await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
              await syncService.reportPlaybackStart(itemId, updatedHistory);
            }
          } catch (e) {
            debugPrint('Jellyfin同步失败，使用本地记录: $e');
            await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
          }
        } else if (isEmbyStream) {
          try {
            final itemId = path.replaceFirst('emby://', '');
            final syncService = EmbyPlaybackSyncService();
            final syncedHistory =
                await syncService.syncOnPlayStart(itemId, existingHistory);
            if (syncedHistory != null) {
              await WatchHistoryManager.addOrUpdateHistory(syncedHistory);
              await _saveVideoPosition(path, syncedHistory.lastPosition);
              debugPrint(
                  'Emby同步成功，更新SharedPreferences位置: ${syncedHistory.lastPosition}ms');
              await syncService.reportPlaybackStart(itemId, syncedHistory);
            } else {
              await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
              await syncService.reportPlaybackStart(itemId, updatedHistory);
            }
          } catch (e) {
            debugPrint('Emby同步失败，使用本地记录: $e');
            await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
          }
        } else {
          await WatchHistoryManager.addOrUpdateHistory(updatedHistory);
        }

        if (_context != null && _context!.mounted) {
          await _context!
              .read<WatchHistoryProvider>()
              .addOrUpdateHistory(updatedHistory);
        }
        return;
      }

      final fileName = path.split('/').last;
      final sanitizedFileName = fileName
          .replaceAll(
              RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[_\.-]'), ' ')
          .trim();

      final initialAnimeName = SharedRemoteHistoryHelper.firstNonEmptyString([
            SharedRemoteHistoryHelper.normalizeHistoryName(_animeTitle),
            SharedRemoteHistoryHelper.normalizeHistoryName(
                _initialHistoryItem?.animeName),
            sanitizedFileName.isEmpty
                ? null
                : SharedRemoteHistoryHelper.normalizeHistoryName(
                    sanitizedFileName),
          ]) ??
          '未知动画';

      final initialEpisodeTitle =
          SharedRemoteHistoryHelper.firstNonEmptyString([
        _initialHistoryItem?.episodeTitle,
        _episodeTitle,
      ]);

      final initialEpisodeId = _episodeId ?? _initialHistoryItem?.episodeId;
      final initialAnimeId = _animeId ?? _initialHistoryItem?.animeId;
      final initialLastPosition = _position.inMilliseconds > 0
          ? _position.inMilliseconds
          : (_initialHistoryItem?.lastPosition ?? 0);
      final initialDuration = _duration.inMilliseconds > 0
          ? _duration.inMilliseconds
          : (_initialHistoryItem?.duration ?? 0);
      final initialProgress = _progress > 0
          ? _progress
          : (_initialHistoryItem?.watchProgress ?? 0.0);

      final item = WatchHistoryItem(
        filePath: path,
        animeName: initialAnimeName,
        episodeTitle: initialEpisodeTitle,
        episodeId: initialEpisodeId,
        animeId: initialAnimeId,
        lastPosition: initialLastPosition,
        duration: initialDuration,
        watchProgress: initialProgress,
        lastWatchTime: DateTime.now(),
        thumbnailPath: _initialHistoryItem?.thumbnailPath,
        isFromScan: _initialHistoryItem?.isFromScan ?? false,
      );

      final bool isJellyfinStream = path.startsWith('jellyfin://');
      final bool isEmbyStream = path.startsWith('emby://');

      if (isJellyfinStream) {
        try {
          final itemId = path.replaceFirst('jellyfin://', '');
          final syncService = JellyfinPlaybackSyncService();
          final syncedHistory = await syncService.syncOnPlayStart(itemId, item);
          if (syncedHistory != null) {
            await WatchHistoryManager.addOrUpdateHistory(syncedHistory);
            await _saveVideoPosition(path, syncedHistory.lastPosition);
            debugPrint(
                'Jellyfin同步成功（新记录），更新SharedPreferences位置: ${syncedHistory.lastPosition}ms');
            await syncService.reportPlaybackStart(itemId, syncedHistory);
          } else {
            await WatchHistoryManager.addOrUpdateHistory(item);
            await syncService.reportPlaybackStart(itemId, item);
          }
        } catch (e) {
          debugPrint('Jellyfin同步失败（新记录），使用本地记录: $e');
          await WatchHistoryManager.addOrUpdateHistory(item);
        }
      } else if (isEmbyStream) {
        try {
          final itemId = path.replaceFirst('emby://', '');
          final syncService = EmbyPlaybackSyncService();
          final syncedHistory = await syncService.syncOnPlayStart(itemId, item);
          if (syncedHistory != null) {
            await WatchHistoryManager.addOrUpdateHistory(syncedHistory);
            await _saveVideoPosition(path, syncedHistory.lastPosition);
            debugPrint(
                'Emby同步成功（新记录），更新SharedPreferences位置: ${syncedHistory.lastPosition}ms');
            await syncService.reportPlaybackStart(itemId, syncedHistory);
          } else {
            await WatchHistoryManager.addOrUpdateHistory(item);
            await syncService.reportPlaybackStart(itemId, item);
          }
        } catch (e) {
          debugPrint('Emby同步失败（新记录），使用本地记录: $e');
          await WatchHistoryManager.addOrUpdateHistory(item);
        }
      } else {
        await WatchHistoryManager.addOrUpdateHistory(item);
      }

      if (_context != null && _context!.mounted) {
        _context!.read<WatchHistoryProvider>().refresh();
      }
    } catch (e) {
      //debugPrint('初始化观看记录时出错: $e\n$s');
    }
  }
}
