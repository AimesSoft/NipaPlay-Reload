import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_notifier.dart';

class ThemeEnvironment {
  final bool isDesktop;
  final bool isPhone;
  final bool isWeb;
  final bool isIOS;
  final bool isTablet;

  const ThemeEnvironment({
    required this.isDesktop,
    required this.isPhone,
    required this.isWeb,
    this.isIOS = false,
    this.isTablet = false,
  });
}

typedef ThemeAppBuilder = Widget Function(ThemeBuildContext context);

class ThemePreview {
  final String title;
  final List<String> highlights;
  final IconData icon;

  const ThemePreview({
    required this.title,
    required this.highlights,
    required this.icon,
  });
}

class ThemeBuildContext {
  final ThemeNotifier themeNotifier;
  final GlobalKey<NavigatorState> navigatorKey;
  final String? launchFilePath;
  final ThemeEnvironment environment;
  final Map<String, dynamic> _settings;
  final Widget Function(Widget child) overlayBuilder;
  final Widget Function() materialHomeBuilder;
  final Widget Function() fluentHomeBuilder;
  final Widget Function() cupertinoHomeBuilder;

  ThemeBuildContext({
    required this.themeNotifier,
    required this.navigatorKey,
    required this.launchFilePath,
    required this.environment,
    required Map<String, dynamic> settings,
    required this.overlayBuilder,
    required this.materialHomeBuilder,
    required this.fluentHomeBuilder,
    required this.cupertinoHomeBuilder,
  }) : _settings = UnmodifiableMapView(settings);

  T setting<T>(String key, T fallback) {
    final value = _settings[key];
    if (value is T) {
      return value;
    }
    return fallback;
  }
}

class ThemeDescriptor {
  final String id;
  final String displayName;
  final ThemePreview preview;
  /// 是否在“主题选择/主题选项”中隐藏（例如：仅用于特定环境的内部主题）。
  final bool hiddenFromThemeOptions;
  final bool supportsDesktop;
  final bool supportsPhone;
  final bool supportsWeb;
  final ThemeAppBuilder appBuilder;
  final bool requiresRestart;

  const ThemeDescriptor({
    required this.id,
    required this.displayName,
    required this.preview,
    required this.appBuilder,
    this.hiddenFromThemeOptions = false,
    this.supportsDesktop = true,
    this.supportsPhone = true,
    this.supportsWeb = true,
    this.requiresRestart = true,
  });

  bool isSupported(ThemeEnvironment env) {
    if (env.isWeb) return supportsWeb;
    if (env.isPhone) return supportsPhone;
    return supportsDesktop;
  }

  Widget buildApp(ThemeBuildContext context) => appBuilder(context);
}
