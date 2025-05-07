import 'package:flutter/material.dart';
import '../utils/video_player_state.dart';
import 'modern_video_controls.dart';
import 'package:provider/provider.dart';

class VideoControlsOverlay extends StatelessWidget {
  const VideoControlsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        if (!videoState.hasVideo) return const SizedBox.shrink();
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
                child: const ModernVideoControls(),
              ),
            ),
          ),
        );
      },
    );
  }
} 