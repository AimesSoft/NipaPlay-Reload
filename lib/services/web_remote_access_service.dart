import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WebRemoteAccessService {
  static const String _baseUrlKey = 'web_remote_access_base_url';
  static String? _cachedBaseUrl;
  static bool _initialized = false;

  static String? get cachedBaseUrl => _cachedBaseUrl;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_baseUrlKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _cachedBaseUrl = normalizeBaseUrl(stored);
    }
    _initialized = true;
  }

  static Future<String?> getBaseUrl() async {
    await ensureInitialized();
    return _cachedBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final normalized = normalizeBaseUrl(url);
    _cachedBaseUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, normalized);
    _initialized = true;
  }

  static String? resolveBaseUrlFromQuery() {
    final uri = Uri.base;
    final rawBaseUrl = uri.queryParameters['api'] ??
        uri.queryParameters['apiBase'] ??
        uri.queryParameters['baseUrl'];
    final normalizedBaseUrl = rawBaseUrl?.trim();
    if (normalizedBaseUrl != null && normalizedBaseUrl.isNotEmpty) {
      return normalizeBaseUrl(normalizedBaseUrl);
    }
    return null;
  }

  static String? resolveBaseUrlFromOrigin() {
    final origin = Uri.base.origin.trim();
    if (origin.isNotEmpty && origin != 'null') {
      return normalizeBaseUrl(origin);
    }
    return null;
  }

  static Future<String?> resolveCandidateBaseUrl() async {
    final queryOverride = resolveBaseUrlFromQuery();
    if (queryOverride != null) return queryOverride;

    await ensureInitialized();
    if (_cachedBaseUrl != null && _cachedBaseUrl!.isNotEmpty) {
      return _cachedBaseUrl;
    }

    return resolveBaseUrlFromOrigin();
  }

  static String normalizeBaseUrl(String url) {
    var value = url.trim();
    if (value.isEmpty) return value;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('/api')) {
      value = value.substring(0, value.length - 4);
    }
    return value;
  }

  static bool isValidBaseUrl(String url) {
    final normalized = normalizeBaseUrl(url);
    final uri = Uri.tryParse(normalized);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static Future<bool> probe(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/info'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data is Map<String, dynamic> && data['app'] == 'NipaPlay';
      }
    } catch (_) {}
    return false;
  }

  static Uri? apiUri(String path) {
    final base = _cachedBaseUrl;
    if (base == null || base.isEmpty) return null;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }

  static String? apiUrl(String path) => apiUri(path)?.toString();

  static Uri proxyUri(Uri target) {
    if (!kIsWeb) return target;
    final base = _cachedBaseUrl;
    if (base == null || base.isEmpty) return target;
    if (!target.isAbsolute) return target;
    if (target.scheme != 'http' && target.scheme != 'https') {
      return target;
    }
    final targetString = target.toString();
    if (targetString.toLowerCase().startsWith(base.toLowerCase())) {
      return target;
    }
    final encoded = Uri.encodeComponent(targetString);
    return Uri.parse('$base/api/web_proxy?url=$encoded');
  }

  static String? proxyUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return proxyUri(uri).toString();
  }

  static String? imageProxyUrl(String imageUrl) {
    if (!kIsWeb) return imageUrl;
    final base = _cachedBaseUrl;
    if (base == null || base.isEmpty) return imageUrl;
    if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    final encodedUrl = base64Url.encode(utf8.encode(imageUrl));
    return '$base/api/image_proxy?url=$encodedUrl';
  }
}
