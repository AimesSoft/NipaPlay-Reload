import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/http_user_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_server_transport_client_stub.dart'
    if (dart.library.io) 'media_server_transport_client_io.dart' as platform;

/// Sends Emby/Jellyfin HTTP requests through one configurable transport.
class MediaServerTransport {
  static String? _connectionUserAgentCache;

  static const String defaultConnectionUserAgent = defaultNipaPlayUserAgent;

  MediaServerTransport({
    String userAgent = defaultConnectionUserAgent,
  })  : _client = platform.createMediaServerClient(),
        _userAgent = _resolveUserAgent(userAgent);

  /// Creates a transport that owns [client] and closes it on timeout or close.
  MediaServerTransport.fromClient(
    http.Client client, {
    String userAgent = defaultConnectionUserAgent,
  })  : _client = client,
        _userAgent = _resolveUserAgent(userAgent);

  /// Persists the User-Agent shared by all Emby/Jellyfin request types.
  ///
  /// An empty value restores [defaultConnectionUserAgent].
  static Future<String> saveConnectionUserAgent(String userAgent) async {
    final sanitized = sanitizeHttpUserAgent(userAgent);
    _connectionUserAgentCache = sanitized;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        SettingsKeys.mediaServerConnectionUserAgent,
        sanitized,
      );
    } catch (_) {}
    return sanitized;
  }

  /// Returns the stored value; an empty value means to use the app default.
  static Future<String> getStoredConnectionUserAgent() async {
    final cached = _connectionUserAgentCache;
    if (cached != null) {
      return cached;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = sanitizeHttpUserAgent(
        preferences.getString(SettingsKeys.mediaServerConnectionUserAgent) ??
            '',
      );
      _connectionUserAgentCache = stored;
      return stored;
    } catch (_) {
      _connectionUserAgentCache = '';
      return '';
    }
  }

  /// Creates a one-request transport from the current persisted UA setting.
  static Future<MediaServerTransport> fromStoredSettings() async {
    final storedUserAgent = await getStoredConnectionUserAgent();
    final userAgent = _resolveUserAgent(storedUserAgent);
    return MediaServerTransport(userAgent: userAgent);
  }

  final http.Client _client;
  final String _userAgent;

  static String _resolveUserAgent(String value) {
    final sanitized = sanitizeHttpUserAgent(value);
    return sanitized.isEmpty ? defaultConnectionUserAgent : sanitized;
  }

  /// Sends [request] and fully buffers its response within [timeout].
  ///
  /// A timeout closes this transport, so it cannot be reused afterwards.
  Future<http.Response> send(
    http.BaseRequest request, {
    required Duration timeout,
  }) async {
    final hasUserAgent = request.headers.keys.any(
      (header) => header.toLowerCase() == 'user-agent',
    );
    if (platform.supportsCustomUserAgentHeader && !hasUserAgent) {
      request.headers['User-Agent'] = _userAgent;
    }
    try {
      return await (() async {
        final streamedResponse = await _client.send(request);
        return http.Response.fromStream(streamedResponse);
      })()
          .timeout(timeout);
    } on TimeoutException {
      _client.close();
      rethrow;
    }
  }

  /// Releases sockets owned by this transport.
  void close() => _client.close();
}
