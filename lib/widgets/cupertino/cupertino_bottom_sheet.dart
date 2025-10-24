import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';

/// 通用的 Cupertino 风格上拉菜单容器
/// 提供标准的上拉菜单外观和行为，内容完全可自定义
class CupertinoBottomSheet extends StatelessWidget {
  /// 菜单标题（可选）
  final String? title;

  /// 菜单内容，完全可自定义
  final Widget child;

  /// 菜单高度占屏幕的比例，默认 0.94
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
    this.heightRatio = 0.94,
    this.showCloseButton = true,
    this.onClose,
    this.floatingTitle = false,
  });

  /// 显示上拉菜单的静态方法
  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    required Widget child,
    double heightRatio = 0.94,
    bool showCloseButton = true,
    VoidCallback? onClose,
    bool floatingTitle = false,
  }) async {
    // 隐藏底部导航栏
    final bottomBarProvider = Provider.of<BottomBarProvider>(context, listen: false);
    bottomBarProvider.hideBottomBar();

    try {
      final result = await showCupertinoModalPopup<T>(
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
      return result;
    } finally {
      // 恢复底部导航栏显示
      bottomBarProvider.showBottomBar();
    }
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

    final double contentTopInset = displayHeader
        ? 0
        : floatingTitle
            ? (showCloseButton
                ? _floatingContentTopInsetWithClose
                : _floatingContentTopInset)
            : (showCloseButton ? _contentTopInsetWithClose : 0);
    final double contentTopSpacing =
        !displayHeader && floatingTitle ? _floatingContentTopSpacing : 0;

    return CupertinoBottomSheetScope(
      contentTopInset: contentTopInset,
      contentTopSpacing: contentTopSpacing,
      title: title,
      floatingTitle: floatingTitle && hasTitle,
      child: Align(
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
              bottom: false,
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
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    final Color resolvedIconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );

    final onPressedCallback = onClose ?? () => Navigator.of(context).pop();

    if (PlatformInfo.isIOS26OrHigher()) {
      return SizedBox(
        width: _closeButtonSize,
        height: _closeButtonSize,
        child: AdaptiveButton.sfSymbol(
          useSmoothRectangleBorder: false,
          onPressed: onPressedCallback,
          style: AdaptiveButtonStyle.glass,
          size: AdaptiveButtonSize.large,
          sfSymbol: SFSymbol('xmark', size: 16, color: resolvedIconColor),
        ),
      );
    }

    return SizedBox(
      width: _closeButtonSize,
      height: _closeButtonSize,
      child: AdaptiveButton.child(
        useSmoothRectangleBorder: false,
        onPressed: onPressedCallback,
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        child: Icon(
          CupertinoIcons.xmark,
          size: 16,
          color: resolvedIconColor,
        ),
      ),
    );
  }

  static const double _closeButtonPadding = 12;
  static const double _closeButtonSize = 40;
  static const double _floatingContentTopInsetWithClose = 44;
  static const double _floatingContentTopInset = 28;
  static const double _contentTopInsetWithClose = 28;
  static const double _floatingContentTopSpacing = 8;
}

class CupertinoBottomSheetScope extends InheritedWidget {
  final double contentTopInset;
  final double contentTopSpacing;
  final String? title;
  final bool floatingTitle;

  const CupertinoBottomSheetScope({
    required this.contentTopInset,
    required this.contentTopSpacing,
    required this.title,
    required this.floatingTitle,
    required super.child,
    super.key,
  });

  static CupertinoBottomSheetScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CupertinoBottomSheetScope>();
  }

  @override
  bool updateShouldNotify(covariant CupertinoBottomSheetScope oldWidget) {
    return contentTopInset != oldWidget.contentTopInset ||
        contentTopSpacing != oldWidget.contentTopSpacing ||
        title != oldWidget.title ||
        floatingTitle != oldWidget.floatingTitle;
  }
}

typedef CupertinoBottomSheetSliversBuilder = List<Widget> Function(
    BuildContext context, double contentTopSpacing);

/// 提供与上拉菜单视觉保持一致的滚动内容布局，
/// 自动处理顶部留白、渐变遮罩以及浮动标题。
class CupertinoBottomSheetContentLayout extends StatelessWidget {
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final Color? backgroundColor;
  final double floatingTitleOpacity;
  final CupertinoBottomSheetSliversBuilder sliversBuilder;

  const CupertinoBottomSheetContentLayout({
    super.key,
    this.controller,
    this.physics,
    this.backgroundColor,
    this.floatingTitleOpacity = 1.0,
    required this.sliversBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final scope = CupertinoBottomSheetScope.maybeOf(context);
    final double contentTopInset = scope?.contentTopInset ?? 0;
    final double contentTopSpacing = scope?.contentTopSpacing ?? 0;
    final bool showFloatingTitle =
        (scope?.floatingTitle ?? false) && (scope?.title?.isNotEmpty ?? false);
    final String? title = scope?.title;

    final Color effectiveBackground = backgroundColor ??
        CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground,
          context,
        );

    final slivers = sliversBuilder(context, contentTopSpacing);
    final double effectiveFloatingTitleOpacity =
        floatingTitleOpacity.clamp(0.0, 1.0).toDouble();

    return ColoredBox(
      color: effectiveBackground,
      child: Stack(
        children: [
          CustomScrollView(
            controller: controller,
            physics: physics ??
                const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
            slivers: [
              if (contentTopInset > 0)
                SliverToBoxAdapter(
                  child: SizedBox(height: contentTopInset / 1.3),
                ),
              ...slivers,
            ],
          ),
          if (contentTopInset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: contentTopInset,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        effectiveBackground,
                        effectiveBackground.withOpacity(0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          if (showFloatingTitle && title != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: effectiveFloatingTitleOpacity,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 68, 0),
                    child: Text(
                      title,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .navTitleTextStyle
                          .copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
