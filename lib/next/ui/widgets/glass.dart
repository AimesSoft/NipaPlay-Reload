import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A frosted panel. Backdrop blur is expensive: use it for a handful of
/// surfaces only (input bar, task pill, popovers). Cards never blur.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.blur = 26,
    this.saturate = 1.7,
    this.color = const Color(0x9916161C), // rgba(22,22,28,.6)
    this.borderColor = const Color(0x24FFFFFF), // rgba(255,255,255,.14)
    this.radius = const BorderRadius.all(Radius.circular(18)),
    this.shadows = const [],
    this.padding = EdgeInsets.zero,
    this.highlight = true,
  });

  final Widget child;
  final double blur;
  final double saturate;
  final Color color;
  final Color? borderColor;
  final BorderRadius radius;
  final List<BoxShadow> shadows;
  final EdgeInsetsGeometry padding;

  /// The concept's `inset 0 1px 0 rgba(255,255,255,.06)`.
  final bool highlight;

  static ColorFilter saturation(double s) => ColorFilter.matrix(<double>[
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
        0, 0, 0, 1, 0,
      ]);

  @override
  Widget build(BuildContext context) {
    final filter = saturate == 1
        ? ui.ImageFilter.blur(
            sigmaX: blur, sigmaY: blur, tileMode: TileMode.mirror)
        : ui.ImageFilter.compose(
            outer: saturation(saturate),
            inner: ui.ImageFilter.blur(
                sigmaX: blur, sigmaY: blur, tileMode: TileMode.mirror));
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: filter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: radius,
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor!, width: 1),
            ),
            position: DecorationPosition.background,
            child: highlight
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment(0, -0.9),
                        colors: [Color(0x0FFFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                    child: Padding(padding: padding, child: child),
                  )
                : Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// A translucent surface without backdrop blur, for chips and secondary
/// buttons that sit over already darkened artwork.
class Tinted extends StatelessWidget {
  const Tinted({
    super.key,
    required this.child,
    this.color = const Color(0x12FFFFFF),
    this.borderColor = NextColors.line2,
    this.radius = const BorderRadius.all(Radius.circular(18)),
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final Color color;
  final Color? borderColor;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: radius,
          border: borderColor == null ? null : Border.all(color: borderColor!),
        ),
        child: Padding(padding: padding, child: child),
      );
}
