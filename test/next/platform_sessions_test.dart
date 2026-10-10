import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/host.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/danmaku/sources.dart';
import 'package:nipaplay/next/network/dandanplay_gateway.dart';
import 'package:nipaplay/next/sessions/capability.dart';
import 'package:nipaplay/next/sessions/page.dart';
import 'package:nipaplay/next/sessions/platform_session.dart';
import 'package:nipaplay/next/sessions/youku_bridge.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';

import 'danmaku_test_support.dart';

// These values are deliberately synthetic and never sent to a network service.
const _account = 'synthetic-account-only';
const _token = 'synthetic-signing-only_4102444800000';
final _clock = DateTime.utc(2026, 10, 11);

http.Response _jsonResponse(Object data,
        {Map<String, String> headers = const {}}) =>
    http.Response.bytes(jsonBytes(data), 200, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers,
    });

final class _Vault implements CredentialVault {
  final data = <CredentialRef, String>{};
  bool failWrite = false, failDelete = false;
  @override
  Future<String?> read(CredentialRef ref) async => data[ref];
  @override
  Future<void> write(CredentialRef ref, String value) async {
    if (failWrite) throw StateError('synthetic-vault-failure');
    data[ref] = value;
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    if (failDelete) throw StateError('synthetic-vault-failure');
    data.remove(ref);
  }
}

final class _Login implements PlatformLoginPort {
  @override
  bool supported = true;
  final opened = <String, String>{};
  @override
  Future<void> open(String platform, String generation) async =>
      opened[platform] = generation;
  @override
  Future<void> close(String platform) async => opened.remove(platform);
}

final class _AbortClient extends http.BaseClient {
  final entered = Completer<void>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    entered.complete();
    await (request as http.Abortable).abortTrigger;
    throw http.RequestAbortedException();
  }
}

void main() {
  late _Vault vault;
  late _Login login;
  late PlatformSessions sessions;
  setUp(() {
    vault = _Vault();
    login = _Login();
    sessions = PlatformSessions(vault, login, now: () => _clock);
  });
  Future<void> signIn(String platform, {List<SessionCookie>? cookies}) async {
    await sessions.openLogin(platform);
    await sessions.capture(
        platform,
        login.opened[platform]!,
        cookies ??
            [
              SessionCookie(
                  platform == 'youku' ? 'P_sck' : 'SESSDATA',
                  _account,
                  platform == 'youku' ? '.youku.com' : '.bilibili.com'),
              if (platform == 'youku')
                const SessionCookie('_m_h5_tk', _token, '.youku.com'),
            ]);
  }

  DanmakuAccess access(String platform) =>
      DanmakuAccess(PlatformSessions.accessReference(platform));
  Matcher sourceStatus(SourceStatus expected) =>
      isA<SourceFailure>().having((e) => e.status, 'source status', expected);
  Future<JsonMap> call(Harness api, String id, JsonMap input) async {
    final result = await api.invokeJson(id, input, Invocation(origin: 'mcp'));
    expect(result, isA<Completed>(), reason: '${result.toEnvelope()}');
    return (result as Completed).value.toJson();
  }

  test('opening login returns immediately without entering or exposing secrets',
      () async {
    final api = Harness([PlatformSessionCapability(sessions)]);
    final opened =
        await call(api, 'ui.open_platform_login', {'platform': 'youku'});
    expect(opened['opened'], true);
    expect(sessions.available('youku'), false);
    expect(vault.data, isEmpty);
    expect(login.opened.keys, ['youku']);
    expect(
        api.catalog.map((s) => s.id),
        unorderedEquals(
            ['sessions.status', 'sessions.logout', 'ui.open_platform_login']));
    final result = await api.invokeJson(
        'ui.open_platform_login',
        {'platform': 'youku', 'password': 'synthetic'},
        Invocation(origin: 'mcp'));
    expect(result, isA<Failed>());
  });

  test('sessions survive restart via vault and status only exports references',
      () async {
    await signIn('youku');
    await signIn('bilibili');
    final restored = PlatformSessions(vault, _Login(), now: () => _clock);
    await restored.restore();
    final result = await call(
        Harness([PlatformSessionCapability(restored)]), 'sessions.status', {});
    final json = jsonEncode(result);
    expect(json, isNot(contains(_account)));
    expect(json, isNot(contains(_token)));
    expect((result['sessions'] as List).map((s) => s['status']),
        ['sessionPresent', 'sessionPresent']);
    expect(restored.status('youku')['accessRef'],
        PlatformSessions.accessReference('youku'));
  });

  test(
      'platform logout is idempotent, isolates the other platform and revokes late capture',
      () async {
    await signIn('youku');
    await signIn('bilibili');
    final generation = login.opened['youku']!;
    final api = Harness([PlatformSessionCapability(sessions)]);
    await call(api, 'sessions.logout', {
      'platforms': ['youku']
    });
    await call(api, 'sessions.logout', {
      'platforms': ['youku']
    });
    expect(sessions.status('youku')['status'], 'loggedOut');
    expect(sessions.available('bilibili'), true);
    expect(vault.data.containsKey(PlatformSessions.reference('youku')), false);
    await expectLater(
        sessions.capture('youku', generation, [
          const SessionCookie('P_sck', _account, '.youku.com'),
        ]),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', FailureCode.conflict)));
  });

  test('expired cookies and anonymous signing tokens do not imply logged in',
      () async {
    await sessions.openLogin('youku');
    await expectLater(
        sessions.capture('youku', login.opened['youku']!, [
          const SessionCookie('_m_h5_tk', _token, '.youku.com'),
        ]),
        throwsA(isA<Failure>()));
    await signIn('youku', cookies: [
      SessionCookie('P_sck', _account, '.youku.com',
          expiresAt: _clock.add(const Duration(seconds: 1))),
    ]);
    final expired = PlatformSessions(vault, _Login(),
        now: () => _clock.add(const Duration(seconds: 2)));
    await expired.restore();
    expect(expired.status('youku')['status'], 'expiredOrRejected');
  });

  test(
      'vault write and delete failures are visible and never claim saved/logout success',
      () async {
    vault.failWrite = true;
    await expectLater(signIn('youku'), throwsA(isA<Failure>()));
    expect(sessions.available('youku'), false);
    vault.failWrite = false;
    await signIn('youku');
    vault.failDelete = true;
    final result =
        await Harness([PlatformSessionCapability(sessions)]).invokeJson(
            'sessions.logout',
            {
              'platforms': ['youku']
            },
            Invocation(origin: 'mcp'));
    expect(result, isA<Failed>());
    expect(sessions.available('youku'), false);
  });

  test('unsupported platforms expose status and refuse to open a login window',
      () async {
    login.supported = false;
    await sessions.restore();
    expect(sessions.status('youku')['status'], 'unsupported');
    await expectLater(sessions.openLogin('youku'), throwsA(isA<Failure>()));
    expect(login.opened, isEmpty);
    expect(vault.data, isEmpty);
  });

  test(
      'corrupt saved session reports a safe error and preserves the other platform',
      () async {
    await signIn('bilibili');
    vault.data[PlatformSessions.reference('youku')] =
        'synthetic-invalid-record';
    final restored = PlatformSessions(vault, _Login(), now: () => _clock);
    await restored.restore();
    expect(restored.status('youku')['status'], 'unavailable');
    expect(jsonEncode(restored.status('youku')),
        isNot(contains('synthetic-invalid-record')));
    expect(restored.available('bilibili'), true);
    await restored.logout('youku');
    expect(restored.status('youku')['status'], 'loggedOut');
  });

  test('cookie capture excludes other domains and rejects header injection',
      () async {
    await signIn('youku', cookies: [
      const SessionCookie('P_sck', _account, '.youku.com'),
      const SessionCookie('SESSDATA', 'synthetic-other-only', '.bilibili.com'),
    ]);
    expect(vault.data.values.single, isNot(contains('synthetic-other-only')));
    await sessions.openLogin('youku');
    await expectLater(
        sessions.capture('youku', login.opened['youku']!, [
          const SessionCookie('P_sck', 'synthetic\r\ninjected', '.youku.com'),
        ]),
        throwsA(isA<Failure>()));
    expect(sessions.cookieHeader('youku', Uri.https('evil.example', '/')),
        isEmpty);
    const hostOnly =
        SessionCookie('test', 'synthetic', 'youku.com', path: '/foo');
    expect(hostOnly.matches(Uri.https('acs.youku.com', '/foo'), _clock), false);
    expect(hostOnly.matches(Uri.https('youku.com', '/foobar'), _clock), false);
  });

  test(
      'capture keeps required session cookies and public IDs do not corrupt source responses',
      () async {
    await signIn('bilibili', cookies: [
      const SessionCookie('SESSDATA', _account, '.bilibili.com'),
      const SessionCookie('DedeUserID', '101', '.bilibili.com'),
      const SessionCookie('appearance_preference',
          'synthetic-unneeded-preference', '.bilibili.com'),
    ]);
    expect(vault.data.values.single,
        isNot(contains('synthetic-unneeded-preference')));
    final host = HttpDanmakuHost(
        publicClient: MockClient((request) async {
          expect(request.headers['cookie'], contains('DedeUserID=101'));
          return _jsonResponse({
            'code': 0,
            'data': {
              'title': '101',
              'pages': [
                {'cid': 101, 'part': '101', 'duration': 60, 'page': 1}
              ]
            },
            'SESSDATA': 'synthetic-server-session-material'
          });
        }),
        dandanplay: DandanplayGateway(client: DandanplayHttpClient()),
        sessions: sessions,
        interval: Duration.zero);
    final bytes = await host.request(
        'bilibili.view', {'bvid': 'BVfixture'}, null, DanmakuCancellation());
    expect(utf8.decode(bytes),
        isNot(contains('synthetic-server-session-material')));
    final videos = await BilibiliDanmakuSource(host)
        .resolve('BVfixture', DanmakuCancellation());
    expect(videos.single.videoId, '101');
    expect(videos.single.title, '101 · 101');
  });

  test('Youku signs and sends only inside host and projects a safe response',
      () async {
    await signIn('youku');
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'POST');
      expect(request.url.host, 'acs.youku.com');
      expect(request.headers['cookie'], contains('P_sck=$_account'));
      final data = Uri.splitQueryString(request.body)['data']!;
      final body = jsonDecode(data) as Map;
      expect(body['mat'], requests == 1 ? 1 : 0);
      expect(body['vid'], 'Xfixture');
      final original =
          jsonDecode(utf8.decode(base64Decode(body['msg'] as String))) as Map;
      expect(original.containsKey('sign'), false);
      expect(
          body['sign'],
          md5
              .convert(
                  utf8.encode('${body['msg']}MkmC9SoIw6xCkSKHhJ7b5D2r51kBiREr'))
              .toString());
      expect(
          request.url.queryParameters['sign'],
          md5
              .convert(utf8.encode(
                  'synthetic-signing-only&${_clock.millisecondsSinceEpoch}&24679788&$data'))
              .toString());
      final payload = youkuPayload([
        {...youkuEntry(), 'cookie': _account},
      ])
        ..['secret'] = _account;
      return _jsonResponse(payload);
    });
    final bridge =
        VaultYoukuSessionBridge(sessions, client, guid: () => 'synthetic-guid');
    final bytes = await bridge.minute(
        'Xfixture', 1, access('youku'), DanmakuCancellation());
    expect(utf8.decode(bytes), isNot(contains(_account)));
    expect(utf8.decode(bytes), isNot(contains('cookie')));
    expect(requests, 1);
    final host = HttpDanmakuHost(
        publicClient: client,
        dandanplay: DandanplayGateway(client: DandanplayHttpClient()),
        youkuSession: bridge,
        interval: Duration.zero);
    final source = YoukuDanmakuSource(
        ScopedDanmakuHost(host, YoukuDanmakuSource(host).describe));
    final result = await source.fetchChunk(
        youkuVideo,
        const DanmakuChunk(0, 0, 60000),
        access('youku'),
        DanmakuCancellation());
    expect(result.entries.single.text, '优酷合成弹幕内容');
  });

  test(
      'wrong platform references and profiles are rejected before any network request',
      () async {
    await signIn('youku');
    var sent = false;
    final bridge = VaultYoukuSessionBridge(sessions, MockClient((_) async {
      sent = true;
      return http.Response('{}', 200);
    }));
    await expectLater(
        bridge.minute('Xfixture', 0, access('bilibili'), DanmakuCancellation()),
        throwsA(isA<Failure>()));
    expect(
        () => sessions.authorize('youku', 'bilibili.segment',
            PlatformSessions.accessReference('youku')),
        throwsA(isA<Failure>()));
    expect(sent, false);
  });

  test('normal MTOP token renewal persists scoped cookies and retries once',
      () async {
    await signIn('youku',
        cookies: [const SessionCookie('P_sck', _account, '.youku.com')]);
    var calls = 0;
    final bridge =
        VaultYoukuSessionBridge(sessions, MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
            jsonEncode({
              'ret': ['FAIL_SYS_TOKEN_EMPTY::synthetic']
            }),
            200,
            headers: {
              'set-cookie':
                  '_m_h5_tk=synthetic-renewed_4102444800000; Domain=youku.com; Path=/; Secure; HttpOnly'
            });
      }
      expect(request.headers['cookie'],
          contains('synthetic-renewed_4102444800000'));
      return _jsonResponse(youkuPayload([]));
    }));
    await bridge.minute('Xfixture', 0, access('youku'), DanmakuCancellation());
    expect(calls, 2);
    expect(
        vault.data.values.single, contains('synthetic-renewed_4102444800000'));
  });

  test('Youku auth expiry reports the platform and session state', () async {
    await signIn('youku');
    var calls = 0;
    final bridge = VaultYoukuSessionBridge(sessions, MockClient((_) async {
      calls++;
      return _jsonResponse({
        'ret': ['FAIL_SYS_SESSION_EXPIRED::synthetic']
      });
    }));
    await expectLater(
        bridge.minute('Xfixture', 0, access('youku'), DanmakuCancellation()),
        throwsA(sourceStatus(SourceStatus.authenticationRequired)));
    expect(calls, 1);
    expect(sessions.status('youku')['status'], 'expiredOrRejected');
    expect(
        SourceFailure(SourceStatus.authenticationRequired,
                diagnostics: sessions.status('youku')['loginHint'] as String)
            .message,
        contains('youku 需要登录态；当前状态：expiredOrRejected'));
  });

  test('Youku rejects redirects, malformed replies and oversized responses',
      () async {
    await signIn('youku');
    for (final response in [
      http.Response('', 302),
      http.Response('not-json', 200),
      http.Response('x' * 8388609, 200)
    ]) {
      final bridge =
          VaultYoukuSessionBridge(sessions, MockClient((_) async => response));
      await expectLater(
          bridge.minute('Xfixture', 0, access('youku'), DanmakuCancellation()),
          throwsA(sourceStatus(response.statusCode == 302
              ? SourceStatus.accessDenied
              : SourceStatus.schemaChanged)));
    }
  });

  test(
      'Youku aborts requests on cancellation and times out without secret diagnostics',
      () async {
    await signIn('youku');
    final client = _AbortClient();
    final bridge = VaultYoukuSessionBridge(sessions, client);
    final cancel = DanmakuCancellation();
    final future = bridge.minute('Xfixture', 0, access('youku'), cancel);
    final check =
        expectLater(future, throwsA(sourceStatus(SourceStatus.cancelled)));
    await client.entered.future;
    cancel.cancel();
    await check;
    final timeout = VaultYoukuSessionBridge(sessions, _AbortClient(),
        timeout: const Duration(milliseconds: 5));
    await expectLater(
        timeout.minute('Xfixture', 0, access('youku'), DanmakuCancellation()),
        throwsA(sourceStatus(SourceStatus.transportFailed)));
  });

  test(
      'logout prevents late Youku response from restoring cookies or reaching source',
      () async {
    await signIn('youku');
    final entered = Completer<void>(), release = Completer<void>();
    final bridge = VaultYoukuSessionBridge(sessions, MockClient((_) async {
      entered.complete();
      await release.future;
      return _jsonResponse(youkuPayload([]), headers: {
        'set-cookie':
            '_m_h5_tk=synthetic-late_4102444800000; Domain=.youku.com; Path=/',
      });
    }));
    final future =
        bridge.minute('Xfixture', 0, access('youku'), DanmakuCancellation());
    final check = expectLater(
        future, throwsA(sourceStatus(SourceStatus.authenticationRequired)));
    await entered.future;
    await sessions.logout('youku');
    release.complete();
    await check;
    expect(vault.data, isEmpty);
  });

  test('Bilibili public profiles use host session cookies only when logged in',
      () async {
    final headers = <String?>[];
    final client = MockClient((request) async {
      headers.add(request.headers['cookie']);
      return _jsonResponse({
        'code': 0,
        'data': {
          'title': '合成',
          'pages': [
            {'cid': 101, 'part': '第一集', 'duration': 60, 'page': 1}
          ]
        }
      });
    });
    final host = HttpDanmakuHost(
        publicClient: client,
        dandanplay: DandanplayGateway(client: DandanplayHttpClient()),
        sessions: sessions,
        interval: Duration.zero);
    final source = BilibiliDanmakuSource(
        ScopedDanmakuHost(host, BilibiliDanmakuSource(host).describe));
    await source.resolve('BVfixture', DanmakuCancellation());
    await signIn('bilibili');
    await source.resolve('BVfixture', DanmakuCancellation());
    await sessions.logout('bilibili');
    await source.resolve('BVfixture', DanmakuCancellation());
    expect(headers, [null, 'SESSDATA=$_account', null]);
    await expectLater(
        host.request('bilibili.view', {'bvid': 'BVfixture'}, access('youku'),
            DanmakuCancellation()),
        throwsA(isA<Failure>()));
    expect(headers.length, 3);
  });

  test(
      'Bilibili login-only failure marks rejected state without leaking platform response',
      () async {
    await signIn('bilibili');
    final host = HttpDanmakuHost(
        publicClient: MockClient((_) async => http.Response(
            jsonEncode({'code': -101, 'message': _account}), 200)),
        dandanplay: DandanplayGateway(client: DandanplayHttpClient()),
        sessions: sessions,
        interval: Duration.zero);
    await expectLater(
        host.request('bilibili.view', {'bvid': 'BVfixture'}, access('bilibili'),
            DanmakuCancellation()),
        throwsA(sourceStatus(SourceStatus.authenticationRequired)));
    expect(sessions.status('bilibili')['status'], 'expiredOrRejected');
  });

  test('anonymous Bilibili login-only endpoint reports the session state',
      () async {
    final host = HttpDanmakuHost(
        publicClient: MockClient((_) async => _jsonResponse({'code': -101})),
        dandanplay: DandanplayGateway(client: DandanplayHttpClient()),
        sessions: sessions,
        interval: Duration.zero);
    await expectLater(
        BilibiliDanmakuSource(host).resolve('BVfixture', DanmakuCancellation()),
        throwsA(isA<SourceFailure>()
            .having(
                (e) => e.status, 'status', SourceStatus.authenticationRequired)
            .having((e) => e.message, 'login hint',
                contains('bilibili 需要登录态；当前状态：loggedOut'))));
    final scoped = ScopedDanmakuHost(
        host,
        const DanmakuDescriptor(
          id: 'other-source',
          platform: 'bilibili',
          hosts: ['api.bilibili.com'],
          profiles: ['bilibili.view'],
          access: 'anonymous',
          segmentMs: 0,
        ));
    await expectLater(
        scoped.request('bilibili.view', {'bvid': 'BVfixture'}, null,
            DanmakuCancellation()),
        throwsA(isA<Failure>()));
  });

  testWidgets('platform session page uses the same Actions to open and logout',
      (tester) async {
    sessions = PlatformSessions(vault, login, now: () => _clock);
    await tester.pumpWidget(
        MaterialApp(home: PlatformSessionsPage(sessions: sessions)));
    await tester.tap(find.text('打开登录页').first);
    await tester.pumpAndSettle();
    expect(login.opened.keys, ['youku']);
    final saved = signIn('youku');
    await tester.pump();
    await saved;
    await tester.pumpAndSettle();
    expect(find.text('会话已保存（本地检查；有效性在请求时确认）'), findsOneWidget);
    await tester.tap(find.text('注销').first);
    await tester.pumpAndSettle();
    expect(vault.data, isEmpty);
  });
}
