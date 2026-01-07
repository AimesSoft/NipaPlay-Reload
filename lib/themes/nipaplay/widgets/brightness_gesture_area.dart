import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class BrightnessGestureArea extends StatefulWidget {
  const BrightnessGestureArea({super.key});

  @override
  State<BrightnessGestureArea> createState() => _BrightnessGestureAreaState();
}

class _BrightnessGestureAreaState extends State<BrightnessGestureArea> {
  void _onVerticalDragStart(BuildContext context, DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.startBrightnessDrag();
  }

  void _onVerticalDragUpdate(BuildContext context, DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.updateBrightnessOnDrag(details.delta.dy, context);
  }

  void _onVerticalDragEnd(BuildContext context, DragEndDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.endBrightnessDrag();
  }

  void _onVerticalDragCancel(BuildContext context) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.endBrightnessDrag();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width /
          2.2, // Consistent with original width
      child: GestureDetector(
        onVerticalDragStart: (details) =>
            _onVerticalDragStart(context, details),
        onVerticalDragUpdate: (details) =>
            _onVerticalDragUpdate(context, details),
        onVerticalDragEnd: (details) => _onVerticalDragEnd(context, details),
        onVerticalDragCancel: () => _onVerticalDragCancel(context),
        behavior: HitTestBehavior.translucent,
        child: Container(), // Empty container, purely for gesture detection
      ),
    );
  }
}
