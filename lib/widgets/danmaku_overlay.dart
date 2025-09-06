import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'danmaku_container.dart';
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_overlay.dart';
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_config.dart';
import 'package:nipaplay/danmaku_canvas/canvas_danmaku_renderer.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/providers/settings_provider.dart';
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
  List<PositionedDanmakuItem> _positionedDanmaku = [];

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      // 弹幕不可见时，彻底不构建，避免文本排版消耗
      return const SizedBox.shrink();
    }
    return Consumer2<VideoPlayerState, SettingsProvider>(
      builder: (context, videoState, settingsProvider, child) {
        final kernelType = DanmakuKernelFactory.getKernelType();

        // 直接从videoState获取已处理好的弹幕列表
        final activeDanmakuList = videoState.danmakuList;

        if (kernelType == DanmakuRenderEngine.gpu) {
          return Stack(
            children: [
              // This container is off-screen, used only for layout calculation
              Offstage(
                offstage: true,
                child: DanmakuContainer(
                  danmakuList: activeDanmakuList,
                  currentTime: widget.currentPosition / 1000,
                  videoDuration: widget.videoDuration / 1000,
                  fontSize: widget.fontSize,
                  isVisible: widget.isVisible,
                  opacity: widget.opacity,
                  status: videoState.status.toString(),
                  playbackRate: videoState.playbackRate,
                  displayArea: videoState.danmakuDisplayArea,
                  timeOffset: settingsProvider.danmakuTimeOffset,
                  onLayoutCalculated: (danmaku) {
                    // Update state with the calculated positions
                    // a little hacky to avoid setState() called during build
                    Future.microtask(() {
                      if (mounted) {
                        setState(() {
                           _positionedDanmaku = danmaku;
                        });
                      }
                    });
                  },
                ),
              ),
              // This is the actual GPU renderer
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return GPUDanmakuOverlay(
                    positionedDanmaku: _positionedDanmaku,
                    isPlaying: widget.isPlaying,
                    config: GPUDanmakuConfig.fromVideoPlayerState(videoState),
                    isVisible: widget.isVisible,
                    opacity: widget.opacity,
                    currentTime: widget.currentPosition / 1000,
                  );
                },
              ),
            ],
          );
        }

        if (kernelType == DanmakuRenderEngine.canvas) {
          return CanvasDanmakuManager.createRenderer(
            fontSize: widget.fontSize,
            opacity: widget.opacity,
            displayArea: videoState.danmakuDisplayArea,
            visible: widget.isVisible,
            stacking: videoState.danmakuStacking,
            mergeDanmaku: videoState.mergeDanmaku,
            blockTopDanmaku: videoState.blockTopDanmaku,
            blockBottomDanmaku: videoState.blockBottomDanmaku,
            blockScrollDanmaku: videoState.blockScrollDanmaku,
            blockWords: videoState.danmakuBlockWords,
            currentTime: widget.currentPosition / 1000,
            isPlaying: widget.isPlaying,
            playbackRate: videoState.playbackRate,
          );
        }

        // Fallback to CPU rendering
        return DanmakuContainer(
          danmakuList: activeDanmakuList,
          currentTime: widget.currentPosition / 1000,
          videoDuration: widget.videoDuration / 1000,
          fontSize: widget.fontSize,
          isVisible: widget.isVisible,
          opacity: widget.opacity,
          status: videoState.status.toString(),
          playbackRate: videoState.playbackRate,
          displayArea: videoState.danmakuDisplayArea,
          timeOffset: settingsProvider.danmakuTimeOffset,
        );
      },
    );
  }
} 