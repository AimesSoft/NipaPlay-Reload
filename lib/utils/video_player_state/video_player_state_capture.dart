part of video_player_state;

class _ThumbnailTargetSize {
  final int width;
  final int height;

  const _ThumbnailTargetSize({
    required this.width,
    required this.height,
  });
}

extension VideoPlayerStateCapture on VideoPlayerState {
  VideoFrameImageRequest _frameImageRequest(PlayerFrame frame) {
    final tracks = player.mediaInfo.video;
    final codec =
        tracks != null && tracks.isNotEmpty ? tracks.first.codec : null;
    return VideoFrameImageRequest(
      bytes: frame.bytes,
      width: frame.width,
      height: frame.height,
      sourceWidth: codec?.width ?? 0,
      sourceHeight: codec?.height ?? 0,
      bgra: player.getPlayerKernelName() == 'Media Kit',
    );
  }

  img.Image? _decodeFrameToImage(PlayerFrame frame) =>
      decodeVideoFrameImage(_frameImageRequest(frame));

  Future<Uint8List?> _encodeFrameToThumbnailBytes(PlayerFrame frame) =>
      compute(encodeVideoThumbnail, _frameImageRequest(frame),
          debugLabel: 'video-thumbnail');

  Uint8List? _encodeFrameToScreenshotBytes(
      PlayerFrame frame, ScreenshotFormat format) {
    final decoded = _decodeFrameToImage(frame);
    if (decoded == null) {
      return null;
    }
    return Uint8List.fromList(
      encodeScreenshotImage(decoded,
          format: format, jpegQuality: _screenshotQuality.jpegQuality),
    );
  }

  _ThumbnailTargetSize _resolveThumbnailTargetSize() {
    int targetHeight = thumbnailMaxHeight;
    int targetWidth = (thumbnailMaxHeight * 16 / 9).round();

    final videoTracks = player.mediaInfo.video;
    if (videoTracks != null && videoTracks.isNotEmpty) {
      final codec = videoTracks.first.codec;
      if (codec.width > 0 && codec.height > 0) {
        final aspectRatio = codec.width / codec.height;
        targetWidth = (targetHeight * aspectRatio).round();
        if (targetWidth > thumbnailMaxWidth) {
          targetWidth = thumbnailMaxWidth;
          targetHeight = (targetWidth / aspectRatio)
              .round()
              .clamp(1, thumbnailMaxHeight)
              .toInt();
        }
      }
    }

    targetWidth = targetWidth.clamp(1, thumbnailMaxWidth).toInt();
    targetHeight = targetHeight.clamp(1, thumbnailMaxHeight).toInt();
    return _ThumbnailTargetSize(width: targetWidth, height: targetHeight);
  }

  _ThumbnailTargetSize _resolveScreenshotTargetSize() {
    final videoTracks = player.mediaInfo.video;
    if (videoTracks != null && videoTracks.isNotEmpty) {
      final codec = videoTracks.first.codec;
      if (codec.width > 0 && codec.height > 0) {
        return _ThumbnailTargetSize(width: codec.width, height: codec.height);
      }
    }
    return _resolveThumbnailTargetSize();
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
    if (kIsWeb) return null;
    if (_currentVideoPath == null || !hasVideo) return null;

    try {
      final targetSize = _resolveThumbnailTargetSize();

      // 使用Player的snapshot方法获取当前帧，保留原始宽高比
      final videoFrame = await player.snapshot(
        width: targetSize.width,
        height: targetSize.height,
      );
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
      final thumbnailPath = '${thumbnailDir.path}/$videoFileHash.jpg';
      final legacyPngPath = '${thumbnailDir.path}/$videoFileHash.png';
      final thumbnailFile = File(thumbnailPath);

      final jpegBytes = await _encodeFrameToThumbnailBytes(videoFrame);
      if (jpegBytes == null || jpegBytes.isEmpty) {
        debugPrint('无法转换截图数据，跳过保存');
        return null;
      }

      await thumbnailFile.writeAsBytes(jpegBytes, flush: true);
      final legacyPngFile = File(legacyPngPath);
      if (legacyPngFile.existsSync()) {
        try {
          legacyPngFile.deleteSync();
        } catch (_) {}
      }
      debugPrint('成功保存截图，大小: ${jpegBytes.length} 字节');
      return thumbnailPath;
    } catch (e) {
      debugPrint('无暂停截图时出错: $e');
      return null;
    }
  }

  // 捕获视频帧的方法（会暂停视频，用于手动截图）
  Future<String?> captureVideoFrame() async {
    if (kIsWeb) return null;
    if (_currentVideoPath == null || !hasVideo) return null;

    try {
      // 暂停播放，以便获取当前帧
      final isPlaying = player.state == PlaybackState.playing;
      if (isPlaying) {
        player.state = PlaybackState.paused;
      }

      // 等待一段时间确保暂停完成
      await Future.delayed(const Duration(milliseconds: 50));

      final targetSize = _resolveThumbnailTargetSize();

      // 使用Player的snapshot方法获取当前帧，保持宽高比
      final videoFrame = await player.snapshot(
        width: targetSize.width,
        height: targetSize.height,
      );
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

      try {
        final jpegBytes = await _encodeFrameToThumbnailBytes(videoFrame);
        if (jpegBytes == null || jpegBytes.isEmpty) {
          // 恢复播放状态
          if (isPlaying) {
            player.state = PlaybackState.playing;
          }
          return null;
        }

        // 创建缩略图目录
        final appDir = await StorageService.getAppStorageDirectory();
        final thumbnailDir = Directory('${appDir.path}/thumbnails');
        if (!thumbnailDir.existsSync()) {
          thumbnailDir.createSync(recursive: true);
        }

        // 保存缩略图文件
        final thumbnailPath = '${thumbnailDir.path}/$videoFileHash.jpg';
        final legacyPngPath = '${thumbnailDir.path}/$videoFileHash.png';
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile.writeAsBytes(jpegBytes, flush: true);
        final legacyPngFile = File(legacyPngPath);
        if (legacyPngFile.existsSync()) {
          try {
            legacyPngFile.deleteSync();
          } catch (_) {}
        }

        // 恢复播放状态
        if (isPlaying) {
          player.state = PlaybackState.playing;
        }

        debugPrint(
            '视频帧缩略图已保存: $thumbnailPath, 尺寸: ${targetSize.width}x${targetSize.height}');

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

  Future<String?> captureScreenshot({
    ScreenshotFormat? format,
    bool? includeDanmaku,
    bool? includeSubtitles,
    bool temporary = false,
  }) async {
    if (kIsWeb || !hasVideo) return null;
    format ??= _screenshotFormat;
    final bytes = await _captureScreenshotBytes(
      format: format,
      // 未显式传参时回退到截图设置页的开关
      includeDanmaku: includeDanmaku ?? _screenshotCaptureIncludesDanmaku,
      includeSubtitles: includeSubtitles ?? _screenshotCaptureIncludesSubtitles,
    );
    if (bytes == null || bytes.isEmpty) return null;

    try {
      final directoryPath = temporary
          ? (await path_provider.getTemporaryDirectory()).path
          : await _resolveScreenshotSaveDirectoryPath();
      final fileName = _buildScreenshotFileName(format);
      final file = File(p.join(directoryPath, fileName));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('截图失败: $e');
      return null;
    }
  }

  Future<bool> captureScreenshotToPhotos({
    bool? includeDanmaku,
    bool? includeSubtitles,
  }) async {
    includeDanmaku ??= _screenshotCaptureIncludesDanmaku;
    includeSubtitles ??= _screenshotCaptureIncludesSubtitles;
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;
    if (!hasVideo) return false;

    final bytes = await _captureScreenshotBytes(
      format: _screenshotFormat,
      includeDanmaku: includeDanmaku,
      includeSubtitles: includeSubtitles,
    );
    if (bytes == null || bytes.isEmpty) return false;

    await PhotoLibraryService.saveImageToPhotos(bytes);
    return true;
  }

  Future<Uint8List?> captureScreenshotPreview({
    bool includeDanmaku = true,
    bool includeSubtitles = true,
  }) {
    return _captureScreenshotBytes(
      includeDanmaku: includeDanmaku,
      includeSubtitles: includeSubtitles,
    );
  }

  Future<Uint8List?> _captureScreenshotBytes({
    ScreenshotFormat? format,
    required bool includeDanmaku,
    required bool includeSubtitles,
  }) async {
    if (kIsWeb) return null;
    if (!hasVideo) return null;
    format ??= _screenshotFormat;

    if (_isCapturingScreenshot) {
      return null;
    }

    if (player.getPlayerKernelName() == 'Erika') {
      try {
        final targetSize = _resolveScreenshotTargetSize();
        final frame = await player.snapshot(
          width: targetSize.width,
          height: targetSize.height,
        );
        if (frame != null) {
          final bytes = _encodeFrameToScreenshotBytes(frame, format);
          if (bytes != null && bytes.isNotEmpty) {
            return bytes;
          }
        }
        debugPrint('Erika截图失败: native snapshot 未返回可编码帧');
        return null;
      } catch (e) {
        debugPrint('Erika截图失败: $e');
        return null;
      }
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
    final previousIncludeDanmaku = _screenshotCaptureIncludesDanmaku;
    final previousIncludeSubtitles = _screenshotCaptureIncludesSubtitles;
    final previousSubtitleTracks = List<int>.from(player.activeSubtitleTracks);
    _screenshotCaptureIncludesDanmaku = includeDanmaku;
    _screenshotCaptureIncludesSubtitles = includeSubtitles;
    if (!includeSubtitles && previousSubtitleTracks.isNotEmpty) {
      // Native player subtitles are rendered into the video surface rather
      // than ExternalSubtitleOverlay. Disable the actual subtitle track for
      // the captured frame, then restore the selection in finally.
      player.activeSubtitleTracks = const <int>[];
    }
    _notifyListeners();
    try {
      // 确保当前帧已渲染完成
      await SchedulerBinding.instance.endOfFrame;
      if (!includeSubtitles && previousSubtitleTracks.isNotEmpty) {
        // Track changes may cross an asynchronous player bridge. Give the
        // texture one additional frame to present without subtitles.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await SchedulerBinding.instance.endOfFrame;
      }

      final devicePixelRatio =
          MediaQuery.maybeOf(boundaryContext)?.devicePixelRatio ?? 1.0;
      // 过高的 pixelRatio 可能导致超大图片占用内存，做一个上限
      final pixelRatio = devicePixelRatio.clamp(1.0, 2.0);

      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      // 先读取原始 RGBA，再按用户选择编码 PNG 或指定质量的 JPEG。
      final rgbaData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final imageWidth = image.width;
      final imageHeight = image.height;
      image.dispose();

      if (rgbaData == null) {
        debugPrint('截图失败: image.toByteData 返回 null');
        return null;
      }

      final rgba = rgbaData.buffer.asUint8List();
      final decoded = img.Image.fromBytes(
        width: imageWidth,
        height: imageHeight,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      // Use the same placement as the player. Cover/fill have no outer bars;
      // forced ratios and original-size modes may have a different visible rect.
      if (_screenshotCropLetterbox &&
          _aspectRatio > 0 &&
          !renderObject.size.isEmpty) {
        final viewport = renderObject.size;
        final videoTracks = player.mediaInfo.video;
        Size? naturalSize;
        if (videoTracks != null && videoTracks.isNotEmpty) {
          final codec = videoTracks.first.codec;
          if (codec.width > 0 && codec.height > 0) {
            naturalSize = Size(codec.width.toDouble(), codec.height.toDouble());
          }
        }
        final visibleRect = VideoAspectGeometry.visibleVideoRect(
          mode: _videoAspectMode,
          viewport: viewport,
          sourceAspect: _aspectRatio,
          naturalSize: naturalSize,
        );
        final scaleX = imageWidth / viewport.width;
        final scaleY = imageHeight / viewport.height;
        final x =
            (visibleRect.left * scaleX).round().clamp(0, imageWidth).toInt();
        final y =
            (visibleRect.top * scaleY).round().clamp(0, imageHeight).toInt();
        final right =
            (visibleRect.right * scaleX).round().clamp(x, imageWidth).toInt();
        final bottom =
            (visibleRect.bottom * scaleY).round().clamp(y, imageHeight).toInt();
        final cw = right - x;
        final ch = bottom - y;
        if (cw > 0 && ch > 0 && (cw < imageWidth || ch < imageHeight)) {
          debugPrint('[Screenshot] 裁剪黑边 x=$x y=$y w=$cw h=$ch '
              '(原始 ${imageWidth}x$imageHeight)');
          final cropped =
              img.copyCrop(decoded, x: x, y: y, width: cw, height: ch);
          final jpegBytes =
              encodeScreenshotImage(cropped,
                  format: format, jpegQuality: _screenshotQuality.jpegQuality);
          return Uint8List.fromList(jpegBytes);
        }
      }
      final jpegBytes =
          encodeScreenshotImage(decoded,
              format: format, jpegQuality: _screenshotQuality.jpegQuality);
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      debugPrint('截图失败: $e');
      return null;
    } finally {
      if (!includeSubtitles && previousSubtitleTracks.isNotEmpty) {
        player.activeSubtitleTracks = previousSubtitleTracks;
      }
      _screenshotCaptureIncludesDanmaku = previousIncludeDanmaku;
      _screenshotCaptureIncludesSubtitles = previousIncludeSubtitles;
      _isCapturingScreenshot = false;
      _notifyListeners();
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
      try {
        await directory.create(recursive: true);
      } catch (_) {
        // 目标路径不可创建（如 iOS 沙盒根 Operation not permitted）：
        // 回退并缓存默认目录，避免每次截图都重复尝试失败路径。
        final fallback = (await _getDefaultScreenshotSaveDirectory()).path;
        _screenshotSaveDirectory = fallback;
        return fallback;
      }
    }
    return directory.path;
  }

  String _buildScreenshotFileName(ScreenshotFormat format) {
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
    return '${baseName}_$timestamp.${format.extension}';
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
    return sanitized.length > maxLength
        ? sanitized.substring(0, maxLength)
        : sanitized;
  }
}
