import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'modern_video_controls.dart';
import 'package:provider/provider.dart';

class VideoControlsOverlay extends StatelessWidget {
  static const double compactDesignWidth = 760.0;
  static const double compactDesignHeight = 168.0;

  final bool showFullscreenButton;
  final double uiScale;

  const VideoControlsOverlay({
    super.key,
    this.showFullscreenButton = true,
    this.uiScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        if (!videoState.hasVideo) return const SizedBox.shrink();
        final controls = ModernVideoControls(
          showFullscreenButton: showFullscreenButton,
        );
        final scaledControls = uiScale >= 0.999
            ? controls
            : LayoutBuilder(
                builder: (context, constraints) {
                  final designWidth =
                      constraints.maxWidth / uiScale < compactDesignWidth
                          ? compactDesignWidth
                          : constraints.maxWidth / uiScale;
                  return SizedBox(
                    height: compactDesignHeight * uiScale,
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minWidth: designWidth,
                      maxWidth: designWidth,
                      minHeight: compactDesignHeight,
                      maxHeight: compactDesignHeight,
                      child: Transform.scale(
                        scale: uiScale,
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          width: designWidth,
                          height: compactDesignHeight,
                          child: controls,
                        ),
                      ),
                    ),
                  );
                },
              );
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: videoState.showControls ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !videoState.showControls,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: Offset(0, videoState.showControls ? 0 : 0.1),
                child: scaledControls,
              ),
            ),
          ),
        );
      },
    );
  }
}
