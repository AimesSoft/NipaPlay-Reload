import '../../utils/globals.dart' as globals;

/// GPU弹幕配置类
/// 
/// 包含GPU弹幕渲染的所有配置选项
class GPUDanmakuConfig {
  /// 字体大小
  final double fontSize;
  
  /// 描边粗细（像素）
  final double strokeWidth;
  
  /// 轨道间距（像素）
  final double trackSpacing;
  
  /// 弹幕持续时间倍数（默认1.0，表示5秒显示时间）
  final double durationMultiplier;
  
  /// 轨道高度倍数（相对于字体大小）
  final double trackHeightMultiplier;
  
  /// 垂直间距（像素）
  final double verticalSpacing;
  
  /// 顶部弹幕占用屏幕高度比例（0.1-1.0）
  final double screenUsageRatio;
  final double danmakuBottomMargin;

  GPUDanmakuConfig({
    double? fontSize,
    this.strokeWidth = 1.0,
    this.trackSpacing = 10.0,
    this.durationMultiplier = 1.0,
    this.trackHeightMultiplier = 1.5, // 默认1.0
    this.verticalSpacing = 0.0,       // 默认0.0
    this.screenUsageRatio = 1.0,      // 恢复为100%屏幕使用率
    this.danmakuBottomMargin = 10.0,
  }) : fontSize = fontSize ?? (globals.isPhone ? 20.0 : 30.0); // 动态默认字体大小



  /// 计算轨道高度
  double get trackHeight => fontSize * trackHeightMultiplier;
  
  /// 计算弹幕持续时间（毫秒）
  int get danmakuDuration => (5000 * durationMultiplier).round();
  
  /// 复制并修改配置
  GPUDanmakuConfig copyWith({
    double? fontSize,
    double? strokeWidth,
    double? trackSpacing,
    double? durationMultiplier,
    double? trackHeightMultiplier,
    double? verticalSpacing,
    double? screenUsageRatio,
  }) {
    return GPUDanmakuConfig(
      fontSize: fontSize ?? this.fontSize,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      trackSpacing: trackSpacing ?? this.trackSpacing,
      durationMultiplier: durationMultiplier ?? this.durationMultiplier,
      trackHeightMultiplier: trackHeightMultiplier ?? this.trackHeightMultiplier,
      verticalSpacing: verticalSpacing ?? this.verticalSpacing,
      screenUsageRatio: screenUsageRatio ?? this.screenUsageRatio,
    );
  }

  @override
  String toString() {
    return 'GPUDanmakuConfig('
        'fontSize: $fontSize, '
        'strokeWidth: $strokeWidth, '
        'trackSpacing: $trackSpacing, '
        'durationMultiplier: $durationMultiplier, '
        'trackHeightMultiplier: $trackHeightMultiplier, '
        'verticalSpacing: $verticalSpacing, '
        'screenUsageRatio: $screenUsageRatio)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GPUDanmakuConfig &&
        other.fontSize == fontSize &&
        other.strokeWidth == strokeWidth &&
        other.trackSpacing == trackSpacing &&
        other.durationMultiplier == durationMultiplier &&
        other.trackHeightMultiplier == trackHeightMultiplier &&
        other.verticalSpacing == verticalSpacing &&
        other.screenUsageRatio == screenUsageRatio;
  }

  @override
  int get hashCode {
    return Object.hash(
      fontSize,
      strokeWidth,
      trackSpacing,
      durationMultiplier,
      trackHeightMultiplier,
      verticalSpacing,
      screenUsageRatio,
    );
  }
} 