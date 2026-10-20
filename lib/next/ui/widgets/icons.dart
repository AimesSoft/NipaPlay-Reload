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
  grip,

  /// The player's controls.
  volume,
  muted,
  danmaku,
  danmakuOff,
  subtitles,
  episodes,
  nextEpisode,
  fullscreen,
  exitFullscreen
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
      case NextGlyph.volume || NextGlyph.muted:
        canvas.drawPath(
            Path()
              ..moveTo(4, 9.5)
              ..lineTo(7.5, 9.5)
              ..lineTo(12, 5.5)
              ..lineTo(12, 18.5)
              ..lineTo(7.5, 14.5)
              ..lineTo(4, 14.5)
              ..close(),
            line);
        if (glyph == NextGlyph.volume) {
          canvas.drawPath(
              Path()
                ..moveTo(15.5, 9)
                ..quadraticBezierTo(17.5, 12, 15.5, 15)
                ..moveTo(18.2, 6.5)
                ..quadraticBezierTo(22, 12, 18.2, 17.5),
              line);
        } else {
          canvas.drawLine(const Offset(16, 9.5), const Offset(21, 14.5), line);
          canvas.drawLine(const Offset(21, 9.5), const Offset(16, 14.5), line);
        }
      case NextGlyph.danmaku || NextGlyph.danmakuOff:
        // A speech bubble: what viewers say over the picture.
        canvas.drawPath(
            Path()
              ..moveTo(7.5, 4)
              ..lineTo(16.5, 4)
              ..quadraticBezierTo(21, 4, 21, 8.5)
              ..lineTo(21, 12.5)
              ..quadraticBezierTo(21, 17, 16.5, 17)
              ..lineTo(11, 17)
              ..lineTo(6.5, 20.5)
              ..lineTo(7, 17)
              ..quadraticBezierTo(3, 16.6, 3, 12.5)
              ..lineTo(3, 8.5)
              ..quadraticBezierTo(3, 4, 7.5, 4)
              ..close(),
            line);
        for (final x in const [8.0, 12.0, 16.0]) {
          canvas.drawCircle(Offset(x, 10.5), 1.25, fill);
        }
        if (glyph == NextGlyph.danmakuOff) {
          canvas.drawLine(const Offset(3.5, 3), const Offset(20.5, 21), line);
        }
      case NextGlyph.subtitles:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3, 5, 18, 14), const Radius.circular(3.5)),
            line);
        canvas.drawLine(const Offset(7, 12), const Offset(10.5, 12), line);
        canvas.drawLine(const Offset(13.5, 12), const Offset(17, 12), line);
        canvas.drawLine(const Offset(7, 15.5), const Offset(14, 15.5), line);
      case NextGlyph.episodes:
        // Cards stacked: one season's episodes.
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3, 9, 18, 11), const Radius.circular(2.5)),
            line);
        canvas.drawLine(const Offset(5.5, 5.8), const Offset(18.5, 5.8), line);
        canvas.drawLine(const Offset(8, 2.8), const Offset(16, 2.8), line);
      case NextGlyph.nextEpisode:
        canvas.drawPath(
            Path()
              ..moveTo(5, 5)
              ..lineTo(15, 12)
              ..lineTo(5, 19)
              ..close(),
            fill);
        canvas.drawLine(const Offset(18.5, 5.5), const Offset(18.5, 18.5), line);
      case NextGlyph.fullscreen:
        canvas.drawPath(
            Path()
              ..moveTo(4, 9)
              ..lineTo(4, 4)
              ..lineTo(9, 4)
              ..moveTo(15, 4)
              ..lineTo(20, 4)
              ..lineTo(20, 9)
              ..moveTo(20, 15)
              ..lineTo(20, 20)
              ..lineTo(15, 20)
              ..moveTo(9, 20)
              ..lineTo(4, 20)
              ..lineTo(4, 15),
            line);
      case NextGlyph.exitFullscreen:
        canvas.drawPath(
            Path()
              ..moveTo(9, 4)
              ..lineTo(9, 9)
              ..lineTo(4, 9)
              ..moveTo(20, 9)
              ..lineTo(15, 9)
              ..lineTo(15, 4)
              ..moveTo(15, 20)
              ..lineTo(15, 15)
              ..lineTo(20, 15)
              ..moveTo(4, 15)
              ..lineTo(9, 15)
              ..lineTo(9, 20),
            line);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.stroke != stroke;
}
