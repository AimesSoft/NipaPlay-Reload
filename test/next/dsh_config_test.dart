import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/dsh_config.dart';
import 'package:nipaplay/next/chat/dsh_runtime.dart';
import 'package:nipaplay/next/settings/dsh_config_store.dart';
import 'package:nipaplay/next/ui/settings/dsh_config_card.dart';
import 'package:nipaplay/next/ui/settings/controls.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';

void main() {
  DshConfig config(Map<String, Object?> values) =>
      DshConfig.parse(jsonEncode({'schema': 1, ...values}));

  test(
      'native options reach model, compaction, plugins and request without credentials',
      () {
    final c = config({
      'model': {
        'contextWindow': 131072,
        'maxTokens': 8192,
        'input': ['text'],
        'compat': {'supportsStore': false}
      },
      'provider': {
        'retryPolicy': {'maxRetries': 7},
        'timeoutMs': 45000
      },
      'request': {'maxTokens': 4096, 'reasoningEffort': 'low'},
      'compaction': {'headroomTokens': 16384, 'thresholdRatio': .7},
      'plugins': {
        'tool-web': {
          'config': {'fetch': false}
        }
      },
    });
    final rows = dshPatch(
        route: const DshRoute(
            baseUrl: 'https://example.invalid',
            model: 'm',
            key: 'secret',
            imageInput: true),
        config: c,
        plugins: Directory('/plugins'),
        personaPrefix: '',
        personaSuffix: '',
        harness: '/harness',
        version: 'test');
    final provider = (((rows.firstWhere((r) => r['id'] == 'llm-pi-ai')['config']
        as Map)['providers'] as Map)['nipaplay']) as Map;
    expect(provider['retryPolicy'], {'mode': 'normal', 'maxRetries': 7});
    expect(provider['timeoutMs'], 45000);
    expect(
        (provider['models'] as List).single, containsPair('input', ['text']));
    expect((provider['models'] as List).single,
        containsPair('contextWindow', 131072));
    expect(rows.where((r) => r['id'] == 'tool-web').last['config'],
        {'fetch': false});
    expect(rows.firstWhere((r) => r['id'] == 'compaction-basic')['config'],
        c.compaction);
    final bridge = (rows.last['insert'] as List).last['config'] as Map;
    expect(bridge['maxTokens'], 4096);
    expect(bridge['reasoningEffort'], 'low');
    expect(jsonEncode(rows), isNot(contains('secret')));
    expect(c.fingerprint,
        config(Map.fromEntries(c.json.entries.toList().reversed)).fingerprint);
  });

  test('invalid budgets, types and host wiring cannot silently fall back', () {
    for (final value in <Map<String, Object?>>[
      {
        'model': {'contextWindow': 8192}
      },
      {
        'model': {'input': 'image'}
      },
      {
        'provider': {'retryPolicy': 3}
      },
      {
        'provider': {'apiKeyEnv': 'OTHER_KEY'}
      },
      {
        'request': {'maxTokens': -1}
      },
      {
        'compaction': {'thresholdRatio': 1.1}
      },
      {
        'compaction': {'headroomTokens': 0}
      },
      {
        'compaction': {'retainTokens': 100, 'retainRatio': .2}
      },
      {
        'plugins': {
          'nipa-app-server': {'disabled': true}
        }
      },
    ]) {
      expect(() => config(value), throwsFormatException, reason: '$value');
    }
  });

  test(
      'per-model compaction inherits retention and summary limits and rejects duplicates',
      () {
    final c = config({
      'compaction': {
        'retainRatio': .1,
        'maxTokens': 1024,
        'modelPolicies': [
          {
            'provider': 'nipaplay',
            'model': 'm',
            'thresholdRatio': .15,
            'headroomTokens': 0
          }
        ],
      }
    });
    c.validateTarget('nipaplay', 'm');
    expect(
        () => config({
              'compaction': {'summarizationModel': 'm'}
            }),
        throwsFormatException);
    expect(
        () => config({
              'compaction': {
                'modelPolicies': [
                  {'provider': 'p', 'model': 'm'},
                  {'provider': 'p', 'model': 'm'},
                ]
              }
            }),
        throwsFormatException);
    expect(
        config({
          'compaction': {'thresholdRatio': 1}
        }).compaction['thresholdRatio'],
        1);
  });

  test(
      'external edits invalidate stale saves; invalid JSON stays visible and blocks launch',
      () async {
    final root = await Directory.systemTemp.createTemp('dsh-config-');
    addTearDown(() => root.delete(recursive: true));
    final store = DshConfigStore(root);
    final original = await store.read();
    expect(await store.file.exists(), false);
    final edited = jsonEncode({
      'schema': 1,
      'compaction': {'auto': false}
    });
    await store.save(edited, expectedRevision: original.revision);
    expect((await store.load()).compaction['auto'], false);
    await expectLater(
        store.save(original.text, expectedRevision: original.revision),
        throwsStateError);
    await store.file.writeAsString('{broken');
    expect((await store.read()).error, isNotNull);
    await expectLater(store.load(), throwsFormatException);
    final broken = await store.read();
    await store.save(original.text, expectedRevision: broken.revision);
    expect((await store.load()).fingerprint, original.fingerprint);
  });

  testWidgets(
      'common controls retain native JSON; drafts survive rebuild and can save or open',
      (tester) async {
    final host = _Settings();
    Widget app() => MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: DshConfigCard(host: host))));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final context = find.descendant(
        of: find.byKey(const ValueKey('model.contextWindow:1')),
        matching: find.byType(TextField));
    await tester.enterText(context, '524288');
    await tester.pumpWidget(app());
    await tester.pump();
    final save = find.widgetWithText(PillButton, '保存配置');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final document = jsonDecode(host.text) as Map;
    expect(document['model']['contextWindow'], 524288);
    expect(document['provider']['transport'], 'sse');
    expect(document['plugins']['tool-web']['config']['fetch'], false);
    final open = find.widgetWithText(PillButton, '打开配置文件');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(host.opened, true);
  });
}

class _Settings implements NextHostDshConfigSettings {
  String text =
      '{"schema":1,"provider":{"transport":"sse"},"plugins":{"tool-web":{"config":{"fetch":false}}}}';
  bool opened = false;
  @override
  Future<UiDshConfig> dshConfig() async =>
      UiDshConfig(path: '/fixture/dsh-config.json', text: text, revision: text);
  @override
  Future<void> saveDshConfig(String value,
      {required String expectedRevision}) async {
    expect(expectedRevision, text);
    DshConfig.parse(value);
    text = value;
  }

  @override
  Future<void> openDshConfig() async {
    opened = true;
  }
}
