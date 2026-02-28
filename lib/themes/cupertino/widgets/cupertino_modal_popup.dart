import 'package:flutter/cupertino.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:provider/provider.dart';

/// Cupertino 主题的上拉菜单统一入口：显示时隐藏底部导航，关闭时恢复。
Future<T?> showCupertinoModalPopupWithBottomBar<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) async {
  final bottomBarProvider = Provider.of<BottomBarProvider>(
    context,
    listen: false,
  );
  bottomBarProvider.hideBottomBar();

  try {
    return await showCupertinoModalPopup<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor:
          barrierColor ?? CupertinoColors.black.withValues(alpha: 0.35),
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
    );
  } finally {
    bottomBarProvider.showBottomBar();
  }
}
