import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../ui_data/service.dart';
import '../ui_data/ui_data.dart';
import '../subtitles/companions.dart';
import '../media/media_probe.dart';
import '../danmaku/store.dart';
import '../danmaku/sidecar.dart';
import 'runtime.dart';
import 'library_codec.dart';
import 'library_transfer.dart';
import 'library_worker.dart';
import 'library_projection.dart';
import '../ui_data/library_search.dart';
import '../media/metadata_provider.dart';
import 'files.dart';
import '../system/operation_observations.dart';

String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

/// A projection of each owner's catalogue, never a copy of its database.
final class MeshLibrary {
  MeshLibrary(
    this.ui,
    this.mesh, {
    Future<JsonMap> Function(String) subtitleProbe = probeMediaInfo,
    this.startupPhase,
    this.prepareDanmaku,
  }) {
    worker = LibraryWorker(ui, subtitleProbe: subtitleProbe);
    ui.state.queryWorker = worker.query;
    files = MeshFiles(mesh, fileReadable, ui.media.store.ownerDeviceId);
    mesh.libraryRequest = request;
    ui.media.searchWorkIds = searchWorkIds;
    mesh.hostConfigurationChanged = _hostConfigurationChanged;
    _libraryChanges = ui.changes.listen((_) => invalidateIndex());
  }
  late final MeshFiles files;
  late final LibraryWorker worker;
  final UiDataService ui;
  final MeshRuntime mesh;
  final void Function(String)? startupPhase;
  final Future<void> Function(String path, String fileId, String episodeId)?
      prepareDanmaku;
  final _peers = <String, JsonMap>{};
  final _online = <String, bool>{};
  final _peerErrors = <String, JsonMap>{};
  final _peerState = <String, JsonMap>{};
  final _peerTasks = <String, (String, List<JsonMap>)>{};

  /// What each other device runs in the background, as it said with its
  /// catalogue: its id, its name and its tasks. A device that cannot be
  /// read, or does not say, has none here.
  Iterable<(String, String, List<JsonMap>)> get peerTasks => [
        for (final MapEntry(key: id, value: (name, tasks)) in _peerTasks.entries)
          (id, name, tasks)
      ];

  /// Keeps what [peer] (named [name]) said it runs, with its catalogue;
  /// null forgets it.
  void heardTasks(String peer, String? name, Object? tasks) {
    final list = tasks is List
        ? [for (final t in tasks) if (t is Map) t.cast<String, Object?>()]
        : null;
    final held = _peerTasks[peer];
    if (list == null || list.isEmpty || name == null) {
      if (_peerTasks.remove(peer) != null) ui.peerTasksChanged();
      return;
    }
    if (held != null &&
        held.$1 == name &&
        jsonEncode(held.$2) == jsonEncode(list)) {
      return;
    }
    _peerTasks[peer] = (name, list);
    ui.peerTasksChanged();
  }
  final _artworkTasks = <String, Future<void>>{};
  final _assetReads = <String, Future<String>>{};
  JsonMap get refreshStatus => {
        'ownerDeviceId': own,
        'scope': 'cached_observations',
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        'refreshInProgress': _sync != null,
        'polling': _timer != null,
        'closed': _closed,
        'peers': [
          for (final id in {
            ..._peers.keys,
            ..._online.keys,
            ..._peerState.keys,
            for (final peer in mesh.cachedDevices)
              if (peer['deviceId'] != own) peer['deviceId'] as String,
          })
            {
              'deviceId': id,
              'online': _online[id],
              'catalogue': _peers.containsKey(id) ? 'saved' : 'not_refreshed',
              'version': _peers[id]?['version'],
              'reachability': 'unknown',
              'catalogueFreshness':
                  _peers.containsKey(id) ? 'stale' : 'not_refreshed',
              ...?_peerState[id],
              if (_peerErrors[id] case final error?) 'error': error
            },
        ],
      };
  Map<String, String> _assets = {};
  final _playAssets = <String, String>{};
  Map<String, UiWork> _works = {};
  PackedWorks? _packedWorks;
  UiHome? _home;
  int? _homeEpoch;
  Future<UiHome>? _homeLoading;
  int? _homeLoadingEpoch;
  List<String> _orderedWorkIds = const [];
  Map<String, String> _episodeParents = {};
  LibrarySearchIndex searchIndex = LibrarySearchIndex();
  Map<String, List<UiEpisode>> _episodes = {};
  final _resolvedIds = <String, String>{};
  Map<String, List<JsonMap>> _locations = {};
  Map<String, String> _localTargets = {};

  Future<void>? _sync, _building, _preparing;
  String? _builtStamp;
  String? _composedStamp;
  StreamSubscription<void>? _libraryChanges;
  bool _indexPrepared = false;
  int _indexEpoch = 0;
  String? _preparedBuiltStamp, _preparedAccount;
  int? _preparedPeerRevision, _preparedOnlineRevision;

  /// Progress moves independently of the catalogue's composition revision.
  int _peersRevision = 0, _progressRevision = 0, _onlineRevision = 0;
  String _changeStamp() => jsonEncode(
      [_builtStamp, _peersRevision, _onlineRevision, _progressRevision]);
  Timer? _timer;
  HttpServer? _http;
  Future<void>? _httpBinding;
  int _requestedPort = 0;
  String _proxyState = 'not_started';
  String? _proxyReason;
  final _readers = <String, JsonMap>{};
  final _streams = <Socket>{};
  final playback = <String, JsonMap>{};
  bool _closed = false;
  String? lastError;
  Database get db => ui.db;
  String get own => mesh.identity?.deviceId ?? ui.media.store.ownerDeviceId;

  Future<void> start({bool background = true}) async {
    await worker.warm();
    final peers = await worker.call('saved') as Map<String, JsonMap>;
    _peers.addAll(peers);
    _peersRevision++;
    _progressRevision++;
    if (background) startPolling();
  }

  /// Starts catalogue refresh ticks after the first complete publication.
  /// Starting the timer while the initial index is still running overlaps two
  /// prepares and puts their result deliveries into the same startup turn.
  void startPolling() {
    if (_closed || _timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _background());
  }

  void _background() {
    if (_closed) return;
    unawaited(refresh().then<void>((_) {}, onError: (Object e, StackTrace s) {
      lastError = e is Failure ? e.message : e.runtimeType.toString();
      Zone.current.handleUncaughtError(e, s);
    }));
  }

  Future<void> _save(String id, Object payload) async {
    final (encoded, fingerprint) = await _encodeSliced(payload);
    final old = await db.query('ui_cache',
        columns: ['fingerprint'], where: 'id=?', whereArgs: [id]);
    if (old.isNotEmpty && old.single['fingerprint'] == fingerprint) return;
    await db.insert(
        'ui_cache', {'id': id, 'fingerprint': fingerprint, 'payload': encoded},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<(String, String)> _encodeSliced(Object payload) =>
      Isolate.run(() => _encode(payload));

  Future<String?> _asset(String? path) async {
    if (path == null) return null;
    final real = await File(path).resolveSymbolicLinks();
    final stat = await File(real).stat();
    final id = 'asset:${_hash([
          real,
          stat.size,
          stat.modified.microsecondsSinceEpoch
        ])}';
    _playAssets[id] = real;
    return id;
  }

  /// Builds the local catalogue again when what it is made of has changed
  /// since it was last built, and not otherwise. The stamp is read in the
  /// library worker, before it reads the catalogue.
  Future<void> _build() {
    if (_indexIsCurrent) return Future<void>.value();
    return _building ??= (() async {
      final result = await worker.buildCurrent(own);
      builds += result.builds;
      _builtStamp = result.stamp;
    })()
        .whenComplete(() => _building = null);
  }

  /// How many times the local catalogue was built.
  int builds = 0;

  Future<void> refresh() =>
      _sync ??= _refresh().whenComplete(() => _sync = null);
  Future<void> _refresh() async {
    final before = _changeStamp();
    await _build();
    if (mesh.accountId != null) {
      for (final peer
          in mesh.cachedDevices.where((d) => d['deviceId'] != own)) {
        if (_closed) break;
        final id = peer['deviceId'] as String;
        if (peer['revoked'] == true) {
          _setOnline(id, false);
          heardTasks(id, null, null);
          continue;
        }
        try {
          _peerState[id] = {
            ...?_peerState[id],
            'refreshing': true,
            'lastAttemptAt': DateTime.now().toUtc().toIso8601String()
          };
          final old = _peers[id];
          final first = await mesh.rpc(id, 'mesh/library/snapshot', {
            'offset': 0,
            'encoding': librarySnapshotEncoding,
            'progressSeparately': true,
            'tasks': true,
            if (old?['version'] != null) 'known': old!['version']
          });
          heardTasks(id, peer['name'] as String? ?? '另一台设备', first['tasks']);
          if (first['progress'] is Map) {
            await _mergeProgress((first['progress'] as Map).map((key, value) =>
                MapEntry(
                    key as String, (value as Map).cast<String, Object?>())));
          }
          if (first['unchanged'] != true &&
              old?['version'] != first['version']) {
            final records = await readLibrarySnapshot(
                first, (input) => mesh.rpc(id, 'mesh/library/snapshot', input),
                cancelled: () => _closed);
            await _mergeProgress({
              for (final r in records.where((r) => r['kind'] == 'watch'))
                r['id'] as String: r['value'] as JsonMap
            });
            records.removeWhere((r) => r['kind'] == 'watch');
            final saved = <String, Object?>{
              'account': mesh.accountId,
              'name': peer['name'],
              'version': first['version'],
              'records': records
            };
            // Publish validated structure first. Optional artwork has its own
            // bounded task and cannot prevent a playable catalogue appearing.
            await _save('mesh:peer:$id', saved);
            _peers[id] = saved;
            _peersRevision++;
            _startArtwork(id, saved);
          }
          final current = _peers[id];
          final artworkAt = DateTime.tryParse(
              _peerState[id]?['artworkAttemptAt'] as String? ?? '');
          if (current != null &&
              (_peerState[id]?['artworkVersion'] != current['version'] ||
                  _peerState[id]?['artwork'] != 'complete' &&
                      (artworkAt == null ||
                          DateTime.now().difference(artworkAt) >=
                              const Duration(seconds: 30)))) {
            _startArtwork(id, current);
          }
          _setOnline(id, true);
          _peerErrors.remove(id);
          _peerState[id] = {
            ...?_peerState[id],
            'refreshing': false,
            'reachability': 'reachable',
            'catalogueFreshness': 'current',
            'lastSuccessAt': DateTime.now().toUtc().toIso8601String()
          };
        } on Failure catch (error) {
          await _catalogueFailed(id, error);
        } on FormatException catch (error) {
          await _catalogueFailed(
              id,
              Failure(FailureCode.invalidInput,
                  'Invalid peer catalogue: ${error.message}'));
        }
      }
      final devices = {for (final d in mesh.cachedDevices) d['deviceId']};
      for (final id in [..._peerTasks.keys]) {
        if (!devices.contains(id)) heardTasks(id, null, null);
      }
    } else {
      for (final id in _peers.keys) {
        _setOnline(id, false);
      }
      for (final id in [..._peerTasks.keys]) {
        heardTasks(id, null, null);
      }
    }
    await prepareIndex();
    if (before != _changeStamp()) ui.notifyLibraryChanged();
  }

  Future<void> _catalogueFailed(String id, Failure error) async {
    // Tasks it said before may have ended since: none are shown for it.
    heardTasks(id, null, null);
    // Catalogue failures do not establish that the file owner is offline.
    // Keep the last complete publication usable when a small authenticated
    // probe still reaches it; a real disconnect continues to disable playback.
    bool? reachable;
    try {
      await mesh.rpc(id, 'mesh/presence', {}, ungated: true);
      reachable = true;
    } on Failure catch (probe) {
      if (probe.details['responseReceived'] == true) reachable = true;
      if (probe.details['reason'] == 'not_delivered') reachable = false;
    }
    if (reachable != null) _setOnline(id, reachable);
    _peerErrors[id] = error.toJson();
    _peerState[id] = {
      ...?_peerState[id],
      'refreshing': false,
      'reachability': reachable == true
          ? 'reachable'
          : reachable == false
              ? 'unreachable'
              : 'unknown',
      'catalogueFreshness': _peers.containsKey(id) ? 'stale' : 'not_refreshed'
    };
    lastError = error.message;
  }

  Future<void> _mergeProgress(Map<String, JsonMap> values) async {
    if (await worker.call('merge', values) == true) {
      _progressRevision++;
      _composedStamp = null;
      invalidateIndex();
    }
  }

  void _setOnline(String id, bool value) {
    if (_online[id] == value) return;
    _online[id] = value;
    _onlineRevision++;
  }

  Future<void> recordProgress(String episodeId, double progress,
      {int? positionMs, int? durationMs}) async {
    await recordProgressBatch([
      {
        'episodeId': episodeId,
        'progress': progress,
        'positionMs': positionMs,
        'durationMs': durationMs
      }
    ]);
  }

  Future<void> recordProgressBatch(List<JsonMap> entries) async {
    await prepareIndex();
    if (entries.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Supply at least one episode observation.');
    }
    final update = await worker.call('progress', entries) as LibraryProgress;
    // Only touched works and their episodes change. No catalogue composition,
    // union-find, title indexing or full-map serialization runs on the UI.
    _works.addAll(update.works);
    _episodes.addAll(update.episodes);
    // Progress changes work values, never their IDs/order. In the lazy worker
    // projection the ID list may still be the immutable empty placeholder.
    if (searchIndex.ready) {
      for (final work in update.works.values) {
        searchIndex.updateProgress(workJson(work),
            update.episodes[work.workId]!.map(episodeJson).toList());
      }
    }
    _progressRevision++;
    ui.notifyLibraryChanged();
  }

  Future<List<UiWork>> library() async {
    await prepareIndex();
    await _ensurePackedWorks();
    final packed = _packedWorks;
    if (packed != null) {
      return UnmodifiableListView(_LibraryWorks(packed, _works));
    }
    return UnmodifiableListView([
      for (final id in _orderedWorkIds)
        if (_readWork(id) case final work?) work,
    ]);
  }

  Future<UiHome> home() async {
    await prepareIndex();
    final epoch = _indexEpoch;
    final cached = _home;
    if (cached != null && _homeEpoch == epoch) return cached;
    final loading = _homeLoading;
    if (loading != null && _homeLoadingEpoch == epoch) return loading;
    final future = worker.homePlan();
    _homeLoading = future;
    _homeLoadingEpoch = epoch;
    try {
      final value = await future;
      if (_homeLoadingEpoch == epoch) {
        _home = value;
        _homeEpoch = epoch;
      }
      return value;
    } finally {
      if (identical(_homeLoading, future)) {
        _homeLoading = null;
        _homeLoadingEpoch = null;
      }
    }
  }

  void invalidateIndex() {
    _indexPrepared = false;
    _indexEpoch++;
    _home = null;
    _homeEpoch = null;
  }

  Future<void> _ensurePackedWorks() async {
    if (_packedWorks != null) return;
    final packed = await worker.works();
    // A work decoded from the previous packed publication is not a cache for
    // this one: the same ID may now carry different device/online state.
    _works.clear();
    _packedWorks = packed;
  }

  bool get _indexIsCurrent =>
      _indexPrepared &&
      _preparedBuiltStamp == _builtStamp &&
      _preparedPeerRevision == _peersRevision &&
      _preparedOnlineRevision == _onlineRevision &&
      _preparedAccount == mesh.accountId;

  Future<void> prepareIndex() {
    final current = _preparing;
    if (current != null) return current;
    if (_indexIsCurrent) return Future<void>.value();
    final epoch = _indexEpoch;
    return _preparing =
        _prepareIndex(epoch).whenComplete(() => _preparing = null);
  }

  /// The worker owns the complete prepare loop: stamping, conditional build,
  /// composition and transfer. The UI publishes the result with reference
  /// replacements only.
  Future<void> _prepareIndex(int epoch) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final peerRevision = _peersRevision;
      final onlineRevision = _onlineRevision;
      final account = mesh.accountId;
      final result = await worker.prepare(
          owner: own,
          peers: _peers,
          peerRevision: peerRevision,
          online: _online,
          onlineRevision: onlineRevision,
          account: account,
          composedStamp: _composedStamp);
      startupPhase?.call('startup: Nipa mesh received');
      builds += result.builds;
      _builtStamp = result.builtStamp;
      if (result.composed) {
        compositions++;
        if (result.snapshot case final snapshot?) {
          _publish(snapshot);
        } else {
          _clearPublishedWorks();
        }
        startupPhase?.call('startup: Nipa mesh published');
        _composedStamp = result.compositionStamp;
      }
      if (epoch == _indexEpoch &&
          peerRevision == _peersRevision &&
          onlineRevision == _onlineRevision &&
          account == mesh.accountId) {
        _preparedBuiltStamp = _builtStamp;
        _preparedPeerRevision = peerRevision;
        _preparedOnlineRevision = onlineRevision;
        _preparedAccount = account;
        _indexPrepared = true;
        return;
      }
    }
  }

  void _clearPublishedWorks() {
    _assets.clear();
    _works.clear();
    _packedWorks = null;
    _orderedWorkIds = const [];
    _episodeParents.clear();
    _episodes.clear();
    _resolvedIds.clear();
    _locations.clear();
    _localTargets.clear();
  }

  Future<JsonMap> search(String query,
      {int limit = 12, int? episodeLimit}) async {
    if (searchIndex.ready) {
      return searchIndex.search(query,
          limit: limit, episodeLimit: episodeLimit);
    }
    await prepareIndex();
    return await worker.call('search', (query, limit, episodeLimit)) as JsonMap;
  }

  Future<List<String?>> searchWorkIds(List<ExternalRef> refs) async {
    if (searchIndex.ready) return refs.map(searchIndex.workId).toList();
    await prepareIndex();
    return (await worker.call('searchWorkIds', refs) as List).cast<String?>();
  }

  Future<JsonMap> managementTargets(List<String> ids) async {
    await prepareIndex();
    return await worker.call('managementTargets', ids) as JsonMap;
  }

  Future<String?> localEpisodeId(String id) async => await _localTarget(id);

  UiWork? _readWork(String id) {
    final cached = _works[id];
    final packed = _packedWorks;
    if (cached != null && (packed == null || packed.contains(id)))
      return cached;
    final record = packed?.record(id);
    if (record == null) return null;
    final work = transferredWorkValue(
        (jsonDecode(record) as Map).cast<String, Object?>());
    _works[id] = work;
    return work;
  }

  Future<String?> _localTarget(String target) async {
    final cached = _localTargets[target];
    if (cached != null) return cached;
    final found = await worker.localTarget(target);
    if (found != null) _localTargets[target] = found;
    return found;
  }

  Future<UiWork?> work(String id) async {
    await prepareIndex();
    await _ensurePackedWorks();
    return _readWork(id) ?? _readWork(await _canonical(id));
  }

  Future<String> canonical(String id) async {
    await prepareIndex();
    return await _canonical(id);
  }

  Future<String> resolvedId(String id) async {
    await prepareIndex();
    return await _canonical(id);
  }

  Future<String> _canonical(String id) async =>
      _resolvedIds[id] ??= await worker.canonical(id);
  Future<List<UiEpisode>> episodes(String id, {int? season}) async {
    await prepareIndex();
    return worker.episodes(id, season: season);
  }

  Future<String?> parent(String id) async {
    await prepareIndex();
    await _ensurePackedWorks();
    if (_readWork(id) != null) return id;
    final parent = await worker.parent(id);
    if (parent != null) _episodeParents[id] = parent;
    return parent;
  }

  Future<JsonMap> evidence(String id) async {
    await prepareIndex();
    return await worker.call('evidence', id) as JsonMap;
  }

  /// A work's page below its episodes, built in the worker from what the
  /// catalogue holds; only the small result crosses to this isolate.
  Future<JsonMap> workMore(String id) async {
    await prepareIndex();
    return await worker.call('workMore', id) as JsonMap;
  }

  /// Works of the catalogue crediting a person of [provider].
  Future<List<String>> worksCrediting(String provider, String person) async {
    await prepareIndex();
    return (await worker.call('worksCrediting', (provider, person)) as List)
        .cast<String>();
  }

  /// The complete projection is transferred by the worker. Publishing consists
  /// solely of reference replacements, independent of catalogue size.
  int compositions = 0;
  void _publish(LibrarySnapshot snapshot) {
    _assets = snapshot.assets;
    _works = {...snapshot.works};
    _packedWorks = snapshot.packedWorks;
    _orderedWorkIds = snapshot.packedWorks != null
        ? []
        : (snapshot.orderedWorks.isEmpty
            ? snapshot.works.keys.toList(growable: false)
            : [for (final work in snapshot.orderedWorks) work.workId]);
    _episodeParents = snapshot.episodeParents;
    _episodes = snapshot.episodes;
    _resolvedIds.clear();
    _locations = snapshot.locations;
    _localTargets = snapshot.localTargets;
  }

  Future<JsonMap> request(String method, JsonMap input, String peer) async {
    if (method.startsWith('mesh/library/files/')) {
      return files.request(method.split('/').last, input, peer);
    }
    switch (method) {
      case 'mesh/library/snapshot':
        await _build();
        final snapshot = await worker.call(
                'snapshot', ({...input, '_peerId': peer}, _progressRevision))
            as JsonMap;
        // What this device runs goes with the first page to a device that
        // shows it.
        return input['tasks'] == true && (input['offset'] ?? 0) == 0
            ? {...snapshot, 'tasks': await ui.meshTasks()}
            : snapshot;
      case 'mesh/library/file':
        final path = await _source(input);
        final stat = await File(path).stat();
        return {'size': stat.size, 'tag': _tag(stat), 'name': p.basename(path)};
      case 'mesh/library/read':
        final path = await _source(input), stat = await File(path).stat();
        final offset = input['offset'], length = input['length'];
        if (input['tag'] != _tag(stat)) {
          throw Failure(
              FailureCode.conflict, 'Source file changed since it was opened.',
              details: {
                'reason': 'file_changed',
                'stage': 'file_read',
                'fileId': input['fileId'],
                'actualTag': _tag(stat)
              });
        }
        if (offset is! int ||
            length is! int ||
            offset < 0 ||
            length < 0 ||
            length > 1048576 ||
            offset + length > stat.size) {
          throw const FormatException('Invalid or stale byte range.');
        }
        return {
          '_meshFile': {'path': path, 'offset': offset, 'length': length}
        };
      case 'mesh/library/play':
        return _playBundle(input);
      default:
        throw const FormatException('Unknown library method.');
    }
  }

  String _tag(FileStat stat) =>
      '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
  Future<String> _source(JsonMap input) async {
    if (input['path'] case final String path) return MeshFiles.absolute(path);
    if (input['assetId'] case final String id) {
      var found = _playAssets[id] ?? _assets[id];
      if (found == null) {
        await prepareIndex();
        found = _playAssets[id] ?? _assets[id];
      }
      if (found == null) {
        final loaded = await worker.asset(id);
        if (loaded != null) _assets[id] = loaded;
        found = loaded;
      }
      if (found == null) {
        throw const Failure(FailureCode.notFound, 'Unknown library asset.');
      }
      return found;
    }
    if (input['fileId'] is! String) {
      throw const FormatException('fileId or assetId required.');
    }
    final rows = await db.query('media_locations',
        where:
            "file_id=? AND owner_device_id=? AND source='local' AND available=1",
        whereArgs: [input['fileId'], ui.media.store.ownerDeviceId]);
    if (rows.isEmpty) {
      throw const Failure(
          FailureCode.notFound, 'File is not in this device library.');
    }
    return rows.first['locator'] as String;
  }

  Future<JsonMap> _playBundle(JsonMap input) async {
    final path = await _source(input);
    final fileId = input['fileId'] as String;
    final episodeId = input['episodeId'] as String;
    final links = await db.query('media_file_episodes',
        where: 'file_id=? AND episode_id=?', whereArgs: [fileId, episodeId]);
    if (links.isEmpty) {
      throw const FormatException('Episode is not in this file.');
    }
    await prepareDanmaku?.call(path, fileId, episodeId);
    final tracks = <JsonMap>[];
    final store = DanmakuStore(ui.media.store);
    await SidecarIndexer(store, () async {}).inspect(fileId, path);
    for (final entityId in [fileId, episodeId]) {
      final entity = await ui.media.store.entity(entityId);
      for (final binding in await store.bindings(entityId)) {
        if (binding['status'] != 'accepted' ||
            binding['entity_revision'] != entity['revision'] ||
            binding['cache_key'] == null) {
          continue;
        }
        final entries = await store.entries(binding['cache_key'] as String);
        final bytes =
            utf8.encode(jsonEncode([for (final e in entries) e.toJson()]));
        final dir = await Directory('${ui.mediaRoot.path}/mesh-assets')
            .create(recursive: true);
        final file = File('${dir.path}/${sha256.convert(bytes)}.json');
        if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
        tracks.add({
          'binding': binding,
          'assetId': await _asset(file.path),
          'startMs': entityId == episodeId ? links.single['start_ms'] ?? 0 : 0,
          'endMs': entityId == episodeId ? links.single['end_ms'] : null
        });
      }
    }
    // Sidecars use the same name matcher as the local subtitle host.
    final subtitles = await subtitleCompanions(ui, fileId, path);
    for (final t in subtitles) {
      if (t['origin'] != 'embedded' && t['available'] == true) {
        t['assetId'] =
            await _asset(t['playbackPath'] as String? ?? t['path'] as String);
        if (p.extension(t['path'] as String).toLowerCase() == '.idx') {
          t['pairAssetId'] =
              await _asset(p.setExtension(t['path'] as String, '.sub'));
        }
      }
    }
    return {
      'tracks': tracks,
      'subtitles': subtitles,
      'startMs': links.single['start_ms'] ?? 0,
      'endMs': links.single['end_ms']
    };
  }

  Future<List<int>> _bytes(
      String peer, JsonMap source, String tag, int offset, int length) async {
    final result = await mesh.rpc(peer, 'mesh/library/read',
        {...source, 'tag': tag, 'offset': offset, 'length': length});
    final bytes = base64Decode(result['data'] as String);
    if (bytes.length != length) {
      throw const Failure(FailureCode.conflict, 'Incomplete source file range.',
          details: {'reason': 'file_range_incomplete', 'stage': 'file_read'});
    }
    return bytes;
  }

  Future<String> cacheAsset(String peer, String id,
      {String? name,
      DateTime? deadline,
      void Function(String)? onStage}) async {
    final directory = await Directory('${ui.mediaRoot.path}/mesh-artwork')
        .create(recursive: true);
    final file = File('${directory.path}/${_hash([
          peer,
          id
        ])}${name == null ? '' : p.extension(name)}');
    if (await file.exists()) return file.path;
    if (_assetReads.length >= 16 && !_assetReads.containsKey(file.path)) {
      throw const Failure(
          FailureCode.unavailable, 'Asset transfer capacity exhausted.',
          details: {'reason': 'asset_transfer_capacity'});
    }
    return _assetReads.putIfAbsent(
        file.path,
        () => (() async {
              final until =
                  deadline ?? DateTime.now().add(const Duration(minutes: 2));
              Duration remaining() {
                if (_closed || !DateTime.now().isBefore(until)) {
                  throw const Failure(
                      FailureCode.unavailable, 'Asset transfer stopped.',
                      details: {
                        'reason': 'asset_transfer_cancelled_or_expired'
                      });
                }
                return until.difference(DateTime.now());
              }

              final source = <String, Object?>{'assetId': id};
              onStage?.call('asset_info');
              final info = await mesh
                  .rpc(peer, 'mesh/library/file', source)
                  .timeout(remaining());
              final size = info['size'];
              if (size is! int || size < 0 || size > 64 * 1024 * 1024) {
                throw const Failure(FailureCode.unavailable,
                    'Asset exceeds the 64 MiB transfer budget.',
                    details: {'reason': 'asset_byte_capacity'});
              }
              remaining();
              final temporary = File('${file.path}.tmp');
              final output = await temporary.open(mode: FileMode.write);
              var outputClosed = false;
              try {
                for (var offset = 0; offset < size; offset += 1048576) {
                  onStage?.call('asset_read');
                  final bytes = await _bytes(
                          peer,
                          source,
                          info['tag'] as String,
                          offset,
                          math.min(size - offset, 1048576))
                      .timeout(remaining());
                  remaining();
                  await output.writeFrom(bytes);
                  onStage?.call('asset_flush');
                  await output.flush();
                }
                onStage?.call('asset_close');
                outputClosed = true;
                await output.close();
                remaining();
                onStage?.call('asset_publish');
                await temporary.rename(file.path);
                return file.path;
              } catch (_) {
                if (!outputClosed) await output.close();
                if (await temporary.exists()) await temporary.delete();
                rethrow;
              }
            })()
                .whenComplete(() {
              // Returning remove() would return this very Future: whenComplete
              // would then wait for itself forever after the file was saved.
              _assetReads.remove(file.path);
            }));
  }

  void _startArtwork(String peer, JsonMap publication) {
    if (_artworkTasks.containsKey(peer) || _closed) return;
    _peerState[peer] = {
      ...?_peerState[peer],
      'artwork': 'loading',
      'artworkFailure': null,
      'artworkAssetId': null,
      'artworkAttemptAt': DateTime.now().toUtc().toIso8601String()
    };
    _artworkTasks[peer] = (() async {
      void stage(String value, [JsonMap facts = const {}]) {
        _peerState[peer] = {
          ...?_peerState[peer],
          'artworkStage': value,
          'artworkUpdatedAt': DateTime.now().toUtc().toIso8601String(),
          ...facts,
        };
      }

      stage('preparing');
      final records = (publication['records'] as List).cast<JsonMap>();
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      var missing = 0;
      // Work on a copy, retaining the published structure on any asset failure.
      final copied = (jsonDecode(jsonEncode(records)) as List).cast<JsonMap>();
      for (final record in copied) {
        if (_closed || !identical(_peers[peer], publication)) return;
        final value = record['value'] as JsonMap;
        final paths =
            record['kind'] == 'work' ? value['artwork'] as JsonMap : value;
        for (final key in record['kind'] == 'work'
            ? ['poster', 'backdrop', 'logo']
            : ['still']) {
          final assetIds =
              (record['_artworkSources'] as Map?)?.cast<String, Object?>() ??
                  <String, Object?>{};
          record['_artworkSources'] = assetIds;
          if (paths[key] case final String path when path.startsWith('asset:'))
            assetIds[key] = path;
          if (assetIds[key] case final String asset) {
            if (!DateTime.now().isBefore(deadline)) {
              missing++;
              paths[key] = null;
              stage('asset_failed', {
                'artworkFailure': {
                  'failureCode': 'timeout',
                  'reason': 'artwork_deadline',
                }
              });
              continue;
            }
            try {
              stage('fetching_asset', {'artworkAssetId': asset});
              paths[key] = await cacheAsset(peer, asset,
                  deadline: deadline, onStage: (value) => stage(value));
            } catch (error) {
              missing++;
              paths[key] = null;
              stage('asset_failed', {
                'artworkFailure': error is Failure
                    ? OperationObservations.failure(error)
                    : {
                        'failureCode':
                            error is TimeoutException ? 'timeout' : 'internal'
                      },
              });
            }
          }
        }
      }
      if (_closed || !identical(_peers[peer], publication)) return;
      final updated = {...publication, 'records': copied};
      stage('saving');
      await _save('mesh:peer:$peer', updated);
      if (_closed || !identical(_peers[peer], publication)) return;
      _peers[peer] = updated;
      _peersRevision++;
      _peerState[peer] = {
        ...?_peerState[peer],
        'artwork': missing == 0 ? 'complete' : 'partial',
        'artworkVersion': publication['version'],
        'missingArtwork': missing
      };
      stage('publishing');
      await prepareIndex();
      stage('settled');
      ui.notifyLibraryChanged();
    })()
        .catchError((Object error) {
      _peerState[peer] = {
        ...?_peerState[peer],
        'artwork': 'failed',
        'artworkFailure': error is Failure
            ? OperationObservations.failure(error)
            : {'failureCode': 'internal'},
        'artworkVersion': publication['version']
      };
    }).whenComplete(() {
      _artworkTasks.remove(peer);
      final current = _peers[peer];
      if (!_closed &&
          current != null &&
          !identical(current, publication) &&
          _peerState[peer]?['artworkVersion'] != current['version']) {
        _startArtwork(peer, current);
      }
    });
  }

  Future<JsonMap> readable(String id) async {
    await prepareIndex();
    final target = await _canonical(id);
    var candidates = _locations[target];
    if (candidates == null) {
      candidates = _locations[target] = await worker.episodeLocations(target);
    }
    final localTarget = await _localTarget(target);
    if (candidates.isEmpty && localTarget != null) {
      final rows = await db.rawQuery(
          'SELECT l.locator,l.file_id AS fileId,f.attributes FROM media_locations l JOIN media_file_episodes e ON e.file_id=l.file_id JOIN media_entities f ON f.id=l.file_id WHERE e.episode_id=? AND l.owner_device_id=? AND l.available=1 ORDER BY l.id',
          [localTarget, ui.media.store.ownerDeviceId]);
      if (rows.isNotEmpty) {
        return {
          'episodeId': target,
          'path': rows.first['locator'],
          'fileId': rows.first['fileId'],
          'sourceInfo': (jsonDecode(rows.first['attributes'] as String)
              as Map)['remoteSource']
        };
      }
    }
    if (candidates.isEmpty) {
      throw const Failure(
          FailureCode.notFound, 'No recorded native file for episode.');
    }
    var location = candidates.where((l) => l['online'] == true).firstOrNull;
    // A saved catalogue is usable before a successful refresh. Probe the file
    // owner independently instead of making catalogue freshness a play gate.
    if (location == null) {
      for (final candidate in candidates.take(3)) {
        final peer = candidate['deviceId'] as String;
        try {
          await mesh.rpc(peer, 'mesh/presence', {}, ungated: true);
          _setOnline(peer, true);
          location = {...candidate, 'online': true};
          break;
        } on Failure catch (error) {
          _peerState[peer] = {
            ...?_peerState[peer],
            'reachability': error.details['reason'] == 'not_delivered'
                ? 'unreachable'
                : 'unknown'
          };
        }
      }
    }
    if (location == null) {
      throw Failure(FailureCode.unavailable,
          'Source reachability has not been confirmed.',
          details: {
            'reason': 'source_not_verified',
            'stage': 'resolve_source',
            'sources': refreshStatus['peers'],
            'cataloguePreserved': true
          });
    }
    if (location['local'] == true) {
      return {
        'episodeId': target,
        'path': await _source(location),
        ...location
      };
    }
    final peer = location['deviceId'] as String;
    final result = <String, Object?>{
      ...location,
      ...await fileReadable(peer, {'fileId': location['fileId']}),
      'episodeId': target
    };
    playback[result['url'] as String] = result;
    return result;
  }

  Future<JsonMap> fileReadable(String peer, JsonMap source) async {
    if (_closed) {
      throw const Failure(FailureCode.unavailable, 'File proxy is closed.');
    }
    if (peer == own) return {'path': await _source(source)};
    final info = await mesh.rpc(peer, 'mesh/library/file', source);
    await _ensureHttp();
    if (_closed) {
      throw const Failure(FailureCode.unavailable, 'File proxy is closed.');
    }
    final random = math.Random.secure();
    final token = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    _readers[token] = {'deviceId': peer, 'source': source, ...info};
    final url =
        'http://127.0.0.1:${_http!.port}/$token/${Uri.encodeComponent(info['name'] as String)}';
    return {...info, 'deviceId': peer, 'url': url};
  }

  JsonMap get fileProxyStatus => {
        'id': 'local',
        'host': '127.0.0.1',
        'state': _proxyState,
        'requestedPort': _requestedPort,
        'port': _http?.port,
        'fallback': _proxyState == 'random_fallback',
        'reason': _proxyReason,
      };

  Future<void> _ensureHttp() async {
    if (_closed) {
      throw const Failure(FailureCode.unavailable, 'File proxy is closed.');
    }
    if (_http != null) return;
    await (_httpBinding ??=
        _bindHttp().whenComplete(() => _httpBinding = null));
  }

  Future<void> _hostConfigurationChanged() async {
    final configured = mesh.hostConfiguration['fileProxyPort'] ?? 0;
    if (configured == _requestedPort) return;
    await _httpBinding;
    await _http?.close(force: true);
    for (final stream in _streams) {
      stream.destroy();
    }
    _streams.clear();
    _http = null;
    _readers.clear();
    playback.clear();
    _assets.clear();
    if (configured is int) {
      _requestedPort = configured;
    }
    _proxyState = 'not_started';
    _proxyReason = null;
    ui.notifyLibraryChanged();
  }

  Future<void> _bindHttp() async {
    final configured = mesh.hostConfiguration['fileProxyPort'] ?? 0;
    if (configured is! int ||
        (configured != 0 && (configured < 1024 || configured > 65535))) {
      _proxyState = 'invalid_configuration';
      _proxyReason = 'fileProxyPort must be 0 or an integer in 1024..65535.';
      ui.notifyLibraryChanged();
      throw Failure(FailureCode.invalidInput, _proxyReason!);
    }
    _requestedPort = configured;
    _proxyReason = null;
    try {
      _http = await HttpServer.bind(InternetAddress.loopbackIPv4, configured);
      _proxyState = configured == 0 ? 'random' : 'fixed';
    } on SocketException catch (error) {
      final inUse = {48, 98, 10048}.contains(error.osError?.errorCode) ||
          error.osError?.message
                  .startsWith('The shared flag to bind() needs to be') ==
              true;
      if (configured == 0 || !inUse) rethrow;
      _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _proxyState = 'random_fallback';
      _proxyReason = 'requested_port_in_use';
    }
    _http!.listen(_serve);
    ui.notifyLibraryChanged();
  }

  Future<JsonMap?> open(String id) async {
    await prepareIndex();
    final target = await _canonical(id);
    await _ensurePackedWorks();
    if (_readWork(target) != null) return {'workId': target};
    if (await _localTarget(target) == null &&
        await worker.parent(target) == null) {
      return null;
    }
    final result = await readable(target);
    if (result['url'] != null) {
      final bundle = await mesh.rpc(
          result['deviceId'] as String,
          'mesh/library/play',
          {'fileId': result['fileId'], 'episodeId': result['sourceEpisodeId']});
      result['bundle'] = bundle;
      playback[result['url'] as String] = result;
    }
    final ep = await worker.episode(target);
    if (ep == null) {
      throw const Failure(FailureCode.notFound, 'Unknown episode.');
    }
    final start = result['startMs'] as int? ?? 0;
    final resume = ep.resumePosition;
    if (resume != null || start != 0) {
      result['resumeMs'] = start + (resume?.inMilliseconds ?? 0);
    }
    return result;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final record = request.uri.pathSegments.isEmpty
        ? null
        : _readers[request.uri.pathSegments.first];
    if (record == null) {
      response.statusCode = 404;
      await response.close();
      return;
    }
    if (!['GET', 'HEAD'].contains(request.method)) {
      response.statusCode = 405;
      await response.close();
      return;
    }
    final size = record['size'] as int;
    var start = 0, end = size - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
        response.statusCode = 416;
        response.headers.set('Content-Range', 'bytes */$size');
        await response.close();
        return;
      }
      if (match[1]!.isEmpty) {
        start = math.max(0, size - int.parse(match[2]!));
      } else {
        start = int.parse(match[1]!);
        if (match[2]!.isNotEmpty) end = math.min(end, int.parse(match[2]!));
      }
      if (start > end || start >= size) {
        response.statusCode = 416;
        response.headers.set('Content-Range', 'bytes */$size');
        await response.close();
        return;
      }
      response.statusCode = 206;
      response.headers.set('Content-Range', 'bytes $start-$end/$size');
    }
    response.headers.set('Accept-Ranges', 'bytes');
    response.headers.set('Content-Type', 'application/octet-stream');
    response.contentLength = math.max(0, end - start + 1);
    var disconnected = false;
    Socket? stream;
    StreamSubscription<List<int>>? disconnect;
    try {
      if (request.method == 'GET') {
        // A read EOF only closes the client's sending half. It may still be
        // receiving the response. A reset/write failure terminates streaming.
        // One response per socket also prevents a pipelined request from being
        // interpreted as file bytes after handing off the HTTP headers.
        response.persistentConnection = false;
        final output = stream = await response.detachSocket();
        _streams.add(output);
        disconnect = output.listen((_) {
          disconnected = true;
          output.destroy();
        }, onError: (Object _) {
          disconnected = true;
        }, cancelOnError: true);
        for (var offset = start; offset <= end; offset += 1048576) {
          if (_closed || disconnected) break;
          final bytes = await _bytes(
              record['deviceId'] as String,
              record['source'] as JsonMap,
              record['tag'] as String,
              offset,
              math.min(1048576, end - offset + 1));
          if (_closed || disconnected) break;
          output.add(bytes);
          await output.flush();
        }
        await output.close();
      } else {
        await response.close();
      }
    } on Object catch (error) {
      if (!disconnected && !_closed) {
        lastError =
            error is Failure ? error.message : error.runtimeType.toString();
      }
      if (stream == null) {
        try {
          (await response.detachSocket()).destroy();
        } on Object {
          // The response or socket is already gone.
        }
      }
    } finally {
      _streams.remove(stream);
      await disconnect?.cancel();
      stream?.destroy();
    }
  }

  /// Next's interface is closed: the merged library is not refreshed until
  /// [start] again.
  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    await _sync;
    await _building;
    await _preparing;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    for (final stream in _streams) {
      stream.destroy();
    }
    _streams.clear();
    await _http?.close(force: true);
    await _sync;
    await _building;
    await _httpBinding;
    await _http?.close(force: true);
    for (final stream in _streams) {
      stream.destroy();
    }
    _streams.clear();
    _http = null;
    _readers.clear();
    playback.clear();
    _proxyState = 'closed';
    await _preparing;
    await _libraryChanges?.cancel();
    _libraryChanges = null;
    await worker.close();
    ui.state.queryWorker = null;
    await files.close();
    mesh.libraryRequest = null;
    mesh.hostConfigurationChanged = null;
  }
}

/// A stable catalogue-sized list whose records are decoded only when a view
/// reads that index. The worker's packed publication keeps startup from
/// materialising every UiWork before the first frame.
final class _LibraryWorks extends ListBase<UiWork> {
  _LibraryWorks(this._packed, this._cache);
  final PackedWorks _packed;
  final Map<String, UiWork> _cache;

  @override
  int get length => _packed.length;

  @override
  set length(int value) => throw UnsupportedError('Cannot resize library view');

  @override
  UiWork operator [](int index) {
    final id = _packed.idAt(index);
    final cached = _cache[id];
    if (cached != null) return cached;
    final record = _packed.record(id);
    if (record == null) throw StateError('Missing published work $id');
    final work = transferredWorkValue(
        (jsonDecode(record) as Map).cast<String, Object?>());
    _cache[id] = work;
    return work;
  }

  @override
  void operator []=(int index, UiWork value) =>
      throw UnsupportedError('Cannot replace library view entries');
}

(String, String) _encode(Object payload) {
  final encoded = jsonEncode(payload);
  return (encoded, sha256.convert(utf8.encode(encoded)).toString());
}
