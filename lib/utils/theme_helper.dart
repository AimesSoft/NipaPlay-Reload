// theme_helper.dart
import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_provider.dart';
import 'package:provider/provider.dart';

// 获取当前主题状态
bool getCurrentThemeMode(BuildContext context, bool modeSwitch) {
  context.watch<ThemeProvider>().isDarkMode;
  if (modeSwitch == true) {
    isDarkModeValue = context.watch<ThemeProvider>().isDarkMode;
  } else {
    isDarkModeValue = isDarkMode(context);  // 假设你有这个方法获取系统模式
  }

  return isDarkModeValue;
}