import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/next_playback.dart';
import 'package:nipaplay/utils/video_aspect_geometry.dart';
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/settings_data.dart';
import 'package:nipaplay/next/ui/player/menu_controls.dart';
import 'package:nipaplay/next/ui/player/player_menus.dart';
import 'package:nipaplay/next/ui/player/player_more.dart';
import 'package:nipaplay/next/ui/settings/controls.dart' show NextToggle;

import 'player_test_support.dart';

/// The registry rows the player's pages read, and what they set.
final class _Settings implements NextSettingsData {
  _Settings(this.rows);
  final List<Map<String, Object?>> rows;
  final sets = <(String, Object?)>[];
  final resets = <List<String>>[];

  @override
  Future<List<UiSetting>> settings() async =>
      [for (final r in rows) UiSetting.fromRow(r)];

  @override
  Future<UiSetting> set(String key, Object? value) async {
    sets.add((key, value));
    final row = rows.firstWhere((r) => r['key'] == key);
    row['value'] = value;
    return UiSetting.fromRow(row);
  }

  @override
  Future<void> reset(List<String> keys) async => resets.add(keys);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _number(String key, num value, num min, num max) =>
    {'key': key, 'type': 'number', 'value': value, 'default': value,
      'minimum': min, 'maximum': max};
Map<String, Object?> _bool(String key, bool value) =>
    {'key': key, 'type': 'boolean', 'value': value, 'default': value};
Map<String, Object?> _text(String key, String value, [List<String>? choices]) =>
    {'key': key, 'type': 'string', 'value': value, 'default': value,
      if (choices != null) 'enum': choices};

class _State extends FakePlayerState {
  @override
  bool get supportsVideoAspectModes => false;
  @override
  VideoAspectMode get videoAspectMode => VideoAspectMode.contain;
}

/// A file NipaPlay draws over the video.
class _OverlayPlayback extends FakePlayback {
  _OverlayPlayback() : super(FakePlayerState());
  @override
  String? drawnOver(SubtitleChoice? on) => on?.path;
}

Widget _host(Widget child) => MaterialApp(
      home: Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: Alignment.bottomRight,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(1280, 800)),
            child: child,
          ),
        ),
      ),
    );

void main() {
  testWidgets('a file drawn over the video: its own colour, font, outline, '
      'and the shared weight; a switch sets the registry', (tester) async {
    final settings = _Settings([
      _text('subtitle.externalColor', '#FFFFFFFF'),
      _text('subtitle.externalFontName', ''),
      _bool('subtitle.bold', false),
      _bool('subtitle.italic', false),
      _number('subtitle.opacity', 1.0, 0, 1),
      _number('subtitle.borderSize', 3.0, 0, 10),
      _number('subtitle.shadowOffset', 0.0, 0, 10),
      _text('subtitle.alignX', 'center', ['left', 'center', 'right']),
      _text('subtitle.color', '#FFFFFFFF'),
    ]);
    await tester.pumpWidget(_host(PlayerMenuSurface(
      width: 320,
      child: SubtitleStylePage(
        playback: _OverlayPlayback(),
        settings: settings,
        on: const SubtitleChoice.file('第1集', '/v/1.srt', selected: true),
        onBack: () {},
      ),
    )));
    await tester.pumpAndSettle();
    for (final label in ['颜色', '字体', '粗体', '斜体', '不透明度', '描边粗细', '水平对齐']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The kernel's own colour is not this file's.
    expect(find.text('文字'), findsNothing);
    await tester.tap(
        find.byWidgetPredicate((w) => w is NextToggle && w.label == '粗体'));
    await tester.pumpAndSettle();
    expect(settings.sets, [('subtitle.bold', true)]);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(settings.resets.single, contains('subtitle.externalColor'));
  });

  testWidgets('⋯ › 播放设置: the seek step and the held speed, a step a click',
      (tester) async {
    final settings = _Settings([
      _number('seek.stepSeconds', 10.0, 1 / 24, 600),
      _number('seek.speedBoostRate', 2.0, 0.01, 5),
      _bool('player.timelinePreviewEnabled', false),
      _bool('danmaku.showDensityChart', false),
    ]);
    await tester.pumpWidget(_host(MoreMenu(
      playback: FakePlayback(_State()),
      settings: settings,
      calls: GuiCalls.none(),
      onScreenshot: () {},
      onPictureInPicture: () {},
    )));
    await tester.tap(find.text('播放设置'));
    await tester.pumpAndSettle();
    expect(find.text('10 秒'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('快进快退加'));
    await tester.pumpAndSettle();
    expect(settings.sets, [('seek.stepSeconds', 11.0)]);
    expect(find.text('11 秒'), findsOneWidget);
  });
}
