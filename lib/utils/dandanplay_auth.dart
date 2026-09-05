import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

abstract final class DandanplayAuth {
  static const String appId = 'nipaplayv1';
  static const String userAgent = 'NipaPlay/1.0';
  static const List<String> _secretServers = <String>[
    'https://nipaplay.aimes-soft.com',
    'https://kurisu.aimes-soft.com',
  ];

  static String? _appSecret;

  static Future<String> getAppSecret() async {
    if (_appSecret != null) return _appSecret!;

    final preferences = await SharedPreferences.getInstance();
    final savedAppSecret = preferences.getString('dandanplay_app_secret');
    if (savedAppSecret != null && savedAppSecret.isNotEmpty) {
      _appSecret = savedAppSecret;
      return savedAppSecret;
    }

    Object? lastError;
    for (final server in _secretServers) {
      try {
        final response = await http.get(
          Uri.parse('$server/nipaplay.php'),
          headers: const <String, String>{
            'User-Agent': userAgent,
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) {
          throw Exception(
            '从 $server 获取 AppSecret 失败: HTTP ${response.statusCode}',
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['encryptedAppSecret'] is! String) {
          throw FormatException(
            '从 $server 获取 AppSecret 失败: 响应格式无效',
          );
        }
        final appSecret = _decryptAppSecret(
          decoded['encryptedAppSecret'] as String,
        );
        await preferences.setString('dandanplay_app_secret', appSecret);
        _appSecret = appSecret;
        return appSecret;
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception('获取 Dandanplay AppSecret 失败: $lastError');
  }

  static String generateSignature({
    required int timestamp,
    required String apiPath,
    required String appSecret,
  }) {
    final source = '$appId$timestamp$apiPath$appSecret';
    return base64Encode(sha256.convert(utf8.encode(source)).bytes);
  }

  static String _decryptAppSecret(String encrypted) {
    final reversedLetters = encrypted.split('').map((character) {
      if (character.toLowerCase() == character.toUpperCase()) return character;
      final uppercase = character == character.toUpperCase();
      final base = (uppercase ? 'A' : 'a').codeUnitAt(0);
      return String.fromCharCode(
        base + 25 - (character.codeUnitAt(0) - base),
      );
    }).join();

    final rotated = reversedLetters.length >= 5
        ? reversedLetters.substring(1, reversedLetters.length - 4) +
            reversedLetters[0] +
            reversedLetters.substring(reversedLetters.length - 4)
        : reversedLetters;
    final reversedDigits = rotated.split('').map((character) {
      final digit = int.tryParse(character);
      return digit == null
          ? character
          : String.fromCharCode('0'.codeUnitAt(0) + 10 - digit);
    }).join();
    return reversedDigits.split('').map((character) {
      if (character.toLowerCase() == character.toUpperCase()) return character;
      return character == character.toLowerCase()
          ? character.toUpperCase()
          : character.toLowerCase();
    }).join();
  }
}
