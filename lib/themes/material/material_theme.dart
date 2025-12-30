import 'package:flutter/material.dart';

import 'package:nipaplay/themes/material/pages/material_main_page.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';

class MaterialThemeDescriptor extends ThemeDescriptor {
  const MaterialThemeDescriptor()
      : super(
          id: ThemeIds.material,
          displayName: 'Material',
          preview: const ThemePreview(
            title: 'Material 3 主题',
            icon: Icons.widgets_outlined,
            highlights: [
              '严格使用 Material 3 组件与配色',
              '自适应导航：NavigationBar / NavigationRail',
              '深浅色模式按规范切换',
              '面向移动端与桌面端布局',
            ],
          ),
          supportsDesktop: true,
          supportsPhone: true,
          supportsWeb: false,
          appBuilder: _buildApp,
        );

  // Google Blue（作为默认种子色；可在后续扩展为用户可配置/动态配色）
  static const Color _seedColor = Color(0xFF1A73E8);

  static Widget _buildApp(ThemeBuildContext context) {
    return MaterialApp(
      title: 'NipaPlay',
      debugShowCheckedModeBanner: false,
      themeMode: context.themeNotifier.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      navigatorKey: context.navigatorKey,
      home: MaterialMainPage(launchFilePath: context.launchFilePath),
      builder: (buildContext, appChild) {
        return context.overlayBuilder(appChild ?? const SizedBox.shrink());
      },
    );
  }
}

