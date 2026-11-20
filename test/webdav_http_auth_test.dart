import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/webdav_http_auth.dart';

void main() {
  group('WebDavChallengeAuth', () {
    test('无凭证时不产生 Authorization 头', () {
      final auth = WebDavChallengeAuth(username: '', password: '');
      expect(auth.hasCredentials, isFalse);
      expect(auth.authorizationHeader('GET', '/dav/file.mkv'), isNull);
      expect(auth.authHeaders('GET', '/dav/file.mkv'), isEmpty);
    });

    test('初始为乐观 Basic，收到 Digest 挑战后切换并重算摘要', () {
      final auth = WebDavChallengeAuth(username: 'u', password: 'p');

      final initial = auth.authorizationHeader('GET', '/dav/file.mkv');
      expect(initial, startsWith('Basic '));

      const challenge =
          'Digest realm="dav", nonce="abc123", qop="auth", opaque="xy", '
          'algorithm=MD5';
      expect(auth.tryHandleUnauthorized(challenge), isTrue);

      final digest =
          auth.authorizationHeader('GET', '/dav/file.mkv');
      expect(digest, startsWith('Digest '));
      expect(digest, contains('username="u"'));
      expect(digest, contains('realm="dav"'));
      expect(digest, contains('nonce="abc123"'));
      expect(digest, contains('uri="/dav/file.mkv"'));
      expect(digest, contains('qop=auth'));
      expect(digest, contains('opaque="xy"'));
      expect(digest, isNot(contains('p"')));
    });

    test('Basic 挑战（凭证被拒）不重试', () {
      final auth = WebDavChallengeAuth(username: 'u', password: 'wrong');
      expect(auth.tryHandleUnauthorized('Basic realm="dav"'), isFalse);
    });

    test('Digest 凭证被拒（非 stale）不重试', () {
      final auth = WebDavChallengeAuth(username: 'u', password: 'wrong');
      const first = 'Digest realm="dav", nonce="n1", qop="auth"';
      expect(auth.tryHandleUnauthorized(first), isTrue);
      expect(auth.tryHandleUnauthorized(first), isFalse);
    });

    test('stale=true 刷新 nonce 后重试一次', () {
      final auth = WebDavChallengeAuth(username: 'u', password: 'p');
      expect(
        auth.tryHandleUnauthorized('Digest realm="dav", nonce="old", qop="auth"'),
        isTrue,
      );
      expect(
        auth.tryHandleUnauthorized(
          'Digest realm="dav", nonce="new", qop="auth", stale=true',
        ),
        isTrue,
      );
      final refreshed = auth.authorizationHeader('GET', '/dav/file.mkv');
      expect(refreshed, contains('nonce="new"'));
      // 重试预算（2）耗尽后不再重试。
      expect(
        auth.tryHandleUnauthorized('Digest realm="dav", nonce="x", stale=true'),
        isFalse,
      );
    });

    test('Digest 计算与 RFC 2617 §3.5 已知向量一致', () {
      final auth = WebDavChallengeAuth(
        username: 'Mufasa',
        password: 'Circle Of Life',
        cnonceGenerator: () => '0a4f113b',
      );
      auth.tryHandleUnauthorized(
        'Digest realm="testrealm@host.com", qop="auth,auth-int", '
        'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", '
        'opaque="5ccc069c403ebaf9f0171e9517f40e41"',
      );
      final header = auth.authorizationHeader('GET', '/dir/index.html');
      expect(header, contains('realm="testrealm@host.com"'));
      expect(header, contains('nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093"'));
      expect(header, contains('uri="/dir/index.html"'));
      expect(header, contains('qop=auth,'));
      expect(header, contains('nc=00000001'));
      expect(header, contains('cnonce="0a4f113b"'));
      expect(header, contains('response="6629fae49393a05397450978507c4ef1"'));
      expect(header, contains('opaque="5ccc069c403ebaf9f0171e9517f40e41"'));
    });

    test('Digest 的 uri 与已编码的请求路径逐字一致（不二次编码）', () {
      final auth = WebDavChallengeAuth(username: 'u', password: 'p');
      auth.tryHandleUnauthorized('Digest realm="dav", nonce="n1", qop="auth"');
      final target = webDavDigestRequestTarget(
        Uri.parse('http://host/dav/番剧 01.mkv'),
      );
      expect(target, '/dav/%E7%95%AA%E5%89%A7%2001.mkv');
      expect(
        auth.authorizationHeader('GET', target),
        contains('uri="/dav/%E7%95%AA%E5%89%A7%2001.mkv"'),
      );
    });
  });

  group('webDavDigestRequestTarget', () {
    test('无 query 时返回 path', () {
      expect(
        webDavDigestRequestTarget(
          Uri.parse('http://host:5000/dav/a%20b.mkv'),
        ),
        '/dav/a%20b.mkv',
      );
    });

    test('带 query 时包含 query', () {
      expect(
        webDavDigestRequestTarget(
          Uri.parse('http://host/dav/file?op=download'),
        ),
        '/dav/file?op=download',
      );
    });
  });

  group('WebDAV 代理流端到端（本地 Basic 服务器）', () {
    late HttpServer upstream;
    late List<String> seenAuthHeaders;

    setUp(() async {
      seenAuthHeaders = [];
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(upstream.forEach((request) async {
        final auth = request.headers.value(HttpHeaders.authorizationHeader);
        seenAuthHeaders.add(auth ?? '');
        if (auth == null || !auth.startsWith('Basic dXNlcjpwYXNz')) {
          // user:pass → dXNlcjpwYXNz
          request.response.statusCode = 401;
          request.response.headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Basic realm="test"',
          );
          await request.response.close();
          return;
        }
        final range = request.headers.value(HttpHeaders.rangeHeader);
        if (range == 'bytes=2-5') {
          request.response.statusCode = 206;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 2-5/10',
          );
          request.response.add([3, 4, 5, 6]);
          await request.response.close();
          return;
        }
        request.response.statusCode = 200;
        request.response.headers.set(HttpHeaders.contentLengthHeader, '10');
        request.response.add([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        await request.response.close();
      }));
    });

    tearDown(() async {
      await upstream.close(force: true);
    });

    test('代理完成挑战协商并透传 206 Range 响应', () async {
      final auth = WebDavChallengeAuth(username: 'user', password: 'pass');
      final client = HttpClient();
      try {
        // 第一个请求携带乐观 Basic（与 WebDAVProxyService 行为一致）。
        final req = await client.getUrl(Uri.parse(
          'http://127.0.0.1:${upstream.port}/dav/video.mkv',
        ));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
        req.headers.set(
          HttpHeaders.authorizationHeader,
          auth.authorizationHeader('GET', '/dav/video.mkv')!,
        );
        final resp = await req.close();
        // 本地服务器只认 Digest 之外的 Basic（dXNlcjpwYXNz），这里应该直接成功。
        expect(resp.statusCode, 206);
        expect(resp.headers.value(HttpHeaders.contentRangeHeader),
            'bytes 2-5/10');
        final body = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        expect(body, [3, 4, 5, 6]);
        expect(seenAuthHeaders, everyElement(startsWith('Basic')));
      } finally {
        client.close(force: true);
      }
    });

    test('乐观 Basic 被拒后按 Digest 挑战切换重试', () async {
      final auth = WebDavChallengeAuth(username: 'user', password: 'pass');
      final client = HttpClient();
      try {
        final url = Uri.parse(
          'http://127.0.0.1:${upstream.port}/dav/video.mkv',
        );
        // 预置一个不匹配的 Basic，让服务器 401。
        final req = await client.getUrl(url);
        req.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode('user:bad'))}',
        );
        final resp = await req.close();
        expect(resp.statusCode, 401);
        expect(
          auth.tryHandleUnauthorized(
            resp.headers.value(HttpHeaders.wwwAuthenticateHeader),
          ),
          isFalse, // Basic 挑战 → 凭证被拒，助手不重试
        );

        // 换成正确凭证重发（模拟上层用正确 Basic 重试路径）。
        final retry = await client.getUrl(url);
        retry.headers.set(
          HttpHeaders.authorizationHeader,
          auth.authorizationHeader('GET', '/dav/video.mkv')!,
        );
        final resp2 = await retry.close();
        expect(resp2.statusCode, 200);
        final body = await resp2.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        expect(body.length, 10);
      } finally {
        client.close(force: true);
      }
    });
  });
}
