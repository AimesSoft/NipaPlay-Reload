export 'package:adaptive_platform_ui/adaptive_platform_ui.dart' hide AdaptiveSnackBar;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart'
    show AdaptiveSnackBarType;
import 'package:flutter/widgets.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';

/// 在 Cupertino 主题下劫持 AdaptiveSnackBar，统一使用 Nipaplay 的通知控件。
class AdaptiveSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    AdaptiveSnackBarType type = AdaptiveSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    String? action,
    VoidCallback? onActionPressed,
  }) {
    // 目前 Nipaplay 通知不区分类型颜色，直接沿用统一样式。
    BlurSnackBar.show(
      context,
      message,
      actionText: action,
      onAction: onActionPressed,
      duration: duration,
    );
  }
}
