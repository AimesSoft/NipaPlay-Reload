import 'dart:ui' as ui;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

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
  });

  final Widget child;
  final String? backgroundImageUrl;
  final Color? backgroundColor;
  final bool blurBackground;
  final VoidCallback? onClose;
  final Widget? topRightAction;
  final double maxWidth;
  final double maxHeightFactor;

  @override
  State<NipaplayWindowScaffold> createState() => _NipaplayWindowScaffoldState();
}

class _NipaplayWindowScaffoldState extends State<NipaplayWindowScaffold> {
  Offset _offset = Offset.zero;
  static const double _contentTopPadding = 14;
  static const double _windowControlPadding = 5;
  static const double _windowControlGap = 6;

  bool _useMacStyleCloseButton() {
    if (kIsWeb) {
      return false;
    }
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final isIPad =
        defaultTargetPlatform == TargetPlatform.iOS && globals.isTablet;
    return isMac || isIPad;
  }

  void _applyWindowOffset(Offset delta) {
    setState(() {
      _offset += delta;
    });
  }

  VoidCallback _resolveCloseHandler(BuildContext context) {
    return widget.onClose ?? () => Navigator.of(context).maybePop();
  }

  Widget _buildMacCloseButton(BuildContext context) {
    final onClose = _resolveCloseHandler(context);
    return Tooltip(
      message: '关闭',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFFFF5F57),
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 2,
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
    return Tooltip(
      message: '关闭',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Icon(
              fluent.FluentIcons.chrome_close,
              size: 14,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = widget.backgroundColor ??
        (isDark ? const Color(0xFF2C2C2C) : Colors.white);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final bool useMacStyleCloseButton = _useMacStyleCloseButton();
    final Widget? topRightAction = widget.topRightAction;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: textColor,
              displayColor: textColor,
            ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: Stack(
            children: [
              Center(
                child: Transform.translate(
                  offset: _offset,
                  child: GestureDetector(
                    onTap: () {}, // 阻止点击内容区域时关闭
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.maxWidth,
                        maxHeight: MediaQuery.of(context).size.height *
                            widget.maxHeightFactor,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          MediaQuery.of(context).padding.top + 20,
                          20,
                          20,
                        ),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
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
                                        bgColor.withOpacity(0.1),
                                        bgColor.withOpacity(0.4),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              DefaultTextStyle(
                                style: TextStyle(color: textColor),
                                child: NipaplayWindowPositionProvider(
                                  onMove: _applyWindowOffset,
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
                                  onPanUpdate: (details) =>
                                      _applyWindowOffset(details.delta),
                                ),
                              ),
                              if (useMacStyleCloseButton)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: _buildMacCloseButton(context),
                                )
                              else if (topRightAction == null)
                                Positioned(
                                  top: _windowControlPadding,
                                  right: _windowControlPadding,
                                  child: _buildFluentCloseButton(context),
                                ),
                              if (topRightAction != null)
                                Positioned(
                                  top: _windowControlPadding,
                                  right: _windowControlPadding,
                                  child: useMacStyleCloseButton
                                      ? topRightAction!
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            topRightAction!,
                                            const SizedBox(
                                              width: _windowControlGap,
                                            ),
                                            _buildFluentCloseButton(context),
                                          ],
                                        ),
                                ),
                            ],
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

  const NipaplayWindowPositionProvider({
    required this.onMove,
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
    return showGeneralDialog<T>(
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
          curve: Curves.easeOutBack,
        );
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
}
