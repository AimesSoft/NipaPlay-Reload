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
  check,
  plus,

  /// A file, a video, a torrent: what was dropped into the conversation.
  file,
  video,
  torrent,

  /// Another computer of the user's, as Finder draws one on the network.
  device,

  /// The library's forms: rows of previews, a grid of cards.
  rows,
  grid,

  /// What a row is dragged by.
  grip
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
      case NextGlyph.plus:
        canvas.drawLine(const Offset(12, 5), const Offset(12, 19), line);
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), line);
      case NextGlyph.file:
        canvas.drawPath(
            Path()
              ..moveTo(14, 3)
              ..lineTo(7, 3)
              ..quadraticBezierTo(5, 3, 5, 5)
              ..lineTo(5, 19)
              ..quadraticBezierTo(5, 21, 7, 21)
              ..lineTo(17, 21)
              ..quadraticBezierTo(19, 21, 19, 19)
              ..lineTo(19, 8)
              ..close()
              ..moveTo(14, 3)
              ..lineTo(14, 8)
              ..lineTo(19, 8),
            line);
      case NextGlyph.video:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3, 5, 18, 14), const Radius.circular(3)),
            line);
        canvas.drawPath(
            Path()
              ..moveTo(10, 9)
              ..lineTo(15, 12)
              ..lineTo(10, 15)
              ..close(),
            fill);
      case NextGlyph.torrent:
        canvas.drawPath(
            Path()
              ..moveTo(12, 4)
              ..lineTo(12, 14)
              ..moveTo(8, 10)
              ..lineTo(12, 14)
              ..lineTo(16, 10)
              ..moveTo(5, 15)
              ..lineTo(5, 19)
              ..lineTo(19, 19)
              ..lineTo(19, 15),
            line);
      case NextGlyph.device:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3, 4, 18, 12.5), const Radius.circular(2)),
            line);
        canvas.drawLine(const Offset(8.5, 20), const Offset(15.5, 20), line);
      case NextGlyph.rows:
        for (final y in [6.0, 12.0, 18.0]) {
          canvas.drawLine(Offset(4, y), Offset(20, y), line);
        }
      case NextGlyph.grid:
        for (final o in const [
          Offset(4, 4),
          Offset(13.5, 4),
          Offset(4, 13.5),
          Offset(13.5, 13.5)
        ]) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(o & const Size(6.5, 6.5),
                  const Radius.circular(1.6)),
              line);
        }
      case NextGlyph.grip:
        for (final x in [9.0, 15.0]) {
          for (final y in [6.0, 12.0, 18.0]) {
            canvas.drawCircle(Offset(x, y), 1.5, fill);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.stroke != stroke;
}
