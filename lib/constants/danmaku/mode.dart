
// lib/constants/danmaku/mode.dart
// 弹幕模式


/// 弹幕协议中的显示模式.
///
/// 模式码沿用 Bilibili XML 与弹弹 play `p` 字段约定. 当前应用的标准类型
/// 只有滚动, 顶部和底部三类, 因此反向滚动与高级弹幕会降级为滚动类型.
enum DanmakuMode {

  scroll        (1, 'scroll'), // 滚动弹幕
  bottom        (4, 'bottom'), // 底部弹幕
  top           (5, 'top'   ), // 顶部弹幕
  reverseScroll (6, 'scroll'), // 反向弹幕
  advanced      (7, 'scroll'); // 高级弹幕

  const DanmakuMode(this.code, this.typeName);

  final int    code;     // 弹幕协议模式码
  final String typeName; // 弹幕标准类型名称

  /// 是否为滚动弹幕类型, 包括正向和反向滚动.
  bool get isScrolling => typeName == 'scroll';

  /// 从协议模式码读取弹幕模式, 未知模式按滚动弹幕处理.
  static DanmakuMode fromCode(int? code) {
    switch (code)
    {
    case  4: return DanmakuMode.bottom;
    case  5: return DanmakuMode.top;
    case  6: return DanmakuMode.reverseScroll;
    case  7: return DanmakuMode.advanced;
    case  1: return DanmakuMode.scroll;
    default: return DanmakuMode.scroll;
    }
  }

  /// 从标准类型名称读取弹幕模式, 未知名称按滚动弹幕处理.
  static DanmakuMode fromTypeName(String? typeName) {
    switch (typeName?.toLowerCase())
    {
    case 'bottom': return DanmakuMode.bottom;
    case 'top'   : return DanmakuMode.top;
    case 'scroll': return DanmakuMode.scroll;
    default      : return DanmakuMode.scroll;
    }
  }
}
