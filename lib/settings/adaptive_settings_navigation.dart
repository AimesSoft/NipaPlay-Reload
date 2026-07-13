import 'package:flutter/widgets.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';

class AdaptiveSettingsNavigation {
  const AdaptiveSettingsNavigation._();

  static Future<T?> openChildPage<T>(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final style = AdaptiveSettingsScope.styleOf(context);
    if (style == AdaptiveSettingsStyle.phone) {
      return CupertinoBottomSheetPageNavigator.push<T>(
        context,
        title: title,
        builder: (_) => AdaptiveSettingsScope(
          style: style,
          child: child,
        ),
      );
    }

    return NipaplayWindow.show<T>(
      context: context,
      child: NipaplayWindowScaffold(
        maxWidth: 600,
        maxHeightFactor: 0.9,
        child: AdaptiveSettingsScope(
          style: style,
          child: child,
        ),
      ),
    );
  }
}
