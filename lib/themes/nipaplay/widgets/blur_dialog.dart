import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class BlurDialog {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    Color? backgroundColor,
    bool barrierDismissible = true,
    bool hidePhoneBottomBar = true,
    Color? phoneBarrierColor,
  }) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return _showPhonePresentation<T>(
        context: context,
        title: title,
        content: content,
        contentWidget: contentWidget,
        actions: actions,
        barrierDismissible: barrierDismissible,
        hidePhoneBottomBar: hidePhoneBottomBar,
        phoneBarrierColor: phoneBarrierColor,
      );
    }

    // 默认使用桌面和平板布局
    return _showDesktopTabletDialog<T>(
      context: context,
      title: title,
      content: content,
      contentWidget: contentWidget,
      actions: actions,
      backgroundColor: backgroundColor,
      barrierDismissible: barrierDismissible,
    );
  }

  static Future<T?> _showDesktopTabletDialog<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    Color? backgroundColor,
    bool barrierDismissible = true,
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
          final screenSize = MediaQuery.of(dialogContext).size;
          final dialogWidth =
              globals.DialogSizes.getDialogWidth(screenSize.width);
          final keyboardHeight = MediaQuery.of(dialogContext).viewInsets.bottom;
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
              actions: actions,
              includeTitle: hasTitle,
            ),
          );

          return NipaplayWindowScaffold(
            maxWidth: dialogWidth,
            maxHeightFactor: isRealPhone ? 0.85 : 0.8,
            onClose: barrierDismissible
                ? () => Navigator.of(dialogContext).maybePop()
                : null,
            backgroundColor: backgroundColor,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: dialogContent,
            ),
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
    bool barrierDismissible = true,
    bool hidePhoneBottomBar = true,
    Color? phoneBarrierColor,
  }) {
    return _showPhoneBottomSheet<T>(
      context: context,
      title: title,
      content: content,
      contentWidget: contentWidget,
      actions: actions,
      barrierDismissible: barrierDismissible,
      hidePhoneBottomBar: hidePhoneBottomBar,
      phoneBarrierColor: phoneBarrierColor,
    );
  }

  static Future<T?> _showPhoneBottomSheet<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    bool barrierDismissible = true,
    bool hidePhoneBottomBar = true,
    Color? phoneBarrierColor,
  }) {
    return CupertinoBottomSheet.show<T>(
      context: context,
      title: title.isEmpty ? null : title,
      heightRatio: 0.86,
      barrierDismissible: barrierDismissible,
      barrierColor: phoneBarrierColor,
      hideBottomBar: hidePhoneBottomBar,
      child: Builder(
        builder: (sheetContext) {
          final keyboardHeight = MediaQuery.of(sheetContext).viewInsets.bottom;
          return SafeArea(
            top: false,
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                24 + keyboardHeight,
              ),
              child: _buildDialogContent(
                context: sheetContext,
                title: title,
                content: content,
                contentWidget: contentWidget,
                actions: actions,
                includeTitle: false,
              ),
            ),
          );
        },
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
