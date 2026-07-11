import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_actions.dart';
import 'package:nipaplay/app/unified_app_view_presenter.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

class CupertinoAppPageActions extends StatelessWidget {
  const CupertinoAppPageActions({
    super.key,
    required this.actionIds,
  });

  final List<String> actionIds;

  @override
  Widget build(BuildContext context) {
    if (actionIds.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actionIds.contains(AppActionIds.toggleTheme)) ...[
          _buildAction(
            context,
            label: '切换深浅模式',
            symbol: CupertinoTheme.brightnessOf(context) == Brightness.dark
                ? 'sun.max.fill'
                : 'moon.fill',
            icon: CupertinoTheme.brightnessOf(context) == Brightness.dark
                ? CupertinoIcons.sun_max_fill
                : CupertinoIcons.moon_fill,
            onPressed: () => _performAction(context, AppActionIds.toggleTheme),
          ),
          const SizedBox(width: 8),
        ],
        if (actionIds.contains(AppActionIds.settings))
          _buildAction(
            context,
            label: '设置',
            symbol: 'gearshape.fill',
            icon: CupertinoIcons.gear_alt_fill,
            onPressed: () => _performAction(context, AppActionIds.settings),
          ),
      ],
    );
  }

  void _toggleTheme(BuildContext context) {
    final notifier = context.read<ThemeNotifier>();
    notifier.themeMode = CupertinoTheme.brightnessOf(context) == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  void _performAction(BuildContext context, String actionId) {
    final action = unifiedAppActionById(actionId);
    if (action == null) return;

    switch (action.kind) {
      case UnifiedAppActionKind.command:
        if (action.id == AppActionIds.toggleTheme) {
          _toggleTheme(context);
        }
        return;
      case UnifiedAppActionKind.openView:
        final targetViewId = action.targetViewId;
        if (targetViewId != null) {
          unawaited(
            UnifiedAppViewPresenter.show<void>(
              context,
              viewId: targetViewId,
            ),
          );
        }
        return;
    }
  }

  Widget _buildAction(
    BuildContext context, {
    required String label,
    required String symbol,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final foreground = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );

    final Widget button;
    if (PlatformInfo.isIOS26OrHigher()) {
      button = AdaptiveButton.sfSymbol(
        onPressed: onPressed,
        sfSymbol: SFSymbol(symbol, size: 18, color: foreground),
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        padding: EdgeInsets.zero,
        minSize: const Size.square(44),
        useSmoothRectangleBorder: false,
      );
    } else {
      final background = CupertinoDynamicColor.resolve(
        CupertinoColors.systemBackground.withValues(alpha: 0.72),
        context,
      );
      button = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              border: Border.all(
                color: foreground.withValues(alpha: 0.1),
              ),
              shape: BoxShape.circle,
            ),
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(44),
              onPressed: onPressed,
              child: Icon(icon, size: 20, color: foreground),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(dimension: 44, child: button),
    );
  }
}
