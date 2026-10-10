import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/lan_http_policy.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/remote_text_input_service.dart';
import 'package:nipaplay/services/web_api_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Handler handler;
  late CredentialStore previous;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('lan-api-');
    StorageService.debugAppStorageDirectoryOverride = dir;
    SharedPreferences.setMockInitialValues({'auto_sync_enabled': false});
    previous = CredentialStore.instance;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    final foldersLoaded = Completer<void>();
    void onFoldersLoaded() => foldersLoaded.complete();
    ServiceProvider.scanService.addListener(onFoldersLoaded);
    await foldersLoaded.future;
    ServiceProvider.scanService.removeListener(onFoldersLoaded);
    final router = Router()..mount('/api', WebApiService().handler);
    handler = lanResponsePolicy()(router.call);
  });
  tearDownAll(() async {
    RemoteTextInputService.instance.clearForTesting();
    await WatchHistoryDatabase.instance.close();
    ServiceProvider.scanService.dispose();
    StorageService.debugAppStorageDirectoryOverride = null;
    CredentialStore.instance = previous;
    await dir.delete(recursive: true);
  });
  Future<Response> call(String method, String path,
          {Object? body, Map<String, String>? headers}) async =>
      handler(Request(method, Uri.parse('http://host/api/$path'),
          headers: headers, body: body == null ? null : jsonEncode(body)));

  test(
      'C1 discovery/gate and C8 account status retain anonymous JSON contracts',
      () async {
    final info = await call('GET', 'info');
    expect(info.statusCode, 200);
    expect((jsonDecode(await info.readAsString()) as Map)['app'], 'NipaPlay');
    final status = await call('GET', 'dandanplay/login_status');
    expect(status.statusCode, 200);
    expect(status.headers['cache-control'], 'no-store');
    expect(jsonDecode(await status.readAsString()), isA<Map>());
  });

  test(
      'C15 add/browse/play accepts existing JSON without Content-Type and preserves media bounds',
      () async {
    final mediaDir = await Directory('${dir.path}/media').create();
    await File('${mediaDir.path}/episode.mp4').writeAsString('0123456789');
    await File('${mediaDir.path}/episode.srt').writeAsString('subtitle');
    await File('${mediaDir.path}/secret.txt').writeAsString('private');
    final added = await call('POST', 'media/local/manage/folders',
        body: {'path': mediaDir.path, 'scan': false});
    expect(added.statusCode, 200);
    expect((jsonDecode(await added.readAsString()) as Map)['success'], true);
    final browse = await call(
        'GET',
        'media/local/manage/browse?${Uri(queryParameters: {
              'path': mediaDir.path
            }).query}');
    expect(browse.statusCode, 200);
    expect(await browse.readAsString(), isNot(contains('secret.txt')));
    final pathQuery =
        Uri(queryParameters: {'path': '${mediaDir.path}/episode.mp4'}).query;
    for (final method in ['GET', 'HEAD']) {
      final stream = await call(method, 'media/local/manage/stream?$pathQuery',
          headers: {'range': 'bytes=2-5'});
      expect(stream.statusCode, 206);
      expect(stream.headers['content-range'], 'bytes 2-5/10');
      expect(stream.headers['content-length'], '4');
      expect(await stream.readAsString(), method == 'GET' ? '2345' : '');
    }
    final subtitleQuery = Uri(queryParameters: {
      'path': '${mediaDir.path}/episode.mp4',
      'name': 'episode.srt'
    }).query;
    for (final method in ['GET', 'HEAD']) {
      final sub =
          await call(method, 'media/local/manage/subtitle?$subtitleQuery');
      expect(sub.statusCode, 200);
      expect(sub.headers['content-length'], '8');
      expect(await sub.readAsString(), method == 'GET' ? 'subtitle' : '');
    }
    final refused = await call(
        'GET',
        'media/local/manage/stream?${Uri(queryParameters: {
              'path': '${mediaDir.path}/secret.txt'
            }).query}');
    expect(refused.statusCode, 403);
  });

  test(
      'C10/C12 history supports single files outside scanned roots and formats without extensions',
      () async {
    final video = File('${dir.path}/single-file');
    await video.writeAsString('media');
    final saved = await call('POST', 'history/progress', body: {
      'filePath': video.path,
      'animeId': 7,
      'episodeId': 70,
      'positionMs': 5,
      'durationMs': 10,
    });
    expect(saved.statusCode, 200);
    final id = sha1.convert(utf8.encode(video.path)).toString();
    final stream = await call('GET', 'media/local/share/episodes/$id/stream');
    expect(stream.statusCode, 200);
    expect(await stream.readAsString(), 'media');
    final history = await call('GET', 'history');
    expect(history.statusCode, 200);
    expect(await history.readAsString(), contains(video.path));
  });

  test(
      'C11 proxies custom AI, media/loopback and another instance with original auth/method/body',
      () async {
    for (final method in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD']) {
      for (final target in [
        'http://127.0.0.1:9000/custom-ai',
        'http://192.168.1.8:8096/subtitles',
        'http://second:1180/api/media/local/share/episodes/id/stream'
      ]) {
        await http.runWithClient(() async {
          // The client is constructed by WebApiService within this zone.
          final router = Router()..mount('/api', WebApiService().handler);
          final response = await lanResponsePolicy()(router.call)(Request(
              method,
              Uri.parse('http://host/api/web_proxy')
                  .replace(queryParameters: {'url': target}),
              headers: {
                'origin': 'https://independent.example',
                'authorization': 'Bearer upstream-key',
                'range': 'bytes=0-2'
              },
              body: ['GET', 'HEAD'].contains(method) ? null : 'body'));
          expect(response.statusCode, 206);
          expect(response.headers['access-control-allow-origin'],
              'https://independent.example');
          if (method == 'HEAD') expect(response.headers['content-length'], '3');
          expect(await response.readAsString(), method == 'HEAD' ? '' : 'abc');
        },
            () => MockClient.streaming((request, body) async {
                  expect(request.url.toString(), target);
                  expect(request.method, method);
                  expect(
                      request.headers['authorization'], 'Bearer upstream-key');
                  expect(request.headers['range'], 'bytes=0-2');
                  expect(await body.bytesToString(),
                      ['GET', 'HEAD'].contains(method) ? '' : 'body');
                  return http.StreamedResponse(
                      Stream.value(
                          method == 'HEAD' ? <int>[] : utf8.encode('abc')),
                      206,
                      headers: {
                        'content-length': '3',
                        'content-range': 'bytes 0-2/10',
                        'access-control-allow-origin': '*'
                      });
                }));
      }
    }
  });

  test(
      'C17 anonymous commands keep 403 and C18 one-time input HTML/form still works',
      () async {
    final denied =
        await call('POST', 'remote/control/command', body: {'command': 'play'});
    expect(denied.statusCode, 403);
    expect((jsonDecode(await denied.readAsString()) as Map)['code'],
        'remote_control_not_authorized');
    final session = RemoteTextInputService.instance
        .createSession(title: 'Input', initialValue: '');
    final page = await call('GET', 'remote/input/${session.key}');
    expect(page.statusCode, 200);
    expect(page.headers['referrer-policy'], 'no-referrer');
    expect(await page.readAsString(), contains('<form'));
    final submitted = await handler(Request(
        'POST', Uri.parse('http://host/api/remote/input/${session.key}'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'field_0=hello'));
    expect(submitted.statusCode, 200);
    expect(await session.result, 'hello');
  });

  test(
      'C6/C11 both proxy handlers keep the host token off nested attacker URLs',
      () async {
    await DandanplayService.saveLoginInfo(
        'synthetic-host-secret', 'fixture', 'fixture');
    try {
      final target =
          Uri.parse('https://attacker.example/api/image_proxy').replace(
        queryParameters: {
          'url': base64Url
              .encode(utf8.encode('https://api.dandanplay.net/api/v2/favorite'))
        },
      );
      for (final route in ['web_proxy', 'image_proxy']) {
        var requests = 0;
        await http.runWithClient(() async {
          final router = Router()..mount('/api', WebApiService().handler);
          final url = route == 'image_proxy'
              ? base64Url.encode(utf8.encode(target.toString()))
              : target.toString();
          final response = await lanResponsePolicy()(router.call)(Request(
              'GET',
              Uri.parse('http://host/api/$route')
                  .replace(queryParameters: {'url': url}),
              headers: {'origin': 'https://independent.example'}));
          expect(response.statusCode, 200);
          expect(response.headers['cache-control'], 'no-store');
          expect(response.headers['access-control-allow-origin'],
              'https://independent.example');
          expect(await response.readAsString(), 'image');
        },
            () => MockClient((request) async {
                  requests++;
                  expect(request.url, target);
                  expect(request.headers.containsKey('authorization'), isFalse);
                  return http.Response('image', 200,
                      headers: {'content-type': 'image/png'});
                }));
        expect(requests, 1);
      }
    } finally {
      await DandanplayService.clearLoginInfo();
    }
  });
}
