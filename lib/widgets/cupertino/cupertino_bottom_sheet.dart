import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

/// 通用的 Cupertino 风格上拉菜单容器
/// 提供标准的上拉菜单外观和行为，内容完全可自定义
class CupertinoBottomSheet extends StatelessWidget {
  /// 菜单标题（可选）
  final String? title;

  /// 菜单内容，完全可自定义
  final Widget child;

  /// 菜单高度占屏幕的比例，默认 0.88
  final double heightRatio;

  /// 是否显示关闭按钮，默认 true
  final bool showCloseButton;

  /// 自定义关闭按钮回调，如果为 null 则使用默认的 Navigator.pop()
  final VoidCallback? onClose;

  /// 标题是否浮动（浮动标题会随滚动渐隐，不占用布局空间），默认 false
  final bool floatingTitle;

  const CupertinoBottomSheet({
    super.key,
    this.title,
    required this.child,
    this.heightRatio = 0.92,
    this.showCloseButton = true,
    this.onClose,
    this.floatingTitle = false,
  });

  /// 显示上拉菜单的静态方法
  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    required Widget child,
    double heightRatio = 0.92,
    bool showCloseButton = true,
    VoidCallback? onClose,
    bool floatingTitle = false,
  }) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (BuildContext context) => CupertinoBottomSheet(
        title: title,
        heightRatio: heightRatio,
        showCloseButton: showCloseButton,
        onClose: onClose,
        floatingTitle: floatingTitle,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final double effectiveHeightRatio = heightRatio.clamp(0.0, 1.0).toDouble();
    final double maxHeight = screenHeight * effectiveHeightRatio;
    final hasTitle = title != null && title!.isNotEmpty;
    final bool displayHeader = hasTitle && !floatingTitle;

    final Widget content;
    if (displayHeader) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Expanded(child: child),
        ],
      );
    } else {
      content = child;
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          height: maxHeight,
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground,
            context,
          ),
          child: SafeArea(
            top: false,
            child: Stack(
              children: [
                Positioned.fill(child: content),
                if (showCloseButton)
                  Positioned(
                    top: _closeButtonPadding,
                    right: _closeButtonPadding,
                    child: _buildCloseButton(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        showCloseButton ? 36 : 28,
        showCloseButton ? 68 : 20,
        8,
      ),
      child: Text(
        title!,
        style: CupertinoTheme.of(context).textTheme.navTitleTextStyle.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return SizedBox(
      width: _closeButtonSize,
      height: _closeButtonSize,
      child: IOS26Button.child(
        onPressed: onClose ?? () => Navigator.of(context).pop(),
        style: IOS26ButtonStyle.glass,
        size: IOS26ButtonSize.large,
        child: Icon(
          CupertinoIcons.xmark,
          size: 24,
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.label,
            context,
          ),
        ),
      ),
    );
  }

  static const double _closeButtonPadding = 12;
  static const double _closeButtonSize = 36;
}
