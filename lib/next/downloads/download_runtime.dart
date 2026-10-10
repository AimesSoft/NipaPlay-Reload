import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/torrent_add_result.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import '../capabilities/download_capability.dart';
import '../tasks/device_identity.dart';
import '../tasks/sqlite_job_store.dart';
import 'builtin_download_backend.dart';
import 'download_backend.dart';
import 'download_executor.dart';
import 'download_library.dart';
import 'download_service.dart';
import 'download_source.dart';

final class DownloadRuntime extends ChangeNotifier {
  DownloadRuntime() {
    ready = _initialize();
  }
  @visibleForTesting
  DownloadRuntime.forTesting(
      {required Directory root,
      required JobStore store,
      required DownloadBackend backend,
      required DownloadLibrary library,
      required Future<bool> Function() isEnabled,
      required Future<Set<String>> Function() loadImportedKeys,
      Duration refreshInterval = const Duration(seconds: 5)}) {
    _enabledOverride = isEnabled;
    _loadImportedKeys = loadImportedKeys;
    _refreshInterval = refreshInterval;
    ready = _connect(root, store, 'device-test', backend, library);
  }
  late final Future<void> ready;
  late final TaskEngine engine;
  late final DownloadService downloads;
  late final DownloadCapability capability;
  late final DownloadBackend _backend;
  Future<bool> Function()? _enabledOverride;
  late Future<Set<String>> Function() _loadImportedKeys;
  Duration _refreshInterval = const Duration(seconds: 5);
  Failure? lastSessionError;
  final _native = TorrentDownloadService.instance;
  Set<String> autoScannedKeys = const {};
  Map<String, Job> _jobsByHash = const {};
  Timer? _timer;
  Future<void>? _refreshing;
  bool _closed = false;

  Future<bool> _enabled() async => _enabledOverride != null
      ? await _enabledOverride!()
      : globals.isDownloaderSupportedPlatform &&
          await SettingsStorage.loadBool(SettingsKeys.downloaderEnabled,
              defaultValue: true);
  Future<void> _initialize() async {
    final storage = await StorageService.getAppStorageDirectory();
    final root = Directory('${storage.path}/next');
    final deviceId = await loadDeviceIdentity(root);
    _loadImportedKeys = _native.loadAutoScannedCompletedTaskKeys;
    await _connect(root, await SqliteJobStore.open(root), deviceId,
        BuiltinDownloadBackend(_native), AppDownloadLibrary(_native));
  }

  Future<void> _connect(Directory root, JobStore store, String deviceId,
      DownloadBackend backend, DownloadLibrary library) async {
    _backend = backend;
    final backends = DownloadBackends([_backend]);
    final executor = DownloadExecutor(
        backends: backends, library: library, isEnabled: _enabled);
    engine = TaskEngine(
        store: store, ownerDeviceId: deviceId, executors: [executor]);
    executor.engine = engine;
    downloads = DownloadService(
        engine: engine,
        executor: executor,
        backends: backends,
        library: library);
    capability = DownloadCapability(
        downloads: downloads,
        sources: DownloadSources(Directory('${root.path}/torrent_sources')));
    await engine.start();
    await _observeSession();
    _scheduleRefresh();
  }

  Future<void> _observeSession() async {
    try {
      await refresh();
      lastSessionError = null;
    } on Failure catch (failure) {
      if (failure.code != FailureCode.unavailable || !failure.retryable) {
        rethrow;
      }
      lastSessionError = failure;
      debugPrint('下载后端暂时不可用: ${failure.message}');
      if (!_closed) notifyListeners();
    }
  }

  void _scheduleRefresh() {
    if (_closed) return;
    _timer = Timer(_refreshInterval, () async {
      try {
        await _observeSession();
      } finally {
        _scheduleRefresh();
      }
    });
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    if (_closed) return;
    if (await _enabled()) {
      await _backend.initialize();
      for (final task in await _backend.list()) {
        await downloads.adopt(_backend, task);
      }
    }
    autoScannedKeys = Set.unmodifiable(await _loadImportedKeys());
    _jobsByHash = {
      for (final job in await engine.list(type: 'download'))
        if ((job.details['backend'] as JsonMap)['kind'] == 'builtin')
          job.input['infoHash'] as String: job
    };
    lastSessionError = null;
    if (!_closed) notifyListeners();
  }

  bool isImporting(TorrentTask task) {
    final job = _jobsByHash[task.infoHash.toLowerCase()];
    return job != null &&
        job.phase == 'importing' &&
        {JobState.running, JobState.cancelling}.contains(job.state);
  }

  Future<void> _adoptNative(int id) async {
    await downloads.adopt(_backend, await _backend.read(id.toString()));
    await refresh();
  }

  Future<TorrentAddResult> addMagnet(String source,
      {required int previewId,
      required String downloadDirectory,
      required bool createFolderForTask}) async {
    await ready;
    final result = await _native.addMagnet(source,
        previewId: previewId,
        downloadDirectory: downloadDirectory,
        createFolderForTask: createFolderForTask);
    await _adoptNative(result.id);
    return result;
  }

  Future<TorrentAddResult> addTorrentFile(String path,
      {required String downloadDirectory,
      required bool createFolderForTask}) async {
    await ready;
    final result = await _native.addTorrentFile(path,
        downloadDirectory: downloadDirectory,
        createFolderForTask: createFolderForTask);
    await _adoptNative(result.id);
    return result;
  }

  Future<Job> _job(int id) async {
    await ready;
    final task = await _backend.read(id.toString());
    return downloads.adopt(_backend, task);
  }

  Future<void> pause(int id) async {
    await downloads.pause((await _job(id)).jobId);
  }

  Future<void> resume(int id) async {
    await downloads.resume((await _job(id)).jobId);
  }

  Future<void> forget(int id) async {
    await downloads.remove((await _job(id)).jobId);
  }

  Future<void> delete(int id) async {
    await downloads.remove((await _job(id)).jobId, deleteData: true);
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await ready;
    await _refreshing;
    final jobs = await engine.list();
    await engine.close();
    for (final job in jobs) {
      await downloads.executor.quiesce(job.jobId);
    }
  }
}
