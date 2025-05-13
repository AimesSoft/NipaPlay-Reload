import 'package:flutter/material.dart';
import 'danmaku_container.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';

class DanmakuOverlay extends StatefulWidget {
  final double currentPosition;
  final double videoDuration;
  final bool isPlaying;
  final double fontSize;
  final bool isVisible;
  final double opacity;

  const DanmakuOverlay({
    super.key,
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
    // 使用Consumer包装，监听VideoPlayerState的变化
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 分批加载弹幕：只取当前窗口弹幕，并且应用过滤
        final activeDanmakuList = videoState.getActiveDanmakuList(widget.currentPosition / 1000);
        return DanmakuContainer(
          danmakuList: activeDanmakuList,
          currentTime: widget.currentPosition / 1000, // 转换为秒
          videoDuration: widget.videoDuration / 1000, // 转换为秒
          fontSize: widget.fontSize,
          isVisible: widget.isVisible,
          opacity: widget.opacity,
        );
      },
    );
  }
} 