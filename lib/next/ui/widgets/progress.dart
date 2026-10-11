import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'icons.dart';

/// `.ring`: total progress of background work.
class ProgressRing extends StatelessWidget {
  const ProgressRing(
      {super.key, required this.progress, this.size = 16, this.thickness = 3});
  final double progress;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0, 1)),
        duration: const Duration(milliseconds: 600),
        curve: NextMotion.ease,
        builder: (context, value, _) => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(value, thickness),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.thickness);
  final double value;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.width / 2 - thickness / 2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;
    canvas.drawArc(
        rect, 0, math.pi * 2, false, stroke..color = const Color(0x24FFFFFF));
    if (value > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false,
          stroke..color = NextColors.accent);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.thickness != thickness;
}

/// `.live .bar` / `.prog`: a thin bar, crimson with a moving sheen while work
/// is running, or plain paper for watch progress.
class ThinBar extends StatelessWidget {
  const ThinBar({
    super.key,
    required this.progress,
    this.height = 3,
    this.width,
    this.live = false,
    this.track = const Color(0x24FFFFFF),
    this.fill,
  });
  final double progress;
  final double height;
  final double? width;
  final bool live;
  final Color track;

  /// Solid fill; defaults to the crimson gradient when [live].
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    // The track spans the available width even under loose constraints.
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: DecoratedBox(
          decoration: BoxDecoration(color: track),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress.clamp(0, 1)),
            duration: const Duration(milliseconds: 600),
            curve: NextMotion.ease,
            builder: (context, value, child) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: child,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                color: fill ?? (live ? null : NextColors.paper),
                gradient: fill == null && live
                    ? const LinearGradient(
                        colors: [NextColors.accent, NextColors.accent2])
                    : null,
              ),
              child: live && !reduced ? const _Sheen() : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _Sheen extends StatefulWidget {
  const _Sheen();

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat();
  late final Animation<Offset> _offset =
      Tween(begin: const Offset(-1, 0), end: const Offset(1, 0)).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
          child: ClipRect(
        child: SlideTransition(
          position: _offset,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0x00FFFFFF),
                Color(0xB3FFFFFF),
                Color(0x00FFFFFF)
              ]),
            ),
            child: SizedBox.expand(),
          ),
        ),
      ));
}

/// A crimson dot with an expanding halo (concept `.pulse`).
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.size = 7});
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration:
          const BoxDecoration(shape: BoxShape.circle, color: NextColors.accent),
    );
    if (reduced) return dot;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final t = (_c.value / 0.7).clamp(0.0, 1.0);
                return Opacity(
                  opacity: (1 - t) * 0.6,
                  child: Transform.scale(
                      scale: 1 + t * 16 / widget.size, child: child),
                );
              },
              child: dot,
            ),
            dot,
          ]),
    );
  }
}

/// `.thinking`: three dots fading in turn.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, this.size = 5, this.color = NextColors.p3});
  final double size;
  final Color color;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _opacity(int i) {
    final t = (_c.value - i * 0.125) % 1.0;
    // keyframes: 0/80/100% → .25, 40% → 1
    if (t < 0.4) return 0.25 + 0.75 * (t / 0.4);
    if (t < 0.8) return 1 - 0.75 * ((t - 0.4) / 0.4);
    return 0.25;
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: '在想',
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Opacity(
                  opacity: _opacity(i),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: widget.color),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

enum StepMarkState { done, running, waiting, failed }

/// `.mark`: the step marker in preparation cards.
class StepMark extends StatelessWidget {
  const StepMark(this.state, {super.key, this.size = 21});
  final StepMarkState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case StepMarkState.done:
        return _circle(
          const Color(0x245BE3B0),
          const Color(0x595BE3B0),
          const NextIcon(NextGlyph.check,
              size: 12, color: NextColors.mint, stroke: 2.6),
        );
      case StepMarkState.running:
        return _circle(NextColors.accentSoft, const Color(0x80FF2E55),
            const PulseDot(size: 7));
      case StepMarkState.waiting:
        return _circle(const Color(0x00000000), NextColors.line2, null);
      case StepMarkState.failed:
        return _circle(
            const Color(0x24FFBF5C),
            const Color(0x66FFBF5C),
            Text('!',
                style: NextText.num(11,
                    weight: FontWeight.w700, color: NextColors.amber)));
    }
  }

  Widget _circle(Color fill, Color ring, Widget? child) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: ring, width: 1),
        ),
        child: child,
      );
}
