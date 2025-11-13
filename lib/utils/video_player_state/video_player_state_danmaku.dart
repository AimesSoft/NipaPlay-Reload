part of video_player_state;

extension VideoPlayerStateDanmaku on VideoPlayerState {
  Future<void> loadDanmaku(String episodeId, String animeIdStr) async {
    try {
      debugPrint('尝试为episodeId=$episodeId, animeId=$animeIdStr加载弹幕');
      _setStatus(PlayerStatus.recognizing, message: '正在加载弹幕...');

      if (episodeId.isEmpty) {
        debugPrint('无效的episodeId，无法加载弹幕');
        _setStatus(PlayerStatus.recognizing, message: '无效的弹幕ID，跳过加载');
        return;
      }

      // 清除之前的弹幕数据
      debugPrint('清除之前的弹幕数据');
      _danmakuList.clear();
      danmakuController?.clearDanmaku();
      notifyListeners();

      // 更新内部状态变量，确保新的弹幕ID被保存
      final parsedAnimeId = int.tryParse(animeIdStr) ?? 0;
      final episodeIdInt = int.tryParse(episodeId) ?? 0;

      if (episodeIdInt > 0 && parsedAnimeId > 0) {
        _episodeId = episodeIdInt;
        _animeId = parsedAnimeId;
        debugPrint('更新内部弹幕ID状态: episodeId=$_episodeId, animeId=$_animeId');
      }

      // 从缓存加载弹幕
      final cachedDanmaku =
          await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (cachedDanmaku != null) {
        debugPrint('从缓存中找到弹幕数据，共${cachedDanmaku.length}条');
        _setStatus(PlayerStatus.recognizing, message: '正在从缓存加载弹幕...');

        // 设置最终加载阶段标志，减少动画性能消耗
        _isInFinalLoadingPhase = true;
        notifyListeners();

        // 加载弹幕到控制器
        danmakuController?.loadDanmaku(cachedDanmaku);
        _setStatus(PlayerStatus.playing,
            message: '从缓存加载弹幕完成 (${cachedDanmaku.length}条)');

        // 解析弹幕数据并添加到弹弹play轨道
        final parsedDanmaku = await compute(
            parseDanmakuListInBackground, cachedDanmaku as List<dynamic>?);

        _danmakuTracks['dandanplay'] = {
          'name': '弹弹play',
          'source': 'dandanplay',
          'episodeId': episodeId,
          'animeId': animeIdStr,
          'danmakuList': parsedDanmaku,
          'count': parsedDanmaku.length,
        };
        _danmakuTrackEnabled['dandanplay'] = true;

        // 重新计算合并后的弹幕列表
        _updateMergedDanmakuList();

        // 移除GPU弹幕字符集预构建调用
        // await _prebuildGPUDanmakuCharsetIfNeeded();

        notifyListeners();
        return;
      }

      debugPrint('缓存中没有找到弹幕，从网络加载中...');
      // 从网络加载弹幕
      final animeId = int.tryParse(animeIdStr) ?? 0;

      // 设置最终加载阶段标志，减少动画性能消耗
      _isInFinalLoadingPhase = true;
      notifyListeners();

      final danmakuData = await DandanplayService.getDanmaku(episodeId, animeId)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('加载弹幕超时');
      });

      if (danmakuData['comments'] != null && danmakuData['comments'] is List) {
        debugPrint('成功从网络加载弹幕，共${danmakuData['count']}条');

        // 加载弹幕到控制器
        final filteredDanmaku = danmakuData['comments']
            .where((d) => !shouldBlockDanmaku(d))
            .toList();
        danmakuController?.loadDanmaku(filteredDanmaku);

        // 解析弹幕数据并添加到弹弹play轨道
        final parsedDanmaku = await compute(parseDanmakuListInBackground,
            danmakuData['comments'] as List<dynamic>?);

        _danmakuTracks['dandanplay'] = {
          'name': '弹弹play',
          'source': 'dandanplay',
          'episodeId': episodeId,
          'animeId': animeId.toString(),
          'danmakuList': parsedDanmaku,
          'count': parsedDanmaku.length,
        };
        _danmakuTrackEnabled['dandanplay'] = true;

        // 重新计算合并后的弹幕列表
        _updateMergedDanmakuList();

        // 移除GPU弹幕字符集预构建调用
        await _prebuildGPUDanmakuCharsetIfNeeded();

        _setStatus(PlayerStatus.playing,
            message: '弹幕加载完成 (${danmakuData['count']}条)');
        notifyListeners();
      } else {
        debugPrint('网络返回的弹幕数据无效');
        _setStatus(PlayerStatus.playing, message: '弹幕数据无效，跳过加载');
      }
    } catch (e) {
      debugPrint('加载弹幕失败: $e');
      _setStatus(PlayerStatus.playing, message: '弹幕加载失败');
    }
  }

  // 从本地JSON数据加载弹幕（多轨道模式）
  Future<void> loadDanmakuFromLocal(Map<String, dynamic> jsonData,
      {String? trackName}) async {
    try {
      debugPrint('开始从本地JSON加载弹幕...');

      // 解析弹幕数据，支持多种格式
      List<dynamic> comments = [];

      if (jsonData.containsKey('comments') && jsonData['comments'] is List) {
        // 标准格式：comments字段包含数组
        comments = jsonData['comments'];
      } else if (jsonData.containsKey('data')) {
        // 兼容格式：data字段
        final data = jsonData['data'];
        if (data is List) {
          // data是数组
          comments = data;
        } else if (data is String) {
          // data是字符串，需要解析
          try {
            final parsedData = json.decode(data);
            if (parsedData is List) {
              comments = parsedData;
            } else {
              throw Exception('data字段的JSON字符串不是数组格式');
            }
          } catch (e) {
            throw Exception('data字段的JSON字符串解析失败: $e');
          }
        } else {
          throw Exception('data字段格式不正确，应为数组或JSON字符串');
        }
      } else {
        throw Exception('JSON文件格式不正确，必须包含comments数组或data字段');
      }

      if (comments.isEmpty) {
        throw Exception('弹幕文件中没有弹幕数据');
      }

      // 解析弹幕数据
      final parsedDanmaku =
          await compute(parseDanmakuListInBackground, comments);

      // 生成轨道名称
      final String finalTrackName =
          trackName ?? 'local_${DateTime.now().millisecondsSinceEpoch}';

      // 添加到本地轨道
      _danmakuTracks[finalTrackName] = {
        'name': trackName ?? '本地轨道${_danmakuTracks.length}',
        'source': 'local',
        'danmakuList': parsedDanmaku,
        'count': parsedDanmaku.length,
        'loadTime': DateTime.now(),
      };
      _danmakuTrackEnabled[finalTrackName] = true;

      // 重新计算合并后的弹幕列表
      _updateMergedDanmakuList();

      debugPrint('本地弹幕轨道添加完成: $finalTrackName，共${comments.length}条');
      _setStatus(PlayerStatus.playing,
          message: '本地弹幕轨道添加完成 (${comments.length}条)');
      notifyListeners();
    } catch (e) {
      debugPrint('加载本地弹幕失败: $e');
      _setStatus(PlayerStatus.playing, message: '本地弹幕加载失败');
      rethrow;
    }
  }

  // 更新合并后的弹幕列表
  void _updateMergedDanmakuList() {
    final List<Map<String, dynamic>> mergedList = [];

    // 合并所有启用的轨道
    for (final trackId in _danmakuTracks.keys) {
      if (_danmakuTrackEnabled[trackId] == true) {
        final trackData = _danmakuTracks[trackId]!;
        final trackDanmaku =
            trackData['danmakuList'] as List<Map<String, dynamic>>;
        mergedList.addAll(trackDanmaku);
      }
    }

    // 重新排序
    mergedList.sort((a, b) {
      final timeA = (a['time'] as double?) ?? 0.0;
      final timeB = (b['time'] as double?) ?? 0.0;
      return timeA.compareTo(timeB);
    });

    _totalDanmakuCount = mergedList.length;
    final filteredList =
        mergedList.where((d) => !shouldBlockDanmaku(d)).toList();
    _danmakuList = filteredList;

    danmakuController?.clearDanmaku();
    danmakuController?.loadDanmaku(filteredList);

    // 通过更新key来强制刷新DanmakuOverlay
    _danmakuOverlayKey = 'danmaku_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint('弹幕轨道合并及过滤完成，显示${_danmakuList.length}条，总计${mergedList.length}条');
    notifyListeners(); // 确保通知UI更新
  }

  // GPU弹幕字符集预构建（如果需要）
  Future<void> _prebuildGPUDanmakuCharsetIfNeeded() async {
    try {
      // 检查当前是否使用GPU弹幕内核
      final currentKernel = await PlayerKernelManager.getCurrentDanmakuKernel();
      if (currentKernel != 'GPU渲染') {
        return; // 不是GPU内核，跳过
      }

      if (_danmakuList.isEmpty) {
        return; // 没有弹幕数据，跳过
      }

      debugPrint('VideoPlayerState: 检测到GPU弹幕内核，开始预构建字符集');
      _setStatus(PlayerStatus.recognizing, message: '正在优化GPU弹幕字符集...');

      // 使用过滤后的弹幕列表来预构建字符集，避免屏蔽词字符被包含
      final filteredDanmakuList = getFilteredDanmakuList();

      // 调用GPU弹幕覆盖层的预构建方法
      await GPUDanmakuOverlay.prebuildDanmakuCharset(filteredDanmakuList);

      debugPrint('VideoPlayerState: GPU弹幕字符集预构建完成');
    } catch (e) {
      debugPrint('VideoPlayerState: GPU弹幕字符集预构建失败: $e');
      // 不抛出异常，避免影响正常播放
    }
  }

  // 切换轨道启用状态
  void toggleDanmakuTrack(String trackId, bool enabled) {
    if (_danmakuTracks.containsKey(trackId)) {
      _danmakuTrackEnabled[trackId] = enabled;
      _updateMergedDanmakuList();
      notifyListeners();
      debugPrint('弹幕轨道 $trackId ${enabled ? "启用" : "禁用"}');
    }
  }

  // 删除弹幕轨道
  void removeDanmakuTrack(String trackId) {
    if (trackId == 'dandanplay') {
      debugPrint('不能删除弹弹play轨道');
      return;
    }

    if (_danmakuTracks.containsKey(trackId)) {
      _danmakuTracks.remove(trackId);
      _danmakuTrackEnabled.remove(trackId);
      _updateMergedDanmakuList();
      notifyListeners();
      debugPrint('删除弹幕轨道: $trackId');
    }
  }

  // 在设置视频时长时更新状态
  void setVideoDuration(Duration duration) {
    _videoDuration = duration;
    notifyListeners();
  }

  // 更新观看记录
  Future<void> _updateWatchHistory() async {
    if (_currentVideoPath == null) {
      return;
    }

    // 防止在播放器重置过程中更新历史记录
    if (_isResetting) {
      return;
    }

    if (_status == PlayerStatus.idle || _status == PlayerStatus.error) {
      return;
    }

    try {
      // 使用 Provider 获取播放记录
      WatchHistoryItem? existingHistory;

      if (_context != null && _context!.mounted) {
        final watchHistoryProvider = _context!.read<WatchHistoryProvider>();
        existingHistory =
            await watchHistoryProvider.getHistoryItem(_currentVideoPath!);
      } else {
        // 不使用 Provider 更新状态，避免不必要的 UI 刷新
        existingHistory = await WatchHistoryDatabase.instance
            .getHistoryByFilePath(_currentVideoPath!);
      }

      if (existingHistory != null) {
        // 使用当前缩略图路径，如果没有则尝试捕获一个
        String? thumbnailPath = _currentThumbnailPath;
        if (thumbnailPath == null || thumbnailPath.isEmpty) {
          thumbnailPath = existingHistory.thumbnailPath;
          if ((thumbnailPath == null || thumbnailPath.isEmpty) &&
              player.state == PlaybackState.playing) {
            // 仅在播放时尝试捕获
            // 仅在没有缩略图时才尝试捕获
            try {
              thumbnailPath = await _captureVideoFrameWithoutPausing();
              if (thumbnailPath != null) {
                _currentThumbnailPath = thumbnailPath;
              }
            } catch (e) {
              //debugPrint('自动捕获缩略图失败: $e');
            }
          }
        }

        // 更新现有记录
        // 对于Jellyfin流媒体，优先使用当前实例变量中的友好名称（如果有的话）
        String finalAnimeName = existingHistory.animeName;
        String? finalEpisodeTitle = existingHistory.episodeTitle;

        // 检查是否是流媒体并且当前有更好的名称
        final bool isJellyfinStream =
            _currentVideoPath!.startsWith('jellyfin://');
        final bool isEmbyStream = _currentVideoPath!.startsWith('emby://');
        final bool isSharedRemoteStream =
            SharedRemoteHistoryHelper.isSharedRemoteStreamPath(
                _currentVideoPath!);
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
              'VideoPlayerState: 使用流媒体/共享媒体友好名称更新记录: $finalAnimeName - $finalEpisodeTitle');
        }

        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: finalAnimeName,
          episodeTitle: finalEpisodeTitle,
          episodeId: _episodeId ??
              existingHistory.episodeId ??
              _initialHistoryItem?.episodeId, // 优先使用存储的 episodeId
          animeId: _animeId ??
              existingHistory.animeId ??
              _initialHistoryItem?.animeId, // 优先使用存储的 animeId
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath ?? _initialHistoryItem?.thumbnailPath,
          isFromScan: existingHistory.isFromScan,
        );

        // Jellyfin同步：如果是Jellyfin流媒体，同步播放进度（每秒同步一次）
        if (isJellyfinStream) {
          try {
            // 每秒同步一次，提供更及时的进度更新
            if (_position.inMilliseconds % 1000 < 100) {
              final itemId = _currentVideoPath!.replaceFirst('jellyfin://', '');
              final syncService = JellyfinPlaybackSyncService();
              await syncService.syncCurrentProgress(_position.inMilliseconds);
            }
          } catch (e) {
            debugPrint('Jellyfin播放进度同步失败: $e');
          }
        }

        // Emby同步：如果是Emby流媒体，同步播放进度（每秒同步一次）
        if (isEmbyStream) {
          try {
            // 每秒同步一次，提供更及时的进度更新
            if (_position.inMilliseconds % 1000 < 100) {
              final itemId = _currentVideoPath!.replaceFirst('emby://', '');
              final syncService = EmbyPlaybackSyncService();
              await syncService.syncCurrentProgress(_position.inMilliseconds);
            }
          } catch (e) {
            debugPrint('Emby播放进度同步失败: $e');
          }
        }

        // 通过 Provider 更新记录
        if (_context != null && _context!.mounted) {
          await _context!
              .read<WatchHistoryProvider>()
              .addOrUpdateHistory(updatedHistory);
        } else {
          // 直接使用数据库更新
          await WatchHistoryDatabase.instance
              .insertOrUpdateWatchHistory(updatedHistory);
        }
      } else {
        // 如果记录不存在，创建新记录
        final fileName = _currentVideoPath!.split('/').last;

        // 尝试从文件名中提取初始动画名称
        String initialAnimeName = fileName.replaceAll(
            RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$', caseSensitive: false), '');
        initialAnimeName =
            initialAnimeName.replaceAll(RegExp(r'[_\.-]'), ' ').trim();

        if (initialAnimeName.isEmpty) {
          initialAnimeName = "未知动画"; // 确保非空
        }

        // 尝试获取缩略图
        String? thumbnailPath = _currentThumbnailPath;
        if (thumbnailPath == null && player.state == PlaybackState.playing) {
          // 仅在播放时尝试捕获
          try {
            thumbnailPath = await _captureVideoFrameWithoutPausing();
            if (thumbnailPath != null) {
              _currentThumbnailPath = thumbnailPath;
            }
          } catch (e) {
            //debugPrint('首次创建记录时捕获缩略图失败: $e');
          }
        }

        final newHistory = WatchHistoryItem(
          filePath: _currentVideoPath!,
          animeName: initialAnimeName,
          episodeId: _episodeId, // 使用从 historyItem 传入的 episodeId
          animeId: _animeId, // 使用从 historyItem 传入的 animeId
          watchProgress: _progress,
          lastPosition: _position.inMilliseconds,
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
          isFromScan: false,
        );

        // 通过 Provider 添加记录
        if (_context != null && _context!.mounted) {
          await _context!
              .read<WatchHistoryProvider>()
              .addOrUpdateHistory(newHistory);
        } else {
          // 直接使用数据库添加
          await WatchHistoryDatabase.instance
              .insertOrUpdateWatchHistory(newHistory);
        }
      }
    } catch (e) {
      debugPrint('更新观看记录时出错: $e');
    }
  }

  // 添加一条新弹幕到当前列表
  void addDanmaku(Map<String, dynamic> danmaku) {
    if (danmaku.containsKey('time') && danmaku.containsKey('content')) {
      _danmakuList.add(danmaku);
      // 按时间重新排序
      _danmakuList.sort((a, b) {
        final timeA = (a['time'] as double?) ?? 0.0;
        final timeB = (b['time'] as double?) ?? 0.0;
        return timeA.compareTo(timeB);
      });
      notifyListeners();
      debugPrint('已添加新弹幕到列表: ${danmaku['content']}');
    }
  }

  // 将一条新弹幕添加到指定的轨道，如果轨道不存在则创建
  void addDanmakuToNewTrack(Map<String, dynamic> danmaku,
      {String trackName = '我的弹幕'}) {
    if (danmaku.containsKey('time') && danmaku.containsKey('content')) {
      final trackId = 'local_$trackName';

      // 检查轨道是否存在
      if (!_danmakuTracks.containsKey(trackId)) {
        // 如果轨道不存在，创建新轨道
        _danmakuTracks[trackId] = {
          'name': trackName,
          'source': 'local',
          'danmakuList': <Map<String, dynamic>>[],
          'count': 0,
          'loadTime': DateTime.now(),
        };
        _danmakuTrackEnabled[trackId] = true; // 默认启用新轨道
      }

      // 添加弹幕到轨道
      final trackDanmaku =
          _danmakuTracks[trackId]!['danmakuList'] as List<Map<String, dynamic>>;
      trackDanmaku.add(danmaku);
      _danmakuTracks[trackId]!['count'] = trackDanmaku.length;

      // 重新计算合并后的弹幕列表
      _updateMergedDanmakuList();

      debugPrint('已将新弹幕添加到轨道 "$trackName": ${danmaku['content']}');
    }
  }

  // 确保视频信息中包含格式化后的动画标题和集数标题
  static void _ensureVideoInfoTitles(Map<String, dynamic> videoInfo) {
    if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
      final match = videoInfo['matches'][0];
      // ... existing code ...
    }
  }

  // 显示发送弹幕对话框
  void showSendDanmakuDialog() {
    debugPrint('[VideoPlayerState] 快捷键触发发送弹幕');

    // 先检查是否已经有弹幕对话框在显示
    final dialogManager = DanmakuDialogManager();

    // 如果已经在显示弹幕对话框，则关闭它，否则显示新对话框
    if (!dialogManager.handleSendDanmakuHotkey()) {
      // 对话框未显示，显示新对话框
      // 检查是否能发送弹幕
      if (episodeId == null) {
        if (_context != null) {
          // 使用BlurSnackBar显示提示
          BlurSnackBar.show(_context!, '无法获取剧集信息，无法发送弹幕');
        }
        return;
      }

      DanmakuDialogManager().showSendDanmakuDialog(
        context: _context!,
        episodeId: episodeId!,
        currentTime: position.inSeconds.toDouble(),
        onDanmakuSent: (danmaku) {
          addDanmakuToNewTrack(danmaku);
        },
        onDialogClosed: () {
          if (player.state == PlaybackState.playing) {
            player.playDirectly();
          }
        },
        wasPlaying: player.state == PlaybackState.playing,
      );
    }
  }

  // 切换时间轴告知弹幕轨道
  void toggleTimelineDanmaku(bool enabled) {
    _isTimelineDanmakuEnabled = enabled;

    if (enabled) {
      // 生成并添加时间轴弹幕轨道
      final timelineDanmaku =
          TimelineDanmakuService.generateTimelineDanmaku(_duration);
      _danmakuTracks['timeline'] = {
        'name': timelineDanmaku['name'],
        'source': timelineDanmaku['source'],
        'danmakuList': timelineDanmaku['comments'],
        'count': timelineDanmaku['count'],
      };
      _danmakuTrackEnabled['timeline'] = true;
    } else {
      // 移除时间轴弹幕轨道
      _danmakuTracks.remove('timeline');
      _danmakuTrackEnabled.remove('timeline');
    }

    _updateMergedDanmakuList();
    notifyListeners();
  }
}
