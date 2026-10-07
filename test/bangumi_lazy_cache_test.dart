import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart'
    show DandanplayLoginRequired;
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

BangumiAnime anime(int id, {String name = 'Cached', String? background}) =>
    BangumiAnime(
      id: id,
      name: name,
      nameCn: name,
      imageUrl: '',
      tags: ['tag'],
      language: 'zh',
      backgroundImageUrl: background,
    );
String stored(BangumiAnime anime, {int? timestamp}) => jsonEncode({
      'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
      'animeDetail': anime.toJson(),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'startup decodes no details; hot cache is bounded and custom metadata survives eviction',
      () async {
    SharedPreferences.setMockInitialValues({
      for (var id = 1; id <= 110; id++) 'bangumi_detail_$id': stored(anime(id)),
      'bangumi_detail_-1': stored(
          anime(-1, name: 'Custom', background: '/local/background.png'),
          timestamp: 0),
    });
    var requests = 0;
    final service = BangumiService.forTesting(MockClient((_) async {
      requests++;
      throw DandanplayLoginRequired();
    }));
    await service.initialize();
    expect(service.getAnimeDetailsFromMemory(1), isNull);
    expect((await service.getAnimeDetails(-1)).name, 'Custom');
    for (var id = 1; id <= 110; id++) {
      await service.getAnimeDetails(id);
    }
    expect(service.getAnimeDetailsFromMemory(1), isNull);
    expect(service.getAnimeDetailsFromMemory(-1), isNull);
    expect((await service.getAnimeDetails(-1)).backgroundImageUrl,
        '/local/background.png');
    expect(requests, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('bangumi_detail_-1'), isTrue);
  });

  test('failed refresh keeps stale details in memory and persistent storage',
      () async {
    final cached = stored(anime(2), timestamp: 0);
    SharedPreferences.setMockInitialValues({'bangumi_detail_2': cached});
    await NetworkSettings.setDandanplayServerMode(
        DandanplayServerMode.hongKong);
    final service = BangumiService.forTesting(
        MockClient((_) async => throw DandanplayLoginRequired()));
    expect((await service.getAnimeDetails(2)).name, 'Cached');
    expect(
        (await SharedPreferences.getInstance()).getString('bangumi_detail_2'),
        cached);
    expect(service.getAnimeDetailsFromMemory(2)?.name, 'Cached');
  });

  test('concurrent refreshes share a request and cannot overwrite a user edit',
      () async {
    SharedPreferences.setMockInitialValues(
        {'bangumi_detail_3': stored(anime(3))});
    await NetworkSettings.setDandanplayServerMode(
        DandanplayServerMode.hongKong);
    final entered = Completer<void>();
    final release = Completer<void>();
    var requests = 0;
    final service = BangumiService.forTesting(MockClient((_) async {
      requests++;
      entered.complete();
      await release.future;
      return http.Response(
          jsonEncode({
            'success': true,
            'bangumi': {
              'animeId': 3,
              'animeTitle': 'API',
              'tags': [
                {'name': 'new'}
              ]
            }
          }),
          200);
    }));
    final first = service.getAnimeDetails(3, forceRefresh: true);
    final second = service.getAnimeDetails(3, forceRefresh: true);
    await entered.future;
    await service.saveCustomAnimeDetail(
        3, anime(3, name: 'Edited', background: '/edited.png'));
    release.complete();
    final results = await Future.wait([first, second]);
    expect(requests, 1);
    expect(results.map((item) => item.name), ['Edited', 'Edited']);
    expect(service.getAnimeDetailsFromMemory(3)?.backgroundImageUrl,
        '/edited.png');
    expect(
        (await SharedPreferences.getInstance()).getString('bangumi_detail_3'),
        contains('Edited'));
  });
}
