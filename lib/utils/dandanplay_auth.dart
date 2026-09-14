import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class DandanplayAuth {
  static const String appId = 'nipaplayv1';
  static const String userAgent = 'NipaPlay/1.0';

  /// The gateway holds the AppSecret; clients only use this compatibility value.
  static Future<String> getAppSecret() async => 'server-managed';

  static String generateSignature({
    required int timestamp,
    required String apiPath,
    required String appSecret,
  }) {
    final source = '$appId$timestamp$apiPath$appSecret';
    return base64Encode(sha256.convert(utf8.encode(source)).bytes);
  }
}
