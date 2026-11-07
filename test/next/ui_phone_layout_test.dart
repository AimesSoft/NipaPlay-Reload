import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/player/menu_controls.dart';
import 'package:nipaplay/next/ui/player/player_layer.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/shell/phone_dock.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/utils/video_player_state.dart' show PlayerStatus;

import 'player_test_support.dart';

/// Next on a phone: the same pages and data, laid out for its narrow room.
/// The sections sit at its foot; under a finger the picture takes taps,
/// double taps and drags, and the player's menus rise as sheets.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 0.0, 'fullScreen': false});
    NextShell.debugServices = (_) => playerTestServices();
  });
  tearDown(() {
    NextShell.debugServices = null;
    NextPlayerLayer.debugTouch = null;
    NextPlayerLayer.debugPhone = null;
  });

  Finder button(String label) => find.byWidgetPredicate(
      (w) => w is Pressable && w.semanticLabel == label);

  testWidgets('a phone has its sections at its foot; a window on its bar',
      (tester) async {
    await pumpPlayer(tester, size: const Size(430, 932));
    await tester.pump(const Duration(milliseconds: 400));
    final dock = find.byType(PhoneDock);
    expect(dock, findsOneWidget);
    for (final label in ['首页', '发现', '媒体库', '动态']) {
      // The bar draws the selected one twice (its glass lens over it).
      expect(find.descendant(of: dock, matching: find.text(label)),
          findsWidgets,
          reason: label);
    }
    // Nipa and the microphone on the dock's line; the menu at the top.
    for (final label in ['和梨花说话', '说话', '菜单']) {
      expect(button(label).hitTestable(), findsOneWidget, reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());

    await pumpPlayer(tester, size: const Size(1440, 900));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhoneDock), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a phone held upright: the menus on glass over the capsule, which '
      'turns the phone sideways', (tester) async {
    NextPlayerLayer.debugTouch = true;
    NextPlayerLayer.debugPhone = true;
    await pumpPlayer(tester,
        status: PlayerStatus.playing, size: const Size(430, 932));
    await tester.pump(const Duration(milliseconds: 400));
    final play = tester.getRect(button('暂停'));
    final full = tester.getRect(button('全屏'));
    expect(full.center.dy, closeTo(play.center.dy, 1), reason: 'one capsule');
    for (final label in ['字幕', '剧集', '更多']) {
      final rect = tester.getRect(button(label));
      expect(rect.bottom, lessThan(play.top), reason: '$label over it');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a phone held sideways: its controls on one capsule, its menus a '
      'sheet at the right above it', (tester) async {
    NextPlayerLayer.debugTouch = true;
    NextPlayerLayer.debugPhone = true;
    await pumpPlayer(tester,
        status: PlayerStatus.playing, size: const Size(932, 430));
    await tester.pump(const Duration(milliseconds: 400));
    expect(button('暂停').hitTestable(), findsOneWidget);
    expect(button('返回').hitTestable(), findsOneWidget);
    expect(button('退出全屏').hitTestable(), findsOneWidget,
        reason: 'stands the phone up again');
    await tester.tap(button('字幕'));
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = find.byType(PlayerMenuSheet);
    expect(sheet, findsOneWidget);
    final box = tester.getRect(find
        .descendant(of: sheet, matching: find.byType(PlayerMenuSurface))
        .first);
    final more = tester.getRect(button('字幕'));
    expect(box.right, closeTo(932 - 28, 1), reason: 'at the right');
    expect(box.bottom, lessThan(more.top), reason: 'above the capsule');
    expect(box.width, closeTo(340 + 20, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'under a finger: a tap hides the controls, a double tap on the right '
      'goes on ten seconds, a sideways drag moves through the video',
      (tester) async {
    NextPlayerLayer.debugTouch = true;
    NextPlayerLayer.debugPhone = false;
    final rig = await pumpPlayer(tester,
        status: PlayerStatus.playing, size: const Size(932, 430));
    await tester.pump(const Duration(milliseconds: 400));
    expect(button('暂停').hitTestable(), findsOneWidget);
    // No volume slider under a finger: the right half's drag is the volume.
    expect(button('静音'), findsNothing);

    const middle = Offset(466, 215);
    await tester.tapAt(middle);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(button('暂停').hitTestable(), findsNothing,
        reason: 'the tap put the controls away');

    const right = Offset(820, 215);
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.state.seeks, [const Duration(minutes: 1, seconds: 15)]);

    await tester.dragFrom(const Offset(300, 215), const Offset(233, 0));
    await tester.pump(const Duration(milliseconds: 800));
    // A quarter of the width is a quarter of the sweep.
    expect(rig.state.seeks.last, const Duration(minutes: 1, seconds: 35));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('under a finger the subtitles menu rises as a sheet',
      (tester) async {
    NextPlayerLayer.debugTouch = true;
    NextPlayerLayer.debugPhone = false;
    await pumpPlayer(tester,
        status: PlayerStatus.playing, size: const Size(932, 430));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(button('字幕'));
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = find.byType(PlayerMenuSheet);
    expect(sheet, findsOneWidget);
    final box = tester.getRect(find
        .descendant(of: sheet, matching: find.byType(PlayerMenuSurface))
        .first);
    expect(box.bottom, greaterThan(430 - 40), reason: 'at the foot');
    expect((box.center.dx - 466).abs(), lessThan(1), reason: 'centred');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
