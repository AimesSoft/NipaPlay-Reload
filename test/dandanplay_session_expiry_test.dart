import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved login the server no longer accepts: NipaPlay renews it once and
/// carries on, or, when the renewal is refused too, ends the login and says
/// so instead of blaming the network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final favorites =
      Uri.parse('${NetworkSettings.primaryServer}/api/v2/favorite');
  final refusedBody = jsonEncode({
    'errorCode': 401,
    'errorMessage': '弹弹play登录已失效，请重新登录',
    'success': false,
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DandanplayService.saveLoginInfo('stale', 'user', 'User');
  });
  tearDown(DandanplayService.clearLoginInfo);

  /// The gateway, as it answers: favorites take only [accepted]; renewal is
  /// GET only and answers [renewal] for the stale token.
  /// Only favorites and renewals are recorded; the router's own region and
  /// health probes are not this test's business. [hold] delays the stale
  /// refusals, so that several arrive together.
  MockClient gateway(List<String> seen,
          {required String accepted,
          required http.Response Function() renewal,
          Future<void>? hold}) =>
      MockClient((request) async {
        final auth = request.headers['authorization'] ?? '';
        final name = request.url.path.split('/').last;
        if (name != 'favorite' && name != 'renew') {
          return http.Response('{}', 200);
        }
        seen.add('${request.method} $name $auth');
        if (name == 'favorite' && auth == 'Bearer stale') await hold;
        if (request.url.path.endsWith('/api/v2/login/renew')) {
          if (request.method == 'POST') {
            return http.Response('', 405, headers: {'allow': 'GET'});
          }
          return renewal();
        }
        return auth == 'Bearer $accepted'
            ? http.Response('{"success":true,"favorites":[]}', 200)
            : http.Response(refusedBody, 401,
                headers: {'content-type': 'application/json; charset=utf-8'});
      });

  test('a refused token is renewed once and the request goes through',
      () async {
    final seen = <String>[];
    final expired = DandanplayService.loginExpired.value;
    final response = await http.runWithClient(
        () => DandanplayHttpClient().get(favorites),
        () => gateway(seen,
            accepted: 'fresh',
            renewal: () => http.Response(
                '{"success":true,"token":"fresh"}', 200)));
    expect(response.statusCode, 200);
    expect(seen, [
      'GET favorite Bearer stale',
      'POST renew Bearer stale',
      'GET renew Bearer stale',
      'GET favorite Bearer fresh',
    ]);
    expect(DandanplayService.isLoggedIn, isTrue);
    expect(DandanplayService.authorizationHeaders['Authorization'],
        'Bearer fresh');
    expect(DandanplayService.loginExpired.value, expired);
  });

  test('a refused renewal ends the login and the reason reaches the user',
      () async {
    final seen = <String>[];
    final expired = DandanplayService.loginExpired.value;
    final client = gateway(seen,
        accepted: 'fresh', renewal: () => http.Response('', 401));
    final response = await http.runWithClient(
        () => DandanplayHttpClient().get(favorites), () => client);
    expect(response.statusCode, 401);
    expect(response.body, refusedBody);
    // The renewal's own 401 asks for no further renewal.
    expect(seen.where((s) => s.contains('renew')), hasLength(2));
    expect(DandanplayService.isLoggedIn, isFalse);
    expect(DandanplayService.loginExpired.value, expired + 1);
    await expectLater(
        http.runWithClient(
            () => DandanplayHttpClient().get(favorites), () => client),
        throwsA(isA<DandanplayLoginRequired>()));
  });

  test('the server message wins over “check the network”', () async {
    final seen = <String>[];
    await expectLater(
        http.runWithClient(
            () => DandanplayService.getUserFavorites(),
            () => gateway(seen,
                accepted: 'fresh',
                renewal: () => http.Response('', 401))),
        throwsA(predicate((e) =>
            e.toString().contains('弹弹play登录已失效，请重新登录') &&
            !e.toString().contains('请检查网络连接'))));
  });

  test('a renewal that cannot reach the server keeps the login', () async {
    final seen = <String>[];
    final expired = DandanplayService.loginExpired.value;
    final response = await http.runWithClient(
        () => DandanplayHttpClient().get(favorites),
        () => gateway(seen,
            accepted: 'fresh', renewal: () => http.Response('', 502)));
    expect(response.statusCode, 401);
    expect(DandanplayService.isLoggedIn, isTrue);
    expect(DandanplayService.authorizationHeaders['Authorization'],
        'Bearer stale');
    expect(DandanplayService.loginExpired.value, expired);
  });

  test('refusals arriving together are confirmed with one renewal', () async {
    final seen = <String>[];
    final release = Completer<void>();
    final responses = await http.runWithClient(() async {
      final client = DandanplayHttpClient();
      final pending = [client.get(favorites), client.get(favorites)];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      release.complete();
      return Future.wait(pending);
    },
        () => gateway(seen,
            accepted: 'fresh',
            hold: release.future,
            renewal: () =>
                http.Response('{"success":true,"token":"fresh"}', 200)));
    expect(responses.map((r) => r.statusCode), [200, 200]);
    expect(seen.where((s) => s == 'GET renew Bearer stale'), hasLength(1));
  });
}
