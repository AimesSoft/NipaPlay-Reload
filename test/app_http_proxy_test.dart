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
