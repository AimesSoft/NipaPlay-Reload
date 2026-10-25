import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/art_origin.dart';
import '../widgets/artwork.dart';

/// The home's backdrop.
///
/// State A frames the artwork like the concept's 660 px hero (`center 30%`),
/// state B like the full-height stage (`center 35%`). The artwork is laid
/// out once for B; A is reached with a transform, so switching states,
/// the slow push-in (1.00 → 1.05 over 20 s) and scrolling only change
/// transforms and opacity. A new backdrop cross-fades in [fade].
class HeroBackdrop extends StatefulWidget {
  const HeroBackdrop({
    super.key,
    required this.workId,
    required this.image,
    required this.tint,
    required this.staged,
    required this.scroll,
    required this.viewport,
    this.fade = NextMotion.crossfade,
    this.soft = false,
  });

  /// The work shown: opening it flies this picture into its detail page.
  final String? workId;
  final String? image;

  /// [image] is a poster standing in for missing wide art.
  final bool soft;
  final int? tint;
  final bool staged;
  final ScrollController scroll;
  final Size viewport;

  /// How long a new backdrop takes to cross-fade in.
  final Duration fade;

  /// Height of state A's hero: the first shelf starts 24 px below it.
  static double heroHeight(double viewportHeight) => viewportHeight - 240;

  @override
  State<HeroBackdrop> createState() => _HeroBackdropState();
}

class _HeroBackdropState extends State<HeroBackdrop>
    with TickerProviderStateMixin {
  late final AnimationController _push =
      AnimationController(vsync: this, duration: NextMotion.kenBurns);
  late final AnimationController _stage = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: widget.staged ? 1 : 0);
  late final Animation<double> _stageT =
      CurvedAnimation(parent: _stage, curve: NextMotion.ease);
  bool _reduced = false;

  /// The visible part of the artwork (A's hero, or the whole page in B).
  final _visible = GlobalKey(debugLabel: 'hero.visible');

  void _syncMotion() {
    final reduced = NextMotion.reduced(context);
    if (reduced == _reduced && (_reduced || _push.isAnimating)) return;
    _reduced = reduced;
    if (_reduced) {
      _push.stop();
      _push.value = 0;
    } else if (!_push.isAnimating) {
      _push.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(HeroBackdrop old) {
    super.didUpdateWidget(old);
    if (old.staged != widget.staged) {
      if (_reduced) {
        _stage.value = widget.staged ? 1 : 0;
      } else if (widget.staged) {
        _stage.forward();
      } else {
        _stage.reverse();
      }
    }
  }

  @override
  void dispose() {
    _push.dispose();
    _stage.dispose();
    super.dispose();
  }

  /// Where a 16:9 artwork lies when it covers the viewport at `center 35%`.
  static Rect _bRect(Size view) {
    const aspect = 16 / 9;
    final wB = math.max(view.width, view.height * aspect), hB = wB / aspect;
    return Rect.fromLTWH(
        (view.width - wB) / 2, (view.height - hB) * 0.35, wB, hB);
  }

  /// Maps the B layout of a 16:9 artwork onto A's framing.
  static (double, Offset) _aFraming(Size view) {
    const aspect = 16 / 9;
    final w = view.width, h = view.height;
    final hA = HeroBackdrop.heroHeight(h);
    final wB = math.max(w, h * aspect), hB = wB / aspect;
    final xB = (w - wB) / 2, yB = (h - hB) * 0.35;
    final wA = math.max(w, hA * aspect), hAImg = wA / aspect;
    final xA = (w - wA) / 2, yA = (hA - hAImg) * 0.30;
    final s = wA / wB;
    return (s, Offset(xA - s * xB, yA - s * yB));
  }

  @override
  Widget build(BuildContext context) {
    _syncMotion();
    final view = widget.viewport;
    final hA = HeroBackdrop.heroHeight(view.height);
    // A phone's hero is a poster standing over the words, framed the same
    // in A and B; the words are under it, so it is shaded from below.
    final compact = view.width < NextLayout.compactWidth;
    final (sA, tA) = compact ? (1.0, Offset.zero) : _aFraming(view);

    // The artwork at its full B size (16:9 cover of the viewport), not
    // clipped to the viewport, so A's smaller scale still covers the width.
    final b = compact ? Rect.fromLTWH(0, 0, view.width, hA) : _bRect(view);
    final art = SizedBox(
      width: view.width,
      height: view.height,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fromRect(
          rect: b,
          child: _origin(AnimatedSwitcher(
            duration: widget.fade,
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, if (current != null) current]),
            child: KeyedSubtree(
              key: ValueKey(widget.image),
              child: widget.image == null
                  ? NoArtGlow(tint: widget.tint)
                  : widget.soft
                  ? SoftArt(widget.image!, tint: widget.tint)
                  : NextImage(
                      widget.image,
                      tint: widget.tint,
                      alignment: const Alignment(0, -0.3),
                      fade: const Duration(milliseconds: 400),
                    ),
            ),
          )),
        ),
      ]),
    );

    final shades = Stack(fit: StackFit.expand, children: [
      // A: the concept's `.hero .shade` over a 660 px hero, then ink.
      FadeTransition(
        opacity: ReverseAnimation(_stageT),
        child: Stack(children: [
          Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: hA,
              child: ShadeLayers(compact ? heroShadeCompact : heroShadeA)),
          Positioned(
              left: 0,
              right: 0,
              top: hA - 1,
              bottom: -2000,
              child: const ColoredBox(color: NextColors.ink)),
        ]),
      ),
      FadeTransition(
          opacity: _stageT,
          child: ShadeLayers(compact ? heroShadeCompact : heroShadeB)),
    ]);

    return ClipRect(
      child: AnimatedBuilder(
        animation: Listenable.merge([_push, _stageT, widget.scroll]),
        builder: (context, _) {
          final t = _stageT.value;
          final scroll = math.max(
              0.0, widget.scroll.hasClients ? widget.scroll.offset : 0.0);
          final s = sA + (1 - sA) * t;
          final offset = Offset.lerp(tA, Offset.zero, t)!;
          final push = 1 + 0.05 * Curves.easeInOut.transform(_push.value);
          final visibleH = hA + (view.height - hA) * t;
          final focus = Offset(view.width / 2, visibleH * 0.45);
          final matrix = Matrix4.identity()
            ..translateByDouble(0, -scroll, 0, 1)
            ..translateByDouble(focus.dx, focus.dy, 0, 1)
            ..scaleByDouble(push, push, 1, 1)
            ..translateByDouble(-focus.dx, -focus.dy, 0, 1)
            ..translateByDouble(offset.dx, offset.dy, 0, 1)
            ..scaleByDouble(s, s, 1, 1);
          return Stack(fit: StackFit.expand, children: [
            Positioned(
              left: 0,
              top: 0,
              width: view.width,
              height: view.height,
              child: Transform(transform: matrix, child: art),
            ),
            Transform.translate(
              offset: Offset(0, -scroll),
              child: shades,
            ),
            Positioned(
              left: 0,
              top: -scroll,
              width: view.width,
              height: visibleH,
              child: SizedBox(key: _visible),
            ),
          ]);
        },
      ),
    );
  }
}

const _ink = NextColors.ink;

extension on _HeroBackdropState {
  Widget _origin(Widget child) {
    final workId = widget.workId;
    if (workId == null) return child;
    return ArtOrigin(
      workId: workId,
      image: widget.image,
      tint: widget.tint,
      alignment: const Alignment(0, -0.3),
      visible: _visible,
      shade: widget.staged ? heroShadeB : heroShadeA,
      lifts: false,
      child: child,
    );
  }
}

Color _a(double alpha) => _ink.withValues(alpha: alpha);

/// The concept's `.hero .shade` over A's hero, then the stage's over the
/// whole page in B: left, bottom and top gradients. Kept as data so a
/// shared element flight can blend them into the detail page's shade.
final heroShadeA = <Gradient>[
  LinearGradient(
    colors: [_a(.94), _a(.78), _a(.24), _a(0)],
    stops: const [0, .26, .56, .72],
  ),
  LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [_ink, _a(.6), _a(0)],
    stops: const [0, .22, .46],
  ),
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_a(.55), _a(0)],
    stops: const [0, .18],
  ),
];

/// A phone's hero: ink rising from under the words, a little under the
/// status bar.
final heroShadeCompact = <Gradient>[
  LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [_ink, _a(.82), _a(.3), _a(0)],
    stops: const [0, .3, .55, .75],
  ),
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_a(.5), _a(0)],
    stops: const [0, .16],
  ),
];

final heroShadeB = <Gradient>[
  LinearGradient(
    colors: [_a(.95), _a(.86), _a(.4), _a(.25)],
    stops: const [0, .38, .7, 1],
  ),
  LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [_ink, _a(.7), _a(0)],
    stops: const [0, .3, .6],
  ),
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_a(.6), _a(0)],
    stops: const [0, .22],
  ),
];

/// Gradients stacked over artwork.
class ShadeLayers extends StatelessWidget {
  const ShadeLayers(this.gradients, {super.key});
  final List<Gradient> gradients;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        for (final g in gradients)
          DecoratedBox(decoration: BoxDecoration(gradient: g)),
      ]);
}

/// No artwork yet: a quiet glow in the work's tint (or Nipa's crimson), so
/// the hero still has depth.
class NoArtGlow extends StatelessWidget {
  const NoArtGlow({super.key, this.tint});
  final int? tint;

  @override
  Widget build(BuildContext context) {
    final glow = tint == null ? NextColors.accent : Color(tint!);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NextColors.ink2,
        gradient: RadialGradient(
          center: const Alignment(0.55, -0.35),
          radius: 0.9,
          colors: [
            glow.withValues(alpha: tint == null ? 0.16 : 0.42),
            glow.withValues(alpha: tint == null ? 0.05 : 0.14),
            NextColors.ink2.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
    );
  }
}
