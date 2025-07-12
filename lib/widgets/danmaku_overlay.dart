import 'package:flutter/material.dart';
import 'danmaku_container.dart';
import 'canvas_danmaku_overlay.dart';
import '../danmaku_gpu/lib/gpu_danmaku_overlay.dart';
import '../danmaku_gpu/lib/gpu_danmaku_config.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../danmaku_abstraction/danmaku_kernel_factory.dart';

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
        final kernelType = DanmakuKernelFactory.getKernelType();

        if (kernelType == DanmakuKernelType.canvasDanmaku) {
          // 使用 Canvas_Danmaku 内核
          return CanvasDanmakuOverlay(
            currentPosition: widget.currentPosition,
            videoDuration: widget.videoDuration,
            isPlaying: widget.isPlaying,
            fontSize: widget.fontSize,
            isVisible: widget.isVisible,
            opacity: widget.opacity,
          );
        } else if (kernelType == DanmakuKernelType.flutterGPUDanmaku) {
          // 使用 Flutter GPU 内核
          final gpuConfig = GPUDanmakuConfig(
            fontSize: widget.fontSize,
            strokeWidth: 1.0,
            trackSpacing: 10.0,
            durationMultiplier: 1.0,
            trackHeightMultiplier: 1.5,
            verticalSpacing: 10.0,
            screenUsageRatio: 0.3,
          );
          
          return GPUDanmakuOverlay(
            currentPosition: widget.currentPosition.toInt(),
            videoDuration: widget.videoDuration.toInt(),
            isPlaying: widget.isPlaying,
            config: gpuConfig,
            isVisible: widget.isVisible,
            opacity: widget.opacity,
          );
        }

        // 默认使用 NipaPlay 内核
        final activeDanmakuList =
            videoState.getActiveDanmakuList(widget.currentPosition / 1000);

        return DanmakuContainer(
          danmakuList: activeDanmakuList,
          currentTime: widget.currentPosition / 1000, // 转换为秒
          videoDuration: widget.videoDuration / 1000, // 转换为秒
          fontSize: widget.fontSize,
          isVisible: widget.isVisible,
          opacity: widget.opacity,
          status: videoState.status, // 传递播放状态
          playbackRate: videoState.playbackRate, // 传递播放速度
        );
      },
    );
  }
} 