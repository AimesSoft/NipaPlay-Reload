import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The shape of an artwork, used to decode at the size it is shown.
enum ArtShape {
  /// 16:9 backdrops and episode stills.
  wide(16 / 9),

  /// 2:3 posters.
  poster(2 / 3),

  /// Logos: width-driven.
  logo(4);

  const ArtShape(this.aspect);
  final double aspect;
}

/// A local artwork file decoded for its displayed size (`cacheWidth`), fading
/// in over a tint gradient while it loads. Missing files show only the tint.
class NextImage extends StatelessWidget {
  const NextImage(
    this.path, {
    super.key,
    this.shape = ArtShape.wide,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.tint,
    this.fade = const Duration(milliseconds: 260),
  });

  final String? path;
  final ArtShape shape;
  final BoxFit fit;
  final Alignment alignment;

  /// ARGB from [UiArtwork.tint], for the placeholder gradient.
  final int? tint;
  final Duration fade;

  /// Rounded up to 128 physical pixels so window resizes reuse decodes.
  static int decodeWidth(Size box, double dpr, ArtShape shape) {
    final logical = shape == ArtShape.logo
        ? box.width
        : math.max(box.width, box.height * shape.aspect);
    final physical = (logical * dpr).ceil();
    return math.max(128, ((physical + 127) ~/ 128) * 128);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(tint: tint, shape: shape);
    final file = path;
    if (file == null || file.isEmpty) return placeholder;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final box = Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : 400,
        constraints.hasBoundedHeight ? constraints.maxHeight : 400,
      );
      final width = decodeWidth(box, dpr, shape);
      return Image(
        image: ResizeImage.resizeIfNeeded(width, null, FileImage(File(file))),
        fit: fit,
        alignment: alignment,
        width: box.width,
        height: shape == ArtShape.logo ? null : box.height,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, synchronous) {
          if (synchronous) return child;
          return Stack(fit: StackFit.passthrough, children: [
            if (shape != ArtShape.logo) Positioned.fill(child: placeholder),
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: fade,
              curve: Curves.easeOut,
              child: child,
            ),
          ]);
        },
        errorBuilder: (context, error, stack) =>
            shape == ArtShape.logo ? const SizedBox.shrink() : placeholder,
      );
    });
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.tint, required this.shape});
  final int? tint;
  final ArtShape shape;

  @override
  Widget build(BuildContext context) {
    if (shape == ArtShape.logo) return const SizedBox.shrink();
    final base = tint == null ? NextColors.ink3 : Color(tint!);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, NextColors.ink, 0.35)!,
            Color.lerp(base, NextColors.ink, 0.8)!,
          ],
        ),
      ),
    );
  }
}
