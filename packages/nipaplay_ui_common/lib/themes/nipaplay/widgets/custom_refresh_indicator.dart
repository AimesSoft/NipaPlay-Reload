import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:glassmorphism/glassmorphism.dart';

class CustomRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final double displacement;
  final double edgeOffset;
  final Color? color;
  final double strokeWidth;
  final double blur;
  final double opacity;

  const CustomRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    this.color,
    this.strokeWidth = 2.0,
    this.blur = 10.0,
    this.opacity = 0.5,
  });

  @override
  State<CustomRefreshIndicator> createState() => _CustomRefreshIndicatorState();
}

class _CustomRefreshIndicatorState extends State<CustomRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.linear,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          _dragOffset = 0.0;
        } else if (notification is ScrollUpdateNotification) {
          if (notification.metrics.pixels < 0) {
            _dragOffset = -notification.metrics.pixels;
            setState(() {});
          }
        } else if (notification is ScrollEndNotification) {
          if (_dragOffset > widget.displacement && !_isRefreshing) {
            _isRefreshing = true;
            setState(() {});
            widget.onRefresh().then((_) {
              if (mounted) {
                setState(() {
                  _isRefreshing = false;
                  _dragOffset = 0.0;
                });
              }
            });
          } else {
            setState(() {
              _dragOffset = 0.0;
            });
          }
        }
        return true;
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragOffset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 40.0,
                alignment: Alignment.center,
                child: _buildRefreshIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRefreshIndicator() {
    final progress = math.min(1.0, _dragOffset / widget.displacement);
    final size = 40.0;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        // 毛玻璃背景
        GlassmorphicContainer(
          width: size,
          height: size,
          borderRadius: size / 2,
          blur: widget.blur,
          alignment: Alignment.center,
          border: 1,
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFffffff).withOpacity(0.1),
              const Color(0xFFFFFFFF).withOpacity(0.05),
            ],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFffffff).withOpacity(0.5),
              const Color((0xFFFFFFFF)).withOpacity(0.5),
            ],
          ),
        ),
        // 白色圆角指示条
        CustomPaint(
          size: Size(size, size),
          painter: CustomRefreshIndicatorPainter(
            value: _isRefreshing ? _animation.value : progress,
            color: widget.color ?? Colors.white,
            strokeWidth: widget.strokeWidth,
            blur: widget.blur,
            opacity: widget.opacity,
          ),
        ),
      ],
    );
  }
}

class CustomRefreshIndicatorPainter extends CustomPainter {
  final double value;
  final Color color;
  final double strokeWidth;
  final double blur;
  final double opacity;

  CustomRefreshIndicatorPainter({
    required this.value,
    required this.color,
    required this.strokeWidth,
    this.blur = 10.0,
    this.opacity = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth * 4;

    // 绘制圆形进度条
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomRefreshIndicatorPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.blur != blur ||
        oldDelegate.opacity != opacity;
  }
} 