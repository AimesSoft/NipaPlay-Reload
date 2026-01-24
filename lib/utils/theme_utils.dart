import 'package:flutter/material.dart';

// 根据当前主题模式返回标题的 TextStyle
TextStyle getTitleTextStyle(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: isDark ? Colors.white : Colors.black87,
  );
}
TextStyle getTextStyle(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return TextStyle(
    fontWeight: FontWeight.normal,
    fontSize: 16,
    color: isDark ? Colors.white : Colors.black87,
  );
}