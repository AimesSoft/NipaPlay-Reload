import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/media_server_service_base.dart';

class _TestMediaServerService extends MediaServerServiceBase {
  @override
  String get serviceName => 'Test';

  @override
  String get serviceType => 'test';

  @override
  String get prefsKeyPrefix => 'test';

  @override
  String get serverNameFallback => 'Test Server';

  @override
  String get notConnectedMessage => 'Not connected';

  @override
  String? serverUrl;

  @override
  String? username;

  @override
  String? password;

  @override
  String? accessToken;

  @override
  String? userId;

  @override
  bool isConnected = false;

  @override
  bool isReady = false;

  @override
  List<String> selectedLibraryIds = <String>[];

  @override
  ServerProfile? currentProfile;

  @override
  String? currentAddressId;

  @override
  String normalizeRequestPath(String path) => path;

  @override
  Future<bool> testConnection(
      String url, String username, String password) async {
    return true;
  }

  @override
  Future<void> performAuthentication(
      String serverUrl, String username, String password) async {}

  @override
  Future<String> getServerId(String url) async => 'server-id';

  @override
  Future<String?> getServerName(String url) async => 'server-name';

  @override
  Future<void> loadAvailableLibraries() async {}

  @override
  Future<void> loadTranscodeSettings() async {}

  @override
  void clearServiceData() {}

  String resolveRelative(String baseUrl, String rawUrl) {
    return resolveServerRelativeUrl(baseUrl, rawUrl);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveServerRelativeUrl', () {
    final service = _TestMediaServerService();

    test('preserves base path when resolving root-like relative path', () {
      final result = service.resolveRelative(
        'https://host/emby',
        '/Videos/1/stream?api_key=abc',
      );
      expect(result, 'https://host/emby/Videos/1/stream?api_key=abc');
    });

    test('keeps absolute url unchanged', () {
      final result = service.resolveRelative(
        'https://host/emby',
        'https://cdn.example.com/video.m3u8',
      );
      expect(result, 'https://cdn.example.com/video.m3u8');
    });

    test('avoids duplicating base path when response already includes it', () {
      final result = service.resolveRelative(
        'https://host/emby',
        '/emby/Videos/1/stream',
      );
      expect(result, 'https://host/emby/Videos/1/stream');
    });
  });

  group('isAllowedRedirectTarget', () {
    final service = _TestMediaServerService();

    test('allows same-origin redirect', () {
      final allowed = service.isAllowedRedirectTarget(
        Uri.parse('https://host/emby/start'),
        Uri.parse('https://host/emby/final'),
      );
      expect(allowed, isTrue);
    });

    test('blocks different host', () {
      final allowed = service.isAllowedRedirectTarget(
        Uri.parse('https://host/emby/start'),
        Uri.parse('https://evil.example.com/steal'),
      );
      expect(allowed, isFalse);
    });

    test('blocks different scheme', () {
      final allowed = service.isAllowedRedirectTarget(
        Uri.parse('https://host/emby/start'),
        Uri.parse('http://host/emby/start'),
      );
      expect(allowed, isFalse);
    });

    test('blocks different port', () {
      final allowed = service.isAllowedRedirectTarget(
        Uri.parse('https://host:8443/emby/start'),
        Uri.parse('https://host/emby/start'),
      );
      expect(allowed, isFalse);
    });

    test('blocks non-http scheme', () {
      final allowed = service.isAllowedRedirectTarget(
        Uri.parse('https://host/emby/start'),
        Uri.parse('ftp://host/file'),
      );
      expect(allowed, isFalse);
    });
  });
}
