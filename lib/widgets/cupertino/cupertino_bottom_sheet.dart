import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

/// 通用的 Cupertino 风格上拉菜单容器
/// 提供标准的上拉菜单外观和行为，内容完全可自定义
class CupertinoBottomSheet extends StatelessWidget {
  /// 菜单标题
  final String title;

  /// 菜单内容，完全可自定义
  final Widget child;

  /// 菜单高度占屏幕的比例，默认 0.92
  final double heightRatio;

  /// 是否显示关闭按钮，默认 true
  final bool showCloseButton;

  /// 自定义关闭按钮回调，如果为 null 则使用默认的 Navigator.pop()
  final VoidCallback? onClose;

  const CupertinoBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.heightRatio = 0.92,
    this.showCloseButton = true,
    this.onClose,
  });

  /// 显示上拉菜单的静态方法
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    double heightRatio = 0.92,
    bool showCloseButton = true,
    VoidCallback? onClose,
  }) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (BuildContext context) => CupertinoBottomSheet(
        title: title,
        child: child,
        heightRatio: heightRatio,
        showCloseButton: showCloseButton,
        onClose: onClose,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * heightRatio;

    return Container(
      height: maxHeight,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground,
          context,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 顶部标题栏
          _buildHeader(context),
          // 可自定义的内容区域
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: CupertinoTheme.of(context).textTheme.navTitleTextStyle?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (showCloseButton)
            SizedBox(
              width: 36,
              height: 36,
              child: IOS26Button.child(
                onPressed: onClose ?? () => Navigator.of(context).pop(),
                style: IOS26ButtonStyle.glass,
                size: IOS26ButtonSize.large,
                child: Icon(
                  CupertinoIcons.xmark,
                  size: 24,
                  color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}