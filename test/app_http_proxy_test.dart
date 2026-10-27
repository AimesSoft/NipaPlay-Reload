import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/app_http_proxy.dart';

void main() {
  tearDown(AppHttpProxy.clear);

  test('manual HTTP proxy overrides the system proxy for all target schemes',
      () {
    AppHttpProxy.set('  http://127.0.0.1:8000  ');

    expect(
      AppHttpProxy.findProxy(
        Uri.parse('http://media.example/video'),
        (_) => 'DIRECT',
      ),
      'PROXY 127.0.0.1:8000',
    );
    expect(
      AppHttpProxy.findProxy(
        Uri.parse('https://media.example/video'),
        (_) => 'DIRECT',
      ),
      'PROXY 127.0.0.1:8000',
    );
  });

  test('empty manual proxy preserves system proxy behavior', () {
    expect(
      AppHttpProxy.findProxy(
        Uri.parse('https://media.example/video'),
        (_) => 'PROXY system.test:9000;DIRECT',
      ),
      'PROXY system.test:9000;DIRECT',
    );
  });

  test('loopback stays direct with both manual and system proxies', () {
    for (final manual in ['', 'http://127.0.0.1:8000']) {
      AppHttpProxy.set(manual);
      for (final host in [
        'localhost',
        'LOCALHOST.',
        '127.0.0.1',
        '127.9.8.7',
        '[::1]',
        '[0:0:0:0:0:0:0:1]',
        '[::ffff:127.0.0.1]',
      ]) {
        expect(
            AppHttpProxy.findProxy(Uri.parse('http://$host:18082/asset'),
                (_) => throw StateError('loopback reached system proxy')),
            'DIRECT',
            reason: '$host with manual proxy $manual');
      }
    }
  });

  test('LAN addresses and misleading hostnames retain the proxy policy', () {
    AppHttpProxy.set('http://127.0.0.1:8000');
    for (final host in [
      'localhost.example',
      '127.0.0.1.example',
      '192.168.1.2',
      '10.1.2.3',
      '[::2]',
      '[2001:db8::1]',
    ]) {
      expect(
          AppHttpProxy.findProxy(
              Uri.parse('http://$host/video'), (_) => 'DIRECT'),
          'PROXY 127.0.0.1:8000',
          reason: host);
    }
  });

  test('a real loopback HTTP bridge bypasses an enabled outbound proxy',
      () async {
    final local = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var proxyRequests = 0;
    local.listen((request) async {
      request.response.write('local mesh bridge');
      await request.response.close();
    });
    proxy.listen((request) async {
      proxyRequests++;
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    });
    final client = HttpClient()
      ..findProxy = (uri) =>
          AppHttpProxy.findProxy(uri, (_) => 'PROXY 127.0.0.1:${proxy.port}');
    try {
      AppHttpProxy.set('http://127.0.0.1:${proxy.port}');
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${local.port}/mesh-asset'));
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(await response.transform(const SystemEncoding().decoder).join(),
          'local mesh bridge');
      expect(proxyRequests, 0);
    } finally {
      client.close(force: true);
      await local.close(force: true);
      await proxy.close(force: true);
    }
  });

  test('only plain HTTP forward proxy endpoints are accepted', () {
    expect(AppHttpProxy.validate(''), isNull);
    expect(
      AppHttpProxy.validate('http://proxy.example:8080'),
      Uri.parse('http://proxy.example:8080'),
    );

    for (final invalid in <String>[
      'https://proxy.example:443',
      'socks5://proxy.example:1080',
      'http://proxy.example:8080/path',
      'http://proxy.example:8080?mode=proxy',
      'http://proxy.example:8080#fragment',
      'http://',
    ]) {
      expect(
        () => AppHttpProxy.validate(invalid),
        throwsA(isA<FormatException>()),
        reason: invalid,
      );
    }
  });
}
