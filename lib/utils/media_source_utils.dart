import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';

class MediaSourceUtils {
  MediaSourceUtils._();

  static List<WebDAVConnection> _remoteWebDavConnections = const [];

  static void updateRemoteWebDavConnections(
      List<WebDAVConnection> connections) {
    _remoteWebDavConnections = List<WebDAVConnection>.unmodifiable(connections);
  }

  static bool isContentUri(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && uri.scheme.toLowerCase() == 'content';
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

  static String _normalizePath(String path, {bool keepTrailingSlash = false}) {
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

  // ==================== 新路径格式工具方法 ====================

  /// 判断路径是否为新格式的 WebDAV 路径 (webdav://connectionName/path)
  static bool isNewWebDavPath(String filePath) {
    if (filePath.isEmpty) return false;
    return filePath.toLowerCase().startsWith('webdav://');
  }

  /// 判断路径是否为新格式的 SMB 路径 (smb://connectionName/path)
  static bool isNewSmbPath(String filePath) {
    if (filePath.isEmpty) return false;
    return filePath.toLowerCase().startsWith('smb://');
  }

  /// 构建新格式 WebDAV 路径: webdav://connectionName/relativePath
  static String buildWebDavPath(String connectionName, String relativePath) {
    var path = relativePath.trim();
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    return 'webdav://$connectionName$path';
  }

  /// 构建新格式 SMB 路径: smb://connectionName/relativePath
  static String buildSmbPath(String connectionName, String relativePath) {
    var path = relativePath.trim();
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    return 'smb://$connectionName$path';
  }

  /// 解析新格式 WebDAV 路径，返回 (connectionName, relativePath)
  /// 如果不是新格式路径返回 null
  static ({String connectionName, String relativePath})? parseWebDavPath(
      String filePath) {
    if (!isNewWebDavPath(filePath)) return null;
    // webdav://connectionName/path
    final pathWithoutScheme = filePath.substring(9); // 去掉 'webdav://'
    final firstSlashIndex = pathWithoutScheme.indexOf('/');
    if (firstSlashIndex == -1) {
      return (connectionName: pathWithoutScheme, relativePath: '/');
    }
    return (
      connectionName: pathWithoutScheme.substring(0, firstSlashIndex),
      relativePath: pathWithoutScheme.substring(firstSlashIndex),
    );
  }

  /// 解析新格式 SMB 路径，返回 (connectionName, relativePath)
  /// 如果不是新格式路径返回 null
  static ({String connectionName, String relativePath})? parseSmbPath(
      String filePath) {
    if (!isNewSmbPath(filePath)) return null;
    // smb://connectionName/path
    final pathWithoutScheme = filePath.substring(6); // 去掉 'smb://'
    final firstSlashIndex = pathWithoutScheme.indexOf('/');
    if (firstSlashIndex == -1) {
      return (connectionName: pathWithoutScheme, relativePath: '/');
    }
    return (
      connectionName: pathWithoutScheme.substring(0, firstSlashIndex),
      relativePath: pathWithoutScheme.substring(firstSlashIndex),
    );
  }

  /// 将旧的 WebDAV 完整 URL 转换为新格式
  /// 旧格式: http://user:pass@host:port/path/to/file.mp4
  /// 新格式: webdav://connectionName/path/to/file.mp4
  static String? migrateWebDavPath(String oldPath) {
    if (isNewWebDavPath(oldPath)) return oldPath;
    if (!isWebDavPath(oldPath)) return null;

    try {
      // 1. 精确匹配：host/port 完全一致
      final resolved = WebDAVService.instance.resolveFileUrl(oldPath);
      if (resolved != null) {
        return buildWebDavPath(resolved.connection.name, resolved.relativePath);
      }

      // 2. 降级匹配：地址已变更，通过 URL path 前缀和用户名来识别连接
      final fileUri = Uri.tryParse(oldPath);
      if (fileUri == null || fileUri.host.isEmpty) return null;

      final connections = WebDAVService.instance.connections;
      if (connections.isEmpty) return null;

      // 如果只有一个 WebDAV 连接，直接用那个
      if (connections.length == 1) {
        final conn = connections.first;
        final relativePath = _extractRelativePath(fileUri.path, conn.url);
        if (relativePath != null) {
          return buildWebDavPath(conn.name, relativePath);
        }
      }

      // 多个连接时，按 URL path 前缀 + username 匹配
      WebDAVConnection? bestMatch;
      int bestScore = -1;

      for (final conn in connections) {
        int score = 0;

        // username 匹配加分
        if (fileUri.userInfo.isNotEmpty) {
          final fileUser = fileUri.userInfo.split(':').first;
          if (fileUser == conn.username) {
            score += 100;
          }
        }

        // URL path 前缀匹配加分
        final relativePath = _extractRelativePath(fileUri.path, conn.url);
        if (relativePath != null) {
          score += 50;
        }

        if (score > bestScore) {
          bestScore = score;
          bestMatch = conn;
        }
      }

      if (bestMatch != null && bestScore >= 50) {
        final relativePath = _extractRelativePath(fileUri.path, bestMatch.url);
        if (relativePath != null) {
          return buildWebDavPath(bestMatch.name, relativePath);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从文件 URL path 中提取相对于连接 base URL 的路径
  /// 返回 null 如果文件路径不是连接路径的子路径
  static String? _extractRelativePath(String filePath, String baseUrl) {
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null) return null;

    var basePath = baseUri.path.trim();
    if (basePath.isEmpty) basePath = '/';
    if (!basePath.endsWith('/')) basePath += '/';
    // 去掉重复斜杠
    basePath = basePath.replaceAll(RegExp(r'/+'), '/');
    var normalizedFilePath = filePath.replaceAll(RegExp(r'/+'), '/');

    if (normalizedFilePath.startsWith(basePath)) {
      var relative = normalizedFilePath.substring(basePath.length);
      if (!relative.startsWith('/')) relative = '/$relative';
      return relative;
    }

    // 文件路径可能与 base path 相同（base 不含末尾 / 的情况）
    final basePathNoTrailing = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    if (normalizedFilePath == basePathNoTrailing) {
      return '/';
    }

    return null;
  }

  /// 将旧的 SMB 代理 URL 转换为新格式
  /// 旧格式: http://127.0.0.1:33221/smb/stream?conn=connectionName&path=/path
  /// 新格式: smb://connectionName/path
  static String? migrateSmbPath(String oldPath) {
    if (isNewSmbPath(oldPath)) return oldPath;

    // 检查是否是旧格式的 SMB 代理 URL
    final uri = Uri.tryParse(oldPath);
    if (uri == null) return null;
    if (uri.path != '/smb/stream') return null;

    final connName = uri.queryParameters['conn']?.trim();
    final smbPath = uri.queryParameters['path']?.trim();
    if (connName == null || connName.isEmpty || smbPath == null) return null;

    return buildSmbPath(connName, smbPath);
  }

  /// 将任意旧格式路径迁移为新格式（如果适用）
  /// 返回迁移后的路径，如果不适用则返回原始路径
  static String migratePath(String filePath) {
    if (filePath.isEmpty) return filePath;
    // 已是新格式，直接返回
    if (isNewWebDavPath(filePath) || isNewSmbPath(filePath)) return filePath;

    // 尝试迁移 WebDAV 路径
    final webdavMigrated = migrateWebDavPath(filePath);
    if (webdavMigrated != null) return webdavMigrated;

    // 尝试迁移 SMB 路径
    final smbMigrated = migrateSmbPath(filePath);
    if (smbMigrated != null) return smbMigrated;

    return filePath;
  }

  /// 将新格式 WebDAV 路径解析为可播放的 HTTP URL
  /// 返回 null 如果找不到对应连接
  static String? resolveWebDavPathToUrl(String filePath) {
    final parsed = parseWebDavPath(filePath);
    if (parsed == null) return null;

    final connection =
        WebDAVService.instance.getConnection(parsed.connectionName);
    if (connection == null) return null;

    return WebDAVService.instance.getFileUrl(connection, parsed.relativePath);
  }

  /// 将新格式 SMB 路径解析为可播放的代理 URL
  /// 返回 null 如果找不到对应连接
  static String? resolveSmbPathToUrl(String filePath) {
    final parsed = parseSmbPath(filePath);
    if (parsed == null) return null;

    final connection = SMBService.instance.getConnection(parsed.connectionName);
    if (connection == null) return null;

    return SMBProxyService.instance
        .buildStreamUrl(connection, parsed.relativePath);
  }
}
