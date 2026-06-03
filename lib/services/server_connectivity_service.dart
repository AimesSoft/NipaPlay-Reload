import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/network_settings.dart';

class ServerConnectivityService {
  static final ServerConnectivityService instance =
      ServerConnectivityService._internal();

  ServerConnectivityService._internal();

  bool? _dandanplayAvailable;
  bool? _bangumiAvailable;
  bool _isChecking = false;

  bool? get dandanplayAvailable => _dandanplayAvailable;
  bool? get bangumiAvailable => _bangumiAvailable;
  bool get isChecking => _isChecking;

  final ValueNotifier<bool?> dandanplayNotifier = ValueNotifier(null);
  final ValueNotifier<bool?> bangumiNotifier = ValueNotifier(null);
  final ValueNotifier<bool> checkingNotifier = ValueNotifier(false);

  Future<void> initialize() async {
    await checkConnectivity();
  }

  Future<void> checkConnectivity() async {
    if (_isChecking) return;
    _isChecking = true;
    checkingNotifier.value = true;
    _dandanplayAvailable = null;
    _bangumiAvailable = null;
    dandanplayNotifier.value = null;
    bangumiNotifier.value = null;

    try {
      final dandanplayServer = await DandanplayService.getApiBaseUrl();
      final bangumiServer = await NetworkSettings.getBangumiServer();

      final results = await Future.wait([
        _checkDandanplay(dandanplayServer),
        _checkBangumi(bangumiServer),
      ]);

      _dandanplayAvailable = results[0];
      _bangumiAvailable = results[1];
      dandanplayNotifier.value = results[0];
      bangumiNotifier.value = results[1];
    } finally {
      _isChecking = false;
      checkingNotifier.value = false;
    }
  }

  static String _generateSignature(
    String appId,
    int timestamp,
    String apiPath,
    String appSecret,
  ) {
    final signatureString = '$appId$timestamp$apiPath$appSecret';
    final hash = sha256.convert(utf8.encode(signatureString));
    return base64.encode(hash.bytes);
  }

  Future<bool> _checkDandanplay(String serverUrl) async {
    const apiPath = '/api/v2/bangumi/1';
    final uri = Uri.parse('$serverUrl$apiPath');
    try {
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final headers = {
        'Accept': 'application/json',
        'User-Agent': DandanplayService.userAgent,
        'X-AppId': DandanplayService.appId,
        'X-Signature': _generateSignature(
          DandanplayService.appId,
          timestamp,
          apiPath,
          appSecret,
        ),
        'X-Timestamp': '$timestamp',
      };
      final response =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } on TimeoutException {
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkBangumi(String serverUrl) async {
    final uri = Uri.parse('$serverUrl/v0/subjects/1');
    const headers = {'User-Agent': 'NipaPlay/1.0'};
    try {
      final response =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } on TimeoutException {
      return false;
    } catch (e) {
      return false;
    }
  }
}
