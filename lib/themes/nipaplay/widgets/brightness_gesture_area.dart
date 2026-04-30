import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class BrightnessGestureArea extends StatefulWidget {
  const BrightnessGestureArea({super.key});

  @override
  State<BrightnessGestureArea> createState() => _BrightnessGestureAreaState();
}

class _BrightnessGestureAreaState extends State<BrightnessGestureArea> {
  // 防误触区域高度
  static const double _topSafeArea = 48.0;
  static const double _bottomSafeArea = 40.0;
  // 最小滑动距离阈值
  static const double _minDragDistance = 10.0;

  double _accumulatedDrag = 0.0;
  bool _hasStartedAdjustment = false;

  void _onVerticalDragStart(BuildContext context, DragStartDetails details) {
    _accumulatedDrag = 0.0;
    _hasStartedAdjustment = false;
  }

  void _onVerticalDragUpdate(BuildContext context, DragUpdateDetails details) {
    _accumulatedDrag += details.delta.dy.abs();

    if (!_hasStartedAdjustment && _accumulatedDrag > _minDragDistance) {
      _hasStartedAdjustment = true;
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.startBrightnessDrag();
    }

    if (_hasStartedAdjustment) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.updateBrightnessOnDrag(details.delta.dy, context);
    }
  }

  void _onVerticalDragEnd(BuildContext context, DragEndDetails details) {
    if (_hasStartedAdjustment) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.endBrightnessDrag();
    }
    _accumulatedDrag = 0.0;
    _hasStartedAdjustment = false;
  }

  void _onVerticalDragCancel(BuildContext context) {
    if (_hasStartedAdjustment) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.endBrightnessDrag();
    }
    _accumulatedDrag = 0.0;
    _hasStartedAdjustment = false;
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final effectiveTopSafeArea = safeTop + _topSafeArea;
    final effectiveBottomSafeArea = safeBottom + _bottomSafeArea;

    return Positioned(
      left: 0,
      top: effectiveTopSafeArea,
      bottom: effectiveBottomSafeArea,
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
