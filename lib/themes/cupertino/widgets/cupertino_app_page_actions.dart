import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_actions.dart';
import 'package:nipaplay/app/unified_app_view_presenter.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
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

    // Keep painting and hit testing in the same Flutter coordinate space.
    // UIKit toolbar groups can lay out their trailing item outside the
    // platform view when a page adds an action (such as the library's menu).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in pageActions)
          _PageActionButton(
            key: ValueKey(action.id),
            label: action.label,
            icon: action.icon,
            onPressed: action.onPressed,
          ),
        if (actionIds.contains(AppActionIds.toggleTheme))
          _PageActionButton(
            key: const ValueKey(AppActionIds.toggleTheme),
            label: '切换深浅模式',
            icon: CupertinoTheme.brightnessOf(context) == Brightness.dark
                ? CupertinoIcons.sun_max_fill
                : CupertinoIcons.moon_fill,
            onPressed: () => _performAction(context, AppActionIds.toggleTheme),
          ),
        if (actionIds.contains(AppActionIds.settings))
          _PageActionButton(
            key: const ValueKey(AppActionIds.settings),
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

class _PageActionButton extends StatefulWidget {
  const _PageActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_PageActionButton> createState() => _PageActionButtonState();
}

class _PageActionButtonState extends State<_PageActionButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        focusColor: const Color(0x00000000),
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onPressed: widget.onPressed,
        child: Icon(
          widget.icon,
          size: 19,
          semanticLabel: widget.label,
          color: CupertinoDynamicColor.resolve(
            widget.onPressed == null
                ? CupertinoColors.inactiveGray
                : _isFocused
                    ? CupertinoTheme.of(context).primaryColor
                    : CupertinoColors.label,
            context,
          ),
        ),
      ),
    );
  }
}
