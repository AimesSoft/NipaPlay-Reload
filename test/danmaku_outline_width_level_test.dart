import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/danmaku/style.dart';

void main() {
  group('normalizeDanmakuOutlineWidthLevel', () {
    test('uses thin outline for missing or invalid settings', () {
      expect(normalizeDanmakuOutlineWidthLevel(null), 1.0);
      expect(normalizeDanmakuOutlineWidthLevel(double.nan), 1.0);
      expect(normalizeDanmakuOutlineWidthLevel(double.infinity), 1.0);
    });

    test('maps current values to off, thin, and thick levels', () {
      expect(normalizeDanmakuOutlineWidthLevel(0.0), 0.0);
      expect(normalizeDanmakuOutlineWidthLevel(1.0), 1.0);
      expect(normalizeDanmakuOutlineWidthLevel(2.0), 2.0);
    });

    test('migrates legacy continuous values without losing outlines', () {
      expect(normalizeDanmakuOutlineWidthLevel(-1.0), 0.0);
      expect(normalizeDanmakuOutlineWidthLevel(0.05), 1.0);
      expect(normalizeDanmakuOutlineWidthLevel(1.49), 1.0);
      expect(normalizeDanmakuOutlineWidthLevel(1.5), 2.0);
      expect(normalizeDanmakuOutlineWidthLevel(4.0), 2.0);
    });

    test('uses a three-level slider in every danmaku settings surface', () {
      final globalSettings =
          File('lib/settings/pages/danmaku_settings_content.dart')
              .readAsStringSync();
      final cupertinoMenu = File(
        'lib/themes/cupertino/widgets/player_menu/cupertino_danmaku_settings_pane.dart',
      ).readAsStringSync();
      final nipaplayMenu = File(
        'lib/themes/nipaplay/widgets/danmaku_settings_menu.dart',
      ).readAsStringSync();

      expect(globalSettings, contains('AdaptiveSettingsTile.slider('));
      expect(globalSettings, contains('divisions: 2'));
      expect(cupertinoMenu, contains('divisions: 2'));
      expect(nipaplayMenu, contains('step: 1.0'));
      expect(nipaplayMenu, contains('0 无描边 · 1 细边 · 2 粗边（原版）'));
      expect(
        '$globalSettings$cupertinoMenu$nipaplayMenu',
        isNot(contains('setNext2DanmakuOutlineWidth(value ? 1.0 : 0.0)')),
      );
    });
  });
}
