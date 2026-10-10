import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/next/capabilities/library_capability.dart';

import 'test_support.dart';

void main() {
  late List<WatchHistoryItem> rows;
  late Harness harness;

  setUp(() {
    rows = [
      watchItem('/media/older.mkv',
          animeName: 'Legacy Alias',
          watchedAt: '2026-10-08T12:00:00+08:00',
          episodeTitle: 'Old title'),
      watchItem('webdav://dav/episode.mkv', episodeTitle: 'Latest title'),
      watchItem('smb://server/second.mkv',
          episodeId: 200,
          episodeTitle: '',
          watchedAt: '2026-10-09T12:00:00+08:00'),
      watchItem('/media/z.mkv', episodeId: null, episodeTitle: null),
      watchItem('/media/a.mkv', episodeId: null, episodeTitle: ''),
      watchItem('/media/other.mkv',
          animeId: 20,
          animeName: 'Other series',
          watchedAt: '2026-10-11T12:00:00+08:00'),
    ];
    harness = Harness([
      LibraryCapability(
        history: () => rows,
        seriesDetail: (id) => id == 10 ? seriesDetail() : null,
      )
    ]);
  });

  group('media.library.search', () {
    test('groups sources, counts episodes and files, and sorts by recency',
        () async {
      final result = await invokeCompleted(harness, 'media.library.search', {});
      expect(result['total'], 2);
      final series = result['series'] as List;
      expect(series.map((item) => item['animeId']), [20, 10]);
      expect(series[1], {
        'animeId': 10,
        'title': 'Localized title',
        'originalTitle': 'Original title',
        'imageUrl': 'https://example.test/cover.jpg',
        'episodeCount': 4,
        'fileCount': 5,
        'lastWatchedAt': '2026-10-10T04:00:00.000Z',
      });
      expect(rows.first.filePath, '/media/older.mkv');
    });

    test('uses exactly the existing media library inclusion rules', () async {
      rows.addAll([
        watchItem('/media/unidentified.mkv', animeId: null),
        watchItem('/media/cleared.mkv', animeName: ''),
        watchItem('jellyfin://123'),
        watchItem('emby://123'),
        watchItem('dandanplay://123'),
        watchItem('https://remote.test/api/v1/stream/123'),
        watchItem('https://remote.test/api/media/local/share/123'),
      ]);
      final result = await invokeCompleted(harness, 'media.library.search', {});
      expect(result['total'], 2);
      expect((result['series'] as List)[1]['fileCount'], 5);
    });

    for (final query in ['LOCALIZED', 'ORIGINAL', 'legacy alias']) {
      test('matches $query without regard to case', () async {
        final result = await invokeCompleted(
            harness, 'media.library.search', {'query': query});
        expect(result['total'], 1);
        expect((result['series'] as List).single['animeId'], 10);
      });
    }

    test('reports total before limiting, including integral JSON doubles',
        () async {
      final result = await invokeCompleted(
          harness, 'media.library.search', {'limit': 1.0});
      expect(result['total'], 2);
      expect((result['series'] as List).single['animeId'], 20);
    });

    test('defaults to 50 and permits the maximum limit of 200', () async {
      rows = [
        for (var i = 0; i < 201; i++) watchItem('/media/$i.mkv', animeId: i)
      ];
      final defaultResult =
          await invokeCompleted(harness, 'media.library.search', {});
      expect((defaultResult['series'] as List).length, 50);
      expect(defaultResult['total'], 201);
      final maxResult = await invokeCompleted(
          harness, 'media.library.search', {'limit': 200});
      expect((maxResult['series'] as List).length, 200);
    });

    test('returns an empty result for no query matches or an empty library',
        () async {
      expect(
          await invokeCompleted(
              harness, 'media.library.search', {'query': 'missing'}),
          {'series': [], 'total': 0});
      rows.clear();
      expect(await invokeCompleted(harness, 'media.library.search', {}),
          {'series': [], 'total': 0});
    });

    for (final input in <JsonMap>[
      {'query': ''},
      {'limit': 0},
      {'limit': 201},
      {'limit': 1.5},
      {'extra': true}
    ]) {
      test('rejects invalid search input $input', () async {
        await invokeFailed(
            harness, 'media.library.search', input, FailureCode.invalidInput);
      });
    }
  });

  group('media.library.series', () {
    test('orders episode IDs, treats null IDs separately and orders files',
        () async {
      final result = await invokeCompleted(
          harness, 'media.library.series', {'animeId': 10.0});
      final episodes = result['episodes'] as List;
      expect(episodes.map((item) => item['episodeId']), [100, 200, null, null]);
      expect(episodes.map((item) => item['title']),
          ['Latest title', 'second.mkv', 'a.mkv', 'z.mkv']);
      expect(episodes.first['files'], [
        {
          'path': 'webdav://dav/episode.mkv',
          'source': 'webdav',
          'progress': 0.5,
          'positionMs': 500,
          'durationMs': 1000,
          'lastWatchedAt': '2026-10-10T04:00:00.000Z',
        },
        {
          'path': '/media/older.mkv',
          'source': 'local',
          'progress': 0.5,
          'positionMs': 500,
          'durationMs': 1000,
          'lastWatchedAt': '2026-10-08T04:00:00.000Z',
        },
      ]);
      expect((episodes[1]['files'] as List).single['source'], 'smb');
      final search = await invokeCompleted(
          harness, 'media.library.search', {'query': 'original'});
      expect(result['series'], (search['series'] as List).single);
    });

    test('returns not_found for missing and excluded series', () async {
      await invokeFailed(harness, 'media.library.series', {'animeId': 999},
          FailureCode.notFound);
      rows = [watchItem('jellyfin://123', animeId: 30)];
      await invokeFailed(harness, 'media.library.series', {'animeId': 30},
          FailureCode.notFound);
    });

    test('uses the basename when the latest episode title is null', () async {
      rows = [
        watchItem('/media/latest.mkv', episodeTitle: null),
        watchItem('/media/older.mkv',
            episodeTitle: 'Old title', watchedAt: '2026-10-01T00:00:00Z')
      ];
      final result = await invokeCompleted(
          harness, 'media.library.series', {'animeId': 10});
      expect((result['episodes'] as List).single['title'], 'latest.mkv');
    });
  });

  group('series title rules', () {
    for (final entry in [
      (
        detail: seriesDetail(),
        title: 'Localized title',
        original: 'Original title',
        image: 'https://example.test/cover.jpg'
      ),
      (
        detail: seriesDetail(nameCn: ''),
        title: 'Original title',
        original: null,
        image: 'https://example.test/cover.jpg'
      ),
      (
        detail: seriesDetail(name: '', nameCn: '', imageUrl: ''),
        title: 'Recorded title',
        original: '',
        image: null
      ),
      (
        detail: seriesDetail(name: 'Same', nameCn: 'Same', imageUrl: ''),
        title: 'Same',
        original: null,
        image: null
      ),
      (detail: null, title: 'Recorded title', original: null, image: null),
    ]) {
      test(
          'resolves title ${entry.title}, original ${entry.original} and image ${entry.image}',
          () async {
        final titleHarness = Harness([
          LibraryCapability(
            history: () => [watchItem('/media/episode.mkv')],
            seriesDetail: (_) => entry.detail,
          )
        ]);
        final result =
            await invokeCompleted(titleHarness, 'media.library.search', {});
        final series = (result['series'] as List).single;
        expect(series['title'], entry.title);
        expect(series['originalTitle'], entry.original);
        expect(series['imageUrl'], entry.image);
      });
    }
  });
}
