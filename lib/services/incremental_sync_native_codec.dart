import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:nipaplay/services/incremental_sync_repository.dart';
import 'package:nipaplay/services/backup_category.dart';
import 'package:nipaplay/src/rust/api/incremental_sync.dart' as rust_sync;
import 'package:nipaplay/src/rust/rust_init.dart';

class IncrementalSyncEncodedBlob {
  const IncrementalSyncEncodedBlob({
    required this.bytes,
    required this.sha256,
    required this.usedRust,
  });

  final Uint8List bytes;
  final String sha256;
  final bool usedRust;
}

class IncrementalSyncNativePatchInput {
  const IncrementalSyncNativePatchInput({
    required this.bytes,
    required this.expectedSha256,
    required this.expectedId,
  });

  final Uint8List bytes;
  final String expectedSha256;
  final String expectedId;
}

class IncrementalSyncNativePatchResult {
  const IncrementalSyncNativePatchResult({
    required this.state,
    required this.appliedPatchIds,
    required this.usedRust,
  });

  final IncrementalSyncState state;
  final List<String> appliedPatchIds;
  final bool usedRust;
}

class FullBackupNativeRestorePlan {
  const FullBackupNativeRestorePlan({
    required this.version,
    required this.timestamp,
    required this.appVersion,
    required this.preferencesJson,
    required this.mediaLibrariesJson,
    required this.accountsJson,
    required this.watchHistoryBatches,
    required this.episodeMatchBatches,
    required this.invalidWatchHistoryCount,
    required this.invalidEpisodeMatchCount,
    required this.usedRust,
  });

  final int version;
  final String timestamp;
  final String appVersion;
  final Uint8List preferencesJson;
  final Uint8List mediaLibrariesJson;
  final Uint8List accountsJson;
  final List<Uint8List> watchHistoryBatches;
  final List<Uint8List> episodeMatchBatches;
  final int invalidWatchHistoryCount;
  final int invalidEpisodeMatchCount;
  final bool usedRust;
}

/// Native acceleration for the pure, CPU-heavy portion of synchronization.
///
/// Platform storage and restoration remain in Dart. Every method has a v1
/// compatible Dart fallback so unsupported targets do not lose sync support.
class IncrementalSyncNativeCodec {
  const IncrementalSyncNativeCodec._();

  static bool _rustUnavailable = kIsWeb;
  static bool _reportedFallback = false;

  static Future<IncrementalSyncEncodedBlob> canonicalizeMap(
    Map<String, dynamic> value,
  ) =>
      encodeMap(value);

  static Future<IncrementalSyncEncodedBlob> encodeMap(
    Map<String, dynamic> value, {
    bool pretty = false,
  }) async {
    final plainBytes = await compute(_encodePlainJson, value);
    if (await _canUseRust()) {
      final result = await rust_sync.syncCanonicalizeJson(
        input: plainBytes,
        pretty: pretty,
      );
      return IncrementalSyncEncodedBlob(
        bytes: result.bytes,
        sha256: result.sha256,
        usedRust: true,
      );
    }
    final canonicalBytes = await compute(
      _canonicalizeJsonBytes,
      (input: plainBytes, pretty: pretty),
    );
    return IncrementalSyncEncodedBlob(
      bytes: canonicalBytes,
      sha256: sha256.convert(canonicalBytes).toString(),
      usedRust: false,
    );
  }

  /// Parses a JSON object through Rust and materializes the validated result
  /// on a background Dart isolate. This keeps malformed/very large backup
  /// parsing away from the UI isolate while retaining the Dart data model used
  /// by platform restoration code.
  static Future<Map<String, dynamic>> decodeJsonMap(Uint8List bytes) async {
    if (await _canUseRust()) {
      final result = await rust_sync.syncCanonicalizeJson(
        input: bytes,
        pretty: false,
      );
      return compute(_decodeJsonMap, result.bytes);
    }
    return compute(_decodeJsonMap, bytes);
  }

  static Future<List<dynamic>> decodeJsonList(Uint8List bytes) =>
      compute(_decodeJsonList, bytes);

  /// Parses and filters a full backup in Rust. Large history collections cross
  /// the FFI boundary in bounded byte batches instead of as thousands of Dart
  /// objects, so the UI isolate only materializes the batch being committed.
  static Future<FullBackupNativeRestorePlan> prepareFullBackupRestore({
    required Uint8List bytes,
    required Set<BackupCategory> categories,
    int batchSize = 500,
  }) async {
    final request = (
      input: bytes,
      includePreferences: categories.contains(BackupCategory.preferences),
      includeMediaLibraries: categories.contains(BackupCategory.mediaLibraries),
      includeWatchHistory: categories.contains(BackupCategory.watchHistory),
      includeEpisodeMatches: categories.contains(BackupCategory.episodeMatches),
      includeAccounts: categories.contains(BackupCategory.accounts),
      batchSize: batchSize,
    );
    if (await _canUseRust()) {
      final result = await rust_sync.backupPrepareRestore(
        input: request.input,
        includePreferences: request.includePreferences,
        includeMediaLibraries: request.includeMediaLibraries,
        includeWatchHistory: request.includeWatchHistory,
        includeEpisodeMatches: request.includeEpisodeMatches,
        includeAccounts: request.includeAccounts,
        batchSize: request.batchSize,
      );
      return FullBackupNativeRestorePlan(
        version: result.version,
        timestamp: result.timestamp,
        appVersion: result.appVersion,
        preferencesJson: result.preferencesJson,
        mediaLibrariesJson: result.mediaLibrariesJson,
        accountsJson: result.accountsJson,
        watchHistoryBatches: result.watchHistoryBatches,
        episodeMatchBatches: result.episodeMatchBatches,
        invalidWatchHistoryCount: result.invalidWatchHistoryCount,
        invalidEpisodeMatchCount: result.invalidEpisodeMatchCount,
        usedRust: true,
      );
    }
    final fallback = await compute(_prepareFullBackupRestoreDart, request);
    return FullBackupNativeRestorePlan(
      version: fallback['version'] as int,
      timestamp: fallback['timestamp'] as String,
      appVersion: fallback['appVersion'] as String,
      preferencesJson: fallback['preferencesJson'] as Uint8List,
      mediaLibrariesJson: fallback['mediaLibrariesJson'] as Uint8List,
      accountsJson: fallback['accountsJson'] as Uint8List,
      watchHistoryBatches:
          (fallback['watchHistoryBatches'] as List).cast<Uint8List>(),
      episodeMatchBatches:
          (fallback['episodeMatchBatches'] as List).cast<Uint8List>(),
      invalidWatchHistoryCount: fallback['invalidWatchHistoryCount'] as int,
      invalidEpisodeMatchCount: fallback['invalidEpisodeMatchCount'] as int,
      usedRust: false,
    );
  }

  static Future<List<IncrementalSyncOperation>> diff({
    required IncrementalSyncState previous,
    required IncrementalSyncState current,
    required DateTime modifiedAt,
    required String deviceId,
  }) async {
    if (await _canUseRust()) {
      final encodedStates = await Future.wait([
        compute(_encodePlainJson, previous),
        compute(_encodePlainJson, current),
      ]);
      final encodedOperations = await rust_sync.syncDiffStates(
        previousJson: encodedStates[0],
        currentJson: encodedStates[1],
        modifiedAt: modifiedAt.toUtc().toIso8601String(),
        deviceId: deviceId,
      );
      final decoded = await compute(_decodeJsonList, encodedOperations);
      return decoded
          .map((value) => IncrementalSyncOperation.fromJson(
                Map<String, dynamic>.from(value as Map),
              ))
          .toList();
    }
    return IncrementalSyncCodec.diff(
      previous: previous,
      current: current,
      modifiedAt: modifiedAt,
      deviceId: deviceId,
    );
  }

  static Future<IncrementalSyncState> decodeSnapshotState({
    required Uint8List snapshotBytes,
    required String expectedSha256,
    required String expectedRepositoryId,
    required int expectedSnapshotVersion,
  }) async {
    if (await _canUseRust()) {
      final result = await rust_sync.syncDecodeSnapshotState(
        snapshotBytes: snapshotBytes,
        expectedSha256: expectedSha256,
        expectedRepositoryId: expectedRepositoryId,
        expectedSnapshotVersion: expectedSnapshotVersion,
      );
      return _stateFromJsonMap(await compute(
        _decodeJsonMap,
        result.stateJson,
      ));
    }

    final actualHash = sha256.convert(snapshotBytes).toString();
    if (expectedSha256.isNotEmpty && actualHash != expectedSha256) {
      throw const FormatException('远端同步对象校验失败');
    }
    final snapshot = await compute(_decodeJsonMap, snapshotBytes);
    if (snapshot['repositoryId'] != expectedRepositoryId ||
        snapshot['snapshotVersion'] != expectedSnapshotVersion) {
      throw const FormatException('基准快照与 manifest.version 不匹配');
    }
    return _stateFromJsonMap(
      Map<String, dynamic>.from(snapshot['state'] as Map? ?? const {}),
    );
  }

  static Future<IncrementalSyncNativePatchResult> applyPatchChain({
    required IncrementalSyncState state,
    required List<IncrementalSyncNativePatchInput> patches,
    required int maximumSnapshotVersion,
  }) async {
    if (patches.isEmpty) {
      return IncrementalSyncNativePatchResult(
        state: IncrementalSyncCodec.cloneState(state),
        appliedPatchIds: const [],
        usedRust: false,
      );
    }
    if (await _canUseRust()) {
      final stateJson = await compute(_encodePlainJson, state);
      final result = await rust_sync.syncApplyPatchChain(
        stateJson: stateJson,
        patches: patches
            .map((patch) => rust_sync.RustSyncPatchInput(
                  bytes: patch.bytes,
                  expectedSha256: patch.expectedSha256,
                  expectedId: patch.expectedId,
                ))
            .toList(),
        maximumSnapshotVersion: maximumSnapshotVersion,
      );
      return IncrementalSyncNativePatchResult(
        state: _stateFromJsonMap(await compute(
          _decodeJsonMap,
          result.stateJson,
        )),
        appliedPatchIds: result.appliedPatchIds,
        usedRust: true,
      );
    }

    var nextState = IncrementalSyncCodec.cloneState(state);
    final appliedIds = <String>[];
    for (final input in patches) {
      if (input.expectedSha256.isNotEmpty &&
          sha256.convert(input.bytes).toString() != input.expectedSha256) {
        throw const FormatException('远端同步对象校验失败');
      }
      final patch = IncrementalSyncPatch.fromJson(
        await compute(_decodeJsonMap, input.bytes),
      );
      if (input.expectedId.isNotEmpty && patch.id != input.expectedId) {
        throw const FormatException('补丁索引与文件内容不匹配');
      }
      if (patch.snapshotVersion > maximumSnapshotVersion) continue;
      nextState = IncrementalSyncCodec.applyOperations(
        nextState,
        patch.operations,
      );
      appliedIds.add(patch.id);
    }
    return IncrementalSyncNativePatchResult(
      state: nextState,
      appliedPatchIds: appliedIds,
      usedRust: false,
    );
  }

  static Future<bool> _canUseRust() async {
    if (_rustUnavailable) return false;
    try {
      await ensureRustInitialized();
      return true;
    } catch (error) {
      _disableRust(error);
      return false;
    }
  }

  static void _disableRust(Object error) {
    _rustUnavailable = true;
    _reportRustCallFallback(error);
  }

  static void _reportRustCallFallback(Object error) {
    if (_reportedFallback) return;
    _reportedFallback = true;
    debugPrint('Rust 增量同步编解码不可用，回退 Dart 实现: $error');
  }
}

Uint8List _encodePlainJson(Map<String, dynamic> value) {
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}

Uint8List _canonicalizeJsonBytes(
  ({Uint8List input, bool pretty}) request,
) {
  final value = jsonDecode(utf8.decode(request.input));
  final encoded = request.pretty
      ? const JsonEncoder.withIndent('  ').convert(value)
      : IncrementalSyncCodec.canonicalJson(value);
  return Uint8List.fromList(utf8.encode(encoded));
}

Map<String, dynamic> _decodeJsonMap(Uint8List input) {
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(input)) as Map);
}

List<dynamic> _decodeJsonList(Uint8List input) {
  return jsonDecode(utf8.decode(input)) as List<dynamic>;
}

Map<String, dynamic> _prepareFullBackupRestoreDart(
  ({
    Uint8List input,
    bool includePreferences,
    bool includeMediaLibraries,
    bool includeWatchHistory,
    bool includeEpisodeMatches,
    bool includeAccounts,
    int batchSize,
  }) request,
) {
  final root = _decodeJsonMap(request.input);
  final version = (root['version'] as num?)?.toInt() ?? 0;
  if (version > 2) {
    throw FormatException('不支持的备份格式版本: $version');
  }
  Uint8List objectBytes(String key, bool selected) {
    if (!selected || !root.containsKey(key)) return Uint8List(0);
    final value = root[key];
    if (value is! Map) throw FormatException('备份字段 $key 必须是 JSON 对象');
    return Uint8List.fromList(utf8.encode(jsonEncode(value)));
  }

  ({List<Uint8List> batches, int invalid}) arrayBatches(
    String key,
    bool selected,
    bool Function(Map<String, dynamic>) valid,
  ) {
    if (!selected || !root.containsKey(key)) return (batches: [], invalid: 0);
    final value = root[key];
    if (value is! List) throw FormatException('备份字段 $key 必须是 JSON 数组');
    final records = <Map<String, dynamic>>[];
    var invalid = 0;
    for (final raw in value) {
      if (raw is Map) {
        final record = Map<String, dynamic>.from(raw);
        if (valid(record)) {
          records.add(record);
          continue;
        }
      }
      invalid++;
    }
    final size = request.batchSize.clamp(1, 2000);
    final batches = <Uint8List>[];
    if (records.isEmpty && value.isEmpty) {
      batches.add(Uint8List.fromList(const [91, 93]));
    }
    for (var offset = 0; offset < records.length; offset += size) {
      final end = (offset + size).clamp(0, records.length);
      batches.add(Uint8List.fromList(
        utf8.encode(jsonEncode(records.sublist(offset, end))),
      ));
    }
    return (batches: batches, invalid: invalid);
  }

  final history = arrayBatches(
    'watchHistory',
    request.includeWatchHistory,
    (record) =>
        record['filePath'] is String &&
        (record['filePath'] as String).isNotEmpty &&
        record['lastWatchTime'] is String,
  );
  final matches = arrayBatches(
    'episodeMatches',
    request.includeEpisodeMatches,
    (record) =>
        record['filePath'] is String &&
        (record['filePath'] as String).isNotEmpty &&
        record['animeId'] is num &&
        record['episodeId'] is num,
  );
  return {
    'version': version,
    'timestamp': root['timestamp'] as String? ?? '',
    'appVersion': root['appVersion'] as String? ?? '',
    'preferencesJson': objectBytes('preferences', request.includePreferences),
    'mediaLibrariesJson':
        objectBytes('mediaLibraries', request.includeMediaLibraries),
    'accountsJson': objectBytes('accounts', request.includeAccounts),
    'watchHistoryBatches': history.batches,
    'episodeMatchBatches': matches.batches,
    'invalidWatchHistoryCount': history.invalid,
    'invalidEpisodeMatchCount': matches.invalid,
  };
}

IncrementalSyncState _stateFromJsonMap(Map<String, dynamic> raw) {
  return raw.map(
    (category, values) => MapEntry(
      category,
      Map<String, dynamic>.from(values as Map),
    ),
  );
}
