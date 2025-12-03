import 'package:nipaplay/themes/cupertino/cupertino_theme.dart';
import 'package:nipaplay/themes/fluent/fluent_theme.dart';
import 'package:nipaplay/themes/nipaplay/nipaplay_theme.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';

class ThemeRegistry {
  static final Map<String, ThemeDescriptor> _themes = {
    ThemeIds.nipaplay: const NipaplayThemeDescriptor(),
    ThemeIds.fluent: const FluentThemeDescriptor(),
    ThemeIds.cupertino: const CupertinoThemeDescriptor(),
  };

  static String get defaultThemeId => ThemeIds.nipaplay;

  static ThemeDescriptor get defaultTheme =>
      _themes[defaultThemeId] ?? const NipaplayThemeDescriptor();

  static ThemeDescriptor defaultThemeForEnvironment(ThemeEnvironment env) {
    if (env.isIOS) {
      final cupertinoTheme = maybeGet(ThemeIds.cupertino);
      if (cupertinoTheme != null && cupertinoTheme.isSupported(env)) {
        return cupertinoTheme;
      }
    }
    return defaultTheme;
  }

  static ThemeDescriptor? maybeGet(String? id) {
    if (id == null) return null;
    return _themes[id];
  }

  static List<ThemeDescriptor> get allThemes =>
      List.unmodifiable(_themes.values);

  static List<ThemeDescriptor> supportedThemes(ThemeEnvironment env) {
    return allThemes.where((theme) => theme.isSupported(env)).toList();
  }

  static ThemeDescriptor resolveTheme(String? id, ThemeEnvironment env) {
    final candidate = maybeGet(id);
    if (candidate != null && candidate.isSupported(env)) {
      return candidate;
    }
    final preferred = defaultThemeForEnvironment(env);
    if (preferred.isSupported(env)) {
      return preferred;
    }
    final available = supportedThemes(env);
    if (available.isNotEmpty) {
      return available.first;
    }
    return defaultTheme;
  }
}
