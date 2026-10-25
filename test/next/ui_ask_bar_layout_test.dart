import 'package:flutter/material.dart' show Material, MaterialApp, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/home/ask_bar.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/widgets/nipa_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final shells = <NextShellController>[];

  // The shell's own timers end with it, before the test does.
  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final shell in shells) {
      shell.dispose();
    }
    shells.clear();
  }

  Future<void> pump(WidgetTester tester, double width,
      {Widget? aside,
      bool expand = false,
      List<String> chips = const []}) async {
    final shell = NextShellController(playerTestServices(), onLeave: () {});
    shells.add(shell);
    await tester.binding.setSurfaceSize(Size(width + 40, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        child: NextShellScope(
          controller: shell,
          child: Center(
            child: AskBar(
              focusNode: FocusNode(),
              controller: TextEditingController(),
              onSay: (_) {},
              mood: NipaMood.idle,
              suggestions: chips,
              maxWidth: width,
              aside: aside,
              onExpand: expand ? () {} : null,
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('the input and what sits beside it fit a narrow page',
      (tester) async {
    // An iPad held upright leaves the home less than the field's 640.
    await pump(tester, 560,
        aside: const SizedBox(width: 160, height: 32), expand: true);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AskBar)).width, lessThanOrEqualTo(560));
    // The field never grows past what it is given.
    final field = tester.getRect(find.byType(TextField, skipOffstage: false));
    expect(field.right, lessThanOrEqualTo(560 + 20));
    await done(tester);
  });

  testWidgets('beside the field when there is room, under it when there is not',
      (tester) async {
    const aside = SizedBox(key: Key('aside'), width: 160, height: 32);
    await pump(tester, 900, aside: aside);
    expect(tester.takeException(), isNull);
    final wide = tester.getTopLeft(find.byKey(const Key('aside')));
    await pump(tester, 700, aside: aside);
    expect(tester.takeException(), isNull);
    final narrow = tester.getTopLeft(find.byKey(const Key('aside')));
    expect(narrow.dy, greaterThan(wide.dy));
    await done(tester);
  });

  testWidgets('suggestions share the line with the field and never overflow',
      (tester) async {
    await pump(tester, 560, chips: ['看看今天的更新', '继续上次的'], expand: true);
    expect(tester.takeException(), isNull);
    await done(tester);
  });
}
