class DanmakuOption {
  /// 默认的字体大小
  final double fontSize;

  /// 显示区域，0.1-1.0
  final double area;

  /// 滚动弹幕运行时间，秒
  final int duration;

  /// 不透明度，0.1-1.0
  final double opacity;

  /// 隐藏顶部弹幕
  final bool hideTop;

  /// 隐藏底部弹幕
  final bool hideBottom;

  /// 隐藏滚动弹幕
  final bool hideScroll;

  /// 弹幕描边
  final bool showStroke;

  /// 描边粗细（像素）- 与nipaPlay内核保持一致
  final double strokeWidth;

  /// 描边颜色 - 与nipaPlay内核保持一致
  final int strokeColor;

  /// 海量弹幕模式 (弹幕轨道占满时进行叠加)
  final bool massiveMode;

  /// 显示碰撞箱
  final bool showCollisionBoxes;

  /// 显示轨道编号
  final bool showTrackNumbers;

  DanmakuOption({
    this.fontSize = 16,
    this.area = 1.0,
    this.duration = 10,
    this.opacity = 1.0,
    this.hideBottom = false,
    this.hideScroll = false,
    this.hideTop = false,
    this.showStroke = true,
    this.strokeWidth = 1.0, // 与nipaPlay内核保持一致的默认值
    this.strokeColor = 0xFF000000, // 与nipaPlay内核保持一致的默认黑色描边
    this.massiveMode = false,
    this.showCollisionBoxes = false,
    this.showTrackNumbers = false,
  });

  DanmakuOption copyWith({
    double? fontSize,
    double? area,
    int? duration,
    double? opacity,
    bool? hideTop,
    bool? hideBottom,
    bool? hideScroll,
    bool? showStroke,
    double? strokeWidth,
    int? strokeColor,
    bool? massiveMode,
    bool? showCollisionBoxes,
    bool? showTrackNumbers,
  }) {
    return DanmakuOption(
      area: area ?? this.area,
      fontSize: fontSize ?? this.fontSize,
      duration: duration ?? this.duration,
      opacity: opacity ?? this.opacity,
      hideTop: hideTop ?? this.hideTop,
      hideBottom: hideBottom ?? this.hideBottom,
      hideScroll: hideScroll ?? this.hideScroll,
      showStroke: showStroke ?? this.showStroke,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeColor: strokeColor ?? this.strokeColor,
      massiveMode: massiveMode ?? this.massiveMode,
      showCollisionBoxes: showCollisionBoxes ?? this.showCollisionBoxes,
      showTrackNumbers: showTrackNumbers ?? this.showTrackNumbers,
    );
  }
}
