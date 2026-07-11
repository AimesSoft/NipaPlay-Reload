import 'dart:ui' as ui;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_window_page.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:provider/provider.dart';

/// 一个通用的窗口脚手架，提供 Nipaplay 风格的视觉外观。
/// 包含：背景图片/模糊、点击背景关闭、阴影圆角容器。
class NipaplayWindowScaffold extends StatefulWidget {
  const NipaplayWindowScaffold({
    super.key,
    required this.child,
    this.backgroundImageUrl,
    this.backgroundColor,
    this.blurBackground = false,
    this.onClose,
    this.topRightAction,
    this.maxWidth = 850,
    this.maxHeightFactor = 0.8,
    this.showCloseButton = true,
    this.embedded = false,
  });

  final Widget child;
  final String? backgroundImageUrl;
  final Color? backgroundColor;
  final bool blurBackground;
  final VoidCallback? onClose;
  final Widget? topRightAction;
  final double maxWidth;
  final double maxHeightFactor;
  final bool showCloseButton;
  final bool embedded;

  @override
  State<NipaplayWindowScaffold> createState() => _NipaplayWindowScaffoldState();
}

class _NipaplayWindowScaffoldState extends State<NipaplayWindowScaffold> {
  Offset _offset = Offset.zero;
  static const double _contentTopPadding = 14;
  static const double _windowControlPadding = 5;
  static const double _windowControlGap = 6;
  static const double _windowedMargin = 20;
  static const double _filledScreenMargin = 10;
  bool _allowBackgroundDismiss = false;
  Animation<double>? _routeAnimation;
  void Function(AnimationStatus)? _routeStatusListener;

  @override
  void initState() {
    super.initState();
    _armDismissGuardIfNeeded();
  }

  @override
  void didUpdateWidget(covariant NipaplayWindowScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onClose == null && widget.onClose != null) {
      _armDismissGuardIfNeeded();
      return;
    }
    if (widget.onClose == null && oldWidget.onClose != null) {
      _detachRouteListener();
      _allowBackgroundDismiss = false;
    }
  }

  @override
  void dispose() {
    _detachRouteListener();
    super.dispose();
  }

  bool _useMacStyleCloseButton() {
    if (kIsWeb) {
      return false;
    }
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final isIPad =
        defaultTargetPlatform == TargetPlatform.iOS && globals.isTablet;
    return isMac || isIPad;
  }

  void _armDismissGuardIfNeeded() {
    if (widget.onClose == null) {
      _allowBackgroundDismiss = false;
      _detachRouteListener();
      return;
    }
    _allowBackgroundDismiss = false;
    _detachRouteListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.onClose == null) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null) {
        _allowBackgroundDismiss = true;
        return;
      }
      if (animation.status == AnimationStatus.completed) {
        _allowBackgroundDismiss = true;
        return;
      }
      _routeAnimation = animation;
      _routeStatusListener = (status) {
        if (status == AnimationStatus.completed) {
          _allowBackgroundDismiss = true;
          _detachRouteListener();
        }
      };
      animation.addStatusListener(_routeStatusListener!);
    });
  }

  void _handleBackgroundTap() {
    if (!_allowBackgroundDismiss) return;
    widget.onClose?.call();
  }

  void _detachRouteListener() {
    if (_routeAnimation != null && _routeStatusListener != null) {
      _routeAnimation!.removeStatusListener(_routeStatusListener!);
    }
    _routeAnimation = null;
    _routeStatusListener = null;
  }

  void _applyWindowOffset(Offset delta) {
    setState(() {
      _offset += delta;
    });
  }

  void _toggleWindowDisplayMode(AppearanceSettingsProvider settings) {
    final nextMode =
        settings.windowDisplayMode == NipaplayWindowDisplayMode.filledScreen
            ? NipaplayWindowDisplayMode.windowed
            : NipaplayWindowDisplayMode.filledScreen;
    if (_offset != Offset.zero) {
      setState(() {
        _offset = Offset.zero;
      });
    }
    settings.setWindowDisplayMode(nextMode);
  }

  VoidCallback _resolveCloseHandler(BuildContext context) {
    return widget.onClose ?? () => Navigator.of(context).maybePop();
  }

  Widget _buildMacCloseButton(BuildContext context) {
    final onClose = _resolveCloseHandler(context);
    final bool isTablet = globals.isTablet;
    final double hitSize = isTablet ? 36 : 28;
    final double buttonSize = isTablet ? 20 : 14;
    return Tooltip(
      message: '关闭',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: SizedBox(
          width: hitSize,
          height: hitSize,
          child: Center(
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: const Color(0xFFFF5F57),
                borderRadius: BorderRadius.circular(buttonSize / 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: isTablet ? 4 : 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFluentCloseButton(BuildContext context) {
    final onClose = _resolveCloseHandler(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isTablet = globals.isTablet;
    final double hitSize = isTablet ? 36 : 28;
    final double iconSize = isTablet ? 18 : 14;
    return Tooltip(
      message: '关闭',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: SizedBox(
          width: hitSize,
          height: hitSize,
          child: Center(
            child: Icon(
              fluent.FluentIcons.chrome_close,
              size: iconSize,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return widget.child;

    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final bool useFilledScreenLayout = appearanceSettings.windowDisplayMode ==
        NipaplayWindowDisplayMode.filledScreen;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = widget.backgroundColor ??
        (isDark ? const Color(0xFF2C2C2C) : Colors.white);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final bool useMacStyleCloseButton = _useMacStyleCloseButton();
    final Widget? topRightAction = widget.topRightAction;
    final bool showCloseButton = widget.showCloseButton;
    final bool usePhoneBottomSheetLayout = globals.isPhone && !globals.isTablet;
    final mediaQuery = MediaQuery.of(context);
    final EdgeInsets safePadding = mediaQuery.padding;
    final Size screenSize = mediaQuery.size;
    final double horizontalMargin =
        useFilledScreenLayout ? _filledScreenMargin : _windowedMargin;
    final double topMargin = safePadding.top + horizontalMargin;
    final double bottomMargin = useFilledScreenLayout
        ? safePadding.bottom + _filledScreenMargin
        : _windowedMargin;
    final double effectiveMaxWidth = useFilledScreenLayout
        ? (screenSize.width - horizontalMargin * 2).clamp(0.0, screenSize.width)
        : widget.maxWidth;
    final double effectiveMaxHeight = useFilledScreenLayout
        ? (screenSize.height - topMargin - bottomMargin)
            .clamp(0.0, screenSize.height)
        : screenSize.height * widget.maxHeightFactor;
    final double windowControlPadding =
        globals.isTablet ? _windowControlPadding + 3 : _windowControlPadding;
    final BorderRadius windowBorderRadius = BorderRadius.circular(15);

    final baseTheme = Theme.of(context);
    final windowTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
      ),
    );
    final windowTextStyle = DefaultTextStyle.of(context)
        .style
        .merge(windowTheme.textTheme.bodyMedium)
        .copyWith(color: textColor);

    if (usePhoneBottomSheetLayout) {
      final double maxSheetHeight = (screenSize.height - safePadding.top - 12)
          .clamp(0.0, screenSize.height);
      const BorderRadius sheetBorderRadius = BorderRadius.vertical(
        top: Radius.circular(24),
      );
      final Widget? phoneTopRightAction = topRightAction;

      return Theme(
        data: windowTheme,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose == null ? null : _handleBackgroundTap,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: screenSize.width,
                        maxWidth: screenSize.width,
                        maxHeight: maxSheetHeight * widget.maxHeightFactor,
                      ),
                      child: Material(
                        color: bgColor,
                        borderRadius: sheetBorderRadius,
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            if (widget.backgroundImageUrl != null &&
                                widget.backgroundImageUrl!.isNotEmpty)
                              Positioned.fill(
                                child: ImageFiltered(
                                  imageFilter: widget.blurBackground
                                      ? ui.ImageFilter.blur(
                                          sigmaX: 40,
                                          sigmaY: 40,
                                        )
                                      : ui.ImageFilter.blur(
                                          sigmaX: 0,
                                          sigmaY: 0,
                                        ),
                                  child: Opacity(
                                    opacity: isDark ? 0.25 : 0.35,
                                    child: CachedNetworkImageWidget(
                                      imageUrl: widget.backgroundImageUrl!,
                                      fit: BoxFit.cover,
                                      shouldCompress: false,
                                      loadMode: CachedImageLoadMode.hybrid,
                                    ),
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      bgColor.withValues(alpha: 0.1),
                                      bgColor.withValues(alpha: 0.4),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            DefaultTextStyle(
                              style: windowTextStyle,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: _contentTopPadding,
                                  bottom: safePadding.bottom,
                                ),
                                child: widget.child,
                              ),
                            ),
                            if (showCloseButton && phoneTopRightAction == null)
                              Positioned(
                                top: windowControlPadding,
                                right: windowControlPadding,
                                child: _buildFluentCloseButton(context),
                              ),
                            if (phoneTopRightAction != null)
                              Positioned(
                                top: windowControlPadding,
                                right: windowControlPadding,
                                child: showCloseButton
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          phoneTopRightAction,
                                          const SizedBox(
                                            width: _windowControlGap,
                                          ),
                                          _buildFluentCloseButton(context),
                                        ],
                                      )
                                    : phoneTopRightAction,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Theme(
      data: windowTheme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose == null ? null : _handleBackgroundTap,
          child: Stack(
            children: [
              Center(
                child: Transform.translate(
                  offset: _offset,
                  child: GestureDetector(
                    onTap: () {}, // 阻止点击内容区域时关闭
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: effectiveMaxWidth,
                        maxHeight: effectiveMaxHeight,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalMargin,
                          topMargin,
                          horizontalMargin,
                          bottomMargin,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: windowBorderRadius,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Material(
                            color: bgColor,
                            borderRadius: windowBorderRadius,
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              children: [
                                if (widget.backgroundImageUrl != null &&
                                    widget.backgroundImageUrl!.isNotEmpty)
                                  Positioned.fill(
                                    child: ImageFiltered(
                                      imageFilter: widget.blurBackground
                                          ? ui.ImageFilter.blur(
                                              sigmaX: 40, sigmaY: 40)
                                          : ui.ImageFilter.blur(
                                              sigmaX: 0, sigmaY: 0),
                                      child: Opacity(
                                        opacity: isDark ? 0.25 : 0.35,
                                        child: CachedNetworkImageWidget(
                                          imageUrl: widget.backgroundImageUrl!,
                                          fit: BoxFit.cover,
                                          shouldCompress: false,
                                          loadMode: CachedImageLoadMode.hybrid,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          bgColor.withValues(alpha: 0.1),
                                          bgColor.withValues(alpha: 0.4),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                DefaultTextStyle(
                                  style: windowTextStyle,
                                  child: NipaplayWindowPositionProvider(
                                    onMove: _applyWindowOffset,
                                    onToggleDisplayMode: () =>
                                        _toggleWindowDisplayMode(
                                      appearanceSettings,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        top: _contentTopPadding,
                                      ),
                                      child: widget.child,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: _contentTopPadding,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onDoubleTap: () => _toggleWindowDisplayMode(
                                      appearanceSettings,
                                    ),
                                    onPanUpdate: (details) =>
                                        _applyWindowOffset(details.delta),
                                  ),
                                ),
                                if (showCloseButton && useMacStyleCloseButton)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    child: _buildMacCloseButton(context),
                                  )
                                else if (showCloseButton &&
                                    topRightAction == null)
                                  Positioned(
                                    top: windowControlPadding,
                                    right: windowControlPadding,
                                    child: _buildFluentCloseButton(context),
                                  ),
                                if (topRightAction != null)
                                  Positioned(
                                    top: windowControlPadding,
                                    right: windowControlPadding,
                                    child: showCloseButton
                                        ? (useMacStyleCloseButton
                                            ? topRightAction
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  topRightAction,
                                                  const SizedBox(
                                                    width: _windowControlGap,
                                                  ),
                                                  _buildFluentCloseButton(
                                                    context,
                                                  ),
                                                ],
                                              ))
                                        : topRightAction,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 用于在窗口内容中处理拖动的手势提供者
class NipaplayWindowPositionProvider extends InheritedWidget {
  final Function(Offset delta) onMove;
  final VoidCallback onToggleDisplayMode;

  const NipaplayWindowPositionProvider({
    required this.onMove,
    required this.onToggleDisplayMode,
    required super.child,
    super.key,
  });

  static NipaplayWindowPositionProvider? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NipaplayWindowPositionProvider>();
  }

  @override
  bool updateShouldNotify(NipaplayWindowPositionProvider oldWidget) => false;
}

/// 窗口工具类，处理弹窗的显示逻辑（透明遮罩、入场动画）
class NipaplayWindow {
  /// 显示一个符合 Nipaplay 规范的窗口。
  /// 注意：child 内部通常应该包含 [NipaplayWindowScaffold] 以获得标准的窗口外观。
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool enableAnimation = true,
    bool barrierDismissible = true,
    Color barrierColor = Colors.transparent,
  }) {
    final bool useLargeScreenSubPage =
        NipaplayLargeScreenModeScope.isActiveOf(context);

    HotkeyService.overlayPush();

    Future<T?> result;
    if (useLargeScreenSubPage) {
      result = Navigator.of(context).push<T>(
        NipaplayLargeScreenWindowPageRoute<T>(
          builder: (_) => NipaplayLargeScreenContentPage(
            closeOnBack: true,
            child: child,
          ),
          enableAnimation: enableAnimation,
          dismissible: barrierDismissible,
        ),
      );
    } else {
      final bool usePhoneBottomSheetLayout =
          globals.isPhone && !globals.isTablet;
      result = showGeneralDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierColor: barrierColor,
        barrierLabel: 'Close',
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) => child,
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          if (!enableAnimation) {
            return FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              ),
              child: child,
            );
          }
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: usePhoneBottomSheetLayout
                ? Curves.easeOutCubic
                : Curves.easeOutBack,
          );
          if (usePhoneBottomSheetLayout) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          }
          return ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
      );
    }

    return result.whenComplete(() => HotkeyService.overlayPop());
  }
}
