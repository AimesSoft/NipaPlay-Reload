// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/linux_system_font_loader.dart';

class AppTheme {
  // 获取适合当前平台的默认字体
  static String? get _platformDefaultFont {
    if (kIsWeb) return null; // Web平台使用浏览器默认字体
    return Platform.isWindows ? "微软雅黑" : null;
  }

  static List<String>? get platformFontFamilyFallback {
    if (kIsWeb) return null;
    return Platform.isLinux ? linuxSystemFontFallback : null;
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
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.light,
      fontFamily: _platformDefaultFont,
      fontFamilyFallback: platformFontFamilyFallback,
    );
  }

  static ThemeData material3DarkTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      fontFamily: _platformDefaultFont,
      fontFamilyFallback: platformFontFamilyFallback,
    );
  }

  static ThemeData lightTheme(Color accentColor) => ThemeData(
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
      );

  static ThemeData darkTheme(Color accentColor) => ThemeData(
        brightness: Brightness.dark, // 设置亮度为深色模式
        fontFamily: _platformDefaultFont, // 使用平台默认字体
        fontFamilyFallback: platformFontFamilyFallback,
        colorScheme: ColorScheme(
          brightness: Brightness.dark, // 设置颜色方案的亮度为深色模式
          primary: accentColor, // 主要颜色
          onPrimary: Colors.white, // 在主要颜色上的文本和图标颜色，确保对比度。
          secondary: accentColor, // 辅助颜色
          onSecondary: Colors.white, // 在辅助颜色上的文本和图标颜色，确保对比度。
          surface: Colors.black, // 表面颜色，深色模式下使用黑色。
          onSurface: Colors.white, // 在表面颜色上的文本和图标颜色，确保对比度。
          error: Colors.red, // 错误颜色，用于显示错误信息。
          onError: Colors.white, // 在错误颜色上的文本和图标颜色，确保对比度。
        ),
      );
}
