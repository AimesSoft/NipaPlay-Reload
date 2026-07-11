import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;

class CupertinoMediaSearchToolbarAction {
  const CupertinoMediaSearchToolbarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final material.IconData icon;
  final material.VoidCallback? onPressed;
  final bool loading;
}

class CupertinoMediaSearchToolbar extends material.StatelessWidget {
  const CupertinoMediaSearchToolbar({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    required this.actions,
    this.leadingAction,
  });

  static const double controlHeight = 38;

  final material.TextEditingController controller;
  final String placeholder;
  final material.ValueChanged<String> onChanged;
  final CupertinoMediaSearchToolbarAction? leadingAction;
  final List<CupertinoMediaSearchToolbarAction> actions;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Padding(
      padding: const material.EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: material.Row(
        children: [
          if (leadingAction case final action?) ...[
            _ToolbarButton(action: action),
            const material.SizedBox(width: 4),
          ],
          material.Expanded(
            child: material.SizedBox(
              height: controlHeight,
              child: cupertino.CupertinoSearchTextField(
                controller: controller,
                placeholder: placeholder,
                onChanged: onChanged,
                onSuffixTap: () {
                  controller.clear();
                  onChanged('');
                },
              ),
            ),
          ),
          if (actions.isNotEmpty) const material.SizedBox(width: 4),
          for (final action in actions) _ToolbarButton(action: action),
        ],
      ),
    );
  }
}

class _ToolbarButton extends material.StatelessWidget {
  const _ToolbarButton({required this.action});

  final CupertinoMediaSearchToolbarAction action;

  @override
  material.Widget build(material.BuildContext context) {
    final foreground = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.label,
      context,
    );
    return material.Semantics(
      button: true,
      label: action.label,
      child: material.SizedBox.square(
        dimension: CupertinoMediaSearchToolbar.controlHeight,
        child: cupertino.CupertinoButton(
          padding: material.EdgeInsets.zero,
          minimumSize: const material.Size.square(
            CupertinoMediaSearchToolbar.controlHeight,
          ),
          onPressed: action.onPressed,
          child: action.loading
              ? const cupertino.CupertinoActivityIndicator(radius: 9)
              : material.Icon(
                  action.icon,
                  size: 21,
                  color: action.onPressed == null
                      ? foreground.withValues(alpha: 0.3)
                      : foreground,
                ),
        ),
      ),
    );
  }
}
