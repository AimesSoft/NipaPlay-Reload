
// lib/models/database/source_record.dart


class DbSourceRecord {
  const DbSourceRecord({
    required this.id,
    required this.sourceType,
    required this.url,
    this.username,
    this.password,
    this.metadataJson,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String sourceType;
  final String url;
  final String? username;
  final String? password;
  final String? metadataJson;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'source_type': sourceType,
        'url': url,
        'username': username,
        'password': password,
        'metadata_json': metadataJson,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DbSourceRecord.fromMap(Map<String, Object?> map) {
    return DbSourceRecord(
      id: map['id'] as String,
      sourceType: map['source_type'] as String,
      url: map['url'] as String,
      username: map['username'] as String?,
      password: map['password'] as String?,
      metadataJson: map['metadata_json'] as String?,
      createdAt: _parseDateTime(map['created_at']),
      updatedAt: _parseDateTime(map['updated_at']),
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
