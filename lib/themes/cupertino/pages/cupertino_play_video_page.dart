import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/danmaku_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/brightness_gesture_area.dart';
import 'package:nipaplay/themes/nipaplay/widgets/volume_gesture_area.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_settings_menu.dart';

class CupertinoPlayVideoPage extends StatefulWidget {
  final String? videoPath;

  const CupertinoPlayVideoPage({super.key, this.videoPath});

  @override
  State<CupertinoPlayVideoPage> createState() => _CupertinoPlayVideoPageState();
}

class _CupertinoPlayVideoPageState extends State<CupertinoPlayVideoPage> {
  double? _dragProgress;
  bool _isDragging = false;
  OverlayEntry? _settingsOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final videoState =
          Provider.of<VideoPlayerState>(context, listen: false);
      videoState.setContext(context);
    });
  }

  @override
  void dispose() {
    _settingsOverlay?.remove();
    _settingsOverlay = null;
    super.dispose();
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
                style: const TextStyle(color: CupertinoColors.white, fontSize: 14),
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
        sfSymbol: const SFSymbol('chevron.backward', size: 18, color: CupertinoColors.white),
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

  Widget _buildBottomControls(VideoPlayerState videoState, double progressValue) {
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
                                    milliseconds:
                                        (value * totalMillis).round(),
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
    _settingsOverlay?.remove();
    _settingsOverlay = OverlayEntry(
      builder: (context) => VideoSettingsMenu(
        onClose: () {
          _settingsOverlay?.remove();
          _settingsOverlay = null;
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_settingsOverlay!);
  }
}
