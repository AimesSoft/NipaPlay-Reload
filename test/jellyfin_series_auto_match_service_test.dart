import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/services/jellyfin_series_auto_match_service.dart';

JellyfinMediaItem series({String id = 'series-1'}) => JellyfinMediaItem(
      id: id,
      name: 'Server title',
      dateAdded: DateTime(2026),
      type: 'Series',
      isFolder: true,
    );

JellyfinSeasonInfo season() => JellyfinSeasonInfo(
      id: 'season-1',
      name: 'Season 1',
      seriesId: 'series-1',
      indexNumber: 1,
    );

JellyfinEpisodeInfo episode() => JellyfinEpisodeInfo(
      id: 'episode-1',
      name: 'Episode 1',
      seriesId: 'series-1',
      seriesName: 'Server title',
      seasonId: 'season-1',
      indexNumber: 1,
      dateAdded: DateTime(2026),
    );

JellyfinSeriesAutoMatchService service({
  required Future<bool> Function() isEnabled,
  Future<Map<String, dynamic>?> Function(String)? loadMapping,
  Future<Map<String, dynamic>> Function(JellyfinEpisodeInfo)? loadVideoInfo,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? matchExactly,
  Future<int> Function(JellyfinMediaItem, int, String)? writeSeriesMapping,
  Future<void> Function(JellyfinEpisodeInfo, int, int)? writeEpisodeMapping,
}) {
  return JellyfinSeriesAutoMatchService(
    isEnabled: isEnabled,
    loadMapping: loadMapping ?? (_) async => null,
    loadSeasons: (_) async => [season()],
    loadEpisodes: (_, __) async => [episode()],
    loadVideoInfo: loadVideoInfo ??
        (_) async => {
              'hash': 'hash',
              'fileName': 'Episode 1.mkv',
              'fileSize': 1024,
            },
    matchExactly: matchExactly ??
        (_) async => {
              'isMatched': true,
              'matches': [
                {
                  'animeId': 123,
                  'animeTitle': 'Canonical title',
                  'episodeId': 1230001,
                },
              ],
            },
    writeSeriesMapping: writeSeriesMapping ?? (_, __, ___) async => 7,
    writeEpisodeMapping: writeEpisodeMapping ?? (_, __, ___) async {},
  );
}

void main() {
  test('disabled setting leaves an unmapped Series untouched', () async {
    var loadedVideoInfo = false;
    final matcher = service(
      isEnabled: () async => false,
      loadVideoInfo: (_) async {
        loadedVideoInfo = true;
        return {};
      },
    );

    final result = await matcher.matchSeriesIfEnabled(series());

    expect(result, isNull);
    expect(loadedVideoInfo, isFalse);
  });

  test('existing Series mapping avoids reading media data', () async {
    var loadedVideoInfo = false;
    final matcher = service(
      isEnabled: () async => true,
      loadMapping: (_) async => {
        'dandanplay_anime_id': 456,
        'dandanplay_anime_title': 'Mapped title',
      },
      loadVideoInfo: (_) async {
        loadedVideoInfo = true;
        return {};
      },
    );

    final result = await matcher.matchSeriesIfEnabled(series());

    expect(result?.animeId, 456);
    expect(result?.animeTitle, 'Mapped title');
    expect(loadedVideoInfo, isFalse);
  });

  test(
    'exact match creates Series and representative Episode mappings',
    () async {
      final writes = <String>[];
      final matcher = service(
        isEnabled: () async => true,
        writeSeriesMapping: (item, animeId, animeTitle) async {
          writes.add('series:${item.id}:$animeId:$animeTitle');
          return 9;
        },
        writeEpisodeMapping: (item, episodeId, mappingId) async {
          writes.add('episode:${item.id}:$episodeId:$mappingId');
        },
      );

      final result = await matcher.matchSeriesIfEnabled(series());

      expect(result?.animeId, 123);
      expect(result?.episodeId, 1230001);
      expect(writes, [
        'series:series-1:123:Canonical title',
        'episode:episode-1:1230001:9',
      ]);
    },
  );

  test('concurrent requests for one Series share a single hash task', () async {
    final gate = Completer<void>();
    var hashCalls = 0;
    final matcher = service(
      isEnabled: () async => true,
      loadVideoInfo: (_) async {
        hashCalls++;
        await gate.future;
        return {'hash': 'hash', 'fileName': 'Episode 1.mkv', 'fileSize': 1024};
      },
    );

    final first = matcher.matchSeriesIfEnabled(series());
    final second = matcher.matchSeriesIfEnabled(series());
    await Future<void>.delayed(Duration.zero);
    gate.complete();

    final results = await Future.wait([first, second]);
    expect(hashCalls, 1);
    expect(results.map((result) => result?.animeId), [123, 123]);
  });

  test('batch matching hashes at most two Series concurrently', () async {
    final gate = Completer<void>();
    var active = 0;
    var maxActive = 0;
    var hashCalls = 0;
    final matcher = service(
      isEnabled: () async => true,
      loadVideoInfo: (_) async {
        hashCalls++;
        active++;
        if (active > maxActive) maxActive = active;
        await gate.future;
        active--;
        return {'hash': 'hash', 'fileName': 'Episode 1.mkv', 'fileSize': 1024};
      },
    );

    final batch = matcher.matchSeriesBatchIfEnabled([
      series(id: 'series-1'),
      series(id: 'series-2'),
      series(id: 'series-3'),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(hashCalls, 2);
    expect(maxActive, 2);
    gate.complete();
    await batch;
    expect(hashCalls, 3);
  });

  test('invalid exact match is not persisted', () async {
    var writeCalled = false;
    final matcher = service(
      isEnabled: () async => true,
      matchExactly: (_) async => {
        'isMatched': false,
        'matches': <Map<String, dynamic>>[],
      },
      writeSeriesMapping: (_, __, ___) async {
        writeCalled = true;
        return 1;
      },
    );

    final result = await matcher.matchSeriesIfEnabled(series());

    expect(result, isNull);
    expect(writeCalled, isFalse);
  });
}
