// ThemeNotifier.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class ThemeNotifier with ChangeNotifier {
  ThemeMode _themeMode;
  double _blurPower;
  String _backgroundImageMode;
  String _customBackgroundPath;

  ThemeNotifier({
    ThemeMode initialThemeMode = ThemeMode.system,
    required double initialBlurPower,
    String initialBackgroundImageMode = "看板娘",
    String initialCustomBackgroundPath = 'assets/backempty.png',
  })  : _themeMode = initialThemeMode,
        _blurPower = initialBlurPower,
        _backgroundImageMode = initialBackgroundImageMode,
        _customBackgroundPath = initialCustomBackgroundPath;

  ThemeMode get themeMode => _themeMode;
  double get blurPower => _blurPower;
  String get backgroundImageMode => _backgroundImageMode;
  String get customBackgroundPath => _customBackgroundPath;

  set themeMode(ThemeMode mode) {
    _themeMode = mode;
    SettingsStorage.saveString('themeMode', mode.toString().split('.').last).then((_) {
      //////print('Theme mode saved: ${mode.toString().split('.').last}'); // 添加日志输出
    });
    notifyListeners();
  } 

  set blurPower(double blur) {
    _blurPower = blur;
    SettingsStorage.saveDouble('blurPower', _blurPower).then((_) { // 使用 saveDouble
      //////print('Blur power saved: $_blurPower'); // 添加日志输出
    });
    notifyListeners();
  }

  set backgroundImageMode(String mode) {
    if (_backgroundImageMode != mode) {
      _backgroundImageMode = mode;
      SettingsStorage.saveString('backgroundImageMode', mode).then((_) {
        //////print('Background image mode saved: $mode'); // 添加日志输出
      });
      globals.backgroundImageMode = mode; // 更新全局变量
      notifyListeners();
    }
  }

  set customBackgroundPath(String path) {
    if (_customBackgroundPath != path) {
      _customBackgroundPath = path;
      SettingsStorage.saveString('customBackgroundPath', path).then((_) {
        //////print('Custom background path saved: $path'); // 添加日志输出
      });
      globals.customBackgroundPath = path; // 更新全局变量
      notifyListeners();
    }
  }
}