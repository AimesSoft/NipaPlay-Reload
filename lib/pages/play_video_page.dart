import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/system_share_service.dart';
import 'package:nipaplay/widgets/airplay_route_picker.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_player_widget.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/nipaplay/widgets/vertical_indicator.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/shortcut_tooltip_manager.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_controls_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/back_button_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_info_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shadow_action_button.dart';
import 'package:nipaplay/app/app_navigation_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:nipaplay/themes/nipaplay/widgets/send_danmaku_button.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/lock_controls_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/skip_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/mobile_playback_status.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_progress_bar.dart';
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';

class PlayVideoPage extends StatefulWidget {
  final String? videoPath;

  const PlayVideoPage({super.key, this.videoPath});

  @override
  State<PlayVideoPage> createState() => _PlayVideoPageState();
}

class _PlayVideoPageState extends State<PlayVideoPage> {
  static const Duration _largeScreenChromeAnimationDuration =
      Duration(milliseconds: 220);
  static const Curve _largeScreenChromeAnimationCurve = Curves.easeOutCubic;
  static const double _largeScreenTopBarHeight = 76;
  static const double _largeScreenBottomControlsHiddenBottom = -220;

  bool _isHoveringAnimeInfo = false;
  bool _isHoveringBackButton = false;
  double _horizontalDragDistance = 0.0;
  bool _isUiLocked = false;
  bool _showUiLockButton = false;
  bool _isLargeScreenProgressDragging = false;
  bool _largeScreenPlayStateChangedByDrag = false;
  Timer? _uiLockButtonTimer;
  bool _isExiting = false;

  bool get _isMacOSHdrVideoOnlyEnabled {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows) &&
        (Platform.environment['NIPAPLAY_MACOS_HDR_VIDEO_ONLY'] == '1' ||
            Platform.environment['NIPAPLAY_WINDOWS_HDR_VIDEO_ONLY'] == '1');
  }

  bool get _isMacOSHdrTransparentFlutterEnabled {
    if (kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return Platform.environment['NIPAPLAY_MACOS_HDR_TRANSPARENT_FLUTTER'] !=
              '0' &&
          Platform.environment['NIPAPLAY_MACOS_HDR_USE_APPKIT_VIEW'] != '1' &&
          Platform.environment['NIPAPLAY_DISABLE_MACOS_WINDOW_OVERLAY'] != '1';
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return Platform.environment['NIPAPLAY_DISABLE_WINDOWS_WINDOW_OVERLAY'] !=
          '1';
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _uiLockButtonTimer?.cancel();
    super.dispose();
  }

  // 处理系统返回键事件
  Future<bool> _handleWillPop() async {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final shouldExit = await videoState.handleBackButton();
    if (shouldExit) {
      setState(() => _isExiting = true);
      unawaited(videoState.resetPlayer().catchError((e) {
        debugPrint('退出重置失败: $e');
      }));
    }
    return shouldExit;
  }

  void _handleSideSwipeDragStart(DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (globals.isPhone && videoState.isFullscreen) {
      _horizontalDragDistance = 0.0;
      //debugPrint("[PlayVideoPage] Side swipe drag start.");
    }
  }

  void _handleSideSwipeDragUpdate(DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (globals.isPhone && videoState.isFullscreen) {
      _horizontalDragDistance += details.delta.dx;
    }
  }

  void _handleSideSwipeDragEnd(DragEndDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!(globals.isPhone && videoState.isFullscreen)) {
      _horizontalDragDistance = 0.0;
      return;
    }

    //debugPrint("[PlayVideoPage] Side swipe drag end.");
    //debugPrint("[PlayVideoPage] Accumulated Drag Distance: $_horizontalDragDistance");
    //debugPrint("[PlayVideoPage] Drag Velocity: ${details.primaryVelocity}");

    final navigation = AppNavigationScope.maybeOf(context);
    if (navigation == null) {
      _horizontalDragDistance = 0.0;
      return;
    }
    final currentIndex = navigation.pageIds.indexOf(navigation.selectedPageId);
    final tabCount = navigation.pageIds.length;
    int newIndex = currentIndex;

    final double dragThreshold = MediaQuery.of(context).size.width / 15;
    //debugPrint("[PlayVideoPage] Drag Threshold: $dragThreshold");

    if (_horizontalDragDistance < -dragThreshold) {
      //debugPrint("[PlayVideoPage] Swipe Left detected (by distance).");
      if (currentIndex < tabCount - 1) {
        newIndex = currentIndex + 1;
      }
    } else if (_horizontalDragDistance > dragThreshold) {
      //debugPrint("[PlayVideoPage] Swipe Right detected (by distance).");
      if (currentIndex > 0) {
        newIndex = currentIndex - 1;
      }
    } else {
      //debugPrint("[PlayVideoPage] Drag distance not enough for side swipe.");
    }

    if (newIndex != currentIndex) {
      navigation.onSelectPage(navigation.pageIds[newIndex]);
    } else {
      //debugPrint("[PlayVideoPage] No tab change needed from side swipe.");
    }
    _horizontalDragDistance = 0.0;
  }

  double getFontSize() {
    if (globals.isPhone) {
      return 20.0;
    } else {
      return 30.0;
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _toggleUiLock(VideoPlayerState videoState) {
    if (!globals.isMobilePlatform) return;
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
    if (!globals.isMobilePlatform) return;
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

  Future<void> _captureScreenshot(VideoPlayerState videoState) async {
    if (kIsWeb) return;
    if (!videoState.hasVideo) return;

    try {
      if (Platform.isIOS) {
        final colorScheme = Theme.of(context).colorScheme;
        final actionColor = colorScheme.onSurface.withOpacity(0.82);
        final cancelColor = colorScheme.onSurface.withOpacity(0.58);
        String? destination;
        switch (videoState.screenshotSaveTarget) {
          case ScreenshotSaveTarget.photos:
            destination = 'photos';
            break;
          case ScreenshotSaveTarget.file:
            destination = 'file';
            break;
          case ScreenshotSaveTarget.ask:
            destination = await BlurDialog.show<String>(
              context: context,
              title: '保存截图',
              content: '请选择保存位置',
              actions: [
                HoverScaleTextButton(
                  onPressed: () => Navigator.of(context).pop('photos'),
                  child: Text(
                    '相册',
                    style: TextStyle(color: actionColor),
                  ),
                ),
                HoverScaleTextButton(
                  onPressed: () => Navigator.of(context).pop('file'),
                  child: Text(
                    '文件',
                    style: TextStyle(color: actionColor),
                  ),
                ),
                HoverScaleTextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    '取消',
                    style: TextStyle(color: cancelColor),
                  ),
                ),
              ],
              barrierDismissible: !_shouldDisableDialogDismiss(videoState),
            );
            break;
        }

        if (!mounted) return;
        if (destination == null) return;

        if (destination == 'photos') {
          final ok = await videoState.captureScreenshotToPhotos();
          if (!mounted) return;
          if (ok) {
            BlurSnackBar.show(context, '截图已保存到相册');
          } else {
            BlurSnackBar.show(context, '截图失败');
          }
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

  bool _shouldDisableDialogDismiss(VideoPlayerState? videoState) {
    if (videoState == null) return false;
    return globals.isTabletLikeMobile && videoState.isAppBarHidden;
  }

  Future<void> _showAirPlayPicker([VideoPlayerState? videoState]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final disableBackgroundDismiss = _shouldDisableDialogDismiss(videoState);

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
      barrierDismissible: !disableBackgroundDismiss,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isMacOSHdrVideoOnlyEnabled) {
      if (_isMacOSHdrTransparentFlutterEnabled) {
        return const VideoPlayerWidget();
      }
      return const ColoredBox(
        color: Colors.black,
        child: VideoPlayerWidget(),
      );
    }

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final usesWindowHostedVideoSurface =
            videoState.player.usesWindowOverlayVideoSurface;
        final isPhonePortrait = globals.isPhone &&
            MediaQuery.orientationOf(context) == Orientation.portrait &&
            videoState.hasVideo;
        return WillPopScope(
          onWillPop: _handleWillPop,
          child: AnimatedContainer(
            duration:
                _isExiting ? Duration.zero : const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            color: videoState.hasVideo &&
                    !isPhonePortrait &&
                    !_isMacOSHdrTransparentFlutterEnabled &&
                    !usesWindowHostedVideoSurface
                ? Colors.black
                : Colors.transparent,
            child: isPhonePortrait
                ? _buildPhonePortraitPlayer(videoState)
                : _buildPlayerStage(videoState),
          ),
        );
      },
    );
  }

  Widget _buildPlayerStage(
    VideoPlayerState videoState, {
    double portraitUiScale = 1.0,
  }) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: VideoPlayerWidget(danmakuScale: portraitUiScale),
        ),
        if (videoState.hasVideo)
          NipaplayLargeScreenModeScope.isActiveOf(context)
              ? _buildLargeScreenMaterialControls(videoState)
              : _buildMaterialControls(
                  videoState,
                  portraitUiScale: portraitUiScale,
                ),
      ],
    );
  }

  Widget _buildPhonePortraitPlayer(VideoPlayerState videoState) {
    final aspectRatio =
        videoState.aspectRatio.isFinite && videoState.aspectRatio > 0
            ? videoState.aspectRatio
            : 16 / 9;
    final animeId = videoState.animeId;

    return SafeArea(
      left: false,
      right: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final requestedVideoHeight = constraints.maxWidth / aspectRatio;
          final maximumVideoHeight = constraints.maxHeight * 0.58;
          final stageHeight = requestedVideoHeight > maximumVideoHeight
              ? maximumVideoHeight
              : requestedVideoHeight;
          final portraitUiScale =
              (constraints.maxWidth / VideoControlsOverlay.compactDesignWidth)
                  .clamp(0.35, 0.72)
                  .toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: stageHeight,
                child: ClipRect(
                  child: ColoredBox(
                    color: Colors.black,
                    child: _buildPlayerStage(
                      videoState,
                      portraitUiScale: portraitUiScale,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: animeId != null && animeId > 0
                    ? AnimeDetailPage(
                        key: ValueKey('portrait-player-detail-$animeId'),
                        animeId: animeId,
                        renderInWindowScaffold: false,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleLargeScreenBack(VideoPlayerState videoState) async {
    try {
      final shouldExit = await videoState.handleBackButton();
      if (!shouldExit) return;
      await videoState.resetPlayer();
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '重置播放器时出错: $e');
    }
  }

  Widget _buildLargeScreenMaterialControls(VideoPlayerState videoState) {
    final bool showShareButton = SystemShareService.isSupported;
    final bool showScreenshotButton = !kIsWeb;
    final bool showAirPlayButton =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final title = (videoState.animeTitle ?? '').trim().isNotEmpty
        ? videoState.animeTitle!.trim()
        : '正在播放';
    final episodeTitle = (videoState.episodeTitle ?? '').trim();
    final bool showChrome = videoState.showControls;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Consumer<VideoPlayerState>(
          builder: (context, videoState, _) {
            return VerticalIndicator(videoState: videoState);
          },
        ),
        AnimatedPositioned(
          duration: _largeScreenChromeAnimationDuration,
          curve: _largeScreenChromeAnimationCurve,
          left: 0,
          right: 0,
          top: showChrome
              ? kNipaplayLargeScreenBottomHintHeight
              : -_largeScreenTopBarHeight,
          child: AnimatedOpacity(
            opacity: showChrome ? 1.0 : 0.0,
            duration: _largeScreenChromeAnimationDuration,
            curve: _largeScreenChromeAnimationCurve,
            child: IgnorePointer(
              ignoring: !showChrome,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    height: 76,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    color: Colors.black.withValues(alpha: 0.34),
                    child: Row(
                      children: [
                        _LargeScreenPlayerBarButton(
                          tooltip: '返回',
                          icon: Ionicons.chevron_back_outline,
                          onPressed: () => _handleLargeScreenBack(videoState),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (episodeTitle.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  episodeTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (videoState.playerTopSendDanmakuButtonVisible)
                          _LargeScreenPlayerBarButton(
                            tooltip: '发送弹幕',
                            icon: Ionicons.chatbubble_ellipses_outline,
                            onPressed: () => _showSendDanmakuDialog(videoState),
                          ),
                        if (videoState.playerTopSkipButtonVisible)
                          _LargeScreenPlayerBarButton(
                            tooltip: '跳过',
                            icon: Ionicons.play_skip_forward_outline,
                            onPressed: videoState.skip,
                          ),
                        if (globals.isDesktop &&
                            videoState.playerTopResizeButtonVisible)
                          _LargeScreenPlayerBarButton(
                            tooltip: ShortcutTooltipManager()
                                .formatActionWithShortcut(
                                    'resize_to_video', '窗口适配视频'),
                            icon: Ionicons.resize_outline,
                            onPressed: videoState.resizeWindowToVideoSize,
                          ),
                        if (videoState.playerTopFrameStepButtonsVisible) ...[
                          _LargeScreenPlayerBarButton(
                            tooltip: '逐帧后退',
                            icon: Ionicons.chevron_back_circle_outline,
                            onPressed: videoState.stepBackward,
                          ),
                          _LargeScreenPlayerBarButton(
                            tooltip: '逐帧前进',
                            icon: Ionicons.chevron_forward_circle_outline,
                            onPressed: videoState.stepForward,
                          ),
                        ],
                        if (showAirPlayButton)
                          _LargeScreenPlayerBarButton(
                            tooltip: '投屏 (AirPlay)',
                            icon: Icons.airplay_rounded,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _showAirPlayPicker(videoState);
                            },
                          ),
                        if (showScreenshotButton)
                          _LargeScreenPlayerBarButton(
                            tooltip: '截图',
                            icon: Icons.camera_alt_outlined,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _captureScreenshot(videoState);
                            },
                          ),
                        if (showShareButton)
                          _LargeScreenPlayerBarButton(
                            tooltip: '分享',
                            icon: Icons.share_rounded,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _shareCurrentMedia(videoState);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildLargeScreenBottomControls(videoState),
      ],
    );
  }

  Widget _buildLargeScreenBottomControls(VideoPlayerState videoState) {
    final bool showChrome = videoState.showControls;
    return AnimatedPositioned(
      duration: _largeScreenChromeAnimationDuration,
      curve: _largeScreenChromeAnimationCurve,
      left: 42,
      right: 42,
      bottom: showChrome
          ? kNipaplayLargeScreenBottomHintHeight + 18
          : _largeScreenBottomControlsHiddenBottom,
      child: AnimatedOpacity(
        opacity: showChrome ? 1.0 : 0.0,
        duration: _largeScreenChromeAnimationDuration,
        curve: _largeScreenChromeAnimationCurve,
        child: IgnorePointer(
          ignoring: !showChrome,
          child: MouseRegion(
            onEnter: (_) => videoState.setControlsHovered(true),
            onExit: (_) => videoState.setControlsHovered(false),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.38),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VideoProgressBar(
                        videoState: videoState,
                        hoverTime: null,
                        isDragging: _isLargeScreenProgressDragging,
                        chapters: videoState.chapterMarkersEnabled
                            ? videoState.chapters
                            : const [],
                        durationMs: videoState.duration.inMilliseconds,
                        currentChapter: videoState.currentChapter,
                        onPositionUpdate: (_) {},
                        onDraggingStateChange: (isDragging) {
                          if (isDragging &&
                              videoState.status == PlayerStatus.paused) {
                            _largeScreenPlayStateChangedByDrag = true;
                            videoState.togglePlayPause();
                          } else if (!isDragging &&
                              _largeScreenPlayStateChangedByDrag) {
                            videoState.togglePlayPause();
                            _largeScreenPlayStateChangedByDrag = false;
                          }
                          setState(() {
                            _isLargeScreenProgressDragging = isDragging;
                          });
                        },
                        formatDuration: _formatDuration,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _LargeScreenPlayerControlButton(
                            tooltip: videoState.canPlayPreviousEpisode
                                ? '上一话'
                                : '无法播放上一话',
                            icon: Icons.skip_previous_rounded,
                            enabled: videoState.canPlayPreviousEpisode,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              unawaited(videoState.playPreviousEpisode());
                            },
                          ),
                          _LargeScreenPlayerControlButton(
                            tooltip: '快退 ${videoState.seekStepDisplayLabel}',
                            icon: Icons.fast_rewind_rounded,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              videoState.seekBackwardByStep();
                            },
                          ),
                          _LargeScreenPlayerControlButton(
                            tooltip: videoState.status == PlayerStatus.playing
                                ? '暂停'
                                : '播放',
                            icon: videoState.status == PlayerStatus.playing
                                ? Ionicons.pause
                                : Ionicons.play,
                            emphasized: true,
                            autofocus: true,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              videoState.togglePlayPause();
                            },
                          ),
                          _LargeScreenPlayerControlButton(
                            tooltip: '快进 ${videoState.seekStepDisplayLabel}',
                            icon: Icons.fast_forward_rounded,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              videoState.seekForwardByStep();
                            },
                          ),
                          _LargeScreenPlayerControlButton(
                            tooltip: videoState.canPlayNextEpisode
                                ? '下一话'
                                : '无法播放下一话',
                            icon: Icons.skip_next_rounded,
                            enabled: videoState.canPlayNextEpisode,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              unawaited(videoState.playNextEpisode());
                            },
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Text(
                              '${_formatDuration(videoState.position)} / ${_formatDuration(videoState.duration)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _LargeScreenPlayerControlButton(
                            tooltip:
                                videoState.danmakuVisible ? '隐藏弹幕' : '显示弹幕',
                            icon: videoState.danmakuVisible
                                ? Icons.chat_bubble_outline_rounded
                                : Icons.speaker_notes_off_outlined,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              videoState.toggleDanmakuVisible();
                            },
                          ),
                          _LargeScreenPlayerControlButton(
                            tooltip: globals.isTablet
                                ? (videoState.isAppBarHidden
                                    ? '显示菜单栏'
                                    : '隐藏菜单栏')
                                : (videoState.isFullscreen ? '退出全屏' : '全屏'),
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
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialControls(
    VideoPlayerState videoState, {
    double portraitUiScale = 1.0,
  }) {
    final bool uiLocked = globals.isMobilePlatform ? _isUiLocked : false;
    final bool showLockButton = globals.isMobilePlatform &&
        (videoState.showControls || (uiLocked && _showUiLockButton));
    final bool showShareButton =
        SystemShareService.isSupported && !globals.isDesktop;
    final bool showScreenshotButton = !kIsWeb && globals.isMobilePlatform;
    final bool showAirPlayButton =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final double horizontalCutoutInset =
        globals.isPhone && portraitUiScale >= 0.999 ? 24.0 : 0.0;

    final int rightButtonCount = (showAirPlayButton ? 1 : 0) +
        (showScreenshotButton ? 1 : 0) +
        (showShareButton ? 1 : 0);
    final double rightButtonsWidth = rightButtonCount > 0
        ? rightButtonCount * 42.0 + (rightButtonCount - 1) * 12.0
        : 0.0;
    final double availableTitleWidth = (MediaQuery.of(context).size.width -
            (16.0 + horizontalCutoutInset) -
            116.0 -
            (16.0 + horizontalCutoutInset) -
            rightButtonsWidth -
            (globals.isMobilePlatform ? 86.0 : 0.0) -
            24.0)
        .clamp(80.0, 600.0)
        .toDouble();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Consumer<VideoPlayerState>(
          builder: (context, videoState, _) {
            return VerticalIndicator(videoState: videoState);
          },
        ),
        Positioned(
          top: 10.0,
          left: 16.0,
          child: AnimatedOpacity(
            opacity: videoState.showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: !videoState.showControls,
              child: Transform.scale(
                scale: portraitUiScale,
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: horizontalCutoutInset,
                    top: 6.0,
                    bottom: 12.0,
                  ),
                  child: MouseRegion(
                    onEnter: (_) => videoState.setControlsHovered(true),
                    onExit: (_) => videoState.setControlsHovered(false),
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
                          child: BackButtonWidget(videoState: videoState),
                        ),
                        const SizedBox(width: 12.0),
                        if (videoState.playerTopSendDanmakuButtonVisible) ...[
                          SendDanmakuButton(
                            onPressed: () => _showSendDanmakuDialog(videoState),
                          ),
                          const SizedBox(width: 8.0),
                        ],
                        if (videoState.playerTopSkipButtonVisible) ...[
                          SkipButton(
                            onPressed: () => videoState.skip(),
                          ),
                          const SizedBox(width: 8.0),
                        ],
                        if (globals.isDesktop &&
                            videoState.playerTopResizeButtonVisible) ...[
                          ShadowActionButton(
                            tooltip: ShortcutTooltipManager()
                                .formatActionWithShortcut(
                                    'resize_to_video', '窗口适配视频'),
                            icon: Ionicons.resize_outline,
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            onPressed: () =>
                                videoState.resizeWindowToVideoSize(),
                          ),
                          const SizedBox(width: 8.0),
                        ],
                        if (globals.isDesktop &&
                            videoState.playerTopFrameStepButtonsVisible) ...[
                          ShadowActionButton(
                            tooltip: ShortcutTooltipManager()
                                .formatActionWithShortcut(
                                    'step_backward', '逐帧后退'),
                            icon: Ionicons.chevron_back_circle_outline,
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            onPressed: () => videoState.stepBackward(),
                          ),
                          const SizedBox(width: 8.0),
                          ShadowActionButton(
                            tooltip: ShortcutTooltipManager()
                                .formatActionWithShortcut(
                                    'step_forward', '逐帧前进'),
                            icon: Ionicons.chevron_forward_circle_outline,
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            onPressed: () => videoState.stepForward(),
                          ),
                          const SizedBox(width: 8.0),
                        ],
                        if (!globals.isDesktop &&
                            videoState.playerTopFrameStepButtonsVisible) ...[
                          ShadowActionButton(
                            tooltip: '逐帧后退',
                            icon: Ionicons.chevron_back_circle_outline,
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            onPressed: () => videoState.stepBackward(),
                          ),
                          const SizedBox(width: 8.0),
                          ShadowActionButton(
                            tooltip: '逐帧前进',
                            icon: Ionicons.chevron_forward_circle_outline,
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            onPressed: () => videoState.stepForward(),
                          ),
                          const SizedBox(width: 8.0),
                        ],
                        const SizedBox(width: 4.0),
                        MouseRegion(
                          cursor: _isHoveringAnimeInfo
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.basic,
                          onEnter: (_) =>
                              setState(() => _isHoveringAnimeInfo = true),
                          onExit: (_) =>
                              setState(() => _isHoveringAnimeInfo = false),
                          child: AnimeInfoWidget(
                            videoState: videoState,
                            maxWidth: availableTitleWidth,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 10.0,
          right: 16.0,
          child: AnimatedOpacity(
            opacity: videoState.showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: !videoState.showControls,
              child: Transform.scale(
                scale: portraitUiScale,
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: horizontalCutoutInset,
                    top: 6.0,
                    bottom: 12.0,
                  ),
                  child: MouseRegion(
                    onEnter: (_) => videoState.setControlsHovered(true),
                    onExit: (_) => videoState.setControlsHovered(false),
                    child: Row(
                      children: [
                        if (showAirPlayButton)
                          ShadowActionButton(
                            tooltip: '投屏 (AirPlay)',
                            icon: Icons.airplay_rounded,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _showAirPlayPicker(videoState);
                            },
                          ),
                        if (showScreenshotButton) ...[
                          if (!kIsWeb &&
                              defaultTargetPlatform == TargetPlatform.iOS)
                            const SizedBox(width: 12),
                          ShadowActionButton(
                            tooltip: '截图',
                            icon: Icons.camera_alt_outlined,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _captureScreenshot(videoState);
                            },
                          ),
                        ],
                        if (showShareButton) ...[
                          const SizedBox(width: 12),
                          ShadowActionButton(
                            tooltip: (!kIsWeb &&
                                    defaultTargetPlatform == TargetPlatform.iOS)
                                ? '分享 / AirDrop'
                                : '分享',
                            icon: (!kIsWeb &&
                                    defaultTargetPlatform == TargetPlatform.iOS)
                                ? Icons.ios_share_rounded
                                : Icons.share_rounded,
                            onPressed: () {
                              videoState.resetHideControlsTimer();
                              _shareCurrentMedia(videoState);
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
        if (globals.isMobilePlatform &&
            (!globals.isTablet || videoState.isFullscreen))
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: AnimatedOpacity(
                opacity: videoState.showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !videoState.showControls,
                  child: Transform.scale(
                    scale: portraitUiScale,
                    alignment: Alignment.topRight,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: MobilePlaybackStatus(compact: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (globals.isMobilePlatform && videoState.isFullscreen)
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
        VideoControlsOverlay(uiScale: portraitUiScale),
        if (uiLocked)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showUiLockButtonTemporarily,
              child: const SizedBox.expand(),
            ),
          ),
        if (globals.isMobilePlatform)
          Positioned(
            left: 16.0 + horizontalCutoutInset,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: Offset(showLockButton ? 0 : -0.1, 0),
                child: AnimatedOpacity(
                  opacity: showLockButton ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: !showLockButton,
                    child: Transform.scale(
                      scale: portraitUiScale,
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

  Future<void> _showSendDanmakuDialog(VideoPlayerState videoState) async {
    final hotkeyService = HotkeyService();
    hotkeyService.unregisterHotkeys();
    try {
      await videoState.showSendDanmakuDialog();
    } finally {
      hotkeyService.registerHotkeys();
    }
  }
}

class _LargeScreenPlayerBarButton extends StatelessWidget {
  const _LargeScreenPlayerBarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: ShadowActionButton(
            tooltip: tooltip,
            icon: icon,
            iconSize: 26,
            padding: EdgeInsets.zero,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _LargeScreenPlayerControlButton extends StatelessWidget {
  const _LargeScreenPlayerControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.emphasized = false,
    this.autofocus = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool emphasized;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final double size = emphasized ? 56 : 46;
    final Color foreground =
        enabled ? Colors.white : Colors.white.withValues(alpha: 0.36);
    final Color fillColor = emphasized
        ? AppAccentColors.current.withValues(alpha: enabled ? 0.94 : 0.22)
        : Colors.white.withValues(alpha: enabled ? 0.10 : 0.045);

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: SizedBox(
          width: size,
          height: size,
          child: NipaplayLargeScreenFocusableAction(
            autofocus: autofocus,
            onActivate: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(8),
            focusScale: emphasized ? 1.055 : 1.07,
            style: NipaplayLargeScreenFocusableStyle(
              idleBackgroundDark: fillColor,
              idleBackgroundLight: fillColor,
              contentColorDark: foreground,
              contentColorLight: foreground,
              focusStrokeColor: Colors.white,
              focusStrokeWidth: emphasized ? 3 : 2,
            ),
            child: Center(
              child: Icon(
                icon,
                color: foreground,
                size: emphasized ? 34 : 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
