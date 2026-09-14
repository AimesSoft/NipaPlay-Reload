import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/system_proxy_service.dart';

void main() {
  tearDown(() {
    SystemProxyService.instance.applyMacOSProxyOutputForTesting('');
  });

  test('macOS HTTP and HTTPS proxies are applied with system exceptions', () {
    SystemProxyService.instance.applyMacOSProxyOutputForTesting('''
<dictionary> {
  ExceptionsList : <array> {
    0 : localhost
    1 : <local>
  }
  HTTPEnable : 1
  HTTPPort : 7897
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7897
  HTTPSProxy : 127.0.0.1
}
''');

    expect(
      SystemProxyService.instance
          .findProxy(Uri.parse('https://nipaplay.aimes-soft.com/')),
      'PROXY 127.0.0.1:7897;DIRECT',
    );
    expect(
      SystemProxyService.instance.findProxy(Uri.parse('http://localhost/')),
      'DIRECT',
    );
  });

  test('macOS HTTP proxy is used as fallback for HTTPS targets', () {
    SystemProxyService.instance.applyMacOSProxyOutputForTesting('''
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 7897
  HTTPProxy : 127.0.0.1
}
''');

    expect(
      SystemProxyService.instance.findProxy(Uri.parse('https://example.com/')),
      'PROXY 127.0.0.1:7897;DIRECT',
    );
  });

  test('disabled macOS proxy configuration falls back to direct', () {
    SystemProxyService.instance.applyMacOSProxyOutputForTesting('''
<dictionary> {
  HTTPEnable : 0
  HTTPSEnable : 0
}
''');

    expect(
      SystemProxyService.instance.findProxy(Uri.parse('https://example.com/')),
      'DIRECT',
    );
  });
}
