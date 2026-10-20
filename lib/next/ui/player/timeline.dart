import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../detail/episodes.dart' show HeatPainter;
import '../theme/tokens.dart';

/// `12:34`, or `1:02:03` past an hour.
String playerTime(Duration d) {
  final s = d.inSeconds.clamp(0, 1 << 31);
  String two(int n) => n.toString().padLeft(2, '0');
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// The video's line: what is watched in paper, what is loaded faintly,
/// and above it the danmaku heat, the same crimson line as an episode's
/// card. Hovered it thickens and tells the time under the pointer; a click
/// or a drag goes there.
class PlayerTimeline extends StatefulWidget {
  const PlayerTimeline({
    super.key,
    required this.position,
    required this.duration,
    this.buffered = Duration.zero,
    this.heat,
    required this.onSeek,
    this.onScrub,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final List<double>? heat;
  final ValueChanged<Duration> onSeek;

  /// True while the viewer drags along it.
  final ValueChanged<bool>? onScrub;

  static const height = 40.0;
  static const _heatHeight = 22.0;
  static const _trackTop = 28.0;

  @override
  State<PlayerTimeline> createState() => _PlayerTimelineState();
}

class _PlayerTimelineState extends State<PlayerTimeline> {
  double? _hover;
  double? _drag;

  double _fraction(Duration d) => widget.duration.inMilliseconds <= 0
      ? 0
      : (d.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);

  Duration _at(double fraction) => Duration(
      milliseconds: (widget.duration.inMilliseconds * fraction).round());

  double _x(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _end() {
    final at = _drag;
    if (at == null) return;
    setState(() => _drag = null);
    widget.onScrub?.call(false);
    widget.onSeek(_at(at));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final width = c.maxWidth;
        final played = _drag ?? _fraction(widget.position);
        final shown = _drag ?? _hover;
        final active = _hover != null || _drag != null;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) => setState(() => _hover = _x(e.localPosition, width)),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) => widget.onSeek(_at(_x(e.localPosition, width))),
            onHorizontalDragStart: (e) {
              setState(() => _drag = _x(e.localPosition, width));
              widget.onScrub?.call(true);
            },
            onHorizontalDragUpdate: (e) =>
                setState(() => _drag = _x(e.localPosition, width)),
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: _end,
            child: SizedBox(
              height: PlayerTimeline.height,
              child: Stack(clipBehavior: Clip.none, children: [
                if (widget.heat case final heat? when heat.length > 1)
                  // Its quiet stretches lie along the track, under it.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: PlayerTimeline._trackTop -
                        PlayerTimeline._heatHeight +
                        2,
                    height: PlayerTimeline._heatHeight,
                    child: AnimatedOpacity(
                      opacity: active ? 0.95 : 0.6,
                      duration: const Duration(milliseconds: 180),
                      child: CustomPaint(painter: HeatPainter(heat)),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: PlayerTimeline._trackTop,
                  child: _Track(
                    played: played,
                    buffered: _fraction(widget.buffered),
                    hover: _hover,
                    thick: active,
                  ),
                ),
                if (active)
                  Positioned(
                    left: played * width - 6,
                    top: PlayerTimeline._trackTop + 2.5 - 6,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: NextColors.paper,
                        boxShadow: [
                          BoxShadow(color: Color(0x66000000), blurRadius: 6)
                        ],
                      ),
                    ),
                  ),
                if (shown != null)
                  Positioned(
                    left: (shown * width - 30).clamp(0.0, math.max(0, width - 60)),
                    top: -14,
                    width: 60,
                    child: Center(child: _TimeBubble(playerTime(_at(shown)))),
                  ),
              ]),
            ),
          ),
        );
      });
}

class _Track extends StatelessWidget {
  const _Track(
      {required this.played,
      required this.buffered,
      required this.hover,
      required this.thick});
  final double played;
  final double buffered;
  final double? hover;
  final bool thick;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: NextMotion.ease,
        height: thick ? 5 : 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: CustomPaint(
            size: Size.infinite,
            painter: _TrackPainter(played, buffered, hover),
          ),
        ),
      );
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.played, this.buffered, this.hover);
  final double played;
  final double buffered;
  final double? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x2EFFFFFF));
    canvas.drawRect(Rect.fromLTWH(0, 0, w * math.max(buffered, played), h),
        Paint()..color = const Color(0x29FFFFFF));
    if (hover case final at? when at > played) {
      canvas.drawRect(Rect.fromLTWH(w * played, 0, w * (at - played), h),
          Paint()..color = const Color(0x40FFFFFF));
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, w * played, h),
        Paint()..color = NextColors.paper);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.played != played || old.buffered != buffered || old.hover != hover;
}

class _TimeBubble extends StatelessWidget {
  const _TimeBubble(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xD912121A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: Text(text,
            maxLines: 1,
            style: NextText.num(12, color: NextColors.paper)),
      );
}
