// lib/utils/danmaku/style.dart
// 定义弹幕样式相关的枚举类型

/// 弹幕描边样式
enum DanmakuOutlineStyle {
  none, // 无描边
  stroke, // 描边
  uniform, // 均匀描边
}

/// 弹幕阴影样式
enum DanmakuShadowStyle {
  none, // 无阴影
  soft, // 柔化阴影
  medium, // 中等阴影
  strong, // 强烈阴影
}

/// 将描边宽度统一为播放器提供的三档渲染 profile：
/// 0 = 无描边、1 = 细边、2 = 粗边。
///
/// 旧版本曾允许保存 0–4 的连续值，因此这里也负责兼容迁移：任意正数
/// 至少保留为细边，1.5 及以上归入粗边。这里的 2 只是档位标识，
/// Next2/DFM+ 不会再把它当成 2 倍描边宽度直接传给 MSDF shader。
const double defaultDanmakuOutlineWidthLevel = 2.0;
const double defaultTvOSErikaDanmakuOutlineWidthLevel = 1.0;

double normalizeDanmakuOutlineWidthLevel(
  double? value, {
  double fallback = defaultDanmakuOutlineWidthLevel,
}) {
  if (value == null || !value.isFinite) {
    return fallback;
  }
  if (value <= 0.0) {
    return 0.0;
  }
  return value < 1.5 ? 1.0 : 2.0;
}
