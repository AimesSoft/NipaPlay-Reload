import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/next/capabilities/history_capability.dart';

import 'test_support.dart';

void main() {
  late List<WatchHistoryItem> rows;
  late Harness harness;
  late List<int> detailCalls;

  setUp(() {
    detailCalls = [];
    rows = [
      watchItem('/media/first.mkv', watchedAt: '2026-10-01T00:00:00Z'),
      watchItem('/media/original.mkv', animeId: 20),
      watchItem('/media/recorded.mkv', animeId: 30),
      watchItem('/media/no-cache.mkv', animeId: 40),
      watchItem('/media/named.mkv',
          animeId: null, episodeId: null, animeName: 'Unidentified series'),
      watchItem('/media/unnamed.mkv',
          animeId: null, episodeId: null, animeName: '', episodeTitle: null),
    ];
    final details = <int, BangumiAnime>{
      10: seriesDetail(),
      20: seriesDetail(id: 20, nameCn: ''),
      30: seriesDetail(id: 30, name: '', nameCn: '', imageUrl: ''),
    };
    harness = Harness([
      HistoryCapability(
        continueWatching: () => rows,
        seriesDetail: (id) {
          detailCalls.add(id);
          return details[id];
        },
      )
    ]);
  });

  test('preserves provider order and shares the library title rules', () async {
    final result =
        await invokeCompleted(harness, 'history.continue_watching', {});
    final items = result['items'] as List;
    expect(
        items.map((item) => item['path']), rows.map((item) => item.filePath));
    expect(items.map((item) => item['seriesTitle']), [
      'Localized title',
      'Original title',
      'Recorded title',
      'Recorded title',
      'Unidentified series',
      'unnamed.mkv',
    ]);
    expect(detailCalls, [10, 20, 30, 40]);
    expect(items.first, {
      'path': '/media/first.mkv',
      'animeId': 10,
      'seriesTitle': 'Localized title',
      'episodeId': 100,
      'episodeTitle': 'Episode one',
      'progress': 0.5,
      'positionMs': 500,
      'durationMs': 1000,
      'lastWatchedAt': '2026-10-01T00:00:00.000Z',
    });
    expect(items.last['animeId'], isNull);
    expect(items.last['episodeId'], isNull);
    expect(items.last['episodeTitle'], isNull);
    expect(items.last['lastWatchedAt'], '2026-10-10T04:00:00.000Z');
  });

  test('takes only the requested number without fetching truncated details',
      () async {
    final result = await invokeCompleted(
        harness, 'history.continue_watching', {'limit': 1.0});
    expect((result['items'] as List).single['path'], rows.first.filePath);
    expect(detailCalls, [10]);
  });

  test('defaults to 20 and permits the maximum limit of 100', () async {
    rows = [for (var i = 0; i < 101; i++) watchItem('/media/$i.mkv')];
    final defaultResult =
        await invokeCompleted(harness, 'history.continue_watching', {});
    expect((defaultResult['items'] as List).length, 20);
    final maxResult = await invokeCompleted(
        harness, 'history.continue_watching', {'limit': 100});
    expect((maxResult['items'] as List).length, 100);
  });

  test('returns an empty continue list', () async {
    rows.clear();
    expect(await invokeCompleted(harness, 'history.continue_watching', {}),
        {'items': []});
    expect(detailCalls, isEmpty);
  });

  for (final input in <JsonMap>[
    {'limit': 0},
    {'limit': 101},
    {'limit': 1.5},
    {'extra': true}
  ]) {
    test('rejects invalid continue input $input', () async {
      await invokeFailed(harness, 'history.continue_watching', input,
          FailureCode.invalidInput);
      expect(detailCalls, isEmpty);
    });
  }
}
