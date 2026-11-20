import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/webdav_proxy_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/webdav_http_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 用一个像真实服务器一样校验 Digest 摘要的本地 WebDAV 服务器，验证字幕下载
// （webDavAuthenticatedGet）与媒体代理（WebDAVProxyService）的实际请求链路。

class _SeenRequest {
  _SeenRequest(this.method, this.target, this.authorization);
  final String method;
  final String target;
  final String? authorization;
}

class _DavServer {
  _DavServer({
    this.requireDigest = true,
    Map<String, List<int>>? files,
    Map<String, String>? redirects,
  })  : files = files ?? {},
        redirects = redirects ?? {};

  static const realm = 'nipaplay-test';
  static const nonce = 'dcd98b7102dd2f0e8b11d0f600bfb0c093';

  final bool requireDigest;
  String username = 'user';
  String password = 'pass';
  final Map<String, List<int>> files;
  final Map<String, String> redirects;
  final List<_SeenRequest> requests = [];
  late final HttpServer _server;

  int get port => _server.port;
  String get origin => 'http://127.0.0.1:$port';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final target = request.uri.toString();
    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    requests.add(_SeenRequest(request.method, target, authorization));
    final response = request.response;

    if (request.method == 'OPTIONS') {
      response.headers.set('DAV', '1, 2');
      await response.close();
      return;
    }
    // 只对取文件（GET/HEAD）强制 Digest：添加连接时的目录校验走 webdav_client
    // 自己的认证实现，不在本测试范围内。
    final fetchesFile = request.method == 'GET' || request.method == 'HEAD';
    if (requireDigest &&
        fetchesFile &&
        !_digestValid(request.method, target, authorization)) {
      response.statusCode = HttpStatus.unauthorized;
      response.headers.set(
        HttpHeaders.wwwAuthenticateHeader,
        'Digest realm="$realm", nonce="$nonce", qop="auth", '
        'opaque="op4que", algorithm=MD5',
      );
      await response.close();
      return;
    }

    final path = Uri.decodeComponent(request.uri.path);
    final redirect = redirects[path];
    if (redirect != null) {
      response.statusCode = HttpStatus.found;
      response.headers.set(HttpHeaders.locationHeader, redirect);
      await response.close();
      return;
    }

    if (request.method == 'PROPFIND') {
      response.statusCode = 207;
      response.headers.contentType =
          ContentType('application', 'xml', charset: 'utf-8');
      response.write('<?xml version="1.0" encoding="utf-8"?>'
          '<D:multistatus xmlns:D="DAV:"><D:response>'
          '<D:href>${request.uri.path}</D:href><D:propstat><D:prop>'
          '<D:resourcetype><D:collection/></D:resourcetype>'
          '</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>'
          '</D:response></D:multistatus>');
      await response.close();
      return;
    }

    final body = files[path];
    if (body == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.headers.contentType = ContentType('video', 'x-matroska');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final range = RegExp(r'^bytes=(\d+)-(\d+)$')
        .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    var bytes = body;
    if (range != null) {
      final start = int.parse(range.group(1)!);
      final end = int.parse(range.group(2)!);
      bytes = body.sublist(start, end + 1);
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${body.length}',
      );
    }
    response.contentLength = bytes.length;
    if (request.method != 'HEAD') response.add(bytes);
    await response.close();
  }

  bool _digestValid(String method, String target, String? header) {
    if (header == null || !header.startsWith('Digest ')) return false;
    final params = <String, String>{
      for (final m in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))')
          .allMatches(header.substring(7)))
        m.group(1)!: m.group(2) ?? m.group(3)!,
    };
    if (params['username'] != username ||
        params['realm'] != realm ||
        params['nonce'] != nonce ||
        params['opaque'] != 'op4que' ||
        params['uri'] != target) {
      return false;
    }
    String h(String value) => md5.convert(utf8.encode(value)).toString();
    final ha1 = h('$username:$realm:$password');
    final ha2 = h('$method:$target');
    final expected = h(
      '$ha1:$nonce:${params['nc']}:${params['cnonce']}:${params['qop']}:$ha2',
    );
    return params['response'] == expected;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 测试绑定默认让所有 HttpClient 请求返回 400；这里要打真实的本地服务器。
  HttpOverrides.global = null;

  group('webDavAuthenticatedGet（字幕下载）', () {
    test('Digest-only 服务器：401 挑战后用 Digest 下载成功（中文文件名）', () async {
      final server = _DavServer(files: {
        '/dav/番剧 01.ass': utf8.encode('[Script Info]'),
      });
      await server.start();
      addTearDown(server.stop);

      final response = await webDavAuthenticatedGet(
        Dio(),
        Uri.parse('${server.origin}/dav/番剧 01.ass'),
        WebDavChallengeAuth(username: 'user', password: 'pass'),
      );

      expect(response.statusCode, 200);
      expect(utf8.decode(response.data!), '[Script Info]');
      expect(server.requests.first.authorization, startsWith('Basic '));
      expect(server.requests.last.authorization, startsWith('Digest '));
    });

    test('同源重定向后 Digest 的 uri 按新路径计算', () async {
      final server = _DavServer(
        files: {'/dav/new.ass': utf8.encode('moved')},
        redirects: {'/dav/old.ass': '/dav/new.ass'},
      );
      await server.start();
      addTearDown(server.stop);

      final response = await webDavAuthenticatedGet(
        Dio(),
        Uri.parse('${server.origin}/dav/old.ass'),
        WebDavChallengeAuth(username: 'user', password: 'pass'),
      );

      expect(response.statusCode, 200);
      expect(utf8.decode(response.data!), 'moved');
    });

    test('跨源重定向不把认证头带给目标主机', () async {
      final target = _DavServer(
        requireDigest: false,
        files: {'/files/sub.ass': utf8.encode('elsewhere')},
      );
      await target.start();
      addTearDown(target.stop);
      final source = _DavServer(
        requireDigest: false,
        redirects: {'/dav/sub.ass': '${target.origin}/files/sub.ass'},
      );
      await source.start();
      addTearDown(source.stop);

      final response = await webDavAuthenticatedGet(
        Dio(BaseOptions(headers: {'user-agent': 'NipaPlay'})),
        Uri.parse('${source.origin}/dav/sub.ass'),
        WebDavChallengeAuth(username: 'user', password: 'pass'),
      );

      expect(response.statusCode, 200);
      expect(utf8.decode(response.data!), 'elsewhere');
      expect(source.requests.single.authorization, startsWith('Basic '));
      expect(target.requests.single.authorization, isNull);
    });

    test('凭证被拒时返回 401 而不是抛错', () async {
      final server = _DavServer(files: {'/dav/a.ass': utf8.encode('x')});
      await server.start();
      addTearDown(server.stop);

      final response = await webDavAuthenticatedGet(
        Dio(),
        Uri.parse('${server.origin}/dav/a.ass'),
        WebDavChallengeAuth(username: 'user', password: 'wrong'),
      );

      expect(response.statusCode, 401);
    });
  });

  group('WebDAVProxyService 端到端', () {
    final media = List<int>.generate(100, (i) => i);
    late _DavServer server;
    late WebDAVConnection connection;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await WebDAVService.instance.initialize();
      server = _DavServer(files: {'/dav/Show 01.mkv': media});
      await server.start();
      final saved = await WebDAVService.instance.upsertConnection(
        WebDAVConnection(
          name: 'digest-proxy',
          url: '${server.origin}/dav/',
          username: 'user',
          password: 'pass',
        ),
      );
      expect(saved, isTrue, reason: '连接校验应通过 Digest 协商');
      connection = WebDAVService.instance.connections
          .firstWhere((c) => c.name == 'digest-proxy');
    });

    tearDownAll(() async {
      await WebDAVProxyService.instance.stop();
      await server.stop();
    });

    Future<String> proxyUrl() async {
      final url = await MediaSourceUtils.resolveWebDavPathToUrlInitialized(
        MediaSourceUtils.buildWebDavPath(connection.id, '/dav/Show 01.mkv'),
      );
      expect(url, startsWith('http://127.0.0.1:${WebDAVProxyService.instance.port}/webdav/stream'));
      return url!;
    }

    test('Range 请求经 Digest 协商后透传为 206', () async {
      server.requests.clear();
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(Uri.parse(await proxyUrl()));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');
      final response = await request.close();
      final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));

      expect(response.statusCode, 206);
      expect(response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 10-19/100');
      expect(body, media.sublist(10, 20));
      expect(server.requests.last.method, 'GET');
      expect(server.requests.last.authorization, startsWith('Digest '));
    });

    test('HEAD 请求以 HEAD 方法发往上游并通过 Digest 校验', () async {
      server.requests.clear();
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.headUrl(Uri.parse(await proxyUrl()));
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, 200);
      expect(response.headers.value(HttpHeaders.contentLengthHeader), '100');
      expect(server.requests.map((r) => r.method), everyElement('HEAD'));
    });

    test('上游拒绝凭证时代理返回 401', () async {
      server.password = 'changed';
      addTearDown(() => server.password = 'pass');
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(Uri.parse(await proxyUrl()));
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, 401);
    });

    test('匿名连接不走代理，仍返回直链', () async {
      final anonymous = _DavServer(requireDigest: false);
      await anonymous.start();
      addTearDown(anonymous.stop);
      final saved = await WebDAVService.instance.upsertConnection(
        WebDAVConnection(
          name: 'anonymous-dav',
          url: '${anonymous.origin}/dav/',
          username: '',
          password: '',
        ),
      );
      expect(saved, isTrue);
      final anon = WebDAVService.instance.connections
          .firstWhere((c) => c.name == 'anonymous-dav');

      final url = await MediaSourceUtils.resolveWebDavPathToUrlInitialized(
        MediaSourceUtils.buildWebDavPath(anon.id, '/dav/Show 01.mkv'),
      );

      expect(WebDAVProxyService.instance.isRunning, isTrue);
      expect(url, startsWith('${anonymous.origin}/dav/'));
    });
  });
}
