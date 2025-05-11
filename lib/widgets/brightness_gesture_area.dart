import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';

class BrightnessGestureArea extends StatefulWidget {
  const BrightnessGestureArea({super.key});

  @override
  State<BrightnessGestureArea> createState() => _BrightnessGestureAreaState();
}

class _BrightnessGestureAreaState extends State<BrightnessGestureArea> {
  bool _isVerticalDrag = false;

  void _onPanStart(BuildContext context, DragStartDetails details) {
    _isVerticalDrag = false; // Reset at the start of a new pan
    // No need to call startBrightnessDrag here, wait for predominant vertical movement
  }

  void _onPanUpdate(BuildContext context, DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!_isVerticalDrag) {
      // First update after start, determine dominant direction
      if (details.delta.dy.abs() > details.delta.dx.abs()) {
        _isVerticalDrag = true;
        videoState.startBrightnessDrag(); // Start drag only when confirmed vertical
      } else {
        // It's a horizontal drag or ambiguous, do nothing for brightness
        return; 
      }
    }

    if (_isVerticalDrag) {
      videoState.updateBrightnessOnDrag(details.delta.dy, context);
    }
  }

  void _onPanEnd(BuildContext context, DragEndDetails details) {
    if (_isVerticalDrag) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.endBrightnessDrag();
    }
    _isVerticalDrag = false; // Reset for next gesture
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width / 2.2, // Consistent with original width
      child: GestureDetector(
        onPanStart: (details) => _onPanStart(context, details),
        onPanUpdate: (details) => _onPanUpdate(context, details),
        onPanEnd: (details) => _onPanEnd(context, details),
        behavior: HitTestBehavior.translucent,
        child: Container(), // Empty container, purely for gesture detection
      ),
    );
  }
} 