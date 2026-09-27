part of video_player_state;

const int _timelinePreviewMaxHeight = 180;
const int _timelinePreviewDefaultWidth = 320;

/// Timeline preview uses an extra background player to capture frames. Keep it
/// on MDK only: enabling the MDK preference must not start another libmpv
/// instance after the playback kernel is switched to MediaKit.
bool supportsTimelinePreviewForKernel(PlayerKernelType kernel) {
  return kernel == PlayerKernelType.mdk;
}

extension VideoPlayerStateTimelinePreview on VideoPlayerState {
  bool get timelinePreviewEnabled => _timelinePreviewEnabled;
  bool get isTimelinePreviewAvailable =>
      _timelinePreviewEnabled && _timelinePreviewSupported;

  Future<void> _loadTimelinePreviewSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_timelinePreviewEnabledKey);
      final resolved = stored ?? false;
      if (_timelinePreviewEnabled != resolved) {
        _timelinePreviewEnabled = resolved;
        _notifyListeners();
      } else {
        _timelinePreviewEnabled = resolved;
      }
    } catch (e) {
      debugPrint('加载时间轴缩略图开关失败: $e');
      _timelinePreviewEnabled = false;
    }
  }

  Future<void> setTimelinePreviewEnabled(bool enabled) async {
    if (_timelinePreviewEnabled == enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_timelinePreviewEnabledKey, enabled);
    } catch (e) {
      debugPrint('保存时间轴缩略图开关失败: $e');
    }

    _timelinePreviewEnabled = enabled;
    if (!enabled) {
      _resetTimelinePreviewState();
    } else if (_currentVideoPath != null) {
      unawaited(_setupTimelinePreviewForVideo(_currentVideoPath!));
    }
    _notifyListeners();
  }

  void _resetTimelinePreviewState() {
    _timelinePreviewCache.clear();
    _timelinePreviewPending.clear();
    _timelinePreviewSupported = false;
    _timelinePreviewDirectory = null;
    _timelinePreviewVideoKey = null;
    _timelinePreviewSessionId++;
    _disposeTimelinePreviewPlayer();
    _timelinePreviewSerialTask = Future.value();
  }

  Future<void> _setupTimelinePreviewForVideo(String path) async {
    _resetTimelinePreviewState();
    if (!_timelinePreviewEnabled || kIsWeb) return;

    if (!_isTimelinePreviewKernelSupported()) {
      _timelinePreviewSupported = false;
      _notifyListeners();
      return;
    }

    _timelinePreviewIntervalMs = _resolveTimelineInterval(_duration);
    final session = _timelinePreviewSessionId;

    final supported = await _isTimelinePreviewSourceSupported(path);
    if (session != _timelinePreviewSessionId) return;
    _timelinePreviewSupported = supported;
    if (!supported) {
      _notifyListeners();
      return;
    }

    _timelinePreviewVideoKey =
        _currentVideoHash ?? md5.convert(utf8.encode(path)).toString();
    final dir = await _ensureTimelinePreviewDirectory();
    if (session != _timelinePreviewSessionId) return;
    _timelinePreviewDirectory = dir.path;
    _hydrateTimelinePreviewCache(dir);
    _notifyListeners();

    unawaited(_prefetchInitialTimelineThumbnails(session));
    unawaited(_backgroundFillTimelineThumbnails(session));
  }

  int _resolveTimelineInterval(Duration duration) {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return 15000;
    final computed = (totalMs / 120).round().clamp(5000, 30000);
    if (computed is int) return computed;
    return (computed as num).toInt();
  }

  Future<Directory> _ensureTimelinePreviewDirectory() async {
    final appDir = await StorageService.getAppStorageDirectory();
    final dirName = _timelinePreviewVideoKey ??
        md5.convert(utf8.encode(_currentVideoPath ?? '')).toString();
    final dir = Directory('${appDir.path}/timeline_thumbnails/$dirName');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  void _hydrateTimelinePreviewCache(Directory dir) {
    if (!dir.existsSync()) return;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = p.basenameWithoutExtension(entity.path);
        final match = RegExp(r'_(\d+)ms$').firstMatch(name);
        if (match == null) continue;
        final bucket = int.tryParse(match.group(1)!);
        if (bucket != null) {
          _timelinePreviewCache[bucket] = entity.path;
        }
      }
    } catch (e) {
      debugPrint('读取时间轴缩略图缓存失败: $e');
    }
  }

  int? getTimelinePreviewBucket(Duration time) {
    if (!isTimelinePreviewAvailable || _duration.inMilliseconds <= 0) {
      return null;
    }
    final totalMs = _duration.inMilliseconds;
    final clamped = time.inMilliseconds.clamp(0, totalMs - 1);
    final interval =
        _timelinePreviewIntervalMs <= 0 ? 15000 : _timelinePreviewIntervalMs;
    return (clamped ~/ interval) * interval;
  }

  Future<String?> getTimelinePreview(Duration time) async {
    if (!isTimelinePreviewAvailable || _currentVideoPath == null) {
      return null;
    }
    final bucket = getTimelinePreviewBucket(time);
    if (bucket == null) return null;

    final cached = _timelinePreviewCache[bucket];
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }

    return _createTimelineThumbnail(bucket, _timelinePreviewSessionId);
  }

  Future<String?> _createTimelineThumbnail(int bucket, int session) async {
    return _withTimelinePreviewSerial(() async {
      if (session != _timelinePreviewSessionId) return null;
      if (_timelinePreviewPending.contains(bucket)) return null;
      final source = _currentActualPlayUrl ?? _currentVideoPath;
      if (source == null || source.isEmpty) return null;
      if (!_isTimelinePreviewKernelSupported()) return null;
      if (_timelinePreviewDirectory == null) {
        _timelinePreviewDirectory =
            (await _ensureTimelinePreviewDirectory()).path;
      }

      final directoryPath = _timelinePreviewDirectory;
      if (directoryPath == null) return null;

      final targetPath = p.join(directoryPath, 'thumb_${bucket}ms.jpg');
      _timelinePreviewPending.add(bucket);

      try {
        final kernel = PlayerFactory.getKernelType();
        final previewPlayer =
            await _ensureTimelinePreviewPlayer(kernel, source);
        if (session != _timelinePreviewSessionId) return null;
        if (previewPlayer == null) return null;

        final frame =
            await _captureTimelineFrame(previewPlayer, bucket, session);
        if (frame == null) return null;

        final jpegBytes = _encodeTimelineFrameToJpeg(frame);
        if (jpegBytes == null || jpegBytes.isEmpty) {
          return null;
        }

        final file = File(targetPath);
        await file.writeAsBytes(jpegBytes, flush: true);
        _timelinePreviewCache[bucket] = targetPath;
        return targetPath;
      } catch (e) {
        debugPrint('生成时间轴缩略图失败: $e');
        return null;
      } finally {
        _timelinePreviewPending.remove(bucket);
      }
    });
  }

  bool _isTimelinePreviewKernelSupported() {
    final kernel = PlayerFactory.getKernelType();
    return supportsTimelinePreviewForKernel(kernel);
  }

  Future<AbstractPlayer?> _ensureTimelinePreviewPlayer(
      PlayerKernelType kernel, String source) async {
    if (_timelinePreviewPlayer != null &&
        _timelinePreviewPlayerKernel == kernel &&
        _timelinePreviewPlayerSource == source) {
      return _timelinePreviewPlayer;
    }

    // 先释放旧实例并等待其原生资源真正销毁，再创建新实例（disposing
    // latch）：避免上一个播放器延迟释放的 150ms 内出现两个 MDK 实例并存
    // 的 D3D11 争用窗口。
    final previousPlayer = _timelinePreviewPlayer;
    _timelinePreviewPlayer = null;
    _timelinePreviewPlayerKernel = null;
    _timelinePreviewPlayerSource = null;
    if (previousPlayer != null) {
      await _disposePreviewPlayerDeferred(previousPlayer);
    }

    final previewPlayer = PlayerFactory().createPlayer(kernelType: kernel);
    try {
      previewPlayer.volume = 0;
      if (!kIsWeb && Platform.isWindows && kernel == PlayerKernelType.mdk) {
        // Windows 防护：预览播放器仅用于 320x180 抽帧，强制软件解码，
        // 避免与主播放器的 D3D11 硬解实例争用。
        // 注意：本项目解码器选择统一走 setDecoders（见
        // decoder_manager.dart），MDK 识别的软解名称为 'FFmpeg'；
        // setProperty('video.hwdec', 'no') 不是 fvp 支持的属性键，会被静默忽略。
        try {
          previewPlayer.setDecoders(PlayerMediaType.video, const ['FFmpeg']);
        } catch (e) {
          debugPrint('设置时间轴预览软解失败: $e');
        }
      }
      previewPlayer.setMedia(source, PlayerMediaType.video);
      // prepare 添加整体超时：任何一步挂住都只放弃本张缩略图，绝不阻塞 UI。
      await previewPlayer
          .prepare()
          .timeout(const Duration(seconds: 5),
              onTimeout: () =>
                  throw TimeoutException('时间轴预览播放器 prepare 超时'));
      previewPlayer.state = PlayerPlaybackState.paused;
      await _waitForTimelinePreviewReady(previewPlayer);
      if (kernel == PlayerKernelType.mdk) {
        // 必须注册渲染目标：fvp 的 snapshot 由 mdk 渲染回调完成，没有渲染
        // 表面时 snapshot 的 Completer 永远不会完成（adapter 层对此调用有
        // 10 秒超时保护，不会无限挂住）。该纹理从不挂到 widget 上，仅用于
        // 驱动 mdk 渲染管线；快照帧数据经 Dart port 独立回传 RGBA。
        try {
          await previewPlayer.updateTexture();
        } catch (e) {
          debugPrint('初始化时间轴截图纹理失败: $e');
        }
      }
      _timelinePreviewPlayer = previewPlayer;
      _timelinePreviewPlayerKernel = kernel;
      _timelinePreviewPlayerSource = source;
      return previewPlayer;
    } catch (e) {
      debugPrint('初始化时间轴截图播放器失败: $e');
      // prepare 超时或初始化失败时同样走延迟释放，绝不在 UI 线程同步
      // dispose 去 join 可能挂住的原生线程。
      unawaited(_disposePreviewPlayerDeferred(previewPlayer));
      return null;
    }
  }

  Future<void> _waitForTimelinePreviewReady(AbstractPlayer player) async {
    for (int i = 0; i < 8; i++) {
      if (player.mediaInfo.duration > 0) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  /// 停止并延迟释放一个预览播放器：先置停止态让原生渲染循环退出，等待
  /// 150ms 后再 dispose，避免在 UI 线程上同步 join 可能仍阻塞的原生渲染
  /// 线程导致窗口"未响应"。返回的 Future 在原生实例真正销毁后完成。
  Future<void> _disposePreviewPlayerDeferred(AbstractPlayer player) async {
    try {
      player.state = PlayerPlaybackState.stopped;
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      player.dispose();
    } catch (_) {}
  }

  /// fire-and-forget 释放当前预览播放器（开关关闭、切集等场景）。
  void _disposeTimelinePreviewPlayer() {
    final player = _timelinePreviewPlayer;
    _timelinePreviewPlayer = null;
    _timelinePreviewPlayerKernel = null;
    _timelinePreviewPlayerSource = null;
    if (player != null) {
      unawaited(_disposePreviewPlayerDeferred(player));
    }
  }

  Future<T> _withTimelinePreviewSerial<T>(Future<T> Function() task) {
    final next = _timelinePreviewSerialTask.then((_) => task());
    _timelinePreviewSerialTask = next.then((_) => null, onError: (_) => null);
    return next;
  }

  Future<PlayerFrame?> _captureTimelineFrame(
      AbstractPlayer player, int bucket, int session) async {
    if (session != _timelinePreviewSessionId) return null;
    try {
      final kernel =
          _timelinePreviewPlayerKernel ?? PlayerFactory.getKernelType();
      if (_timelinePreviewPlayerKernel == PlayerKernelType.mdk &&
          player.textureId.value == null) {
        try {
          await player.updateTexture();
        } catch (e) {
          debugPrint('时间轴截图纹理创建失败: $e');
        }
      }

      int targetHeight = _timelinePreviewMaxHeight;
      int targetWidth = _timelinePreviewDefaultWidth;
      final videoStreams = player.mediaInfo.video;
      if (videoStreams != null && videoStreams.isNotEmpty) {
        final codec = videoStreams.first.codec;
        if (codec.width > 0 && codec.height > 0) {
          final aspect = codec.width / codec.height;
          targetWidth = (targetHeight * aspect).round();
          targetWidth =
              targetWidth.clamp(1, _timelinePreviewDefaultWidth * 3).toInt();
        }
      }

      player.state = PlayerPlaybackState.paused;
      player.seek(position: bucket);
      await Future.delayed(const Duration(milliseconds: 140));

      if (kernel == PlayerKernelType.mdk) {
        // 关键时序：mdk 的 Player::snapshot() 在【下一次渲染回调】时才完成，
        // 因此必须先挂起快照请求、再让播放器播放；若先暂停再请求，暂停状态
        // 下不再产生渲染帧，Completer 永远不会完成（旧代码正是在此处永久
        // 挂死串行队列，dispose 时 join 原生线程导致整个窗口"未响应"）。
        PlayerFrame? frame;
        try {
          player.state = PlayerPlaybackState.playing;
          frame = await player
              .snapshot(width: targetWidth, height: targetHeight)
              .timeout(const Duration(seconds: 2), onTimeout: () => null);
        } finally {
          player.state = PlayerPlaybackState.paused;
        }
        if (session != _timelinePreviewSessionId) return null;
        if (frame == null || frame.bytes.isEmpty) {
          // 部分视频 seek 后首帧解码较慢，重试一次：先播放预滚 80ms 再挂请求。
          try {
            player.state = PlayerPlaybackState.playing;
            await Future.delayed(const Duration(milliseconds: 80));
            frame = await player
                .snapshot(width: targetWidth, height: targetHeight)
                .timeout(const Duration(seconds: 2), onTimeout: () => null);
          } finally {
            player.state = PlayerPlaybackState.paused;
          }
        }
        if (session != _timelinePreviewSessionId) return null;
        if (frame == null || frame.bytes.isEmpty) {
          return null;
        }
        return _normalizeTimelineFrameSize(
          frame,
          player,
          fallbackWidth: targetWidth,
          fallbackHeight: targetHeight,
        );
      }

      player.state = PlayerPlaybackState.playing;
      await Future.delayed(const Duration(milliseconds: 70));
      player.state = PlayerPlaybackState.paused;
      await Future.delayed(const Duration(milliseconds: 40));

      if (session != _timelinePreviewSessionId) return null;

      PlayerFrame? frame = await player
          .snapshot(width: targetWidth, height: targetHeight)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (frame == null || frame.bytes.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 80));
        frame = await player
            .snapshot(width: targetWidth, height: targetHeight)
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
      }
      if (session != _timelinePreviewSessionId) return null;
      if (frame == null || frame.bytes.isEmpty) {
        return null;
      }
      return _normalizeTimelineFrameSize(
        frame,
        player,
        fallbackWidth: targetWidth,
        fallbackHeight: targetHeight,
      );
    } catch (e) {
      debugPrint('捕获时间轴帧失败: $e');
      return null;
    }
  }

  Uint8List? _encodeTimelineFrameToJpeg(PlayerFrame frame) {
    try {
      img.Image? image;

      try {
        image = img.decodeImage(frame.bytes);
      } catch (_) {}

      image ??= _decodeTimelineRawFrame(frame);
      if (image == null) {
        return null;
      }

      if (image.height > _timelinePreviewMaxHeight) {
        image = img.copyResize(
          image,
          height: _timelinePreviewMaxHeight,
        );
      }

      return img.encodeJpg(image, quality: 60);
    } catch (e) {
      debugPrint('编码时间轴缩略图失败: $e');
      return null;
    }
  }

  img.Image? _decodeTimelineRawFrame(PlayerFrame frame) {
    final width = frame.width > 0 ? frame.width : _timelinePreviewDefaultWidth;
    final height = frame.height > 0 ? frame.height : _timelinePreviewMaxHeight;
    final bytes = frame.bytes;
    if (width <= 0 || height <= 0 || bytes.isEmpty) return null;

    int? rowStride;
    if (bytes.length % height == 0) {
      final stride = bytes.length ~/ height;
      if (stride >= width * 4) {
        rowStride = stride;
      }
    }

    if (bytes.length < width * height * 4 && rowStride == null) {
      return null;
    }

    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      numChannels: 4,
      rowStride: rowStride,
      order: _resolveTimelinePreviewChannelOrder(),
    );
  }

  PlayerFrame _normalizeTimelineFrameSize(
    PlayerFrame frame,
    AbstractPlayer player, {
    required int fallbackWidth,
    required int fallbackHeight,
  }) {
    final bytes = frame.bytes;
    int resolvedWidth = frame.width;
    int resolvedHeight = frame.height;

    bool lengthMatches(int width, int height) {
      if (width <= 0 || height <= 0) return false;
      return bytes.length == width * height * 4;
    }

    if (!lengthMatches(resolvedWidth, resolvedHeight)) {
      final streams = player.mediaInfo.video;
      if (streams != null && streams.isNotEmpty) {
        final codec = streams.first.codec;
        if (lengthMatches(codec.width, codec.height)) {
          resolvedWidth = codec.width;
          resolvedHeight = codec.height;
        }
      }
    }

    if (resolvedWidth <= 0 || resolvedHeight <= 0) {
      resolvedWidth = fallbackWidth;
      resolvedHeight = fallbackHeight;
    }

    if (resolvedWidth == frame.width && resolvedHeight == frame.height) {
      return frame;
    }

    return PlayerFrame(
      width: resolvedWidth,
      height: resolvedHeight,
      bytes: bytes,
    );
  }

  img.ChannelOrder _resolveTimelinePreviewChannelOrder() {
    final kernel =
        _timelinePreviewPlayerKernel ?? PlayerFactory.getKernelType();
    if (kernel == PlayerKernelType.mediaKit) {
      return img.ChannelOrder.bgra;
    }
    return img.ChannelOrder.rgba;
  }

  Future<void> _prefetchInitialTimelineThumbnails(int session) async {
    if (session != _timelinePreviewSessionId ||
        !isTimelinePreviewAvailable ||
        _duration.inMilliseconds <= 0) {
      return;
    }

    final total = _duration.inMilliseconds;
    final samples = <int>{
      0,
      total ~/ 4,
      total ~/ 2,
      (total - _timelinePreviewIntervalMs).clamp(0, total - 1),
    };

    for (final bucket in samples) {
      if (session != _timelinePreviewSessionId || !isTimelinePreviewAvailable) {
        return;
      }
      await _createTimelineThumbnail(bucket, session);
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _backgroundFillTimelineThumbnails(int session) async {
    if (session != _timelinePreviewSessionId ||
        !isTimelinePreviewAvailable ||
        _duration.inMilliseconds <= 0) {
      return;
    }

    final total = _duration.inMilliseconds;
    final interval =
        _timelinePreviewIntervalMs <= 0 ? 15000 : _timelinePreviewIntervalMs;
    const int maxThumbnails = 80;
    int generated = 0;

    for (int bucket = 0;
        bucket <= total && generated < maxThumbnails;
        bucket += interval) {
      if (session != _timelinePreviewSessionId || !isTimelinePreviewAvailable) {
        return;
      }
      if (_timelinePreviewCache.containsKey(bucket)) {
        continue;
      }
      await _createTimelineThumbnail(bucket, session);
      generated++;
      await Future.delayed(const Duration(milliseconds: 220));
    }
  }

  Future<bool> _isTimelinePreviewSourceSupported(String path) async {
    if (path.isEmpty || kIsWeb) return false;
    final lower = path.toLowerCase();

    if (lower.startsWith('jellyfin://') || lower.startsWith('emby://')) {
      return false;
    }

    if (lower.startsWith('sharedremote://')) {
      return true;
    }

    if (SharedRemoteHistoryHelper.isSharedRemoteStreamPath(path)) {
      return true;
    }

    if (MediaSourceUtils.isSmbPath(path)) {
      return true;
    }

    if (_looksLikeLocalFile(path)) {
      return true;
    }

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      try {
        final resolved = WebDAVService.instance.resolveFileUrl(path);
        if (resolved != null) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  bool _looksLikeLocalFile(String path) {
    if (path.startsWith('file://')) return true;
    final uri = Uri.tryParse(path);
    if (uri == null) return true;
    if (uri.scheme.isEmpty) return true;
    if (Platform.isWindows && uri.scheme.length == 1) {
      // Windows 盘符
      return true;
    }
    return false;
  }

  Future<void> _clearTimelinePreviewFiles() async {
    String? dirPath = _timelinePreviewDirectory;
    try {
      if (dirPath == null && _timelinePreviewVideoKey != null) {
        final appDir = await StorageService.getAppStorageDirectory();
        dirPath =
            '${appDir.path}/timeline_thumbnails/${_timelinePreviewVideoKey}';
      }
      if (dirPath == null) return;
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;
      await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('清理时间轴缩略图失败: $e');
    }
  }
}
