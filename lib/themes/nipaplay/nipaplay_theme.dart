import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';
import 'package:nipaplay/utils/app_theme.dart';

class NipaplayThemeDescriptor extends ThemeDescriptor {
  const NipaplayThemeDescriptor()
      : super(
          id: ThemeIds.nipaplay,
          displayName: 'NipaPlay',
          preview: const ThemePreview(
            title: 'NipaPlay 主题',
            icon: Icons.blur_on,
            highlights: [
              '磨砂玻璃效果',
              '渐变背景',
              '圆角设计',
              '适合多媒体应用',
            ],
          ),
          supportsDesktop: true,
          supportsPhone: true,
          supportsWeb: false,
          appBuilder: _buildApp,
        );

  static Widget _buildApp(ThemeBuildContext context) {
    return MaterialApp(
      title: 'NipaPlay',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: context.themeNotifier.themeMode,
      localizationsDelegates: fluent.FluentLocalizations.localizationsDelegates,
      supportedLocales: fluent.FluentLocalizations.supportedLocales,
      navigatorKey: context.navigatorKey,
      home: context.materialHomeBuilder(),
      builder: (buildContext, appChild) {
        return context.overlayBuilder(
          appChild ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
