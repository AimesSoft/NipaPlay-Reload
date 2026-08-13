import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:nipaplay/services/incremental_sync_repository.dart';
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

IncrementalSyncState _stateFromJsonMap(Map<String, dynamic> raw) {
  return raw.map(
    (category, values) => MapEntry(
      category,
      Map<String, dynamic>.from(values as Map),
    ),
  );
}
