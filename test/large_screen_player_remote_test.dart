import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_player_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_scaffold_layout.dart';

void main() {
  test('visible large-screen controls receive navigation and select keys', () {
    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.select,
    ]) {
      expect(
        shouldDelegateLargeScreenPlayerKeyToControls(
          isLargeScreen: true,
          controlsVisible: true,
          key: key,
        ),
        isTrue,
      );
    }
  });

  test('hidden controls leave direction keys to playback shortcuts', () {
    expect(
      shouldDelegateLargeScreenPlayerKeyToControls(
        isLargeScreen: true,
        controlsVisible: false,
        key: LogicalKeyboardKey.arrowRight,
      ),
      isFalse,
    );
  });

  test('large-screen playback consumes route pop while video is active', () {
    expect(
      shouldConsumeLargeScreenPlaybackPop(
        isLargeScreen: true,
        hasVideo: true,
      ),
      isTrue,
    );
    expect(
      shouldConsumeLargeScreenPlaybackPop(
        isLargeScreen: false,
        hasVideo: true,
      ),
      isFalse,
    );
  });

  test('player menu press reveals controls before opening the player menu', () {
    expect(
      resolveLargeScreenPlayerMenuTarget(controlsVisible: false),
      NipaplayLargeScreenPlayerMenuTarget.revealControls,
    );
    expect(
      resolveLargeScreenPlayerMenuTarget(controlsVisible: true),
      NipaplayLargeScreenPlayerMenuTarget.openPlayerMenu,
    );
  });

  test('large-screen player exposes only television-ready chrome actions', () {
    final source = File('lib/pages/play_video_page.dart').readAsStringSync();
    final controlsStart = source.indexOf(
      'Widget _buildLargeScreenMaterialControls',
    );
    final controlsEnd = source.indexOf(
      'void _syncLargeScreenPlayerControlFocus',
    );
    final controls = source.substring(controlsStart, controlsEnd);

    expect(controls, isNot(contains("tooltip: '返回'")));
    expect(controls, isNot(contains("tooltip: '发送弹幕'")));
    expect(controls, isNot(contains('videoState.toggleDanmakuVisible()')));
    expect(controls, isNot(contains("tooltip: '投屏 (AirPlay)'")));
    expect(controls, isNot(contains("tooltip: '截图'")));
    expect(controls, isNot(contains("tooltip: '分享'")));
    expect(controls, isNot(contains("'退出全屏'")));
    expect(controls, isNot(contains("'全屏'")));

    final menu = File(
      'lib/themes/nipaplay/widgets/large_screen_player_menu_panel.dart',
    ).readAsStringSync();
    expect(menu, contains('required this.initialFocusNode'));
    expect(menu, contains('PlayerMenuDefinitionBuilder'));
    expect(menu, contains('NipaplayLargeScreenPlayerMenuTab'));
    expect(menu, contains('NipaplayLargeScreenPlayerMenuPaneHost'));
    expect(menu, contains("title: const Text('返回媒体库')"));
    expect(menu, contains("title: const Text('发送弹幕')"));
    expect(menu, contains("title: const Text('显示弹幕')"));
    expect(menu, isNot(contains("'进入全屏'")));
    expect(menu, isNot(contains("'窗口适配视频'")));

    final components = File(
      'lib/themes/nipaplay/widgets/large_screen_player_menu_components.dart',
    ).readAsStringSync();
    expect(components, contains('class NipaplayLargeScreenPlayerMenuTile'));
    expect(
      components,
      contains('class NipaplayLargeScreenPlayerMenuActionSurface'),
    );
  });
}
