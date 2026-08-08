import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:provider/provider.dart';

class FluentSettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  static Color get _activeColor => AppAccentColors.current;

  const FluentSettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  void _handleChanged(BuildContext context, bool newValue) {
    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      final sfx = context.read<LargeScreenUiSfxService>();
      if (newValue) {
        sfx.playSwitchOn();
      } else {
        sfx.playSwitchOff();
      }
    }
    onChanged?.call(newValue);
  }

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
        onChanged: onChanged != null
            ? (v) => _handleChanged(context, v)
            : null,
      ),
    );
  }
}
