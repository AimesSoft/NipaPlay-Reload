import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class CupertinoPlayVideoPage extends StatefulWidget {
  final String? videoPath;

  const CupertinoPlayVideoPage({super.key, this.videoPath});

  @override
  State<CupertinoPlayVideoPage> createState() => _CupertinoPlayVideoPageState();
}

class _CupertinoPlayVideoPageState extends State<CupertinoPlayVideoPage> {
  double? _dragProgress;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        return WillPopScope(
          onWillPop: () => _handleSystemBack(videoState),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: AdaptiveScaffold(
              appBar: videoState.showControls
                  ? AdaptiveAppBar(
                      title: _composeTitle(videoState).isNotEmpty
                          ? _composeTitle(videoState)
                          : null,
                      leading: _buildAppBarLeading(videoState),
                      useNativeToolbar: true,
                    )
                  : null,
              body: SafeArea(
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
      behavior: HitTestBehavior.opaque,
      onTap: () {
        videoState.toggleControls();
      },
      onPanDown: (_) => videoState.resetHideControlsTimer(),
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
          if (hasVideo) _buildBottomControls(videoState, progressValue),
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

  Widget _buildAppBarLeading(VideoPlayerState videoState) {
    Future<void> handlePress() async {
      final shouldPop = await _requestExit(videoState);
      if (shouldPop && mounted) {
        Navigator.of(context).pop();
      }
    }

    if (PlatformInfo.isIOS26OrHigher()) {
      return AdaptiveButton.sfSymbol(
        onPressed: handlePress,
        sfSymbol: const SFSymbol('chevron.backward', size: 18, color: CupertinoColors.white),
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        useSmoothRectangleBorder: false,
      );
    }

    return AdaptiveButton.child(
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

  Widget _buildBottomControls(VideoPlayerState videoState, double progressValue) {
    final duration = videoState.videoDuration;
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
                                  setState(() {
                                    _isDragging = false;
                                    _dragProgress = null;
                                  });
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(position),
                        style: const TextStyle(
                          color: CupertinoColors.systemGrey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: const TextStyle(
                          color: CupertinoColors.systemGrey,
                          fontSize: 12,
                        ),
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

  Widget _buildPlayPauseButton(VideoPlayerState videoState) {
    final isPaused = videoState.isPaused;

    void handlePress() {
      if (isPaused) {
        videoState.play();
      } else {
        videoState.pause();
      }
    }

    if (PlatformInfo.isIOS26OrHigher()) {
      return AdaptiveButton.sfSymbol(
        onPressed: handlePress,
        sfSymbol: SFSymbol(
          isPaused ? 'play.fill' : 'pause.fill',
          size: 20,
          color: CupertinoColors.white,
        ),
        style: AdaptiveButtonStyle.filled,
        size: AdaptiveButtonSize.large,
        useSmoothRectangleBorder: true,
      );
    }

    return AdaptiveButton.child(
      onPressed: handlePress,
      style: AdaptiveButtonStyle.filled,
      size: AdaptiveButtonSize.large,
      useSmoothRectangleBorder: true,
      child: Icon(
        isPaused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
        color: CupertinoColors.white,
        size: 22,
      ),
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
}
