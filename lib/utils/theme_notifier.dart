// ThemeNotifier.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class ThemeNotifier with ChangeNotifier {
  ThemeMode _themeMode;
  double _blurPower; // 修改 blurPower 变量类型为 double

  ThemeNotifier({
    ThemeMode initialThemeMode = ThemeMode.system,
    required double initialBlurPower, // 修改初始 blurPower 值类型为 double
  })  : _themeMode = initialThemeMode,
        _blurPower = initialBlurPower;

  ThemeMode get themeMode => _themeMode;
  double get blurPower => _blurPower; // 修改 blurPower getter 类型为 double

  set themeMode(ThemeMode mode) {
    _themeMode = mode;
    SettingsStorage.saveString('themeMode', mode.toString().split('.').last).then((_) {
      //print('Theme mode saved: ${mode.toString().split('.').last}'); // 添加日志输出
    });
    notifyListeners();
  } 

  set blurPower(double blur) {
    _blurPower = blur;
    SettingsStorage.saveDouble('blurPower', _blurPower).then((_) { // 使用 saveDouble
      //print('Blur power saved: $_blurPower'); // 添加日志输出
    });
    notifyListeners();
  }

}