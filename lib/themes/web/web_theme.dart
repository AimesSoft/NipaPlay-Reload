import 'package:flutter/material.dart';

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

  static const Color _bilibiliBlue = Color(0xFF00A1D6);

  static Widget _buildApp(ThemeBuildContext context) {
    return MaterialApp(
      title: 'NipaPlay Web',
      debugShowCheckedModeBanner: false,
      themeMode: context.themeNotifier.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _bilibiliBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F8),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _bilibiliBlue,
          brightness: Brightness.dark,
        ),
      ),
      navigatorKey: context.navigatorKey,
      home: const WebHomePage(),
      builder: (buildContext, appChild) {
        return context.overlayBuilder(appChild ?? const SizedBox.shrink());
      },
    );
  }
}
