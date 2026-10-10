import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/host.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/media/provider_transport.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/network/dandanplay_gateway.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/nipaplay_server_router.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'danmaku_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final router = NipaplayServerRouter.instance;
  const primary = NetworkSettings.hongKongServer;
  const backup = NetworkSettings.chinaServer;
  late List<http.Request> requests;
  late DandanplayGateway gateway;
  late http.Client publicClient;
  late HttpDanmakuHost host;
  late HttpMetadataTransport metadata;
  late Map<String, String> account;
  var responseStatus = 200;
  String? networkError;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      NetworkSettings.autoRegionKey: NetworkSettings.autoRegionOverseas,
      NetworkSettings.autoRegionAtKey: DateTime.now().millisecondsSinceEpoch,
    });
    router.reportSuccess(Uri.parse(primary));
    router.reportSuccess(Uri.parse(backup));
    requests = [];
    account = {'Authorization': 'Bearer account-fixture-token'};
    responseStatus = 200;
    networkError = null;
    final client = DandanplayHttpClient(
        authorization: () => account,
        inner: MockClient((request) async {
          requests.add(request);
          if (networkError case final error?) {
            throw http.ClientException(error, request.url);
          }
          final fixtures = jsonDecode(
              await File('test/next/fixtures/media/dandanplay.json')
                  .readAsString()) as Map;
          final endpoint = request.url.path.substring('/dandanplay'.length);
          return http.Response(
              jsonEncode(fixtures[endpoint] ?? {}), responseStatus, headers: {
            'content-type': 'application/json; charset=utf-8',
            'retry-after': '0'
          });
        }));
    gateway = DandanplayGateway(client: client);
    publicClient = MockClient((_) async => fail('Wrong provider client'));
    host = HttpDanmakuHost(
        publicClient: publicClient,
        dandanplay: gateway,
        interval: Duration.zero);
    metadata =
        HttpMetadataTransport.dandanplay(gateway, interval: Duration.zero);
  });
  tearDown(() {
    gateway.client.close();
    publicClient.close();
    router.reportSuccess(Uri.parse(primary));
    router.reportSuccess(Uri.parse(backup));
  });

  Future<List<int>> searchDanmaku([String query = '动画']) => host.request(
      'dandanplay.search', {'query': query}, null, DanmakuCancellation());

  test(
      'all Dandanplay profiles and metadata operations use Classic gateway '
      'URLs and current account authentication', () async {
    expect(await DandanplayService.getApiBaseUrl(), primary);
    await searchDanmaku();
    await host.request(
        'dandanplay.episodes', {'workId': '7001'}, null, DanmakuCancellation());
    await host.request('dandanplay.comments', {'videoId': '7101'}, null,
        DanmakuCancellation());
    account = {'Authorization': 'Bearer updated-fixture-token'};
    final provider = DandanplayMetadataProvider(metadata);
    final anime = (await provider.search('动画')).single;
    await provider.get(anime.ref);
    await provider.matchHash('fixture.mkv', 'fixture-hash', 100);
    expect(requests.map((r) => r.url.toString()), [
      '$primary/api/v2/search/episodes?anime=${Uri.encodeQueryComponent('动画')}',
      '$primary/api/v2/bangumi/7001',
      '$primary/api/v2/comment/7101?withRelated=true&chConvert=0',
      '$primary/api/v2/search/anime?keyword=${Uri.encodeQueryComponent('动画')}',
      '$primary/api/v2/bangumi/7001',
      '$primary/api/v2/match',
    ]);
    expect(
        requests.take(3).every((r) =>
            r.headers['authorization'] == 'Bearer account-fixture-token'),
        isTrue);
    expect(
        requests.skip(3).every((r) =>
            r.headers['authorization'] == 'Bearer updated-fixture-token'),
        isTrue);
    expect(
        requests.every((r) => !r.headers.containsKey('x-signature')), isTrue);
    expect(requests.last.method, 'POST');
    expect((jsonDecode(requests.last.body) as Map)['matchMode'], 'hashOnly');
  });

  test('injected routing preserves nested gateway prefixes and trailing slash',
      () async {
    await NetworkSettings.setDandanplayServer(
        'https://custom.invalid/proxy/dandanplay/');
    var routeCalls = 0;
    final custom = DandanplayGateway(
        client: gateway.client,
        apiBaseUrl: () async {
          routeCalls++;
          return 'https://custom.invalid/proxy/dandanplay/';
        });
    await HttpMetadataTransport.dandanplay(custom, interval: Duration.zero)
        .request('/api/v2/search/anime', query: {'keyword': 'fixture'});
    expect(routeCalls, 1);
    expect(requests.single.url.toString(),
        'https://custom.invalid/proxy/dandanplay/api/v2/search/anime?keyword=fixture');
    expect(requests.single.headers['authorization'],
        'Bearer account-fixture-token');
  });

  for (final driver in ['danmaku', 'metadata']) {
    for (final failure in ['HTTP 502', 'connection error']) {
      test(
          '$driver $failure triggers Classic failover for both existing '
          'Next consumers', () async {
        if (failure == 'HTTP 502') {
          responseStatus = 502;
        } else {
          networkError = 'synthetic offline failure';
        }
        final switched = Completer<void>();
        void changed() {
          if (router.snapshot?.effectiveServer == backup &&
              !switched.isCompleted) {
            switched.complete();
          }
        }

        router.snapshotNotifier.addListener(changed);
        addTearDown(() => router.snapshotNotifier.removeListener(changed));
        for (var i = 0; i < NipaplayServerRouter.failureThreshold; i++) {
          await expectLater(
              driver == 'danmaku'
                  ? searchDanmaku()
                  : metadata.request('/api/v2/search/anime'),
              throwsA(driver == 'danmaku'
                  ? isA<SourceFailure>().having(
                      (e) => e.status, 'status', SourceStatus.transportFailed)
                  : isA<ProviderRetry>()));
        }
        await switched.future.timeout(const Duration(seconds: 2));
        expect(requests.every((r) => r.url.host == Uri.parse(primary).host),
            isTrue);
        expect(await DandanplayService.getApiBaseUrl(), backup);
        responseStatus = 200;
        networkError = null;
        // Use the already-created consumers: neither may cache the old route.
        await searchDanmaku();
        await DandanplayMetadataProvider(metadata).search('动画');
        expect(requests[requests.length - 2].url.path,
            '/dandanplay/api/v2/search/episodes');
        expect(requests.last.url.path, '/dandanplay/api/v2/search/anime');
        expect(
            requests
                .skip(NipaplayServerRouter.failureThreshold)
                .every((r) => r.url.host == Uri.parse(backup).host),
            isTrue);
      });
    }
  }

  test('Classic login gate is translated without sending anonymous requests',
      () async {
    account = {};
    await expectLater(
        searchDanmaku(),
        throwsA(isA<SourceFailure>().having(
            (e) => e.status, 'status', SourceStatus.authenticationRequired)));
    await expectLater(
        metadata.request('/api/v2/search/anime'),
        throwsA(isA<Failure>().having(
            (e) => e.message, 'message', contains('login is required'))));
    expect(requests, isEmpty);
  });

  test(
      'Dandanplay failures contain status, target and content type without '
      'query, credentials or exception text', () async {
    responseStatus = 502;
    await expectLater(
        searchDanmaku('query-fixture-secret'),
        throwsA(isA<SourceFailure>().having(
            (e) => e.message,
            'message',
            allOf(
                contains('HTTP 502'),
                contains('host=${Uri.parse(primary).host}'),
                contains('path=/dandanplay/api/v2/search/episodes'),
                contains('content-type=application/json'),
                isNot(contains('query-fixture-secret')),
                isNot(contains('account-fixture-token'))))));
    networkError = 'Bearer exception-fixture-secret';
    await expectLater(
        searchDanmaku('query-fixture-secret'),
        throwsA(isA<SourceFailure>().having(
            (e) => e.message,
            'message',
            allOf(
                contains('HTTP unavailable'),
                contains('path=/dandanplay/api/v2/search/episodes'),
                isNot(contains('exception-fixture-secret')),
                isNot(contains('query-fixture-secret'))))));
  });

  for (final provider in ['tmdb', 'bangumi']) {
    for (final prefix in ['', '/proxy/provider', '/proxy/provider/']) {
      test('$provider base prefix "$prefix" survives GET and POST paths',
          () async {
        final seen = <http.Request>[];
        final client = MockClient((request) async {
          seen.add(request);
          return http.Response('{}', 200);
        });
        addTearDown(client.close);
        final transport = HttpMetadataTransport(
            provider: provider,
            baseUri: Uri.parse('https://example.invalid$prefix'),
            client: client,
            interval: Duration.zero);
        final path =
            provider == 'tmdb' ? '/3/search/tv' : '/v0/search/subjects';
        await transport.request(path, query: {'q': '动画'});
        await transport.request(path.substring(1), body: {'keyword': '动画'});
        final expected = '${prefix.replaceFirst(RegExp(r'/+$'), '')}$path';
        expect(seen.map((r) => r.url.path), [expected, expected]);
        expect(seen.first.url.queryParameters, {'q': '动画'});
        expect(seen.last.method, 'POST');
        expect(jsonDecode(seen.last.body), {'keyword': '动画'});
      });
    }
  }

  for (final status in [404, 502, 200]) {
    test(
        'metadata HTTP $status diagnostics exclude authenticated URL and '
        'response content', () async {
      final client = MockClient((_) async => http.Response(
              'body-fixture-secret', status, headers: {
            'content-type': 'text/html; secret=header-fixture-secret'
          }));
      addTearDown(client.close);
      final transport = HttpMetadataTransport(
          provider: 'tmdb',
          baseUri: Uri.parse(
              'https://user-fixture:password-fixture@example.invalid/proxy'),
          client: client,
          privateQuery: () async => {'api_key': 'api-fixture-secret'},
          interval: Duration.zero);
      String? message;
      try {
        await transport.request('/3/search/tv');
        fail('Must reject error or malformed JSON');
      } on ProviderRetry catch (error) {
        message = error.reason;
      } on Failure catch (error) {
        message = error.message;
      }
      expect(
          message,
          allOf(
              contains('HTTP $status'),
              contains('host=example.invalid'),
              contains('path=/proxy/3/search/tv'),
              contains('content-type=text/html')));
      for (final secret in [
        'user-fixture',
        'password-fixture',
        'api-fixture-secret',
        'body-fixture-secret',
        'header-fixture-secret'
      ]) {
        expect(message, isNot(contains(secret)));
      }
    });
  }

  test('danmaku action keeps transport diagnostics in its failure envelope',
      () async {
    final fixture = DanmakuFixture();
    await fixture.open();
    addTearDown(fixture.close);
    fixture.host.failure = const SourceFailure(SourceStatus.transportFailed,
        diagnostics: 'HTTP 502; host=fixture.invalid; '
            'path=/dandanplay/api/v2/search/episodes; content-type=text/html');
    final outcome = await fixture.harness.invokeJson(
        'danmaku.search',
        {'sourceId': 'dandanplay', 'query': 'fixture'},
        Invocation(origin: 'mcp'));
    expect(
        outcome,
        isA<Failed>().having(
            (e) => e.failure.message,
            'message',
            allOf(
                contains('transportFailed'),
                contains('HTTP 502'),
                contains('/dandanplay/api/v2/search/episodes'),
                contains('content-type=text/html'))));
  });
}
