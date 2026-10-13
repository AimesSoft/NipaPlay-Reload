// Explicit experiment; not included in the regular constraint suite.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/mesh/library_codec.dart';
import 'package:nipaplay/next/mesh/library.dart';
import 'package:nipaplay/next/mesh/library_capability.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/library_index.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'media_test_support.dart';
import '../security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('X56 5000 works / 60000 episodes indexed queries', () async {
    final fixture = MediaFixture();
    await fixture.open(sources: []);
    addTearDown(fixture.close);
    final rows = [
      for (var i = 0; i < 5000; i++)
        {
          'id': 'mesh-work:$i',
          'added': i,
          'payload': workJson(UiWork(
              workId: 'mesh-work:$i',
              title: '奇幻作品 $i',
              originalTitle: 'Original Adventure $i',
              year: 2000 + i % 27,
              devices: i.isEven
                  ? const []
                  : [UiDevice(name: '测试设备', online: i % 5 != 0)])),
          'facts': {
            'searchTitles': ['别名 $i', '異世界物語 $i'],
            'identityKeys': [
              jsonEncode(['dandanplay', 'work', '', '$i'])
            ],
            'searchEpisodes': [
              for (var n = 1; n <= 12; n++)
                {
                  'episode': episodeJson(UiEpisode(
                      episodeId: 'mesh-episode:$i:$n',
                      workId: 'mesh-work:$i',
                      number: n,
                      title: '旅行章节 $n · $i',
                      playable: i % 5 != 0,
                      device: i.isEven
                          ? null
                          : UiDevice(name: '测试设备', online: i % 5 != 0))),
                  'titles': ['Chapter $n Adventure $i'],
                }
            ],
          },
        }
    ];
    final clock = Stopwatch()..start();
    await replaceLibraryIndex(fixture.jobs.database, rows);
    final projectionMs = clock.elapsedMicroseconds / 1000;
    final vault = MemoryVault();
    final ui = UiDataService(fixture.service, fixture.engine,
        StateCapability([]), StateSources(), fixture.root, vault);
    final mesh =
        MeshRuntime(root: fixture.root, vault: vault, token: () async => null);
    final library = MeshLibrary(ui, mesh);
    ui.meshLibrary = library;
    addTearDown(() async {
      await ui.close();
      await mesh.close();
    });
    final index = library.searchIndex;
    final harness = Harness([MeshLibraryCapability(library)]);
    final rssBefore = ProcessInfo.currentRss;
    clock.reset();
    final cached = [
      for (final r in await fixture.jobs.database.query('next_library_index'))
        {
          ...r,
          'payload': jsonDecode(r['payload'] as String),
          'facts': jsonDecode(r['facts'] as String),
        }
    ];
    index.replace(cached);
    print(jsonEncode({
      'observation': 'index preparation',
      'works': 5000,
      'episodes': 60000,
      'projectionWriteMs': projectionMs,
      'sqliteReadAndPostingBuildMs': clock.elapsedMicroseconds / 1000,
      'processRssMiB': ProcessInfo.currentRss / 1048576,
      'rssBeforeCachedReadMiB': rssBefore / 1048576
    }));
    for (final query in [
      '奇',
      '奇幻',
      '奇幻作品 4999',
      'original ADVENTURE 4999',
      '别名 4999',
      '異世界物語 4999',
      '2026',
      '旅行章节 12 · 4999',
      'Chapter 12 Adventure 4999',
      '作品 2026',
      '不存在',
      '%_'
    ]) {
      for (var warm = 0; warm < 10; warm++) index.search(query);
      final samples = <double>[];
      for (var i = 0; i < 100; i++) {
        clock.reset();
        index.search(query);
        samples.add(clock.elapsedMicroseconds / 1000);
      }
      samples.sort();
      final result = index.search(query);
      final actionSamples = <double>[];
      for (var i = 0; i < 100; i++) {
        clock.reset();
        final outcome = await harness.invokeJson('media.library.search_merged',
            {'query': query, 'limit': 12}, Invocation(origin: 'gui'));
        expect(outcome, isA<Completed>());
        jsonEncode(outcome.toEnvelope());
        actionSamples.add(clock.elapsedMicroseconds / 1000);
      }
      actionSamples.sort();
      print(jsonEncode({
        'query': query,
        'runs': 100,
        'medianMs': samples[50],
        'p95Ms': samples[94],
        'maxMs': samples.last,
        'workTotal': result['workTotal'],
        'episodeTotal': result['episodeTotal'],
        'harnessAndJsonMedianMs': actionSamples[50],
        'harnessAndJsonP95Ms': actionSamples[94],
        'harnessAndJsonMaxMs': actionSamples.last
      }));
    }
    expect(index.workId(const ExternalRef('dandanplay', 'anime', '4999')),
        'mesh-work:4999');
    expect(((index.search('别名 4999')['works'] as List).single as Map)['workId'],
        'mesh-work:4999');
    expect((index.search('旅行章节 12 · 4999')['episodes'] as List).length, 1);
    clock.reset();
    index.replace(cached);
    print(jsonEncode({
      'observation': 'unchanged text projection replacement',
      'milliseconds': clock.elapsedMicroseconds / 1000
    }));
  });
}
