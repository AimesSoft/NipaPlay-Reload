import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> showMediaCaptureDialog({
  required BuildContext context,
  required VideoPlayerState videoState,
  required Future<void> Function(
    ScreenshotSaveTarget target, {
    required bool includeDanmaku,
    required bool includeSubtitles,
  }) onCaptureImage,
  bool barrierDismissible = true,
}) {
  return BlurDialog.show<void>(
    context: context,
    title: '',
    desktopMaxWidth: 1120,
    desktopMaxHeightFactor: 0.9,
    barrierDismissible: barrierDismissible,
    contentWidget: MediaCaptureDialogContent(
      videoState: videoState,
      onCaptureImage: onCaptureImage,
    ),
  );
}

class MediaCaptureDialogContent extends StatefulWidget {
  const MediaCaptureDialogContent({
    super.key,
    required this.videoState,
    required this.onCaptureImage,
  });

  final VideoPlayerState videoState;
  final Future<void> Function(
    ScreenshotSaveTarget target, {
    required bool includeDanmaku,
    required bool includeSubtitles,
  }) onCaptureImage;

  @override
  State<MediaCaptureDialogContent> createState() =>
      _MediaCaptureDialogContentState();
}

class _MediaCaptureDialogContentState extends State<MediaCaptureDialogContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;
  late double _startMillis;
  late double _endMillis;
  late double _maximumMillis;
  int _framesPerSecond = 15;
  GifExportQuality _quality = GifExportQuality.normal;
  String? _previewPath;
  Uint8List? _imagePreviewBytes;
  bool _includeDanmaku = true;
  bool _includeSubtitles = true;
  bool _isRefreshingImagePreview = false;
  bool _isWorking = false;
  String? _workingLabel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final duration = widget.videoState.duration.inMilliseconds;
    _maximumMillis = duration > 0 ? duration.toDouble() : 1.0;
    _startMillis = widget.videoState.position.inMilliseconds
        .clamp(0, _maximumMillis.toInt())
        .toDouble();
    _endMillis = (_startMillis + 5000).clamp(0, _maximumMillis).toDouble();
    if (_endMillis <= _startMillis) {
      _startMillis = (_maximumMillis - 5000).clamp(0, _maximumMillis);
      _endMillis = _maximumMillis;
    }
    _startTimeController =
        TextEditingController(text: _formatTime(_startMillis));
    _endTimeController = TextEditingController(text: _formatTime(_endMillis));
    final size = _recommendedSize();
    _widthController = TextEditingController(text: '${size.$1}');
    _heightController = TextEditingController(text: '${size.$2}');
    final supportsCompositedScreenshot =
        widget.videoState.player.getPlayerKernelName() != 'Erika';
    // 初值来自截图设置页(而非每次弹窗都重置);同时受内核合成截图能力约束
    _includeDanmaku = supportsCompositedScreenshot &&
        widget.videoState.screenshotCaptureIncludesDanmaku &&
        widget.videoState.danmakuVisible;
    _includeSubtitles = supportsCompositedScreenshot &&
        widget.videoState.screenshotCaptureIncludesSubtitles;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 等弹窗打开动画完成后再生成预览：全分辨率 toImage+JPEG 编码
      // 是 100-500ms 的重活，立即执行会阻塞动画线程导致打开掉帧。
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) unawaited(_refreshImagePreview());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    final previewPath = _previewPath;
    if (previewPath != null) {
      unawaited(
          File(previewPath).delete().catchError((_) => File(previewPath)));
    }
    super.dispose();
  }

  (int, int) _sourceSize() {
    final video = widget.videoState.player.mediaInfo.video;
    if (video != null && video.isNotEmpty) {
      final codec = video.first.codec;
      if (codec.width > 0 && codec.height > 0) {
        return (codec.width, codec.height);
      }
    }
    final aspect = widget.videoState.aspectRatio > 0
        ? widget.videoState.aspectRatio
        : 16 / 9;
    return (1920, _even(1920 / aspect));
  }

  (int, int) _recommendedSize() {
    final source = _sourceSize();
    if (source.$1 <= 640) return source;
    return (640, _even(640 * source.$2 / source.$1));
  }

  int _even(num value) {
    final rounded = value.round().clamp(2, 8192);
    return rounded.isEven ? rounded : rounded - 1;
  }

  void _setOutputSize((int, int) size) {
    setState(() {
      _widthController.text = '${size.$1}';
      _heightController.text = '${size.$2}';
    });
  }

  String _formatTime(double milliseconds) {
    final duration = Duration(milliseconds: milliseconds.round());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final tenths = (duration.inMilliseconds.remainder(1000) ~/ 100).toString();
    final hours = duration.inHours;
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds.$tenths'
        : '$minutes:$seconds.$tenths';
  }

  double? _parseTime(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length > 3) return null;
    var seconds = 0.0;
    for (final part in parts) {
      final parsed = double.tryParse(part);
      if (parsed == null || parsed < 0) return null;
      seconds = seconds * 60 + parsed;
    }
    if (!seconds.isFinite) return null;
    return seconds * 1000;
  }

  void _handleTimeChanged({required bool start}) {
    final parsed = _parseTime(
      start ? _startTimeController.text : _endTimeController.text,
    );
    if (parsed == null) return;
    setState(() {
      if (start) {
        _startMillis = parsed;
      } else {
        _endMillis = parsed;
      }
    });
  }

  void _fillCurrentTime() {
    final current = widget.videoState.position.inMilliseconds
        .clamp(0, _maximumMillis.toInt())
        .toDouble();
    final previousDuration = (_endMillis - _startMillis).clamp(500, 30000);
    setState(() {
      _startMillis = current;
      _endMillis = (current + previousDuration).clamp(0, _maximumMillis);
      if (_endMillis <= _startMillis) {
        _startMillis = (_maximumMillis - 500).clamp(0, _maximumMillis);
        _endMillis = _maximumMillis;
      }
      _startTimeController.text = _formatTime(_startMillis);
      _endTimeController.text = _formatTime(_endMillis);
    });
  }

  String? _validateSource() {
    if (!widget.videoState.player.supportsGifExport) {
      return '当前平台暂不支持 Erika GIF 导出工具。';
    }
    final source = widget.videoState.currentResolvedMediaSource;
    if (source == null || source.trim().isEmpty) {
      return '没有可导出的媒体地址。';
    }
    final start = _parseTime(_startTimeController.text);
    final end = _parseTime(_endTimeController.text);
    if (start == null || end == null) return '请输入有效的开始和结束时间。';
    if (start < 0 || end > _maximumMillis) return '时间范围不能超出视频时长。';
    if (end <= start) return '结束时间必须晚于开始时间。';
    if (end - start > 30000) return '单次 GIF 最长支持 30 秒。';
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null || width < 2 || height < 2) {
      return '请输入有效的输出尺寸。';
    }
    if (width > 4096 || height > 4096) return '输出尺寸不能超过 4096 × 4096。';
    return null;
  }

  Future<GifExportResult?> _exportTo(String outputPath, String label) async {
    final validation = _validateSource();
    if (validation != null) {
      BlurSnackBar.show(context, validation);
      return null;
    }
    final source = widget.videoState.currentResolvedMediaSource!;
    final start = _parseTime(_startTimeController.text)!;
    final end = _parseTime(_endTimeController.text)!;
    setState(() {
      _isWorking = true;
      _workingLabel = label;
    });
    try {
      final result = await widget.videoState.player.exportGif(
        GifExportRequest(
          inputUri: source,
          outputPath: outputPath,
          start: Duration(milliseconds: start.round()),
          end: Duration(milliseconds: end.round()),
          framesPerSecond: _framesPerSecond,
          outputWidth: int.parse(_widthController.text),
          outputHeight: int.parse(_heightController.text),
          quality: _quality,
        ),
      );
      return result;
    } catch (error) {
      if (mounted) BlurSnackBar.show(context, 'GIF 导出失败：$error');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _workingLabel = null;
        });
      }
    }
  }

  Future<String?> _refreshPreview() async {
    final directory = await getTemporaryDirectory();
    final outputPath = p.join(
      directory.path,
      'nipaplay_gif_preview_${DateTime.now().microsecondsSinceEpoch}.gif',
    );
    final result = await _exportTo(outputPath, '正在生成预览…');
    if (result == null || !mounted) return null;
    final previous = _previewPath;
    setState(() => _previewPath = result.outputPath);
    if (previous != null && previous != result.outputPath) {
      unawaited(File(previous).delete().catchError((_) => File(previous)));
    }
    return result.outputPath;
  }

  Future<void> _copyPreview() async {
    final path = _previewPath ?? await _refreshPreview();
    if (path == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: Uri.file(path).toString()));
    if (mounted) BlurSnackBar.show(context, 'GIF 文件地址已复制到剪贴板');
  }

  Future<void> _exportFile() async {
    final location = await getSaveLocation(
      suggestedName: 'nipaplay_${DateTime.now().millisecondsSinceEpoch}.gif',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'GIF 动图', extensions: ['gif']),
      ],
    );
    if (location == null || !mounted) return;
    final result = await _exportTo(location.path, '正在导出 GIF…');
    if (result != null && mounted) {
      BlurSnackBar.show(
        context,
        'GIF 已导出：${result.width}×${result.height}，${result.frameCount} 帧',
      );
    }
  }

  bool get _supportsCompositedScreenshot =>
      widget.videoState.player.getPlayerKernelName() != 'Erika';

  Future<void> _refreshImagePreview() async {
    if (_isRefreshingImagePreview) return;
    setState(() => _isRefreshingImagePreview = true);
    final bytes = await widget.videoState.captureScreenshotPreview(
      includeDanmaku: _includeDanmaku,
      includeSubtitles: _includeSubtitles,
    );
    if (!mounted) return;
    setState(() {
      _imagePreviewBytes = bytes;
      _isRefreshingImagePreview = false;
    });
    if (bytes == null || bytes.isEmpty) {
      BlurSnackBar.show(context, '当前画面预览生成失败');
    }
  }

  Future<void> _captureImage(ScreenshotSaveTarget target) async {
    setState(() {
      _isWorking = true;
      _workingLabel =
          target == ScreenshotSaveTarget.photos ? '正在保存到相册…' : '正在保存截图…';
    });
    try {
      await widget.onCaptureImage(
        target,
        includeDanmaku: _includeDanmaku,
        includeSubtitles: _includeSubtitles,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _workingLabel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppAccentColors.current.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.photo_camera_back_rounded,
                    color: AppAccentColors.current),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('画面截取',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            )),
                    Text('保存当前画面，或从正在播放的媒体生成 GIF 动图',
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.62),
                          fontSize: 13,
                        )),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed:
                    _isWorking ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [
                Tab(text: '图片截取', icon: Icon(Icons.image_outlined)),
                Tab(text: 'GIF 截取', icon: Icon(Icons.gif_box_outlined)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 430,
            child: TabBarView(
              controller: _tabController,
              children: [_buildImageTab(colors), _buildGifTab(colors)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTab(ColorScheme colors) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final preview = _Panel(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_imagePreviewBytes != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Image.memory(
                  _imagePreviewBytes!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              )
            else
              Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 72,
                  color: colors.onSurface.withValues(alpha: 0.22),
                ),
              ),
            if (_isRefreshingImagePreview)
              ColoredBox(
                color: colors.surface.withValues(alpha: 0.7),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      );
      final controls = _Panel(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '图片截取设置',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _supportsCompositedScreenshot
                    ? '预览与导出会按下方叠加内容设置生成。'
                    : 'Erika 当前输出视频原始帧，截图不包含字幕和弹幕。',
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.58),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('包含弹幕'),
                subtitle: const Text('将当前屏幕上的弹幕合成到截图'),
                value: _includeDanmaku,
                onChanged: !_supportsCompositedScreenshot || _isWorking
                    ? null
                    : (value) {
                        setState(() => _includeDanmaku = value);
                        unawaited(_refreshImagePreview());
                      },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('包含字幕'),
                subtitle: const Text('将当前外挂字幕合成到截图'),
                value: _includeSubtitles,
                onChanged: !_supportsCompositedScreenshot || _isWorking
                    ? null
                    : (value) {
                        setState(() => _includeSubtitles = value);
                        unawaited(_refreshImagePreview());
                      },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('裁剪黑边'),
                subtitle: const Text('截图不包含视频画面外的上下/左右黑边'),
                value: widget.videoState.screenshotCropLetterbox,
                onChanged: !_supportsCompositedScreenshot || _isWorking
                    ? null
                    : (value) {
                        unawaited(
                          widget.videoState.setScreenshotCropLetterbox(value),
                        );
                        unawaited(_refreshImagePreview());
                      },
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _isWorking ? null : _refreshImagePreview,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新预览'),
              ),
              const SizedBox(height: 10),
              if (!kIsWeb && Platform.isIOS) ...[
                FilledButton.icon(
                  onPressed: _isWorking
                      ? null
                      : () => unawaited(
                            _captureImage(ScreenshotSaveTarget.photos),
                          ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('保存到相册'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isWorking
                      ? null
                      : () => unawaited(
                            _captureImage(ScreenshotSaveTarget.file),
                          ),
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text('保存到文件'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _isWorking
                      ? null
                      : () => unawaited(
                            _captureImage(ScreenshotSaveTarget.file),
                          ),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('立即截取'),
                ),
            ],
          ),
        ),
      );
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 11, child: preview),
            const SizedBox(width: 18),
            Expanded(flex: 9, child: controls),
          ],
        );
      }
      return ListView(
        children: [
          SizedBox(height: 230, child: preview),
          const SizedBox(height: 16),
          SizedBox(height: 350, child: controls),
        ],
      );
    });
  }

  Widget _buildGifTab(ColorScheme colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final preview = _buildPreview(colors);
        final settings = _buildSettings(colors);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 11, child: preview),
              const SizedBox(width: 18),
              Expanded(flex: 10, child: settings),
            ],
          );
        }
        return ListView(
          children: [
            SizedBox(height: 250, child: preview),
            const SizedBox(height: 16),
            settings,
          ],
        );
      },
    );
  }

  Widget _buildPreview(ColorScheme colors) {
    return _Panel(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_previewPath != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Image.file(
                File(_previewPath!),
                key: ValueKey(_previewPath),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            )
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gif_box_outlined,
                    size: 72, color: colors.onSurface.withValues(alpha: 0.22)),
                const SizedBox(height: 12),
                Text('调整参数后刷新预览',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.55),
                    )),
              ],
            ),
          Positioned(
            left: 12,
            top: 12,
            child: _Badge(
              icon: Icons.play_circle_outline_rounded,
              text: '${_formatTime(_startMillis)} – ${_formatTime(_endMillis)}',
            ),
          ),
          if (_isWorking)
            ColoredBox(
              color: colors.surface.withValues(alpha: 0.74),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppAccentColors.current),
                    const SizedBox(height: 14),
                    Text(_workingLabel ?? '正在处理…'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSettings(ColorScheme colors) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('GIF 导出设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 4),
              Text('独立导出，不会中断当前播放。最长 30 秒。',
                  style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.58),
                      fontSize: 12)),
              const SizedBox(height: 14),
              _sectionLabel('时间范围'),
              Row(
                children: [
                  Expanded(
                    child: _timeField(
                      controller: _startTimeController,
                      label: '开始时间',
                      onChanged: (_) => _handleTimeChanged(start: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _smallAction('填入当前时间', _fillCurrentTime),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _timeField(
                      controller: _endTimeController,
                      label: '结束时间',
                      onChanged: (_) => _handleTimeChanged(start: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _endMillis > _startMillis
                        ? '共 ${((_endMillis - _startMillis) / 1000).toStringAsFixed(1)} 秒'
                        : '时间范围无效',
                    style: TextStyle(
                      color: _endMillis > _startMillis
                          ? colors.onSurface.withValues(alpha: 0.68)
                          : colors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _sectionLabel('输出尺寸'),
              Row(
                children: [
                  Expanded(child: _numberField(_widthController, '宽度')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('×',
                        style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.5))),
                  ),
                  Expanded(child: _numberField(_heightController, '高度')),
                  const SizedBox(width: 8),
                  _smallAction('推荐', () => _setOutputSize(_recommendedSize())),
                  const SizedBox(width: 6),
                  _smallAction('原始', () => _setOutputSize(_sourceSize())),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _sectionLabel('帧率')),
                  Text('$_framesPerSecond fps',
                      style: TextStyle(color: AppAccentColors.current)),
                ],
              ),
              Slider(
                min: 5,
                max: 30,
                divisions: 25,
                value: _framesPerSecond.toDouble(),
                onChanged: _isWorking
                    ? null
                    : (value) =>
                        setState(() => _framesPerSecond = value.round()),
              ),
              _sectionLabel('输出质量'),
              SegmentedButton<GifExportQuality>(
                segments: const [
                  ButtonSegment(
                    value: GifExportQuality.normal,
                    icon: Icon(Icons.bolt_rounded),
                    label: Text('普通'),
                  ),
                  ButtonSegment(
                    value: GifExportQuality.high,
                    icon: Icon(Icons.auto_awesome_rounded),
                    label: Text('高质量'),
                  ),
                ],
                selected: {_quality},
                onSelectionChanged: _isWorking
                    ? null
                    : (value) => setState(() => _quality = value.first),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _actionButton(Icons.refresh_rounded, '刷新预览', _refreshPreview),
                  _actionButton(Icons.copy_rounded, '复制到剪贴板', _copyPreview),
                  _actionButton(Icons.save_alt_rounded, '导出动图文件', _exportFile,
                      primary: true),
                  _actionButton(Icons.close_rounded, '关闭',
                      () async => Navigator.of(context).pop()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      enabled: !_isWorking,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _timeField({
    required TextEditingController controller,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      enabled: !_isWorking,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:.]')),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: '00:00.0',
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _smallAction(String label, VoidCallback action) => TextButton(
        onPressed: _isWorking ? null : action,
        child: Text(label),
      );

  Widget _actionButton(
    IconData icon,
    String label,
    Future<void> Function() action, {
    bool primary = false,
  }) {
    final callback = _isWorking ? null : () => unawaited(action());
    return primary
        ? FilledButton.icon(
            onPressed: callback, icon: Icon(icon), label: Text(label))
        : OutlinedButton.icon(
            onPressed: callback, icon: Icon(icon), label: Text(label));
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.09)),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
