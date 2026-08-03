import 'package:shared_preferences/shared_preferences.dart';

class LargeScreenModePreferences {
  LargeScreenModePreferences._();

  static const String key = 'nipaplay_use_large_screen_layout';

  static Future<bool> load({bool defaultValue = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  static Future<void> save(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, enabled);
  }
}
