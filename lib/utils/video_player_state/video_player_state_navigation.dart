part of video_player_state;

extension VideoPlayerStateNavigation on VideoPlayerState {
  // 播放上一话
  Future<void> playPreviousEpisode() async {
    if (!canPlayPreviousEpisode || _currentVideoPath == null) {
      debugPrint('[上一话] 无法播放上一话：检查条件不满足');
      return;
    }

    try {
      debugPrint('[上一话] 开始使用剧集导航服务查找上一话');

      // Jellyfin同步：如果是Jellyfin流媒体，先报告播放停止
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('jellyfin://')) {
        try {
          final itemId = _currentVideoPath!.replaceFirst('jellyfin://', '');
          final syncService = JellyfinPlaybackSyncService();
          final historyItem =
              await WatchHistoryManager.getHistoryItem(_currentVideoPath!);
          if (historyItem != null) {
            await syncService.reportPlaybackStopped(itemId, historyItem,
                isCompleted: false);
            debugPrint('[上一话] Jellyfin播放停止报告完成');
          }
        } catch (e) {
          debugPrint('[上一话] Jellyfin播放停止报告失败: $e');
        }
      }

      // Emby同步：如果是Emby流媒体，先报告播放停止
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('emby://')) {
        try {
          final itemId = _currentVideoPath!.replaceFirst('emby://', '');
          final syncService = EmbyPlaybackSyncService();
          final historyItem =
              await WatchHistoryManager.getHistoryItem(_currentVideoPath!);
          if (historyItem != null) {
            await syncService.reportPlaybackStopped(itemId, historyItem,
                isCompleted: false);
            debugPrint('[上一话] Emby播放停止报告完成');
          }
        } catch (e) {
          debugPrint('[上一话] Emby播放停止报告失败: $e');
        }
      }

      // 暂停当前视频
      if (_status == PlayerStatus.playing) {
        togglePlayPause();
      }

      // 使用剧集导航服务
      final navigationService = EpisodeNavigationService.instance;
      final result = await navigationService.getPreviousEpisode(
        currentFilePath: _currentVideoPath!,
        animeId: _animeId,
        episodeId: _episodeId,
      );

      if (result.success) {
        debugPrint('[上一话] ${result.message}');

        // 根据结果类型调用不同的播放逻辑
        if (result.historyItem != null) {
          // 从数据库找到的剧集，包含完整的历史信息
          final historyItem = result.historyItem!;

          // 检查是否为Jellyfin或Emby流媒体，如果是则需要获取实际的HTTP URL
          if (historyItem.filePath.startsWith('jellyfin://')) {
            try {
              // 从jellyfin://协议URL中提取episodeId（简单格式：jellyfin://episodeId）
              final episodeId =
                  historyItem.filePath.replaceFirst('jellyfin://', '');
              // 获取实际的HTTP流媒体URL
              final actualPlayUrl =
                  JellyfinService.instance.getStreamUrl(episodeId);
              debugPrint('[上一话] 获取Jellyfin流媒体URL: $actualPlayUrl');

              // 使用Jellyfin协议URL作为标识符，HTTP URL作为实际播放源
              await initializePlayer(historyItem.filePath,
                  historyItem: historyItem, actualPlayUrl: actualPlayUrl);
            } catch (e) {
              debugPrint('[上一话] 获取Jellyfin流媒体URL失败: $e');
              _showEpisodeErrorMessage('上一话', '获取流媒体URL失败: $e');
              return;
            }
          } else if (historyItem.filePath.startsWith('emby://')) {
            try {
              // 从emby://协议URL中提取episodeId（只取最后一部分）
              final embyPath = historyItem.filePath.replaceFirst('emby://', '');
              final pathParts = embyPath.split('/');
              final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
              // 获取实际的HTTP流媒体URL
              final actualPlayUrl =
                  await EmbyService.instance.getStreamUrl(episodeId);
              debugPrint('[上一话] 获取Emby流媒体URL: $actualPlayUrl');

              // 使用Emby协议URL作为标识符，HTTP URL作为实际播放源
              await initializePlayer(historyItem.filePath,
                  historyItem: historyItem, actualPlayUrl: actualPlayUrl);
            } catch (e) {
              debugPrint('[上一话] 获取Emby流媒体URL失败: $e');
              _showEpisodeErrorMessage('上一话', '获取流媒体URL失败: $e');
              return;
            }
          } else {
            // 本地文件或其他类型
            await initializePlayer(historyItem.filePath,
                historyItem: historyItem);
          }
        } else if (result.filePath != null) {
          // 从文件系统找到的文件，需要创建基本的历史记录
          final historyItemForPrevVideo = await WatchHistoryDatabase.instance
              .getHistoryByFilePath(result.filePath!);
          await initializePlayer(result.filePath!,
              historyItem: historyItemForPrevVideo);
        }
      } else {
        debugPrint('[上一话] ${result.message}');
        _showEpisodeNotFoundMessage('上一话');
      }
    } catch (e) {
      debugPrint('[上一话] 播放上一话时出错：$e');
      _showEpisodeErrorMessage('上一话', e.toString());
    }
  }

  // 播放下一话
  Future<void> playNextEpisode() async {
    if (!canPlayNextEpisode || _currentVideoPath == null) {
      debugPrint('[下一话] 无法播放下一话：检查条件不满足');
      return;
    }

    try {
      debugPrint('[下一话] 开始使用剧集导航服务查找下一话 (自动播放触发)');

      // Jellyfin同步：如果是Jellyfin流媒体，先报告播放停止
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('jellyfin://')) {
        try {
          final itemId = _currentVideoPath!.replaceFirst('jellyfin://', '');
          final syncService = JellyfinPlaybackSyncService();
          final historyItem =
              await WatchHistoryManager.getHistoryItem(_currentVideoPath!);
          if (historyItem != null) {
            await syncService.reportPlaybackStopped(itemId, historyItem,
                isCompleted: false);
            debugPrint('[下一话] Jellyfin播放停止报告完成');
          }
        } catch (e) {
          debugPrint('[下一话] Jellyfin播放停止报告失败: $e');
        }
      }

      // Emby同步：如果是Emby流媒体，先报告播放停止
      if (_currentVideoPath != null &&
          _currentVideoPath!.startsWith('emby://')) {
        try {
          final itemId = _currentVideoPath!.replaceFirst('emby://', '');
          final syncService = EmbyPlaybackSyncService();
          final historyItem =
              await WatchHistoryManager.getHistoryItem(_currentVideoPath!);
          if (historyItem != null) {
            await syncService.reportPlaybackStopped(itemId, historyItem,
                isCompleted: false);
            debugPrint('[下一话] Emby播放停止报告完成');
          }
        } catch (e) {
          debugPrint('[下一话] Emby播放停止报告失败: $e');
        }
      }

      // 暂停当前视频
      if (_status == PlayerStatus.playing) {
        togglePlayPause();
      }

      // 使用剧集导航服务
      final navigationService = EpisodeNavigationService.instance;
      final result = await navigationService.getNextEpisode(
        currentFilePath: _currentVideoPath!,
        animeId: _animeId,
        episodeId: _episodeId,
      );

      if (result.success) {
        debugPrint('[下一话] ${result.message}');

        // 根据结果类型调用不同的播放逻辑
        if (result.historyItem != null) {
          // 从数据库找到的剧集，包含完整的历史信息
          final historyItem = result.historyItem!;

          // 检查是否为Jellyfin或Emby流媒体，如果是则需要获取实际的HTTP URL
          if (historyItem.filePath.startsWith('jellyfin://')) {
            try {
              // 从jellyfin://协议URL中提取episodeId（简单格式：jellyfin://episodeId）
              final episodeId =
                  historyItem.filePath.replaceFirst('jellyfin://', '');
              // 获取实际的HTTP流媒体URL
              final actualPlayUrl =
                  JellyfinService.instance.getStreamUrl(episodeId);
              debugPrint('[下一话] 获取Jellyfin流媒体URL: $actualPlayUrl');

              // 使用Jellyfin协议URL作为标识符，HTTP URL作为实际播放源
              await initializePlayer(historyItem.filePath,
                  historyItem: historyItem, actualPlayUrl: actualPlayUrl);
            } catch (e) {
              debugPrint('[下一话] 获取Jellyfin流媒体URL失败: $e');
              _showEpisodeErrorMessage('下一话', '获取流媒体URL失败: $e');
              return;
            }
          } else if (historyItem.filePath.startsWith('emby://')) {
            try {
              // 从emby://协议URL中提取episodeId（只取最后一部分）
              final embyPath = historyItem.filePath.replaceFirst('emby://', '');
              final pathParts = embyPath.split('/');
              final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
              // 获取实际的HTTP流媒体URL
              final actualPlayUrl =
                  await EmbyService.instance.getStreamUrl(episodeId);
              debugPrint('[下一话] 获取Emby流媒体URL: $actualPlayUrl');

              // 使用Emby协议URL作为标识符，HTTP URL作为实际播放源
              await initializePlayer(historyItem.filePath,
                  historyItem: historyItem, actualPlayUrl: actualPlayUrl);
            } catch (e) {
              debugPrint('[下一话] 获取Emby流媒体URL失败: $e');
              _showEpisodeErrorMessage('下一话', '获取流媒体URL失败: $e');
              return;
            }
          } else {
            // 本地文件或其他类型
            await initializePlayer(historyItem.filePath,
                historyItem: historyItem);
          }
        } else if (result.filePath != null) {
          // 从文件系统找到的文件，需要创建基本的历史记录
          final historyItemForNextVideo = await WatchHistoryDatabase.instance
              .getHistoryByFilePath(result.filePath!);
          await initializePlayer(result.filePath!,
              historyItem: historyItemForNextVideo);
        }
      } else {
        debugPrint('[下一话] ${result.message}');
        _showEpisodeNotFoundMessage('下一话');
      }
    } catch (e) {
      debugPrint('[下一话] 播放下一话时出错：$e');
      _showEpisodeErrorMessage('下一话', e.toString());
    }
  }

  // 显示剧集未找到的消息
  void _showEpisodeNotFoundMessage(String episodeType) {
    if (_context != null) {
      final message = '没有找到可播放的$episodeType';
      debugPrint('[剧集切换] $message');
      // 这里可以添加SnackBar或其他UI提示
      // ScaffoldMessenger.of(_context!).showSnackBar(
      //   SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      // );
    }
  }

  // 显示剧集错误消息
  void _showEpisodeErrorMessage(String episodeType, String error) {
    if (_context != null) {
      final message = '播放$episodeType时出错：$error';
      debugPrint('[剧集切换] $message');
      // 这里可以添加SnackBar或其他UI提示
      // ScaffoldMessenger.of(_context!).showSnackBar(
      //   SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      // );
    }
  }

  // 启动UI更新定时器（根据弹幕内核类型设置不同的更新频率，同时处理数据保存）
  void _startUiUpdateTimer() {
    // 取消现有定时器；Ticker仅在需要时复用
    _uiUpdateTimer?.cancel();
    // 若已有Ticker，先停止，避免重复启动造成持续产帧
    _uiUpdateTicker?.stop();

    // 记录上次更新时间，用于计算时间增量
    _lastTickTime = DateTime.now().millisecondsSinceEpoch;
    // 初始化节流时间戳
    _lastUiNotifyMs = _lastTickTime;
    _lastSaveTimeMs = _lastTickTime;
    _lastSavedPositionMs = _position.inMilliseconds;

    // 🔥 关键优化：使用Ticker代替Timer.periodic
    // Ticker会与显示刷新率同步，更精确地控制帧率
    // 如未创建过，则创建Ticker；注意此Ticker不受TickerMode影响（非Widget上下文），需手动启停
    _uiUpdateTicker ??= Ticker((elapsed) async {
      // 计算从上次更新到现在的时间增量
      final nowTime = DateTime.now().millisecondsSinceEpoch;
      final deltaTime = nowTime - _lastTickTime;
      _lastTickTime = nowTime;
      final bool shouldUiNotify =
          (nowTime - _lastUiNotifyMs) >= _uiUpdateIntervalMs;

      // 更新弹幕控制器的时间戳
      if (danmakuController != null) {
        try {
          // 使用反射安全调用updateTick方法，不论是哪种内核
          // 这是一种动态方法调用，可以处理不同弹幕控制器
          final updateTickMethod = danmakuController?.updateTick;
          if (updateTickMethod != null && updateTickMethod is Function) {
            updateTickMethod(deltaTime);
          }
        } catch (e) {
          // 静默处理错误，避免影响主流程
          debugPrint('更新弹幕时间戳失败: $e');
        }
      }

      if (!_isSeeking && hasVideo) {
        if (_status == PlayerStatus.playing) {
          final playerPosition = player.position;
          final playerDuration = player.mediaInfo.duration;

          if (playerPosition >= 0 && playerDuration > 0) {
            // 更新UI显示
            _position = Duration(milliseconds: playerPosition);
            _duration = Duration(milliseconds: playerDuration);
            _progress = _position.inMilliseconds / _duration.inMilliseconds;
            // 高频时间轴：每帧更新弹幕时间
            _playbackTimeMs.value = _position.inMilliseconds.toDouble();

            // 节流保存播放位置：时间或位移达到阈值时才写
            if (_currentVideoPath != null) {
              final int posMs = _position.inMilliseconds;
              final bool byTime =
                  (nowTime - _lastSaveTimeMs) >= _positionSaveIntervalMs;
              final bool byDelta = (_lastSavedPositionMs < 0) ||
                  ((posMs - _lastSavedPositionMs).abs() >=
                      _positionSaveDeltaThresholdMs);
              if (byTime || byDelta) {
                _saveVideoPosition(_currentVideoPath!, posMs);
                _lastSaveTimeMs = nowTime;
                _lastSavedPositionMs = posMs;
              }
            }

            // 每10秒更新一次观看记录（使用分桶去抖，避免在窗口内重复调用）
            final int currentBucket = _position.inMilliseconds ~/ 10000;
            if (currentBucket != _lastHistoryUpdateBucket) {
              _lastHistoryUpdateBucket = currentBucket;
              _updateWatchHistory();
            }

            // 检测播放结束
            if (_position.inMilliseconds >= _duration.inMilliseconds - 100) {
              player.state = PlaybackState.paused;
              _setStatus(PlayerStatus.paused, message: '播放结束');
              if (_currentVideoPath != null) {
                _saveVideoPosition(_currentVideoPath!, 0);
                debugPrint(
                    'VideoPlayerState: Video ended, explicitly saved position 0 for $_currentVideoPath');

                // Jellyfin同步：如果是Jellyfin流媒体，报告播放结束
                if (_currentVideoPath!.startsWith('jellyfin://')) {
                  _handleJellyfinPlaybackEnd(_currentVideoPath!);
                }

                // Emby同步：如果是Emby流媒体，报告播放结束
                if (_currentVideoPath!.startsWith('emby://')) {
                  _handleEmbyPlaybackEnd(_currentVideoPath!);
                }

                // 播放结束时触发自动云同步
                try {
                  await AutoSyncService.instance.syncOnPlaybackEnd();
                } catch (e) {
                  debugPrint('播放结束时云同步失败: $e');
                }

                // 根据用户设置处理播放结束行为
                await _handlePlaybackEndAction();
              }
            }

            if (shouldUiNotify) {
              _lastUiNotifyMs = nowTime;
              notifyListeners();
            }
          } else {
            // 错误处理逻辑（原来在10秒定时器中）
            // 当播放器返回无效的 position 或 duration 时
            // 增加额外检查以避免在字幕操作等特殊情况下误报

            // 如果之前已经有有效的时长信息，而现在临时返回0，可能是正常的操作过程
            final bool hasValidDurationBefore = _duration.inMilliseconds > 0;
            final bool isTemporaryInvalid = hasValidDurationBefore &&
                playerPosition == 0 &&
                playerDuration == 0;

            // 检查是否是Jellyfin流媒体正在初始化
            final bool isJellyfinInitializing = _currentVideoPath != null &&
                (_currentVideoPath!.contains('jellyfin://') ||
                    _currentVideoPath!.contains('emby://')) &&
                _status == PlayerStatus.loading;

            // 检查是否是播放器正在重置过程中
            final bool isPlayerResetting = player.state ==
                    PlaybackState.stopped &&
                (_status == PlayerStatus.idle || _status == PlayerStatus.error);

            // 检查是否正在执行resetPlayer操作
            final bool isInResetProcess =
                _currentVideoPath == null && _status == PlayerStatus.idle;

            if (isTemporaryInvalid ||
                isJellyfinInitializing ||
                isPlayerResetting ||
                isInResetProcess ||
                _isResetting) {
              // 跳过错误检测的各种情况
              return;
            }

            final String pathForErrorLog = _currentVideoPath ?? "未知路径";
            final String baseName = p.basename(pathForErrorLog);

            // 优先使用来自播放器适配器的特定错误消息
            String userMessage;
            if (player.mediaInfo.specificErrorMessage != null &&
                player.mediaInfo.specificErrorMessage!.isNotEmpty) {
              userMessage = player.mediaInfo.specificErrorMessage!;
            } else {
              final String technicalDetail =
                  '(pos: $playerPosition, dur: $playerDuration)';
              userMessage = '视频文件 "$baseName" 可能已损坏或无法读取 $technicalDetail';
            }

            debugPrint(
                'VideoPlayerState: 播放器返回无效的视频数据 (position: $playerPosition, duration: $playerDuration) 路径: $pathForErrorLog. 错误信息: $userMessage. 已停止播放并设置为错误状态.');

            _error = userMessage;

            player.state = PlaybackState.stopped;

            // 停止定时器和Ticker
            if (_uiUpdateTicker?.isTicking ?? false) {
              _uiUpdateTicker!.stop();
              _uiUpdateTicker!.dispose();
              _uiUpdateTicker = null;
            }

            _setStatus(PlayerStatus.error, message: userMessage);

            _position = Duration.zero;
            _progress = 0.0;
            _duration = Duration.zero;

            WidgetsBinding.instance.addPostFrameCallback((_) async {
              // 1. 执行 handleBackButton 逻辑 (处理全屏、截图等)
              await handleBackButton();

              // 2. DO NOT call resetPlayer() here. The dialog's action will call it.

              // 3. 通知UI层执行pop/显示对话框等
              onSeriousPlaybackErrorAndShouldPop?.call();
            });

            return;
          }
        } else if (_status == PlayerStatus.paused &&
            _lastSeekPosition != null) {
          // 暂停状态：使用最后一次seek的位置
          _position = _lastSeekPosition!;
          _playbackTimeMs.value = _position.inMilliseconds.toDouble();
          if (_duration.inMilliseconds > 0) {
            _progress = _position.inMilliseconds / _duration.inMilliseconds;
            // 暂停下也节流保存位置
            if (_currentVideoPath != null) {
              final int posMs = _position.inMilliseconds;
              final bool byTime =
                  (nowTime - _lastSaveTimeMs) >= _positionSaveIntervalMs;
              final bool byDelta = (_lastSavedPositionMs < 0) ||
                  ((posMs - _lastSavedPositionMs).abs() >=
                      _positionSaveDeltaThresholdMs);
              if (byTime || byDelta) {
                _saveVideoPosition(_currentVideoPath!, posMs);
                _lastSaveTimeMs = nowTime;
                _lastSavedPositionMs = posMs;
              }
            }

            // 暂停状态下，只在位置变化时更新观看记录
            _updateWatchHistory();
          }
          if (shouldUiNotify) {
            _lastUiNotifyMs = nowTime;
            notifyListeners();
          }
        }
      }
    });

    // 仅在真正播放时启动Ticker；其他状态保持停止以避免空闲帧
    if (_status == PlayerStatus.playing) {
      _uiUpdateTicker!.start();
      debugPrint('启动UI更新Ticker（playing）');
    } else {
      _uiUpdateTicker!.stop();
      debugPrint('已准备UI更新Ticker但未启动（status=$_status）');
    }
  }
}
