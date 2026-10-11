import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/torrent_add_result.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/services/torrent_download_service.dart';

import '../capabilities/download_capability.dart';
import '../capabilities/download_metadata_capability.dart';
import 'download_backend.dart';
import 'download_executor.dart';
import 'download_service.dart';
import 'download_source.dart';

final class DownloadRuntime extends ChangeNotifier {
  DownloadRuntime(
      {required DownloadBackend backend,
      required DownloadLibrary library,
      required Future<bool> Function() isEnabled,
      required Future<Set<String>> Function() loadImportedKeys,
      Duration refreshInterval = const Duration(seconds: 5)})
      : _backend = backend,
        _library = library,
        _enabled = isEnabled,
        _loadImportedKeys = loadImportedKeys,
        _refreshInterval = refreshInterval {
    _backends = DownloadBackends([backend]);
    executor = DownloadExecutor(
        backends: _backends, library: library, isEnabled: isEnabled);
  }
  final _ready = Completer<void>();
  Future<void> get ready => _ready.future;
  late final TaskEngine engine;
  late final DownloadExecutor executor;
  late final DownloadService downloads;
  late final DownloadCapability capability;
  late final DownloadMetadataCapability metadataCapability;
  final DownloadBackend _backend;
  final DownloadLibrary _library;
  late final DownloadBackends _backends;
  final Future<bool> Function() _enabled;
  final Future<Set<String>> Function() _loadImportedKeys;
  final Duration _refreshInterval;
  Failure? lastSessionError;
  final _native = TorrentDownloadService.instance;
  Set<String> autoScannedKeys = const {};
  Map<String, Job> _jobsByHash = const {};
  Timer? _timer;
  Future<void>? _refreshing;
  bool _closed = false;

  void attach(TaskEngine engine, Directory root) {
    this.engine = engine;
    executor.engine = engine;
    downloads = DownloadService(
        engine: engine,
        executor: executor,
        backends: _backends,
        library: _library);
    capability = DownloadCapability(
        downloads: downloads,
        deleteAudit: JsonlJournal(File('${root.path}/download-audit.jsonl')),
        sources: DownloadSources(Directory('${root.path}/torrent_sources')));
    metadataCapability = DownloadMetadataCapability(
        DownloadSources(Directory('${root.path}/torrent_sources')), _enabled);
  }

  Future<void> start() {
    _ready.complete(_startObservation());
    return ready;
  }

  Future<void> _startObservation() async {
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

  Future<void> stop() async {
    _closed = true;
    _timer?.cancel();
    await ready;
    await _refreshing;
  }

  Future<void> quiesce(Iterable<Job> jobs) async {
    for (final job in jobs) {
      await executor.quiesce(job.jobId);
    }
  }
}
