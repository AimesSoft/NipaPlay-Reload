import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Next owns these values while its interface is open. The shared preference
/// keys are the data boundary; no Classic player object crosses it.
abstract interface class NextDanmakuSettingsTarget {
  Object? readSetting(String key);
  Future<void> writeSetting(String key, Object? value);
}

abstract final class NextDanmakuSettings {
  static NextDanmakuSettingsTarget? active;

  static const keys = <String, String>{
    'danmaku.visible': 'danmaku_visible',
    'danmaku.showDensityChart': 'show_danmaku_density_chart',
    'danmaku.randomColor': 'danmaku_random_color_enabled',
    'danmaku.stacking': 'danmaku_stacking',
    'danmaku.merge': 'merge_danmaku',
    'danmaku.blockTop': 'block_top_danmaku',
    'danmaku.blockBottom': 'block_bottom_danmaku',
    'danmaku.blockScroll': 'block_scroll_danmaku',
    'danmaku.opacity': 'danmaku_opacity',
    'danmaku.fontSize': 'danmaku_font_size',
    'danmaku.speedMultiplier': 'danmaku_speed_multiplier',
    'danmaku.displayArea': 'danmaku_display_area',
    'danmaku.trackGap': 'danmaku_dfm_plus_track_gap',
    'danmaku.outlineWidth': 'next2_danmaku_outline_width',
    'danmaku.outlineStyle': 'danmaku_outline_style',
    'danmaku.shadowStyle': 'danmaku_shadow_style',
    'danmaku.fontFamily': 'danmaku_font_family',
    'danmaku.fontFilePath': 'danmaku_font_file_path',
    'danmaku.blockWords': 'danmaku_block_words',
    'danmaku.rememberOffset': 'remember_danmaku_offset',
    'danmaku.manualOffset': '@runtime:danmaku.manualOffset',
    'player.introSkipEnabled': 'intro_skip_enabled',
  };

  static const defaults = <String, Object>{
    'danmaku.visible': true,
    'danmaku.showDensityChart': false,
    'danmaku.randomColor': false,
    'danmaku.stacking': false,
    'danmaku.merge': false,
    'danmaku.blockTop': false,
    'danmaku.blockBottom': false,
    'danmaku.blockScroll': false,
    'danmaku.opacity': 1.0,
    'danmaku.fontSize': 30.0,
    'danmaku.speedMultiplier': 1.0,
    'danmaku.displayArea': 1.0,
    'danmaku.trackGap': 0.15,
    'danmaku.outlineWidth': 2.0,
    'danmaku.outlineStyle': 'uniform',
    'danmaku.shadowStyle': 'strong',
    'danmaku.fontFamily': '',
    'danmaku.fontFilePath': '',
    'danmaku.blockWords': <String>[],
    'danmaku.rememberOffset': false,
    'danmaku.manualOffset': 0.0,
    'player.introSkipEnabled': true,
  };

  static Future<Map<String, Object?>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, Object?>{...defaults};
    for (final entry in keys.entries) {
      var value = prefs.get(entry.value);
      if (value == null) continue;
      if (entry.key == 'danmaku.blockWords' && value is String) {
        value = List<String>.from(jsonDecode(value) as List);
      }
      if (entry.key == 'danmaku.outlineStyle' && value is int) {
        value = ['none', 'stroke', 'uniform'][value.clamp(0, 2)];
      }
      if (entry.key == 'danmaku.shadowStyle' && value is int) {
        value = ['none', 'soft', 'medium', 'strong'][value.clamp(0, 3)];
      }
      values[entry.key] = value;
    }
    return values;
  }
}
