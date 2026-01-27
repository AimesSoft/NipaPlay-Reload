import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Locale, ThemeMode;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';

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
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme = AppTheme.material3LightScheme(lightDynamic);
        final darkScheme = AppTheme.material3DarkScheme(darkDynamic);
        return AdaptiveApp(
          title: 'NipaPlay',
          navigatorKey: context.navigatorKey,
          themeMode: context.themeNotifier.themeMode,
          materialLightTheme: AppTheme.material3LightTheme(lightScheme),
          materialDarkTheme: AppTheme.material3DarkTheme(darkScheme),
          cupertinoLightTheme: const CupertinoThemeData(
            brightness: Brightness.light,
          ),
          cupertinoDarkTheme: const CupertinoThemeData(
            brightness: Brightness.dark,
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
            return DefaultTextStyle(
              style: DefaultTextStyle.of(buildContext).style,
              overflow: TextOverflow.visible,
              softWrap: true,
              child: child,
            );
          },
        );
      },
    );
  }
}
