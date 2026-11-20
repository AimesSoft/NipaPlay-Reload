import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Adjusts the player's volume after child scrollables have had first refusal.
class PlayerVolumeScrollRegion extends StatefulWidget {
  const PlayerVolumeScrollRegion({
    super.key,
    required this.isEnabled,
    required this.onVolumeChange,
    required this.child,
  });

  // Read when handling the event: opening a menu can suppress shortcuts without
  // rebuilding the video surface.
  final bool Function() isEnabled;
  final ValueChanged<double> onVolumeChange;
  final Widget child;

  @override
  State<PlayerVolumeScrollRegion> createState() =>
      _PlayerVolumeScrollRegionState();
}

class _PlayerVolumeScrollRegionState extends State<PlayerVolumeScrollRegion> {
  // Accumulating small deltas avoids applying 5% for every precision-touchpad
  // event. Mouse wheel deltas also vary with the OS scrolling settings.
  static const _pixelsPerStep = 20.0;
  static const _gestureTimeout = Duration(milliseconds: 500);
  double _remainder = 0;
  Duration? _lastScrollTime;

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!widget.isEnabled()) {
      _remainder = 0;
      _lastScrollTime = null;
      return;
    }
    if (event is! PointerScrollEvent ||
        !event.scrollDelta.dy.isFinite ||
        event.scrollDelta.dy == 0 ||
        event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()) {
      return;
    }

    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (!mounted || !widget.isEnabled()) return;
      final scroll = event as PointerScrollEvent;
      final delta = scroll.scrollDelta.dy;
      final previousTime = _lastScrollTime;
      if (previousTime == null ||
          scroll.timeStamp < previousTime ||
          scroll.timeStamp - previousTime > _gestureTimeout ||
          (_remainder != 0 && _remainder.sign != delta.sign)) {
        _remainder = 0;
      }
      _lastScrollTime = scroll.timeStamp;
      _remainder += delta;
      final steps = (_remainder / _pixelsPerStep).truncate();
      if (steps == 0) return;
      _remainder -= steps * _pixelsPerStep;
      // Wheel up raises volume. Large wheel deltas still produce one 5% step
      // rather than making the volume jump by 25% with Windows' default delta.
      widget.onVolumeChange(steps < 0 ? 0.05 : -0.05);
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handlePointerSignal,
        child: widget.child,
      );
}
