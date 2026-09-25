part of video_player_state;

const int _timelinePreviewMaxHeight = 180;
const int _timelinePreviewDefaultWidth = 320;

/// Timeline preview uses an extra background player to capture frames. Keep it
/// on MDK only: enabling the MDK preference must not start another libmpv
/// instance after the playback kernel is switched to MediaKit.
bool supportsTimelinePreviewForKernel(PlayerKernelType kernel) {
  // Windows 上不能创建第二个后台 MDK 播放器：双 MDK 实例会在部分机器的
  // D3D11/显卡驱动层发生原生死锁，表现为窗口瞬间"未响应"（Dart 层无法
  // 规避）。Windows 改为调用独立的 ffmpeg 子进程抽帧（见
  // _createTimelineThumbnailViaFfmpeg），与播放内核无关，进程隔离也保证
  // 子进程出任何问题都不会卡死主程序。
  if (!kIsWeb && Platform.isWindows) {
    return true;
  }
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
        // Windows：独立 ffmpeg 子进程抽帧，绝不创建第二个播放器。
        if (!kIsWeb && Platform.isWindows) {
          return await _createTimelineThumbnailViaFfmpeg(
              source, targetPath, bucket, session);
        }
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
    // Windows 走 ffmpeg 子进程，只看 ffmpeg.exe 是否随包提供，与播放内核无关
    if (!kIsWeb && Platform.isWindows) {
      return _resolveTimelineFfmpegPath() != null;
    }
    final kernel = PlayerFactory.getKernelType();
    return supportsTimelinePreviewForKernel(kernel);
  }

  /// 定位随应用打包的 ffmpeg.exe（release 包中与 NipaPlay.exe 同目录，
  /// 由 Windows 构建工作流下载并放入打包目录）。开发环境下不存在则返回
  /// null，时间轴预览自动不可用。
  String? _resolveTimelineFfmpegPath() {
    if (kIsWeb || !Platform.isWindows) return null;
    final exePath =
        p.join(File(Platform.resolvedExecutable).parent.path, 'ffmpeg.exe');
    return File(exePath).existsSync() ? exePath : null;
  }

  /// 把应用内部使用的媒体地址转成 ffmpeg 能识别的输入地址。
  String? _normalizeTimelineSourceForFfmpeg(String source) {
    if (source.isEmpty) return null;
    if (source.startsWith('file://')) {
      try {
        return Uri.parse(source).toFilePath();
      } catch (_) {
        return null;
      }
    }
    // 本地盘符路径、UNC（SMB）路径、http(s) 直链 ffmpeg 均可直接打开
    return source;
  }

  /// Windows 专用：启动 ffmpeg 子进程在指定时间点抽一帧，缩放为缩略图后
  /// 直接写成 JPEG 文件。子进程与主程序完全隔离：
  /// - 不会创建第二个播放器/D3D11 设备，从根源上消除原生死锁；
  /// - 启动与退出均有超时，异常时直接 kill 进程，绝不影响 UI 线程。
  Future<String?> _createTimelineThumbnailViaFfmpeg(
    String source,
    String targetPath,
    int bucket,
    int session,
  ) async {
    final exe = _resolveTimelineFfmpegPath();
    if (exe == null) return null;
    final input = _normalizeTimelineSourceForFfmpeg(source);
    if (input == null) return null;

    final args = <String>[
      '-hide_banner',
      '-loglevel', 'error',
      '-nostdin',
      '-y',
      // -ss 放在 -i 之前为输入级 seek，直接定位到最近关键帧，
      // 长视频也几乎瞬时完成，缩略图无需帧级精确。
      '-ss', (bucket / 1000.0).toStringAsFixed(3),
      '-i', input,
      '-frames:v', '1',
      '-vf', 'scale=$_timelinePreviewDefaultWidth:-2',
      '-q:v', '4',
      '-f', 'image2',
      targetPath,
    ];

    Process? process;
    try {
      process = await Process.start(exe, args)
          .timeout(const Duration(seconds: 10));
      // 排空 stderr，避免管道缓冲区写满后子进程阻塞
      unawaited(process.stderr.drain<List<int>>(<int>[]));
      final exitCode =
          await process.exitCode.timeout(const Duration(seconds: 20));
      if (session != _timelinePreviewSessionId) return null;
      final file = File(targetPath);
      if (exitCode == 0 &&
          await file.exists() &&
          (await file.length()) > 0) {
        _timelinePreviewCache[bucket] = targetPath;
        return targetPath;
      }
      debugPrint('ffmpeg 时间轴抽帧失败: exit=$exitCode, bucket=${bucket}ms');
      return null;
    } catch (e) {
      debugPrint('ffmpeg 时间轴抽帧异常: $e');
      if (process != null) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
      return null;
    }
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
      previewPlayer.dispose();
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
    try {
      _timelinePreviewPlayer?.dispose();
    } catch (_) {}
    _timelinePreviewPlayer = null;
    _timelinePreviewPlayerKernel = null;
    _timelinePreviewPlayerSource = null;
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

      player.state = PlayerPlaybackState.playing;
      await Future.delayed(const Duration(milliseconds: 70));
      player.state = PlayerPlaybackState.paused;
      await Future.delayed(const Duration(milliseconds: 40));

      if (session != _timelinePreviewSessionId) return null;

      if (kernel == PlayerKernelType.mdk) {
        // MDK 首次 snapshot 可能没有渲染帧，先触发一次以确保后续截图可用。
        await player.snapshot(width: targetWidth, height: targetHeight);
        await Future.delayed(const Duration(milliseconds: 60));
      }

      PlayerFrame? frame =
          await player.snapshot(width: targetWidth, height: targetHeight);
      if ((frame == null || frame.bytes.isEmpty) &&
          kernel == PlayerKernelType.mdk) {
        await Future.delayed(const Duration(milliseconds: 80));
        frame = await player.snapshot(width: targetWidth, height: targetHeight);
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
