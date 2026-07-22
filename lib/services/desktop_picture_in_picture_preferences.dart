import 'package:shared_preferences/shared_preferences.dart';

enum DesktopPictureInPicturePosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class DesktopPictureInPicturePreferences {
  DesktopPictureInPicturePreferences._();

  static const DesktopPictureInPicturePosition defaultPosition =
      DesktopPictureInPicturePosition.topRight;
  static const String _positionKey =
      'desktop_picture_in_picture_window_position';

  static DesktopPictureInPicturePosition parsePosition(String? rawValue) {
    return switch (rawValue) {
      'topLeft' => DesktopPictureInPicturePosition.topLeft,
      'bottomLeft' => DesktopPictureInPicturePosition.bottomLeft,
      'bottomRight' => DesktopPictureInPicturePosition.bottomRight,
      'topRight' || _ => defaultPosition,
    };
  }

  static String serializePosition(DesktopPictureInPicturePosition position) {
    return switch (position) {
      DesktopPictureInPicturePosition.topLeft => 'topLeft',
      DesktopPictureInPicturePosition.topRight => 'topRight',
      DesktopPictureInPicturePosition.bottomLeft => 'bottomLeft',
      DesktopPictureInPicturePosition.bottomRight => 'bottomRight',
    };
  }

  static Future<DesktopPictureInPicturePosition> loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    return parsePosition(prefs.getString(_positionKey));
  }

  static Future<void> savePosition(
    DesktopPictureInPicturePosition position,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_positionKey, serializePosition(position));
  }
}
