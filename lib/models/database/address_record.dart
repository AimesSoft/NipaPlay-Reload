
// lib/models/database/address_record.dart


class DbAddressRecord {
  const DbAddressRecord({
    required this.sourceId,
    required this.relativePath,
    this.fileHash,
    this.lastSyncedAt,
  });

  final String sourceId;
  final String relativePath;
  final String? fileHash;
  final DateTime? lastSyncedAt;

  Map<String, Object?> toMap() => {
        'source_id': sourceId,
        'relative_path': relativePath,
        'file_hash': fileHash,
        'last_synced_at': (lastSyncedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbAddressRecord.fromMap(Map<String, Object?> map) {
    return DbAddressRecord(
      sourceId: map['source_id'] as String,
      relativePath: map['relative_path'] as String,
      fileHash: map['file_hash'] as String?,
      lastSyncedAt: _parseDateTime(map['last_synced_at']),
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
