import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('concurrent first use binds one healthy proxy and restart works',
      () async {
    SharedPreferences.setMockInitialValues({'smb_proxy_port': 0});
    final proxy = SMBProxyService.instance;
    expect(proxy.isRunning, isFalse);
    addTearDown(proxy.stop);
    await Future.wait(List.generate(10, (_) => proxy.initialize()));
    expect(proxy.isRunning, isTrue);
    final port = proxy.port;
    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    try {
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/smb/health')))
          .close();
      expect(response.statusCode, 200);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    await proxy.initialize();
    expect(proxy.port, port);
    await proxy.stop();
    expect(proxy.isRunning, isFalse);
    await proxy.initialize();
    expect(proxy.isRunning, isTrue);
  });
}

class _RealHttp extends HttpOverrides {}
