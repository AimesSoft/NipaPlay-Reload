import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../player/subtitles/controller.dart' show OverlayFrame;

/// The subtitle file NipaPlay draws over the video (SRT, VTT and other
/// text files): the line the session's subtitles give, outlined, where the
/// shared settings put it. It rebuilds only when the line or its look
/// changes; it never takes the pointer (clicks go to the picture below).
///
/// The size, colour, font, outline and shadow are Classic's overlay's, from
/// the same settings (D3); so is the place: a height of 0 (top) to 100
/// (bottom) of the stage and a sideways shift, kept per file.
class NextSubtitleLayer extends StatelessWidget {
  const NextSubtitleLayer({super.key, required this.overlay});
  final ValueListenable<OverlayFrame?> overlay;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ValueListenableBuilder<OverlayFrame?>(
          valueListenable: overlay,
          builder: (context, frame, _) {
            if (frame == null ||
                frame.text.trim().isEmpty ||
                frame.look.opacity <= 0) {
              return const SizedBox.expand();
            }
            return _Line(frame: frame);
          },
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.frame});
  final OverlayFrame frame;

  static TextAlign _align(int x) => switch (x) {
        0 => TextAlign.left,
        2 => TextAlign.right,
        _ => TextAlign.center,
      };

  static double _alignX(int x) => switch (x) {
        0 => -1,
        2 => 1,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final look = frame.look;
    final placement = frame.placement;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final base = (width * 0.03).clamp(18.0, 42.0);
      final size = (base * look.overlayScale).clamp(14.0, 72.0).toDouble();
      final fonts = [
        for (final f in look.overlayFont.split(','))
          if (f.trim().isNotEmpty) f.trim()
      ];
      final color = Color(look.overlayColor);
      final fill = TextStyle(
        inherit: false,
        decoration: TextDecoration.none,
        fontSize: size,
        fontWeight: look.bold ? FontWeight.bold : FontWeight.w500,
        fontStyle: look.italic ? FontStyle.italic : FontStyle.normal,
        color: color,
        height: 1.28,
        fontFamily: fonts.firstOrNull,
        fontFamilyFallback: fonts.length > 1 ? fonts.sublist(1) : null,
        shadows: look.shadowOffset > 0
            ? [
                Shadow(
                  color: color,
                  offset: Offset(0, look.shadowOffset),
                  blurRadius: look.shadowOffset * 2,
                )
              ]
            : null,
      );
      final align = _align(look.alignX);
      final border = look.borderSize.clamp(0.0, 8.0).toDouble();
      final text = Text(frame.text, textAlign: align, softWrap: true, style: fill);
      final position = placement.position
          .clamp(0.0, 100.0)
          .toDouble();
      return Opacity(
        opacity: look.opacity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Align(
            alignment: Alignment(_alignX(look.alignX), position / 100 * 2 - 1),
            child: Transform.translate(
              offset: Offset(placement.marginX, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width * 0.9),
                child: border <= 0
                    ? text
                    : Stack(alignment: Alignment.center, children: [
                        Text(
                          frame.text,
                          textAlign: align,
                          softWrap: true,
                          // The outline: the same text, stroked black.
                          style: TextStyle(
                            inherit: false,
                            decoration: TextDecoration.none,
                            fontSize: fill.fontSize,
                            fontWeight: fill.fontWeight,
                            fontStyle: fill.fontStyle,
                            height: fill.height,
                            fontFamily: fill.fontFamily,
                            fontFamilyFallback: fill.fontFamilyFallback,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeJoin = StrokeJoin.round
                              ..strokeWidth = border
                              ..color = const Color(0xFF000000),
                          ),
                        ),
                        text,
                      ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}
