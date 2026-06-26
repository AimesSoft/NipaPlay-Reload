import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:provider/provider.dart';

class PlayerMenuColors {
  const PlayerMenuColors({
    required this.surface,
    required this.foreground,
    required this.secondaryForeground,
    required this.disabledForeground,
    required this.divider,
    required this.border,
    required this.accent,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.selectedBorder,
    required this.hoverBackground,
    required this.controlBackground,
    required this.controlBorder,
    required this.shadow,
  });

  final Color surface;
  final Color foreground;
  final Color secondaryForeground;
  final Color disabledForeground;
  final Color divider;
  final Color border;
  final Color accent;
  final Color selectedBackground;
  final Color selectedForeground;
  final Color selectedBorder;
  final Color hoverBackground;
  final Color controlBackground;
  final Color controlBorder;
  final Color shadow;
}

class PlayerMenuTheme {
  const PlayerMenuTheme._();

  static PlayerMenuColors colorsOf(BuildContext context) {
    final isDark = _resolveIsDark(context);
    final accent = AppAccentColors.current;
    final foreground = isDark ? Colors.white : Colors.black87;
    final surface = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    return PlayerMenuColors(
      surface: surface,
      foreground: foreground,
      secondaryForeground: foreground.withValues(alpha: 0.68),
      disabledForeground: foreground.withValues(alpha: 0.38),
      divider: foreground.withValues(alpha: isDark ? 0.12 : 0.10),
      border: foreground.withValues(alpha: isDark ? 0.18 : 0.12),
      accent: accent,
      selectedBackground: accent.withValues(alpha: isDark ? 0.24 : 0.14),
      selectedForeground: accent,
      selectedBorder: accent.withValues(alpha: isDark ? 0.62 : 0.42),
      hoverBackground: foreground.withValues(alpha: isDark ? 0.08 : 0.05),
      controlBackground: foreground.withValues(alpha: isDark ? 0.08 : 0.04),
      controlBorder: foreground.withValues(alpha: isDark ? 0.22 : 0.14),
      shadow: Colors.black.withValues(alpha: isDark ? 0.28 : 0.16),
    );
  }

  static bool _resolveIsDark(BuildContext context) {
    final themeNotifier = context.read<ThemeNotifier?>();
    final themeMode = themeNotifier?.themeMode ?? ThemeMode.system;
    return switch (themeMode) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
  }

  static ThemeData dataFor(BuildContext context) {
    final baseTheme = Theme.of(context);
    final colors = colorsOf(context);
    final brightness =
        _resolveIsDark(context) ? Brightness.dark : Brightness.light;
    final colorScheme = baseTheme.colorScheme.copyWith(
      brightness: brightness,
      primary: colors.accent,
      secondary: colors.accent,
      surface: colors.surface,
      onSurface: colors.foreground,
      onSurfaceVariant: colors.secondaryForeground,
    );

    return baseTheme.copyWith(
      colorScheme: colorScheme,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      dividerColor: colors.divider,
      textTheme: baseTheme.textTheme.apply(
        bodyColor: colors.foreground,
        displayColor: colors.foreground,
      ),
      iconTheme: baseTheme.iconTheme.copyWith(color: colors.foreground),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          overlayColor: Colors.transparent,
        ),
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: colors.controlBackground,
        hintStyle: TextStyle(color: colors.disabledForeground),
        suffixStyle: TextStyle(color: colors.secondaryForeground),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.controlBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.accent),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
