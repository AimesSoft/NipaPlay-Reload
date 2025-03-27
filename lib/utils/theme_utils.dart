import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart'; // 引入主题相关方法

// 根据当前主题模式返回标题的 TextStyle
TextStyle getTitleTextStyle(BuildContext context) {
  // 获取当前主题模式（夜间模式或日间模式）
  isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
  
  // 根据主题模式决定字体颜色
  Color textColor = isDarkModeValue ? const Color.fromARGB(255, 219, 219, 219) : const Color.fromARGB(255, 54, 54, 54);

  // 返回相应的 TextStyle
  return TextStyle(
    fontWeight: FontWeight.bold, // 设置加粗
    fontSize: 15, // 设置字体大小
    color: textColor, // 根据主题模式设置字体颜色
  );
}
TextStyle getBarTitleTextStyle(BuildContext context) {
  // 获取当前主题模式（夜间模式或日间模式）
  isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
  
  // 根据主题模式决定字体颜色
  Color textColor = isDarkModeValue ? const Color.fromARGB(255, 219, 219, 219) : const Color.fromARGB(255, 54, 54, 54);

  // 返回相应的 TextStyle
  return TextStyle(
    fontWeight: FontWeight.bold, // 设置加粗
    fontSize: 20, // 设置字体大小
    color: textColor, // 根据主题模式设置字体颜色
  );
}
TextStyle getBarTextStyle(BuildContext context) {
  // 获取当前主题模式（夜间模式或日间模式）
  isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
  
  // 根据主题模式决定字体颜色
  Color textColor = isDarkModeValue ? const Color.fromARGB(255, 219, 219, 219) : const Color.fromARGB(255, 54, 54, 54);

  // 返回相应的 TextStyle
  return TextStyle(
    fontWeight: FontWeight.normal, // 设置加粗
    fontSize: 15, // 设置字体大小
    color: textColor, // 根据主题模式设置字体颜色
  );
}
TextStyle getToggleTextStyle(BuildContext context) {
  // 获取当前主题模式（夜间模式或日间模式）
  isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
  
  // 根据主题模式决定字体颜色
  Color textColor = isDarkModeValue ? const Color.fromARGB(255, 202, 202, 202) : const Color.fromARGB(255, 54, 54, 54);

  // 返回相应的 TextStyle
  return TextStyle(
    fontWeight: FontWeight.normal, // 设置加粗
    fontSize: 14, // 设置字体大小
    color: textColor, // 根据主题模式设置字体颜色
  );
}
TextStyle getIconTextStyle(BuildContext context) {
  // 获取当前主题模式（夜间模式或日间模式）
  isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
  
  // 根据主题模式决定字体颜色
  Color textColor = isDarkModeValue ? const Color.fromARGB(255, 219, 219, 219) : const Color.fromARGB(255, 54, 54, 54);

  // 返回相应的 TextStyle
  return TextStyle(
    fontWeight: FontWeight.w600, // 设置加粗
    fontSize: 10, // 设置字体大小
    color: textColor, // 根据主题模式设置字体颜色
  );
}
TextStyle getVersionTextStyle(BuildContext context) {
  Color textColor =  const Color.fromARGB(255, 131, 131, 131);

  // 返回相应的 TextStyle
  return TextStyle(
    fontWeight: FontWeight.normal, // 设置加粗
    fontSize: 13, // 设置字体大小
    color: textColor, // 根据主题模式设置字体颜色
  );
}