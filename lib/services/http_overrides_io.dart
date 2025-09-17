// ignore: avoid_web_libraries_in_flutter
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'certificate_trust_service.dart';

/// 在非 Web 平台，为 Dart IO 网络栈设置证书例外规则
class NipaHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    // 仅在真正的 IO 环境下设置回调
    if (!kIsWeb) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        try {
          final der = cert.der; // 证书原始 DER
          final allow = CertificateTrustService.instance.allowHost(host, derBytes: der);
          if (!allow) {
            debugPrint('TLS 拒绝: $host:${port} - 自签名/无效证书未被允许');
          }
          return allow;
        } catch (e) {
          debugPrint('badCertificateCallback 异常: $e');
          return false;
        }
      };
    }
    return client;
  }
}

void installNipaHttpOverrides() {
  HttpOverrides.global = NipaHttpOverrides();
}
