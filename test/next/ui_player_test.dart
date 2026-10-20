import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/panel/chat_panel.dart';
import 'package:nipaplay/next/ui/player/player_layer.dart';
import 'package:nipaplay/next/ui/player/timeline.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/shell/top_bar.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';

import 'player_test_support.dart';

/// The player under Next: the shell draws its controls over Classic's
/// video, Classic draws its own everywhere else; back returns to the page
/// the video was opened from; Nipa is a click or ⌘K away; the controls go
/// when the pointer rests and stay while it is on them.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 78.0, 'fullScreen': false});
    NextShell.debugServices = (_) => playerTestServices();
  });
  tearDown(() => NextShell.debugServices = null);

  Finder button(String label) => find.byWidgetPredicate(
      (w) => w is Pressable && w.semanticLabel == label);

  Offstage classicHost(WidgetTester tester) => tester.widget<Offstage>(find
      .ancestor(
          of: find.text('classic', skipOffstage: false),
          matching: find.byType(Offstage, skipOffstage: false))
      .first);

  testWidgets('Next on: its controls lie over Classic\'s video',
      (tester) async {
    final p = await pumpPlayer(tester, status: PlayerStatus.playing);
    expect(globals.nextShellHostsPlayer, isTrue);
    expect(classicHost(tester).offstage, isFalse,
        reason: 'the video shows through');
    expect(find.byType(NextPlayerLayer), findsOneWidget);
    expect(find.byType(NextTopBar), findsNothing,
        reason: 'the pages are hidden under the video');

    expect(find.textContaining('葬送的芙莉莲', findRichText: true), findsOneWidget);
    expect(find.textContaining('第5话 死者的幻影', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('01:05', findRichText: true), findsOneWidget);
    expect(find.textContaining('24:00', findRichText: true), findsOneWidget);
    for (final label in [
      '返回',
      '暂停',
      '下一集',
      '静音',
      '关闭弹幕',
      '字幕',
      '剧集',
      '全屏',
      'Nipa'
    ]) {
      expect(button(label).hitTestable(), findsOneWidget, reason: label);
    }

    await tester.tap(button('暂停'));
    await tester.pump();
    expect(p.state.toggles, 1);
    expect(button('播放'), findsOneWidget);

    await tester.tap(button('关闭弹幕'));
    await tester.pump();
    expect(p.state.danmakuVisible, isFalse);
    expect(button('显示弹幕'), findsOneWidget);

    await tester.tap(button('静音'));
    await tester.pump();
    expect(p.state.currentSystemVolume, 0);
    await tester.tap(button('取消静音'));
    await tester.pump();
    expect(p.state.currentSystemVolume, closeTo(0.8, 0.001));

    await tester.tap(button('全屏'));
    await tester.pump();
    expect(p.state.fullscreenToggles, 1);
    expect(button('退出全屏'), findsOneWidget);

    await tester.tap(button('下一集'));
    expect(p.state.nextEpisodes, 1);

    // The heat comes from the danmaku Classic loaded.
    final heat = p.playback.heat();
    expect(heat, isNotNull);
    expect(heat!.reduce((a, b) => a > b ? a : b), 1);
    expect(
        tester.widget<PlayerTimeline>(find.byType(PlayerTimeline)).heat, heat);

    // A click on the timeline goes there.
    final line = tester.getRect(find.byType(PlayerTimeline));
    await tester.tapAt(Offset(line.left + line.width / 2, line.bottom - 10));
    await tester.pump();
    expect(p.state.seeks.single.inSeconds, closeTo(12 * 60, 2));
  });

  testWidgets('a file the library knows shows its work and episode',
      (tester) async {
    playerTestLibrary['/v/[Group] Show [01][1080p].mkv'] =
        (work: '躲在超市后门抽烟的两人', episode: '第 1 集 在超市后门吸烟的二人');
    addTearDown(playerTestLibrary.clear);
    final p = await pumpPlayer(tester, status: PlayerStatus.playing);
    p.state.currentVideoPath = '/v/[Group] Show [01][1080p].mkv';
    p.state.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('躲在超市后门抽烟的两人', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('第 1 集 在超市后门吸烟的二人', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('葬送的芙莉莲', findRichText: true), findsNothing,
        reason: "Classic's names give way to the library's");
  });

  testWidgets('the controls go when the pointer rests, stay while on them',
      (tester) async {
    final p = await pumpPlayer(tester, status: PlayerStatus.playing);
    double opacity() => tester
        .widget<AnimatedOpacity>(find
            .ancestor(of: button('字幕'), matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;
    expect(opacity(), 1);

    p.state.showControlsNow(false);
    await tester.pumpAndSettle();
    expect(opacity(), 0, reason: 'Classic hid them: the pointer rested');
    expect(button('字幕').hitTestable(), findsNothing);

    p.state.showControlsNow(true);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(720, 400));
    await mouse.moveTo(tester.getCenter(button('字幕')));
    await tester.pump();
    expect(p.state.hovered, isTrue);
    p.state.showControlsNow(false);
    await tester.pumpAndSettle();
    expect(opacity(), 1, reason: 'the pointer is on them');

    await mouse.moveTo(const Offset(720, 400));
    await tester.pumpAndSettle();
    expect(p.state.hovered, isFalse);
    expect(opacity(), 0);
  });

  testWidgets('back returns to the page the video was opened from',
      (tester) async {
    final p = await pumpPlayer(tester);
    expect(classicHost(tester).offstage, isTrue);
    final shell = NextShellScope.of(tester.element(find.byType(NextTopBar)));
    shell.go(NextSection.activity);
    unawaited(shell.navigatorKey.currentState!.push(PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const Center(child: Text('原来的页面')))));
    await tester.pumpAndSettle();
    expect(find.text('原来的页面'), findsOneWidget);

    p.state.play();
    await tester.pumpAndSettle();
    expect(find.text('原来的页面'), findsNothing);
    expect(find.byType(NextPlayerLayer), findsOneWidget);
    // Esc while watching leaves the pages as they are.
    expect(shell.escape(), isFalse);

    await tester.tap(button('返回'));
    await tester.pumpAndSettle();
    expect(p.playback.left, 1);
    expect(find.byType(NextPlayerLayer), findsNothing);
    expect(classicHost(tester).offstage, isTrue);
    expect(find.text('原来的页面'), findsOneWidget);
    expect(shell.section, NextSection.activity);
  });

  testWidgets('Nipa over the video: a click or ⌘K; Classic\'s hotkeys rest',
      (tester) async {
    final p = await pumpPlayer(tester, status: PlayerStatus.playing);
    final shell =
        NextShellScope.of(tester.element(find.byType(NextPlayerLayer)));
    await tester.tap(button('Nipa').hitTestable());
    await tester.pump(const Duration(milliseconds: 600));
    expect(shell.panelOpen.value, isTrue);
    expect(find.byType(ChatPanelLayer), findsOneWidget);
    expect(p.playback.holds, 1, reason: 'space is the input\'s now');

    shell.closePanel();
    await tester.pump(const Duration(milliseconds: 600));
    expect(p.playback.holds, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 600));
    expect(shell.panelOpen.value, isTrue);

    // Leaving the video with the conversation open, on the home: it is
    // the home's own again.
    p.state.status = PlayerStatus.idle;
    p.state.notify();
    await tester.pump(const Duration(milliseconds: 600));
    expect(shell.panelOpen.value, isFalse);
    expect(shell.homeChatOpen.value, isTrue);
    expect(p.playback.holds, 0);
  });

  testWidgets('subtitles and episodes: chosen in Next\'s menus',
      (tester) async {
    final p = await pumpPlayer(tester, status: PlayerStatus.playing);
    await tester.tap(button('字幕'));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('日语'), findsOneWidget);
    expect(p.playback.holds, 1);
    await tester.tap(find.text('日语'));
    await tester.pumpAndSettle();
    expect(p.playback.chosen.single.label, '日语');
    expect(find.text('简体中文'), findsNothing, reason: 'the menu closed');
    expect(p.playback.holds, 0);

    await tester.tap(button('剧集'));
    await tester.pumpAndSettle();
    expect(find.text('第4话 灵魂安眠之地'), findsOneWidget);
    await tester.tap(find.text('第6话 村子的英雄'));
    await tester.pumpAndSettle();
    expect(p.playback.played.single.title, '第6话 村子的英雄');

    // Esc closes a menu, and only the menu.
    await tester.tap(button('字幕'));
    await tester.pumpAndSettle();
    expect(find.text('简体中文'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('简体中文'), findsNothing);
    expect(find.byType(NextPlayerLayer), findsOneWidget);
  });

  testWidgets('clicks on the picture are still Classic\'s video\'s',
      (tester) async {
    var taps = 0;
    await pumpPlayer(tester,
        status: PlayerStatus.playing,
        classic: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox.expand(),
        ));
    await tester.tapAt(const Offset(720, 450));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1, reason: 'pause and full screen live there');
    await tester.tap(button('字幕'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1, reason: 'the controls take their own clicks');
  });

  testWidgets('in an opening: 跳过片头, even with the controls away',
      (tester) async {
    final p = await pumpPlayer(tester, status: PlayerStatus.playing);
    expect(button('跳过片头').hitTestable(), findsNothing);
    p.playback.segment = SkipSegmentKind.opening;
    p.state.showControlsNow(false);
    await tester.pumpAndSettle();
    await tester.tap(button('跳过片头'));
    expect(p.playback.skips, 1);
    p.playback.segment = SkipSegmentKind.ending;
    p.state.notify();
    await tester.pumpAndSettle();
    expect(button('跳过片尾').hitTestable(), findsOneWidget);
  });

  testWidgets('while it opens: the title and a pulse, no controls',
      (tester) async {
    await pumpPlayer(tester, status: PlayerStatus.loading);
    expect(find.text('葬送的芙莉莲'), findsOneWidget);
    expect(button('暂停'), findsNothing);
    expect(button('返回'), findsNothing);
  });

  testWidgets('Next off: Classic alone, and its own controls', (tester) async {
    await pumpPlayer(tester, next: false, status: PlayerStatus.playing);
    expect(globals.nextShellHostsPlayer, isFalse);
    expect(find.byType(NextShell), findsNothing);
    expect(find.byType(NextPlayerLayer), findsNothing);
    expect(classicHost(tester).offstage, isFalse);
    expect(
        shouldBuildClassicPlayerControls(
            nextHostsPlayer: globals.nextShellHostsPlayer,
            secondaryWindow: false),
        isTrue);
  });

  test('Classic\'s controls: everywhere but Next\'s main window', () {
    expect(
        shouldBuildClassicPlayerControls(
            nextHostsPlayer: false, secondaryWindow: false),
        isTrue);
    expect(
        shouldBuildClassicPlayerControls(
            nextHostsPlayer: false, secondaryWindow: true),
        isTrue);
    expect(
        shouldBuildClassicPlayerControls(
            nextHostsPlayer: true, secondaryWindow: true),
        isTrue,
        reason: 'a detached or picture-in-picture window keeps them');
    expect(
        shouldBuildClassicPlayerControls(
            nextHostsPlayer: true, secondaryWindow: false),
        isFalse);
  });
}
