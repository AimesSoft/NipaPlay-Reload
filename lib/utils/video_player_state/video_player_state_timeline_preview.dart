part of video_player_state;

const String _timelinePreviewEnabledKey = 'timelinePreviewEnabled';
const int _timelinePreviewIntervalMs = 15000;
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
    _timelinePreviewEnabled = enabled;
    _notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_timelinePreviewEnabledKey, enabled);
    } catch (e) {
      debugPrint('保存时间轴缩略图开关失败: $e');
    }
    if (enabled) {
      _timelinePreviewSupported = _isTimelinePreviewKernelSupported();
      if (_currentVideoPath != null) {
        _timelinePreviewSessionId++;
        unawaited(_prefetchInitialTimelineThumbnails());
      }
    } else {
      _resetTimelinePreviewState();
    }
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

  Future<void> _setupTimelinePreviewForVideo(String videoPath) async {
    if (!_timelinePreviewEnabled) return;
    _timelinePreviewSupported = _isTimelinePreviewKernelSupported();
    if (!_timelinePreviewSupported) return;
    _timelinePreviewSessionId++;
    _disposeTimelinePreviewPlayer();
    _timelinePreviewCache.clear();
    _timelinePreviewVideoKey = null;
    unawaited(() async {
      final dir = await _ensureTimelinePreviewDirectory();
      _timelinePreviewDirectory = dir.path;
      _hydrateTimelinePreviewCache(dir);
      if (_timelinePreviewEnabled && _timelinePreviewSupported) {
        unawaited(_prefetchInitialTimelineThumbnails());
        unawaited(_backgroundFillTimelineThumbnails());
      }
    }());
  }

  int _computeTimelineThumbnailCount() {
    final duration = _duration.inMilliseconds;
    if (duration <= 0) return 0;
    final interval =
        _timelinePreviewIntervalMs <= 0 ? 15000 : _timelinePreviewIntervalMs;
    return math.max(1, duration ~/ interval + 1);
  }

  int _computeTimelineThumbnailWidth() {
    final count = _computeTimelineThumbnailCount();
    final ratio = 8000.0 / count;
    final raw = (_timelinePreviewDefaultWidth * math.sqrt(ratio)).toInt();
    return raw.clamp(_timelinePreviewDefaultWidth, _timelinePreviewDefaultWidth * 3)
        .toInt();
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
        // Windows 平台改用独立 ffmpeg.exe 子进程抽帧，不再创建第二个 MDK
        // 播放器。fvp 的 updateTexture/snapshot 在第二播放器（无 widget 挂载）
        // 场景下无法获得渲染回调，textureId 永远为 null，snapshot 永远超时
        // 返回空帧——这是 fvp 的架构限制（设计上只服务挂载在 widget tree
        // 上的播放器）。子进程与主程序完全隔离，卡死/崩溃最多损失单张
        // 缩略图（20s 超时自动 kill），物理上不可能让主窗口未响应。
        if (!kIsWeb && Platform.isWindows) {
          final ok = await _captureTimelineFrameWithFfmpeg(
              source, bucket, targetPath);
          if (!ok || session != _timelinePreviewSessionId) return null;
          if (!File(targetPath).existsSync()) return null;
          _timelinePreviewCache[bucket] = targetPath;
          return targetPath;
        }

        // 非 Windows 平台：保留原始 MDK 第二播放器抽帧路径（已验证可用）。
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

  // ===========================================================================
  // Windows: ffmpeg.exe 子进程抽帧
  // ===========================================================================

  /// 查找随包分发的 ffmpeg.exe。优先与可执行文件同目录，其次 PATH。
  Future<String?> _findFfmpegExecutable() async {
    // 1. 与主程序同目录（CI 打包时放入）
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidate = p.join(exeDir, 'ffmpeg.exe');
      if (await File(candidate).exists()) return candidate;
      // portable 模式可能在 data/ 子目录
      final dataCandidate = p.join(exeDir, 'data', 'ffmpeg.exe');
      if (await File(dataCandidate).exists()) return dataCandidate;
    } catch (_) {}

    // 2. PATH 查找
    try {
      final result = await Process.run('where', ['ffmpeg.exe'],
          stdoutEncoding: systemEncoding,
          stderrEncoding: systemEncoding);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty) {
          final first = out.split(RegExp(r'\r?\n')).first.trim();
          if (first.isNotEmpty && await File(first).exists()) return first;
        }
      }
    } catch (_) {}

    return null;
  }

  /// 将媒体源路径转换为 ffmpeg 可接受的输入参数。
  /// - 本地盘符路径：直接用
  /// - file:// URI：解码为路径
  /// - UNC（\\server\share）：直接用
  /// - http(s) 直链：直接用
  String _ffmpegInputFromSource(String source) {
    if (source.startsWith('file://')) {
      try {
        return Uri.parse(source).toFilePath();
      } catch (_) {
        return source.substring(7);
      }
    }
    return source;
  }

  /// 用 ffmpeg.exe 抽取指定时间点的帧并缩放为 JPEG。
  /// 成功写出文件返回 true，任何失败（找不到 ffmpeg、超时、非零退出）返回 false。
  Future<bool> _captureTimelineFrameWithFfmpeg(
      String source, int bucketMs, String targetPath) async {
    final ffmpeg = await _findFfmpegExecutable();
    if (ffmpeg == null) {
      debugPrint('时间轴预览：未找到 ffmpeg.exe，请确保随包分发或已加入 PATH');
      return false;
    }

    final input = _ffmpegInputFromSource(source);
    final seekSec = (bucketMs / 1000.0).toStringAsFixed(3);

    // 输入级 seek（-ss 在 -i 之前）速度快、对大多数格式可靠。
    // scale 保持宽高比，高度固定 180，宽度上限 960 防止超宽。
    // -frames:v 1 只取一帧，-q:v 2 是 JPEG 高质量。
    final args = [
      '-y',                          // 覆盖已存在文件
      '-ss', seekSec,                // 输入级 seek
      '-i', input,                   // 输入
      '-frames:v', '1',              // 只取一帧
      '-vf', 'scale=\'min(960,iw)\':180:force_original_aspect_ratio=decrease',
      '-q:v', '2',                   // JPEG 高质量
      targetPath,                    // 输出
    ];

    final Process proc;
    try {
      proc = await Process.start(ffmpeg, args);
    } catch (e) {
      debugPrint('时间轴预览：启动 ffmpeg 失败: $e');
      return false;
    }

    // ffmpeg 会向 stderr 输出大量进度信息，必须排空管道，否则缓冲区写满
    // 后子进程会阻塞挂起。
    unawaited(proc.stdout.drain<void>());
    unawaited(proc.stderr.drain<void>());

    // 20 秒超时：子进程卡死/网络流缓慢时自动 kill，不影响主程序。
    final done = Completer<bool>();
    var killed = false;

    proc.exitCode.then((code) {
      if (!done.isCompleted) {
        done.complete(code == 0);
      }
    });

    final timer = Timer(const Duration(seconds: 20), () {
      if (!done.isCompleted) {
        killed = true;
        try {
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {}
        done.complete(false);
      }
    });

    final ok = await done.future;
    timer.cancel();

    if (!ok) {
      if (killed) {
        debugPrint('时间轴预览：ffmpeg 超时（20s）已终止 bucket=${bucketMs}ms');
      } else {
        // 非零退出：常见于 seek 超过时长、流损坏等，清理可能的空文件。
        try {
          if (await File(targetPath).exists()) {
            await File(targetPath).delete();
          }
        } catch (_) {}
      }
      return false;
    }

    // 验证输出文件非空
    try {
      final f = File(targetPath);
      return (await f.length()) > 0;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // 非 Windows：保留原始 MDK 第二播放器抽帧路径
  // ===========================================================================

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

  Future<void> _prefetchInitialTimelineThumbnails() async {
    if (!_timelinePreviewEnabled || !_timelinePreviewSupported) return;
    final duration = _duration.inMilliseconds;
    if (duration <= 0) return;

    final interval =
        _timelinePreviewIntervalMs <= 0 ? 15000 : _timelinePreviewIntervalMs;
    final count = math.min(2, duration ~/ interval + 1);
    final sessionId = _timelinePreviewSessionId;

    for (var i = 0; i < count; i++) {
      if (sessionId != _timelinePreviewSessionId) return;
      final bucket = (i * duration ~/ count) ~/ interval * interval;
      final cached = _timelinePreviewCache[bucket];
      if (cached == null || !File(cached).existsSync()) {
        await _createTimelineThumbnail(bucket, sessionId);
        // 批量预取间隔：避免短时间启动过多子进程。
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  Future<void> _backgroundFillTimelineThumbnails() async {
    if (!_timelinePreviewEnabled || !_timelinePreviewSupported) return;
    final duration = _duration.inMilliseconds;
    if (duration <= 0) return;

    final interval =
        _timelinePreviewIntervalMs <= 0 ? 15000 : _timelinePreviewIntervalMs;
    final total = duration ~/ interval + 1;
    // 后台批量生成上限 24 张（原 80 张过多，子进程方案下减少以降低 CPU/IO 压力）。
    final limit = math.min(24, total);
    final sessionId = _timelinePreviewSessionId;

    for (var i = 0; i < limit; i++) {
      if (sessionId != _timelinePreviewSessionId) return;
      if (!_timelinePreviewEnabled) return;
      final bucket = i * interval;
      if (bucket > duration) break;
      final cached = _timelinePreviewCache[bucket];
      if (cached == null || !File(cached).existsSync()) {
        await _createTimelineThumbnail(bucket, sessionId);
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }
}
