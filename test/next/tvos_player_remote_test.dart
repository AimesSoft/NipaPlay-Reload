import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/television_focus.dart';
import 'package:nipaplay/utils/video_player_state.dart' show PlayerStatus;

import 'player_test_support.dart';

/// Next on a television: the remote watches with the picture focused (left
/// and right seek, select plays or pauses), steps down into the controls,
/// and Menu steps back out of them before it leaves the video. Only the
/// focused button is paper.
void main() {
  final original = TelevisionFocusable.isTelevision;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 0.0, 'fullScreen': false});
    NextShell.debugServices = (_) => playerTestServices();
    TelevisionFocusable.isTelevision = () => true;
  });
  tearDown(() {
    NextShell.debugServices = null;
    TelevisionFocusable.isTelevision = original;
  });

  Finder button(String label) => find.byWidgetPredicate(
      (w) => w is Pressable && w.semanticLabel == label);

  bool focusedIn(Finder finder) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    final element = finder.evaluate().single;
    var found = false;
    focused.visitAncestorElements((e) {
      if (identical(e, element)) found = true;
      return !found;
    });
    return found || identical(focused, element);
  }

  testWidgets(
      'watching, the arrows seek and select plays; down goes into the '
      'controls; Menu comes back out before it leaves', (tester) async {
    final rig = await pumpPlayer(tester,
        status: PlayerStatus.playing, size: const Size(1920, 1080));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(rig.state.seeks, [const Duration(minutes: 1, seconds: 15)]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(rig.state.seeks.last, const Duration(seconds: 55));
    expect(rig.state.seeks, hasLength(2), reason: 'one step a press');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(rig.state.toggles, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(focusedIn(button('播放')), isTrue, reason: 'the first control');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(rig.state.seeks, hasLength(2),
        reason: 'on the controls the arrows move the focus');

    final controller = NextShellScope.of(tester.element(button('播放')));
    expect(controller.escape(), isTrue, reason: 'out of the controls');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(rig.state.seeks, hasLength(3), reason: 'watching again');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('only the focused button is paper', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
      PlayButton(label: '播放', onTap: () {}, autofocus: true),
      NextButton.ghost(label: '详情', onTap: () {}),
    ]))));
    await tester.pump(const Duration(milliseconds: 400));
    Color fill(String label) {
      final box = tester.widget<AnimatedContainer>(find
          .descendant(
              of: button(label), matching: find.byType(AnimatedContainer))
          .first);
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(fill('播放'), const Color(0xFFF5F1EA), reason: 'autofocused');
    expect(fill('详情').a, lessThan(0.5), reason: 'glass');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fill('详情'), const Color(0xFFF5F1EA));
    expect(fill('播放').a, lessThan(0.5));
  });
}
