import '../../services/nipaplay_server_router.dart';

/// Default gateway resolution for a host without a browser relay or GUI login.
abstract final class DandanplayService {
  static Future<String> getApiBaseUrl() =>
      NipaplayServerRouter.instance.effectiveServer();
  static Map<String, String> get authorizationHeaders => const {};
  static bool get isLoggedIn => false;
}

abstract final class WebRemoteAccessService {
  static String? get cachedBaseUrl => null;
  static bool isWithinBase(Uri uri, Uri base) => false;
}
