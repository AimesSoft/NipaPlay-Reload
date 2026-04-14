import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class RemoteControlSettings {
  RemoteControlSettings._();

  static const String receiverEnabledKey = 'remote_control_receiver_enabled';
  static const String matchedBaseUrlKey = 'remote_control_matched_base_url';
  static const String matchedHostnameKey = 'remote_control_matched_hostname';
  static const String clientIdKey = 'remote_control_client_id';

  static Future<bool> isReceiverEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(receiverEnabledKey) ?? true;
  }

  static Future<void> setReceiverEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(receiverEnabledKey, enabled);
  }

  static Future<String?> getMatchedBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(matchedBaseUrlKey)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw;
  }

  static Future<String?> getMatchedHostname() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(matchedHostnameKey)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw;
  }

  static Future<void> saveMatchedTarget({
    required String baseUrl,
    String? hostname,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(matchedBaseUrlKey, baseUrl);
    final trimmedHostname = hostname?.trim() ?? '';
    if (trimmedHostname.isEmpty) {
      await prefs.remove(matchedHostnameKey);
    } else {
      await prefs.setString(matchedHostnameKey, trimmedHostname);
    }
  }

  static Future<void> clearMatchedTarget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(matchedBaseUrlKey);
    await prefs.remove(matchedHostnameKey);
  }

  static Future<String> getOrCreateClientId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(clientIdKey)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random().nextInt(0x7fffffff).toRadixString(36);
    final clientId = 'rc-$timestamp-$random';
    await prefs.setString(clientIdKey, clientId);
    return clientId;
  }
}
