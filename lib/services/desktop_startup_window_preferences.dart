import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

enum DesktopStartupWindowState {
  windowed,
  maximized,
}

enum DesktopStartupWindowPosition {
  topLeft,
  topRight,
  center,
  bottomLeft,
  bottomRight,
}

class DesktopStartupWindowPreferences {
  DesktopStartupWindowPreferences._();

  static const Size minWindowSize = Size(600, 400);
  static const Size defaultWindowSize = Size(1280, 720);
  static const DesktopStartupWindowState defaultState =
      DesktopStartupWindowState.maximized;
  static const DesktopStartupWindowPosition defaultPosition =
      DesktopStartupWindowPosition.center;

  static const String _stateKey = 'desktop_startup_window_state';
  static const String _positionKey = 'desktop_startup_window_position';
  static const String _widthKey = 'desktop_startup_window_width';
  static const String _heightKey = 'desktop_startup_window_height';

  static DesktopStartupWindowState parseState(String? rawValue) {
    switch (rawValue) {
      case 'windowed':
        return DesktopStartupWindowState.windowed;
      case 'maximized':
      default:
        return defaultState;
    }
  }

  static String serializeState(DesktopStartupWindowState state) {
    switch (state) {
      case DesktopStartupWindowState.windowed:
        return 'windowed';
      case DesktopStartupWindowState.maximized:
        return 'maximized';
    }
  }

  static DesktopStartupWindowPosition parsePosition(String? rawValue) {
    switch (rawValue) {
      case 'topLeft':
        return DesktopStartupWindowPosition.topLeft;
      case 'topRight':
        return DesktopStartupWindowPosition.topRight;
      case 'bottomLeft':
        return DesktopStartupWindowPosition.bottomLeft;
      case 'bottomRight':
        return DesktopStartupWindowPosition.bottomRight;
      case 'center':
      default:
        return defaultPosition;
    }
  }

  static String serializePosition(DesktopStartupWindowPosition position) {
    switch (position) {
      case DesktopStartupWindowPosition.topLeft:
        return 'topLeft';
      case DesktopStartupWindowPosition.topRight:
        return 'topRight';
      case DesktopStartupWindowPosition.center:
        return 'center';
      case DesktopStartupWindowPosition.bottomLeft:
        return 'bottomLeft';
      case DesktopStartupWindowPosition.bottomRight:
        return 'bottomRight';
    }
  }

  static Size sanitizeSize(Size size) {
    final double width = size.width < minWindowSize.width
        ? minWindowSize.width
        : size.width;
    final double height = size.height < minWindowSize.height
        ? minWindowSize.height
        : size.height;
    return Size(width, height);
  }

  static Future<DesktopStartupWindowState> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    return parseState(prefs.getString(_stateKey));
  }

  static Future<void> saveState(DesktopStartupWindowState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, serializeState(state));
  }

  static Future<DesktopStartupWindowPosition> loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    return parsePosition(prefs.getString(_positionKey));
  }

  static Future<void> savePosition(DesktopStartupWindowPosition position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_positionKey, serializePosition(position));
  }

  static Future<Size> loadSize() async {
    final prefs = await SharedPreferences.getInstance();
    final double width =
        prefs.getDouble(_widthKey) ?? defaultWindowSize.width;
    final double height =
        prefs.getDouble(_heightKey) ?? defaultWindowSize.height;
    return sanitizeSize(Size(width, height));
  }

  static Future<void> saveSize(Size size) async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = sanitizeSize(size);
    await prefs.setDouble(_widthKey, resolved.width);
    await prefs.setDouble(_heightKey, resolved.height);
  }

  static Future<void> resetSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_widthKey);
    await prefs.remove(_heightKey);
  }
}
