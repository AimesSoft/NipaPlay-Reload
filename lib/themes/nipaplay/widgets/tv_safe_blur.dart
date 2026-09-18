import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// 电视设备上是否统一跳过昂贵的 backdrop 模糊。
///
/// 抽成顶层函数，方便在不引入 widget 依赖的地方复用
/// （例如 [CachedNetworkImageWidget] 判断要不要跳过淡入动画）。
bool get shouldSkipTvBackdropBlur => globals.isTelevision;

/// 在电视设备上自动降级为半透明色块的 [BackdropFilter] 替代品。
///
/// 为什么需要它：`BackdropFilter` 必须每帧重新捕获并模糊它下方的已渲染内容，
/// 无法缓存。σ22–40 的高斯在 Mali-450 级别的 GPU 上是纯填充率与内存带宽开销，
/// 而低端安卓电视/盒子（联发科方案，常见 32 位）正是这一类硬件。
///
/// 这些位置的真实视觉需求只是"面板底下压一层半透明底色"，
/// 关掉模糊后布局与配色完全不变，只是少了毛玻璃质感。
///
/// 用法与 `BackdropFilter` 一致；在电视上 [backdropFilter] 为空，
/// 直接返回 [child]，调用方自身的半透明背景色会照常生效。
class TvSafeBackdropFilter extends StatelessWidget {
  const TvSafeBackdropFilter({
    super.key,
    required this.filter,
    required this.child,
    this.enabled = true,
  });

  /// 非电视设备上使用的滤镜（通常是 `ImageFilter.blur`）。
  final ImageFilter filter;

  final Widget child;

  /// 调用方自己的开关；为 false 时无条件不模糊。
  final bool enabled;

  /// 是否在电视设备上跳过模糊。
  static bool get shouldSkipBlur => shouldSkipTvBackdropBlur;

  @override
  Widget build(BuildContext context) {
    if (!enabled || shouldSkipBlur) {
      return child;
    }
    return BackdropFilter(filter: filter, child: child);
  }
}
