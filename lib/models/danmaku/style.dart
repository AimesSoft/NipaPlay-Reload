
// lib/models/danmaku/style.dart
// 弹幕样式


/// 弹幕的基础视觉样式.
///
/// [copyWith] 创建新实例.
class DanmakuStyle {

  // 弹幕样式常数
  static const double minOpacity      = 0.0;
  static const double maxOpacity      = 1.0;
  static const double minOutlineWidth = 0.5; // 0 表示不启用描边
  static const double maxOutlineWidth = 5.0;

  static const double defDanmakuFontSize = 24.0;
  static const double minDanmakuFontSize = 12.0;
  static const double maxDanmakuFontSize = 60.0;

  double  _opacity;                // 弹幕透明度
  double  _outlineWidth;           // 弹幕描边宽度
  double  _danmakuFontSize;        // 弹幕字体大小
  double  _danmakuOffset;          // 弹幕时间偏移量 (秒)
  bool    _danmakuAllowStacking;   // 是否允许弹幕堆叠

  /// 构造函数
  DanmakuStyle({
    double  opacity                = maxOpacity,
    double  outlineWidth           = 1.0,
    double  danmakuFontSize        = DanmakuStyle.defDanmakuFontSize,
    double  danmakuOffset          = 0.0,
    bool    danmakuAllowStacking   = true,
  }) :
  _opacity                = _normalizeOpacity(opacity),
  _outlineWidth           = _normalizeOutlineWidth(outlineWidth),
  _danmakuFontSize        = _normalizeDanmakuFontSize(danmakuFontSize),
  _danmakuOffset          = _normalizeDanmakuOffset(danmakuOffset),
  _danmakuAllowStacking   = danmakuAllowStacking;


  // --- Getters and Setters --- //

  double get opacity => _opacity;
  set opacity(double value) => _opacity = _normalizeOpacity(value);

  double get outlineWidth => _outlineWidth;
  set outlineWidth(double value) =>
      _outlineWidth = _normalizeOutlineWidth(value);

  bool get outlineEnabled => _outlineWidth > 0.0;

  bool get danmakuAllowStacking => _danmakuAllowStacking;
  set danmakuAllowStacking(bool value) {
    if (_danmakuAllowStacking == value) return;
    _danmakuAllowStacking = value;
  }

  double get danmakuFontSize => _danmakuFontSize;
  set danmakuFontSize(double value) => _danmakuFontSize = _normalizeDanmakuFontSize(value);

  double get danmakuOffset => _danmakuOffset;
  set danmakuOffset(double value) => _danmakuOffset = _normalizeDanmakuOffset(value);

  DanmakuStyle copyWith({
    double? opacity,
    double? outlineWidth,
    double? danmakuFontSize,
    double? danmakuOffset,
    bool  ? danmakuAllowStacking,
  }) {
    return DanmakuStyle(
      opacity                 : opacity                 ?? _opacity,
      outlineWidth            : outlineWidth            ?? _outlineWidth,
      danmakuFontSize         : danmakuFontSize         ?? _danmakuFontSize,
      danmakuOffset           : danmakuOffset           ?? _danmakuOffset,
      danmakuAllowStacking    : danmakuAllowStacking    ?? _danmakuAllowStacking,
    );
  }


  static double _normalizeOpacity(double value) {
    if (!value.isFinite) return maxOpacity;
    return value.clamp(minOpacity, maxOpacity).toDouble();
  }

  static double _normalizeOutlineWidth(double value) {
    if (!value.isFinite) return 1.0;
    if (value <= 0.0) return 0.0;
    return value.clamp(minOutlineWidth, maxOutlineWidth).toDouble();
  }

  static double _normalizeDanmakuFontSize(double value) {
    if (!value.isFinite) return 24.0;
    return value.clamp(minDanmakuFontSize, maxDanmakuFontSize).toDouble();
  }

  static double _normalizeDanmakuOffset(double value) {
    return value.isFinite ? value : 0.0;
  }


  @override
  bool operator == (Object other) {
    return identical(this, other)           ||
    other is DanmakuStyle                   &&
    other._opacity == _opacity              &&
    other._outlineWidth == _outlineWidth    &&
    other._danmakuFontSize == _danmakuFontSize &&
    other._danmakuOffset == _danmakuOffset  &&
    other._danmakuAllowStacking == _danmakuAllowStacking;
  }

  @override
  int get hashCode => Object.hash(_opacity, _outlineWidth, _danmakuFontSize, _danmakuOffset, _danmakuAllowStacking);
}
