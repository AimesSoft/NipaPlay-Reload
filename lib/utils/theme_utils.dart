import 'package:flutter/material.dart';

// 根据当前主题模式返回标题的 TextStyle
TextStyle getTitleTextStyle(BuildContext context) {
  // 返回相应的 TextStyle
  return const TextStyle(
    fontWeight: FontWeight.bold, // 设置加粗
    fontSize: 16, // 设置字体大小
    color: Colors.white, // 根据主题模式设置字体颜色
  );
}
TextStyle getTextStyle(BuildContext context) {
  // 返回相应的 TextStyle
  return const TextStyle(
    fontWeight: FontWeight.normal, // 设置加粗
    fontSize: 16, // 设置字体大小
    color: Colors.white, // 根据主题模式设置字体颜色
  );
}