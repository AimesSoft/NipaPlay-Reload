import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/services/media_server_playlist_loader.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final payload = <String, dynamic>{
    'Id': 'movie-id',
    'Name': 'Fixture Movie',
    'Type': 'Movie',
    'DateCreated': '2026-10-05T00:00:00Z',
    'Genres': ['Animation'],
    'Studios': [
      {'Name': 'Fixture Studio'}
    ],
    'RunTimeTicks': 450000000,
  };

  testWidgets(
      'Jellyfin detail Play returns a movie when matching is skipped',
      (tester) => http.runWithClient(() async {
            tester.view.physicalSize = const Size(1280, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            SharedPreferences.setMockInitialValues({
              'skip_danmaku_matching': true,
            });
            PackageInfo.setMockInitialValues(
              appName: 'NipaPlay',
              packageName: 'nipaplay',
              version: '1.0.0',
              buildNumber: '1',
              buildSignature: '',
            );
            final service = JellyfinService.instance
              ..serverUrl = 'http://jellyfin.test'
              ..accessToken = 'fixture'
              ..userId = 'user'
              ..isConnected = true;
            addTearDown(() {
              service
                ..serverUrl = null
                ..accessToken = null
                ..userId = null
                ..isConnected = false;
            });
            WatchHistoryItem? selected;
            final settings = SettingsProvider();
            addTearDown(settings.dispose);
            await tester.pumpWidget(MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: settings),
                ChangeNotifierProvider(
                    create: (_) => AppearanceSettingsProvider()),
                ChangeNotifierProvider(
                    create: (_) => LargeScreenUiSfxService()),
              ],
              child: MaterialApp(
                home: NipaplayLargeScreenModeScope(
                  isActive: true,
                  child: Scaffold(
                    body: Builder(builder: (context) {
                      return TextButton(
                        onPressed: () async {
                          selected = await MediaServerDetailPage.showJellyfin(
                              context, 'movie-id');
                        },
                        child: const Text('Open movie'),
                      );
                    }),
                  ),
                ),
              ),
            ));
            await tester.tap(find.text('Open movie'));
            await tester.pumpAndSettle();
            expect(settings.skipDanmakuMatching, isTrue);
            await tester.tap(find.text('播放').last);
            await tester.pumpAndSettle();
            expect(selected?.filePath, 'jellyfin://movie-id');
            expect(selected?.animeId, isNull);
            expect(find.byType(MediaServerDetailPage), findsNothing);
          },
              () => MockClient((request) async =>
                  request.url.path == '/Users/user/Items/movie-id'
                      ? http.Response(jsonEncode(payload), 200,
                          headers: {'content-type': 'application/json'})
                      : http.Response('', 404))));

  test('Jellyfin movie details from the item endpoint form a one-item queue',
      () async {
    final item = JellyfinEpisodeInfo.fromJson(payload);
    final queue = await loadMediaServerPlaylist(
      currentItem: item,
      seriesId: item.seriesId,
      seasonId: item.seasonId,
      loadSeason: (_, __) => fail('A movie has no season to request'),
    );
    expect(queue.single.id, 'movie-id');
    expect(queue.single.name, 'Fixture Movie');
  });

  test('Emby movie details from the item endpoint form a one-item queue',
      () async {
    final item = EmbyEpisodeInfo.fromJson(payload);
    final queue = await loadMediaServerPlaylist(
      currentItem: item,
      seriesId: item.seriesId,
      seasonId: item.seasonId,
      loadSeason: (_, __) => fail('A movie has no season to request'),
    );
    expect(queue.single.id, 'movie-id');
    expect(queue.single.name, 'Fixture Movie');
  });
  test('Jellyfin movie details produce a playable unmatched movie identity',
      () {
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
