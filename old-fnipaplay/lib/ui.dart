import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:fnipaplay/videos.dart';

class VideoPosa extends State<MyVideoPlayer> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('绘制圆角矩形示例'),
        ),
        body: CustomPaint(
          size: const Size(100, 3), // 指定画布大小
          painter: MyRectanglePainter(),
        ),
      ),
    );
  }
}

class MyRectanglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    // 定义圆角矩形的路径
    Path path = Path();
    path.moveTo(0, size.height); // 左下角起点
    path.lineTo(0, size.height - 1); // 左上角
    path.arcToPoint(Offset(3, size.height - 1),
        radius: const Radius.circular(1)); // 右上角
    path.lineTo(3, size.height); // 右下角
    path.close();

    // 绘制圆角矩形
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
class BlurTextContainer extends StatelessWidget {
  final String animeTitle;
  final String episodeTitle;
  final double iconOpacity;
  final Function(bool isHovering) onHover;

  const BlurTextContainer({
    super.key,
    required this.animeTitle,
    required this.episodeTitle,
    required this.iconOpacity,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(52, 0, 0, 0).withOpacity(0.1),
            offset: const Offset(2, 2),
            blurRadius: 10,
          ),
          BoxShadow(
            color: const Color.fromARGB(33, 0, 0, 0).withOpacity(0.1),
            offset: const Offset(-2, 2),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: MouseRegion(
              onEnter: (_) => onHover(true),
              onExit: (_) => onHover(false),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: iconOpacity,
                child: Text(
                  '$animeTitle $episodeTitle',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}