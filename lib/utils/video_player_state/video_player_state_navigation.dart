part of video_player_state;

extension VideoPlayerStateNavigation on VideoPlayerState {
  // 播放上一话
  Future<void> playPreviousEpisode() async {
    if (!canPlayPreviousEpisode || _currentVideoPath == null) {
      debugPrint('[上一话] 无法播放上一话：检查条件不满足');
      return;
    }

    if (_isEpisodeNavigating) {
      debugPrint('[上一话] 已有切集任务，忽略本次请求');
      _showNavigationBusyMessage('上一话');
      return;
    }

    _isEpisodeNavigating = true;

    try {
      debugPrint('[上一话] 开始使用剧集导航服务查找上一话');

      _showEpisodeNavigationDialog('上一话');

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

        WatchHistoryItem? historyItem = result.historyItem;

        if (historyItem == null && result.filePath != null) {
          historyItem = await WatchHistoryDatabase.instance
              .getHistoryByFilePath(result.filePath!);
        }

        if (historyItem == null && result.filePath != null) {
          // 为本地文件构造简易历史项
          historyItem = WatchHistoryItem(
            filePath: result.filePath!,
            animeName: '未知',
            watchProgress: 0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
          );
        }

        if (historyItem != null &&
            WatchHistoryAutoMatchHelper.shouldAutoMatch(historyItem)) {
          historyItem = await _tryAutoMatchForNavigation(historyItem);
        }

        if (historyItem != null) {
          // 从数据库找到的剧集，包含完整的历史信息
          final resolvedHistory = historyItem;
          // 检查是否为Jellyfin或Emby流媒体，如果是则需要获取实际的HTTP URL
          if (resolvedHistory.filePath.startsWith('jellyfin://')) {
            try {
              // 从jellyfin://协议URL中提取episodeId（简单格式：jellyfin://episodeId）
              final episodeId =
                  resolvedHistory.filePath.replaceFirst('jellyfin://', '');
              final playbackSession =
                  await JellyfinService.instance.createPlaybackSession(
                itemId: episodeId,
                startPositionMs: resolvedHistory.lastPosition > 0
                    ? resolvedHistory.lastPosition
                    : null,
              );
              debugPrint('[上一话] 获取Jellyfin播放会话: ${playbackSession.streamUrl}');

              await initializePlayer(
                resolvedHistory.filePath,
                historyItem: resolvedHistory,
                playbackSession: playbackSession,
              );
            } catch (e) {
              debugPrint('[上一话] 获取Jellyfin播放会话失败: $e');
              _showEpisodeErrorMessage('上一话', '获取播放会话失败: $e');
              return;
            }
          } else if (resolvedHistory.filePath.startsWith('emby://')) {
            try {
              // 从emby://协议URL中提取episodeId（只取最后一部分）
              final embyPath =
                  resolvedHistory.filePath.replaceFirst('emby://', '');
              final pathParts = embyPath.split('/');
              final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
              final playbackSession =
                  await EmbyService.instance.createPlaybackSession(
                itemId: episodeId,
                startPositionMs: resolvedHistory.lastPosition > 0
                    ? resolvedHistory.lastPosition
                    : null,
              );
              debugPrint('[上一话] 获取Emby播放会话: ${playbackSession.streamUrl}');

              await initializePlayer(
                resolvedHistory.filePath,
                historyItem: resolvedHistory,
                playbackSession: playbackSession,
              );
            } catch (e) {
              debugPrint('[上一话] 获取Emby播放会话失败: $e');
              _showEpisodeErrorMessage('上一话', '获取播放会话失败: $e');
              return;
            }
          } else {
            // 本地文件或其他类型
            await initializePlayer(resolvedHistory.filePath,
                historyItem: resolvedHistory);
          }
        } else {
          _showEpisodeErrorMessage('上一话', '无法加载上一话的历史记录');
        }
      } else {
        debugPrint('[上一话] ${result.message}');
        _showEpisodeNotFoundMessage('上一话');
      }
    } catch (e) {
      debugPrint('[上一话] 播放上一话时出错：$e');
      _showEpisodeErrorMessage('上一话', e.toString());
    } finally {
      _hideEpisodeNavigationDialog();
      _isEpisodeNavigating = false;
    }
  }

  // 播放下一话
  Future<void> playNextEpisode() async {
    if (!canPlayNextEpisode || _currentVideoPath == null) {
      debugPrint('[下一话] 无法播放下一话：检查条件不满足');
      return;
    }

    if (_isEpisodeNavigating) {
      debugPrint('[下一话] 已有切集任务，忽略本次请求');
      _showNavigationBusyMessage('下一话');
      return;
    }

    _isEpisodeNavigating = true;

    try {
      debugPrint('[下一话] 开始使用剧集导航服务查找下一话 (自动播放触发)');

      _showEpisodeNavigationDialog('下一话');

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

        WatchHistoryItem? historyItem = result.historyItem;

        if (historyItem == null && result.filePath != null) {
          historyItem = await WatchHistoryDatabase.instance
              .getHistoryByFilePath(result.filePath!);
        }

        if (historyItem == null && result.filePath != null) {
          historyItem = WatchHistoryItem(
            filePath: result.filePath!,
            animeName: '未知',
            watchProgress: 0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
          );
        }

        if (historyItem != null &&
            WatchHistoryAutoMatchHelper.shouldAutoMatch(historyItem)) {
          historyItem = await _tryAutoMatchForNavigation(historyItem);
        }

        if (historyItem != null) {
          // 从数据库找到的剧集，包含完整的历史信息
          final resolvedHistory = historyItem;
          // 检查是否为Jellyfin或Emby流媒体，如果是则需要获取实际的HTTP URL
          if (resolvedHistory.filePath.startsWith('jellyfin://')) {
            try {
              // 从jellyfin://协议URL中提取episodeId（简单格式：jellyfin://episodeId）
              final episodeId =
                  resolvedHistory.filePath.replaceFirst('jellyfin://', '');
              final playbackSession =
                  await JellyfinService.instance.createPlaybackSession(
                itemId: episodeId,
                startPositionMs: resolvedHistory.lastPosition > 0
                    ? resolvedHistory.lastPosition
                    : null,
              );
              debugPrint('[下一话] 获取Jellyfin播放会话: ${playbackSession.streamUrl}');

              await initializePlayer(
                resolvedHistory.filePath,
                historyItem: resolvedHistory,
                playbackSession: playbackSession,
              );
            } catch (e) {
              debugPrint('[下一话] 获取Jellyfin播放会话失败: $e');
              _showEpisodeErrorMessage('下一话', '获取播放会话失败: $e');
              return;
            }
          } else if (resolvedHistory.filePath.startsWith('emby://')) {
            try {
              // 从emby://协议URL中提取episodeId（只取最后一部分）
              final embyPath =
                  resolvedHistory.filePath.replaceFirst('emby://', '');
              final pathParts = embyPath.split('/');
              final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
              final playbackSession =
                  await EmbyService.instance.createPlaybackSession(
                itemId: episodeId,
                startPositionMs: resolvedHistory.lastPosition > 0
                    ? resolvedHistory.lastPosition
                    : null,
              );
              debugPrint('[下一话] 获取Emby播放会话: ${playbackSession.streamUrl}');

              await initializePlayer(
                resolvedHistory.filePath,
                historyItem: resolvedHistory,
                playbackSession: playbackSession,
              );
            } catch (e) {
              debugPrint('[下一话] 获取Emby播放会话失败: $e');
              _showEpisodeErrorMessage('下一话', '获取播放会话失败: $e');
              return;
            }
          } else {
            // 本地文件或其他类型
            await initializePlayer(resolvedHistory.filePath,
                historyItem: resolvedHistory);
          }
        } else {
          _showEpisodeErrorMessage('下一话', '无法加载下一话的历史记录');
        }
      } else {
        debugPrint('[下一话] ${result.message}');
        _showEpisodeNotFoundMessage('下一话');
      }
    } catch (e) {
      debugPrint('[下一话] 播放下一话时出错：$e');
      _showEpisodeErrorMessage('下一话', e.toString());
    } finally {
      _hideEpisodeNavigationDialog();
      _isEpisodeNavigating = false;
    }
  }

  Future<WatchHistoryItem?> _tryAutoMatchForNavigation(
    WatchHistoryItem historyItem,
  ) async {
    if (_context == null || !_context!.mounted) {
      return historyItem;
    }

    final matchablePath = await _resolveMatchablePath(historyItem.filePath);
    if (matchablePath == null) {
      return historyItem;
    }

    return await WatchHistoryAutoMatchHelper.tryAutoMatch(
      _context!,
      historyItem,
      matchablePath: matchablePath,
      onMatched: (msg) => BlurSnackBar.show(_context!, msg),
    );
  }

  Future<String?> _resolveMatchablePath(String filePath) async {
    if (filePath.startsWith('jellyfin://')) {
      final episodeId = filePath.replaceFirst('jellyfin://', '');
      if (!JellyfinService.instance.isConnected) {
        return null;
      }
      return JellyfinService.instance.getStreamUrlWithOptions(
        episodeId,
        forceDirectPlay: true,
      );
    }
    if (filePath.startsWith('emby://')) {
      final embyPath = filePath.replaceFirst('emby://', '');
      final episodeId = embyPath.split('/').last;
      if (!EmbyService.instance.isConnected) {
        return null;
      }
      return EmbyService.instance.getStreamUrlWithOptions(
        episodeId,
        forceDirectPlay: true,
      );
    }
    return filePath;
  }

  void _showNavigationBusyMessage(String episodeType) {
    if (_context == null || !_context!.mounted) {
      return;
    }
    BlurSnackBar.show(_context!, '正在处理$episodeType请求，请稍候');
  }

  void _showEpisodeNavigationDialog(String episodeType) {
    if (_context == null || !_context!.mounted || _navigationDialogVisible) {
      return;
    }

    if (!_shouldShowNavigationDialog()) {
      return;
    }
    _navigationDialogVisible = true;
    BlurDialog.show(
      context: _context!,
      title: '正在搜索$episodeType',
      barrierDismissible: false,
      contentWidget: _buildEpisodeNavigationDialogContent(),
    ).whenComplete(() {
      _navigationDialogVisible = false;
    });
  }

  bool _shouldShowNavigationDialog() {
    if (_currentVideoPath == null) {
      return false;
    }
    return _currentVideoPath!.startsWith('jellyfin://') ||
        _currentVideoPath!.startsWith('emby://');
  }

  void _hideEpisodeNavigationDialog() {
    if (!_navigationDialogVisible || _context == null || !_context!.mounted) {
      return;
    }
    Navigator.of(_context!, rootNavigator: true).pop();
    _navigationDialogVisible = false;
  }

  Widget _buildEpisodeNavigationDialogContent() {
    final isCupertinoTheme = _context != null && _context!.mounted
        ? Provider.of<UIThemeProvider>(_context!, listen: false)
            .isCupertinoTheme
        : false;

    final Widget indicator = isCupertinoTheme
        ? const CupertinoActivityIndicator(radius: 12)
        : const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          );

    final TextStyle textStyle = isCupertinoTheme
        ? const TextStyle(
            color: CupertinoColors.secondaryLabel,
            fontSize: 14,
          )
        : const TextStyle(
            color: Colors.white,
            fontSize: 14,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 8),
        indicator,
        const SizedBox(height: 16),
        Text(
          '正在定位剧集并匹配弹幕，请稍候…',
          style: textStyle,
          textAlign: TextAlign.center,
        ),
      ],
    );
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
    if (!kReleaseMode) {
      debugPrint('[LOOP-RESTART-DIAG] _startUiUpdateTimer() CALLED: '
          '_status=$_status _seekTargetMs=$_seekTargetMs '
          '_lastRawPlayerMs=$_lastRawPlayerMs '
          'tickerExisted=${_uiUpdateTicker != null}');
    }
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
    // 重置平滑时钟锚点，下次 Ticker 回调时重新对齐
    _lastRawPlayerMs = -1;
    _anchorSetBySeek = false; // 新 Ticker 实例首帧锚点非 seek 设置
    // [VIDEO-OPEN-PTM-DIAG] 根因2辅助：追踪 _startUiUpdateTimer 时的 playbackTimeMs 状态
    // 假设：此时 playbackTimeMs=0（由 _resetVideoState 设置），
    // Ticker 首帧锚定到 player.position（可能也是0），导致弹幕从头播放
    if (!kReleaseMode) {
      debugPrint('[VIDEO-OPEN-PTM-DIAG] _startUiUpdateTimer: '
          'playbackTimeMs=${_playbackTimeMs.value.toStringAsFixed(1)} '
          '_position=${_position.inMilliseconds} '
          '_smoothAnchorMs=${_smoothAnchorMs.toStringAsFixed(1)} '
          '_seekTargetMs=$_seekTargetMs '
          '_status=$_status ← Ticker will anchor to player.position on first frame');
    }
    // [NEXT-DIAG] 重置帧间隔基线，避免跨 Ticker 实例的假阳性
    _lastElapsedUs = 0;
    _diagBaselineFrameUs = 0;
    _diagFrameSampleCount = 0;

    // 🔥 关键优化：使用Ticker代替Timer.periodic
    // Ticker会与显示刷新率同步，更精确地控制帧率
    // 如未创建过，则创建Ticker；注意此Ticker不受TickerMode影响（非Widget上下文），需手动启停
    _uiUpdateTicker ??= Ticker((elapsed) async {
      // 计算从上次更新到现在的时间增量
      final nowTime = DateTime.now().millisecondsSinceEpoch;
      final deltaTime = nowTime - _lastTickTime;
      _lastTickTime = nowTime;
      final bool shouldUiNotify =
          (nowTime - _lastUiNotifyMs) >= effectiveUiUpdateIntervalMs;

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
            // 同步当前章节索引（MKV 自带章节，参考 mpv playloop.c:607 get_current_chapter）
            _updateCurrentChapterFromPosition(playerPosition);
            final previousDurationMs = _duration.inMilliseconds;
            final previousSubtitleDelay = subtitleDelaySeconds;
            _duration = Duration(milliseconds: playerDuration);
            if (previousDurationMs != playerDuration &&
                (previousSubtitleDelay - subtitleDelaySeconds).abs() >=
                    0.0001) {
              unawaited(applySubtitleStylePreference());
            }
            _progress = _position.inMilliseconds / _duration.inMilliseconds;
            final bufferedMs = player.bufferedPosition;
            _bufferedPositionMs = bufferedMs <= 0
                ? 0
                : (_duration.inMilliseconds > 0
                    ? bufferedMs.clamp(0, _duration.inMilliseconds).toInt()
                    : bufferedMs);
            // 高频时间轴：每帧更新弹幕时间（Ticker elapsed 插值，微秒精度）
            // player.position 返回整数 ms，直接使用会导致 16/17ms 交替增量，
            // 造成滚动弹幕每帧约 1px 的位置抖动（频闪）。
            // 解决方案：以 player.position 为锚点，用 Ticker.elapsed（微秒精度、
            // 与 vsync 精确同步）在锚点间线性插值，获得均匀的亚毫秒推进；
            // 漂移过大时（seek/暂停恢复）立即对齐。
            final currentElapsedUs = elapsed.inMicroseconds;
            // [NEXT-DIAG] 检测帧丢失：自适应基线，前30帧采样最小帧间隔，
            // 超过基线2倍则判定跳帧，2秒节流
            if (kDebugMode && _lastElapsedUs > 0) {
              final frameDeltaUs = currentElapsedUs - _lastElapsedUs;
              if (_diagFrameSampleCount < 30) {
                // 采样阶段：收集最小帧间隔作为基线
                _diagFrameSampleCount++;
                if (frameDeltaUs > 0 &&
                    (_diagBaselineFrameUs == 0 || frameDeltaUs < _diagBaselineFrameUs)) {
                  _diagBaselineFrameUs = frameDeltaUs;
                }
              } else if (_diagBaselineFrameUs > 0 &&
                  frameDeltaUs > _diagBaselineFrameUs * 2) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - _lastDiagFrameSkipTimeMs >= 2000) {
                  _lastDiagFrameSkipTimeMs = now;
                  debugPrint('[NEXT-DIAG] FRAME SKIP: $frameDeltaUs μs '
                      '(baseline=${_diagBaselineFrameUs}μs) '
                      'at playback=${playerPosition}ms');
                }
              }
            }
            _lastElapsedUs = currentElapsedUs;
            final playerMs = playerPosition.toDouble();

            // seek 保护：player.position 更新有延迟，在它追上 seekTarget 之前
            // 保持锚定在 seek 目标位置，避免弹幕闪回旧位置
            if (_seekTargetMs != null) {
              if ((playerMs - _seekTargetMs!).abs() < 100.0) {
                // player.position 已追上 seek 目标，恢复正常插值
                // [LOOP-RESTART-DIAG] 诊断：seek 保护结束
                if (!kReleaseMode) {
                  debugPrint('[LOOP-RESTART-DIAG] SEEK CAUGHT UP: '
                      'playerMs=${playerMs.toStringAsFixed(1)} '
                      'seekTargetMs=${_seekTargetMs!.toStringAsFixed(1)} '
                      'ptm=${_playbackTimeMs.value.toStringAsFixed(1)}');
                }
                _seekTargetMs = null; // [SEEK-TRACE] source=SEEK-CAUGHT-UP
                _smoothAnchorMs = playerMs;
                _smoothAnchorElapsedUs = currentElapsedUs;
                _lastRawPlayerMs = playerPosition;
                _anchorSetBySeek = false; // seek 完成，锚点已对齐到实际位置
              } else {
                // 还在等待 player.position 追上，从 seekTarget 插值推进
                final elapsedDeltaUs = currentElapsedUs - _smoothAnchorElapsedUs;
                _playbackTimeMs.value = (_smoothAnchorMs + elapsedDeltaUs / 1000.0 * effectivePlaybackRate)
                    .clamp(0.0, _duration.inMilliseconds.toDouble());
              }
            } else if (_lastRawPlayerMs < 0) {
              // 首帧或重置后：锚定
              // ✅ P3 修复：暂停恢复场景下，play() 已设置 _smoothAnchorMs = 暂停时的值，
              // _smoothAnchorElapsedUs = 0。此时不应让 player.position 覆盖锚点，
              // 而是直接用已设置的锚点插值推进，让漂移修正自然校准。
              final isResumeFromPause = _smoothAnchorElapsedUs == 0 && _playbackTimeMs.value > 100.0;

              if (isResumeFromPause) {
                // 暂停恢复：锚点已在 play() 中设置，直接插值推进
                final elapsedDeltaUs = currentElapsedUs - _smoothAnchorElapsedUs;
                final newPtm = (_smoothAnchorMs + elapsedDeltaUs / 1000.0 * effectivePlaybackRate)
                    .clamp(0.0, _duration.inMilliseconds.toDouble());
                _playbackTimeMs.value = newPtm;
                // 标记 _lastRawPlayerMs 让下一帧走漂移修正路径
                // 但不立即锚定到 playerMs，让漂移修正渐进收敛
                _lastRawPlayerMs = playerPosition;
                if (!kReleaseMode) {
                  debugPrint('[RESUME-PAUSE-DIAG] Resume from pause: '
                      'anchorMs=${_smoothAnchorMs.toStringAsFixed(1)} '
                      'playerMs=${playerMs.toStringAsFixed(1)} '
                      'ptm=${newPtm.toStringAsFixed(1)} '
                      'delta=${(newPtm - playerMs).toStringAsFixed(1)}ms');
                }
              } else {
              // ✅ 防御性修复(V3)：检测过期 playerMs
              // 核心判断：如果 playbackTimeMs ≈ 0（刚被重置）且 playerMs >> 0，
              // 则 playerMs 一定是过期数据（旧视频/旧位置），无论 _anchorSetBySeek 是什么值。
              // 没有合法场景会同时出现 playbackTimeMs=0 和 playerMs=1420007。
              // 合法首帧加载：playbackTimeMs=恢复位置, playerMs=恢复位置 → 信任
              // 合法从头播放：playbackTimeMs=0, playerMs≈0 → 信任
              // 过期数据：playbackTimeMs=0(刚重置), playerMs=旧末尾 → 不信任
              final anchorDelta = (playerMs - _smoothAnchorMs).abs();
              final prevPtm = _playbackTimeMs.value;
              final ptmDelta = (playerMs - prevPtm).abs();
              // 过期检测：playbackTimeMs 接近 0 且 playerMs 远离 0 → playerMs 是旧值
              // 扩展（2026-06-21）：覆盖切集反向场景
              // 原判定 prevPtm<100 && playerMs>1000 只覆盖"playbackTimeMs 归零 + playerMs 旧末尾"
              // 切集反向场景：prevPtm=旧集末尾(大) + playerMs=新集开头(小) → 原判定不触发
              // → 走 FIRST-ANCHOR 把新集 playerMs 当有效值 → playbackTimeMs 突跌 → 回弹
              // 扩展：prevPtm>1000 且 playerMs<prevPtm-1000 也视为污染，启用 seek 保护
              final isStalePlayerMs = (prevPtm < 100.0 && playerMs > 1000.0) ||
                  (prevPtm > 1000.0 && playerMs < prevPtm - 1000.0);
              if (!kReleaseMode) {
                debugPrint('[LOOP-RESTART-DIAG] TICKER LAST_RAW<0: '
                    'playerMs=${playerMs.toStringAsFixed(1)} '
                    'prevPtm=${prevPtm.toStringAsFixed(1)} '
                    'ptmDelta=${ptmDelta.toStringAsFixed(1)} '
                    'smoothAnchorMs=${_smoothAnchorMs.toStringAsFixed(1)} '
                    'anchorDelta=${anchorDelta.toStringAsFixed(1)} '
                    'seekTargetMs=$_seekTargetMs '
                    'anchorSetBySeek=$_anchorSetBySeek '
                    'isStale=$isStalePlayerMs');
              }
              if (isStalePlayerMs) {
                // playerMs 是过期数据（旧视频位置），不信任它
                // 保持 playbackTimeMs 不变，启用 seek 保护等待 player.position 追上
                _smoothAnchorElapsedUs = currentElapsedUs;
                _seekTargetMs = prevPtm > 0.0 ? prevPtm : _smoothAnchorMs;
                _lastRawPlayerMs = -1; // 保持负值，让 seek 保护分支接管下一帧
                // playbackTimeMs 保持当前值（不跳到过期 playerMs）
                final elapsedDeltaUs = currentElapsedUs - _smoothAnchorElapsedUs;
                _playbackTimeMs.value = (_seekTargetMs! + elapsedDeltaUs / 1000.0 * effectivePlaybackRate)
                    .clamp(0.0, _duration.inMilliseconds.toDouble());
                if (!kReleaseMode) {
                  debugPrint('[LOOP-RESTART-DIAG] STALE PLAYER: '
                      'rejecting stale playerMs=${playerMs.toStringAsFixed(1)} '
                      'anchoring to seekTargetMs=${_seekTargetMs?.toStringAsFixed(1)} '
                      'prevPtm=${prevPtm.toStringAsFixed(1)}');
                }
              } else {
                // playerMs 合法：首帧加载/恢复位置/从头播放 → 正常锚定
                // ✅ P7修复：首帧锚定路径添加P1单调递增保护
                // 根因：暂停恢复后 player.position 可能回退（比暂停前小），
                // 直接赋值 _playbackTimeMs.value = playerMs 会导致 playbackTimeMs 回退 → 弹幕回弹。
                // 修复：与锚点过期重锚路径（line 712-729）保持一致的单调递增保护逻辑。
                final newPtmCandidate = playerMs.clamp(0.0, _duration.inMilliseconds.toDouble());
                if (newPtmCandidate < _playbackTimeMs.value - 0.5 && _playbackTimeMs.value > 100.0) {
                  // playerMs 回退 → 保持 prevPtm，锚定到 prevPtm 使后续帧正常推进
                  _smoothAnchorMs = _playbackTimeMs.value;
                  _smoothAnchorElapsedUs = currentElapsedUs;
                  _lastRawPlayerMs = playerPosition;
                  _anchorSetBySeek = false;
                  // playbackTimeMs 保持不变（hold）
                  if (!kReleaseMode) {
                    debugPrint('[FIRST-ANCHOR-DIAG] BACKWARD PREVENTED: '
                        'prevPtm=${_playbackTimeMs.value.toStringAsFixed(1)} → playerMs=${playerMs.toStringAsFixed(1)} '
                        'delta=${(newPtmCandidate - _playbackTimeMs.value).toStringAsFixed(1)}ms '
                        'rate=$effectivePlaybackRate ← held at prevPtm, anchor=prevPtm');
                  }
                } else {
                  _smoothAnchorMs = playerMs;
                  _smoothAnchorElapsedUs = currentElapsedUs;
                  _lastRawPlayerMs = playerPosition;
                  _anchorSetBySeek = false;
                  _playbackTimeMs.value = newPtmCandidate;
                }
              }
              }
            } else {
              // 正常播放：检测锚点是否过期（seek/暂停恢复后第一帧）
              final elapsedDeltaUs = currentElapsedUs - _smoothAnchorElapsedUs;
              if (elapsedDeltaUs > 50000) {
                // 锚点距今超过 50ms，说明经历了 seek/暂停等中断，
                // 重新锚定到当前 player.position，避免插值跳变
                // [PTM-ANCHOR-EXPIRE-DIAG] 根因1辅助诊断：追踪锚点过期重锚定
                // 假设：暂停后恢复，锚点过期 → 直接对齐到 playerMs →
                // 如果 playerMs < playbackTimeMs（player.position 回退），playbackTimeMs 回跳
                if (!kReleaseMode) {
                  final prevPtm = _playbackTimeMs.value;
                  final anchorAgeMs = elapsedDeltaUs / 1000.0;
                  if (playerMs < prevPtm - 1.0 && prevPtm > 100.0) {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (now - _lastDiagPtmBackwardMs >= 500) {
                      _lastDiagPtmBackwardMs = now;
                      debugPrint('[PTM-ANCHOR-EXPIRE-DIAG] ANCHOR EXPIRE causes ptm BACKWARD: '
                          'anchorAge=${anchorAgeMs.toStringAsFixed(1)}ms > 50ms → snap to playerMs '
                          'prevPtm=${prevPtm.toStringAsFixed(1)} → playerMs=${playerMs.toStringAsFixed(1)} '
                          'delta=${(playerMs - prevPtm).toStringAsFixed(1)}ms '
                          'rate=$effectivePlaybackRate');
                    }
                  }
                }
                _smoothAnchorMs = playerMs;
                _smoothAnchorElapsedUs = currentElapsedUs;
                _lastRawPlayerMs = playerPosition;
                // ✅ P1 单调递增保护：锚点过期重锚定时，确保 playbackTimeMs 不回退
                final _anchorExpireNewPtm = playerMs.clamp(0.0, _duration.inMilliseconds.toDouble());
                if (_anchorExpireNewPtm < _playbackTimeMs.value && _playbackTimeMs.value > 100.0) {
                  // playerMs 回退 → 保持 prevPtm，锚定到 prevPtm 使后续帧正常推进
                  _smoothAnchorMs = _playbackTimeMs.value;
                  _playbackTimeMs.value = _playbackTimeMs.value; // hold
                  if (!kReleaseMode) {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (now - _lastDiagPtmBackwardMs >= 500) {
                      _lastDiagPtmBackwardMs = now;
                      debugPrint('[PTM-MONOTONICITY-DIAG] ANCHOR-EXPIRE backward prevented: '
                          'prevPtm=${_playbackTimeMs.value.toStringAsFixed(1)} '
                          'playerMs=${playerMs.toStringAsFixed(1)} → held at prevPtm');
                    }
                  }
                } else {
                  _playbackTimeMs.value = _anchorExpireNewPtm;
                }
              } else if (playerPosition != _lastRawPlayerMs) {
                // player.position 更新了：检查平滑时钟与实际位置的漂移
                final smoothMs = _smoothAnchorMs + elapsedDeltaUs / 1000.0 * effectivePlaybackRate;
                final drift = smoothMs - playerMs;
                // [CHAIN-A] 记录 drift 修正前的 playbackTimeMs，供末尾聚合输出使用
                final chainAPrevPtm = _playbackTimeMs.value;
                if (drift.abs() > 30.0) {
                  // 大跳变（seek/暂停恢复后）
                  // ✅ 修复：如果 playerMs < 当前 playbackTimeMs（回退场景），
                  // 不立即对齐到 playerMs，而是渐进修正，避免 playbackTimeMs 回跳。
                  // 回跳场景：暂停恢复时 player.position 返回比暂停前小的值；
                  // 正常播放时平滑时钟超前但 playerMs 落后。
                  // 前进场景：seek 后 playerMs 大幅领先 → 立即对齐正确。
                  final prevPtm = _playbackTimeMs.value;
                  final isBackward = playerMs < prevPtm - 5.0; // playerMs 比 playbackTimeMs 小 >5ms
                  if (isBackward) {
                    // ✅ 回退保护：渐进修正而非立即对齐
                    // P3 优化：提高修正速率到 35%，让暂停恢复后的时间偏差更快收敛。
                    // 旧值 20% 在暂停恢复后需要 ~15 帧才能收敛 30ms 偏差，
                    // 期间弹幕时间与视频不同步。35% 可在 ~8 帧内收敛。
                    final correctionMs = drift * 0.35;
                    _smoothAnchorMs = smoothMs - correctionMs;
                    final correctionUsExact = correctionMs * 1000.0 / effectivePlaybackRate;
                    _smoothAnchorElapsedUs =
                        currentElapsedUs - correctionUsExact.round();
                    // [PTM-MONOTONICITY-DIAG] 检测渐进修正是否导致 playbackTimeMs 回退
                    if (!kReleaseMode) {
                      final newDeltaUs = currentElapsedUs - _smoothAnchorElapsedUs;
                      final newPtm = (_smoothAnchorMs + newDeltaUs / 1000.0 * effectivePlaybackRate)
                          .clamp(0.0, _duration.inMilliseconds.toDouble());
                      if (newPtm < prevPtm - 0.5 && prevPtm > 100.0) {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        if (now - _lastDiagPtmBackwardMs >= 200) {
                          _lastDiagPtmBackwardMs = now;
                          debugPrint('[PTM-MONOTONICITY-DIAG] PROGRESSIVE CORRECTION causes ptm BACKWARD: '
                              'prevPtm=${prevPtm.toStringAsFixed(1)} → newPtm=${newPtm.toStringAsFixed(1)} '
                              'delta=${(newPtm - prevPtm).toStringAsFixed(3)}ms '
                              'drift=${drift.toStringAsFixed(1)}ms correction=${correctionMs.toStringAsFixed(1)}ms '
                              'smoothMs=${smoothMs.toStringAsFixed(1)} playerMs=${playerMs.toStringAsFixed(1)} '
                              'rate=$effectivePlaybackRate ← ROOT CAUSE: drift correction violates monotonicity');
                        }
                      }
                      // 保留原有 DRIFT-SNAP-DIAG
                      final now2 = DateTime.now().millisecondsSinceEpoch;
                      if (now2 - _lastDiagDriftSnapMs >= 500) {
                        _lastDiagDriftSnapMs = now2;
                        debugPrint('[DRIFT-SNAP-DIAG] BACKWARD PROTECTED: '
                            'drift=${drift.toStringAsFixed(1)}ms > 30ms BUT playerMs(${playerMs.toStringAsFixed(1)}) < ptm(${prevPtm.toStringAsFixed(1)}) '
                            '→ progressive correction 20% instead of snap '
                            'smoothMs=${smoothMs.toStringAsFixed(1)} rate=$effectivePlaybackRate '
                            'ptmWillBackward=${newPtm < prevPtm ? "YES←BUG" : "no"}');
                      }
                    }
                  } else {
                    // [FIX-L2] 前进场景：playerMs >= playbackTimeMs，改渐进追赶替代立即 snap。
                    // 根因：原实现立即 _smoothAnchorMs=playerMs → playbackTimeMs 阶跃到 playerMs
                    // → engine item.x 阶跃 → painter displayX 漂移 → drift 修正 → 回弹。
                    // 修复：用 0.35 渐进追赶。注意 big-fwd 时 drift<0（smoothMs 落后 playerMs），
                    // correctionMs=drift*0.35<0，需让当前帧 newPtm = smoothMs + |correctionMs| 立即追赶，
                    // 而非像 backward 那样保持当前帧连续（backward 靠下一帧 anchor 减小来收敛）。
                    // big-fwd 是持续追赶场景，当前帧就应前进 |correctionMs|，否则在 drift 稳态时
                    // 永不收敛（回归实证：drift=-278ms 持续，0.35 修正被 anchorElapsedUs 抵消）。
                    // 实现：_smoothAnchorMs = smoothMs - correctionMs（= smoothMs + |correctionMs|），
                    //       _smoothAnchorElapsedUs = currentElapsedUs（不调整，newDeltaUs=0），
                    // → newPtm = anchorMs + 0 = smoothMs + |correctionMs|，当前帧立即追赶。
                    final correctionMs = drift * 0.35;
                    _smoothAnchorMs = smoothMs - correctionMs;
                    _smoothAnchorElapsedUs = currentElapsedUs;
                    if (!kReleaseMode) {
                      final snapDeltaMs = playerMs - prevPtm;
                      if (snapDeltaMs.abs() > 10.0) {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        if (now - _lastDiagDriftSnapMs >= 500) {
                          _lastDiagDriftSnapMs = now;
                          debugPrint('[DRIFT-SNAP-DIAG] FORWARD PROGRESSIVE: '
                              'drift=${drift.toStringAsFixed(1)}ms → 0.35 progressive (was snap): '
                              'prevPtm=${prevPtm.toStringAsFixed(1)} → playerMs=${playerMs.toStringAsFixed(1)} '
                              'delta=${snapDeltaMs.toStringAsFixed(1)}ms '
                              'smoothMs=${smoothMs.toStringAsFixed(1)} rate=$effectivePlaybackRate');
                        }
                      }
                    }
                  }
                } else {
                  // 小漂移：渐进修正锚点
                  // [FIX-L2] 收敛速率 0.15 → 0.25，减少正常播放的系统性落后。
                  // 根因：flutter.log 实证 small 分支持续 drift -15~-29ms，0.15 收敛太慢，
                  // 平滑时钟系统性落后 player.position，item.x 微左移 vs displayX 墙钟走，
                  // 14px 边缘周期性漂移 → 不丝滑。0.25 可在 ~9 帧内收敛 30ms 偏差，
                  // 同时保持帧间连续性（单帧修正占比 <25% 正常移动）。
                  final correctionMs = drift * 0.25;
                  _smoothAnchorMs = smoothMs - correctionMs;
                  // 锚点时间调整：锚点位置被修正了 correctionMs，
                  // 锚点时间需设置为 currentElapsedUs - correctionMs*1000/rate，
                  // 使得当前帧输出 = smoothMs（保持连续性），
                  // 下一帧的插值从修正后的锚点自然推进。
                  final correctionUsExact = correctionMs * 1000.0 / effectivePlaybackRate;
                  final correctionUsRounded = correctionUsExact.round();
                  _smoothAnchorElapsedUs =
                      currentElapsedUs - correctionUsRounded;
                  // [DRIFT-ROUND-DIAG] 根因A诊断：追踪 .round() 舍入误差
                  // 假设：.round() 将微小的 correctionUs（倍速时<100μs）截断为整数，
                  // 误差被后续帧 * _playbackRate 放大 → 周期性振荡 → playbackTimeMs 微回退
                  if (!kReleaseMode) {
                    final roundErrorUs = (correctionUsExact - correctionUsRounded).abs();
                    final prevPtmValue = _playbackTimeMs.value;
                    final newPtmValue = (_smoothAnchorMs + (currentElapsedUs - _smoothAnchorElapsedUs) / 1000.0 * effectivePlaybackRate)
                        .clamp(0.0, _duration.inMilliseconds.toDouble());
                    final ptmDelta = newPtmValue - prevPtmValue;
                    // 仅在舍入误差>0.5μs 或 playbackTimeMs 回退时输出
                    if (roundErrorUs > 0.5 || ptmDelta < -0.5) {
                      final now = DateTime.now().millisecondsSinceEpoch;
                      if (now - _lastDiagRoundTimeMs >= 500) {
                        _lastDiagRoundTimeMs = now;
                        debugPrint('[DRIFT-ROUND-DIAG] correctionMs=${correctionMs.toStringAsFixed(4)} '
                            'correctionUsExact=${correctionUsExact.toStringAsFixed(2)} '
                            'correctionUsRounded=$correctionUsRounded '
                            'roundError=${roundErrorUs.toStringAsFixed(2)}μs '
                            'rate=$effectivePlaybackRate '
                            'ptmDelta=${ptmDelta.toStringAsFixed(3)}ms '
                            'drift=${drift.toStringAsFixed(2)}ms '
                            'BACKWARD=${ptmDelta < -0.5 ? "YES" : "no"}');
                      }
                    }
                  }
                }
                _lastRawPlayerMs = playerPosition;
                final newDeltaUs = currentElapsedUs - _smoothAnchorElapsedUs;
                final newPtm = (_smoothAnchorMs + newDeltaUs / 1000.0 * effectivePlaybackRate)
                    .clamp(0.0, _duration.inMilliseconds.toDouble());
                // [DRIFT-ROUND-DIAG] 追踪 playbackTimeMs 回退（无论走哪个分支）
                if (!kReleaseMode) {
                  final prevPtm = _playbackTimeMs.value;
                  if (newPtm < prevPtm - 0.5 && prevPtm > 100.0) {
                    // playbackTimeMs 回退 >0.5ms（排除开头/边界情况）
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (now - _lastDiagPtmBackwardMs >= 500) {
                      _lastDiagPtmBackwardMs = now;
                      debugPrint('[PTM-BACKWARD-DIAG] playbackTimeMs 回退: '
                          '${prevPtm.toStringAsFixed(1)} → ${newPtm.toStringAsFixed(1)} '
                          'delta=${(newPtm - prevPtm).toStringAsFixed(3)}ms '
                          'rate=$effectivePlaybackRate '
                          'anchorMs=${_smoothAnchorMs.toStringAsFixed(1)} '
                          'playerMs=${playerMs.toStringAsFixed(1)}');
                    }
                  }
                }
                // ✅ P1 单调递增保护：漂移修正后确保 playbackTimeMs 不回退
                if (newPtm < _playbackTimeMs.value && _playbackTimeMs.value > 100.0) {
                  _smoothAnchorMs = _playbackTimeMs.value;
                  _smoothAnchorElapsedUs = currentElapsedUs;
                  // playbackTimeMs 保持不变（hold），锚点重设到 prevPtm 使后续帧正常推进
                  if (!kReleaseMode) {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (now - _lastDiagPtmBackwardMs >= 200) {
                      _lastDiagPtmBackwardMs = now;
                      debugPrint('[PTM-MONOTONICITY-DIAG] DRIFT-CORRECTION backward prevented: '
                          'prevPtm=${_playbackTimeMs.value.toStringAsFixed(1)} '
                          'newPtm=${newPtm.toStringAsFixed(1)} → held at prevPtm, anchor reset');
                    }
                  }
                } else {
                  _playbackTimeMs.value = newPtm;
                }
                // [CHAIN-A] 全链路回弹诊断 — 平滑时钟层单帧聚合
                // 捕获正常播放时 player.position 更新导致的 drift 修正最终结果。
                // 与 painter 侧 [CHAIN-B] 共享墙钟时间戳，按时间排序可看到完整因果链：
                //   position更新 → 平滑时钟修正/hold → 下一帧 painter drift修正 → 回弹
                // branch: small=|drift|<=30ms渐进0.15; big-back=drift>30且playerMs回退0.35渐进;
                //         big-fwd=drift>30且前进snap; hold=P1单调保护卡住一帧
                if (!kReleaseMode) {
                  final finalPtm = _playbackTimeMs.value;
                  final held = (newPtm < chainAPrevPtm && chainAPrevPtm > 100.0);
                  final branch = drift.abs() > 30.0
                      ? (playerMs < chainAPrevPtm - 5.0 ? 'big-back' : 'big-fwd')
                      : 'small';
                  // 仅在发生 hold/回退/大drift时输出，避免正常帧刷屏
                  if (held || drift.abs() > 15.0 || newPtm < chainAPrevPtm - 0.5) {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    debugPrint('[CHAIN-A] t=$now '
                        'ptm ${chainAPrevPtm.toStringAsFixed(1)}→${finalPtm.toStringAsFixed(1)} '
                        'drift=${drift.toStringAsFixed(1)}ms '
                        'playerMs=${playerMs.toStringAsFixed(1)} '
                        'branch=$branch held=${held ? "YES" : "no"} '
                        'rate=$effectivePlaybackRate '
                        'newPtmRaw=${newPtm.toStringAsFixed(1)}');
                  }
                }
              } else {
                // player.position 未变，正常插值推进
                // ✅ P1 单调递增保护：正常插值也确保不回退
                final _interpPtm = (_smoothAnchorMs + elapsedDeltaUs / 1000.0 * effectivePlaybackRate)
                    .clamp(0.0, _duration.inMilliseconds.toDouble());
                if (_interpPtm < _playbackTimeMs.value && _playbackTimeMs.value > 100.0) {
                  // 插值回退 → 重锚到 prevPtm
                  _smoothAnchorMs = _playbackTimeMs.value;
                  _smoothAnchorElapsedUs = currentElapsedUs;
                } else {
                  _playbackTimeMs.value = _interpPtm;
                }
              }
            }

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
                await _updateWatchHistory(forceRemoteSync: true);

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
              _notifyListeners();
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

            final bool isStreamingPath =
                (_currentVideoPath?.startsWith('jellyfin://') ?? false) ||
                    (_currentVideoPath?.startsWith('emby://') ?? false) ||
                    (_currentVideoPath?.startsWith('http://') ?? false) ||
                    (_currentVideoPath?.startsWith('https://') ?? false) ||
                    (_currentActualPlayUrl?.startsWith('http://') ?? false) ||
                    (_currentActualPlayUrl?.startsWith('https://') ?? false);
            final bool isStreamingStartupGrace = isStreamingPath &&
                _lastPlaybackStartMs > 0 &&
                (nowTime - _lastPlaybackStartMs) <
                    VideoPlayerState._streamingInvalidDataGraceMs;

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
                isStreamingStartupGrace ||
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
            _bufferedPositionMs = 0;

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
          // 暂停状态：使用最后一次seek的位置，同时重置平滑时钟锚点
          _position = _lastSeekPosition!;
          _playbackTimeMs.value = _position.inMilliseconds.toDouble();
          _smoothAnchorMs = _position.inMilliseconds.toDouble();
          _smoothAnchorElapsedUs = _lastElapsedUs;
          _lastRawPlayerMs = _position.inMilliseconds;
          _seekTargetMs = null; // [SEEK-TRACE] source=PAUSED-BRANCH
          if (_duration.inMilliseconds > 0) {
            _progress = _position.inMilliseconds / _duration.inMilliseconds;
            final bufferedMs = player.bufferedPosition;
            _bufferedPositionMs = bufferedMs <= 0
                ? 0
                : bufferedMs.clamp(0, _duration.inMilliseconds).toInt();
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
          } else {
            _bufferedPositionMs = 0;
          }
          if (shouldUiNotify) {
            _lastUiNotifyMs = nowTime;
            _notifyListeners();
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
    }
  }
}
