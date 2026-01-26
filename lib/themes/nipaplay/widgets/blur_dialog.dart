import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class BlurDialog {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    // 根据主题设置选择使用哪个dialog
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);

    if (uiThemeProvider.isCupertinoTheme) {
      return _showCupertinoDialog<T>(
        context: context,
        title: title,
        content: content,
        contentWidget: contentWidget,
        actions: actions,
        barrierDismissible: barrierDismissible,
      );
    }
    
    // 默认使用 NipaPlay 主题
    return _showNipaplayDialog<T>(
      context: context,
      title: title,
      content: content,
      contentWidget: contentWidget,
      actions: actions,
      barrierDismissible: barrierDismissible,
    );
  }

  static Future<T?> _showNipaplayDialog<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
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
          final colorScheme = Theme.of(dialogContext).colorScheme;
          final screenSize = MediaQuery.of(dialogContext).size;
          final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
          final keyboardHeight = MediaQuery.of(dialogContext).viewInsets.bottom;
          final shortestSide = screenSize.shortestSide;
          final bool isRealPhone = globals.isPhone && shortestSide < 600;
          final bool hasTitle = title.isNotEmpty;

          Widget dialogContent = Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasTitle) ...[
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                ],
                if (content != null)
                  Text(
                    content,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.9),
                      fontSize: 15,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (contentWidget != null)
                  contentWidget,
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
            ),
          );

          return NipaplayWindowScaffold(
            maxWidth: dialogWidth,
            maxHeightFactor: isRealPhone ? 0.85 : 0.8,
            onClose: barrierDismissible
                ? () => Navigator.of(dialogContext).maybePop()
                : null,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: dialogContent,
            ),
          );
        },
      ),
    );
  }

  static Future<T?> _showCupertinoDialog<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext ctx) {
        final List<Widget> children = [];

        if (content != null && content.isNotEmpty) {
          children.add(Text(
            content,
            style: const TextStyle(fontSize: 15, height: 1.35),
            textAlign: TextAlign.center,
          ));
        }

        if (contentWidget != null) {
          if (children.isNotEmpty) {
            children.add(const SizedBox(height: 12));
          }
          children.add(contentWidget);
        }

        return CupertinoAlertDialog(
          title: title.isNotEmpty
              ? Text(
                  title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                )
              : null,
          content: children.isEmpty
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
          actions: actions ?? const <Widget>[],
        );
      },
    );
  }
} 
