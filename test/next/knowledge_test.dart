import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/knowledge/service.dart';
import 'package:nipaplay/next/knowledge/capability.dart';
import 'package:nipaplay/next/mesh/runtime.dart';

const commit = '0123456789012345678901234567890123456789';
const build = <String, Object?>{
  'appVersion': '2.0',
  'sourceCommit': commit,
  'sourceDirty': false
};
Map<String, Object?> snapshot(
    {String content =
        '# Mesh\n\n## 目录\n设备在线不代表目录已刷新。\nplayback.kernel reads live facts.\n'}) {
  final data = <String, Object?>{
    'formatVersion': 1,
    'appVersion': '2.0',
    'sourceCommit': commit,
    'sourceDirty': false,
    'contentRevision': 'test',
    'documents': [
      {
        'id': 'docs/next/test.md',
        'title': 'Mesh',
        'kind': 'current',
        'sha256': sha256.convert(utf8.encode(content)).toString(),
        'content': content
      },
    ],
    'actions': {
      'playback.kernel': ['lib/next/capabilities/kernel_control.dart']
    },
  };
  data['contentRevision'] = knowledgeContentRevision(data);
  return data;
}

ProjectKnowledge service(Map<String, Object?> data,
        {Map<String, Object?> runtime = build}) =>
    ProjectKnowledge(() async => jsonEncode(data), runtimeBuild: runtime);
const live = ActionSpec(
    id: 'playback.kernel',
    title: 'Live kernel',
    description: 'actual host contract',
    effect: Effect.read,
    input: ObjectSchema({}),
    output: ObjectSchema({'ready': BooleanSchema()}));

void main() {
  test('search returns versioned Chinese excerpts and source line/section',
      () async {
    final found = await service(snapshot()).search('设备 目录');
    expect(found['matchCount'], 1);
    final item = (found['results'] as List).single as Map;
    expect(item['line'], 4);
    expect(item['section'], '目录');
    expect(item['excerpt'], contains('在线不代表'));
    expect((found['provenance'] as Map)['binding'], 'matched');
    expect(item['sourceUrl'], contains('/$commit/'));
  });

  test('read continuation preserves long lines and rejects arbitrary paths',
      () async {
    final content = '# Long\n${List.filled(33000, '字').join()}\nend';
    final docs = service(snapshot(content: content));
    var offset = 0;
    final output = StringBuffer();
    while (true) {
      final page =
          await docs.read('docs/next/test.md', offset: offset, length: 10000);
      output.write(page['content']);
      if (page['nextOffset'] == null) break;
      offset = page['nextOffset'] as int;
    }
    expect(output.toString(), content);
    await expectLater(docs.read('../../secret'), throwsA(isA<Failure>()));
    await expectLater(
        docs.read('docs/next/test.md', length: 25000), throwsA(isA<Failure>()));
    await expectLater(docs.search('  '), throwsA(isA<Failure>()));
    await expectLater(docs.search('Mesh', limit: 100), throwsA(isA<Failure>()));
  });

  test('version mismatch, unknown and modified build never claim matched',
      () async {
    for (final entry in [
      ({...build, 'sourceCommit': 'f' * 40}, 'mismatch'),
      ({...build, 'appVersion': '3.0'}, 'mismatch'),
      (<String, Object?>{}, 'unverified'),
      ({...build, 'sourceDirty': null}, 'unverified'),
      ({...build, 'sourceDirty': true}, 'modified'),
    ]) {
      final index = await service(snapshot(), runtime: entry.$1).index();
      expect((index['provenance'] as Map)['binding'], entry.$2);
    }
  });

  test('corrupt digest fails closed but locate still returns live schema',
      () async {
    final data = snapshot();
    ((data['documents'] as List).single as Map)['content'] = 'tampered';
    final docs = service(data);
    await expectLater(docs.index(), throwsA(isA<Failure>()));
    final result = await docs.locate('playback.kernel', [live]);
    expect(result['knowledgeStatus'], 'unavailable');
    expect((result['liveSpec'] as Map)['description'], 'actual host contract');
    expect(((result['liveSpec'] as Map)['output'] as Map)['properties'],
        contains('ready'));
  });

  test('damaged source mapping fails the manifest digest', () async {
    final data = snapshot();
    (data['actions'] as Map)['playback.kernel'] = ['lib/wrong.dart'];
    await expectLater(service(data).index(), throwsA(isA<Failure>()));
  });

  test('static source reference cannot imply host availability', () async {
    final result = await service(snapshot()).locate('playback.kernel', []);
    expect(result['registeredOnThisHost'], false);
    expect(result['liveSpec'], isNull);
    expect(result['sourceReferences'], hasLength(1));
  });

  test('knowledge is read-only and callable on the receiving Mesh host', () {
    final capability = KnowledgeCapability(service(snapshot()), () => [live]);
    expect(capability.actions, hasLength(4));
    for (final action in capability.actions) {
      expect(action.spec.effect, Effect.read);
      expect(meshActionAllowed(action.spec.id), true);
    }
  });

  test('registered actions enforce schemas and expose current contract',
      () async {
    late final Harness harness;
    harness = Harness(
        [KnowledgeCapability(service(snapshot()), () => harness.catalog)]);
    final ok = (await harness.invokeJson('knowledge.locate',
            {'action': 'knowledge.read'}, Invocation(origin: 'test')))
        .toEnvelope();
    expect(ok['status'], 'completed');
    final liveSpec = ((ok['result'] as Map)['liveSpec'] as Map);
    expect((liveSpec['input'] as Map)['required'], ['documentId']);
    final invalid = (await harness.invokeJson(
            'knowledge.read',
            {'documentId': 'docs/next/test.md', 'length': 24001},
            Invocation(origin: 'test')))
        .toEnvelope();
    expect(invalid['status'], 'failed');
    final index = (await harness.invokeJson(
            'knowledge.index', {}, Invocation(origin: 'test')))
        .toEnvelope();
    expect(index['status'], 'completed');
  });

  test('installed asset loads and excludes historical reports', () async {
    final docs = ProjectKnowledge(
        () => File('assets/next/knowledge/catalog.json').readAsString(),
        runtimeBuild: {});
    final index = await docs.index();
    expect(index['historyIncluded'], false);
    final entries = index['documents'] as List;
    expect(entries.length, greaterThan(10));
    expect(
        entries.any(
            (d) => (d as Map)['documentId'] == 'docs/next/ARCHITECTURE.md'),
        true);
    expect(
        entries.any(
            (d) => (d as Map)['documentId'].toString().contains('_REPORT')),
        false);
    expect(
        (await docs.search('playback.kernel'))['matchCount'], greaterThan(0));
  });
}
