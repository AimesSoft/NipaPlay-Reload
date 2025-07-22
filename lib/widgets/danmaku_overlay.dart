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
          final gpuConfig = GPUDanmakuConfig();
          
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
        // 🔥 新增：支持多弹幕来源的轨道管理
        // 获取所有启用的弹幕轨道
        final enabledTracks = <String, List<Map<String, dynamic>>>{};
        final tracks = videoState.danmakuTracks;
        final trackEnabled = videoState.danmakuTrackEnabled;
        
        // 只处理启用的轨道
        for (final trackId in tracks.keys) {
          if (trackEnabled[trackId] == true) {
            final trackData = tracks[trackId]!;
            final trackDanmaku = trackData['danmakuList'] as List<Map<String, dynamic>>;
            
            // 过滤当前时间窗口内的弹幕
            final currentTimeSeconds = widget.currentPosition / 1000;
            final activeDanmaku = trackDanmaku.where((d) {
              final t = d['time'] as double? ?? 0.0;
              return t >= currentTimeSeconds - 15.0 && t <= currentTimeSeconds + 15.0;
            }).toList();
            
            if (activeDanmaku.isNotEmpty) {
              enabledTracks[trackId] = activeDanmaku;
            }
          }
        }
        
        // 合并所有启用轨道的弹幕
        final List<Map<String, dynamic>> activeDanmakuList = [];
        for (final trackDanmaku in enabledTracks.values) {
          activeDanmakuList.addAll(trackDanmaku);
        }
        
        // 按时间排序
        activeDanmakuList.sort((a, b) {
          final timeA = (a['time'] ?? 0.0) as double;
          final timeB = (b['time'] ?? 0.0) as double;
          return timeA.compareTo(timeB);
        });

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