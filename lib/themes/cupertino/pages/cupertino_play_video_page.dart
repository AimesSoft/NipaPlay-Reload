import 'dart:async';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/system_share_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/widgets/context_menu/context_menu.dart';
import 'package:nipaplay/widgets/danmaku_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/brightness_gesture_area.dart';
import 'package:nipaplay/themes/nipaplay/widgets/volume_gesture_area.dart';
import 'package:nipaplay/themes/nipaplay/widgets/danmaku_density_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/minimal_progress_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/playback_info_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_player_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_controls_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/vertical_indicator.dart';
import 'package:nipaplay/themes/nipaplay/widgets/back_button_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_info_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/glass_action_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/send_danmaku_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/skip_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/lock_controls_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_settings_menu.dart';
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
  bool _isHoveringAnimeInfo = false;
  bool _isHoveringBackButton = false;
  double _horizontalDragDistance = 0.0;
  bool _isUiLocked = false;
  bool _showUiLockButton = false;
  Timer? _uiLockButtonTimer;
  final OverlayContextMenuController _contextMenuController =
      OverlayContextMenuController();
  OverlayEntry? _playbackInfoOverlay;
  OverlayEntry? _settingsOverlay;
  final GlobalKey _settingsButtonKey = GlobalKey();

  bool get _useNipaplayControls {
    return PlatformInfo.isAndroid ||
        (PlatformInfo.isIOS && !PlatformInfo.isIOS26OrHigher());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_useNipaplayControls) return;
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.setContext(context);
    });
  }

  @override
  void dispose() {
    _contextMenuController.dispose();
    _hidePlaybackInfoOverlay();
    _settingsOverlay?.remove();
    _settingsOverlay = null;
    _uiLockButtonTimer?.cancel();
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
    if (_useNipaplayControls) {
      return _buildNipaplayBody(videoState);
    }
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
            const MinimalProgressBar(),
            const DanmakuDensityBar(),
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

  Widget _buildNipaplayBody(VideoPlayerState videoState) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        const Positioned.fill(
          child: VideoPlayerWidget(
            emptyPlaceholder: ColoredBox(color: Colors.black),
          ),
        ),
        if (videoState.hasVideo) _buildNipaplayControls(videoState),
      ],
    );
  }

  Widget _buildNipaplayControls(VideoPlayerState videoState) {
    final bool uiLocked = globals.isPhone ? _isUiLocked : false;
    final bool showLockButton = globals.isPhone &&
        (videoState.showControls || (uiLocked && _showUiLockButton));
    final bool showShareButton =
        SystemShareService.isSupported && !globals.isDesktop;
    final bool showScreenshotButton = !kIsWeb && globals.isPhone;

    return Stack(
      children: [
        Consumer<VideoPlayerState>(
          builder: (context, videoState, _) {
            return VerticalIndicator(videoState: videoState);
          },
        ),
        Positioned(
          top: 16.0,
          left: 16.0,
          child: SafeArea(
            bottom: false,
            child: AnimatedOpacity(
              opacity: videoState.showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !videoState.showControls,
                child: Padding(
                  padding: EdgeInsets.only(left: globals.isPhone ? 24.0 : 0.0),
                  child: Row(
                    children: [
                      MouseRegion(
                        cursor: _isHoveringBackButton
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        onEnter: (_) =>
                            setState(() => _isHoveringBackButton = true),
                        onExit: (_) =>
                            setState(() => _isHoveringBackButton = false),
                        child: BackButtonWidget(
                          videoState: videoState,
                          onExit: () async {
                            if (mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      SendDanmakuButton(
                        onPressed: () => _showSendDanmakuDialog(videoState),
                      ),
                      const SizedBox(width: 8.0),
                      SkipButton(
                        onPressed: () => videoState.skip(),
                      ),
                      const SizedBox(width: 12.0),
                      MouseRegion(
                        cursor: _isHoveringAnimeInfo
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        onEnter: (_) =>
                            setState(() => _isHoveringAnimeInfo = true),
                        onExit: (_) =>
                            setState(() => _isHoveringAnimeInfo = false),
                        child: AnimeInfoWidget(videoState: videoState),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16.0,
          right: 16.0,
          child: SafeArea(
            bottom: false,
            child: AnimatedOpacity(
              opacity: videoState.showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !videoState.showControls,
                child: Padding(
                  padding: EdgeInsets.only(right: globals.isPhone ? 24.0 : 0.0),
                  child: MouseRegion(
                    onEnter: (_) => videoState.setControlsHovered(true),
                    onExit: (_) => videoState.setControlsHovered(false),
                    child: Row(
                      children: [
                        if (!kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.iOS)
                          GlassActionButton(
                            tooltip: '投屏 (AirPlay)',
                            icon: Icons.airplay_rounded,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _showAirPlayPickerNipaplay();
                            },
                          ),
                        if (showScreenshotButton) ...[
                          if (!kIsWeb &&
                              defaultTargetPlatform == TargetPlatform.iOS)
                            const SizedBox(width: 12),
                          GlassActionButton(
                            tooltip: '截图',
                            icon: Icons.camera_alt_outlined,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _captureScreenshotNipaplay(videoState);
                            },
                          ),
                        ],
                        if (showShareButton) ...[
                          const SizedBox(width: 12),
                          GlassActionButton(
                            tooltip: (!kIsWeb &&
                                    defaultTargetPlatform ==
                                        TargetPlatform.iOS)
                                ? '分享 / AirDrop'
                                : '分享',
                            icon: (!kIsWeb &&
                                    defaultTargetPlatform ==
                                        TargetPlatform.iOS)
                                ? Icons.ios_share_rounded
                                : Icons.share_rounded,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _shareCurrentMediaNipaplay(videoState);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (globals.isPhone && videoState.isFullscreen)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 60,
            child: GestureDetector(
              onHorizontalDragStart: _handleSideSwipeDragStart,
              onHorizontalDragUpdate: _handleSideSwipeDragUpdate,
              onHorizontalDragEnd: _handleSideSwipeDragEnd,
              behavior: HitTestBehavior.translucent,
              dragStartBehavior: DragStartBehavior.down,
              child: Container(),
            ),
          ),
        const VideoControlsOverlay(showFullscreenButton: false),
        if (uiLocked)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showUiLockButtonTemporarily,
              child: const SizedBox.expand(),
            ),
          ),
        if (globals.isPhone)
          Positioned(
            left: 16.0 + (globals.isPhone ? 24.0 : 0.0),
            top: 0,
            bottom: 0,
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -90),
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 150),
                  offset: Offset(showLockButton ? 0 : -0.1, 0),
                  child: AnimatedOpacity(
                    opacity: showLockButton ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: IgnorePointer(
                      ignoring: !showLockButton,
                      child: LockControlsButton(
                        locked: uiLocked,
                        onPressed: () => _toggleUiLock(videoState),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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

  void _handleSideSwipeDragStart(DragStartDetails details) {
    if (!globals.isPhone) return;
    if (!_isUiLocked) {
      _horizontalDragDistance = 0.0;
    }
  }

  void _handleSideSwipeDragUpdate(DragUpdateDetails details) {
    if (!globals.isPhone) return;
    if (!_isUiLocked) {
      _horizontalDragDistance += details.delta.dx;
    }
  }

  void _handleSideSwipeDragEnd(DragEndDetails details) {
    if (!globals.isPhone || _isUiLocked) {
      _horizontalDragDistance = 0.0;
      return;
    }

    final TabController? tabController =
        context.findAncestorWidgetOfExactType<DefaultTabController>() != null
            ? DefaultTabController.of(context)
            : null;

    if (tabController == null) {
      _horizontalDragDistance = 0.0;
      return;
    }

    TabChangeNotifier? tabChangeNotifier;
    try {
      tabChangeNotifier =
          Provider.of<TabChangeNotifier>(context, listen: false);
    } catch (_) {
      tabChangeNotifier = null;
    }
    if (tabChangeNotifier == null) {
      _horizontalDragDistance = 0.0;
      return;
    }

    final currentIndex = tabController.index;
    final tabCount = tabController.length;
    int newIndex = currentIndex;

    final double dragThreshold = MediaQuery.of(context).size.width / 15;

    if (_horizontalDragDistance < -dragThreshold) {
      if (currentIndex < tabCount - 1) {
        newIndex = currentIndex + 1;
      }
    } else if (_horizontalDragDistance > dragThreshold) {
      if (currentIndex > 0) {
        newIndex = currentIndex - 1;
      }
    }

    if (newIndex != currentIndex) {
      tabChangeNotifier.changeTab(newIndex);
    }
    _horizontalDragDistance = 0.0;
  }

  void _toggleUiLock(VideoPlayerState videoState) {
    if (!globals.isPhone) return;
    final nextLocked = !_isUiLocked;
    _uiLockButtonTimer?.cancel();
    setState(() {
      _isUiLocked = nextLocked;
      _showUiLockButton = nextLocked;
    });
    videoState.setShowControls(!nextLocked);

    if (nextLocked) {
      _showUiLockButtonTemporarily();
    }
  }

  void _showUiLockButtonTemporarily(
      [Duration duration = const Duration(seconds: 3)]) {
    if (!mounted) return;
    if (!globals.isPhone) return;
    if (!_isUiLocked) return;

    _uiLockButtonTimer?.cancel();
    setState(() {
      _showUiLockButton = true;
    });
    _uiLockButtonTimer = Timer(duration, () {
      if (!mounted) return;
      if (!_isUiLocked) return;
      setState(() {
        _showUiLockButton = false;
      });
    });
  }

  Future<void> _shareCurrentMediaNipaplay(
      VideoPlayerState videoState) async {
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
      if (!mounted) return;
      BlurSnackBar.show(context, '没有可分享的内容');
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
      if (!mounted) return;
      BlurSnackBar.show(context, '分享失败: $e');
    }
  }

  Future<void> _captureScreenshotNipaplay(
      VideoPlayerState videoState) async {
    if (kIsWeb) return;
    if (!videoState.hasVideo) return;

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final destination = await BlurDialog.show<String>(
          context: context,
          title: '保存截图',
          content: '请选择保存位置',
          actions: [
            HoverScaleTextButton(
              onPressed: () => Navigator.of(context).pop('photos'),
              child: const Text(
                '相册',
                style: TextStyle(color: Colors.white),
              ),
            ),
            HoverScaleTextButton(
              onPressed: () => Navigator.of(context).pop('file'),
              child: const Text(
                '文件',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );

        if (!mounted) return;
        if (destination == null) return;

        if (destination == 'photos') {
          final ok = await videoState.captureScreenshotToPhotos();
          if (!mounted) return;
          BlurSnackBar.show(context, ok ? '截图已保存到相册' : '截图失败');
          return;
        }
      }

      final path = await videoState.captureScreenshot();
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        BlurSnackBar.show(context, '截图失败');
        return;
      }
      BlurSnackBar.show(context, '截图已保存: $path');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '截图失败: $e');
    }
  }

  Future<void> _showAirPlayPickerNipaplay() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    await BlurDialog.show(
      context: context,
      title: '投屏',
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(height: 8),
          Text(
            '点击下方 AirPlay 图标选择设备',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          Center(child: AirPlayRoutePicker(size: 44)),
          SizedBox(height: 12),
          Text(
            '如未发现设备，请确认与接收端在同一局域网。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _showSendDanmakuDialog(VideoPlayerState videoState) async {
    final hotkeyService = HotkeyService();
    hotkeyService.unregisterHotkeys();
    try {
      await videoState.showSendDanmakuDialog();
    } finally {
      hotkeyService.registerHotkeys();
    }
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
                  if (videoState.hasVideo) ...[
                    _buildSendDanmakuButton(videoState),
                    const SizedBox(width: 8),
                    _buildSkipButton(videoState),
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: _buildTitleButton(context, videoState)),
                  if (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.iOS) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: PlatformInfo.isIOS26OrHigher()
                          ? AdaptiveButton.sfSymbol(
                              onPressed: () =>
                                  _showAirPlayPickerSheet(videoState),
                              sfSymbol: const SFSymbol('airplayvideo',
                                  size: 18, color: CupertinoColors.white),
                              style: AdaptiveButtonStyle.glass,
                              size: AdaptiveButtonSize.large,
                              useSmoothRectangleBorder: false,
                            )
                          : AdaptiveButton.child(
                              onPressed: () =>
                                  _showAirPlayPickerSheet(videoState),
                              style: AdaptiveButtonStyle.glass,
                              size: AdaptiveButtonSize.large,
                              useSmoothRectangleBorder: false,
                              child: const Icon(
                                Icons.airplay_rounded,
                                size: 18,
                                color: CupertinoColors.white,
                              ),
                            ),
                    ),
                  ],
                  if (SystemShareService.isSupported && !globals.isDesktop) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: PlatformInfo.isIOS26OrHigher()
                          ? AdaptiveButton.sfSymbol(
                              onPressed: () {
                                videoState.resetHideControlsTimer();
                                _shareCurrentMedia(videoState);
                              },
                              sfSymbol: const SFSymbol('square.and.arrow.up',
                                  size: 18, color: CupertinoColors.white),
                              style: AdaptiveButtonStyle.glass,
                              size: AdaptiveButtonSize.large,
                              useSmoothRectangleBorder: false,
                            )
                          : AdaptiveButton.child(
                              onPressed: () {
                                videoState.resetHideControlsTimer();
                                _shareCurrentMedia(videoState);
                              },
                              style: AdaptiveButtonStyle.glass,
                              size: AdaptiveButtonSize.large,
                              useSmoothRectangleBorder: false,
                              child: const Icon(
                                CupertinoIcons.share,
                                size: 18,
                                color: CupertinoColors.white,
                              ),
                            ),
                    ),
                  ],
                  if (!kIsWeb && videoState.hasVideo) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: PlatformInfo.isIOS26OrHigher()
                          ? AdaptiveButton.sfSymbol(
                              onPressed: () {
                                videoState.resetHideControlsTimer();
                                _captureScreenshot(videoState);
                              },
                              sfSymbol: const SFSymbol('camera',
                                  size: 18, color: CupertinoColors.white),
                              style: AdaptiveButtonStyle.glass,
                              size: AdaptiveButtonSize.large,
                              useSmoothRectangleBorder: false,
                            )
                          : AdaptiveButton.child(
                              onPressed: () {
                                videoState.resetHideControlsTimer();
                                _captureScreenshot(videoState);
                              },
                              style: AdaptiveButtonStyle.glass,
                              size: AdaptiveButtonSize.large,
                              useSmoothRectangleBorder: false,
                              child: const Icon(
                                CupertinoIcons.camera,
                                size: 18,
                                color: CupertinoColors.white,
                              ),
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

  Widget _buildSendDanmakuButton(VideoPlayerState videoState) {
    final enabled = videoState.episodeId != null;

    return SizedBox(
      width: 44,
      height: 44,
      child: AdaptiveButton.child(
        onPressed: enabled
            ? () {
                videoState.resetHideControlsTimer();
                unawaited(videoState.showSendDanmakuDialog());
              }
            : null,
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        enabled: enabled,
        useSmoothRectangleBorder: false,
        child: const Icon(
          Icons.chat_bubble_outline_rounded,
          size: 20,
          color: CupertinoColors.white,
        ),
      ),
    );
  }

  Widget _buildSkipButton(VideoPlayerState videoState) {
    final enabled = videoState.hasVideo;

    return SizedBox(
      width: 44,
      height: 44,
      child: AdaptiveButton.child(
        onPressed: enabled
            ? () {
                videoState.resetHideControlsTimer();
                videoState.skip();
              }
            : null,
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        enabled: enabled,
        useSmoothRectangleBorder: false,
        child: const Icon(
          Icons.double_arrow_rounded,
          size: 20,
          color: CupertinoColors.white,
        ),
      ),
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
        child: IgnorePointer(
          child: AdaptiveButton(
            onPressed: () {},
            label: title,
            textColor: CupertinoColors.white,
            style: AdaptiveButtonStyle.glass,
            size: AdaptiveButtonSize.large,
            enabled: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            useSmoothRectangleBorder: true,
          ),
        ),
      ),
    );
  }

  AdaptiveButtonSize _resolveControlButtonSize(double extent) {
    return extent >= 44 ? AdaptiveButtonSize.large : AdaptiveButtonSize.medium;
  }

  Widget _buildControlIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool enabled,
    required double size,
    required double iconSize,
  }) {
    final button = SizedBox(
      width: size,
      height: size,
      child: AdaptiveButton.child(
        onPressed: enabled ? onPressed : null,
        style: AdaptiveButtonStyle.plain,
        size: _resolveControlButtonSize(size),
        enabled: enabled,
        useSmoothRectangleBorder: false,
        child: Icon(
          icon,
          size: iconSize,
          color: CupertinoColors.white,
        ),
      ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1.0 : 0.35,
      child: button,
    );
  }

  Widget _buildBottomControls(
      VideoPlayerState videoState, double progressValue) {
    final duration = videoState.duration;
    final position = videoState.position;
    final totalMillis = duration.inMilliseconds;
    final isPhone = globals.isPhone;
    final smallButtonExtent = isPhone ? 36.0 : 32.0;
    final playButtonExtent = isPhone ? 44.0 : 36.0;
    final smallIconSize = isPhone ? 24.0 : 20.0;
    final playIconSize = isPhone ? 30.0 : 24.0;
    final spacing = isPhone ? 4.0 : 6.0;
    final rightSpacing = isPhone ? 10.0 : 12.0;

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
                  AdaptiveSlider(
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildControlIconButton(
                        icon: Icons.skip_previous_rounded,
                        onPressed: () {
                          videoState.resetHideControlsTimer();
                          unawaited(videoState.playPreviousEpisode());
                        },
                        enabled: videoState.canPlayPreviousEpisode,
                        size: smallButtonExtent,
                        iconSize: smallIconSize,
                      ),
                      SizedBox(width: spacing),
                      _buildControlIconButton(
                        icon: Icons.fast_rewind_rounded,
                        onPressed: () {
                          videoState.resetHideControlsTimer();
                          final newPosition = videoState.position -
                              Duration(seconds: videoState.seekStepSeconds);
                          videoState.seekTo(newPosition);
                        },
                        enabled: videoState.hasVideo,
                        size: smallButtonExtent,
                        iconSize: smallIconSize,
                      ),
                      SizedBox(width: spacing),
                      _buildPlayPauseButton(
                        videoState,
                        buttonSize: playButtonExtent,
                        iconSize: playIconSize,
                      ),
                      SizedBox(width: spacing),
                      _buildControlIconButton(
                        icon: Icons.fast_forward_rounded,
                        onPressed: () {
                          videoState.resetHideControlsTimer();
                          final newPosition = videoState.position +
                              Duration(seconds: videoState.seekStepSeconds);
                          videoState.seekTo(newPosition);
                        },
                        enabled: videoState.hasVideo,
                        size: smallButtonExtent,
                        iconSize: smallIconSize,
                      ),
                      SizedBox(width: spacing),
                      _buildControlIconButton(
                        icon: Icons.skip_next_rounded,
                        onPressed: () {
                          videoState.resetHideControlsTimer();
                          unawaited(videoState.playNextEpisode());
                        },
                        enabled: videoState.canPlayNextEpisode,
                        size: smallButtonExtent,
                        iconSize: smallIconSize,
                      ),
                      const Spacer(),
                      Text(
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
                      SizedBox(width: rightSpacing),
                      Builder(
                        builder: (buttonContext) {
                          return SizedBox(
                            key: _settingsButtonKey,
                            width: smallButtonExtent,
                            height: smallButtonExtent,
                            child: PlatformInfo.isIOS26OrHigher()
                                ? AdaptiveButton.sfSymbol(
                                    onPressed: () {
                                      videoState.resetHideControlsTimer();
                                      _showSettingsMenu(buttonContext);
                                    },
                                    sfSymbol: SFSymbol(
                                      'gearshape.fill',
                                      size: smallIconSize,
                                      color: CupertinoColors.white,
                                    ),
                                    style: AdaptiveButtonStyle.plain,
                                    size: _resolveControlButtonSize(
                                      smallButtonExtent,
                                    ),
                                    useSmoothRectangleBorder: false,
                                  )
                                : AdaptiveButton.child(
                                    onPressed: () {
                                      videoState.resetHideControlsTimer();
                                      _showSettingsMenu(buttonContext);
                                    },
                                    style: AdaptiveButtonStyle.plain,
                                    size: _resolveControlButtonSize(
                                      smallButtonExtent,
                                    ),
                                    useSmoothRectangleBorder: false,
                                    child: Icon(
                                      CupertinoIcons.settings,
                                      size: smallIconSize,
                                      color: CupertinoColors.white,
                                    ),
                                  ),
                          );
                        },
                      ),
                      SizedBox(width: spacing),
                      _buildControlIconButton(
                        icon: globals.isTablet
                            ? (videoState.isAppBarHidden
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded)
                            : (videoState.isFullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded),
                        onPressed: () {
                          videoState.resetHideControlsTimer();
                          if (globals.isTablet) {
                            videoState.toggleAppBarVisibility();
                          } else {
                            unawaited(videoState.toggleFullscreen());
                          }
                        },
                        enabled: true,
                        size: smallButtonExtent,
                        iconSize: smallIconSize,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton(
    VideoPlayerState videoState, {
    double? buttonSize,
    double? iconSize,
  }) {
    final isPaused = videoState.isPaused;
    final resolvedButtonSize = buttonSize ?? 40.0;
    final resolvedIconSize = iconSize ?? 22.0;

    void handlePress() {
      videoState.resetHideControlsTimer();
      if (isPaused) {
        videoState.play();
      } else {
        videoState.pause();
      }
    }

    final adaptiveSize = _resolveControlButtonSize(resolvedButtonSize);

    Widget button;
    if (PlatformInfo.isIOS26OrHigher()) {
      button = AdaptiveButton.sfSymbol(
        onPressed: handlePress,
        sfSymbol: SFSymbol(
          isPaused ? 'play.fill' : 'pause.fill',
          size: resolvedIconSize,
          color: CupertinoColors.white,
        ),
        style: AdaptiveButtonStyle.plain,
        size: adaptiveSize,
        useSmoothRectangleBorder: false,
      );
    } else {
      button = AdaptiveButton.child(
        onPressed: handlePress,
        style: AdaptiveButtonStyle.plain,
        size: adaptiveSize,
        useSmoothRectangleBorder: false,
        child: Icon(
          isPaused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
          color: CupertinoColors.white,
          size: resolvedIconSize,
        ),
      );
    }

    return SizedBox(
      width: resolvedButtonSize,
      height: resolvedButtonSize,
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

  void _showSettingsMenu(BuildContext buttonContext) {
    final videoState =
        Provider.of<VideoPlayerState>(buttonContext, listen: false);
    _settingsOverlay?.remove();
    videoState.setControlsVisibilityLocked(true);

    Rect? anchorRect;
    final RenderBox? renderBox =
        buttonContext.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(Offset.zero);
      anchorRect = position & renderBox.size;
    } else {
      final RenderBox? keyRenderBox =
          _settingsButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (keyRenderBox != null && keyRenderBox.hasSize) {
        final position = keyRenderBox.localToGlobal(Offset.zero);
        anchorRect = position & keyRenderBox.size;
      }
    }

    _settingsOverlay = OverlayEntry(
      builder: (context) => VideoSettingsMenu(
        anchorRect: anchorRect,
        anchorKey: _settingsButtonKey,
        onClose: () {
          videoState.setControlsVisibilityLocked(false);
          _settingsOverlay?.remove();
          _settingsOverlay = null;
        },
      ),
    );

    final overlay = Overlay.of(buttonContext);
    if (overlay == null) {
      videoState.setControlsVisibilityLocked(false);
      return;
    }
    overlay.insert(_settingsOverlay!);
  }
}
