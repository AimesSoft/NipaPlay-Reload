import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/material.dart' show ColorScheme, Locale, ThemeMode;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';
import 'package:nipaplay/utils/app_theme.dart';

const Color _cupertinoAccentColor = Color(0xFFFF2E55);

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
    return DynamicColorBuilder(
      builder: (_, __) {
        final lightScheme = ColorScheme.fromSeed(
          seedColor: _cupertinoAccentColor,
          brightness: Brightness.light,
        );
        final darkScheme = ColorScheme.fromSeed(
          seedColor: _cupertinoAccentColor,
          brightness: Brightness.dark,
        );
        return AdaptiveApp(
          title: 'NipaPlay',
          navigatorKey: context.navigatorKey,
          themeMode: context.themeNotifier.themeMode,
          materialLightTheme: AppTheme.material3LightTheme(lightScheme),
          materialDarkTheme: AppTheme.material3DarkTheme(darkScheme),
          cupertinoLightTheme: const CupertinoThemeData(
            brightness: Brightness.light,
            primaryColor: _cupertinoAccentColor,
          ),
          cupertinoDarkTheme: const CupertinoThemeData(
            brightness: Brightness.dark,
            primaryColor: _cupertinoAccentColor,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', ''),
          ],
          home: context.cupertinoHomeBuilder(),
          builder: (buildContext, appChild) {
            final child = context.overlayBuilder(
              appChild ?? const SizedBox.shrink(),
            );
            if (context.environment.isIOS) {
              return child;
            }
            return DefaultTextStyle.merge(
              style: const TextStyle(decoration: TextDecoration.none),
              child: child,
            );
          },
        );
      },
    );
  }
}
