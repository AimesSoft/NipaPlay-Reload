import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 弹幕密度数据点
class DanmakuDensityPoint {
  final double timePosition; // 0.0 到 1.0，表示在视频中的位置比例
  final int count; // 该时间点的弹幕数量

  const DanmakuDensityPoint({
    required this.timePosition,
    required this.count,
  });
}

/// 弹幕密度曲线图组件
/// 类似B站播放器底部的弹幕密度条
class DanmakuDensityChart extends StatelessWidget {
  /// 弹幕密度数据点列表
  final List<DanmakuDensityPoint> densityData;
  
  /// 图表高度
  final double height;
  
  /// 图表宽度
  final double? width;
  
  /// 曲线颜色
  final Color curveColor;
  
  /// 填充渐变色
  final List<Color>? fillGradientColors;
  
  /// 背景色
  final Color backgroundColor;
  
  /// 是否显示网格线
  final bool showGrid;
  
  /// 网格线颜色
  final Color gridColor;
  
  /// 曲线线宽
  final double strokeWidth;
  
  /// 当前播放位置 (0.0 到 1.0)
  final double? currentPosition;
  
  /// 播放位置指示器颜色
  final Color positionIndicatorColor;

  const DanmakuDensityChart({
    super.key,
    required this.densityData,
    this.height = 60.0,
    this.width,
    this.curveColor = Colors.white70,
    this.fillGradientColors,
    this.backgroundColor = Colors.transparent,
    this.showGrid = false,
    this.gridColor = Colors.white12,
    this.strokeWidth = 1.5,
    this.currentPosition,
    this.positionIndicatorColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    if (densityData.isEmpty) {
      return Container(
        height: height,
        width: width,
        color: backgroundColor,
        child: const Center(
          child: Text(
            '暂无弹幕数据',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Container(
      height: height,
      width: width,
      color: backgroundColor,
      child: CustomPaint(
        size: Size.infinite,
        painter: DanmakuDensityPainter(
          densityData: densityData,
          curveColor: curveColor,
          fillGradientColors: fillGradientColors ?? [
            curveColor.withValues(alpha: 0.3),
            curveColor.withValues(alpha: 0.0),
          ],
          showGrid: showGrid,
          gridColor: gridColor,
          strokeWidth: strokeWidth,
          currentPosition: currentPosition,
          positionIndicatorColor: positionIndicatorColor,
        ),
      ),
    );
  }
}

/// 弹幕密度图表绘制器
class DanmakuDensityPainter extends CustomPainter {
  final List<DanmakuDensityPoint> densityData;
  final Color curveColor;
  final List<Color> fillGradientColors;
  final bool showGrid;
  final Color gridColor;
  final double strokeWidth;
  final double? currentPosition;
  final Color positionIndicatorColor;

  DanmakuDensityPainter({
    required this.densityData,
    required this.curveColor,
    required this.fillGradientColors,
    required this.showGrid,
    required this.gridColor,
    required this.strokeWidth,
    this.currentPosition,
    required this.positionIndicatorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (densityData.isEmpty || size.width <= 0 || size.height <= 0) return;

    // 找到最大弹幕数量用于归一化
    final maxCount = densityData.map((e) => e.count).reduce(math.max);
    if (maxCount == 0) return;

    // 绘制网格线
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    // 绘制填充区域
    _drawFillArea(canvas, size, maxCount);

    // 绘制曲线
    _drawCurve(canvas, size, maxCount);

    // 绘制当前播放位置指示器
    if (currentPosition != null) {
      _drawPositionIndicator(canvas, size);
    }
  }

  /// 绘制网格线
  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    // 垂直网格线 (时间轴)
    for (int i = 0; i <= 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // 水平网格线 (密度轴)
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  /// 绘制填充区域
  void _drawFillArea(Canvas canvas, Size size, int maxCount) {
    if (fillGradientColors.isEmpty) return;

    final path = Path();
    final points = _calculatePoints(size, maxCount);

    if (points.isEmpty) return;

    // 构建填充路径
    path.moveTo(points.first.dx, size.height);
    for (final point in points) {
      path.lineTo(point.dx, point.dy);
    }
    path.lineTo(points.last.dx, size.height);
    path.close();

    // 创建渐变
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: fillGradientColors,
    );

    final paint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path, paint);
  }

  /// 绘制曲线
  void _drawCurve(Canvas canvas, Size size, int maxCount) {
    final paint = Paint()
      ..color = curveColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final points = _calculatePoints(size, maxCount);

    if (points.isEmpty) return;

    path.moveTo(points.first.dx, points.first.dy);

    // 使用贝塞尔曲线平滑连接点
    for (int i = 1; i < points.length; i++) {
      final current = points[i];
      final previous = points[i - 1];
      
      // 计算控制点以创建平滑曲线
      final controlPoint1 = Offset(
        previous.dx + (current.dx - previous.dx) * 0.3,
        previous.dy,
      );
      final controlPoint2 = Offset(
        current.dx - (current.dx - previous.dx) * 0.3,
        current.dy,
      );

      path.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        current.dx,
        current.dy,
      );
    }

    canvas.drawPath(path, paint);
  }

  /// 绘制当前播放位置指示器
  void _drawPositionIndicator(Canvas canvas, Size size) {
    if (currentPosition == null) return;

    final x = size.width * currentPosition!;
    final paint = Paint()
      ..color = positionIndicatorColor
      ..strokeWidth = 1.5;

    // 绘制垂直指示线
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      paint,
    );

    // 绘制顶部小三角形
    final trianglePath = Path();
    trianglePath.moveTo(x - 4, 0);
    trianglePath.lineTo(x + 4, 0);
    trianglePath.lineTo(x, 6);
    trianglePath.close();

    canvas.drawPath(trianglePath, paint..style = PaintingStyle.fill);
  }

  /// 计算曲线上的点坐标
  List<Offset> _calculatePoints(Size size, int maxCount) {
    final points = <Offset>[];

    for (final dataPoint in densityData) {
      final x = size.width * dataPoint.timePosition;
      final normalizedHeight = dataPoint.count / maxCount;
      final y = size.height * (1.0 - normalizedHeight * 0.9); // 留10%顶部边距

      points.add(Offset(x, y));
    }

    return points;
  }

  @override
  bool shouldRepaint(covariant DanmakuDensityPainter oldDelegate) {
    return densityData != oldDelegate.densityData ||
        curveColor != oldDelegate.curveColor ||
        currentPosition != oldDelegate.currentPosition ||
        fillGradientColors != oldDelegate.fillGradientColors;
  }
}