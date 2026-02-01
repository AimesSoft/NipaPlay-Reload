import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/webdav_service.dart';

class MediaSourceUtils {
  MediaSourceUtils._();

  static List<WebDAVConnection> _remoteWebDavConnections = const [];

  static void updateRemoteWebDavConnections(
      List<WebDAVConnection> connections) {
    _remoteWebDavConnections = List<WebDAVConnection>.unmodifiable(connections);
  }

  static bool isSmbPath(String filePath) {
    if (filePath.isEmpty) return false;
    final lower = filePath.toLowerCase();
    if (lower.startsWith('smb://')) return true;
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }

    final uri = Uri.tryParse(filePath);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') {
      return false;
    }
    return uri.path.startsWith('/smb/');
  }

  static bool isWebDavPath(String filePath) {
    if (filePath.isEmpty) return false;
    final lower = filePath.toLowerCase();
    if (lower.startsWith('webdav://') || lower.startsWith('dav://')) {
      return true;
    }
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    final uri = Uri.tryParse(filePath);
    if (uri == null) return false;
    if (uri.userInfo.isNotEmpty) return true;
    final pathLower = uri.path.toLowerCase();
    if (pathLower.contains('/webdav') || pathLower.contains('/dav')) {
      return true;
    }
    if (kIsWeb && _remoteWebDavConnections.isNotEmpty) {
      if (_matchesRemoteWebDavConnection(uri)) {
        return true;
      }
    }
    try {
      return WebDAVService.instance.resolveFileUrl(filePath) != null;
    } catch (_) {
      return false;
    }
  }

  static bool _matchesRemoteWebDavConnection(Uri fileUri) {
    final fileHost = fileUri.host.toLowerCase();
    for (final conn in _remoteWebDavConnections) {
      final baseUri = Uri.tryParse(conn.url.trim());
      if (baseUri == null || baseUri.scheme.isEmpty || baseUri.host.isEmpty) {
        continue;
      }
      if (baseUri.scheme != fileUri.scheme) continue;
      if (baseUri.host.toLowerCase() != fileHost) continue;
      if (_effectivePort(baseUri) != _effectivePort(fileUri)) continue;

      final basePath = _normalizePath(baseUri.path);
      final filePath = _normalizePath(fileUri.path, keepTrailingSlash: true);
      if (filePath == basePath.substring(0, basePath.length - 1) ||
          filePath.startsWith(basePath)) {
        return true;
      }
    }
    return false;
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    if (uri.scheme == 'https') return 443;
    if (uri.scheme == 'http') return 80;
    return 0;
  }

  static String _normalizePath(String path,
      {bool keepTrailingSlash = false}) {
    var normalized = path.trim();
    if (normalized.isEmpty) {
      return '/';
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    if (!keepTrailingSlash && normalized.length > 1) {
      normalized = normalized.replaceFirst(RegExp(r'/*$'), '');
    }
    if (!normalized.endsWith('/')) {
      normalized += '/';
    }
    return normalized;
  }
}
