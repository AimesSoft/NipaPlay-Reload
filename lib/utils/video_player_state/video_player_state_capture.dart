part of video_player_state;

class _RawFrameSpec {
  final int width;
  final int height;
  final int? rowStride;

  const _RawFrameSpec({
    required this.width,
    required this.height,
    this.rowStride,
  });
}

extension VideoPlayerStateCapture on VideoPlayerState {
  bool _isPngBytes(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
  }

  bool _isJpegBytes(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }

  _RawFrameSpec? _matchRawFrameSpec(PlayerFrame frame) {
    final byteLength = frame.bytes.length;
    final candidates = <_RawFrameSpec>[];

    void addCandidate(int width, int height) {
      if (width > 0 && height > 0) {
        candidates.add(_RawFrameSpec(width: width, height: height));
      }
    }

    addCandidate(frame.width, frame.height);

    final videoTracks = player.mediaInfo.video;
    if (videoTracks != null && videoTracks.isNotEmpty) {
      final codec = videoTracks.first.codec;
      addCandidate(codec.width, codec.height);
    }

    for (final candidate in candidates) {
      final expected = candidate.width * candidate.height * 4;
      if (byteLength == expected) {
        return candidate;
      }
    }

    for (final candidate in candidates) {
      if (byteLength % candidate.height != 0) {
        continue;
      }
      final stride = byteLength ~/ candidate.height;
      if (stride >= candidate.width * 4) {
        return _RawFrameSpec(
          width: candidate.width,
          height: candidate.height,
          rowStride: stride,
        );
      }
    }

    return null;
  }

  // 触发图片缓存刷新，使新缩略图可见
  void _triggerImageCacheRefresh(String imagePath) {
    if (kIsWeb) return; // Web平台不支持文件操作
    try {
      // 从图片缓存中移除该图片
      ////debugPrint('刷新图片缓存: $imagePath');
      // 清除特定图片的缓存
      final file = File(imagePath);
      if (file.existsSync()) {
        // 1. 先获取文件URI
        final uri = Uri.file(imagePath);
        // 2. 从缓存中驱逐此图像
        PaintingBinding.instance.imageCache.evict(FileImage(file));
        // 3. 也清除以NetworkImage方式缓存的图像
        PaintingBinding.instance.imageCache.evict(NetworkImage(uri.toString()));
        ////debugPrint('图片缓存已刷新');
      }
    } catch (e) {
      //debugPrint('刷新图片缓存失败: $e');
    }
  }

  // 启动截图定时器 - 每5秒截取一次视频帧
  void _startScreenshotTimer() {
    // 移除定时截图功能，改为条件性截图
    // 原先的定时截图代码已被删除
  }

  // 停止截图定时器
  void _stopScreenshotTimer() {
    // 不再需要停止定时器，但保留方法以避免其他地方调用出错
  }

  // 不暂停视频的截图方法
  Future<String?> _captureVideoFrameWithoutPausing() async {
    if (_currentVideoPath == null || !hasVideo) return null;

    try {
      // 使用适当的宽高比计算图像尺寸
      const int targetWidth = 0; // 使用0表示使用原始宽度
      const int targetHeight = 0; // 使用0表示使用原始高度

      // 使用Player的snapshot方法获取当前帧，保留原始宽高比
      final videoFrame =
          await player.snapshot(width: targetWidth, height: targetHeight);
      if (videoFrame == null) {
        debugPrint('截图失败: 播放器返回了null');
        return null;
      }

      // 检查截图尺寸
      debugPrint(
          '获取到的截图尺寸: ${videoFrame.width}x${videoFrame.height}, 字节数: ${videoFrame.bytes.length}');

      // 使用缓存的哈希值或重新计算哈希值
      String videoFileHash;
      if (_currentVideoHash != null) {
        videoFileHash = _currentVideoHash!;
      } else {
        videoFileHash = await _calculateFileHash(_currentVideoPath!);
        _currentVideoHash = videoFileHash; // 缓存哈希值
      }

      // 创建缩略图目录
      final appDir = await StorageService.getAppStorageDirectory();
      final thumbnailDir = Directory('${appDir.path}/thumbnails');
      if (!thumbnailDir.existsSync()) {
        thumbnailDir.createSync(recursive: true);
      }

      // 保存缩略图文件路径
      final thumbnailPath = '${thumbnailDir.path}/$videoFileHash.png';
      final thumbnailFile = File(thumbnailPath);

      final frameBytes = videoFrame.bytes;

      if (_isPngBytes(frameBytes)) {
        debugPrint('检测到PNG格式的截图数据，直接保存');
        await thumbnailFile.writeAsBytes(frameBytes);
        debugPrint('成功保存PNG截图，大小: ${frameBytes.length} 字节');
        return thumbnailPath;
      }

      if (_isJpegBytes(frameBytes)) {
        debugPrint('检测到JPEG格式的截图数据，直接保存');
        await thumbnailFile.writeAsBytes(frameBytes);
        debugPrint('成功保存JPEG截图，大小: ${frameBytes.length} 字节');
        return thumbnailPath;
      }

      img.Image? decoded;
      try {
        decoded = img.decodeImage(frameBytes);
      } catch (_) {}

      if (decoded != null) {
        debugPrint('检测到已编码的截图数据，转换为PNG保存');
        final pngBytes = img.encodePng(decoded);
        await thumbnailFile.writeAsBytes(pngBytes);
        debugPrint('成功保存转换后的截图，尺寸: ${decoded.width}x${decoded.height}');
        return thumbnailPath;
      }

      debugPrint('检测到原始像素格式的截图数据，尝试转换处理');
      final rawSpec = _matchRawFrameSpec(videoFrame);
      if (rawSpec == null) {
        debugPrint('无法确定原始截图尺寸，跳过保存');
        return null;
      }

      final expectedLength = rawSpec.width * rawSpec.height * 4;
      if (frameBytes.length < expectedLength ||
          (frameBytes.length != expectedLength && rawSpec.rowStride == null)) {
        debugPrint(
            '原始截图数据长度与尺寸不匹配: ${frameBytes.length} 字节, 期望: $expectedLength');
        return null;
      }

      try {
        final channelOrder = player.getPlayerKernelName() == 'Media Kit'
            ? img.ChannelOrder.bgra
            : img.ChannelOrder.rgba;
        final rawCopy = Uint8List.fromList(frameBytes);
        final image = img.Image.fromBytes(
          width: rawSpec.width,
          height: rawSpec.height,
          bytes: rawCopy.buffer,
          numChannels: 4,
          rowStride: rawSpec.rowStride,
          order: channelOrder,
        );

        final pngBytes = img.encodePng(image);
        await thumbnailFile.writeAsBytes(pngBytes);

        debugPrint(
            '成功保存转换后的截图，保留了${rawSpec.width}x${rawSpec.height}的原始比例');
        return thumbnailPath;
      } catch (e) {
        debugPrint('处理图像数据时出错: $e');
        return null;
      }
    } catch (e) {
      debugPrint('无暂停截图时出错: $e');
      return null;
    }
  }

  // 捕获视频帧的方法（会暂停视频，用于手动截图）
  Future<String?> captureVideoFrame() async {
    if (_currentVideoPath == null || !hasVideo) return null;

    try {
      // 暂停播放，以便获取当前帧
      final isPlaying = player.state == PlaybackState.playing;
      if (isPlaying) {
        player.state = PlaybackState.paused;
      }

      // 等待一段时间确保暂停完成
      await Future.delayed(const Duration(milliseconds: 50));

      // 计算保持原始宽高比的图像尺寸
      const int targetHeight = 128;
      int targetWidth = 128; // 默认值

      // 从视频媒体信息获取宽高比
      if (player.mediaInfo.video != null &&
          player.mediaInfo.video!.isNotEmpty) {
        final videoTrack = player.mediaInfo.video![0];
        if (videoTrack.codec.width > 0 && videoTrack.codec.height > 0) {
          final aspectRatio = videoTrack.codec.width / videoTrack.codec.height;
          targetWidth = (targetHeight * aspectRatio).round();
        }
      }

      // 使用Player的snapshot方法获取当前帧，保持宽高比
      final videoFrame =
          await player.snapshot(width: targetWidth, height: targetHeight);
      if (videoFrame == null) {
        //debugPrint('无法捕获视频帧');

        // 恢复播放状态
        if (isPlaying) {
          player.state = PlaybackState.playing;
        }

        return null;
      }

      // 使用缓存的哈希值或重新计算哈希值
      String videoFileHash;
      if (_currentVideoHash != null) {
        videoFileHash = _currentVideoHash!;
      } else {
        videoFileHash = await _calculateFileHash(_currentVideoPath!);
        _currentVideoHash = videoFileHash; // 缓存哈希值
      }

      // 直接使用image包将RGBA数据转换为PNG
      try {
        // 从RGBA字节数据创建图像
        final image = img.Image.fromBytes(
          width: targetWidth, // Should be videoFrame.width
          height: targetHeight, // Should be videoFrame.height
          bytes: videoFrame.bytes.buffer, // CHANGED to get ByteBuffer
          numChannels: 4,
        );

        // 编码为PNG格式
        final pngBytes = img.encodePng(image);

        // 创建缩略图目录
        final appDir = await StorageService.getAppStorageDirectory();
        final thumbnailDir = Directory('${appDir.path}/thumbnails');
        if (!thumbnailDir.existsSync()) {
          thumbnailDir.createSync(recursive: true);
        }

        // 保存缩略图文件
        final thumbnailPath = '${thumbnailDir.path}/$videoFileHash.png';
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile.writeAsBytes(pngBytes);

        // 恢复播放状态
        if (isPlaying) {
          player.state = PlaybackState.playing;
        }

        debugPrint(
            '视频帧缩略图已保存: $thumbnailPath, 尺寸: ${targetWidth}x$targetHeight');

        // 更新当前缩略图路径
        _currentThumbnailPath = thumbnailPath;

        return thumbnailPath;
      } catch (e) {
        //debugPrint('处理图像数据时出错: $e');

        // 恢复播放状态
        if (isPlaying) {
          player.state = PlaybackState.playing;
        }

        return null;
      }
    } catch (e) {
      //debugPrint('截取视频帧时出错: $e');

      // 恢复播放状态
      if (player.state == PlaybackState.paused &&
          _status == PlayerStatus.playing) {
        player.state = PlaybackState.playing;
      }

      return null;
    }
  }

  Future<String?> captureScreenshot() async {
    final bytes = await _captureScreenshotPngBytes();
    if (bytes == null || bytes.isEmpty) return null;

    try {
      final directoryPath = await _resolveScreenshotSaveDirectoryPath();
      final fileName = _buildScreenshotFileName();
      final file = File(p.join(directoryPath, fileName));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('截图失败: $e');
      return null;
    }
  }

  Future<bool> captureScreenshotToPhotos() async {
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;
    if (!hasVideo) return false;

    final bytes = await _captureScreenshotPngBytes();
    if (bytes == null || bytes.isEmpty) return false;

    await PhotoLibraryService.saveImageToPhotos(bytes);
    return true;
  }

  Future<Uint8List?> _captureScreenshotPngBytes() async {
    if (kIsWeb) return null;
    if (!hasVideo) return null;

    if (_isCapturingScreenshot) {
      return null;
    }

    final boundaryContext = screenshotBoundaryKey.currentContext;
    if (boundaryContext == null) {
      debugPrint('截图失败: screenshotBoundaryKey 未挂载到组件树');
      return null;
    }

    final renderObject = boundaryContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      debugPrint('截图失败: RenderObject 不是 RenderRepaintBoundary');
      return null;
    }

    _isCapturingScreenshot = true;
    try {
      // 确保当前帧已渲染完成
      await SchedulerBinding.instance.endOfFrame;

      final devicePixelRatio =
          MediaQuery.maybeOf(boundaryContext)?.devicePixelRatio ?? 1.0;
      // 过高的 pixelRatio 可能导致超大图片占用内存，做一个上限
      final pixelRatio = devicePixelRatio.clamp(1.0, 2.0);

      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        debugPrint('截图失败: image.toByteData 返回 null');
        return null;
      }

      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('截图失败: $e');
      return null;
    } finally {
      _isCapturingScreenshot = false;
    }
  }

  Future<String> _resolveScreenshotSaveDirectoryPath() async {
    String path = (_screenshotSaveDirectory ?? '').trim();
    if (path.isEmpty) {
      path = (await _getDefaultScreenshotSaveDirectory()).path;
      _screenshotSaveDirectory = path;
    }

    if (Platform.isMacOS) {
      final resolved = await SecurityBookmarkService.resolveBookmark(path);
      if (resolved != null && resolved.isNotEmpty) {
        path = resolved;
        _screenshotSaveDirectory = resolved;
      }
    }

    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }

  String _buildScreenshotFileName() {
    String baseName;

    final titleParts = <String>[
      if ((animeTitle ?? '').trim().isNotEmpty) animeTitle!.trim(),
      if ((episodeTitle ?? '').trim().isNotEmpty) episodeTitle!.trim(),
    ];

    if (titleParts.isNotEmpty) {
      baseName = titleParts.join(' - ');
    } else if ((_currentVideoPath ?? '').trim().isNotEmpty) {
      baseName = p.basenameWithoutExtension(_currentVideoPath!);
    } else {
      baseName = 'screenshot';
    }

    baseName = _sanitizeFileName(baseName);

    final now = DateTime.now();
    final timestamp = _formatTimestamp(now);
    return '${baseName}_$timestamp.png';
  }

  String _formatTimestamp(DateTime time) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');
    return '${time.year}${twoDigits(time.month)}${twoDigits(time.day)}_'
        '${twoDigits(time.hour)}${twoDigits(time.minute)}${twoDigits(time.second)}_'
        '${threeDigits(time.millisecond)}';
  }

  String _sanitizeFileName(String input) {
    final sanitized = input
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) {
      return 'screenshot';
    }
    // 避免文件名过长导致某些文件系统写入失败
    const maxLength = 80;
    return sanitized.length > maxLength ? sanitized.substring(0, maxLength) : sanitized;
  }
}
