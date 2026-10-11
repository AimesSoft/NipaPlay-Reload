import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../home/hero_backdrop.dart' show NoArtGlow, ShadeLayers;
import '../theme/tokens.dart';
import '../widgets/art_origin.dart';
import '../widgets/artwork.dart';

/// The detail page's backdrop: the work's artwork full bleed at the
/// concept's `center 20%`, under its shade, moving at 0.3× the scroll.
///
/// While the route animates, the same layer grows out of the picture the
/// work was opened from ([source]) and shrinks back into it on return:
/// frame, corners, framing and the picture's own shade all interpolate, and
/// a different picture (a poster) cross-fades into the backdrop. When there
/// is nothing to fly to, the page fades.
class DetailBackdrop extends StatelessWidget {
  const DetailBackdrop({
    super.key,
    required this.image,
    required this.tint,
    required this.size,
    required this.scroll,
    required this.route,
    required this.flight,
    required this.flies,
    required this.source,
    required this.parallax,
  });

  final String? image;
  final int? tint;
  final Size size;
  final ScrollController scroll;

  /// The route's own animation, and the same with the flight's curve.
  final Animation<double> route;
  final Animation<double> flight;
  final bool flies;

  /// Where the picture flown from is this frame; null when it is gone.
  final ArtFrame? Function() source;
  final bool parallax;

  static const alignment = Alignment(0, -0.6);

  @override
  Widget build(BuildContext context) {
    final decode = NextImage.decodeWidth(
        size, MediaQuery.devicePixelRatioOf(context), ArtShape.wide);
    return AnimatedBuilder(
      animation: Listenable.merge([route, scroll]),
      builder: (context, _) {
        final t = route.value;
        final e = flight.value;
        final moving = flies && t < 1;
        final from = moving ? source() : null;
        final offset =
            parallax && scroll.hasClients ? math.max(0.0, scroll.offset) : 0.0;
        final dest = Rect.fromLTWH(0, -0.3 * offset, size.width, size.height);
        var rect = dest, clip = dest, radius = 0.0;
        var align = alignment;
        if (from != null) {
          rect = Rect.lerp(from.rect, dest, e)!;
          clip = Rect.lerp(from.clip, dest, e)!;
          radius = lerpDouble(from.radius, 0, e)!;
          align = Alignment.lerp(from.alignment, alignment, e)!;
        }
        // Nothing to fly to: the page fades. Over a backdrop that stays
        // (the home's hero), the flight fades in over it.
        final fade = moving && from == null
            ? t
            : (from != null && !from.lifts
                ? Curves.easeOut.transform((t / 0.3).clamp(0.0, 1.0))
                : 1.0);
        final base = from == null
            ? fade
            : Curves.easeOut.transform((t / 0.7).clamp(0.0, 1.0));
        final same = from != null && from.image == image;
        final artIn =
            from == null || same ? 1.0 : const Interval(0.05, 0.5).transform(e);
        return Stack(fit: StackFit.expand, children: [
          Opacity(
              opacity: base, child: const ColoredBox(color: NextColors.ink)),
          Positioned.fromRect(
            rect: clip,
            child: Opacity(
              opacity: fade,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                clipBehavior: radius > 0 ? Clip.antiAlias : Clip.hardEdge,
                child: Stack(fit: StackFit.expand, children: [
                  Positioned(
                    left: rect.left - clip.left,
                    top: rect.top - clip.top,
                    width: rect.width,
                    height: rect.height,
                    child: Stack(fit: StackFit.expand, children: [
                      if (from != null)
                        _Art(from.image,
                            decodeWidth: from.decodeWidth,
                            tint: from.tint,
                            alignment: align),
                      Opacity(
                        opacity: artIn,
                        child: image == null
                            ? NoArtGlow(tint: tint)
                            : _Art(image,
                                decodeWidth: decode,
                                tint: tint,
                                alignment: align,
                                placeholder: from == null),
                      ),
                    ]),
                  ),
                  // A picture with its own shade blends it into the
                  // page's (per gradient, so it never thins out midway).
                  if (from?.shade case final shade?)
                    ShadeLayers([
                      for (var i = 0; i < shade.length; i++)
                        Gradient.lerp(shade[i], detailShade[i], e)!
                    ])
                  else
                    Opacity(
                        opacity: from == null ? 1 : e,
                        child: ShadeLayers(detailShade)),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// A picture decoded once at [decodeWidth] (so a growing frame never
/// re-decodes), covering its box.
class _Art extends StatelessWidget {
  const _Art(this.path,
      {required this.decodeWidth,
      required this.tint,
      required this.alignment,
      this.placeholder = false});
  final String? path;
  final int decodeWidth;
  final int? tint;
  final Alignment alignment;

  /// Show the tint while loading (no other picture is under it).
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final file = path;
    if (file == null) return NextImage(null, tint: tint);
    return Image(
      image:
          ResizeImage.resizeIfNeeded(decodeWidth, null, FileImage(File(file))),
      fit: BoxFit.cover,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) {
        if (synchronous) return child;
        return Stack(fit: StackFit.passthrough, children: [
          if (placeholder) NextImage(null, tint: tint),
          AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: child,
          ),
        ]);
      },
      errorBuilder: (context, error, stack) => NextImage(null, tint: tint),
    );
  }
}

/// The concept's detail shade: dark on the left where the words are, ink at
/// the bottom under the episodes, a little at the top under the bar.
final detailShade = <Gradient>[
  LinearGradient(
    colors: [_a(.95), _a(.8), _a(.22), _a(.05)],
    stops: const [0, .3, .62, 1],
  ),
  LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [NextColors.ink, _a(.85), _a(0)],
    stops: const [0, .26, .55],
  ),
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_a(.55), _a(0)],
    stops: const [0, .2],
  ),
];

Color _a(double alpha) => NextColors.ink.withValues(alpha: alpha);
