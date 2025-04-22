import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import '../utils/video_player_state.dart';
import 'tooltip_bubble.dart';
import '../utils/globals.dart' as globals;

class BackButtonWidget extends StatefulWidget {
  final VideoPlayerState videoState;

  const BackButtonWidget({
    super.key,
    required this.videoState,
  });

  @override
  State<BackButtonWidget> createState() => _BackButtonWidgetState();
}

class _BackButtonWidgetState extends State<BackButtonWidget> {
  bool _isBackButtonHovered = false;
  bool _isBackButtonPressed = false;

  @override
  Widget build(BuildContext context) {
    if (!(widget.videoState.hasVideo && !(globals.isDesktop && widget.videoState.isFullscreen))) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.videoState.showControls ? 1.0 : 0.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 150),
        offset: Offset(widget.videoState.showControls ? 0 : -0.1, 0),
        child: Padding(
          padding: EdgeInsets.all(16.0).copyWith(
            left: globals.isPhone ? 40.0 : 16.0,
          ),
          child: MouseRegion(
            onEnter: (_) {
              setState(() => _isBackButtonHovered = true);
              widget.videoState.setControlsHovered(true);
            },
            onExit: (_) {
              setState(() => _isBackButtonHovered = false);
              widget.videoState.setControlsHovered(false);
            },
            child: TooltipBubble(
              text: '返回',
              showOnRight: true,
              verticalOffset: 8,
              child: GestureDetector(
                onTapDown: (_) => setState(() => _isBackButtonPressed = true),
                onTapUp: (_) async {
                  setState(() => _isBackButtonPressed = false);
                  try {
                    // 重置播放器状态
                    await widget.videoState.resetPlayer();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('重置播放器时出错: $e')),
                      );
                    }
                  }
                },
                onTapCancel: () => setState(() => _isBackButtonPressed = false),
                child: GlassmorphicContainer(
                  width: 48,
                  height: 48,
                  borderRadius: 25,
                  blur: 30,
                  alignment: Alignment.center,
                  border: 1,
                  linearGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFffffff).withOpacity(0.2),
                      const Color(0xFFFFFFFF).withOpacity(0.2),
                    ],
                  ),
                  borderGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFffffff).withOpacity(0.5),
                      const Color((0xFFFFFFFF)).withOpacity(0.5),
                    ],
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isBackButtonHovered ? 1.0 : 0.6,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 100),
                      scale: _isBackButtonPressed ? 0.9 : 1.0,
                      child: const Icon(
                        Ionicons.chevron_back_outline,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 