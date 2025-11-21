import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class VerticalIndicator extends StatefulWidget {
  final VideoPlayerState videoState;

  const VerticalIndicator({
    super.key,
    required this.videoState,
  });

  @override
  State<VerticalIndicator> createState() => _VerticalIndicatorState();
}

class _VerticalIndicatorState extends State<VerticalIndicator> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.videoState.isFullscreen) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 10,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        offset: Offset(widget.videoState.showControls ? 0 : 1, 0),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: widget.videoState.showControls ? 1.0 : 0.0,
          child: SizedBox(
            height: MediaQuery.of(context).size.height,
            child: Center(
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.elasticOut,
                  tween: Tween<double>(
                    begin: 0.33,
                    end: _isHovered ? 0.5 : 0.33,
                  ),
                  builder: (context, value, child) {
                    return Container(
                      width: globals.isPhone ? 6 : 8,
                      height: MediaQuery.of(context).size.height * value,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(globals.isPhone ? 3 : 4),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 