import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/full_backup_service.dart';
import 'package:nipaplay/services/incremental_sync_native_codec.dart';
import 'package:nipaplay/services/incremental_sync_data_filter.dart';
import 'package:nipaplay/services/incremental_sync_repository.dart';
import 'package:nipaplay/services/incremental_sync_transport.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';

enum AutoSyncPhase { idle, pulling, merging, pushing, complete, failed }

class AutoSyncRunResult {
  const AutoSyncRunResult({
    required this.downloadedPatches,
    required this.uploadedOperations,
    required this.restoredOperations,
    required this.createdRepository,
  });

  final int downloadedPatches;
  final int uploadedOperations;
  final int restoredOperations;
  final bool createdRepository;
}

typedef IncrementalSyncTransportFactory = IncrementalSyncTransport Function({
  required String serverUrl,
  required String username,
  required String password,
});
typedef AutoSyncRunner = Future<AutoSyncRunResult> Function();

class AutoSyncService extends ChangeNotifier {
  static const int _patchesBeforeSnapshotCompaction = 64;
  static const int _snapshotGenerationsToKeep = 2;
  static const int _patchCleanupBatchSize = 4;
  static const Duration _defaultLocalChangeDebounce = Duration(seconds: 45);

  AutoSyncService._({
    IncrementalSyncTransportFactory? transportFactory,
    AutoSyncRunner? syncRunner,
    Duration localChangeDebounce = _defaultLocalChangeDebounce,
  })  : _syncRunner = syncRunner,
        _localChangeDebounce = localChangeDebounce,
        _transportFactory = transportFactory ??
            (({
              required serverUrl,
              required username,
              required password,
            }) =>
                WebDavIncrementalSyncTransport(
                  serverUrl: serverUrl,
                  username: username,
                  password: password,
                ));

  @visibleForTesting
  AutoSyncService.forTesting({
    required IncrementalSyncTransportFactory transportFactory,
    AutoSyncRunner? syncRunner,
    Duration localChangeDebounce = _defaultLocalChangeDebounce,
  }) : this._(
          transportFactory: transportFactory,
          syncRunner: syncRunner,
          localChangeDebounce: localChangeDebounce,
        );

  static AutoSyncService? _instance;
  static AutoSyncService get instance => _instance ??= AutoSyncService._();

  final IncrementalSyncTransportFactory _transportFactory;
  final AutoSyncRunner? _syncRunner;
  final Duration _localChangeDebounce;
  final FullBackupService _backupService = FullBackupService();

  Timer? _syncTimer;
  Timer? _localChangeTimer;
  Future<AutoSyncRunResult>? _activeSync;
  bool _isInitialized = false;
  bool _isSyncing = false;
  AutoSyncPhase _phase = AutoSyncPhase.idle;
  String? _lastError;
  int _completedRunCount = 0;

  bool get isSyncing => _isSyncing;
  AutoSyncPhase get phase => _phase;
  String? get lastError => _lastError;
  int get completedRunCount => _completedRunCount;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    if (!await AutoSyncSettings.isEnabled()) return;
    if (!await AutoSyncSettings.hasWebDavConfiguration()) {
      await AutoSyncSettings.setEnabled(false);
      return;
    }
    await _startAutoSync();
    // Repository parsing and restoration must never extend app startup.
    unawaited(_ignoreResult(_performSync()));
  }

  Future<void> enable() async {
    if (!await AutoSyncSettings.hasWebDavConfiguration()) {
      throw StateError('请先配置 WebDAV 服务器');
    }
    await AutoSyncSettings.setEnabled(true);
    await _startAutoSync();
    await _performSync();
  }

  Future<void> disable() async {
    await AutoSyncSettings.setEnabled(false);
    _stopAutoSync();
  }

  Future<bool> isEnabled() => AutoSyncSettings.isEnabled();

  Future<String?> getSyncPath() => AutoSyncSettings.getSyncPath();

  Future<AutoSyncRunResult> manualSync() => _performSync();

  Future<void> scheduleSyncAfterLocalChange() async {
    if (!await _shouldSyncOnRecordChange()) return;
    _localChangeTimer?.cancel();
    _localChangeTimer = Timer(_localChangeDebounce, () {
      _localChangeTimer = null;
      unawaited(_ignoreResult(_performSync()));
    });
  }

  Future<void> syncOnPlaybackEnd() async {
    if (!await _shouldSyncOnRecordChange()) return;
    final lastSyncAt = await AutoSyncSettings.getLastSyncAt();
    if (lastSyncAt != null &&
        DateTime.now().difference(lastSyncAt) <= const Duration(minutes: 2)) {
      return;
    }
    await _performSync();
  }

  Future<bool> _shouldSyncOnRecordChange() async {
    if (!await AutoSyncSettings.isEnabled() ||
        !await AutoSyncSettings.getSyncOnRecordChange()) {
      return false;
    }
    return (await AutoSyncSettings.getCategories())
        .contains(BackupCategory.watchHistory);
  }

  Future<void> reloadSchedule() async {
    if (await AutoSyncSettings.isEnabled()) {
      await _startAutoSync();
    }
  }

  Future<bool> testConnection({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final transport = _transportFactory(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
    final manifestBytes = await transport.read(
      _remoteJoin(remotePath, incrementalSyncManifestFile),
    );
    if (manifestBytes != null) return true;
    await transport.ensureDirectory(remotePath);
    await transport.listFileNames(remotePath);
    return true;
  }

  Future<void> _startAutoSync() async {
    _stopAutoSync();
    final interval = await AutoSyncSettings.getIntervalMinutes();
    _syncTimer = Timer.periodic(Duration(minutes: interval), (_) {
      unawaited(_ignoreResult(_performSync()));
    });
    debugPrint('增量同步定时器已启动: 每 $interval 分钟');
  }

  void _stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
  }

  Future<AutoSyncRunResult> _performSync() async {
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
    final active = _activeSync;
    if (active != null) return active;
    final future = _performSyncOnce();
    _activeSync = future;
    try {
      return await future;
    } finally {
      if (identical(_activeSync, future)) _activeSync = null;
    }
  }

  Future<AutoSyncRunResult> _performSyncOnce() async {
    if (!await AutoSyncSettings.isEnabled()) {
      throw StateError('自动同步未启用');
    }

    _setPhase(AutoSyncPhase.pulling);
    _isSyncing = true;
    notifyListeners();
    try {
      final result = await (_syncRunner?.call() ?? _synchronizeRepository());
      await AutoSyncSettings.recordSyncSuccess(DateTime.now());
      _lastError = null;
      _completedRunCount++;
      _setPhase(AutoSyncPhase.complete);
      return result;
    } catch (error, stackTrace) {
      _lastError = error.toString();
      await AutoSyncSettings.recordSyncError(error);
      _setPhase(AutoSyncPhase.failed);
      debugPrint('增量同步失败: $error\n$stackTrace');
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<AutoSyncRunResult> _synchronizeRepository() async {
    final serverUrl = await AutoSyncSettings.getServerUrl();
    if (serverUrl.isEmpty) throw StateError('WebDAV 服务器地址为空');
    final username = await AutoSyncSettings.getUsername();
    final password = await AutoSyncSettings.getPassword();
    final remoteRoot = await AutoSyncSettings.getRemotePath();
    final categories = await AutoSyncSettings.getCategories();
    final deviceId = await AutoSyncSettings.getOrCreateDeviceId();
    final transport = _transportFactory(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    final manifestPath = _remoteJoin(remoteRoot, incrementalSyncManifestFile);
    // A number of hosted WebDAV gateways allow GET/PUT but return 503 for
    // PROPFIND on iOS. An existing repository has a canonical manifest, so
    // probe it directly and avoid making directory listing a prerequisite.
    final manifestBytes = await transport.read(manifestPath);
    if (manifestBytes == null) {
      await transport.ensureDirectory(remoteRoot);
    }
    final localBackup = IncrementalSyncDataFilter.sanitizeBackup(
      await _backupService.collectBackupData(
        categories: categories,
        // Thumbnails and local media paths are device-bound cache/library
        // artifacts and must never enter the cross-device repository.
        includeWatchHistoryThumbnails: false,
      ),
    );
    final localState =
        IncrementalSyncCodec.flattenBackup(localBackup, categories);
    if (manifestBytes == null) {
      return _createRepository(
        transport: transport,
        remoteRoot: remoteRoot,
        manifestPath: manifestPath,
        localState: localState,
        categories: categories,
        deviceId: deviceId,
        serverUrl: serverUrl,
        username: username,
      );
    }

    var manifest = IncrementalSyncManifest.fromJson(
      _decodeMap(manifestBytes, expectedHash: null),
    );
    final cache = await _loadCache(
      serverUrl: serverUrl,
      username: username,
      remoteRoot: remoteRoot,
    );
    final cacheIsValid = cache != null &&
        cache.repositoryId == manifest.repositoryId &&
        cache.snapshotVersion == manifest.snapshotVersion &&
        cache.snapshotSha256 == manifest.snapshotSha256;

    IncrementalSyncState remoteState;
    final appliedPatchIds = <String>{};
    IncrementalSyncState? synchronizationBase;
    if (cacheIsValid) {
      remoteState = IncrementalSyncCodec.cloneState(cache.state);
      synchronizationBase = IncrementalSyncCodec.cloneState(cache.state);
      appliedPatchIds.addAll(cache.appliedPatchIds);
    } else {
      final snapshotBytes = await transport.read(
        _remoteJoin(remoteRoot, manifest.snapshotFile),
      );
      if (snapshotBytes == null) {
        throw StateError('远端基准快照不存在: ${manifest.snapshotFile}');
      }
      remoteState = await IncrementalSyncNativeCodec.decodeSnapshotState(
        snapshotBytes: snapshotBytes,
        expectedSha256: manifest.snapshotSha256,
        expectedRepositoryId: manifest.repositoryId,
        expectedSnapshotVersion: manifest.snapshotVersion,
      );
      appliedPatchIds.addAll(manifest.snapshotPatchIds);
    }

    final patchEntries = await _discoverPatchEntries(
      transport: transport,
      remoteRoot: remoteRoot,
      manifest: manifest,
    );
    final pendingPatchInputs = <IncrementalSyncNativePatchInput>[];
    for (final entry in patchEntries) {
      if (appliedPatchIds.contains(entry.id)) continue;
      final bytes = await transport.read(_remoteJoin(remoteRoot, entry.file));
      if (bytes == null) continue;
      pendingPatchInputs.add(IncrementalSyncNativePatchInput(
        bytes: bytes,
        expectedSha256: entry.sha256,
        expectedId: entry.id,
      ));
    }
    final patchResult = await IncrementalSyncNativeCodec.applyPatchChain(
      state: remoteState,
      patches: pendingPatchInputs,
      maximumSnapshotVersion: manifest.snapshotVersion,
    );
    remoteState = patchResult.state;
    appliedPatchIds.addAll(patchResult.appliedPatchIds);
    final downloadedPatches = patchResult.appliedPatchIds.length;

    _setPhase(AutoSyncPhase.merging);
    final selectedNames = categories.map(backupCategoryWireName).toSet();
    final selectedRemoteStateRaw =
        _selectCategories(remoteState, selectedNames);
    final selectedRemoteState = _selectCategories(
      IncrementalSyncDataFilter.sanitizeState(remoteState),
      selectedNames,
    );
    final mergedSelectedState = synchronizationBase == null
        ? _mergeFirstSync(selectedRemoteState, localState)
        : await _mergeChangedStates(
            base: _selectCategories(
              IncrementalSyncDataFilter.sanitizeState(synchronizationBase),
              selectedNames,
            ),
            remote: selectedRemoteState,
            local: localState,
          );
    final mergedState = IncrementalSyncCodec.cloneState(remoteState);
    for (final category in selectedNames) {
      mergedState[category] = Map<String, dynamic>.from(
        mergedSelectedState[category] ?? const {},
      );
    }
    final operationsForLocal = await IncrementalSyncNativeCodec.diff(
      previous: localState,
      current: mergedSelectedState,
      modifiedAt: DateTime.now().toUtc(),
      deviceId: 'remote',
    );
    await _applyOperationsLocally(operationsForLocal);

    _setPhase(AutoSyncPhase.pushing);
    final operationsForRemote = await IncrementalSyncNativeCodec.diff(
      // Compare with the unsanitized remote state so legacy local-media
      // entries are published as deletions and disappear after compaction.
      previous: selectedRemoteStateRaw,
      current: mergedSelectedState,
      modifiedAt: DateTime.now().toUtc(),
      deviceId: deviceId,
    );
    IncrementalSyncPatchEntry? uploadedEntry;
    if (operationsForRemote.isNotEmpty) {
      final now = DateTime.now().toUtc();
      final patchId = '${now.microsecondsSinceEpoch}-$deviceId';
      final patch = IncrementalSyncPatch(
        id: patchId,
        snapshotVersion: manifest.snapshotVersion,
        createdAt: now,
        deviceId: deviceId,
        operations: operationsForRemote,
      );
      final patchBytes = _encodeMap(patch.toJson());
      final safeDeviceId = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName =
          'patch_v${manifest.snapshotVersion}_${now.microsecondsSinceEpoch}_$safeDeviceId.diff';
      await transport.write(_remoteJoin(remoteRoot, fileName), patchBytes);
      uploadedEntry = IncrementalSyncPatchEntry(
        id: patchId,
        file: fileName,
        sha256: sha256.convert(patchBytes).toString(),
        size: patchBytes.length,
        createdAt: now,
        deviceId: deviceId,
      );
      appliedPatchIds.add(patchId);
    }

    // Re-read the tiny index before publishing our update. Immutable patch
    // files are also discovered by directory listing, so a concurrent writer
    // cannot permanently lose data even when its manifest PUT races ours.
    final latestManifestBytes = await transport.read(manifestPath);
    if (latestManifestBytes != null) {
      final latest = IncrementalSyncManifest.fromJson(
        _decodeMap(latestManifestBytes, expectedHash: null),
      );
      if (latest.repositoryId != manifest.repositoryId ||
          latest.snapshotVersion != manifest.snapshotVersion) {
        throw StateError('远端仓库在同步期间切换了基准快照，请重试');
      }
      manifest = latest;
    }
    final entriesById = <String, IncrementalSyncPatchEntry>{
      for (final entry in manifest.patches) entry.id: entry,
      for (final entry in patchEntries) entry.id: entry,
      if (uploadedEntry != null) uploadedEntry.id: uploadedEntry,
    };
    var updatedManifest = manifest.copyWith(
      categories: {
        ...manifest.categories,
        ...categories.map(backupCategoryWireName),
      },
      patches: entriesById.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      updatedAt: DateTime.now().toUtc(),
    );
    if (uploadedEntry != null ||
        updatedManifest.patches.length != manifest.patches.length) {
      await transport.write(
        manifestPath,
        _encodeMap(updatedManifest.toJson()),
        atomic: true,
      );
    }

    final uncompactedPatchCount = updatedManifest.patches
        .where((entry) => !updatedManifest.snapshotPatchIds.contains(entry.id))
        .length;
    if (uncompactedPatchCount >= _patchesBeforeSnapshotCompaction) {
      updatedManifest = await _compactSnapshot(
        transport: transport,
        remoteRoot: remoteRoot,
        manifestPath: manifestPath,
        manifest: updatedManifest,
        state: mergedState,
        appliedPatchIds: appliedPatchIds,
      );
    }
    updatedManifest = await _cleanupCompactedPatches(
      transport: transport,
      remoteRoot: remoteRoot,
      manifestPath: manifestPath,
      manifest: updatedManifest,
      appliedPatchIds: appliedPatchIds,
    );

    await _saveCache(
      IncrementalSyncCache(
        repositoryId: updatedManifest.repositoryId,
        snapshotVersion: updatedManifest.snapshotVersion,
        snapshotSha256: updatedManifest.snapshotSha256,
        appliedPatchIds: appliedPatchIds,
        state: mergedState,
      ),
      serverUrl: serverUrl,
      username: username,
      remoteRoot: remoteRoot,
    );
    return AutoSyncRunResult(
      downloadedPatches: downloadedPatches,
      uploadedOperations: operationsForRemote.length,
      restoredOperations: operationsForLocal.length,
      createdRepository: false,
    );
  }

  Future<AutoSyncRunResult> _createRepository({
    required IncrementalSyncTransport transport,
    required String remoteRoot,
    required String manifestPath,
    required IncrementalSyncState localState,
    required Set<BackupCategory> categories,
    required String deviceId,
    required String serverUrl,
    required String username,
  }) async {
    final now = DateTime.now().toUtc();
    final repositoryId = sha256
        .convert(utf8.encode('$deviceId:${now.microsecondsSinceEpoch}'))
        .toString()
        .substring(0, 20);
    const snapshotVersion = 1;
    const snapshotFile = 'snap_v1.json';
    final snapshotBlob = await IncrementalSyncNativeCodec.canonicalizeMap({
      'formatVersion': incrementalSyncFormatVersion,
      'repositoryId': repositoryId,
      'snapshotVersion': snapshotVersion,
      'createdAt': now.toIso8601String(),
      'state': localState,
    });
    final snapshotBytes = snapshotBlob.bytes;
    final snapshotHash = snapshotBlob.sha256;
    await transport.write(_remoteJoin(remoteRoot, snapshotFile), snapshotBytes);
    final manifest = IncrementalSyncManifest(
      repositoryId: repositoryId,
      snapshotVersion: snapshotVersion,
      snapshotFile: snapshotFile,
      snapshotSha256: snapshotHash,
      snapshotPatchIds: const {},
      categories: categories.map(backupCategoryWireName).toSet(),
      patches: const [],
      updatedAt: now,
    );
    await transport.write(
      manifestPath,
      _encodeMap(manifest.toJson()),
      atomic: true,
    );
    await _saveCache(
      IncrementalSyncCache(
        repositoryId: repositoryId,
        snapshotVersion: snapshotVersion,
        snapshotSha256: snapshotHash,
        appliedPatchIds: const {},
        state: localState,
      ),
      serverUrl: serverUrl,
      username: username,
      remoteRoot: remoteRoot,
    );
    return const AutoSyncRunResult(
      downloadedPatches: 0,
      uploadedOperations: 0,
      restoredOperations: 0,
      createdRepository: true,
    );
  }

  Future<List<IncrementalSyncPatchEntry>> _discoverPatchEntries({
    required IncrementalSyncTransport transport,
    required String remoteRoot,
    required IncrementalSyncManifest manifest,
  }) async {
    final byFile = <String, IncrementalSyncPatchEntry>{
      for (final entry in manifest.patches) entry.file: entry,
    };
    List<String> names;
    try {
      names = await transport.listFileNames(remoteRoot);
    } on WebDavSyncException catch (error) {
      final statusCode = error.statusCode;
      if (statusCode == null || statusCode < 500) rethrow;
      // manifest.version is the authoritative patch index. Directory listing
      // only recovers immutable patches uploaded immediately before a writer
      // could publish its manifest, so a gateway-level PROPFIND failure should
      // not prevent normal pull/push from continuing.
      debugPrint(
        'WebDAV 目录枚举不可用（HTTP $statusCode），'
        '本次使用 manifest.version 中的补丁索引继续同步',
      );
      names = const [];
    }
    for (final name in names.where(
      (name) => name.startsWith('patch_v') && name.endsWith('.diff'),
    )) {
      if (byFile.containsKey(name)) continue;
      final bytes = await transport.read(_remoteJoin(remoteRoot, name));
      if (bytes == null) continue;
      final patch = IncrementalSyncPatch.fromJson(
        _decodeMap(bytes, expectedHash: null),
      );
      byFile[name] = IncrementalSyncPatchEntry(
        id: patch.id,
        file: name,
        sha256: sha256.convert(bytes).toString(),
        size: bytes.length,
        createdAt: patch.createdAt,
        deviceId: patch.deviceId,
      );
    }
    return byFile.values.toList()
      ..sort((a, b) {
        final byDate = a.createdAt.compareTo(b.createdAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
  }

  Future<IncrementalSyncManifest> _compactSnapshot({
    required IncrementalSyncTransport transport,
    required String remoteRoot,
    required String manifestPath,
    required IncrementalSyncManifest manifest,
    required IncrementalSyncState state,
    required Set<String> appliedPatchIds,
  }) async {
    final nextVersion = manifest.snapshotVersion + 1;
    final snapshotFile = 'snap_v$nextVersion.json';
    final now = DateTime.now().toUtc();
    final snapshotBlob = await IncrementalSyncNativeCodec.canonicalizeMap({
      'formatVersion': incrementalSyncFormatVersion,
      'repositoryId': manifest.repositoryId,
      'snapshotVersion': nextVersion,
      'createdAt': now.toIso8601String(),
      'state': state,
    });
    final snapshotBytes = snapshotBlob.bytes;
    final snapshotHash = snapshotBlob.sha256;
    await transport.write(_remoteJoin(remoteRoot, snapshotFile), snapshotBytes);
    final compacted = manifest.copyWith(
      snapshotVersion: nextVersion,
      snapshotFile: snapshotFile,
      snapshotSha256: snapshotHash,
      snapshotPatchIds: Set<String>.from(appliedPatchIds),
      updatedAt: now,
    );
    await transport.write(
      manifestPath,
      _encodeMap(compacted.toJson()),
      atomic: true,
    );
    final obsoleteSnapshotVersion = nextVersion - _snapshotGenerationsToKeep;
    if (obsoleteSnapshotVersion >= 1) {
      final obsoleteSnapshot = 'snap_v$obsoleteSnapshotVersion.json';
      try {
        await transport.delete(_remoteJoin(remoteRoot, obsoleteSnapshot));
      } catch (error) {
        // Keep the newly published snapshot authoritative even when the
        // provider temporarily refuses maintenance DELETE requests.
        debugPrint('清理旧同步快照失败，将保留该文件: $obsoleteSnapshot: $error');
      }
    }
    return compacted;
  }

  Future<IncrementalSyncManifest> _cleanupCompactedPatches({
    required IncrementalSyncTransport transport,
    required String remoteRoot,
    required String manifestPath,
    required IncrementalSyncManifest manifest,
    required Set<String> appliedPatchIds,
  }) async {
    final oldestRetainedVersion =
        manifest.snapshotVersion - _snapshotGenerationsToKeep + 1;
    if (oldestRetainedVersion <= 1) return manifest;

    final candidates = manifest.patches
        .where((entry) {
          final version = _patchSnapshotVersion(entry.file);
          return version != null &&
              version < oldestRetainedVersion &&
              manifest.snapshotPatchIds.contains(entry.id);
        })
        .take(_patchCleanupBatchSize)
        .toList();
    if (candidates.isEmpty) return manifest;

    final deletedIds = <String>{};
    for (final entry in candidates) {
      try {
        await transport.delete(_remoteJoin(remoteRoot, entry.file));
        deletedIds.add(entry.id);
      } catch (error) {
        // Garbage collection is maintenance work. A provider that temporarily
        // rejects DELETE must not turn an otherwise successful sync into a
        // failure; the manifest entry keeps the file queued for a later run.
        debugPrint('清理已压缩同步补丁失败，将稍后重试: ${entry.file}: $error');
      }
    }
    if (deletedIds.isEmpty) return manifest;

    try {
      final latestBytes = await transport.read(manifestPath);
      if (latestBytes == null) return manifest;
      final latest = IncrementalSyncManifest.fromJson(
        _decodeMap(latestBytes, expectedHash: null),
      );
      if (latest.repositoryId != manifest.repositoryId ||
          latest.snapshotVersion != manifest.snapshotVersion ||
          latest.snapshotSha256 != manifest.snapshotSha256) {
        // Do not let maintenance adopt a snapshot whose state was not pulled
        // during this run. The next sync will see the version mismatch and
        // rebuild its cache from that newer snapshot.
        return manifest;
      }

      // Only prune IDs that the latest published snapshot still confirms as
      // included. This preserves patches uploaded by a concurrent device.
      final safeDeletedIds =
          deletedIds.where(latest.snapshotPatchIds.contains).toSet();
      if (safeDeletedIds.isEmpty) return latest;
      final cleaned = latest.copyWith(
        patches: latest.patches
            .where((entry) => !safeDeletedIds.contains(entry.id))
            .toList(),
        snapshotPatchIds: latest.snapshotPatchIds.difference(safeDeletedIds),
        updatedAt: DateTime.now().toUtc(),
      );
      await transport.write(
        manifestPath,
        _encodeMap(cleaned.toJson()),
        atomic: true,
      );
      appliedPatchIds.removeAll(safeDeletedIds);
      debugPrint('已清理 ${safeDeletedIds.length} 个过期增量同步补丁');
      return cleaned;
    } catch (error) {
      // Deleted files are already represented by the current snapshot. If the
      // metadata prune fails, a later run safely retries it (DELETE accepts
      // 404), while synchronization itself remains successful.
      debugPrint('更新补丁清理索引失败，将稍后重试: $error');
      return manifest;
    }
  }

  @visibleForTesting
  Future<IncrementalSyncManifest> cleanupCompactedPatchesForTesting({
    required IncrementalSyncTransport transport,
    required String remoteRoot,
    required String manifestPath,
    required IncrementalSyncManifest manifest,
    required Set<String> appliedPatchIds,
  }) {
    return _cleanupCompactedPatches(
      transport: transport,
      remoteRoot: remoteRoot,
      manifestPath: manifestPath,
      manifest: manifest,
      appliedPatchIds: appliedPatchIds,
    );
  }

  static int? _patchSnapshotVersion(String fileName) {
    final match = RegExp(r'^patch_v(\d+)_').firstMatch(fileName);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  IncrementalSyncState _mergeFirstSync(
    IncrementalSyncState remote,
    IncrementalSyncState local,
  ) {
    final merged = IncrementalSyncCodec.cloneState(remote);
    for (final category in local.keys) {
      final target = merged.putIfAbsent(category, () => {});
      for (final entry in local[category]!.entries) {
        if (!target.containsKey(entry.key)) {
          target[entry.key] = entry.value;
        } else if (category == BackupCategory.watchHistory.name &&
            _localWatchRecordIsNewer(entry.value, target[entry.key])) {
          target[entry.key] = entry.value;
        }
      }
    }
    return merged;
  }

  Future<IncrementalSyncState> _mergeChangedStates({
    required IncrementalSyncState base,
    required IncrementalSyncState remote,
    required IncrementalSyncState local,
  }) async {
    final now = DateTime.now().toUtc();
    final remoteChanges = await IncrementalSyncNativeCodec.diff(
      previous: base,
      current: remote,
      modifiedAt: now,
      deviceId: 'remote',
    );
    final localChanges = await IncrementalSyncNativeCodec.diff(
      previous: base,
      current: local,
      modifiedAt: now,
      deviceId: 'local',
    );
    final remoteKeys = {
      for (final operation in remoteChanges)
        '${operation.category}\u0000${operation.key}',
    };
    final acceptedLocalChanges = <IncrementalSyncOperation>[];
    for (final operation in localChanges) {
      final identity = '${operation.category}\u0000${operation.key}';
      if (!remoteKeys.contains(identity)) {
        acceptedLocalChanges.add(operation);
        continue;
      }
      if (operation.category == BackupCategory.watchHistory.name &&
          !operation.deleted &&
          _localWatchRecordIsNewer(
            operation.value,
            remote[operation.category]?[operation.key],
          )) {
        acceptedLocalChanges.add(operation);
      } else if (operation.category != BackupCategory.watchHistory.name) {
        // A local value that differs from the last synchronized base is an
        // explicit local edit. Publishing it as a new immutable patch gives
        // every device the same eventual result.
        acceptedLocalChanges.add(operation);
      }
    }
    return IncrementalSyncCodec.applyOperations(remote, acceptedLocalChanges);
  }

  bool _localWatchRecordIsNewer(dynamic local, dynamic remote) {
    if (local is! Map) return false;
    if (remote is! Map) return true;
    final localTime =
        DateTime.tryParse(local['lastWatchTime']?.toString() ?? '');
    final remoteTime =
        DateTime.tryParse(remote['lastWatchTime']?.toString() ?? '');
    if (localTime == null) return false;
    if (remoteTime == null) return true;
    return localTime.isAfter(remoteTime);
  }

  Future<void> _applyOperationsLocally(
    List<IncrementalSyncOperation> operations,
  ) async {
    if (operations.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final database = WatchHistoryDatabase.instance;
    for (final operation
        in operations.where((operation) => operation.deleted)) {
      if (operation.category == BackupCategory.preferences.name) {
        await prefs.remove(operation.key);
      } else if (operation.category == BackupCategory.watchHistory.name) {
        await database.deleteHistory(operation.key);
      } else if (operation.category == BackupCategory.episodeMatches.name) {
        final existing = await database.getHistoryByFilePath(operation.key);
        if (existing != null) {
          await database.insertOrUpdateWatchHistory(WatchHistoryItem(
            filePath: existing.filePath,
            animeName: existing.animeName,
            episodeTitle: existing.episodeTitle,
            episodeId: null,
            animeId: null,
            watchProgress: existing.watchProgress,
            lastPosition: existing.lastPosition,
            duration: existing.duration,
            lastWatchTime: existing.lastWatchTime,
            thumbnailPath: existing.thumbnailPath,
            isFromScan: existing.isFromScan,
            videoHash: existing.videoHash,
          ));
        }
      }
    }
    for (final operation in operations.where(
      (operation) =>
          !operation.deleted &&
          operation.category == BackupCategory.accounts.name &&
          operation.value is Map &&
          operation.value['isLoggedIn'] == false,
    )) {
      if (operation.key == 'dandanplay') {
        await prefs.setBool('dandanplay_logged_in', false);
        await prefs.remove('dandanplay_token');
        await prefs.remove('dandanplay_username');
        await prefs.remove('dandanplay_screenname');
      } else if (operation.key == 'bangumi') {
        await prefs.setBool('bangumi_logged_in', false);
        await prefs.remove('bangumi_access_token');
        await prefs.remove('bangumi_user_info');
      }
    }
    for (final operation in operations.where(
      (operation) =>
          !operation.deleted &&
          operation.category == BackupCategory.mediaLibraries.name,
    )) {
      final value = operation.value;
      if (operation.key == 'serverProfiles' && value is List && value.isEmpty) {
        await MultiAddressServerService.instance.loadProfiles();
        final ids = MultiAddressServerService.instance.profiles
            .map((profile) => profile.id)
            .toList();
        for (final id in ids) {
          await MultiAddressServerService.instance.deleteProfile(id);
        }
      } else if (operation.key == 'webdavConnections' &&
          value is List &&
          value.isEmpty) {
        await WebDAVService.instance.initialize();
        final names = WebDAVService.instance.connections
            .map((connection) => connection.name)
            .toList();
        for (final name in names) {
          await WebDAVService.instance.removeConnection(name);
        }
      } else if (operation.key == 'smbConnections' &&
          value is List &&
          value.isEmpty) {
        await SMBService.instance.initialize();
        final names = SMBService.instance.connections
            .map((connection) => connection.name)
            .toList();
        for (final name in names) {
          await SMBService.instance.removeConnection(name);
        }
      } else if (operation.key == 'dandanplayRemote' && value == null) {
        await DandanplayRemoteService.instance.disconnect();
      }
    }

    final changedState = <String, Map<String, dynamic>>{};
    for (final operation
        in operations.where((operation) => !operation.deleted)) {
      changedState.putIfAbsent(operation.category, () => {})[operation.key] =
          operation.value;
    }
    if (changedState.isEmpty) return;
    final categories = changedState.keys
        .map(backupCategoryFromWireName)
        .whereType<BackupCategory>()
        .toSet();
    final result = await _backupService.restoreFromData(
      backupData: IncrementalSyncCodec.inflateState(changedState),
      categories: categories,
    );
    if (!result.success) {
      throw StateError(result.errorMessage ?? '增量数据导入失败');
    }
  }

  Future<IncrementalSyncCache?> _loadCache({
    required String serverUrl,
    required String username,
    required String remoteRoot,
  }) async {
    try {
      final file = await _cacheFile(serverUrl, username, remoteRoot);
      if (!await file.exists()) return null;
      return IncrementalSyncCache.fromJson(await compute(
        _decodeSyncJsonString,
        await file.readAsString(),
      ));
    } catch (error) {
      debugPrint('读取增量同步本地索引失败，将重建: $error');
      return null;
    }
  }

  Future<void> _saveCache(
    IncrementalSyncCache cache, {
    required String serverUrl,
    required String username,
    required String remoteRoot,
  }) async {
    final file = await _cacheFile(serverUrl, username, remoteRoot);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final encoded =
        await IncrementalSyncNativeCodec.canonicalizeMap(cache.toJson());
    await temporary.writeAsBytes(encoded.bytes);
    await temporary.rename(file.path);
  }

  Future<File> _cacheFile(
    String serverUrl,
    String username,
    String remoteRoot,
  ) async {
    final directory = await getApplicationSupportDirectory();
    final key = sha256
        .convert(utf8.encode('$serverUrl\u0000$username\u0000$remoteRoot'))
        .toString()
        .substring(0, 24);
    return File(
        path.join(directory.path, 'incremental_sync', '$key.index.json'));
  }

  static IncrementalSyncState _selectCategories(
    IncrementalSyncState source,
    Set<String> categories,
  ) {
    return <String, Map<String, dynamic>>{
      for (final category in categories)
        category: Map<String, dynamic>.from(source[category] ?? const {}),
    };
  }

  static Map<String, dynamic> _decodeMap(
    Uint8List bytes, {
    required String? expectedHash,
  }) {
    if (expectedHash != null && expectedHash.isNotEmpty) {
      final actual = sha256.convert(bytes).toString();
      if (actual != expectedHash) {
        throw const FormatException('远端同步对象校验失败');
      }
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  static Uint8List _encodeMap(Map<String, dynamic> value) {
    return Uint8List.fromList(
      utf8.encode(IncrementalSyncCodec.canonicalJson(value)),
    );
  }

  static String _remoteJoin(String root, String fileName) {
    return root == '/' ? '/$fileName' : '$root/$fileName';
  }

  void _setPhase(AutoSyncPhase value) {
    _phase = value;
    notifyListeners();
  }

  static Future<void> _ignoreResult(Future<AutoSyncRunResult> future) async {
    try {
      await future;
    } catch (_) {
      // The failure is persisted and exposed through [lastError].
    }
  }

  @override
  void dispose() {
    _stopAutoSync();
    if (identical(_instance, this)) _instance = null;
    super.dispose();
  }
}

Map<String, dynamic> _decodeSyncJsonString(String value) {
  return Map<String, dynamic>.from(jsonDecode(value) as Map);
}
