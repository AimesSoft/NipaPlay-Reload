import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/nipaplay_lan_discovery.dart';

// 覆盖范围：
// 1) 发现协议线格式回归（nipaplay_discover / nipaplay_discover_response v1），
//    防止协议字节被无意改动（协议兼容性约束）。
// 2) 应答器 5 秒内回包（对应扫描端 _discoverByUdp 的等待窗口）。
// 3) 端口被占用/系统保留时 start() 返回 false 并记录原因（失败可见性修复）。
void main() {
  group('NipaPlayLanDiscoveryProtocol 线格式', () {
    test('发现请求字节保持 v1 协议格式', () {
      final bytes =
          utf8.decode(NipaPlayLanDiscoveryProtocol.buildRequestBytes());
      expect(bytes, '{"type":"nipaplay_discover","v":1}');
    });

    test('发现响应可被扫描端解析且字段完整', () {
      final bytes =
          NipaPlayLanDiscoveryProtocol.buildResponseBytes(webPort: 1180);
      final payload = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(payload['type'], 'nipaplay_discover_response');
      expect(payload['v'], NipaPlayLanDiscoveryProtocol.protocolVersion);
      expect(payload['app'], 'NipaPlay');
      expect(payload['port'], 1180);
      expect(payload['hostname'], isA<String>());
      expect(payload['os'], isA<String>());
    });
  });

  group('NipaPlayLanDiscoveryResponder', () {
    test('应在 5 秒内回应合法发现请求', () async {
      final responder = NipaPlayLanDiscoveryResponder();
      final started = await responder.start(webPort: 12345);
      expect(started, isTrue, reason: responder.lastStartError ?? 'UDP 绑定失败');
      expect(responder.isRunning, isTrue);
      addTearDown(responder.stop);

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(socket.close);

      // 只认 webPort==12345 的应答，避免同机其他 32123 应答者造成串扰
      final response = Completer<Datagram>();
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final parsed =
              NipaPlayLanDiscoveryProtocol.tryParseResponse(datagram!);
          if (parsed != null && parsed.port == 12345 && !response.isCompleted) {
            response.complete(datagram);
          }
        }
      });

      socket.send(
        NipaPlayLanDiscoveryProtocol.buildRequestBytes(),
        InternetAddress.loopbackIPv4,
        nipaplayLanDiscoveryPort,
      );

      final datagram = await response.future
          .timeout(const Duration(seconds: 5), onTimeout: () {
        fail('发现请求在 5 秒内未收到应答');
      });
      final parsed = NipaPlayLanDiscoveryProtocol.tryParseResponse(datagram);
      expect(parsed, isNotNull);
      expect(parsed!.port, 12345);
      expect(parsed.ip, isNotEmpty);
    });

    test('端口被占用时 start 返回 false 且记录原因（不再静默失败）', () async {
      // 两层验证策略：
      //  - 非 Windows：真实独占绑定（无 SO_REUSEADDR）+ reuseAddress 绑定 = EADDRINUSE，确定性成立。
      //  - Windows：Dart 的 UDP socket 不设 SO_EXCLUSIVEADDRUSE，独占占用无法从 Dart 可靠构造；
      //    用测试注入强制绑定抛错验证失败分支，真实占用场景由
      //    scripts/verify_webdav_discovery.ps1 的 L1/L4 断言覆盖（见 docs/webdav/evidence）。
      RawDatagramSocket? dartBlocker;
      if (Platform.isWindows) {
        NipaPlayLanDiscoveryResponder.bindOverrideForTest =
            (InternetAddress host, int port, {bool reuseAddress = true}) async {
          throw const SocketException('测试注入：模拟 UDP 32123 被占用/被系统保留');
        };
        addTearDown(() {
          NipaPlayLanDiscoveryResponder.bindOverrideForTest = null;
        });
      } else {
        dartBlocker = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          nipaplayLanDiscoveryPort,
        );
        addTearDown(dartBlocker.close);
      }

      final responder = NipaPlayLanDiscoveryResponder();
      final started = await responder.start(webPort: 1180);
      expect(started, isFalse, reason: '端口被占用时不应报告启动成功');
      expect(responder.isRunning, isFalse);
      expect(responder.lastStartError, isNotNull);
      expect(responder.lastStartError, contains('32123'));
      await responder.stop();
    });
  });
}
