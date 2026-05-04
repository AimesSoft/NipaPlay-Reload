import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/material.dart' show ColorScheme;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';
import 'package:nipaplay/utils/app_theme.dart';

class CupertinoThemeDescriptor extends ThemeDescriptor {
  const CupertinoThemeDescriptor()
      : super(
          id: ThemeIds.cupertino,
          displayName: 'Cupertino',
          preview: const ThemePreview(
            title: 'Cupertino 主题',
            icon: CupertinoIcons.device_phone_portrait,
            highlights: [
              '贴近原生 iOS 体验',
              '自适应平台控件',
              '深浅模式同步',
              '底部导航布局',
            ],
          ),
          supportsDesktop: false,
          supportsPhone: true,
          supportsWeb: false,
          appBuilder: _buildApp,
        );

  static Widget _buildApp(ThemeBuildContext context) {
    return Consumer<AppearanceSettingsProvider>(
      builder: (_, appearanceSettings, __) {
        final accentColor = appearanceSettings.accentColorPreset.color;
        final lightScheme = ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.light,
        );
        final darkScheme = ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.dark,
        );
        return DynamicColorBuilder(
          builder: (_, __) {
            return AdaptiveApp(
              title: 'NipaPlay',
              navigatorKey: context.navigatorKey,
              themeMode: context.themeNotifier.themeMode,
              materialLightTheme: AppTheme.material3LightTheme(lightScheme),
              materialDarkTheme: AppTheme.material3DarkTheme(darkScheme),
              cupertinoLightTheme: CupertinoThemeData(
                brightness: Brightness.light,
                primaryColor: accentColor,
              ),
              cupertinoDarkTheme: CupertinoThemeData(
                brightness: Brightness.dark,
                primaryColor: accentColor,
              ),
              locale: context.locale,
              localizationsDelegates: context.localizationsDelegates,
              supportedLocales: context.supportedLocales,
              home: context.cupertinoHomeBuilder(),
              builder: (buildContext, appChild) {
                final child = context.overlayBuilder(
                  appChild ?? const SizedBox.shrink(),
                );
                if (context.environment.isIOS) {
                  return child;
                }
                return DefaultTextStyle.merge(
                  style: TextStyle(decoration: TextDecoration.none),
                  child: child,
                );
              },
            );
          },
        );
      },
    );
  }
}
