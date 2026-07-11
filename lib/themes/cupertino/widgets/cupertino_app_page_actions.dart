import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_actions.dart';
import 'package:nipaplay/app/unified_app_view_presenter.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_glass_button_group.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_page_actions_scope.dart';
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
    final controller = CupertinoPageActionsScope.maybeOf(context);
    if (controller == null) return _buildActions(context, const []);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildActions(context, controller.actions),
    );
  }

  Widget _buildActions(
    BuildContext context,
    List<CupertinoPageAction> pageActions,
  ) {
    if (actionIds.isEmpty && pageActions.isEmpty) {
      return const SizedBox.shrink();
    }

    return CupertinoGlassButtonGroup(
      buttonSize: 44,
      items: [
        for (final action in pageActions)
          CupertinoGlassButtonGroupItem(
            label: action.label,
            icon: action.icon,
            onPressed: action.onPressed,
          ),
        if (actionIds.contains(AppActionIds.toggleTheme))
          CupertinoGlassButtonGroupItem(
            label: '切换深浅模式',
            icon: CupertinoTheme.brightnessOf(context) == Brightness.dark
                ? CupertinoIcons.sun_max_fill
                : CupertinoIcons.moon_fill,
            onPressed: () => _performAction(context, AppActionIds.toggleTheme),
          ),
        if (actionIds.contains(AppActionIds.settings))
          CupertinoGlassButtonGroupItem(
            label: '设置',
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
}
