import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';

class FluentThemeDescriptor extends ThemeDescriptor {
  const FluentThemeDescriptor()
      : super(
          id: ThemeIds.fluent,
          displayName: 'Fluent UI',
          preview: const ThemePreview(
            title: 'Fluent UI 主题',
            icon: fluent.FluentIcons.app_icon_default,
            highlights: [
              '微软 Fluent Design 语言',
              '统一的自适应导航',
              '亚克力材质与动效',
              '为桌面端优化',
            ],
          ),
          supportsDesktop: true,
          supportsPhone: false,
          supportsWeb: false,
          appBuilder: _buildApp,
        );

  static Widget _buildApp(ThemeBuildContext context) {
    final ThemeMode themeMode =
        context.setting<ThemeMode>('fluentThemeMode', ThemeMode.dark);

    return fluent.FluentApp(
      title: 'NipaPlay',
      debugShowCheckedModeBanner: false,
      theme: fluent.FluentThemeData.light(),
      darkTheme: fluent.FluentThemeData.dark(),
      themeMode: themeMode,
      navigatorKey: context.navigatorKey,
      home: context.fluentHomeBuilder(),
      builder: (buildContext, appChild) {
        return context.overlayBuilder(
          appChild ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
