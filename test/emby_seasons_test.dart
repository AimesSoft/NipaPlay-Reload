import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #570：有的 Emby 服务端会忽略通用 Items 接口的 IncludeItemTypes 过滤，
// 把单集当成季返回。季列表必须走标准季接口，并且只保留真正的季/集。

const _season1 = {
  'Id': 'season-1',
  'Name': '第 1 季',
  'Type': 'Season',
  'SeriesId': 'series',
  'IndexNumber': 1,
};
const _season2 = {
  'Id': 'season-2',
  'Name': '第 2 季',
  'Type': 'Season',
  'SeriesId': 'series',
  'IndexNumber': 2,
};
const _episode1 = {
  'Id': 'episode-1',
  'Name': '第一集的标题',
  'Type': 'Episode',
  'SeriesId': 'series',
  'SeasonId': 'season-1',
  'IndexNumber': 1,
  'ParentIndexNumber': 1,
};

Future<List<Uri>> _serve(
  Map<String, Object> responses, {
  required void Function(String baseUrl) onReady,
}) async {
  SharedPreferences.setMockInitialValues({});
  final requests = <Uri>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    requests.add(request.uri);
    final body = responses[request.uri.path];
    if (body == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>404 Not Found</html>');
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
    }
    await request.response.close();
  });

  final service = EmbyService.instance;
  final oldUrl = service.serverUrl;
  final oldUser = service.userId;
  final oldToken = service.accessToken;
  final oldConnected = service.isConnected;
  final oldProfile = service.currentProfile;
  final oldLibraries = List<EmbyLibrary>.of(service.availableLibraries);
  addTearDown(() async {
    await server.close(force: true);
    service.currentProfile = oldProfile;
    service.serverUrl = oldUrl;
    service.userId = oldUser;
    service.accessToken = oldToken;
    service.isConnected = oldConnected;
    service.availableLibraries
      ..clear()
      ..addAll(oldLibraries);
  });
  service.currentProfile = null;
  service.userId = 'test-user';
  service.accessToken = 'test-token';
  service.isConnected = true;
  onReady('http://${server.address.address}:${server.port}');
  return requests;
}

void main() {
  test('季列表使用标准季接口', () async {
    final requests = await _serve({
      '/emby/Shows/series/Seasons': {
        'Items': [_season1, _season2],
      },
    }, onReady: (url) => EmbyService.instance.serverUrl = url);

    final seasons = await EmbyService.instance.getSeasons('series');

    expect(seasons.map((s) => s.id), ['season-1', 'season-2']);
    expect(requests.single.path, '/emby/Shows/series/Seasons');
    expect(requests.single.queryParameters['userId'], 'test-user');
  });

  test('标准季接口不可用时回退到 Items 接口，并丢弃混进来的单集', () async {
    final requests = await _serve({
      // 服务端无视 IncludeItemTypes=Season，季和单集混在一起返回。
      '/emby/Users/test-user/Items': {
        'Items': [_season1, _episode1, _season2],
      },
    }, onReady: (url) => EmbyService.instance.serverUrl = url);

    final seasons = await EmbyService.instance.getSeasons('series');

    expect(seasons.map((s) => s.name), ['第 1 季', '第 2 季']);
    expect(requests.map((r) => r.path), [
      '/emby/Shows/series/Seasons',
      '/emby/Users/test-user/Items',
    ]);
  });

  test('按季取集时丢弃混进来的季条目', () async {
    await _serve({
      '/emby/Users/test-user/Items': {
        'Items': [_season1, _episode1],
      },
    }, onReady: (url) => EmbyService.instance.serverUrl = url);

    final episodes = await EmbyService.instance.getEpisodes('season-1');

    expect(episodes.map((e) => e.id), ['episode-1']);
  });
}
