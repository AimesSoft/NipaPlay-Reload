import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Action;
import 'package:nipaplay/next/capabilities/classic_action.dart';
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/shell/agent_inbox.dart';

void main() {
  testWidgets(
      'question appears without waiting for turn end; close is not an answer',
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget());
    await tester.pump();
    expect(find.text('问题标题'), findsOneWidget);
    expect(world.answers, isEmpty);
    await tester.tap(find.byTooltip('收起；问题仍待回答'));
    await tester.pump();
    expect(world.rows.single['state'], 'pending');
    expect(world.answers, isEmpty);
    await tester.tap(find.text('梨花提醒 · 1'));
    await tester.pump();
    await tester.tap(find.text('仅这次'));
    await tester.pump();
    expect(world.answers.single, {'id': 'q1', 'answer': '仅这次'});
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets(
      'new notifications do not steal focus or erase an unfinished answer',
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget());
    await tester.pump();
    await tester.enterText(find.byType(TextField), '按我自己的规则');
    world.rows.insert(0, {
      'id': 'n2',
      'kind': 'notice',
      'state': 'unread',
      'hidden': false,
      'title': '新提醒',
      'body': '还有独立任务',
      'severity': 'info'
    });
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('按我自己的规则'), findsOneWidget);
    expect(find.text('问题标题'), findsOneWidget);
    await tester.tap(find.text('回复'));
    await tester.pump();
    expect(world.answers.single['id'], 'q1');
    expect(world.answers.single['answer'], '按我自己的规则');
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets(
      'remote outage retains local questions without publishing polling errors',
      (tester) async {
    final world = _Inbox();
    await tester.pumpWidget(world.widget(peer: 'offline-peer'));
    await tester.pump();
    expect(find.text('问题标题'), findsOneWidget);
    expect(find.textContaining('original remote failure'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '保留回复');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('保留回复'), findsOneWidget);
    expect(world.notices, 0);
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });

  testWidgets(
      'small viewport contains long errors and options; full error can be copied',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final world = _Inbox();
    final error =
        'HTTP 500\n${List.filled(100, 'original error line').join('\n')}';
    world.rows[0].addAll({
      'severity': 'error',
      'body': error,
      'options': List.generate(6, (i) => '选项 $i：这是一个较长的说明')
    });
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(world.widget());
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('复制完整错误'));
    await tester.tap(find.text('复制完整错误'));
    await tester.pump();
    expect(copied, error);
    await tester.pumpWidget(const SizedBox());
    await world.events.close();
  });
}

class _Inbox {
  final events = StreamController<Map>.broadcast();
  final rows = <JsonMap>[
    {
      'id': 'q1',
      'kind': 'question',
      'state': 'pending',
      'hidden': false,
      'title': '问题标题',
      'body': '要不要整理目录和文件名？',
      'severity': 'info',
      'options': ['仅这次', '保持原样']
    }
  ];
  final answers = <JsonMap>[];
  int notices = 0;
  late final calls = GuiCalls(() async => Harness([_Capability(this)]));
  Widget widget({String? peer}) => MaterialApp(
      home: Scaffold(
          body: AgentInboxOverlay(
              calls: calls, events: events.stream, peer: () => peer)));
}

class _Capability implements Capability {
  _Capability(_Inbox world)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'mesh.invoke',
                  title: 'remote',
                  description: 'remote',
                  effect: Effect.read,
                  input: ObjectSchema({}, additionalProperties: true),
                  output: ObjectSchema({}, additionalProperties: true)),
              (_, invocation) async => throw const Failure(
                  FailureCode.unavailable, 'original remote failure')),
          ClassicAction(
              const ActionSpec(
                  id: 'ui.notify',
                  title: 'notice',
                  description: 'notice',
                  effect: Effect.write,
                  input: ObjectSchema({}, additionalProperties: true),
                  output: ObjectSchema({}, additionalProperties: true)),
              (_, invocation) async {
            world.notices++;
            return {};
          }),
          for (final op in ['list', 'respond', 'dismiss'])
            ClassicAction(
                ActionSpec(
                    id: 'ui.inbox.$op',
                    title: op,
                    description: op,
                    effect: op == 'list' ? Effect.read : Effect.write,
                    input: const ObjectSchema({}, additionalProperties: true),
                    output: const ObjectSchema({}, additionalProperties: true)),
                (input, _) async {
              if (op == 'list')
                return {
                  'items': world.rows
                      .where((r) =>
                          r['state'] == 'pending' || r['state'] == 'unread')
                      .toList(),
                  'nextOffset': null,
                  'popupsEnabled': true
                };
              final row = world.rows.firstWhere((r) => r['id'] == input['id']);
              if (op == 'respond') {
                world.answers.add(Map.of(input));
                row['state'] = 'answered';
              }
              if (op == 'dismiss') row['hidden'] = true;
              return row;
            }),
        ];
  @override
  final List<ClassicAction> actions;
}
