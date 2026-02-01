import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WebRemoteAccessService {
  static const String _baseUrlKey = 'web_remote_access_base_url';
  static String? _cachedBaseUrl;
  static bool _initialized = false;
  static final Map<String, bool> _probeCache = {};
  static final Map<String, Future<bool>> _probeInFlight = {};
  
  /// Base URL 变更通知器
  static final ValueNotifier<String?> baseUrlNotifier = ValueNotifier<String?>(null);

  static String? get cachedBaseUrl => _cachedBaseUrl;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_baseUrlKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _cachedBaseUrl = normalizeBaseUrl(stored);
      baseUrlNotifier.value = _cachedBaseUrl;
    }
    _initialized = true;
  }

  static Future<String?> getBaseUrl() async {
    await ensureInitialized();
    return _cachedBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final normalized = normalizeBaseUrl(url);
    if (_cachedBaseUrl != normalized) {
      _cachedBaseUrl = normalized;
      baseUrlNotifier.value = normalized;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_baseUrlKey, normalized);
    }
    _probeCache[normalized] = true;
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
    if (queryOverride != null) {
      final ok = await _probeCached(queryOverride);
      if (ok) {
        return queryOverride;
      }
    }

    await ensureInitialized();
    if (_cachedBaseUrl != null && _cachedBaseUrl!.isNotEmpty) {
      if (!kIsWeb) {
        return _cachedBaseUrl;
      }
      final ok = await _probeCached(_cachedBaseUrl!);
      if (ok) {
        return _cachedBaseUrl;
      }
    }

    final origin = resolveBaseUrlFromOrigin();
    if (origin == null) return null;
    final ok = await _probeCached(origin);
    return ok ? origin : null;
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

  static Future<bool> _probeCached(String baseUrl) async {
    final normalized = normalizeBaseUrl(baseUrl);
    if (!isValidBaseUrl(normalized)) {
      _probeCache[normalized] = false;
      return false;
    }
    if (_probeCache.containsKey(normalized)) {
      return _probeCache[normalized] ?? false;
    }
    final inflight = _probeInFlight[normalized];
    if (inflight != null) return inflight;
    final future = probe(normalized).then((ok) {
      _probeCache[normalized] = ok;
      _probeInFlight.remove(normalized);
      return ok;
    });
    _probeInFlight[normalized] = future;
    return future;
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
    if (base == null || base.isEmpty) {
      debugPrint('[WebRemote] imageProxyUrl: Base URL is empty, returning original: $imageUrl');
      return imageUrl;
    }
    
    // 如果是网络图片但不是 http/https，直接返回（可能是一些 data:image 或 blob:）
    if (imageUrl.startsWith('data:') || imageUrl.startsWith('blob:')) {
      return imageUrl;
    }

    // 本地路径或普通网络图片，都走代理
    final encodedUrl = base64Url.encode(utf8.encode(imageUrl));
    final proxyUrl = '$base/api/image_proxy?url=$encodedUrl';
    return proxyUrl;
  }

  static Future<List<Map<String, dynamic>>> fetchHistory() async {
    final base = await resolveCandidateBaseUrl();
    if (base == null) return [];

    try {
      final response = await http.get(Uri.parse('$base/api/history'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('Error fetching remote history: $e');
    }
    return [];
  }
}
