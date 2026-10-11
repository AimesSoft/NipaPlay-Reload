import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The concept's stroke icons, drawn on a 24-unit grid.
enum NextGlyph {
  search,
  send,
  play,
  close,
  pause,
  chevronRight,
  chevronLeft,
  check
}

class NextIcon extends StatelessWidget {
  const NextIcon(this.glyph,
      {super.key, this.size = 16, this.color = NextColors.p2, this.stroke});
  final NextGlyph glyph;
  final double size;
  final Color color;
  final double? stroke;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GlyphPainter(glyph, color, stroke)),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color, this.stroke);
  final NextGlyph glyph;
  final Color color;
  final double? stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke ?? 2;
    final fill = Paint()..color = color;
    switch (glyph) {
      case NextGlyph.search:
        canvas.drawCircle(const Offset(11, 11), 7, line);
        canvas.drawLine(const Offset(20, 20), const Offset(16.5, 16.5), line);
      case NextGlyph.send:
        line.strokeWidth = stroke ?? 2.4;
        canvas.drawPath(
            Path()
              ..moveTo(12, 19)
              ..lineTo(12, 5)
              ..moveTo(5, 12)
              ..lineTo(12, 5)
              ..lineTo(19, 12),
            line);
      case NextGlyph.play:
        canvas.drawPath(
            Path()
              ..moveTo(6, 4)
              ..lineTo(20, 12)
              ..lineTo(6, 20)
              ..close(),
            fill);
      case NextGlyph.close:
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), line);
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), line);
      case NextGlyph.pause:
        const r = Radius.circular(1.2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(6, 5, 4, 14), r), fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(14, 5, 4, 14), r),
            fill);
      case NextGlyph.chevronRight:
        canvas.drawPath(
            Path()
              ..moveTo(9, 6)
              ..lineTo(15, 12)
              ..lineTo(9, 18),
            line);
      case NextGlyph.chevronLeft:
        canvas.drawPath(
            Path()
              ..moveTo(15, 6)
              ..lineTo(9, 12)
              ..lineTo(15, 18),
            line);
      case NextGlyph.check:
        canvas.drawPath(
            Path()
              ..moveTo(5, 12.5)
              ..lineTo(10, 17)
              ..lineTo(19, 7),
            line);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.stroke != stroke;
}
