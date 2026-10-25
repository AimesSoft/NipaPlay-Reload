import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/torrent_add_result.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/services/torrent_download_service.dart';

import '../capabilities/download_capability.dart';
import '../state/change_history.dart';
import '../capabilities/download_metadata_capability.dart';
import '../tasks/sqlite_job_store.dart';
import 'download_backend.dart';
import 'download_executor.dart';
import 'download_service.dart';
import 'download_source.dart';
import 'http_download_backend.dart';
import 'qbittorrent_download_backend.dart';
import 'qbittorrent_hub.dart';
import '../../security/credential_vault.dart';

final class DownloadRuntime extends ChangeNotifier {
  DownloadRuntime(
      {required DownloadBackend backend,
      required DownloadLibrary library,
      required Future<bool> Function() isEnabled,
      required Future<Set<String>> Function() loadImportedKeys,
      Duration refreshInterval = const Duration(seconds: 5),
      HttpDownloadBackend? httpBackend})
      : _backend = backend,
        http = httpBackend ??
            HttpDownloadBackend(
                defaultDirectory: () =>
                    TorrentDownloadService.instance.getDownloadDirectory()),
        _library = library,
        _enabled = isEnabled,
        _loadImportedKeys = loadImportedKeys,
        _refreshInterval = refreshInterval {
    _backends = DownloadBackends([backend, http]);
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

  /// Only Next registers this backend; Classic's page never lists it.
  final HttpDownloadBackend http;

  /// The qBittorrents the person added in settings. Null until [attach] is
  /// given a credential vault. Only Next knows them; Classic never lists them.
  QbittorrentHub? qbittorrent;
  final _qbittorrentErrors = <String, Failure>{};
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

  void attach(TaskEngine engine, Directory root, {CredentialVault? vault}) {
    this.engine = engine;
    http.stateDirectory ??= Directory('${root.path}/http_downloads');
    if (vault != null) {
      qbittorrent = QbittorrentHub(
          file: File('${root.path}/qbittorrent.json'), vault: vault)
        ..onRegistered = ((QbittorrentDownloadBackend backend) {
          _backends.register(backend);
          _qbittorrentErrors.remove(backend.reference.key);
        })
        ..onRemoved = ((DownloadBackendRef ref) {
          _backends.unregister(ref);
          _qbittorrentErrors.remove(ref.key);
        });
    }
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
        DownloadSources(Directory('${root.path}/torrent_sources')), _enabled,
        httpBackend: http);
  }

  Future<void> start() {
    _ready.complete(_startObservation());
    return ready;
  }

  Future<void> _startObservation() async {
    final hub = qbittorrent;
    if (hub != null) {
      await hub.load();
      for (final backend in hub.backends) {
        _backends.register(backend);
      }
    }
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
    final jobsByHash = <String, Job>{};
    if (await _enabled()) {
      await _backend.initialize();
      final tasks = await _backend.list();
      for (final task in tasks) {
        jobsByHash[task.infoHash.toLowerCase()] =
            await downloads.adopt(_backend, task);
      }
      await downloads.observeMissingSessions(_backend, tasks,
          candidateIds: await _missingSessionIds(_backend, tasks));
      // HTTP sessions are never adopted (they only exist because Next added
      // them); only a session that vanished is noticed.
      await http.initialize();
      final httpTasks = await http.list();
      await downloads.observeMissingSessions(http, httpTasks,
          candidateIds: await _missingSessionIds(http, httpTasks));
      // A qBittorrent is asked independently: one that is off does not stop
      // the others, and its torrents are never adopted (it holds what its
      // owner put there, not only what Next added).
      await Future.wait([
        for (final backend in _backends.values)
          if (backend is QbittorrentDownloadBackend) _refreshQbittorrent(backend)
      ]);
    }
    autoScannedKeys = Set.unmodifiable(await _loadImportedKeys());
    _jobsByHash = Map.unmodifiable(jobsByHash);
    lastSessionError = null;
    if (!_closed) notifyListeners();
  }

  Future<void> _refreshQbittorrent(QbittorrentDownloadBackend backend) async {
    final key = backend.reference.key;
    try {
      await backend.initialize();
      final tasks = await backend.list();
      await downloads.observeMissingSessions(backend, tasks,
          candidateIds: await _missingSessionIds(backend, tasks));
      _qbittorrentErrors.remove(key);
    } on Failure catch (failure) {
      _qbittorrentErrors[key] = failure;
    } catch (error) {
      _qbittorrentErrors[key] =
          const Failure(FailureCode.unavailable, 'qBittorrent failed.', retryable: true);
    }
  }

  /// The SQL store can identify vanished sessions without decoding the
  /// complete download history. Other stores (used by callers and tests) keep
  /// the previous full-list fallback in DownloadService.
  Future<List<String>?> _missingSessionIds(
      DownloadBackend backend, List<DownloadSnapshot> present) async {
    final store = engine.store;
    if (store is! SqliteJobStore) return null;
    return store.missingDownloadSessionIds(
        backendKind: backend.reference.kind,
        backendId: backend.reference.id,
        presentHashes: {for (final task in present) task.infoHash});
  }

  /// What each download backend is doing now: whether downloads are on,
  /// how many tasks it holds in each state, the rate it reports and the
  /// limits set on it. Nothing is started to find out: the backends are
  /// asked only while downloads are enabled, as the periodic refresh does.
  Future<List<JsonMap>> engineStatus() async {
    final enabled = await _enabled();
    final jobs = await engine.list(type: 'download');
    final observedAt = DateTime.now().toUtc().toIso8601String();
    final rows = <JsonMap>[];
    final others = [
      for (final backend in _backends.values)
        if (backend is QbittorrentDownloadBackend) backend
    ];
    for (final backend in [_backend, http, ...others]) {
      final key = backend.reference.key;
      JsonMap? facts;
      if (backend is QbittorrentDownloadBackend) {
        facts = enabled ? await backend.status() : backend.identity;
      }
      final mine = [
        for (final job in jobs)
          // A task without a recorded backend belongs to no engine.
          if (job.details['backend'] case final JsonMap recorded
              when DownloadBackendRef.fromJson(recorded).key == key)
            job
      ];
      int count(bool Function(JobState) match) =>
          mine.where((job) => match(job.state)).length;
      int? down, up;
      String? error;
      if (enabled && facts != null && facts['online'] == false) {
        error = facts['error'] as String? ?? 'unavailable';
      } else if (enabled) {
        try {
          down = 0;
          up = 0;
          for (final task in await backend.list()) {
            if (task.finished || task.paused) continue;
            down = down! + (task.downloadSpeedBytesPerSecond ?? 0);
            up = up! + (task.uploadSpeedBytesPerSecond ?? 0);
          }
        } on Failure catch (failure) {
          down = up = null;
          error = failure.code.wireName;
        } catch (_) {
          down = up = null;
          error = 'backend_failed';
        }
      }
      JsonMap? limits;
      if (enabled &&
          backend is BandwidthDownloadBackend &&
          !(facts != null && facts['online'] == false)) {
        try {
          limits = await downloads.bandwidth({}, ref: backend.reference);
        } catch (_) {
          limits = null;
        }
      }
      final actual = (limits?['actual'] as Map?)?.cast<String, Object?>();
      rows.add({
        'backend': backend.reference.kind,
        if (facts != null) ...{
          'id': facts['id'],
          'name': facts['name'],
          'address': facts['address'],
          'local': facts['local'],
          'online': facts['online'],
          'version': facts['version'],
          'apiVersion': facts['apiVersion'],
        },
        'enabled': enabled,
        'running': count((s) => s == JobState.running),
        'queued': count((s) => s == JobState.queued),
        'paused': count((s) => s == JobState.paused),
        'waiting': count((s) => const {
              JobState.waitingRetry,
              JobState.waitingUser,
              JobState.needsDecision,
              JobState.interrupted
            }.contains(s)),
        'finished': count((s) => s.isTerminal),
        'total': mine.length,
        'downloadBytesPerSecond': down,
        'uploadBytesPerSecond': up,
        'limitsSupported': backend is BandwidthDownloadBackend
            ? (limits?['supported'])
            : false,
        'sessionInitialized': limits?['sessionInitialized'],
        'downloadLimitBytesPerSecond': actual?['downloadBytesPerSecond'],
        'uploadLimitBytesPerSecond': actual?['uploadBytesPerSecond'],
        'error': error ??
            (backend == _backend ? lastSessionError?.code.wireName : null),
        'observedAt': observedAt,
      });
    }
    return rows;
  }

  /// What every online qBittorrent holds, asked now: its own torrents, not
  /// only the ones Next tracks. `jobId` is the download task that follows a
  /// torrent (null when none does); naming a torrent in `download.add` makes
  /// one. A qBittorrent that does not answer contributes no rows (its state is
  /// in [engineStatus]); nothing is started.
  Future<List<JsonMap>> qbittorrentTorrents() async {
    if (!await _enabled()) return const [];
    final jobs = await engine.list(type: 'download');
    final tracked = <String, String>{};
    for (final job in jobs) {
      final recorded = job.details['backend'];
      if (recorded is! Map || job.input['infoHash'] is! String) continue;
      if (job.receipt?.details['sessionPresent'] == false) continue;
      tracked['${DownloadBackendRef.fromJson(recorded.cast<String, Object?>()).key}|${job.input['infoHash']}'] =
          job.jobId;
    }
    final rows = <JsonMap>[];
    for (final backend in _backends.values) {
      if (backend is! QbittorrentDownloadBackend) continue;
      try {
        for (final task in await backend.list()) {
          rows.add({
            'id': backend.id,
            'name': backend.name,
            'local': backend.local,
            'infoHash': task.infoHash,
            'title': task.title,
            'state': task.state,
            'paused': task.paused,
            'finished': task.finished,
            'completedBytes': task.completed,
            'totalBytes': task.total,
            'downloadBytesPerSecond': task.downloadSpeedBytesPerSecond,
            'uploadBytesPerSecond': task.uploadSpeedBytesPerSecond,
            'savePath': task.output.path,
            'category': (task.health?['qbittorrent'] as Map?)?['category'],
            'jobId': tracked['${backend.reference.key}|${task.infoHash}'],
          });
        }
      } on Failure {
        continue;
      }
    }
    return rows;
  }

  bool isImporting(TorrentTask task) {
    final job = _jobsByHash[task.infoHash.toLowerCase()];
    return job != null &&
        job.phase == 'importing' &&
        {JobState.running, JobState.cancelling}.contains(job.state);
  }

  Future<void> _adoptNative(int id) async {
    await BodyChanges.fromUser(() async =>
        downloads.adopt(_backend, await _backend.read(id.toString())));
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
    await BodyChanges.fromUser(
        () async => downloads.pause((await _job(id)).jobId));
  }

  Future<void> resume(int id) async {
    await BodyChanges.fromUser(
        () async => downloads.resume((await _job(id)).jobId));
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
    await http.close();
  }

  Future<void> quiesce(Iterable<Job> jobs) async {
    for (final job in jobs) {
      await executor.quiesce(job.jobId);
    }
  }
}
