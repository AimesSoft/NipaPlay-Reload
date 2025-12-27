import 'package:shared_preferences/shared_preferences.dart';

enum DesktopExitBehavior {
  askEveryTime,
  minimizeToTrayOrTaskbar,
  closePlayer,
}

class DesktopExitPreferences {
  DesktopExitPreferences._();

  static const String key = 'desktop_exit_action';

  static const String _minimizeValue = 'minimize';
  static const String _closeValue = 'close';

  static DesktopExitBehavior parse(String? rawValue) {
    switch (rawValue) {
      case _minimizeValue:
        return DesktopExitBehavior.minimizeToTrayOrTaskbar;
      case _closeValue:
        return DesktopExitBehavior.closePlayer;
      default:
        return DesktopExitBehavior.askEveryTime;
    }
  }

  static String? serialize(DesktopExitBehavior behavior) {
    switch (behavior) {
      case DesktopExitBehavior.askEveryTime:
        return null;
      case DesktopExitBehavior.minimizeToTrayOrTaskbar:
        return _minimizeValue;
      case DesktopExitBehavior.closePlayer:
        return _closeValue;
    }
  }

  static Future<DesktopExitBehavior> load() async {
    final prefs = await SharedPreferences.getInstance();
    return parse(prefs.getString(key));
  }

  static Future<void> save(DesktopExitBehavior behavior) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = serialize(behavior);
    if (raw == null) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, raw);
  }
}

