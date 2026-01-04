import 'dart:async';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/system_share_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/context_menu/context_menu.dart';
import 'package:nipaplay/widgets/danmaku_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/brightness_gesture_area.dart';
import 'package:nipaplay/themes/nipaplay/widgets/volume_gesture_area.dart';
import 'package:nipaplay/themes/nipaplay/widgets/playback_info_menu.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_player_menu.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/widgets/airplay_route_picker.dart';

class CupertinoPlayVideoPage extends StatefulWidget {
  final String? videoPath;

  const CupertinoPlayVideoPage({super.key, this.videoPath});

  @override
  State<CupertinoPlayVideoPage> createState() => _CupertinoPlayVideoPageState();
}

class _CupertinoPlayVideoPageState extends State<CupertinoPlayVideoPage> {
  double? _dragProgress;
  bool _isDragging = false;
  final OverlayContextMenuController _contextMenuController =
      OverlayContextMenuController();
  OverlayEntry? _playbackInfoOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.setContext(context);
    });
  }

  @override
  void dispose() {
    _contextMenuController.dispose();
    _hidePlaybackInfoOverlay();
    super.dispose();
  }

  Future<void> _showMessage(String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareCurrentMedia(VideoPlayerState videoState) async {
    if (!SystemShareService.isSupported) return;

    final currentVideoPath = videoState.currentVideoPath;
    final currentActualUrl = videoState.currentActualPlayUrl;

    String? filePath;
    String? url;

    if (currentVideoPath != null && currentVideoPath.isNotEmpty) {
      final uri = Uri.tryParse(currentVideoPath);
      final scheme = uri?.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        url = currentVideoPath;
      } else if (scheme == 'jellyfin' || scheme == 'emby') {
        url = currentActualUrl;
      } else if (scheme == 'smb' || scheme == 'webdav' || scheme == 'dav') {
        url = currentVideoPath;
      } else {
        filePath = currentVideoPath;
      }
    } else {
      url = currentActualUrl;
    }

    final titleParts = <String>[
      if ((videoState.animeTitle ?? '').trim().isNotEmpty)
        videoState.animeTitle!.trim(),
      if ((videoState.episodeTitle ?? '').trim().isNotEmpty)
        videoState.episodeTitle!.trim(),
    ];
    final subject = titleParts.isEmpty ? null : titleParts.join(' · ');

    if ((filePath == null || filePath.isEmpty) &&
        (url == null || url.isEmpty)) {
      await _showMessage('没有可分享的内容');
      return;
    }

    try {
      await SystemShareService.share(
        text: subject,
        url: url,
        filePath: filePath,
        subject: subject,
      );
    } catch (e) {
      await _showMessage('分享失败: $e');
    }
  }

  void _showPlaybackInfoOverlay() {
    if (_playbackInfoOverlay != null) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _playbackInfoOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hidePlaybackInfoOverlay,
              onSecondaryTap: _hidePlaybackInfoOverlay,
            ),
          ),
          PlaybackInfoMenu(onClose: _hidePlaybackInfoOverlay),
        ],
      ),
    );

    overlay.insert(_playbackInfoOverlay!);
  }

  void _hidePlaybackInfoOverlay() {
    _playbackInfoOverlay?.remove();
    _playbackInfoOverlay = null;
  }

  Future<void> _captureScreenshot(VideoPlayerState videoState) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final destination = await showCupertinoModalPopup<String>(
          context: context,
          builder: (ctx) => CupertinoActionSheet(
            title: const Text('保存截图'),
            message: const Text('请选择保存位置'),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(ctx).pop('photos'),
                child: const Text('相册'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(ctx).pop('file'),
                child: const Text('文件'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
          ),
        );

        if (!mounted) return;
        if (destination == null) return;

        if (destination == 'photos') {
          final ok = await videoState.captureScreenshotToPhotos();
          if (!mounted) return;
          AdaptiveSnackBar.show(
            context,
            message: ok ? '截图已保存到相册' : '截图失败',
            type: ok
                ? AdaptiveSnackBarType.success
                : AdaptiveSnackBarType.error,
          );
          return;
        }
      }

      final path = await videoState.captureScreenshot();
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        AdaptiveSnackBar.show(
          context,
          message: '截图失败',
          type: AdaptiveSnackBarType.error,
        );
        return;
      }
      AdaptiveSnackBar.show(
        context,
        message: '截图已保存: $path',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '截图失败: $e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _closePlayback(VideoPlayerState videoState) async {
    final shouldPop = await _requestExit(videoState);
    if (shouldPop && mounted) {
      Navigator.of(context).pop();
    }
  }

  List<ContextMenuAction> _buildContextMenuActions(VideoPlayerState videoState) {
    final actions = <ContextMenuAction>[
      ContextMenuAction(
        icon: Icons.skip_previous_rounded,
        label: '上一话',
        enabled: videoState.canPlayPreviousEpisode,
        onPressed: () => unawaited(videoState.playPreviousEpisode()),
      ),
      ContextMenuAction(
        icon: Icons.skip_next_rounded,
        label: '下一话',
        enabled: videoState.canPlayNextEpisode,
        onPressed: () => unawaited(videoState.playNextEpisode()),
      ),
      ContextMenuAction(
        icon: Icons.fast_forward_rounded,
        label: '快进 ${videoState.seekStepSeconds} 秒',
        enabled: videoState.hasVideo,
        onPressed: () {
          final newPosition = videoState.position +
              Duration(seconds: videoState.seekStepSeconds);
          videoState.seekTo(newPosition);
        },
      ),
      ContextMenuAction(
        icon: Icons.fast_rewind_rounded,
        label: '快退 ${videoState.seekStepSeconds} 秒',
        enabled: videoState.hasVideo,
        onPressed: () {
          final newPosition = videoState.position -
              Duration(seconds: videoState.seekStepSeconds);
          videoState.seekTo(newPosition);
        },
      ),
      ContextMenuAction(
        icon: Icons.chat_bubble_outline_rounded,
        label: '发送弹幕',
        enabled: videoState.episodeId != null,
        onPressed: () => unawaited(videoState.showSendDanmakuDialog()),
      ),
      ContextMenuAction(
        icon: Icons.camera_alt_outlined,
        label: '截图',
        enabled: videoState.hasVideo,
        onPressed: () => unawaited(_captureScreenshot(videoState)),
      ),
      ContextMenuAction(
        icon: Icons.double_arrow_rounded,
        label: '跳过',
        enabled: videoState.hasVideo,
        onPressed: videoState.skip,
      ),
      ContextMenuAction(
        icon: videoState.isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        label: videoState.isFullscreen ? '窗口化' : '全屏',
        enabled: globals.isDesktop,
        onPressed: () => unawaited(videoState.toggleFullscreen()),
      ),
      ContextMenuAction(
        icon: Icons.close_rounded,
        label: '关闭播放',
        enabled: videoState.hasVideo,
        onPressed: () => unawaited(_closePlayback(videoState)),
      ),
      ContextMenuAction(
        icon: Icons.info_outline_rounded,
        label: '播放信息',
        enabled: videoState.hasVideo,
        onPressed: _showPlaybackInfoOverlay,
      ),
    ];

    if (SystemShareService.isSupported) {
      actions.add(
        ContextMenuAction(
          icon: Icons.share_rounded,
          label: '分享',
          enabled: videoState.hasVideo,
          onPressed: () => unawaited(_shareCurrentMedia(videoState)),
        ),
      );
    }

    return actions;
  }

  Future<void> _showAirPlayPickerSheet(VideoPlayerState videoState) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    videoState.resetHideControlsTimer();
    await CupertinoBottomSheet.show(
      context: context,
      title: '投屏 (AirPlay)',
      heightRatio: 0.5,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                '点击下方 AirPlay 图标选择设备',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              AirPlayRoutePicker(size: 56),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        return WillPopScope(
          onWillPop: () => _handleSystemBack(videoState),
          child: CupertinoPageScaffold(
            backgroundColor: CupertinoColors.black,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: SafeArea(
                top: false,
                bottom: false,
                child: _buildBody(videoState),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(VideoPlayerState videoState) {
    final textureId = videoState.player.textureId.value;
    final hasVideo = videoState.hasVideo && textureId != null && textureId >= 0;
    final progressValue = _isDragging
        ? (_dragProgress ?? videoState.progress)
        : videoState.progress;

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: () {
        if (!videoState.showControls) {
          videoState.setShowControls(true);
          videoState.resetHideControlsTimer();
        } else {
          videoState.toggleControls();
        }
      },
      onSecondaryTapDown: globals.isDesktop
          ? (details) {
              if (!videoState.hasVideo) return;
              _hidePlaybackInfoOverlay();

              _contextMenuController.showActionsMenu(
                context: context,
                globalPosition: details.globalPosition,
                style: ContextMenuStyles.solidDark(),
                actions: _buildContextMenuActions(videoState),
              );
            }
          : null,
      onDoubleTap: () {
        if (videoState.hasVideo) {
          videoState.togglePlayPause();
        }
      },
      onTapDown: (_) {
        if (videoState.showControls) {
          videoState.resetHideControlsTimer();
        }
      },
      onHorizontalDragStart: globals.isPhone && videoState.hasVideo
          ? (_) {
              videoState.startSeekDrag(context);
            }
          : null,
      onHorizontalDragUpdate: globals.isPhone && videoState.hasVideo
          ? (details) {
              videoState.updateSeekDrag(details.delta.dx, context);
            }
          : null,
      onHorizontalDragEnd: globals.isPhone && videoState.hasVideo
          ? (_) {
              videoState.endSeekDrag();
            }
          : null,
      child: RepaintBoundary(
        key: videoState.screenshotBoundaryKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Container(
                color: CupertinoColors.black,
                child: hasVideo
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: videoState.aspectRatio,
                          child: Texture(
                            textureId: textureId,
                          ),
                        ),
                      )
                    : _buildPlaceholder(videoState),
              ),
            ),
            if (videoState.hasVideo && videoState.danmakuVisible)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: ValueListenableBuilder<double>(
                    valueListenable: videoState.playbackTimeMs,
                    builder: (context, posMs, __) {
                      return DanmakuOverlay(
                        key: ValueKey('danmaku_${videoState.danmakuOverlayKey}'),
                        currentPosition: posMs,
                        videoDuration:
                            videoState.duration.inMilliseconds.toDouble(),
                        isPlaying: videoState.status == PlayerStatus.playing,
                        fontSize: videoState.actualDanmakuFontSize,
                        isVisible: videoState.danmakuVisible,
                        opacity: videoState.mappedDanmakuOpacity,
                      );
                    },
                  ),
                ),
              ),
            _buildTopBar(videoState),
            if (hasVideo) _buildBottomControls(videoState, progressValue),
            if (globals.isPhone && videoState.hasVideo)
              const BrightnessGestureArea(),
            if (globals.isPhone && videoState.hasVideo)
              const VolumeGestureArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(VideoPlayerState videoState) {
    final messages = videoState.statusMessages;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CupertinoActivityIndicator(radius: 14),
          if (messages.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                messages.last,
                style:
                    const TextStyle(color: CupertinoColors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar(VideoPlayerState videoState) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: videoState.showControls ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !videoState.showControls,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  _buildBackButton(videoState),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTitleButton(context, videoState)),
                  if (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.iOS) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: AdaptiveButton.sfSymbol(
                        onPressed: () => _showAirPlayPickerSheet(videoState),
                        sfSymbol: const SFSymbol('airplayvideo',
                            size: 18, color: CupertinoColors.white),
                        style: AdaptiveButtonStyle.glass,
                        size: AdaptiveButtonSize.large,
                        useSmoothRectangleBorder: false,
                      ),
                    ),
                  ],
                  if (SystemShareService.isSupported && !globals.isDesktop) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: AdaptiveButton.sfSymbol(
                        onPressed: () {
                          videoState.resetHideControlsTimer();
                          _shareCurrentMedia(videoState);
                        },
                        sfSymbol: const SFSymbol('square.and.arrow.up',
                            size: 18, color: CupertinoColors.white),
                        style: AdaptiveButtonStyle.glass,
                        size: AdaptiveButtonSize.large,
                        useSmoothRectangleBorder: false,
                      ),
                    ),
                  ],
                  if (!kIsWeb && videoState.hasVideo) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: AdaptiveButton.sfSymbol(
                        onPressed: () {
                          videoState.resetHideControlsTimer();
                          _captureScreenshot(videoState);
                        },
                        sfSymbol: const SFSymbol('camera',
                            size: 18, color: CupertinoColors.white),
                        style: AdaptiveButtonStyle.glass,
                        size: AdaptiveButtonSize.large,
                        useSmoothRectangleBorder: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton(VideoPlayerState videoState) {
    Future<void> handlePress() async {
      final shouldPop = await _requestExit(videoState);
      if (shouldPop && mounted) {
        Navigator.of(context).pop();
      }
    }

    Widget button;
    if (PlatformInfo.isIOS26OrHigher()) {
      button = AdaptiveButton.sfSymbol(
        onPressed: handlePress,
        sfSymbol: const SFSymbol('chevron.backward',
            size: 18, color: CupertinoColors.white),
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        useSmoothRectangleBorder: false,
      );
    } else {
      button = AdaptiveButton.child(
        onPressed: handlePress,
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        useSmoothRectangleBorder: false,
        child: const Icon(
          CupertinoIcons.back,
          color: CupertinoColors.white,
          size: 22,
        ),
      );
    }

    return SizedBox(
      width: 44,
      height: 44,
      child: button,
    );
  }

  Widget _buildTitleButton(BuildContext context, VideoPlayerState videoState) {
    final title = _composeTitle(videoState);
    if (title.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxWidth = MediaQuery.of(context).size.width * 0.5;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AdaptiveButton(
          onPressed: null,
          label: title,
          style: AdaptiveButtonStyle.glass,
          size: AdaptiveButtonSize.large,
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          useSmoothRectangleBorder: true,
        ),
      ),
    );
  }

  Widget _buildBottomControls(
      VideoPlayerState videoState, double progressValue) {
    final duration = videoState.duration;
    final position = videoState.position;
    final totalMillis = duration.inMilliseconds;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: videoState.showControls ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !videoState.showControls,
            child: Padding(
              padding: EdgeInsets.only(
                left: globals.isPhone ? 16 : 24,
                right: globals.isPhone ? 16 : 24,
                bottom: globals.isPhone ? 16 : 24,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _buildPlayPauseButton(videoState),
                      const SizedBox(width: 16),
                      Expanded(
                        child: AdaptiveSlider(
                          value: totalMillis > 0
                              ? progressValue.clamp(0.0, 1.0)
                              : 0.0,
                          min: 0.0,
                          max: 1.0,
                          activeColor: CupertinoColors.activeBlue,
                          onChangeStart: totalMillis > 0
                              ? (_) {
                                  videoState.resetHideControlsTimer();
                                  setState(() {
                                    _isDragging = true;
                                  });
                                }
                              : null,
                          onChanged: totalMillis > 0
                              ? (value) {
                                  setState(() {
                                    _dragProgress = value;
                                  });
                                }
                              : null,
                          onChangeEnd: totalMillis > 0
                              ? (value) {
                                  final target = Duration(
                                    milliseconds: (value * totalMillis).round(),
                                  );
                                  videoState.seekTo(target);
                                  videoState.resetHideControlsTimer();
                                  setState(() {
                                    _isDragging = false;
                                    _dragProgress = null;
                                  });
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: kMinInteractiveDimensionCupertino,
                        height: kMinInteractiveDimensionCupertino,
                        child: AdaptiveButton.sfSymbol(
                          onPressed: () {
                            videoState.resetHideControlsTimer();
                            _showSettingsMenu(context);
                          },
                          sfSymbol: const SFSymbol('gearshape.fill'),
                          style: AdaptiveButtonStyle.glass,
                          size: AdaptiveButtonSize.large,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(
                            color: Color.fromARGB(140, 0, 0, 0),
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton(VideoPlayerState videoState) {
    final isPaused = videoState.isPaused;

    void handlePress() {
      if (isPaused) {
        videoState.play();
      } else {
        videoState.pause();
      }
    }

    Widget button;
    if (PlatformInfo.isIOS26OrHigher()) {
      button = AdaptiveButton.sfSymbol(
        onPressed: handlePress,
        sfSymbol: SFSymbol(
          isPaused ? 'play.fill' : 'pause.fill',
          size: 20,
          color: CupertinoColors.white,
        ),
        style: AdaptiveButtonStyle.plain,
        size: AdaptiveButtonSize.medium,
        useSmoothRectangleBorder: false,
      );
    } else {
      button = AdaptiveButton.child(
        onPressed: handlePress,
        style: AdaptiveButtonStyle.plain,
        size: AdaptiveButtonSize.medium,
        useSmoothRectangleBorder: false,
        child: Icon(
          isPaused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
          color: CupertinoColors.white,
          size: 22,
        ),
      );
    }

    return SizedBox(
      width: 40,
      height: 40,
      child: button,
    );
  }

  Future<bool> _handleSystemBack(VideoPlayerState videoState) async {
    final shouldPop = await _requestExit(videoState);
    return shouldPop;
  }

  Future<bool> _requestExit(VideoPlayerState videoState) async {
    final shouldPop = await videoState.handleBackButton();
    if (shouldPop) {
      await videoState.resetPlayer();
    }
    return shouldPop;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      final hourStr = hours.toString().padLeft(2, '0');
      return '$hourStr:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _composeTitle(VideoPlayerState videoState) {
    final title = videoState.animeTitle;
    final episode = videoState.episodeTitle;
    if (title == null && episode == null) {
      return '';
    }
    if (title != null && episode != null) {
      return '$title · $episode';
    }
    return title ?? episode ?? '';
  }

  void _showSettingsMenu(BuildContext context) {
    CupertinoBottomSheet.show(
      context: context,
      title: '播放设置',
      floatingTitle: true,
      heightRatio: 0.92,
      child: const CupertinoPlayerMenu(),
    );
  }
}
