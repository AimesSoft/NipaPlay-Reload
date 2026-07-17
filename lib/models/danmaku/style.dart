
// lib/models/danmaku/style.dart
// 弹幕样式


/// 弹幕的基础视觉样式.
///
/// [copyWith] 创建新实例.
class DanmakuStyle {

  // 弹幕透明度和描边宽度的范围
  static const double minOpacity      = 0.0;
  static const double maxOpacity      = 1.0;
  static const double minOutlineWidth = 0.5;
  static const double maxOutlineWidth = 5.0;

  double  _opacity;         // 弹幕透明度
  double  _outlineWidth;    // 弹幕描边宽度
  bool    _outlineEnabled;  // 弹幕描边是否启用

  /// 构造函数
  DanmakuStyle({
    double  opacity         = maxOpacity,
    double  outlineWidth    = 1.0,
    bool    outlineEnabled  = true,
  }) :
  _opacity        = _normalizeOpacity(opacity),
  _outlineWidth   = _normalizeOutlineWidth(outlineWidth),
  _outlineEnabled = outlineEnabled;


  // --- Getters and Setters --- //

  double get opacity => _opacity;
  set opacity(double value) => _opacity = _normalizeOpacity(value);

  double get outlineWidth => _outlineWidth;
  set outlineWidth(double value) =>
      _outlineWidth = _normalizeOutlineWidth(value);

  bool get outlineEnabled => _outlineEnabled;
  set outlineEnabled(bool value) {
    if (_outlineEnabled == value) return;
    _outlineEnabled = value;
  }

  DanmakuStyle copyWith({
    double? opacity,
    double? outlineWidth,
    bool  ? outlineEnabled,
  }) {
    return DanmakuStyle(
      opacity         : opacity         ?? _opacity,
      outlineWidth    : outlineWidth    ?? _outlineWidth,
      outlineEnabled  : outlineEnabled  ?? _outlineEnabled,
    );
  }


  static double _normalizeOpacity(double value) {
    if (!value.isFinite) return maxOpacity;
    return value.clamp(minOpacity, maxOpacity).toDouble();
  }

  static double _normalizeOutlineWidth(double value) {
    if (!value.isFinite) return 1.0;
    return value.clamp(minOutlineWidth, maxOutlineWidth).toDouble();
  }


  @override
  bool operator == (Object other) {
    return identical(this, other)           ||
    other is DanmakuStyle                   &&
    other._opacity == _opacity              &&
    other._outlineWidth == _outlineWidth    &&
    other._outlineEnabled == _outlineEnabled;
  }

  @override
  int get hashCode => Object.hash(_opacity, _outlineWidth, _outlineEnabled);
}
 