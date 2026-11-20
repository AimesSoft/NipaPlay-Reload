import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/classic_action.dart';
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/rika_store.dart';
import 'package:nipaplay/next/ui/settings/section_store.dart';
import 'package:nipaplay/next/ui/widgets/sheet.dart';

/// The store's actions as the card calls them, with what was asked.
final class _FakeStore implements Capability {
  final calls = <String>[];
  var installed = false;
  var notRun = false;

  JsonMap get _item => {
        'id': 'dmhy',
        'kind': 'skill',
        'name': '动漫花园',
        'version': '1.0.0',
        'description': '在动漫花园搜索资源。',
        'category': 'bt',
        'reviewed': true,
        'notices': ['只读取公开的发布信息。'],
        'installedVersion': installed ? '1.0.0' : null,
        'enabled': installed ? true : null,
      };

  ClassicAction _action(String id, Future<JsonMap> Function(JsonMap) run) =>
      ClassicAction(
          ActionSpec(
              id: id,
              title: id,
              description: id,
              effect: Effect.write,
              input: const ObjectSchema({}, additionalProperties: true),
              output: const ObjectSchema({}, additionalProperties: true)),
          (input, _) {
        calls.add('$id ${input.isEmpty ? '' : input}'.trim());
        return run(input);
      });

  @override
  late final List<Action> actions = [
    _action(
        'store.list',
        (_) async => {
              'official': [_item],
              'installed': [if (installed) _item],
            }),
    _action('store.install', (input) async {
      installed = true;
      return {'installed': _item};
    }),
    _action(
        'store.resolve_npm',
        (_) async => {
              'npm': 'dsh-example',
              'requested': 'latest',
              'version': '1.0.0',
              'hasSkill': true,
              'declaresDshPlugin': true,
              'notices': ['没有经过审核'],
              'kinds': {
                'skill': {'installable': true},
                'plugin': {'installable': true}
              },
            }),
    _action(
        'store.readme', (_) async => {'version': '2.0.0', 'readme': '另一版说明'}),
    _action(
        'store.apply',
        (_) async => notRun
            ? {'status': 'notRun', 'restarted': false, 'reason': '未运行'}
            : {'restarted': true}),
  ];
}

void main() {
  late _FakeStore fake;

  Future<void> pumpCard(WidgetTester tester) async {
    fake = _FakeStore();
    final store = NextRikaStore(GuiCalls(() async => Harness([fake])));
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Stack(children: [
          Positioned.fill(
              child: SingleChildScrollView(child: RikaStoreCard(store: store))),
          const Positioned.fill(child: NextSheetLayer()),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('an item is installed only after its notices are read',
      (tester) async {
    await pumpCard(tester);
    expect(find.text('动漫花园'), findsOneWidget);
    expect(find.text('BT 来源'), findsOneWidget);
    expect(find.text('重启梨花'), findsNothing);
    await tester.tap(find.text('动漫花园'));
    await tester.pumpAndSettle();
    expect(find.textContaining('说明对应版本 2.0.0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('store.details.close')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('安装').first);
    await tester.pumpAndSettle();
    expect(find.text('只读取公开的发布信息。'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(fake.calls.where((c) => c.startsWith('store.install')), isEmpty);

    await tester.tap(find.text('安装').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('store.notice.accept')));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('store.install {id: dmhy, version: 1.0.0}'));
    expect(find.text('卸载'), findsOneWidget);

    fake.notRun = true;
    await tester.tap(find.text('重启梨花'));
    await tester.pumpAndSettle();
    expect(find.text('重启梨花'), findsOneWidget);
    expect(find.textContaining('未重启'), findsOneWidget);
    fake.notRun = false;
    await tester.tap(find.text('重启梨花'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('store.apply'));
    expect(find.text('重启梨花'), findsNothing);
  });

  testWidgets('an npm package is installed only after the warning',
      (tester) async {
    await pumpCard(tester);
    await tester.enterText(find.byType(EditableText), 'dsh-example');
    await tester.pumpAndSettle();
    await tester.tap(find.text('安装').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('没有经过审核'), findsWidgets);
    expect(find.textContaining('请求：latest · 解析版本：1.0.0'), findsOneWidget);
    expect(find.text('安装为DSH 插件'), findsOneWidget);
    await tester.tap(find.text('安装为技能'));
    await tester.pumpAndSettle();
    expect(
        fake.calls,
        contains(
            'store.install {version: 1.0.0, npm: dsh-example, kind: skill}'));
  });
}
