import 'package:flutter/material.dart';

class CrtEffect extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const CrtEffect({
    super.key,
    required this.child,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const IgnorePointer(
          child: CustomPaint(
            painter: _CrtOverlayPainter(),
          ),
        ),
      ],
    );
  }
}

class _CrtOverlayPainter extends CustomPainter {
  const _CrtOverlayPainter();

  static const double _lineHeight = 1.0;
  static const double _lineSpacing = 2.0;
  static const Color _scanlineColor = Color(0x1A000000);
  static const RadialGradient _vignette = RadialGradient(
    radius: 0.9,
    colors: [
      Colors.transparent,
      Color(0x55000000),
    ],
    stops: [0.6, 1.0],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = _scanlineColor
      ..isAntiAlias = false;
    final double step = _lineHeight + _lineSpacing;

    for (double y = 0; y < size.height; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, _lineHeight), linePaint);
    }

    final Rect rect = Offset.zero & size;
    final Paint vignettePaint = Paint()..shader = _vignette.createShader(rect);
    canvas.drawRect(rect, vignettePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
