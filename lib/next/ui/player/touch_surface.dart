import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../theme/tokens.dart';
import 'playback.dart';
import 'timeline.dart' show playerTime;

/// The picture under a finger (a phone, a tablet): a tap shows or hides the
/// controls, a double tap on the left or right third goes back or on ten
/// seconds (in the middle it plays or pauses), a sideways drag moves
/// through the video, an upright drag on the left half sets the screen's
/// brightness and on the right half the volume. What a gesture is doing
/// shows in the middle while it does it. Nothing here reads the kernel:
/// the playback's own snapshot and calls only.
class PlayerTouchSurface extends StatefulWidget {
  const PlayerTouchSurface(
      {super.key, required this.playback, required this.onTap});
  final NextPlayback playback;

  /// Show or hide the controls.
  final VoidCallback onTap;

  /// A double tap's step.
  static const step = Duration(seconds: 10);

  /// A drag across the whole width moves this far.
  static const sweep = Duration(seconds: 120);

  @override
  State<PlayerTouchSurface> createState() => _PlayerTouchSurfaceState();
}

enum _Drag { seek, brightness, volume }

class _PlayerTouchSurfaceState extends State<PlayerTouchSurface> {
  Offset? _doubleAt;
  Offset? _start;
  _Drag? _drag;
  Duration _from = Duration.zero;
  Duration? _target;
  double _level = 0;
  double _levelFrom = 0;
  bool _brightnessKnown = false;
  String? _hint;
  Timer? _hintGone;

  NextPlayback get _p => widget.playback;

  @override
  void dispose() {
    _hintGone?.cancel();
    // The screen's own brightness comes back with the controls' end.
    if (_brightnessKnown) {
      unawaited(ScreenBrightness()
          .resetApplicationScreenBrightness()
          .catchError((Object _) {}));
    }
    super.dispose();
  }

  void _say(String text, {bool linger = true}) {
    _hintGone?.cancel();
    setState(() => _hint = text);
    if (linger) {
      _hintGone = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _hint = null);
      });
    }
  }

  void _double() {
    final at = _doubleAt;
    final box = context.size;
    if (at == null || box == null || !_p.hasVideo) return;
    final third = box.width / 3;
    if (at.dx > third && at.dx < 2 * third) {
      _p.togglePlay();
      return;
    }
    final back = at.dx <= third;
    final d = _p.duration;
    var to = _p.position + (back ? -PlayerTouchSurface.step : PlayerTouchSurface.step);
    if (to < Duration.zero) to = Duration.zero;
    if (d > Duration.zero && to > d) to = d;
    _p.seek(to);
    unawaited(HapticFeedback.selectionClick());
    _say(back ? '−10 秒' : '+10 秒');
  }

  void _panStart(DragStartDetails d) {
    _start = d.localPosition;
    _drag = null;
  }

  Future<void> _panUpdate(DragUpdateDetails d) async {
    final start = _start;
    final box = context.size;
    if (start == null || box == null || !_p.hasVideo) return;
    final delta = d.localPosition - start;
    if (_drag == null) {
      if (delta.distance < 8) return;
      if (delta.dx.abs() > delta.dy.abs()) {
        _drag = _Drag.seek;
        _from = _p.position;
      } else if (start.dx < box.width / 2) {
        _drag = _Drag.brightness;
        _levelFrom = _level = await _brightness();
      } else {
        _drag = _Drag.volume;
        _levelFrom = _level = _p.volume;
      }
    }
    switch (_drag!) {
      case _Drag.seek:
        final d = _p.duration;
        var to = _from +
            PlayerTouchSurface.sweep * (delta.dx / math.max(1.0, box.width));
        if (to < Duration.zero) to = Duration.zero;
        if (d > Duration.zero && to > d) to = d;
        _target = to;
        _say('${playerTime(to)} / ${playerTime(d)}', linger: false);
      case _Drag.brightness:
      case _Drag.volume:
        final value = (_levelFrom - delta.dy / math.max(1.0, box.height * 0.8))
            .clamp(0.0, 1.0);
        if ((value - _level).abs() < 0.01) return;
        _level = value;
        final percent = '${(value * 100).round()}%';
        if (_drag == _Drag.brightness) {
          unawaited(ScreenBrightness()
              .setApplicationScreenBrightness(value)
              .catchError((Object _) {}));
          _say('亮度 $percent', linger: false);
        } else {
          unawaited(_p.setVolume(value));
          _say('音量 $percent', linger: false);
        }
    }
  }

  void _panEnd(DragEndDetails _) {
    if (_drag == _Drag.seek && _target != null) _p.seek(_target!);
    _drag = null;
    _start = null;
    _target = null;
    if (_hint != null) _say(_hint!);
  }

  Future<double> _brightness() async {
    try {
      final value = await ScreenBrightness().application;
      _brightnessKnown = true;
      return value;
    } catch (_) {
      return 0.5;
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Measured from where the finger came down.
        dragStartBehavior: DragStartBehavior.down,
        onTap: widget.onTap,
        onDoubleTapDown: (d) => _doubleAt = d.localPosition,
        onDoubleTap: _double,
        onPanStart: _panStart,
        onPanUpdate: (d) => unawaited(_panUpdate(d)),
        onPanEnd: _panEnd,
        child: Stack(fit: StackFit.expand, children: [
          const SizedBox.expand(),
          Center(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hint == null ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xB308080B),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_hint ?? '',
                      style: NextText.num(16,
                          weight: FontWeight.w600, color: NextColors.paper)),
                ),
              ),
            ),
          ),
        ]),
      );
}

/// A phone turns sideways for a video's full screen and stands up again
/// for the pages. The pages are upright; while a video is open the phone
/// may turn either way.
abstract final class PhoneOrientation {
  static const _upright = [DeviceOrientation.portraitUp];
  static const _sideways = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const _any = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static Future<void> pages() => _set(_upright, SystemUiMode.edgeToEdge);
  static Future<void> video() => _set(_any, SystemUiMode.edgeToEdge);

  /// Full screen: sideways, the system's bars away; and back.
  static Future<void> fullScreen(bool on) => on
      ? _set(_sideways, SystemUiMode.immersiveSticky)
      : _set(_upright, SystemUiMode.edgeToEdge);

  static Future<void> _set(
      List<DeviceOrientation> orientations, SystemUiMode mode) async {
    try {
      await SystemChrome.setPreferredOrientations(orientations);
      await SystemChrome.setEnabledSystemUIMode(mode);
    } catch (e) {
      debugPrint('[NextPlayer] orientation: $e');
    }
  }
}
