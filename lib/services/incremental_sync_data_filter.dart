import 'package:nipaplay/services/backup_category.dart';
import 'package:nipaplay/services/incremental_sync_repository.dart';
import 'package:nipaplay/services/incremental_sync_webdav_connections.dart';
import 'package:nipaplay/services/webdav_service.dart';

/// Removes device-bound local media data from the cross-device repository.
///
/// Full backups intentionally do not use this filter. It applies only to
/// WebDAV incremental synchronization, where a local filesystem path and its
/// scan metadata are meaningless on another device.
class IncrementalSyncDataFilter {
  const IncrementalSyncDataFilter._();

  static Map<String, dynamic> sanitizeBackup(
    Map<String, dynamic> backup, {
    Map<String, String> webDavConnectionTombstones = const {},
  }) {
    final result = Map<String, dynamic>.from(backup);

    final mediaLibraries = backup[BackupCategory.mediaLibraries.name];
    final localLibraryRoots = _localLibraryRoots(mediaLibraries);
    if (mediaLibraries is Map) {
      final sanitizedMediaLibraries = Map<String, dynamic>.from(mediaLibraries)
        ..remove('localMediaLibraries');
      _normalizeWebDavConnections(
        sanitizedMediaLibraries,
        tombstones: webDavConnectionTombstones,
      );
      result[BackupCategory.mediaLibraries.name] = sanitizedMediaLibraries;
    }

    for (final category in const [
      BackupCategory.watchHistory,
      BackupCategory.episodeMatches,
    ]) {
      final records = backup[category.name];
      if (records is List) {
        result[category.name] = records
            .where((record) =>
                record is Map &&
                !isDeviceLocalRecord(record, localLibraryRoots))
            .toList();
      }
    }
    return result;
  }

  static IncrementalSyncState sanitizeState(IncrementalSyncState state) {
    final result = IncrementalSyncCodec.cloneState(state);
    final localLibraryRoots =
        _localLibraryRoots(state[BackupCategory.mediaLibraries.name]);
    final mediaLibraries = result[BackupCategory.mediaLibraries.name];
    mediaLibraries?.remove('localMediaLibraries');
    if (mediaLibraries != null) {
      _normalizeWebDavConnections(mediaLibraries);
    }
    for (final category in const [
      BackupCategory.watchHistory,
      BackupCategory.episodeMatches,
    ]) {
      result[category.name]?.removeWhere(
        (_, record) =>
            record is Map && isDeviceLocalRecord(record, localLibraryRoots),
      );
    }
    return result;
  }

  static void _normalizeWebDavConnections(
    Map<String, dynamic> mediaLibraries, {
    Map<String, String> tombstones = const {},
  }) {
    final rawConnections = mediaLibraries.remove('webdavConnections');
    if (rawConnections is List) {
      for (final rawConnection in rawConnections) {
        if (rawConnection is! Map) continue;
        final connection = WebDAVConnection.fromJson(
          Map<String, dynamic>.from(rawConnection),
        ).toJson()
          ..remove('isConnected');
        final id = connection['id']?.toString().trim();
        if (id == null || id.isEmpty) continue;
        mediaLibraries.putIfAbsent(
          IncrementalSyncWebDavConnections.keyFor(id),
          () => connection,
        );
      }
    }

    for (final key in mediaLibraries.keys
        .where(IncrementalSyncWebDavConnections.isConnectionKey)
        .toList(growable: false)) {
      final value = mediaLibraries[key];
      if (value is Map &&
          !IncrementalSyncWebDavConnections.isTombstone(value)) {
        mediaLibraries[key] = Map<String, dynamic>.from(value)
          ..remove('isConnected');
      }
    }

    for (final entry in tombstones.entries) {
      final key = IncrementalSyncWebDavConnections.keyFor(entry.key);
      if (mediaLibraries.containsKey(key)) continue;
      mediaLibraries[key] = IncrementalSyncWebDavConnections.tombstone(
        connectionId: entry.key,
        deletedAt: entry.value,
      );
    }
  }

  static bool isDeviceLocalRecord(
    Map<dynamic, dynamic> record, [
    Iterable<String> localLibraryRoots = const [],
  ]) {
    final filePath = record['filePath']?.toString().trim() ?? '';
    if (filePath.isEmpty) return false;
    if (_isRemoteMediaPath(filePath)) return false;

    // Current exports carry this flag for scan-created records. The path
    // fallback also catches old episodeMatches entries that predate the flag.
    if (record['isFromScan'] == true) return true;
    return localLibraryRoots.any(
      (root) => _isPathInsideLibrary(filePath, root),
    );
  }

  static bool _isRemoteMediaPath(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('webdav://') ||
        lower.startsWith('dav://') ||
        lower.startsWith('smb://') ||
        lower.startsWith('jellyfin://') ||
        lower.startsWith('emby://') ||
        lower.startsWith('dandanplay://')) {
      return true;
    }
    final uri = Uri.tryParse(filePath);
    return uri != null &&
        uri.hasScheme &&
        uri.scheme.length > 1 &&
        uri.scheme.toLowerCase() != 'file' &&
        uri.scheme.toLowerCase() != 'content';
  }

  static List<String> _localLibraryRoots(dynamic mediaLibraries) {
    if (mediaLibraries is! Map) return const [];
    final roots = mediaLibraries['localMediaLibraries'];
    if (roots is! List) return const [];
    return roots
        .map((root) => root.toString().trim())
        .where((root) => root.isNotEmpty)
        .toList();
  }

  static bool _isPathInsideLibrary(String filePath, String libraryRoot) {
    String normalize(String value) {
      var normalized = value.trim().replaceAll('\\', '/');
      while (normalized.length > 1 && normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      if (RegExp(r'^[a-zA-Z]:/').hasMatch(normalized)) {
        normalized = normalized.toLowerCase();
      }
      return normalized;
    }

    final path = normalize(filePath);
    final root = normalize(libraryRoot);
    return path == root || path.startsWith('$root/');
  }
}
