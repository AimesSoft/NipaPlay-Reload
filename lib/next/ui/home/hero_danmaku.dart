import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A few short comments viewers left on the hero's work, drifting across
/// the sky in its upper right (concept `.danmaku`): faint, few, slow, at
/// most one per lane. Nothing when there are none, and nothing under
/// reduced motion (they would only stand there).
class HeroDanmaku extends StatefulWidget {
  const HeroDanmaku({super.key, required this.lines});
  final List<String> lines;

  /// Where the sky is, in the hero: right of 60 % of its width, below the
  /// top bar.
  static Rect area(Size viewport) => Rect.fromLTWH(
      viewport.width * 0.6, NextMetrics.topBar + 26, viewport.width * 0.4, 120);

  @override
  State<HeroDanmaku> createState() => _HeroDanmakuState();
}

/// A lane: its height in the band, one crossing's duration, where in its
/// first crossing it starts (so the sky is not empty at first), the text.
typedef _Lane = ({
  double top,
  Duration crossing,
  double start,
  double size,
  double alpha,
});

class _HeroDanmakuState extends State<HeroDanmaku>
    with SingleTickerProviderStateMixin {
  static const List<_Lane> _lanes = [
    (
      top: 6,
      crossing: Duration(seconds: 28),
      start: 0.42,
      size: 15,
      alpha: 0.42
    ),
    (
      top: 44,
      crossing: Duration(seconds: 34),
      start: 0.17,
      size: 14,
      alpha: 0.34
    ),
    (
      top: 82,
      crossing: Duration(seconds: 25),
      start: 0.65,
      size: 15,
      alpha: 0.38
    ),
  ];

  /// How far past the band's left edge a comment travels before it is gone.
  static const _beyond = 300.0;

  late final Ticker _ticker;
  final _now = ValueNotifier<Duration>(Duration.zero);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _now.value = elapsed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final moving = !NextMotion.reduced(context);
    if (moving && !_ticker.isActive) {
      _ticker.start();
    } else if (!moving && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    if (lines.isEmpty || NextMotion.reduced(context)) {
      return const SizedBox.shrink();
    }
    final lanes = _lanes.take(lines.length).toList();
    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000)
          ],
          stops: [0, 0.14, 0.86, 1],
        ).createShader(bounds),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return ValueListenableBuilder(
              valueListenable: _now,
              builder: (context, now, _) => Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final (i, lane) in lanes.indexed)
                    _comment(lane, i, lanes.length, lines, now, width),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Lane [i]'s comment now: each crossing takes its next line; the lanes
  /// share the lines out, so two never show the same one.
  Widget _comment(_Lane lane, int i, int count, List<String> lines,
      Duration now, double width) {
    final t = now.inMicroseconds / lane.crossing.inMicroseconds + lane.start;
    final lap = t.floor();
    final through = t - lap;
    final line = lines[(i + lap * count) % lines.length];
    return Positioned(
      top: lane.top,
      left: width - through * (width + _beyond),
      child: Text(
        line,
        maxLines: 1,
        softWrap: false,
        style: NextText.sans(
          lane.size,
          weight: FontWeight.w600,
          color: Color.fromRGBO(255, 255, 255, lane.alpha),
          shadows: const [
            Shadow(
                color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1))
          ],
        ),
      ),
    );
  }
}
