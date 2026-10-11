class IncrementalSyncWebDavConnections {
  const IncrementalSyncWebDavConnections._();

  static const String keyPrefix = 'webdavConnection:';
  static const String tombstoneMarker = '_syncDeleted';

  static String keyFor(String connectionId) => '$keyPrefix$connectionId';

  static bool isConnectionKey(String key) => key.startsWith(keyPrefix);

  static String? connectionIdFromKey(String key) {
    if (!isConnectionKey(key)) return null;
    final id = key.substring(keyPrefix.length).trim();
    return id.isEmpty ? null : id;
  }

  static bool isTombstone(dynamic value) =>
      value is Map && value[tombstoneMarker] == true;

  static String tombstoneDeletedAt(dynamic value) {
    if (value is Map) {
      final deletedAt = value['deletedAt']?.toString().trim();
      if (deletedAt?.isNotEmpty == true) return deletedAt!;
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        .toIso8601String();
  }

  static Map<String, dynamic> tombstone({
    required String connectionId,
    required String deletedAt,
  }) {
    return {
      'id': connectionId,
      tombstoneMarker: true,
      'deletedAt': deletedAt,
    };
  }
}
