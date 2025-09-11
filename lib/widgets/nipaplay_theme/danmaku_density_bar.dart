import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import '../danmaku_density_chart.dart';
import '../../services/danmaku_density_analyzer.dart';

class DanmakuDensityBar extends StatelessWidget {
  const DanmakuDensityBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        if (!videoState.hasVideo || !videoState.showDanmakuDensityChart) {
          return const SizedBox.shrink();
        }
        
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SizedBox(
            height: 20,
            child: _buildDanmakuDensityChart(videoState),
          ),
        );
      },
    );
  }

  /// 构建弹幕密度曲线图
  Widget _buildDanmakuDensityChart(VideoPlayerState videoState) {
    // 如果没有弹幕数据或视频时长为0，则不显示
    if (videoState.danmakuList.isEmpty || videoState.duration.inSeconds <= 0) {
      return const SizedBox.shrink();
    }

    // 分析弹幕密度
    final densityPoints = DanmakuDensityAnalyzer.analyzeDensity(
      danmakuList: videoState.danmakuList,
      videoDurationSeconds: videoState.duration.inSeconds,
      segmentCount: 150, // 适中的精度
    );

    // 如果没有密度数据，则不显示
    if (densityPoints.isEmpty) {
      return const SizedBox.shrink();
    }

    // 平滑处理
    final smoothedPoints = DanmakuDensityAnalyzer.smoothDensityData(
      densityPoints: densityPoints,
      windowSize: 3,
    );

    return DanmakuDensityChart(
      densityData: smoothedPoints,
      height: 20,
      curveColor: videoState.minimalProgressBarColor.withValues(alpha: 0.9),
      fillGradientColors: [
        videoState.minimalProgressBarColor.withValues(alpha: 0.4),
        videoState.minimalProgressBarColor.withValues(alpha: 0.0),
      ],
      backgroundColor: Colors.transparent,
      currentPosition: null,
      strokeWidth: 1.5,
    );
  }
}