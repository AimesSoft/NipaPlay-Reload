import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class BlurDialog {
  /// Build dismissing actions with [actionsBuilder] so their context belongs
  /// to the dialog route, including when the caller uses a nested Navigator.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    AppDisplaySurface? displaySurface,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
    Color? backgroundColor,
    bool barrierDismissible = true,
    bool hidePhoneBottomBar = true,
    Color? phoneBarrierColor,
    double? desktopMaxWidth,
    double? desktopMaxHeightFactor,
    double phoneHeightRatio = 0.86,
  }) {
    assert(actions == null || actionsBuilder == null);
    if ((displaySurface ?? AppDisplaySurfaceScope.of(context)) ==
        AppDisplaySurface.phone) {
      return _showPhonePresentation<T>(
        context: context,
        title: title,
        content: content,
        contentWidget: contentWidget,
        actions: actions,
        actionsBuilder: actionsBuilder,
        barrierDismissible: barrierDismissible,
        hidePhoneBottomBar: hidePhoneBottomBar,
        phoneBarrierColor: phoneBarrierColor,
        heightRatio: phoneHeightRatio,
      );
    }

    // 默认使用桌面和平板布局
    return _showDesktopTabletDialog<T>(
      context: context,
      title: title,
      content: content,
      contentWidget: contentWidget,
      actions: actions,
      actionsBuilder: actionsBuilder,
      backgroundColor: backgroundColor,
      barrierDismissible: barrierDismissible,
      maxWidth: desktopMaxWidth,
      maxHeightFactor: desktopMaxHeightFactor,
    );
  }

  static Future<T?> _showDesktopTabletDialog<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
    Color? backgroundColor,
    bool barrierDismissible = true,
    double? maxWidth,
    double? maxHeightFactor,
  }) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<T>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: barrierDismissible,
      child: Builder(
        builder: (BuildContext dialogContext) {
          final screenSize = MediaQuery.sizeOf(dialogContext);
          final dialogWidth =
              maxWidth ?? globals.DialogSizes.getDialogWidth(screenSize.width);
          final shortestSide = screenSize.shortestSide;
          final bool isRealPhone = globals.isPhone && shortestSide < 600;
          final bool hasTitle = title.isNotEmpty;

          Widget dialogContent = Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: _buildDialogContent(
              context: dialogContext,
              title: title,
              content: content,
              contentWidget: contentWidget,
              actions: actionsBuilder?.call(dialogContext) ?? actions,
              includeTitle: hasTitle,
            ),
          );

          return NipaplayWindowScaffold(
            maxWidth: dialogWidth,
            maxHeightFactor: maxHeightFactor ?? (isRealPhone ? 0.85 : 0.8),
            onClose: barrierDismissible
                ? () => Navigator.of(dialogContext).maybePop()
                : null,
            backgroundColor: backgroundColor,
            child: _KeyboardInsetScrollView(child: dialogContent),
          );
        },
      ),
    );
  }

  static Future<T?> _showPhonePresentation<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
    bool barrierDismissible = true,
    bool hidePhoneBottomBar = true,
    Color? phoneBarrierColor,
    double heightRatio = 0.86,
  }) {
    return _showPhoneBottomSheet<T>(
      context: context,
      title: title,
      content: content,
      contentWidget: contentWidget,
      actions: actions,
      actionsBuilder: actionsBuilder,
      barrierDismissible: barrierDismissible,
      hidePhoneBottomBar: hidePhoneBottomBar,
      phoneBarrierColor: phoneBarrierColor,
      heightRatio: heightRatio,
    );
  }

  static Future<T?> _showPhoneBottomSheet<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
    bool barrierDismissible = true,
    bool hidePhoneBottomBar = true,
    Color? phoneBarrierColor,
    double heightRatio = 0.86,
  }) {
    return CupertinoBottomSheet.show<T>(
      context: context,
      title: title.isEmpty ? null : title,
      heightRatio: heightRatio,
      barrierDismissible: barrierDismissible,
      barrierColor: phoneBarrierColor,
      hideBottomBar: hidePhoneBottomBar,
      child: SafeArea(
        top: false,
        bottom: false,
        child: _KeyboardInsetScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Builder(
            builder: (sheetContext) => _buildDialogContent(
              context: sheetContext,
              title: title,
              content: content,
              contentWidget: contentWidget,
              actions: actionsBuilder?.call(sheetContext) ?? actions,
              includeTitle: false,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildDialogContent({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    bool includeTitle = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (includeTitle && title.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (content != null)
          Text(
            content,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.9),
              fontSize: 15,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        if (contentWidget != null) contentWidget,
        if (actions != null) ...[
          const SizedBox(height: 24),
          if ((globals.isPhone && !globals.isTablet) && actions.length > 2)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: actions
                  .map((action) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: action,
                      ))
                  .toList(),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: actions
                  .map((action) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: action,
                      ))
                  .toList(),
            ),
        ],
      ],
    );
  }
}

// Only the scrolling inset subscribes to keyboard metrics. The dialog body is
// a stable child, so successive IME animation frames do not rebuild its form.
class _KeyboardInsetScrollView extends StatelessWidget {
  const _KeyboardInsetScrollView({
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: padding +
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: child,
      );
}
