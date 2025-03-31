// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light, // 设置亮度为浅色模式
    colorScheme: ColorScheme(
      brightness: Brightness.light, // 设置颜色方案的亮度为浅色模式
      primary: Colors.white.withOpacity(0.35), // 主要颜色，用于应用的主要交互元素，如选中的标签、按钮等。这里使用了带透明度的白色。
      onPrimary: Colors.white, // 在主要颜色上的文本和图标颜色，确保对比度。
      secondary: Colors.grey[300]!, // 辅助颜色，用于应用中不那么突出的元素，如背景、分割线等。
      onSecondary: Colors.black, // 在辅助颜色上的文本和图标颜色，确保对比度。
      surface: Colors.white, // 表面颜色，用于卡片、对话框等表面元素。
      onSurface: Colors.white, // 在表面颜色上的文本和图标颜色，确保对比度。
      error: Colors.red, // 错误颜色，用于显示错误信息。
      onError: Colors.white, // 在错误颜色上的文本和图标颜色，确保对比度。
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark, // 设置亮度为深色模式
    colorScheme: ColorScheme(
      brightness: Brightness.dark, // 设置颜色方案的亮度为深色模式
      primary: Colors.grey[500]!.withOpacity(0.4), // 主要颜色，在深色模式下使用深灰色，带透明度。
      onPrimary: Colors.white, // 在主要颜色上的文本和图标颜色，确保对比度。
      secondary: Colors.grey[300]!, // 辅助颜色，深色模式下使用灰色。
      onSecondary: Colors.white, // 在辅助颜色上的文本和图标颜色，确保对比度。
      surface: Colors.white, // 表面颜色，深色模式下使用白色。
      onSurface: Colors.white, // 在表面颜色上的文本和图标颜色，确保对比度。
      error: Colors.red, // 错误颜色，用于显示错误信息。
      onError: Colors.white, // 在错误颜色上的文本和图标颜色，确保对比度。
    ),
  );
}