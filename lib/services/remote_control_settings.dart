import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:shared_preferences/shared_preferences.dart';

class RemoteControlSettings {
  RemoteControlSettings._();

  static const String receiverEnabledKey = 'remote_control_receiver_enabled';
  static const String matchedBaseUrlKey = 'remote_control_matched_base_url';
  static const String matchedHostnameKey = 'remote_control_matched_hostname';
  static const String clientIdKey = 'remote_control_client_id';
  static const String trustedDevicesKey = 'remote_control_trusted_devices';

  static Future<bool> isReceiverEnabled() async {
    // 在移动端（phone）禁用被控监听
    if (globals.isPhone) {
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(receiverEnabledKey) ?? true;
  }

  static Future<void> setReceiverEnabled(bool enabled) async {
    // 在移动端（phone）不允许设置为启用状态
    if (globals.isPhone) {
      return;
    }
    
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

  static Future<List<Map<String, dynamic>>> getTrustedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(trustedDevicesKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  static Future<void> addTrustedDevice(Map<String, dynamic> device) async {
    final devices = await getTrustedDevices();
    final clientKey = device['clientKey'] as String;
    final existingIndex = devices.indexWhere((d) => d['clientKey'] == clientKey);
    
    if (existingIndex >= 0) {
      devices[existingIndex] = device;
    } else {
      devices.add(device);
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(trustedDevicesKey, jsonEncode(devices));
  }

  static Future<void> removeTrustedDevice(String clientKey) async {
    final devices = await getTrustedDevices();
    devices.removeWhere((d) => d['clientKey'] == clientKey);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(trustedDevicesKey, jsonEncode(devices));
  }

  static Future<void> clearTrustedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(trustedDevicesKey);
  }
}
