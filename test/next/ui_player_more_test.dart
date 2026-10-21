import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/next/ui/player/menu_controls.dart';
import 'package:nipaplay/next/ui/player/player_more.dart';
import 'package:nipaplay/next/ui/player/timeline.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';

/// What Classic's bar and player menu offer while watching, in Next's
/// controls: ⋯ (the speed, the audio track, the picture's fit, the
/// danmaku's look, a still, picture in picture) and the subtitle menu's
/// timing and size. Each sets Classic's own state, in Classic's own
/// settings; the player kernel is told as by Classic's menus.
void main() {
  setUp(() {
    // Classic's state reads its settings as it is made.
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 78.0, 'fullScreen': false});
    NextShell.debugServices = (_) => playerTestServices();
  });
  tearDown(() => NextShell.debugServices = null);

  Finder button(String label) =>
      find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

  Finder valueOf(String row, String value) =>
      find.descendant(of: button(row), matching: find.text(value));

  Future<void> open(WidgetTester tester, [String? page]) async {
    await tester.tap(button('更多'));
    await tester.pumpAndSettle();
    if (page != null) {
      await tester.tap(button(page));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('⋯ is in the bar; its menu holds what the bar has no room for',
      (tester) async {
    final p = await pumpClassicPlayer(tester);
    await tester.pump();
    expect(button('更多').hitTestable(), findsOneWidget);
    // The time and the full screen button stay where they were.
    expect(button('全屏').hitTestable(), findsOneWidget);
    expect(find.text('1.0×'), findsNothing,
        reason: 'the normal speed is not shown in the bar');

    await open(tester);
    expect(find.byType(MoreMenu), findsOneWidget);
    expect(p.playback.holds, 1, reason: "Classic's hotkeys rest meanwhile");
    expect(valueOf('倍速', '1.0×'), findsOneWidget);
    expect(valueOf('音轨', '日语'), findsOneWidget);
    expect(valueOf('画面', '适应'), findsOneWidget);
    for (final label in ['弹幕', '截图', '画中画']) {
      expect(button(label).hitTestable(), findsOneWidget, reason: label);
    }

    // A click anywhere else puts it away.
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.byType(MoreMenu), findsNothing);
    expect(p.playback.holds, 0);
  });

  testWidgets('the speed: Classic plays at it, and the bar says so',
      (tester) async {
    final p = await pumpClassicPlayer(tester);
    await open(tester, '倍速');
    for (final r in [
      '0.5×',
      '0.75×',
      '1.0×',
      '1.25×',
      '1.5×',
      '2.0×',
      '3.0×'
    ]) {
      expect(button(r), findsOneWidget, reason: r);
    }
    await tester.tap(button('1.5×'));
    await tester.pumpAndSettle();
    expect(p.state.playbackRate, 1.5);
    expect(p.state.kernel.playbackRate, 1.5, reason: 'the player was told');
    expect(valueOf('倍速', '1.5×'), findsOneWidget, reason: 'back on the menu');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MoreMenu), findsNothing);
    final time =
        tester.getRect(find.textContaining('14:32', findRichText: true));
    final rate = tester.getRect(find.text('1.5×'));
    expect(rate.left, greaterThan(time.right),
        reason: 'beside the time while it is not the normal speed');
    expect(
        rate.top, greaterThan(tester.getRect(find.byType(PlayerTimeline)).top));
  });

  testWidgets('a speed Classic was set to, not among the usual, is listed',
      (tester) async {
    final p = await pumpClassicPlayer(tester);
    await p.state.setPlaybackRate(2.5);
    await tester.pump();
    await open(tester, '倍速');
    expect(button('2.5×'), findsOneWidget);
    await tester.tap(button('1.0×'));
    await tester.pumpAndSettle();
    expect(p.state.playbackRate, 1);
  });

  testWidgets('the audio track: Classic switches the player to it',
      (tester) async {
    final p = await pumpClassicPlayer(tester);
    await open(tester, '音轨');
    expect(button('日语'), findsOneWidget);
    await tester.tap(button('评论音轨'));
    await tester.pumpAndSettle();
    expect(p.state.kernel.activeAudioTracks, [1]);
    expect(valueOf('音轨', '评论音轨'), findsOneWidget);
  });

  testWidgets('one audio track: nothing to choose', (tester) async {
    final kernel = ClassicKernel();
    kernel.mediaInfo =
        kernel.mediaInfo.copyWith(audio: kernel.mediaInfo.audio!.sublist(0, 1));
    await pumpClassicPlayer(tester, state: ClassicPlayerState(kernel));
    await open(tester);
    expect(button('音轨'), findsNothing);
    expect(button('倍速'), findsOneWidget);
  });

  testWidgets('the picture: Classic fits it so, and keeps it', (tester) async {
    final p = await pumpClassicPlayer(tester);
    await open(tester, '画面');
    for (final label in MoreMenuState.fitLabels.values) {
      expect(button(label), findsOneWidget, reason: label);
    }
    await tester.tap(button('裁剪'));
    await tester.pumpAndSettle();
    expect(p.state.videoAspectMode, VideoAspectMode.cover);
    expect(valueOf('画面', '裁剪'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('video_aspect_mode'), 'cover');
  });

  testWidgets('danmaku: opacity, size, area, kinds kept away, timing',
      (tester) async {
    final p = await pumpClassicPlayer(tester);
    await open(tester, '弹幕');
    expect(find.byType(PlayerMenuBack), findsOneWidget);

    Finder slider(String label) => find
        .byWidgetPredicate((w) => w is PlayerMenuSlider && w.label == label);

    // Halfway along the opacity's track.
    final track = tester.getRect(slider('透明度'));
    await tester
        .tapAt(Offset(track.left + (track.width - 48) / 2, track.center.dy));
    await tester.pumpAndSettle();
    expect(p.state.danmakuOpacity, closeTo(0.5, 0.02));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(SettingsKeys.danmakuOpacity), closeTo(0.5, 0.02),
        reason: "Classic's own setting");
    expect(find.text('${(p.state.danmakuOpacity * 100).round()}%'),
        findsOneWidget);

    final before = p.state.actualDanmakuFontSize;
    await tester.drag(slider('字号'), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(p.state.danmakuFontSize, lessThan(before));
    expect(p.state.danmakuFontSize, greaterThanOrEqualTo(12));
    expect(find.text('${p.state.danmakuFontSize.round()}'), findsOneWidget);

    await tester.tap(button('1/4'));
    await tester.pumpAndSettle();
    expect(p.state.danmakuDisplayArea, 0.25);

    await tester.tap(button('顶部'));
    await tester.pumpAndSettle();
    await tester.tap(button('滚动'));
    await tester.pumpAndSettle();
    expect(p.state.blockTopDanmaku, isTrue);
    expect(p.state.blockScrollDanmaku, isTrue);
    expect(p.state.blockBottomDanmaku, isFalse);
    expect(prefs.getBool(SettingsKeys.blockTopDanmaku), isTrue);
    await tester.tap(button('顶部'));
    await tester.pumpAndSettle();
    expect(p.state.blockTopDanmaku, isFalse);

    await tester.tap(button('弹幕偏移加'));
    await tester.pump();
    await tester.tap(button('弹幕偏移加'));
    await tester.pump();
    expect(p.state.manualDanmakuOffset, 1.0);
    expect(find.text('+1.0s'), findsOneWidget);
    await tester.tap(button('弹幕偏移减'));
    await tester.tap(button('弹幕偏移减'));
    await tester.tap(button('弹幕偏移减'));
    await tester.pump();
    expect(p.state.manualDanmakuOffset, -0.5);
    expect(find.text('−0.5s'), findsOneWidget);
    await tester.tap(button('弹幕偏移复原'));
    await tester.pump();
    expect(p.state.manualDanmakuOffset, 0);

    // Esc goes back a page, then closes the menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerMenuBack), findsNothing);
    expect(button('倍速'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MoreMenu), findsNothing);
  });

  testWidgets('a page leads back with ‹', (tester) async {
    await pumpClassicPlayer(tester);
    await open(tester, '倍速');
    expect(button('倍速'), findsNothing);
    await tester.tap(button('返回').last);
    await tester.pumpAndSettle();
    expect(button('倍速'), findsOneWidget);
    expect(find.byType(MoreMenu), findsOneWidget);
  });

  testWidgets('the subtitle on: earlier or later, smaller or larger',
      (tester) async {
    final p = await pumpClassicPlayer(tester);
    await tester.tap(button('字幕'));
    await tester.pumpAndSettle();
    expect(button('简体中文'), findsOneWidget);
    expect(find.text('0s'), findsOneWidget);

    await tester.tap(button('偏移加'));
    await tester.pump();
    await tester.tap(button('偏移加'));
    await tester.pump();
    await tester.tap(button('偏移加'));
    await tester.pump();
    expect(p.state.subtitleDelaySeconds, closeTo(0.3, 0.001));
    expect(p.state.kernel.properties['sub-delay'], '0.30',
        reason: 'the player was told');
    expect(find.text('+0.3s'), findsOneWidget);

    // Held, it keeps going.
    final hold = await tester.startGesture(tester.getCenter(button('偏移减')));
    await tester.pump(const Duration(milliseconds: 1000));
    await hold.up();
    await tester.pump();
    expect(p.state.subtitleDelaySeconds, lessThan(-0.2));

    await tester.tap(button('偏移复原'));
    await tester.pump();
    expect(p.state.subtitleDelaySeconds, 0);

    await tester.tap(button('大小加'));
    await tester.pump();
    expect(p.state.subtitleScale, closeTo(1.05, 0.001));
    expect(p.state.kernel.properties['sub-scale'], '1.05');
    expect(find.text('105%'), findsOneWidget);
    await tester.tap(button('大小复原'));
    await tester.pump();
    expect(p.state.subtitleScale, 1);
  });

  testWidgets('no subtitle on: nothing to time', (tester) async {
    final kernel = ClassicKernel()..activeSubtitleTracks = [];
    await pumpClassicPlayer(tester, state: ClassicPlayerState(kernel));
    await tester.tap(button('字幕'));
    await tester.pumpAndSettle();
    expect(button('关闭'), findsOneWidget);
    expect(button('偏移加'), findsNothing);
    expect(button('大小加'), findsNothing);
  });

  testWidgets('a still: taken, a moment in the corner, a click opens it',
      (tester) async {
    final p = await pumpClassicPlayer(tester);
    await open(tester);
    await tester.tap(button('截图'));
    await tester.pump();
    expect(p.playback.screenshots, 1);
    expect(find.byType(MoreMenu), findsNothing, reason: 'the menu went first');
    await tester.pump(const Duration(milliseconds: 400));
    expect(button('打开截图').hitTestable(), findsOneWidget);
    await tester.tap(button('打开截图'));
    await tester.pumpAndSettle();
    expect(p.playback.opened, ['/tmp/nipa-next/player-more-still.png']);
    expect(button('打开截图').hitTestable(), findsNothing);

    // None could be taken: it says so, and goes.
    p.playback.still = null;
    await open(tester);
    await tester.tap(button('截图'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('截图失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('截图失败').hitTestable(), findsNothing);
  });

  testWidgets('picture in picture: Classic takes the video to its window',
      (tester) async {
    final p = await pumpClassicPlayer(tester);
    await open(tester);
    await tester.tap(button('画中画'));
    await tester.pumpAndSettle();
    expect(p.playback.pictureInPictures, 1);
    expect(find.byType(MoreMenu), findsNothing);
  });
}
