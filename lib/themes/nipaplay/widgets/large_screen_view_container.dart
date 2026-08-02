import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_window_page.dart';
import 'package:nipaplay/utils/hotkey_service.dart';

/// 大屏幕模式下承载二级页面的统一容器。
///
/// 桌面端使用虚拟窗口、手机端使用上拉页面；电视端则通过这个容器把二级
/// 内容放进一个有明确边界、可用遥控器关闭的全屏浮层中。
class NipaplayLargeScreenViewContainer extends StatelessWidget {
  const NipaplayLargeScreenViewContainer({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onClose,
    this.maxWidth = 1280,
    this.maxHeightFactor = 0.88,
    this.autofocusClose = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onClose;
  final double maxWidth;
  final double maxHeightFactor;
  final bool autofocusClose;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required WidgetBuilder builder,
    String? subtitle,
    double maxWidth = 1280,
    double maxHeightFactor = 0.88,
    bool autofocusClose = true,
    bool barrierDismissible = true,
    bool enableAnimation = true,
  }) {
    HotkeyService.overlayPush();
    final result = Navigator.of(context).push<T>(
      NipaplayLargeScreenWindowPageRoute<T>(
        enableAnimation: enableAnimation,
        dismissible: barrierDismissible,
        builder: (routeContext) => NipaplayLargeScreenModeScope(
          isActive: true,
          child: NipaplayLargeScreenContentPage(
            closeOnBack: true,
            child: NipaplayLargeScreenViewContainer(
              title: title,
              subtitle: subtitle,
              maxWidth: maxWidth,
              maxHeightFactor: maxHeightFactor,
              autofocusClose: autofocusClose,
              onClose: () => Navigator.of(routeContext).maybePop(),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    );
    return result.whenComplete(HotkeyService.overlayPop);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF151820);
    final mediaQuery = MediaQuery.of(context);
    final availableHeight = mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom;
    final maxHeight = availableHeight * maxHeightFactor;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: ColoredBox(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.46)
                      : Colors.white.withValues(alpha: 0.32),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 48,
                vertical: 34,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                  ),
                  child: DecoratedBox(
                    key: const ValueKey<String>(
                      'large-screen-view-container',
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF17191F).withValues(alpha: 0.94)
                          : const Color(0xFFF5F5F8).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: textColor.withValues(alpha: 0.12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.42 : 0.18,
                          ),
                          blurRadius: 54,
                          spreadRadius: 4,
                          offset: const Offset(0, 22),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: FocusTraversalGroup(
                        policy: WidgetOrderTraversalPolicy(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                28,
                                22,
                                18,
                                18,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: textColor,
                                            fontSize: 28,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        if (subtitle?.trim().isNotEmpty ==
                                            true) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: textColor.withValues(
                                                alpha: 0.60,
                                              ),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Tooltip(
                                    message: '关闭',
                                    child: NipaplayLargeScreenFocusableAction(
                                      autofocus: autofocusClose,
                                      onActivate: onClose ??
                                          () =>
                                              Navigator.of(context).maybePop(),
                                      borderRadius: BorderRadius.circular(10),
                                      focusScale: 1.06,
                                      padding: const EdgeInsets.all(13),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: textColor.withValues(alpha: 0.10),
                            ),
                            Expanded(child: child),
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
    );
  }
}
