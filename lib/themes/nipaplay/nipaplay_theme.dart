import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/theme_background_reveal_provider.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/themes/theme_ids.dart';
import 'package:nipaplay/themes/nipaplay/widgets/ui_scale_wrapper.dart';
import 'package:nipaplay/utils/app_theme.dart';

class DesktopTabletThemeDescriptor extends ThemeDescriptor {
  const DesktopTabletThemeDescriptor()
      : super(
          id: ThemeIds.desktopTablet,
          displayName: '桌面和平板布局',
          preview: const ThemePreview(
            title: '桌面和平板布局',
            icon: Icons.color_lens_outlined,
            highlights: [
              '浅色/深色界面',
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
    return Consumer<ThemeBackgroundRevealProvider>(
      builder: (buildContext, revealProvider, _) {
        final themeAnimationDuration = revealProvider.isActive
            ? Duration.zero
            : const Duration(milliseconds: 420);
        final accentColor = buildContext
            .watch<AppearanceSettingsProvider>()
            .accentColorPreset
            .color;
        return MaterialApp(
          title: 'NipaPlay',
          debugShowCheckedModeBanner: false,
          color: Colors.transparent,
          theme: AppTheme.lightTheme(accentColor),
          darkTheme: AppTheme.darkTheme(accentColor),
          themeMode: context.themeNotifier.themeMode,
          themeAnimationDuration: themeAnimationDuration,
          themeAnimationCurve: Curves.easeInOutCubic,
          locale: context.locale,
          localizationsDelegates: [
            ...context.localizationsDelegates,
            ...fluent.FluentLocalizations.localizationsDelegates,
          ],
          supportedLocales: context.supportedLocales,
          navigatorKey: context.navigatorKey,
          home: context.materialHomeBuilder(),
          builder: (buildContext, appChild) {
            final uiScale =
                buildContext.select<AppearanceSettingsProvider, double>(
              (provider) => provider.uiScale,
            );
            final overlayChild = context.overlayBuilder(
              appChild ?? const SizedBox.shrink(),
            );
            return UiScaleWrapper(
              scale: uiScale,
              child: overlayChild,
            );
          },
        );
      },
    );
  }
}
