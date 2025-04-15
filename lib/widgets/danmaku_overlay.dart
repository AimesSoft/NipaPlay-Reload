import 'package:flutter/material.dart';
import 'danmaku_container.dart';

class DanmakuOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> danmakuList;
  final double currentPosition;
  final double videoDuration;
  final bool isPlaying;
  final double fontSize;
  final bool isVisible;
  final double opacity;

  const DanmakuOverlay({
    super.key,
    required this.danmakuList,
    required this.currentPosition,
    required this.videoDuration,
    required this.isPlaying,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  @override
  Widget build(BuildContext context) {
    return DanmakuContainer(
      danmakuList: widget.danmakuList,
      currentTime: widget.currentPosition / 1000, // 转换为秒
      videoDuration: widget.videoDuration / 1000, // 转换为秒
      fontSize: widget.fontSize,
      isVisible: widget.isVisible,
      opacity: widget.opacity,
    );
  }
} 