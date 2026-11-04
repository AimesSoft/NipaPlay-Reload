import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/webdav_proxy_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test binding 会拦截一切 HttpClient 请求（一律返回 400），HTTP
  // 断言在测试环境永远失败。监听 socket 是否真实存在改用 TCP 连接验证，
  // Socket.connect 不经过该拦截；生产代码的 /health HTTP 探测保持不变。
  Future<bool> tcpConnectable(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  group('WebDAVProxyService 回环代理自愈', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    tearDown(() async {
      await WebDAVProxyService.instance.stop();
    });

    test('initialize 后监听真实可连', () async {
      await WebDAVProxyService.instance.initialize();

      final service = WebDAVProxyService.instance;
      expect(service.isRunning, isTrue);
      expect(service.port, greaterThan(0));
      expect(await tcpConnectable(service.port), isTrue);
    });

    test('监听 socket 被回收后再次 initialize 会就地重启（复现 iOS 后台挂起）', () async {
      final service = WebDAVProxyService.instance;
      await service.initialize();
      final firstPort = service.port;

      // 只关 socket，保留 _isRunning/_port，等价于 iOS 回收监听端口后的现场。
      await service.simulateListenerReclaimedForTest();
      expect(service.isRunning, isTrue, reason: 'Dart 侧状态标记未失效');
      expect(await tcpConnectable(firstPort), isFalse, reason: '旧端口已经拒连');

      await service.initialize();

      expect(service.isRunning, isTrue);
      expect(service.port, greaterThan(0));
      expect(await tcpConnectable(service.port), isTrue);
    });

    test('ensureAliveIfRunning 在代理从未启动时是 no-op，不主动拉起', () async {
      await WebDAVProxyService.instance.ensureAliveIfRunning();
      expect(WebDAVProxyService.instance.isRunning, isFalse);
    });
  });
}
