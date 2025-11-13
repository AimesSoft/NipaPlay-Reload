part of video_player_state;

extension VideoPlayerStateMetadata on VideoPlayerState {
  // 添加setter方法以支持手动匹配后立即更新标题
  void setAnimeTitle(String? title) {
    _animeTitle = title;
    notifyListeners();

    // 立即更新历史记录，确保历史记录卡片显示正确的动画名称
    _updateHistoryWithNewTitles();
  }

  void setEpisodeTitle(String? title) {
    _episodeTitle = title;
    notifyListeners();

    // 立即更新历史记录，确保历史记录卡片显示正确的动画名称
    _updateHistoryWithNewTitles();
  }

  Future<void> _removeHistoryEntry(String filePath) async {
    try {
      if (_context != null && _context!.mounted) {
        await _context!.read<WatchHistoryProvider>().removeHistory(filePath);
      } else {
        await WatchHistoryManager.removeHistory(filePath);
      }
    } catch (e) {
      debugPrint('删除历史记录时出错 ($filePath): $e');
    }
  }

  /// 使用新的标题更新历史记录
  Future<void> _updateHistoryWithNewTitles() async {
    if (_currentVideoPath == null) return;

    // 只有当两个标题都有值时才更新
    if (_animeTitle == null || _animeTitle!.isEmpty) return;

    try {
      debugPrint(
          '[VideoPlayerState] 使用新标题更新历史记录: $_animeTitle - $_episodeTitle');

      // 获取现有历史记录
      final existingHistory = await WatchHistoryDatabase.instance
          .getHistoryByFilePath(_currentVideoPath!);
      if (existingHistory == null) {
        debugPrint('[VideoPlayerState] 未找到现有历史记录，跳过更新');
        return;
      }

      // 创建更新后的历史记录
      final updatedHistory = WatchHistoryItem(
        filePath: existingHistory.filePath,
        animeName: _animeTitle!,
        episodeTitle: _episodeTitle ?? existingHistory.episodeTitle,
        episodeId: _episodeId ?? existingHistory.episodeId,
        animeId: _animeId ?? existingHistory.animeId,
        watchProgress: existingHistory.watchProgress,
        lastPosition: existingHistory.lastPosition,
        duration: existingHistory.duration,
        lastWatchTime: DateTime.now(),
        thumbnailPath: existingHistory.thumbnailPath,
        isFromScan: existingHistory.isFromScan,
      );

      // 保存更新后的记录
      await WatchHistoryDatabase.instance
          .insertOrUpdateWatchHistory(updatedHistory);

      debugPrint(
          '[VideoPlayerState] 成功更新历史记录: ${updatedHistory.animeName} - ${updatedHistory.episodeTitle}');

      // 通知UI刷新历史记录
      if (_context != null && _context!.mounted) {
        _context!.read<WatchHistoryProvider>().refresh();
      }
    } catch (e) {
      debugPrint('[VideoPlayerState] 更新历史记录时出错: $e');
    }
  }

  Future<void> _recognizeVideo(String videoPath) async {
    if (videoPath.isEmpty) return;

    try {
      _setStatus(PlayerStatus.recognizing, message: '正在识别视频...');

      // 使用超时处理网络请求
      try {
        //debugPrint('尝试获取视频信息...');
        final videoInfo = await DandanplayService.getVideoInfo(videoPath)
            .timeout(const Duration(seconds: 15), onTimeout: () {
          //debugPrint('获取视频信息超时');
          throw TimeoutException('连接服务器超时');
        });

        if (videoInfo['isMatched'] == true) {
          //debugPrint('视频匹配成功，开始加载弹幕...');
          _setStatus(PlayerStatus.recognizing, message: '视频识别成功，正在加载弹幕...');

          // 更新观看记录的动画和集数信息
          await _updateWatchHistoryWithVideoInfo(videoPath, videoInfo);

          if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
            final match = videoInfo['matches'][0];
            if (match['episodeId'] != null && match['animeId'] != null) {
              try {
                //debugPrint('尝试加载弹幕...');
                _setStatus(PlayerStatus.recognizing, message: '正在加载弹幕...');
                final episodeId = match['episodeId'].toString();
                final animeId = match['animeId'] as int;

                // 从缓存加载弹幕
                //debugPrint('检查弹幕缓存...');
                final cachedDanmakuRaw =
                    await DanmakuCacheManager.getDanmakuFromCache(episodeId);
                if (cachedDanmakuRaw != null) {
                  //debugPrint('从缓存加载弹幕...');
                  _setStatus(PlayerStatus.recognizing, message: '正在从缓存解析弹幕...');

                  // 设置最终加载阶段标志，减少动画性能消耗
                  _isInFinalLoadingPhase = true;
                  notifyListeners();

                  _danmakuList = await compute(parseDanmakuListInBackground,
                      cachedDanmakuRaw as List<dynamic>?);

                  // Sort the list immediately after parsing
                  _danmakuList.sort((a, b) {
                    final timeA = (a['time'] as double?) ?? 0.0;
                    final timeB = (b['time'] as double?) ?? 0.0;
                    return timeA.compareTo(timeB);
                  });
                  //debugPrint('缓存弹幕解析并排序完成');

                  notifyListeners();
                  _setStatus(PlayerStatus.recognizing,
                      message: '从缓存加载弹幕完成 (${_danmakuList.length}条)');
                  return; // Return early after loading from cache
                }

                //debugPrint('从网络加载弹幕...');
                // 从网络加载弹幕
                final danmakuData =
                    await DandanplayService.getDanmaku(episodeId, animeId)
                        .timeout(const Duration(seconds: 15), onTimeout: () {
                  //debugPrint('加载弹幕超时');
                  throw TimeoutException('加载弹幕超时');
                });

                // 设置最终加载阶段标志，减少动画性能消耗
                _isInFinalLoadingPhase = true;
                notifyListeners();

                _setStatus(PlayerStatus.recognizing, message: '正在解析网络弹幕...');
                if (danmakuData['comments'] != null &&
                    danmakuData['comments'] is List) {
                  // Use compute for parsing network danmaku, using the imported function
                  _danmakuList = await compute(parseDanmakuListInBackground,
                      danmakuData['comments'] as List<dynamic>?);

                  // Sort the list immediately after parsing
                  _danmakuList.sort((a, b) {
                    final timeA = (a['time'] as double?) ?? 0.0;
                    final timeB = (b['time'] as double?) ?? 0.0;
                    return timeA.compareTo(timeB);
                  });
                  //debugPrint('网络弹幕解析并排序完成');
                } else {
                  _danmakuList = [];
                  _danmakuTracks.clear();
                  _danmakuTrackEnabled.clear();
                }

                notifyListeners();
                _setStatus(PlayerStatus.recognizing,
                    message: '弹幕加载完成 (${_danmakuList.length}条)');

                // 如果是GPU模式，预构建字符集
                await _prebuildGPUDanmakuCharsetIfNeeded();
              } catch (e) {
                //debugPrint('弹幕加载/解析错误: $e\n$s');
                _danmakuList = [];
                _danmakuTracks.clear();
                _danmakuTrackEnabled.clear();
                _setStatus(PlayerStatus.recognizing, message: '弹幕加载失败，跳过');
              }
            }
          } else {
            //debugPrint('视频未匹配到信息');
            _danmakuList = [];
            _danmakuTracks.clear();
            _danmakuTrackEnabled.clear();
            _setStatus(PlayerStatus.recognizing, message: '未匹配到视频信息，跳过弹幕');
          }
        }
      } catch (e) {
        //debugPrint('视频识别网络错误: $e\n$s');
        _danmakuList = [];
        _danmakuTracks.clear();
        _danmakuTrackEnabled.clear();
        _setStatus(PlayerStatus.recognizing, message: '无法连接服务器，跳过加载弹幕');
      }
    } catch (e) {
      //debugPrint('识别视频或加载弹幕时发生严重错误: $e\n$s');
      rethrow;
    }
  }

  // 根据视频识别信息更新观看记录
  Future<void> _updateWatchHistoryWithVideoInfo(
      String path, Map<String, dynamic> videoInfo) async {
    try {
      //debugPrint('更新观看记录开始，视频路径: $path');
      // 获取现有记录
      WatchHistoryItem? existingHistory;

      if (_context != null && _context!.mounted) {
        final watchHistoryProvider = _context!.read<WatchHistoryProvider>();
        existingHistory = await watchHistoryProvider.getHistoryItem(path);
      } else {
        existingHistory =
            await WatchHistoryDatabase.instance.getHistoryByFilePath(path);
      }

      if (existingHistory == null) {
        //debugPrint('未找到现有观看记录，跳过更新');
        return;
      }

      // 获取识别到的动画信息
      String? apiAnimeName; // 从 videoInfo 或其 matches 中获取
      String? episodeTitle;
      int? animeId, episodeId;

      // 从videoInfo直接读取animeTitle和episodeTitle
      apiAnimeName = videoInfo['animeTitle'] as String?;
      episodeTitle = videoInfo['episodeTitle'] as String?;

      // 从匹配信息中获取animeId和episodeId
      if (videoInfo['matches'] != null &&
          videoInfo['matches'] is List &&
          videoInfo['matches'].isNotEmpty) {
        final match = videoInfo['matches'][0];
        // 如果直接字段为空，且匹配中有值，则使用匹配中的值
        if ((apiAnimeName == null || apiAnimeName.isEmpty) &&
            match['animeTitle'] != null) {
          apiAnimeName = match['animeTitle'] as String?;
        }

        episodeId = match['episodeId'] as int?;
        animeId = match['animeId'] as int?;
      }

      // 解析最终的 animeName，确保非空
      String resolvedAnimeName;
      if (apiAnimeName != null && apiAnimeName.isNotEmpty) {
        resolvedAnimeName = apiAnimeName;
      } else {
        // 如果 API 未提供有效名称，则使用现有记录中的名称
        resolvedAnimeName = existingHistory.animeName;
      }

      // 如果仍然没有动画名称，从文件名提取
      if (resolvedAnimeName.isEmpty) {
        final fileName = path.split('/').last;
        String extractedName = fileName.replaceAll(
            RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv)$', caseSensitive: false), '');
        extractedName = extractedName.replaceAll(RegExp(r'[_\.-]'), ' ').trim();

        resolvedAnimeName = extractedName.trim().isNotEmpty
            ? extractedName
            : "未知动画"; // 确保不会是空字符串
      }

      debugPrint(
          '识别到动画：$resolvedAnimeName，集数：${episodeTitle ?? '未知集数'}，animeId: $animeId, episodeId: $episodeId');

      // 更新当前动画标题和集数标题
      _animeTitle = resolvedAnimeName;
      _episodeTitle = episodeTitle;

      // 如果仍在加载/识别状态，并且成功识别出动画标题，则更新状态消息
      debugPrint('更新观看记录: $_animeTitle');
      String message = '正在加载: $_animeTitle';
      if (_episodeTitle != null && _episodeTitle!.isNotEmpty) {
        message += ' - $_episodeTitle';
      }
      // 直接设置状态和消息，但不改变PlayerStatus本身
      _setStatus(_status, message: message);

      notifyListeners();

      // 创建更新后的观看记录
      final updatedHistory = WatchHistoryItem(
        filePath: existingHistory.filePath,
        animeName: resolvedAnimeName,
        episodeTitle: (episodeTitle != null && episodeTitle.isNotEmpty)
            ? episodeTitle
            : existingHistory.episodeTitle,
        episodeId: episodeId ?? existingHistory.episodeId,
        animeId: animeId ?? existingHistory.animeId,
        watchProgress: existingHistory.watchProgress,
        lastPosition: existingHistory.lastPosition,
        duration: existingHistory.duration,
        lastWatchTime: existingHistory.lastWatchTime, // 保留上次观看时间，直到真正播放并更新进度
        thumbnailPath: existingHistory.thumbnailPath,
        isFromScan: existingHistory.isFromScan,
      );

      debugPrint(
          '准备保存更新后的观看记录，动画名: ${updatedHistory.animeName}, 集数: ${updatedHistory.episodeTitle}');

      // 保存更新后的记录
      if (_context != null && _context!.mounted) {
        await _context!
            .read<WatchHistoryProvider>()
            .addOrUpdateHistory(updatedHistory);
      } else {
        await WatchHistoryDatabase.instance
            .insertOrUpdateWatchHistory(updatedHistory);
      }

      debugPrint('成功更新观看记录');
    } catch (e) {
      debugPrint('更新观看记录时出错: $e');
      // 错误不应阻止视频播放
    }
  }

  // 计算文件前16MB数据的MD5哈希值
  Future<String> _calculateFileHash(String filePath) async {
    if (kIsWeb) {
      // 在Web平台上，我们没有直接的文件访问权限，所以返回一个基于路径的哈希值
      return md5.convert(utf8.encode(filePath)).toString();
    }
    if (filePath.startsWith('http://') ||
        filePath.startsWith('https://') ||
        filePath.startsWith('jellyfin://') ||
        filePath.startsWith('emby://')) {
      return md5.convert(utf8.encode(filePath)).toString();
    }
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('文件不存在: $filePath');
      }

      const int maxBytes = 16 * 1024 * 1024; // 16MB
      final bytes =
          await file.openRead(0, maxBytes).expand((chunk) => chunk).toList();
      return md5.convert(bytes).toString();
    } catch (e) {
      //debugPrint('计算文件哈希值失败: $e');
      // 返回一个基于文件名的备用哈希值
      return md5.convert(utf8.encode(filePath)).toString();
    }
  }

  // 添加缩略图更新监听器
  void addThumbnailUpdateListener(VoidCallback listener) {
    if (!_thumbnailUpdateListeners.contains(listener)) {
      _thumbnailUpdateListeners.add(listener);
    }
  }

  // 移除缩略图更新监听器
  void removeThumbnailUpdateListener(VoidCallback listener) {
    _thumbnailUpdateListeners.remove(listener);
  }

  // 通知所有缩略图更新监听器
  void _notifyThumbnailUpdateListeners() {
    for (final listener in _thumbnailUpdateListeners) {
      try {
        listener();
      } catch (e) {
        //debugPrint('缩略图更新监听器执行错误: $e');
      }
    }
  }

  // 立即更新观看记录中的缩略图
  Future<void> _updateWatchHistoryWithNewThumbnail(String thumbnailPath) async {
    if (_currentVideoPath == null) return;

    try {
      // 获取当前播放记录
      WatchHistoryItem? existingHistory;

      if (_context != null && _context!.mounted) {
        final watchHistoryProvider = _context!.read<WatchHistoryProvider>();
        existingHistory =
            await watchHistoryProvider.getHistoryItem(_currentVideoPath!);
      } else {
        existingHistory = await WatchHistoryDatabase.instance
            .getHistoryByFilePath(_currentVideoPath!);
      }

      if (existingHistory != null) {
        // 仅更新缩略图和时间戳，保留其他所有字段
        final updatedHistory = WatchHistoryItem(
          filePath: existingHistory.filePath,
          animeName: existingHistory.animeName,
          episodeTitle: existingHistory.episodeTitle,
          episodeId:
              _episodeId ?? existingHistory.episodeId, // 优先使用存储的 episodeId
          animeId: _animeId ?? existingHistory.animeId, // 优先使用存储的 animeId
          watchProgress: _progress, // 更新当前进度
          lastPosition: _position.inMilliseconds, // 更新当前位置
          duration: _duration.inMilliseconds,
          lastWatchTime: DateTime.now(),
          thumbnailPath: thumbnailPath,
          isFromScan: existingHistory.isFromScan,
        );

        // 保存更新后的记录
        if (_context != null && _context!.mounted) {
          await _context!
              .read<WatchHistoryProvider>()
              .addOrUpdateHistory(updatedHistory);
        } else {
          await WatchHistoryDatabase.instance
              .insertOrUpdateWatchHistory(updatedHistory);
        }

        debugPrint('观看记录缩略图已更新: $thumbnailPath');

        // 通知缩略图已更新，需要刷新UI
        _notifyThumbnailUpdateListeners();

        // 尝试刷新已显示的缩略图
        _triggerImageCacheRefresh(thumbnailPath);
      }
    } catch (e) {
      // 添加 stackTrace
      //debugPrint('更新观看记录缩略图时出错: $e\n$s'); // 打印堆栈信息
    }
  }
}
