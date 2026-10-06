import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/media_server_playlist_loader.dart';

void main() {
  Future<List<Map<String, dynamic>>> playlist(
    Map<String, dynamic> json,
    Future<List<Map<String, dynamic>>> Function(String, String) loadSeason,
  ) {
    final item = json;
    return loadMediaServerPlaylist(
      currentItem: item,
      seriesId: item['SeriesId'] as String?,
      seasonId: item['SeasonId'] as String?,
      loadSeason: loadSeason,
    );
  }

  test('Jellyfin movie stays playable without requesting nonexistent season',
      () async {
    final result = await playlist(
      {'Id': 'movie', 'Name': '剧场版', 'Type': 'Movie'},
      (_, __) => throw StateError('Movies have no season endpoint'),
    );
    expect(result.single['Id'], 'movie');
    expect(result.single['Name'], '剧场版');
  });

  test('episode missing season metadata retains the current playable item',
      () async {
    final result = await playlist(
      {'Id': 'episode', 'Name': '第一话', 'SeriesId': 'series'},
      (_, __) => throw StateError('Missing season must not be requested'),
    );
    expect(result.single['Id'], 'episode');
  });

  test(
      'regular episode requests its own season and preserves the returned queue',
      () async {
    final sibling = {'Id': 'sibling', 'Name': '第二话'};
    final result = await playlist(
      {
        'Id': 'episode',
        'Name': '第一话',
        'SeriesId': 'series',
        'SeasonId': 'season'
      },
      (series, season) async {
        expect(series, 'series');
        expect(season, 'season');
        return [sibling];
      },
    );
    expect(result, [sibling]);
  });

  test(
      'server errors remain visible rather than becoming a successful single item',
      () async {
    await expectLater(
      playlist(
        {
          'Id': 'episode',
          'Name': '第一话',
          'SeriesId': 'series',
          'SeasonId': 'season'
        },
        (_, __) async => throw StateError('Server unavailable'),
      ),
      throwsStateError,
    );
  });
}
