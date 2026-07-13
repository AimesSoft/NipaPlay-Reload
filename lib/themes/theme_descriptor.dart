import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/utils/theme_notifier.dart';

class ThemeEnvironment {
  final bool isDesktop;
  final bool isPhone;
  final bool isWeb;
  final bool isIOS;
  final bool isTablet;
  final bool isTelevision;

  const ThemeEnvironment({
    required this.isDesktop,
    required this.isPhone,
    required this.isWeb,
    this.isIOS = false,
    this.isTablet = false,
    this.isTelevision = false,
  });

  AppDisplaySurface get displaySurface {
    if (isTelevision) return AppDisplaySurface.television;
    if (isPhone) return AppDisplaySurface.phone;
    return AppDisplaySurface.desktopTablet;
  }
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
  final Locale locale;
  final List<Locale> supportedLocales;
  final List<LocalizationsDelegate<dynamic>> localizationsDelegates;
  final Map<String, dynamic> _settings;
  final Widget Function(Widget child) overlayBuilder;
  final Map<AppDisplaySurface, Widget Function()> _homeBuilders;

  ThemeBuildContext({
    required this.themeNotifier,
    required this.navigatorKey,
    required this.launchFilePath,
    required this.environment,
    required this.locale,
    required this.supportedLocales,
    required this.localizationsDelegates,
    required Map<String, dynamic> settings,
    required this.overlayBuilder,
    required Map<AppDisplaySurface, Widget Function()> homeBuilders,
  })  : _settings = UnmodifiableMapView(settings),
        _homeBuilders = UnmodifiableMapView(homeBuilders);

  T setting<T>(String key, T fallback) {
    final value = _settings[key];
    if (value is T) {
      return value;
    }
    return fallback;
  }

  Widget buildHome(AppDisplaySurface surface) {
    var builder = _homeBuilders[surface] ??
        _homeBuilders[AppDisplaySurface.desktopTablet];
    if (builder == null && _homeBuilders.isNotEmpty) {
      builder = _homeBuilders.values.first;
    }
    assert(builder != null, 'No application shell registered for $surface.');
    return AppDisplaySurfaceScope(
      surface: surface,
      child: builder?.call() ?? const SizedBox.shrink(),
    );
  }
}

class ThemeDescriptor {
  final String id;
  final String displayName;
  final ThemePreview preview;

  /// 是否在布局候选中隐藏（例如：仅用于特定环境的内部布局）。
  final bool hiddenFromLayoutOptions;
  final bool supportsDesktop;
  final bool supportsPhone;
  final bool supportsWeb;
  final bool supportsTelevision;
  final ThemeAppBuilder appBuilder;
  final bool requiresRestart;

  const ThemeDescriptor({
    required this.id,
    required this.displayName,
    required this.preview,
    required this.appBuilder,
    this.hiddenFromLayoutOptions = false,
    this.supportsDesktop = true,
    this.supportsPhone = true,
    this.supportsWeb = true,
    this.supportsTelevision = false,
    this.requiresRestart = true,
  });

  bool isSupported(ThemeEnvironment env) {
    if (env.isWeb) return supportsWeb;
    return switch (env.displaySurface) {
      AppDisplaySurface.phone => supportsPhone,
      AppDisplaySurface.desktopTablet => supportsDesktop,
      AppDisplaySurface.television => supportsTelevision,
    };
  }

  Widget buildApp(ThemeBuildContext context) => appBuilder(context);
}
