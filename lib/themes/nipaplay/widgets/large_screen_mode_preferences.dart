import 'package:shared_preferences/shared_preferences.dart';

class LargeScreenModePreferences {
  LargeScreenModePreferences._();

  static const String key = 'nipaplay_use_large_screen_layout';

  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> save(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, enabled);
  }
}
