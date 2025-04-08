import 'package:flutter/material.dart';
import '../utils/video_player_state.dart';
import 'modern_video_controls.dart';
import 'package:provider/provider.dart';

class VideoControlsOverlay extends StatefulWidget {
  const VideoControlsOverlay({super.key});

  @override
  State<VideoControlsOverlay> createState() => _VideoControlsOverlayState();
}

class _VideoControlsOverlayState extends State<VideoControlsOverlay> {
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showOverlay();
    });
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  void _showOverlay() {
    _overlayEntry = OverlayEntry(
      builder: (context) => Consumer<VideoPlayerState>(
        builder: (context, videoState, child) {
          if (!videoState.hasVideo) return const SizedBox.shrink();

          return Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: videoState.showControls ? 1.0 : 0.0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: Offset(0, videoState.showControls ? 0 : 0.1),
                child: const ModernVideoControls(),
              ),
            ),
          );
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
} 