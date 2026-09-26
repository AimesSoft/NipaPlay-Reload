import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/plugin_media_proxy.dart';

void main() {
  test('forwards headers, ranges, HEAD and denies unknown routes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = PluginMediaProxy();
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await proxy.close();
      await server.close(force: true);
    });
    server.listen((request) async {
      expect(request.headers.value('referer'), 'https://source.test/');
      expect(request.headers.value('user-agent'), 'TestClient');
      if (request.method == 'GET') {
        expect(request.headers.value('range'), 'bytes=2-4');
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 2-4/10');
        request.response.headers.set('accept-ranges', 'bytes');
        request.response.contentLength = 3;
        request.response.add([2, 3, 4]);
      } else {
        request.response.contentLength = 10;
      }
      await request.response.close();
    });
    final url =
        await proxy.register('http://127.0.0.1:${server.port}/video.mp4', {
      'Referer': 'https://source.test/',
      'User-Agent': 'TestClient',
    });
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('range', 'bytes=2-4');
    final response = await request.close();
    expect(response.statusCode, 206);
    expect(response.headers.value('content-range'), 'bytes 2-4/10');
    expect(await response.expand((chunk) => chunk).toList(), [2, 3, 4]);
    final head = await (await client.headUrl(Uri.parse(url))).close();
    expect(head.contentLength, 10);
    await head.drain<void>();
    final missing = await (await client
            .getUrl(Uri.parse(url).replace(path: '/unknown/media')))
        .close();
    expect(missing.statusCode, 404);
    await missing.drain<void>();
  });

  test('direct sources need no local endpoint', () async {
    final proxy = PluginMediaProxy();
    expect(await proxy.register('https://media.test/video.mp4', {}),
        'https://media.test/video.mp4');
    await proxy.close();
  });

  test('transfers media while the calling isolate is blocked', () async {
    final upstreamReady = ReceivePort();
    final upstream =
        await Isolate.spawn(_startUpstream, upstreamReady.sendPort);
    final upstreamPort = await upstreamReady.first as int;
    upstreamReady.close();
    final proxy = PluginMediaProxy();
    final readerReady = ReceivePort();
    final readerDone = ReceivePort();
    Isolate? reader;
    addTearDown(() async {
      reader?.kill(priority: Isolate.immediate);
      upstream.kill(priority: Isolate.immediate);
      readerReady.close();
      readerDone.close();
      await proxy.close();
    });
    final endpoint = await proxy.register(
      'http://127.0.0.1:$upstreamPort/media',
      {'referer': 'https://source.test/'},
    );
    reader = await Isolate.spawn(_readMedia, [
      endpoint,
      readerReady.sendPort,
      readerDone.sendPort,
    ]);
    final start = await readerReady.first as SendPort;
    start.send(null);
    sleep(const Duration(seconds: 1));
    final resumedAt = DateTime.now().microsecondsSinceEpoch;
    final result =
        await readerDone.first.timeout(const Duration(seconds: 5)) as List<int>;
    expect(result[0], 512 * 1024);
    expect(result[1], lessThan(resumedAt),
        reason: 'Media I/O must continue independently of the UI isolate.');
  });

  test('preserves the configured network route and can restart', () async {
    final route = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = PluginMediaProxy();
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      AppHttpProxy.clear();
      client.close(force: true);
      await proxy.close();
      await route.close(force: true);
    });
    route.listen((request) async {
      expect(request.uri.host, 'unreachable.invalid');
      request.response.write('routed');
      await request.response.close();
    });
    AppHttpProxy.set('http://127.0.0.1:${route.port}');
    for (var i = 0; i < 2; i++) {
      final url = await proxy.register(
        'http://unreachable.invalid/media',
        {'referer': 'https://source.test/'},
      );
      final response = await (await client.getUrl(Uri.parse(url))).close();
      expect(
          await response.fold<List<int>>([], (all, part) => all..addAll(part)),
          'routed'.codeUnits);
      await proxy.close();
    }
  });

  test('cancels abandoned transfers and serves a subsequent range', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = PluginMediaProxy();
    final client = HttpClient();
    final disconnected = Completer<void>();
    addTearDown(() async {
      client.close(force: true);
      await proxy.close();
      await upstream.close(force: true);
    });
    upstream.listen((request) async {
      try {
        if (request.headers.value('range') != null) {
          request.response.statusCode = 206;
          request.response.headers.set('content-range', 'bytes 4-6/10');
          request.response.contentLength = 3;
          request.response.add([4, 5, 6]);
        } else {
          request.response.bufferOutput = false;
          unawaited(request.response.done.then<void>(
            (_) => disconnected.complete(),
            onError: (Object _) => disconnected.complete(),
          ));
          await request.response.addStream(Stream.periodic(
            const Duration(milliseconds: 10),
            (_) => List<int>.filled(4096, 1),
          ).take(1000));
        }
        await request.response.close();
      } catch (_) {}
    });
    final endpoint = Uri.parse(await proxy.register(
      'http://127.0.0.1:${upstream.port}/media',
      {'referer': 'https://source.test/'},
    ));
    final initial = await (await client.getUrl(endpoint)).close();
    await initial.first;
    await disconnected.future.timeout(const Duration(seconds: 3));
    final seek = await client.getUrl(endpoint);
    seek.headers.set('range', 'bytes=4-6');
    final response = await seek.close();
    expect(response.statusCode, 206);
    expect(await response.expand((chunk) => chunk).toList(), [4, 5, 6]);
  });
}

Future<void> _startUpstream(SendPort ready) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  ready.send(server.port);
  await for (final request in server) {
    request.response.contentLength = 512 * 1024;
    request.response.add(List<int>.filled(512 * 1024, 1));
    await request.response.close();
  }
}

Future<void> _readMedia(List<Object> args) async {
  final start = ReceivePort();
  (args[1] as SendPort).send(start.sendPort);
  await start.first;
  start.close();
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final response =
        await (await client.getUrl(Uri.parse(args[0] as String))).close();
    final bytes =
        await response.fold<int>(0, (total, chunk) => total + chunk.length);
    (args[2] as SendPort).send([bytes, DateTime.now().microsecondsSinceEpoch]);
  } finally {
    client.close(force: true);
  }
}
