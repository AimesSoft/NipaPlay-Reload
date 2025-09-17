import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrustedCertRule {
  final String host; // 不含协议与端口，例如: example.com 或 10.0.0.2
  final bool allowInvalid; // 允许该主机的无效/自签名证书
  final List<String> sha256Pins; // 证书指纹(sha256 der)十六进制字符串列表，可选

  TrustedCertRule({
    required this.host,
    this.allowInvalid = false,
    List<String>? sha256Pins,
  }) : sha256Pins = sha256Pins ?? const [];

  Map<String, dynamic> toJson() => {
        'host': host,
        'allowInvalid': allowInvalid,
        'sha256Pins': sha256Pins,
      };

  static TrustedCertRule fromJson(Map<String, dynamic> json) => TrustedCertRule(
        host: json['host'] as String,
        allowInvalid: json['allowInvalid'] as bool? ?? false,
        sha256Pins: (json['sha256Pins'] as List?)?.cast<String>() ?? const [],
      );
}

/// 管理自签名/无效证书的信任策略（仅影响 Dart 层发起的 HTTP 请求）
class CertificateTrustService {
  static final CertificateTrustService instance = CertificateTrustService._internal();
  CertificateTrustService._internal();

  static const _prefsKey = 'trusted_cert_rules_v1';
  static const _prefsGlobalAllowKey = 'trusted_cert_global_allow_v1';

  bool _globalAllow = false; // 极不推荐，一刀切允许所有无效证书
  final List<TrustedCertRule> _rules = [];

  bool get globalAllow => _globalAllow;
  List<TrustedCertRule> get rules => List.unmodifiable(_rules);

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _globalAllow = prefs.getBool(_prefsGlobalAllowKey) ?? false;
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _rules
          ..clear()
          ..addAll(list.map((e) => TrustedCertRule.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('CertificateTrustService 初始化失败: $e');
    }
  }

  Future<void> setGlobalAllow(bool allow) async {
    _globalAllow = allow;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsGlobalAllowKey, allow);
  }

  Future<void> upsertRule(TrustedCertRule rule) async {
    final idx = _rules.indexWhere((r) => r.host == rule.host);
    if (idx >= 0) {
      _rules[idx] = rule;
    } else {
      _rules.add(rule);
    }
    await _persist();
  }

  Future<void> removeRule(String host) async {
    _rules.removeWhere((r) => r.host == host);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_rules.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  /// 在 IO 平台下由 HttpOverrides 调用：判断是否允许该主机证书
  /// - host: 目标主机名（不含协议）
  /// - derBytes: 服务器返回的证书 DER 原始字节，用于指纹校验（可为空，若为空仅根据 allowInvalid 判断）
  bool allowHost(String host, {Uint8List? derBytes}) {
    if (_globalAllow) return true;
    final rule = _rules.firstWhere(
      (r) => _hostEquals(r.host, host),
      orElse: () => TrustedCertRule(host: '__none__'),
    );

    if (rule.host == '__none__') return false;

    // 若配置了指纹，则必须匹配其一
    if (rule.sha256Pins.isNotEmpty && derBytes != null) {
      final digest = sha256.convert(derBytes).bytes;
      final hex = _toHex(digest);
      return rule.sha256Pins.map((s) => s.toLowerCase()).contains(hex.toLowerCase());
    }

    // 未配置指纹，纯允许该主机的无效证书
    return rule.allowInvalid;
  }

  bool _hostEquals(String a, String b) {
    // 忽略端口与大小写，简单匹配
    String norm(String h) => h.trim().toLowerCase().split(':').first;
    return norm(a) == norm(b);
  }

  String _toHex(List<int> bytes) {
    final StringBuffer sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
