import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/join_prompt.dart';
import 'package:nipaplay/next/ui/widgets/dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, List<bool?> answers,
      {bool next = true}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            const dialog = MeshJoinPromptDialog(name: 'iPad', platform: 'ios');
            answers.add(await Navigator.of(context).push<bool>(next
                ? NextDialogRoute<bool>(builder: (_) => dialog)
                : DialogRoute<bool>(context: context, builder: (_) => dialog)));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the person says it is theirs, or that it is not', (tester) async {
    final answers = <bool?>[];
    await open(tester, answers);
    expect(find.text('有新设备加入'), findsOneWidget);
    expect(find.text('“iPad”（iOS）刚刚加入。'), findsOneWidget);
    await tester.tap(find.text('是我'));
    await tester.pumpAndSettle();
    expect(answers, [false]);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不是我'));
    await tester.pumpAndSettle();
    expect(answers, [false, true]);
  });

  testWidgets('Esc leaves it unanswered; Classic gets its own dialog', (tester) async {
    final answers = <bool?>[];
    await open(tester, answers);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(answers, [null]);
    await open(tester, answers, next: false);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('不是我'));
    await tester.pumpAndSettle();
    expect(answers, [null, true]);
  });

  test('"not me" removes the device, "mine" is remembered, no answer decides nothing', () async {
    final removed = <String>[], acknowledged = <String>[];
    Future<void> run(List<bool?> answers) {
      final queue = [...answers];
      return answerJoin({'deviceId': 'd1'},
          prompt: (_) async => queue.isEmpty ? null : queue.removeAt(0),
          remove: (id) async => removed.add(id),
          acknowledge: (id) async => acknowledged.add(id),
          retryAfter: Duration.zero);
    }

    await run([true]);
    expect(removed, ['d1']);
    expect(acknowledged, isEmpty);
    await run([false]);
    expect(removed, ['d1']);
    expect(acknowledged, ['d1']);
    // The window could not be shown a few times, then it could.
    await run([null, null, true]);
    expect(removed, ['d1', 'd1']);
    // Never answered: nothing is removed or remembered.
    await run([null, null, null, null, true]);
    expect(removed, ['d1', 'd1']);
    expect(acknowledged, ['d1']);
  });
}
