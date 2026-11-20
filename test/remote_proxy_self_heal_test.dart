import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/remote_proxy_diagnostics.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/webdav_proxy_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final webdav = WebDAVProxyService.instance;
  final smb = SMBProxyService.instance;
  for (final (name, initialize, stop, closeListener, getPort, isRunning) in [
    (
      'webdav',
      webdav.initialize,
      webdav.stop,
      webdav.closeListenerForTesting,
      () => webdav.port,
      () => webdav.isRunning
    ),
    (
      'smb',
      smb.initialize,
      smb.stop,
      smb.closeListenerForTesting,
      () => smb.port,
      () => smb.isRunning
    ),
  ]) {
    Uri endpoint(int port, [String route = 'health']) =>
        Uri.parse('http://127.0.0.1:$port/$name/$route');

    void proxyTest(String description, Future<void> Function() run) {
      test(
          '$name $description',
          () => HttpOverrides.runWithHttpOverrides(
                () async {
                  SharedPreferences.setMockInitialValues(
                      {'${name}_proxy_port': 0});
                  addTearDown(stop);
                  await run();
                },
                _RealHttp(),
              ));
    }

    proxyTest('recovers the old endpoint after its listener is reclaimed',
        () async {
      await initialize();
      final port = getPort();
      final health = endpoint(port);
      final (status, marker) = await _request(health);
      expect(status, 200);

      await closeListener();
      expect(isRunning(), isTrue);
      expect(getPort(), port);
      await expectLater(_request(health), throwsA(isA<SocketException>()));

      await Future.wait(List.generate(4, (_) => initialize()));
      expect(getPort(), port);
      final (newStatus, newMarker) = await _request(health);
      expect(newStatus, 200);
      expect(newMarker, isNotNull);
      expect(newMarker, isNot(marker));
      expect((await _request(endpoint(port, 'stream'))).$1, 400);
    });

    proxyTest('retains its healthy listener on reuse and resume', () async {
      await initialize();
      final port = getPort();
      final before = await _request(endpoint(port));
      expect(before.$2, isNotNull);
      await initialize();
      await RemoteProxyDiagnostics.lifecycle('resumed');
      expect(getPort(), port);
      expect(await _request(endpoint(port)), before);
    });

    proxyTest('heals on resume without a new initialize call', () async {
      await initialize();
      final port = getPort();
      await RemoteProxyDiagnostics.lifecycle('paused');
      await closeListener();
      await RemoteProxyDiagnostics.lifecycle('resumed');
      expect(getPort(), port);
      expect((await _request(endpoint(port))).$1, 200);
    });

    proxyTest('does not trust a foreign 200 health response', () async {
      await initialize();
      final oldPort = getPort();
      await closeListener();
      final occupant =
          await HttpServer.bind(InternetAddress.loopbackIPv4, oldPort);
      addTearDown(() => occupant.close(force: true));
      occupant.listen((request) {
        request.response.headers
            .set(RemoteProxyDiagnostics.healthHeader, 'foreign');
        request.response.close();
      });
      expect(await _request(endpoint(oldPort)), (200, 'foreign'));

      await initialize();
      expect(getPort(), isNot(oldPort));
      final (status, marker) = await _request(endpoint(getPort()));
      expect(status, 200);
      expect(marker, isNot(anyOf(isNull, 'foreign')));
      expect(
          (await SharedPreferences.getInstance()).getInt('${name}_proxy_port'),
          getPort());
      expect(await _request(endpoint(oldPort)), (200, 'foreign'));
    });

    proxyTest('does not restart on an inconclusive health timeout', () async {
      await initialize();
      final port = getPort();
      await closeListener();
      final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      addTearDown(() => silent.close(force: true));
      var requests = 0;
      silent.listen((_) => requests++);

      await initialize();
      expect(requests, 1);
      expect(getPort(), port);
      expect(isRunning(), isTrue);
    });

    proxyTest('does not resurrect a proxy stopped during resume', () async {
      await initialize();
      final port = getPort();
      await closeListener();
      final resuming = RemoteProxyDiagnostics.lifecycle('resumed');
      await Future.wait([resuming, stop(), stop()]);
      await RemoteProxyDiagnostics.lifecycle('resumed');
      expect(isRunning(), isFalse);
      expect(getPort(), 0);
      await expectLater(
          _request(endpoint(port)), throwsA(isA<SocketException>()));
      await initialize();
      expect(getPort(), port);
      expect((await _request(endpoint(port))).$1, 200);
    });
  }
}

Future<(int, String?)> _request(Uri uri) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final response = await (await client.getUrl(uri)).close();
    await response.drain<void>();
    return (
      response.statusCode,
      response.headers.value(RemoteProxyDiagnostics.healthHeader)
    );
  } finally {
    client.close(force: true);
  }
}

class _RealHttp extends HttpOverrides {}
