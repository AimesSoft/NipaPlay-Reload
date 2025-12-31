import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show ThemeMode, Icons;
import 'package:flutter/widgets.dart';

import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';
import 'package:nipaplay/themes/web/pages/web_home_page.dart';

class WebRemoteThemeDescriptor extends ThemeDescriptor {
  const WebRemoteThemeDescriptor()
      : super(
          id: ThemeIds.webRemote,
          displayName: 'Web Remote',
          preview: const ThemePreview(
            title: 'Web Remote（隐藏）',
            icon: Icons.web,
            highlights: [
              '仅用于 Web UI',
              '适配大屏布局',
              '远程访问：媒体库/库管理/观看记录',
            ],
          ),
          supportsDesktop: false,
          supportsPhone: false,
          supportsWeb: true,
          hiddenFromThemeOptions: true,
          requiresRestart: false,
          appBuilder: _buildApp,
        );

  static Widget _buildApp(ThemeBuildContext context) {
    return fluent.FluentApp(
      title: 'NipaPlay Web',
      debugShowCheckedModeBanner: false,
      themeMode: context.themeNotifier.themeMode,
      theme: fluent.FluentThemeData.light(),
      darkTheme: fluent.FluentThemeData.dark(),
      navigatorKey: context.navigatorKey,
      home: const WebHomePage(),
      builder: (buildContext, appChild) {
        return context.overlayBuilder(appChild ?? const SizedBox.shrink());
      },
    );
  }
}
