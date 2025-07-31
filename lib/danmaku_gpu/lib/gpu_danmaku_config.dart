import '../../utils/globals.dart' as globals;
import '../../utils/video_player_state.dart';

/// GPU弹幕配置类
///
/// 包含所有与GPU弹幕渲染相关的配置选项
class GPUDanmakuConfig {
  /// 字体大小
  final double fontSize;
  
  /// 弹幕持续时间倍数（默认1.0，表示5秒显示时间）
  final double durationMultiplier;
  
  /// 轨道高度倍数（相对于字体大小）
  final double trackHeightMultiplier;
  
  /// 弹幕底部外边距
  final double danmakuBottomMargin;

  /// 屏幕使用率（0.0 - 1.0）
  final double screenUsageRatio;

  /// 滚动弹幕速度（屏幕宽度/秒）
  final double scrollScreensPerSecond;

  GPUDanmakuConfig({
    double? fontSize,
    this.durationMultiplier = 1.0,
    this.trackHeightMultiplier = 1.5,
    this.danmakuBottomMargin = 10.0,
    this.screenUsageRatio = 1.0,
    this.scrollScreensPerSecond = 0.1,
  }) : fontSize = fontSize ?? (globals.isPhone ? 20.0 : 30.0);

  /// 从VideoPlayerState创建配置
  factory GPUDanmakuConfig.fromVideoPlayerState(VideoPlayerState videoState) {
    return GPUDanmakuConfig(
      fontSize: videoState.actualDanmakuFontSize,
      trackHeightMultiplier: videoState.danmakuTrackHeightMultiplier,
      screenUsageRatio: videoState.danmakuDisplayArea,
    );
  }

  /// 计算轨道高度
  double get trackHeight => fontSize * trackHeightMultiplier;
  
  /// 计算弹幕持续时间（毫秒）
  int get duration => (5000 * durationMultiplier).round();

  /// 复制配置并更新部分值
  GPUDanmakuConfig copyWith({
    double? fontSize,
    double? durationMultiplier,
    double? trackHeightMultiplier,
    double? danmakuBottomMargin,
    double? screenUsageRatio,
    double? scrollScreensPerSecond,
  }) {
    return GPUDanmakuConfig(
      fontSize: fontSize ?? this.fontSize,
      durationMultiplier: durationMultiplier ?? this.durationMultiplier,
      trackHeightMultiplier: trackHeightMultiplier ?? this.trackHeightMultiplier,
      danmakuBottomMargin: danmakuBottomMargin ?? this.danmakuBottomMargin,
      screenUsageRatio: screenUsageRatio ?? this.screenUsageRatio,
      scrollScreensPerSecond: scrollScreensPerSecond ?? this.scrollScreensPerSecond,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is GPUDanmakuConfig &&
        other.fontSize == fontSize &&
        other.durationMultiplier == durationMultiplier &&
        other.trackHeightMultiplier == trackHeightMultiplier &&
        other.danmakuBottomMargin == danmakuBottomMargin &&
        other.screenUsageRatio == screenUsageRatio &&
        other.scrollScreensPerSecond == scrollScreensPerSecond;
  }

  @override
  int get hashCode {
    return fontSize.hashCode ^
        durationMultiplier.hashCode ^
        trackHeightMultiplier.hashCode ^
        danmakuBottomMargin.hashCode ^
        screenUsageRatio.hashCode ^
        scrollScreensPerSecond.hashCode;
  }
} 