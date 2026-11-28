import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mirror = 'https://one.example';
  const otherMirror = 'https://two.example';

  void seed(int id) => SharedPreferences.setMockInitialValues({
        'bangumi_server_url': mirror,
        'bangumi_detail_$id': jsonEncode({
          'bangumi': {'bangumiId': id}
        }),
      });

  BangumiAnime anime(int id) =>
      BangumiAnime(id: id, name: '番剧', nameCn: '', imageUrl: 'fallback-$id');

  for (final status in [429, 503]) {
    test('mirror retries after $status and upgrades the fallback', () async {
      final item = anime(status);
      seed(item.id);
      var recovering = false;
      final requests = <String>[];
      await http.runWithClient(() async {
        expect(await resolveDashboardCover(item.id, item), item.imageUrl);
        recovering = true;
        expect(await resolveDashboardCover(item.id, item),
            '$mirror/v0/subjects/$status/image?type=large');
        expect(requests, [mirror, mirror]);
      },
          () => MockClient((request) async {
                if (request.method == 'HEAD') {
                  requests.add(request.url.origin);
                  return http.Response('', recovering ? 200 : status);
                }
                return http.Response('{}', 200);
              }));
    });
  }

  test('changing the mirror resolves the same anime again', () async {
    final item = anime(800);
    seed(item.id);
    final hosts = <String>[];
    await http.runWithClient(() async {
      expect(await resolveDashboardCover(item.id, item), startsWith(mirror));
      await NetworkSettings.setBangumiServer(otherMirror);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'bangumi_detail_800',
          jsonEncode({
            'bangumi': {'bangumiId': 800}
          }));
      expect(
          await resolveDashboardCover(item.id, item), startsWith(otherMirror));
      expect(hosts, [mirror, otherMirror]);
    },
        () => MockClient((request) async {
              hosts.add(request.url.origin);
              return http.Response('', 200);
            }));
  });

  testWidgets('a missing cover is retried after ten minutes', (tester) async {
    final item = anime(404);
    seed(item.id);
    var requests = 0;
    final client = MockClient((request) async {
      if (request.method != 'HEAD') return http.Response('{}', 200);
      requests++;
      return http.Response('', requests == 1 ? 404 : 200);
    });
    await http.runWithClient(() async {
      expect(await resolveDashboardCover(item.id, item), item.imageUrl);
      await tester.pump(const Duration(minutes: 9));
      expect(await resolveDashboardCover(item.id, item), item.imageUrl);
      expect(requests, 1);
      await tester.pump(const Duration(minutes: 1));
      expect(await resolveDashboardCover(item.id, item), startsWith(mirror));
      expect(requests, 2);
    }, () => client);
  });

  test('concurrent upgrades share one HEAD and cache its success', () async {
    final item = anime(801);
    seed(item.id);
    final started = Completer<void>();
    final response = Completer<http.Response>();
    var requests = 0;
    await http.runWithClient(() async {
      final first = resolveDashboardCover(item.id, item);
      final second = resolveDashboardCover(item.id, item);
      await started.future;
      response.complete(http.Response('', 200));
      expect(await first, startsWith(mirror));
      expect(await second, await first);
      expect(await resolveDashboardCover(item.id, item), await first);
      expect(requests, 1);
    },
        () => MockClient((request) async {
              requests++;
              if (!started.isCompleted) started.complete();
              return response.future;
            }));
  });
}
