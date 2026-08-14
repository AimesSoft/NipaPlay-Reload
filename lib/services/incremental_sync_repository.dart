import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:nipaplay/services/backup_category.dart';

typedef IncrementalSyncState = Map<String, Map<String, dynamic>>;

const int incrementalSyncFormatVersion = 1;
const String incrementalSyncManifestFile = 'manifest.version';

String backupCategoryWireName(BackupCategory category) => category.name;

BackupCategory? backupCategoryFromWireName(String value) {
  for (final category in BackupCategory.values) {
    if (category.name == value) return category;
  }
  return null;
}

class IncrementalSyncPatchEntry {
  const IncrementalSyncPatchEntry({
    required this.id,
    required this.file,
    required this.sha256,
    required this.size,
    required this.createdAt,
    required this.deviceId,
  });

  final String id;
  final String file;
  final String sha256;
  final int size;
  final DateTime createdAt;
  final String deviceId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'file': file,
        'sha256': sha256,
        'size': size,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
      };

  factory IncrementalSyncPatchEntry.fromJson(Map<String, dynamic> json) {
    return IncrementalSyncPatchEntry(
      id: json['id'] as String,
      file: json['file'] as String,
      sha256: json['sha256'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      deviceId: json['deviceId'] as String? ?? '',
    );
  }
}

class IncrementalSyncManifest {
  const IncrementalSyncManifest({
    required this.repositoryId,
    required this.snapshotVersion,
    required this.snapshotFile,
    required this.snapshotSha256,
    required this.snapshotPatchIds,
    required this.categories,
    required this.patches,
    required this.updatedAt,
  });

  final String repositoryId;
  final int snapshotVersion;
  final String snapshotFile;
  final String snapshotSha256;
  final Set<String> snapshotPatchIds;
  final Set<String> categories;
  final List<IncrementalSyncPatchEntry> patches;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'formatVersion': incrementalSyncFormatVersion,
        'repositoryId': repositoryId,
        'snapshot': {
          'version': snapshotVersion,
          'file': snapshotFile,
          'sha256': snapshotSha256,
          'includedPatchIds': snapshotPatchIds.toList()..sort(),
        },
        'categories': categories.toList()..sort(),
        'patches': patches.map((entry) => entry.toJson()).toList(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory IncrementalSyncManifest.fromJson(Map<String, dynamic> json) {
    final formatVersion = (json['formatVersion'] as num?)?.toInt() ?? 0;
    if (formatVersion > incrementalSyncFormatVersion || formatVersion < 1) {
      throw FormatException('不支持的同步仓库版本: $formatVersion');
    }
    final snapshot = Map<String, dynamic>.from(json['snapshot'] as Map);
    return IncrementalSyncManifest(
      repositoryId: json['repositoryId'] as String,
      snapshotVersion: (snapshot['version'] as num).toInt(),
      snapshotFile: snapshot['file'] as String,
      snapshotSha256: snapshot['sha256'] as String? ?? '',
      snapshotPatchIds:
          (snapshot['includedPatchIds'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet(),
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toSet(),
      patches: (json['patches'] as List<dynamic>? ?? const [])
          .map((value) => IncrementalSyncPatchEntry.fromJson(
                Map<String, dynamic>.from(value as Map),
              ))
          .toList(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  IncrementalSyncManifest copyWith({
    Set<String>? categories,
    List<IncrementalSyncPatchEntry>? patches,
    DateTime? updatedAt,
    int? snapshotVersion,
    String? snapshotFile,
    String? snapshotSha256,
    Set<String>? snapshotPatchIds,
  }) {
    return IncrementalSyncManifest(
      repositoryId: repositoryId,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      snapshotFile: snapshotFile ?? this.snapshotFile,
      snapshotSha256: snapshotSha256 ?? this.snapshotSha256,
      snapshotPatchIds: snapshotPatchIds ?? this.snapshotPatchIds,
      categories: categories ?? this.categories,
      patches: patches ?? this.patches,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class IncrementalSyncOperation {
  const IncrementalSyncOperation({
    required this.category,
    required this.key,
    required this.deleted,
    required this.value,
    required this.modifiedAt,
    required this.deviceId,
  });

  final String category;
  final String key;
  final bool deleted;
  final dynamic value;
  final DateTime modifiedAt;
  final String deviceId;

  Map<String, dynamic> toJson() => {
        'category': category,
        'key': key,
        'deleted': deleted,
        if (!deleted) 'value': value,
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
      };

  factory IncrementalSyncOperation.fromJson(Map<String, dynamic> json) {
    return IncrementalSyncOperation(
      category: json['category'] as String,
      key: json['key'] as String,
      deleted: json['deleted'] as bool? ?? false,
      value: json['value'],
      modifiedAt: DateTime.parse(json['modifiedAt'] as String).toUtc(),
      deviceId: json['deviceId'] as String? ?? '',
    );
  }
}

class IncrementalSyncPatch {
  const IncrementalSyncPatch({
    required this.id,
    required this.snapshotVersion,
    required this.createdAt,
    required this.deviceId,
    required this.operations,
  });

  final String id;
  final int snapshotVersion;
  final DateTime createdAt;
  final String deviceId;
  final List<IncrementalSyncOperation> operations;

  Map<String, dynamic> toJson() => {
        'formatVersion': incrementalSyncFormatVersion,
        'id': id,
        'snapshotVersion': snapshotVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'operations':
            operations.map((operation) => operation.toJson()).toList(),
      };

  factory IncrementalSyncPatch.fromJson(Map<String, dynamic> json) {
    final formatVersion = (json['formatVersion'] as num?)?.toInt() ?? 0;
    if (formatVersion != incrementalSyncFormatVersion) {
      throw FormatException('不支持的补丁版本: $formatVersion');
    }
    return IncrementalSyncPatch(
      id: json['id'] as String,
      snapshotVersion: (json['snapshotVersion'] as num).toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      deviceId: json['deviceId'] as String? ?? '',
      operations: (json['operations'] as List<dynamic>? ?? const [])
          .map((value) => IncrementalSyncOperation.fromJson(
                Map<String, dynamic>.from(value as Map),
              ))
          .toList(),
    );
  }
}

class IncrementalSyncCodec {
  const IncrementalSyncCodec._();

  static IncrementalSyncState flattenBackup(
    Map<String, dynamic> backup,
    Set<BackupCategory> categories,
  ) {
    final state = <String, Map<String, dynamic>>{};
    for (final category in categories) {
      final name = backupCategoryWireName(category);
      switch (category) {
        case BackupCategory.preferences:
          final preferences = _asStringMap(backup[name]);
          state[name] = _asStringMap(preferences['settings']);
        case BackupCategory.mediaLibraries:
        case BackupCategory.accounts:
          state[name] = _asStringMap(backup[name]);
        case BackupCategory.watchHistory:
        case BackupCategory.episodeMatches:
          final values = backup[name] as List<dynamic>? ?? const [];
          final records = <String, dynamic>{};
          for (final raw in values) {
            final record = _asStringMap(raw);
            final key = _recordKey(record);
            records[key] = record;
          }
          state[name] = records;
      }
    }
    return state;
  }

  static Map<String, dynamic> inflateState(
    IncrementalSyncState state, {
    Iterable<String>? onlyCategories,
  }) {
    final included = onlyCategories?.toSet() ?? state.keys.toSet();
    final backup = <String, dynamic>{
      'version': 2,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'appVersion': '',
    };
    for (final entry in state.entries) {
      if (!included.contains(entry.key)) continue;
      final category = backupCategoryFromWireName(entry.key);
      switch (category) {
        case BackupCategory.preferences:
          backup[entry.key] = {'settings': entry.value};
        case BackupCategory.watchHistory:
        case BackupCategory.episodeMatches:
          backup[entry.key] = entry.value.values.toList();
        case BackupCategory.mediaLibraries:
        case BackupCategory.accounts:
          backup[entry.key] = entry.value;
        case null:
          break;
      }
    }
    return backup;
  }

  static List<IncrementalSyncOperation> diff({
    required IncrementalSyncState previous,
    required IncrementalSyncState current,
    required DateTime modifiedAt,
    required String deviceId,
  }) {
    final operations = <IncrementalSyncOperation>[];
    final categoryNames = <String>{...previous.keys, ...current.keys};
    for (final category in categoryNames) {
      final before = previous[category] ?? const <String, dynamic>{};
      final after = current[category] ?? const <String, dynamic>{};
      final keys = <String>{...before.keys, ...after.keys}.toList()..sort();
      for (final key in keys) {
        final hadValue = before.containsKey(key);
        final hasValue = after.containsKey(key);
        if (hadValue && !hasValue) {
          operations.add(IncrementalSyncOperation(
            category: category,
            key: key,
            deleted: true,
            value: null,
            modifiedAt: modifiedAt,
            deviceId: deviceId,
          ));
        } else if (hasValue &&
            (!hadValue ||
                contentHash(before[key]) != contentHash(after[key]))) {
          operations.add(IncrementalSyncOperation(
            category: category,
            key: key,
            deleted: false,
            value: after[key],
            modifiedAt: modifiedAt,
            deviceId: deviceId,
          ));
        }
      }
    }
    return operations;
  }

  static IncrementalSyncState applyOperations(
    IncrementalSyncState source,
    Iterable<IncrementalSyncOperation> operations,
  ) {
    final result = cloneState(source);
    for (final operation in operations) {
      final values = result.putIfAbsent(operation.category, () => {});
      if (operation.deleted) {
        values.remove(operation.key);
      } else {
        values[operation.key] = operation.value;
      }
    }
    return result;
  }

  static IncrementalSyncState cloneState(IncrementalSyncState state) {
    return state.map(
      (category, values) =>
          MapEntry(category, Map<String, dynamic>.from(values)),
    );
  }

  static Map<String, Map<String, String>> buildHashIndex(
    IncrementalSyncState state,
  ) {
    return state.map(
      (category, values) => MapEntry(
        category,
        values.map((key, value) => MapEntry(key, contentHash(value))),
      ),
    );
  }

  static String contentHash(dynamic value) {
    return sha256.convert(utf8.encode(canonicalJson(value))).toString();
  }

  static String canonicalJson(dynamic value) =>
      jsonEncode(_canonicalize(value));

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  static Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String _recordKey(Map<String, dynamic> record) {
    final path = record['filePath']?.toString();
    if (path != null && path.isNotEmpty) return path;
    final videoHash = record['videoHash']?.toString();
    if (videoHash != null && videoHash.isNotEmpty) return 'hash:$videoHash';
    return 'record:${contentHash(record)}';
  }
}

class IncrementalSyncCache {
  const IncrementalSyncCache({
    required this.repositoryId,
    required this.snapshotVersion,
    required this.snapshotSha256,
    required this.appliedPatchIds,
    required this.state,
  });

  final String repositoryId;
  final int snapshotVersion;
  final String snapshotSha256;
  final Set<String> appliedPatchIds;
  final IncrementalSyncState state;

  Map<String, dynamic> toJson() => {
        'formatVersion': incrementalSyncFormatVersion,
        'repositoryId': repositoryId,
        'snapshotVersion': snapshotVersion,
        'snapshotSha256': snapshotSha256,
        'appliedPatchIds': appliedPatchIds.toList()..sort(),
        'state': state,
      };

  factory IncrementalSyncCache.fromJson(Map<String, dynamic> json) {
    final rawState =
        Map<String, dynamic>.from(json['state'] as Map? ?? const {});
    return IncrementalSyncCache(
      repositoryId: json['repositoryId'] as String? ?? '',
      snapshotVersion: (json['snapshotVersion'] as num?)?.toInt() ?? 0,
      snapshotSha256: json['snapshotSha256'] as String? ?? '',
      appliedPatchIds: (json['appliedPatchIds'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toSet(),
      state: rawState.map(
        (category, values) => MapEntry(
          category,
          Map<String, dynamic>.from(values as Map),
        ),
      ),
    );
  }
}
