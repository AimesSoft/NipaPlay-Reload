import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/utils/network_settings.dart';

void main() {
  const gateway = NetworkSettings.primaryServer;

  test('every official API blocks anonymous requests before the network',
      () async {
    var requests = 0;
    final client = DandanplayHttpClient(
      authorization: () => {},
      inner: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    for (final path in [
      'comment/123',
      'match',
      'search/anime',
      'search/adv/config',
      'bangumi/shin',
      'bangumi/42/comments',
      'trending/all/hot/week',
      'favorite',
      'playhistory',
      'unknown/future',
      'unknown/healthz',
      'login/renew',
    ]) {
      for (final base in [gateway, 'https://api.dandanplay.net']) {
        await expectLater(
            client.get(Uri.parse('$base/api/v2/$path'), headers: {
              'Authorization': 'Bearer caller-supplied-fake-token',
            }),
            throwsA(isA<DandanplayLoginRequired>()));
      }
    }
    expect(requests, 0);
    client.close();
  });

  test('only POST login/register can start an anonymous session', () async {
    var requests = 0;
    final client = DandanplayHttpClient(
      authorization: () => {},
      inner: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    for (final path in ['login', 'register']) {
      await client.post(Uri.parse('$gateway/api/v2/$path'), body: '{}');
      await expectLater(client.get(Uri.parse('$gateway/api/v2/$path')),
          throwsA(isA<DandanplayLoginRequired>()));
    }
    expect(requests, 2);
    client.close();
  });

  test('an existing client reads current credentials on every request',
      () async {
    var account = <String, String>{'Authorization': 'Bearer account-token'};
    final seen = <http.Request>[];
    final client = DandanplayHttpClient(
      authorization: () => account,
      inner: MockClient((request) async {
        seen.add(request);
        return http.Response('{}', 200);
      }),
    );
    await client.get(Uri.parse('$gateway/api/v2/comment/123'));
    expect(seen.single.headers['authorization'], 'Bearer account-token');
    account = {};
    await expectLater(client.get(Uri.parse('$gateway/api/v2/comment/456')),
        throwsA(isA<DandanplayLoginRequired>()));
    expect(seen.length, 1);
    client.close();
  });

  test('third-party compatible APIs and Bangumi work anonymously', () async {
    final seen = <http.Request>[];
    final client = DandanplayHttpClient(
      authorization: () => {},
      inner: MockClient((request) async {
        seen.add(request);
        return http.Response('{}', 200);
      }),
    );
    for (final url in [
      'https://third-party.example/api/v2/match',
      'https://third-party.example/api/v2/comment/123',
      'https://api.bgm.tv/v0/subjects/1',
      'https://assets.anixplayer.net/poster/example.jpg',
      '$gateway/healthz',
    ]) {
      await client.get(Uri.parse(url));
    }
    expect(seen.length, 5);
    expect(seen.every((r) => !r.headers.containsKey('authorization')), isTrue);
    client.close();
  });

  test('never forwards the Dandanplay account token to a custom provider',
      () async {
    final seen = <http.Request>[];
    final client = DandanplayHttpClient(
      authorization: () => {'Authorization': 'Bearer account-token'},
      inner: MockClient((request) async {
        seen.add(request);
        return http.Response('{}', 200);
      }),
    );
    await client.get(
        Uri.parse('https://third-party.example/api/v2/comment/123'),
        headers: {'Authorization': 'Bearer account-token'});
    await client.get(Uri.parse('https://api.bgm.tv/v0/me'),
        headers: {'Authorization': 'Bearer bangumi-token'});
    expect(seen[0].headers.containsKey('authorization'), isFalse);
    expect(seen[1].headers['authorization'], 'Bearer bangumi-token');
    client.close();
  });

  test('Web/image relay URLs cannot bypass the provider gate', () async {
    var requests = 0;
    final client = DandanplayHttpClient(
      authorization: () => {},
      inner: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    for (final relay in ['web_proxy', 'image_proxy']) {
      final uri = Uri.parse('http://localhost:8080/api/$relay').replace(
        queryParameters: {'url': '$gateway/api/v2/comment/123'},
      );
      await expectLater(
          client.get(uri), throwsA(isA<DandanplayLoginRequired>()));
    }
    expect(requests, 0);
    client.close();
  });

  test('base64 image relay URLs cannot bypass the provider gate', () async {
    final client = DandanplayHttpClient(
      authorization: () => {},
      inner: MockClient((_) async => fail('Must not reach the network')),
    );
    final uri = Uri.parse('http://localhost:8080/api/image_proxy').replace(
      queryParameters: {
        'url': base64Url.encode(utf8.encode('$gateway/api/v2/comment/123')),
      },
    );
    await expectLater(client.get(uri), throwsA(isA<DandanplayLoginRequired>()));
    client.close();
  });
}
