import 'package:flutter/material.dart';  // 确保这行代码存在
class SettingsService {
  String _backgroundImage = "default.jpg";
  Color _primaryColor = Colors.blue;

  String get backgroundImage => _backgroundImage;
  Color get primaryColor => _primaryColor;

  // 设置背景图片
  void setBackgroundImage(String imageName) {
    _backgroundImage = imageName;
    print('Background image set to $imageName');
  }

  // 设置主色调
  void setPrimaryColor(Color color) {
    _primaryColor = color;
    print('Primary color set to $color');
  }
}
