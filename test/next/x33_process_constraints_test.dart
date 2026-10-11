import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/chat/turn_process_store.dart';
import 'package:nipaplay/next/capabilities/ui_capability.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'execution facts survive restart, isolate threads and redact before disk',
      () async {
    final root = await Directory.systemTemp.createTemp('x33-');
    try {
      final file = File('${root.path}/facts.json');
      final store = TurnProcessStore(file, maxTurns: 2);
      final now = DateTime.utc(2026);
      void event(String method, Map params) => store.observe({
            'method': method,
            'params': {'threadId': 'one', ...params}
          }, 'origin', now);
      event('turn/started', {
        'turn': {'id': 'a'}
      });
      event('item/started', {
        'turnId': 'a',
        'item': {
          'id': 'cmd',
          'type': 'commandExecution',
          'command': 'echo cookie=private'
        }
      });
      event('item/completed', {
        'turnId': 'a',
        'item': {
          'id': 'cmd',
          'type': 'commandExecution',
          'command': 'echo cookie=private',
          'exitCode': 7,
          'durationMs': 35,
          'aggregatedOutput': 'Bearer private\ncookie=private'
        }
      });
      event('turn/completed', {
        'turn': {'id': 'a', 'status': 'completed'}
      });
      final restored = TurnProcessStore(file);
      expect(restored.read('two', 'a'), isNull);
      final item = (restored.read('one', 'a')!['items'] as List).single;
      expect(item['exitCode'], 7);
      expect(item['durationMs'], 35);
      final history = {
        'id': 'a',
        'items': <Map>[
          {'id': 'user', 'type': 'userMessage', 'text': '你的话'},
          {'id': 'folded-thought', 'type': 'reasoning', 'summary': []},
          {'id': 'assistant', 'type': 'agentMessage', 'text': '回复'},
        ]
      };
      restored.restore('one', history);
      restored.restore('one', history);
      expect((history['items'] as List).map((v) => v['id']),
          ['user', 'assistant', 'cmd']);
      expect(file.readAsStringSync(), isNot(contains('private')));
      for (final id in ['b', 'c']) {
        event('turn/started', {
          'turn': {'id': id}
        });
      }
      expect(TurnProcessStore(file).read('one', 'a'), isNull);
      expect(jsonDecode(file.readAsStringSync()), hasLength(2));
      final small = TurnProcessStore(file, maxBytes: 400);
      small.observe({
        'method': 'turn/started',
        'params': {
          'threadId': 'one',
          'turn': {'id': 'd'}
        }
      }, 'origin', now);
      expect(file.lengthSync(), lessThanOrEqualTo(400));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('invisible Next preserves Classic work routing and direct anime targets',
      () async {
    final f = MediaFixture();
    await f.open();
    try {
      await f.identities.importLegacy([
        {
          'filePath': '${f.media.path}/one.mkv',
          'animeName': '作品',
          'animeId': 7001,
          'episodeId': 7101,
          'episodeTitle': '第 1 集'
        }
      ]);
      final work =
          (await f.jobs.database.query('media_entities', where: "kind='work'"))
              .single['id'] as String;
      var nextVisible = false, classicOpens = 0;
      final api = Harness([
        UiCapability(
            media: () => f.service,
            openWork: (_) async => nextVisible ? true : null,
            openDetail: (_) async {
              classicOpens++;
              return true;
            })
      ]);
      Future<Map> open(Map<String, Object?> target) async =>
          (await api.invokeJson('ui.open', target, Invocation(origin: 'test'))
                  as Completed)
              .value
              .toJson();
      expect((await open({'entityId': work}))['interface'], 'classic');
      nextVisible = true;
      expect((await open({'workId': work}))['interface'], 'next');
      expect((await open({'animeId': 7001}))['interface'], 'classic');
      expect(classicOpens, 2);
    } finally {
      await f.close();
    }
  });
}
