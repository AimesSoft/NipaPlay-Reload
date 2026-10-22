import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/danmaku/sidecar.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/settings/application_settings.dart';
import 'package:nipaplay/next/settings/classic_settings.dart';
import 'package:nipaplay/next/settings/download_settings.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/settings/setting_descriptions.dart';
import 'package:nipaplay/next/settings/system_settings.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';

import 'media_test_support.dart';

/// 兜底说明的特征：只把设置名字再说一遍，不说值的含义。
final _boilerplate = [
  RegExp(r'^调整'),
  RegExp(r'沿用当前播放器的即时应用方式'),
  RegExp(r'复用 Classic 的持久化与应用方式'),
  RegExp(r'保存偏好，生效方式为'),
];

void main() {
  late MediaFixture media;
  late SubtitleLibrary subtitles;
  late List<SettingEntry> entries;

  setUp(() async {
    media = MediaFixture();
    await media.open();
    subtitles = SubtitleLibrary(media.service, media.root);
    entries = [
      ...ApplicationSettings.entries(),
      ...ClassicSettings.entries(),
      ...SystemSettings(
              SidecarIndexer(DanmakuStore(media.identities), () async {}),
              subtitles)
          .entries(),
      ...DownloadSettings.entries(),
      NextUiPreference.setting(),
    ];
  });

  tearDown(() async {
    await subtitles.close();
    await media.close();
  });

  test('every registered setting says what its value means', () {
    expect(entries.length, greaterThan(200));
    final problems = <String>[];
    for (final entry in entries) {
      final text = entry.description.trim();
      if (text.isEmpty) {
        problems.add('${entry.key}: empty description');
        continue;
      }
      if (text == entry.title || text == entry.key) {
        problems.add('${entry.key}: description repeats the name');
      }
      for (final pattern in _boilerplate) {
        if (pattern.hasMatch(text)) {
          problems.add('${entry.key}: boilerplate "$text"');
        }
      }
      if (text.length < 8) {
        problems.add('${entry.key}: too short "$text"');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('description tables only name settings that exist', () {
    final keys = {for (final entry in entries) entry.key};
    final stale = <String>[
      for (final table in [
        applicationSettingDescriptions,
        classicSettingDescriptions,
        systemSettingDescriptions,
      ])
        for (final key in table.keys)
          if (!keys.contains(key)) key,
    ];
    expect(stale, isEmpty);
  });

  test('a saved-only apply mode is stated after the meaning', () {
    expect(describeWithApply('含义。', 'immediate'), '含义。');
    expect(describeWithApply('含义。', 'reload_player'), contains('下次打开媒体时重建播放器'));
    expect(describeWithApply('含义。', 'restart_app'), contains('重启应用后生效'));
  });
}
