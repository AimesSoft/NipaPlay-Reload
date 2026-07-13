import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

/// 通用的毛玻璃底部弹出菜单
class GlassBottomSheet extends StatelessWidget {
  const GlassBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.height,
    this.embedded = false,
  });

  final String title;
  final Widget child;
  final double? height;
  final bool embedded;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    double? height,
  }) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return CupertinoBottomSheet.show<T>(
        context: context,
        title: title,
        child: GlassBottomSheet(
          title: title,
          height: height,
          embedded: true,
          child: child,
        ),
      );
    }

    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<T>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: GlassBottomSheet(
        title: title,
        child: child,
        height: height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final sheetHeight = height ?? MediaQuery.of(context).size.height * 0.6;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final content = SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + keyboardHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!embedded) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  locale: const Locale('zh', 'CN'),
                  style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ) ??
                      TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                  textAlign: TextAlign.left,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Expanded(child: child),
          ],
        ),
      ),
    );
    if (embedded) return content;
    return NipaplayWindowScaffold(
      maxWidth: dialogWidth,
      maxHeightFactor: (sheetHeight / screenSize.height).clamp(0.5, 0.9),
      onClose: () => Navigator.of(context).maybePop(),
      child: content,
    );
  }
}
