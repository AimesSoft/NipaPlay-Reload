import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/registry.dart';

/// F-owned settings use shared storage and provenance, without invoking a
/// Classic player setter (or its preview warning/decoder) while Next is open.
Future<bool> writeNextFeatureSetting(
    String key, String storageKey, Object? value) async {
  const keys = {
    'player.volume',
    'player.volumeBoost',
    'playback.rate',
    'player.timelinePreviewEnabled',
    'player.videoAspectMode',
    'player.screenshotSaveTarget',
    'player.screenshotQuality',
    'player.screenshotFormat',
    'player.screenshotIncludeDanmaku',
    'player.screenshotIncludeSubtitles',
    'player.screenshotCropLetterbox',
  };
  if (!keys.contains(key)) return false;
  final stored = switch (key) {
    'player.screenshotSaveTarget' =>
      ['ask', 'photos', 'file'].indexOf(value as String),
    'player.screenshotQuality' =>
      ['standard', 'high', 'ultra', 'max'].indexOf(value as String),
    _ => value,
  };
  final prefs = await SharedPreferences.getInstance();
  await SettingsAccess.persist(storageKey, () async {
    switch (stored) {
      case bool value:
        return prefs.setBool(storageKey, value);
      case int value:
        return prefs.setInt(storageKey, value);
      case double value:
        return prefs.setDouble(storageKey, value);
      case String value:
        return prefs.setString(storageKey, value);
      default:
        throw ArgumentError.value(value, key);
    }
  });
  return true;
}
