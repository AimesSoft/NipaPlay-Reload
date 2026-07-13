import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';

class CupertinoBottomSheetOption<T> {
  const CupertinoBottomSheetOption({
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.enabled = true,
    this.destructive = false,
  });

  final String label;
  final T value;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final bool destructive;
}

/// 通用的 Cupertino 风格上拉菜单容器
/// 提供标准的上拉菜单外观和行为，内容完全可自定义
class CupertinoBottomSheet extends StatelessWidget {
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

  /// 带子页面的上拉菜单使用此控制器同步标题和返回状态。
  final CupertinoBottomSheetPageController pageController;

  const CupertinoBottomSheet({
    super.key,
    required this.child,
    this.heightRatio = 0.94,
    this.showCloseButton = true,
    this.onClose,
    this.floatingTitle = false,
    required this.pageController,
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
    bool barrierDismissible = true,
    Color? barrierColor,
    CupertinoBottomSheetPageController? pageController,
    bool hideBottomBar = true,
  }) async {
    final displaySurface = AppDisplaySurfaceScope.of(context);
    // 隐藏底部导航栏
    final bottomBarProvider =
        Provider.of<BottomBarProvider>(context, listen: false);
    final ownsPageController = pageController == null;
    final effectivePageController = pageController ??
        CupertinoBottomSheetPageController(rootTitle: title ?? '');
    if (hideBottomBar) {
      bottomBarProvider.hideBottomBar();
    }

    try {
      final result = await showCupertinoModalPopup<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierColor: barrierColor ?? kCupertinoModalBarrierColor,
        builder: (BuildContext context) => AppDisplaySurfaceScope(
          surface: displaySurface,
          child: CupertinoBottomSheet(
            heightRatio: heightRatio,
            showCloseButton: showCloseButton,
            onClose: onClose,
            floatingTitle: floatingTitle,
            pageController: effectivePageController,
            child: child,
          ),
        ),
      );
      return result;
    } finally {
      // 恢复底部导航栏显示
      if (hideBottomBar) {
        bottomBarProvider.showBottomBar();
      }
      if (ownsPageController) {
        effectivePageController.dispose();
      }
    }
  }

  static Future<T?> showSelection<T>({
    required BuildContext context,
    required String title,
    required List<CupertinoBottomSheetOption<T>> options,
    double? heightRatio,
    bool hideBottomBar = true,
  }) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final contentHeight = 112.0 + options.length * 52.0;
    final effectiveHeightRatio = heightRatio ??
        (contentHeight / screenHeight).clamp(0.3, 0.82).toDouble();

    return show<T>(
      context: context,
      title: title,
      heightRatio: effectiveHeightRatio,
      hideBottomBar: hideBottomBar,
      child: CupertinoBottomSheetContentLayout(
        sliversBuilder: (context, topSpacing) => [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, topSpacing + 4, 12, 24),
            sliver: SliverToBoxAdapter(
              child: CupertinoListSection.insetGrouped(
                margin: EdgeInsets.zero,
                children: [
                  for (final option in options)
                    _CupertinoBottomSheetOptionTile<T>(option: option),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示带内部导航栈的上拉菜单。
  ///
  /// 根页面及其后续页面使用最近的 [Navigator]，因此子页面切换始终
  /// 发生在上拉菜单内部，不会把应用主界面替换成独立路由。
  static Future<T?> showPage<T>({
    required BuildContext context,
    required String title,
    required WidgetBuilder rootPageBuilder,
    double heightRatio = 0.94,
    bool showCloseButton = true,
    bool floatingTitle = true,
    bool barrierDismissible = true,
  }) async {
    final pageController = CupertinoBottomSheetPageController(
      rootTitle: title,
    );
    try {
      return await show<T>(
        context: context,
        title: title,
        heightRatio: heightRatio,
        showCloseButton: showCloseButton,
        floatingTitle: floatingTitle,
        barrierDismissible: barrierDismissible,
        pageController: pageController,
        child: CupertinoBottomSheetPageNavigator(
          controller: pageController,
          rootPageBuilder: rootPageBuilder,
        ),
      );
    } finally {
      pageController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, _) => _buildSheet(
        context,
        effectiveTitle: pageController.title,
        showBackButton: pageController.canPop,
      ),
    );
  }

  Widget _buildSheet(
    BuildContext context, {
    required String? effectiveTitle,
    required bool showBackButton,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final double effectiveHeightRatio = heightRatio.clamp(0.0, 1.0).toDouble();
    final double maxHeight = screenHeight * effectiveHeightRatio;
    final hasTitle = effectiveTitle != null && effectiveTitle.isNotEmpty;
    final bool displayHeader = hasTitle && !floatingTitle;

    final Widget content;
    if (displayHeader) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(
            context,
            effectiveTitle,
            showBackButton: showBackButton,
          ),
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
    final sheetBackground = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    return CupertinoBottomSheetScope(
      contentTopInset: contentTopInset,
      contentTopSpacing: contentTopSpacing,
      title: effectiveTitle,
      floatingTitle: floatingTitle && hasTitle,
      showBackButton: showBackButton,
      pageController: pageController,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
            height: maxHeight,
            color: sheetBackground,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Stack(
                children: [
                  Positioned.fill(child: content),
                  if (contentTopInset > 0)
                    _buildTopScrim(
                      backgroundColor: sheetBackground,
                      height: contentTopInset,
                    ),
                  if (floatingTitle && hasTitle)
                    _buildFloatingTitle(
                      context,
                      effectiveTitle,
                      showBackButton: showBackButton,
                      opacity: pageController.titleOpacity,
                    ),
                  if (showBackButton)
                    Positioned(
                      top: _closeButtonPadding,
                      left: _closeButtonPadding,
                      child: _buildBackButton(context),
                    ),
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

  Widget _buildTopScrim({
    required Color backgroundColor,
    required double height,
  }) {
    return Positioned(
      key: const ValueKey<String>('cupertino-bottom-sheet-top-scrim'),
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                backgroundColor,
                backgroundColor.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String effectiveTitle, {
    required bool showBackButton,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        showBackButton ? 68 : 20,
        showCloseButton ? 36 : 28,
        showCloseButton ? 68 : 20,
        8,
      ),
      child: Text(
        effectiveTitle,
        style: CupertinoTheme.of(context).textTheme.navTitleTextStyle.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildFloatingTitle(
    BuildContext context,
    String effectiveTitle, {
    required bool showBackButton,
    required double opacity,
  }) {
    return Positioned(
      top: 0,
      left: showBackButton ? 64 : 0,
      right: showCloseButton ? 64 : 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              effectiveTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildBackButton(BuildContext context) {
    final Color resolvedIconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final onPressed = pageController.maybePop;

    if (PlatformInfo.isIOS26OrHigher()) {
      return SizedBox.square(
        dimension: _closeButtonSize,
        child: AdaptiveButton.sfSymbol(
          useSmoothRectangleBorder: false,
          onPressed: onPressed,
          style: AdaptiveButtonStyle.glass,
          size: AdaptiveButtonSize.large,
          sfSymbol: SFSymbol(
            'chevron.left',
            size: 16,
            color: resolvedIconColor,
          ),
        ),
      );
    }

    return SizedBox.square(
      dimension: _closeButtonSize,
      child: _buildFallbackHeaderButton(
        context,
        label: '返回',
        icon: CupertinoIcons.chevron_back,
        iconSize: 18,
        onPressed: onPressed,
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
      child: _buildFallbackHeaderButton(
        context,
        label: '关闭',
        icon: CupertinoIcons.xmark,
        iconSize: 16,
        onPressed: onPressedCallback,
      ),
    );
  }

  Widget _buildFallbackHeaderButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required double iconSize,
    required VoidCallback onPressed,
  }) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final iconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    return GlassButton(
      label: label,
      icon: Icon(icon, size: iconSize, color: iconColor),
      onTap: onPressed,
      width: _closeButtonSize,
      height: _closeButtonSize,
      iconSize: iconSize,
      useOwnLayer: true,
      quality: GlassQuality.standard,
      shape: const LiquidOval(),
      settings: isLight
          ? _lightFallbackHeaderButtonSettings
          : _darkFallbackHeaderButtonSettings,
      stretch: 0.15,
      alignment: Alignment.center,
    );
  }

  static const _lightFallbackHeaderButtonSettings = LiquidGlassSettings(
    glassColor: Color(0xFFFFFFFF),
    backerColor: Color(0xFFFFFFFF),
    blur: 6,
    lightIntensity: 0.72,
    ambientStrength: 0.3,
    whitenStrength: 1,
    whitenGated: false,
  );

  static const _darkFallbackHeaderButtonSettings = LiquidGlassSettings(
    glassColor: Color(0x66000000),
    backerColor: Color(0xB3000000),
    blur: 6,
    lightIntensity: 0.38,
    ambientStrength: 0.2,
  );

  static const double _closeButtonPadding = 12;
  static const double _closeButtonSize = 40;
  static const double _floatingContentTopInsetWithClose = 44;
  static const double _floatingContentTopInset = 28;
  static const double _contentTopInsetWithClose = 28;
  static const double _floatingContentTopSpacing = 8;
}

class _CupertinoBottomSheetOptionTile<T> extends StatelessWidget {
  const _CupertinoBottomSheetOptionTile({required this.option});

  final CupertinoBottomSheetOption<T> option;

  @override
  Widget build(BuildContext context) {
    final labelColor = option.destructive
        ? CupertinoColors.destructiveRed
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final disabledColor = CupertinoDynamicColor.resolve(
      CupertinoColors.tertiaryLabel,
      context,
    );

    return CupertinoListTile(
      leading: option.icon == null
          ? null
          : Icon(
              option.icon,
              size: 20,
              color: option.enabled ? labelColor : disabledColor,
            ),
      title: Text(
        option.label,
        style: TextStyle(
          color: option.enabled ? labelColor : disabledColor,
        ),
      ),
      subtitle: option.subtitle == null ? null : Text(option.subtitle!),
      trailing: option.selected
          ? Icon(
              CupertinoIcons.check_mark,
              size: 18,
              color: CupertinoTheme.of(context).primaryColor,
            )
          : null,
      onTap: option.enabled
          ? () => Navigator.of(context).pop<T>(option.value)
          : null,
    );
  }
}

class CupertinoBottomSheetPageController extends ChangeNotifier {
  CupertinoBottomSheetPageController({required String rootTitle})
      : _rootTitle = rootTitle,
        _title = rootTitle;

  final String _rootTitle;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];
  late final NavigatorObserver observer =
      _CupertinoBottomSheetNavigatorObserver(this);

  String _title;
  bool _canPop = false;
  double _titleOpacity = 1;
  bool _disposed = false;

  String get title => _title;
  bool get canPop => _canPop;
  double get titleOpacity => _titleOpacity;

  void setTitleOpacity(double opacity) {
    if (_disposed) return;
    final nextOpacity = opacity.clamp(0.0, 1.0).toDouble();
    if ((nextOpacity - _titleOpacity).abs() < 0.001) return;
    _titleOpacity = nextOpacity;
    notifyListeners();
  }

  Future<void> maybePop() async {
    await navigatorKey.currentState?.maybePop();
  }

  void _didPush(Route<dynamic> route) {
    _routes.add(route);
    _sync();
  }

  void _didPop(Route<dynamic> route) {
    _routes.remove(route);
    _sync();
  }

  void _didRemove(Route<dynamic> route) {
    _routes.remove(route);
    _sync();
  }

  void _didReplace(Route<dynamic>? oldRoute, Route<dynamic>? newRoute) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _routes[index] = newRoute;
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    var nextTitle = _rootTitle;
    for (final route in _routes.reversed) {
      final routeTitle = route.settings.name;
      if (routeTitle != null && routeTitle.isNotEmpty && routeTitle != '/') {
        nextTitle = routeTitle;
        break;
      }
    }
    final nextCanPop = _routes.length > 1;
    if (nextTitle == _title && nextCanPop == _canPop) return;
    _title = nextTitle;
    _canPop = nextCanPop;
    _titleOpacity = 1;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _CupertinoBottomSheetNavigatorObserver extends NavigatorObserver {
  _CupertinoBottomSheetNavigatorObserver(this.controller);

  final CupertinoBottomSheetPageController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller._didPush(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller._didPop(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller._didRemove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    controller._didReplace(oldRoute, newRoute);
  }
}

class CupertinoBottomSheetPageScope
    extends InheritedNotifier<CupertinoBottomSheetPageController> {
  const CupertinoBottomSheetPageScope({
    super.key,
    required CupertinoBottomSheetPageController controller,
    required super.child,
  }) : super(notifier: controller);

  static CupertinoBottomSheetPageScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CupertinoBottomSheetPageScope>();
  }
}

class CupertinoBottomSheetPageNavigator extends StatelessWidget {
  const CupertinoBottomSheetPageNavigator({
    super.key,
    required this.controller,
    required this.rootPageBuilder,
  });

  final CupertinoBottomSheetPageController controller;
  final WidgetBuilder rootPageBuilder;

  static Future<T?> push<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
  }) {
    return Navigator.of(context).push<T>(
      CupertinoPageRoute<T>(
        settings: RouteSettings(name: title),
        builder: builder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoBottomSheetPageScope(
      controller: controller,
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: Navigator(
          key: controller.navigatorKey,
          observers: <NavigatorObserver>[controller.observer],
          onGenerateInitialRoutes: (_, __) => <Route<void>>[
            CupertinoPageRoute<void>(builder: rootPageBuilder),
          ],
        ),
      ),
    );
  }
}

class CupertinoBottomSheetScope extends InheritedWidget {
  final double contentTopInset;
  final double contentTopSpacing;
  final String? title;
  final bool floatingTitle;
  final bool showBackButton;
  final CupertinoBottomSheetPageController pageController;

  const CupertinoBottomSheetScope({
    required this.contentTopInset,
    required this.contentTopSpacing,
    required this.title,
    required this.floatingTitle,
    required this.showBackButton,
    required this.pageController,
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
        floatingTitle != oldWidget.floatingTitle ||
        showBackButton != oldWidget.showBackButton ||
        pageController != oldWidget.pageController;
  }
}

typedef CupertinoBottomSheetSliversBuilder = List<Widget> Function(
    BuildContext context, double contentTopSpacing);

/// 提供与上拉菜单视觉保持一致的滚动内容布局，
/// 自动处理顶部留白和渐变遮罩；标题由上拉菜单容器统一绘制。
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
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (scope != null && routeIsCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scope.pageController.setTitleOpacity(floatingTitleOpacity);
      });
    }
    final Color effectiveBackground = backgroundColor ??
        CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground,
          context,
        );

    final slivers = sliversBuilder(context, contentTopSpacing);
    return ColoredBox(
      color: effectiveBackground,
      child: CustomScrollView(
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
    );
  }
}
