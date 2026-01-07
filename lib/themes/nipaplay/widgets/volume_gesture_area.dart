import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class VolumeGestureArea extends StatefulWidget {
  const VolumeGestureArea({super.key});

  @override
  State<VolumeGestureArea> createState() => _VolumeGestureAreaState();
}

class _VolumeGestureAreaState extends State<VolumeGestureArea> {
  void _onVerticalDragStart(BuildContext context, DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.startVolumeDrag();
  }

  void _onVerticalDragUpdate(BuildContext context, DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.updateVolumeOnDrag(details.delta.dy, context);
  }

  void _onVerticalDragEnd(BuildContext context, DragEndDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.endVolumeDrag();
  }

  void _onVerticalDragCancel(BuildContext context) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.endVolumeDrag();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width / 2.2,
      child: GestureDetector(
        onVerticalDragStart: (details) =>
            _onVerticalDragStart(context, details),
        onVerticalDragUpdate: (details) =>
            _onVerticalDragUpdate(context, details),
        onVerticalDragEnd: (details) => _onVerticalDragEnd(context, details),
        onVerticalDragCancel: () => _onVerticalDragCancel(context),
        behavior: HitTestBehavior.translucent,
        child: Container(),
      ),
    );
  }
}
