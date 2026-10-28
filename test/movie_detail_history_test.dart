import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';

void main() {
  final payload = <String, dynamic>{
    'Id': 'movie-id',
    'Name': 'Fixture Movie',
    'Type': 'Movie',
    'DateCreated': '2026-10-05T00:00:00Z',
    'Genres': ['Animation'],
    'Studios': [{'Name': 'Fixture Studio'}],
    'RunTimeTicks': 450000000,
  };
  test('Jellyfin movie details produce a playable unmatched movie identity', () {
    final detail = JellyfinMediaItemDetail.fromJson(payload);
    final movie = JellyfinMovieInfo.fromDetail(detail);
    final history = movie.toWatchHistoryItem();
    expect(history.filePath, 'jellyfin://movie-id');
    expect(history.animeName, 'Fixture Movie');
    expect(history.episodeTitle, isNull);
    expect(history.animeId, isNull);
    expect(history.episodeId, isNull);
    expect(movie.runTimeTicks, 450000000);
    expect(movie.genres, ['Animation']);
    expect(movie.dateAdded, detail.dateAdded);
  });
  test('Emby movie details produce a playable unmatched movie identity', () {
    final detail = EmbyMediaItemDetail.fromJson(payload);
    final movie = EmbyMovieInfo.fromDetail(detail);
    final history = movie.toWatchHistoryItem();
    expect(history.filePath, 'emby://movie-id');
    expect(history.animeName, 'Fixture Movie');
    expect(history.episodeTitle, isNull);
    expect(history.animeId, isNull);
    expect(history.episodeId, isNull);
    expect(movie.runTimeTicks, 450000000);
    expect(movie.genres, ['Animation']);
    expect(movie.dateAdded, detail.dateAdded);
  });
}
