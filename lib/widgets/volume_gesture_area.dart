import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';

class VolumeGestureArea extends StatefulWidget {
  const VolumeGestureArea({super.key});

  @override
  State<VolumeGestureArea> createState() => _VolumeGestureAreaState();
}

class _VolumeGestureAreaState extends State<VolumeGestureArea> {
  bool _isVerticalDrag = false;

  void _onPanStart(BuildContext context, DragStartDetails details) {
    _isVerticalDrag = false; 
  }

  void _onPanUpdate(BuildContext context, DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!_isVerticalDrag) {
      if (details.delta.dy.abs() > details.delta.dx.abs()) {
        _isVerticalDrag = true;
        videoState.startVolumeDrag(); 
      } else {
        return; 
      }
    }

    if (_isVerticalDrag) {
      videoState.updateVolumeOnDrag(details.delta.dy, context);
    }
  }

  void _onPanEnd(BuildContext context, DragEndDetails details) {
    if (_isVerticalDrag) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.endVolumeDrag();
    }
    _isVerticalDrag = false; 
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width / 2.2,
      child: GestureDetector(
        onPanStart: (details) => _onPanStart(context, details),
        onPanUpdate: (details) => _onPanUpdate(context, details),
        onPanEnd: (details) => _onPanEnd(context, details),
        behavior: HitTestBehavior.translucent,
        child: Container(), 
      ),
    );
  }
} 