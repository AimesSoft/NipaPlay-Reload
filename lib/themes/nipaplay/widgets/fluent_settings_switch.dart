import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

class FluentSettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  static const Color _activeColor = Color(0xFFFF2E55);

  const FluentSettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accentColor = fluent.AccentColor.swatch({
      'normal': _activeColor,
      'default': _activeColor,
    });
    final toggleSwitchTheme = fluent.ToggleSwitchThemeData(
      checkedDecoration: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.disabled)
            ? _activeColor.withValues(alpha: 0.4)
            : _activeColor;
        return BoxDecoration(
          color: color,
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(100),
        );
      }),
    );
    final theme = fluent.FluentThemeData(
      brightness: brightness,
      accentColor: accentColor,
      toggleSwitchTheme: toggleSwitchTheme,
    );
    return fluent.FluentTheme(
      data: theme,
      child: fluent.ToggleSwitch(
        checked: value,
        onChanged: onChanged,
      ),
    );
  }
}
