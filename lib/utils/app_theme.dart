// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/linux_system_font_loader.dart';

class AppTheme {
  /// Windows 上使用英文名指定微软雅黑：本地化名「微软雅黑」在非中文
  /// 区域设置的 Windows 上会匹配失败，导致中文回退到点阵宋体。
  /// 英文名在任意区域设置下均可匹配，且雅黑带真实 Bold 字重，
  /// 大标题粗体观感与原生应用一致。
  static String? get _platformDefaultFont {
    if (kIsWeb) return null; // Web平台使用浏览器默认字体
    return Platform.isWindows ? 'Microsoft YaHei' : null;
  }

  static List<String>? get platformFontFamilyFallback {
    if (kIsWeb) return null;
    if (Platform.isLinux) return linuxSystemFontFallback;
    // Windows：本地化名兜底英文名匹配失败的极端环境，
    // 内置 subfont（Droid Sans Fallback）作最后离线保底。
    if (Platform.isWindows) {
      return const ['微软雅黑', 'subfont'];
    }
    return null;
  }

  /// Windows 上未显式设置 locale 的 Text 会把 CJK 字形渲染成日文
  /// 字形变体（如「达」左上带点、「与」底部横线出头）。主题层统一
  /// 给全部文本样式附加简体中文 locale：Text 未显式设置 locale 时会
  /// 经 DefaultTextStyle 合并继承该值，按简体字形渲染，一处修复全局
  /// 生效（显式设置了 locale 的 Text 不受影响）。
  ///
  /// 页面里全新构造的局部 ThemeData（如沉浸式详情页的深色覆盖主题）
  /// 也必须经过本方法：Material 会用 `Theme.of(context).textTheme.bodyMedium`
  /// 替换式注入 DefaultTextStyle，未过本方法的局部主题会把按钮、菜单
  /// 等组件的 CJK 字形退回日文变体。
  static ThemeData applyHansLocale(ThemeData theme) {
    TextStyle? attach(TextStyle? style) =>
        style?.copyWith(locale: const Locale('zh-Hans'));
    final base = theme.textTheme;
    return theme.copyWith(
      textTheme: TextTheme(
        displayLarge: attach(base.displayLarge),
        displayMedium: attach(base.displayMedium),
        displaySmall: attach(base.displaySmall),
        headlineLarge: attach(base.headlineLarge),
        headlineMedium: attach(base.headlineMedium),
        headlineSmall: attach(base.headlineSmall),
        titleLarge: attach(base.titleLarge),
        titleMedium: attach(base.titleMedium),
        titleSmall: attach(base.titleSmall),
        bodyLarge: attach(base.bodyLarge),
        bodyMedium: attach(base.bodyMedium),
        bodySmall: attach(base.bodySmall),
        labelLarge: attach(base.labelLarge),
        labelMedium: attach(base.labelMedium),
        labelSmall: attach(base.labelSmall),
      ),
    );
  }

  static ColorScheme material3LightScheme(ColorScheme? dynamicScheme) {
    return dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: AppAccentColors.current,
          brightness: Brightness.light,
        );
  }

  static ColorScheme material3DarkScheme(ColorScheme? dynamicScheme) {
    return dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: AppAccentColors.current,
          brightness: Brightness.dark,
        );
  }

  static ThemeData material3LightTheme(ColorScheme scheme) {
    return applyHansLocale(ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.light,
      fontFamily: _platformDefaultFont,
      fontFamilyFallback: platformFontFamilyFallback,
    ));
  }

  static ThemeData material3DarkTheme(ColorScheme scheme) {
    return applyHansLocale(ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      fontFamily: _platformDefaultFont,
      fontFamilyFallback: platformFontFamilyFallback,
    ));
  }

  static ThemeData lightTheme(Color accentColor) => applyHansLocale(ThemeData(
        brightness: Brightness.light, // 设置亮度为浅色模式
        fontFamily: _platformDefaultFont, // 使用平台默认字体
        fontFamilyFallback: platformFontFamilyFallback,
        colorScheme: ColorScheme(
          brightness: Brightness.light, // 设置颜色方案的亮度为浅色模式
          primary: accentColor, // 主要颜色
          onPrimary: Colors.white, // 在主要颜色上的文本和图标颜色
          secondary: accentColor, // 辅助颜色
          onSecondary: Colors.white, // 在辅助颜色上的文本和图标颜色
          surface: Colors.white, // 表面颜色
          onSurface: Colors.black87, // 在表面颜色上的文本和图标颜色
          error: Colors.red, // 错误颜色
          onError: Colors.white, // 在错误颜色上的文本和图标颜色
        ),
      ));

  static ThemeData darkTheme(Color accentColor) => applyHansLocale(ThemeData(
        brightness: Brightness.dark, // 设置亮度为深色模式
        fontFamily: _platformDefaultFont, // 使用平台默认字体
        fontFamilyFallback: platformFontFamilyFallback,
        colorScheme: ColorScheme(
          brightness: Brightness.dark, // 设置亮度为深色模式
          primary: accentColor, // 主要颜色
          onPrimary: Colors.white, // 在主要颜色上的文本和图标颜色，确保对比度。
          secondary: accentColor, // 辅助颜色
          onSecondary: Colors.white, // 在辅助颜色上的文本和图标颜色，确保对比度。
          surface: Colors.black, // 表面颜色，深色模式下使用黑色。
          onSurface: Colors.white, // 在表面颜色上的文本和图标颜色，确保对比度。
          error: Colors.red, // 错误颜色
          onError: Colors.white, // 在错误颜色上的文本和图标颜色，确保对比度。
        ),
      ));
}
