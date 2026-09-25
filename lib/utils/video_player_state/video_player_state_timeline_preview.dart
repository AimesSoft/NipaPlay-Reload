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
    // 不能在 UI 线程上立即 dispose 预览播放器：它可能正卡在 seek/snapshot 的
    // 原生调用中，MDK delete 会 join 原生线程，从而冻结整个窗口（未响应）。
    // 先摘除引用，再把释放排到当前串行截图队列之后，确保没有在途截图任务后
    // 才真正释放；bump 过的 session 也会让在途任务自行短路退出。
    final oldPlayer = _timelinePreviewPlayer;
    _timelinePreviewPlayer = null;
    _timelinePreviewPlayerKernel = null;
    _timelinePreviewPlayerSource = null;
    _timelinePreviewSerialTask = _timelinePreviewSerialTask
        .then((_) => _releasePreviewPlayerSafely(oldPlayer))
        .then((_) => null, onError: (_) => null);
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

    _disposeTimelinePreviewPlayer();

    final previewPlayer = PlayerFactory().createPlayer(kernelType: kernel);
    try {
      previewPlayer.volume = 0;
      if (kernel == PlayerKernelType.mdk) {
        // 截图播放器强制软解：主播放器此时通常正以 D3D11 硬解（MFT:d3d=11）
        // 播放，第二个 MDK 实例再起一套 D3D11 硬解设备，会在部分机器上与主
        // 实例争用 GPU/驱动资源，严重时原生渲染线程挂起、整个窗口未响应
        // （日志戛然而止、无任何异常）。缩略图仅 320x180，软解开销可忽略。
        try {
          previewPlayer.setDecoders(PlayerMediaType.video, const ['FFmpeg']);
        } catch (e) {
          debugPrint('设置时间轴截图软解失败: $e');
        }
      }
      previewPlayer.setMedia(source, PlayerMediaType.video);
      await previewPlayer.prepare();
      previewPlayer.state = PlayerPlaybackState.paused;
      await _waitForTimelinePreviewReady(previewPlayer);
      if (kernel == PlayerKernelType.mdk) {
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
      unawaited(_releasePreviewPlayerSafely(previewPlayer));
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

  void _disposeTimelinePreviewPlayer() {
    final player = _timelinePreviewPlayer;
    _timelinePreviewPlayer = null;
    _timelinePreviewPlayerKernel = null;
    _timelinePreviewPlayerSource = null;
    unawaited(_releasePreviewPlayerSafely(player));
  }

  /// 安全释放预览播放器：先停止播放让原生渲染/解码线程退出当前帧，短暂等待
  /// 后再 delete，避免与在途 seek/snapshot 并发进入 MDK 原生层造成线程挂死。
  /// 全程不在 UI 线程上同步等待原生调用。
  Future<void> _releasePreviewPlayerSafely(AbstractPlayer? player) async {
    if (player == null) return;
    try {
      player.state = PlayerPlaybackState.stopped;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      player.dispose();
    } catch (_) {}
  }

  Future<T> _withTimelinePreviewSerial<T>(Future<T> Function() task) {
    final next = _timelinePreviewSerialTask.then((_) => task());
    _timelinePreviewSerialTask = next.then((_) => null, onError: (_) => null);
    return next;
  }

  /// fvp 的 snapshot 由原生渲染线程异步回调完成；当渲染表面不可见或原生
  /// 线程卡住时回调可能永远不来，这里统一加 2 秒超时，避免串行截图队列被
  /// 一个永不完成的 Future 永久堵死（进而拖住后续释放播放器的任务）。
  Future<PlayerFrame?> _timelineSnapshotWithTimeout(
    AbstractPlayer player, {
    required int width,
    required int height,
  }) {
    return player
        .snapshot(width: width, height: height)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
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

      player.state = PlayerPlaybackState.playing;
      await Future.delayed(const Duration(milliseconds: 70));
      player.state = PlayerPlaybackState.paused;
      await Future.delayed(const Duration(milliseconds: 40));

      if (session != _timelinePreviewSessionId) return null;

      if (kernel == PlayerKernelType.mdk) {
        // MDK 首次 snapshot 可能没有渲染帧，先触发一次以确保后续截图可用。
        await _timelineSnapshotWithTimeout(
          player,
          width: targetWidth,
          height: targetHeight,
        );
        await Future.delayed(const Duration(milliseconds: 60));
      }

      PlayerFrame? frame = await _timelineSnapshotWithTimeout(
        player,
        width: targetWidth,
        height: targetHeight,
      );
      if ((frame == null || frame.bytes.isEmpty) &&
          kernel == PlayerKernelType.mdk) {
        await Future.delayed(const Duration(milliseconds: 80));
        frame = await _timelineSnapshotWithTimeout(
          player,
          width: targetWidth,
          height: targetHeight,
        );
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
    // 只预取开头和中点两帧：预取阶段第二播放器刚创建，与主播放器的初始化/
    // 硬解同时进行，采样点过多会加剧 GPU 争用；其余位置由悬停时按需生成。
    final samples = <int>{
      0,
      total ~/ 2,
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
    // 后台填充要克制：每个缩略图都伴随第二播放器的 seek/播放/暂停/多次
    // snapshot，长视频全速填充会持续与主播放器争用解码与 GPU，曾导致整个
    // 窗口未响应。上限降到 24 张、间隔拉大到 600ms，日常悬停基本都能命中
    // 缓存，未命中的位置再按需即时生成。
    const int maxThumbnails = 24;
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
      await Future.delayed(const Duration(milliseconds: 600));
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
