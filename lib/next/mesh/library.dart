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
import '../danmaku/store.dart';
import '../danmaku/sidecar.dart';
import 'runtime.dart';
import 'library_codec.dart';
import 'library_worker.dart';
import 'library_projection.dart';
import '../ui_data/library_search.dart';
import '../media/metadata_provider.dart';
import 'files.dart';

String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

/// A projection of each owner's catalogue, never a copy of its database.
final class MeshLibrary {
  MeshLibrary(this.ui, this.mesh) {
    worker = LibraryWorker(ui);
    ui.state.queryWorker = worker.query;
    files = MeshFiles(mesh, fileReadable, ui.media.store.ownerDeviceId);
    mesh.libraryRequest = request;
    ui.media.searchWorkIds = searchWorkIds;
    mesh.hostConfigurationChanged = _hostConfigurationChanged;
  }
  late final MeshFiles files;
  late final LibraryWorker worker;
  final UiDataService ui;
  final MeshRuntime mesh;
  final _peers = <String, JsonMap>{};
  final _online = <String, bool>{};
  Map<String, String> _assets = {};
  final _playAssets = <String, String>{};
  Map<String, UiWork> _works = {};
  List<UiWork> _orderedWorks = [];
  Map<String, String> _episodeParents = {};
  LibrarySearchIndex searchIndex = LibrarySearchIndex();
  Map<String, List<UiEpisode>> _episodes = {};
  Map<String, String> _aliases = {};
  Map<String, List<JsonMap>> _locations = {};
  Map<String, String> _localTargets = {};

  Future<void>? _sync, _building;
  String? _builtStamp;
  String? _composedStamp;

  /// Progress moves independently of the catalogue's composition revision.
  int _peersRevision = 0, _progressRevision = 0;
  String _changeStamp() => jsonEncode([_builtStamp, _peersRevision, _online]);
  Timer? _timer;
  HttpServer? _http;
  Future<void>? _httpBinding;
  int _requestedPort = 0;
  String _proxyState = 'not_started';
  String? _proxyReason;
  final _readers = <String, JsonMap>{};
  final playback = <String, JsonMap>{};
  bool _closed = false;
  String? lastError;
  DateTime _deviceRead = DateTime.fromMillisecondsSinceEpoch(0);
  Database get db => ui.db;
  String get own => mesh.identity?.deviceId ?? ui.media.store.ownerDeviceId;

  Future<void> start() async {
    await worker.warm();
    final peers = await worker.call('saved') as Map<String, JsonMap>;
    _peers.addAll(peers);
    _peersRevision++;
    _progressRevision++;
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

  /// What the local catalogue is built from, told by a few integers: the
  /// database's change epoch and Classic's state (see
  /// [UiDataService.catalogueStamp]).
  Future<String> _stamp() async => jsonEncode([own, await ui.catalogueStamp()]);

  /// Builds the local catalogue again when what it is made of has changed
  /// since it was last built, and not otherwise. The stamp is taken before
  /// reading, so a change made meanwhile builds once more.
  Future<void> _build() => _building ??= (() async {
        for (var attempt = 0; attempt < 3; attempt++) {
          final stamp = await _stamp();
          if (_builtStamp == stamp) return;
          builds++;
          await worker.build('$_run:$stamp');
          _builtStamp = stamp;
        }
      })()
          .whenComplete(() => _building = null);

  /// How many times the local catalogue was built.
  int builds = 0;

  /// Tells this run's versions from an earlier run's: Classic's state, which
  /// they also stand for, starts over with it.
  final _run = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> refresh() =>
      _sync ??= _refresh().whenComplete(() => _sync = null);
  Future<void> _refresh() async {
    final before = _changeStamp();
    await _build();
    if (mesh.accountId != null) {
      if (DateTime.now().difference(_deviceRead).inSeconds >= 30) {
        await mesh.refreshDevices();
        _deviceRead = DateTime.now();
      }
      for (final peer
          in mesh.cachedDevices.where((d) => d['deviceId'] != own)) {
        final id = peer['deviceId'] as String;
        if (peer['revoked'] == true) {
          _online[id] = false;
          continue;
        }
        try {
          final old = _peers[id];
          final first = await mesh.rpc(id, 'mesh/library/snapshot', {
            'offset': 0,
            if (old?['version'] != null) 'known': old!['version']
          });
          if (first['unchanged'] != true &&
              old?['version'] != first['version']) {
            final records = (first['records'] as List).cast<JsonMap>().toList();
            var next = first['next'] as int?;
            while (next != null) {
              final page = await mesh.rpc(id, 'mesh/library/snapshot',
                  {'offset': next, 'version': first['version']});
              if (page['version'] != first['version'])
                throw const Failure(
                    FailureCode.conflict, 'Library changed during pagination.');
              records.addAll((page['records'] as List).cast<JsonMap>());
              next = page['next'] as int?;
            }
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
            await _cacheArtwork(id, records);
            _peers[id] = saved;
            _peersRevision++;
            await _save('mesh:peer:$id', saved);
          }
          _online[id] = true;
        } on Failure catch (error) {
          _online[id] = false;
          lastError = error.message;
        }
      }
    } else {
      for (final id in _peers.keys) _online[id] = false;
    }
    await _compose();
    if (before != _changeStamp()) ui.notifyLibraryChanged();
  }

  Future<void> _mergeProgress(Map<String, JsonMap> values) async {
    if (await worker.call('merge', values) == true) _progressRevision++;
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
    if (entries.isEmpty)
      throw const Failure(
          FailureCode.invalidInput, 'Supply at least one episode observation.');
    final update = await worker.call('progress', entries) as LibraryProgress;
    // Only touched works and their episodes change. No catalogue composition,
    // union-find, title indexing or full-map serialization runs on the UI.
    _works.addAll(update.works);
    _episodes.addAll(update.episodes);
    for (final entry in update.orderedUpdates.entries) {
      _orderedWorks[entry.key] = entry.value;
    }
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
    return UnmodifiableListView(_orderedWorks);
  }

  Future<void> prepareIndex() async {
    await _build();
    await _compose();
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

  String? localEpisodeId(String id) => _localTargets[_aliases[id] ?? id];

  Future<UiWork?> work(String id) async {
    await prepareIndex();
    return _works[_aliases[id] ?? id];
  }

  Future<String> canonical(String id) async {
    await prepareIndex();
    return _aliases[id] ?? id;
  }

  String resolvedId(String id) => _aliases[id] ?? id;
  Future<List<UiEpisode>> episodes(String id, {int? season}) async {
    await prepareIndex();
    return (_episodes[_aliases[id] ?? id] ?? [])
        .where((e) => season == null || e.season == season)
        .toList();
  }

  Future<String?> parent(String id) async {
    await prepareIndex();
    final target = _aliases[id] ?? id;
    if (_works.containsKey(target)) return target;
    return _episodeParents[target];
  }

  Future<JsonMap> evidence(String id) async {
    await prepareIndex();
    return await worker.call('evidence', id) as JsonMap;
  }

  Future<void>? _composing;

  /// Composes again when what it is made of has changed since, and not
  /// otherwise. A call that comes while one runs waits for it, and the run
  /// looks again before it returns, so a change made meanwhile is composed.
  Future<void> _compose() => _composing ??= (() async {
        for (var attempt = 0; attempt < 3; attempt++) {
          final composition = jsonEncode([own, _changeStamp()]);
          if (_composedStamp == composition) return;
          await _composeNow();
          _composedStamp = composition;
        }
      })()
          .whenComplete(() => _composing = null);

  /// The complete projection is transferred by the worker. Publishing consists
  /// solely of reference replacements, independent of catalogue size.
  int compositions = 0;
  Future<void> _composeNow() async {
    final result = await worker.compose(_peers, _online, mesh.accountId);
    compositions++;
    _assets = result.assets;
    _works = result.works;
    _orderedWorks = result.orderedWorks;
    _episodeParents = result.episodeParents;
    _episodes = result.episodes;
    _aliases = result.aliases;
    _locations = result.locations;
    _localTargets = result.localTargets;
  }

  Future<JsonMap> request(String method, JsonMap input, String peer) async {
    if (method.startsWith('mesh/library/files/'))
      return files.request(method.split('/').last, input, peer);
    switch (method) {
      case 'mesh/library/snapshot':
        await _build();
        return await worker.call('snapshot', (input, _progressRevision))
            as JsonMap;
      case 'mesh/library/file':
        final path = await _source(input);
        final stat = await File(path).stat();
        return {'size': stat.size, 'tag': _tag(stat), 'name': p.basename(path)};
      case 'mesh/library/read':
        final path = await _source(input), stat = await File(path).stat();
        final offset = input['offset'], length = input['length'];
        if (input['tag'] != _tag(stat) ||
            offset is! int ||
            length is! int ||
            offset < 0 ||
            length < 0 ||
            length > 1048576 ||
            offset + length > stat.size)
          throw const FormatException('Invalid or stale byte range.');
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
      final path = _playAssets[id] ?? _assets[id];
      if (path == null) await prepareIndex();
      final found = _playAssets[id] ?? _assets[id];
      if (found == null)
        throw const Failure(FailureCode.notFound, 'Unknown library asset.');
      return found;
    }
    if (input['fileId'] is! String)
      throw const FormatException('fileId or assetId required.');
    final rows = await db.query('media_locations',
        where:
            "file_id=? AND owner_device_id=? AND source='local' AND available=1",
        whereArgs: [input['fileId'], ui.media.store.ownerDeviceId]);
    if (rows.isEmpty)
      throw const Failure(
          FailureCode.notFound, 'File is not in this device library.');
    return rows.first['locator'] as String;
  }

  Future<JsonMap> _playBundle(JsonMap input) async {
    final path = await _source(input);
    final fileId = input['fileId'] as String;
    final episodeId = input['episodeId'] as String;
    final links = await db.query('media_file_episodes',
        where: 'file_id=? AND episode_id=?', whereArgs: [fileId, episodeId]);
    if (links.isEmpty)
      throw const FormatException('Episode is not in this file.');
    final tracks = <JsonMap>[];
    final store = DanmakuStore(ui.media.store);
    await SidecarIndexer(store, () async {}).inspect(fileId, path);
    for (final entityId in [fileId, episodeId]) {
      final entity = await ui.media.store.entity(entityId);
      for (final binding in await store.bindings(entityId)) {
        if (binding['status'] != 'accepted' ||
            binding['entity_revision'] != entity['revision'] ||
            binding['cache_key'] == null) continue;
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
        if (p.extension(t['path'] as String).toLowerCase() == '.idx')
          t['pairAssetId'] =
              await _asset(p.setExtension(t['path'] as String, '.sub'));
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
    return base64Decode(result['data'] as String);
  }

  Future<String> cacheAsset(String peer, String id, {String? name}) async {
    final directory = await Directory('${ui.mediaRoot.path}/mesh-artwork')
        .create(recursive: true);
    final file = File('${directory.path}/${_hash([
          peer,
          id
        ])}${name == null ? '' : p.extension(name)}');
    if (await file.exists()) return file.path;
    final source = <String, Object?>{'assetId': id};
    final info = await mesh.rpc(peer, 'mesh/library/file', source);
    final size = info['size'] as int;
    final temporary = File('${file.path}.tmp'), output = temporary.openWrite();
    try {
      for (var offset = 0; offset < size; offset += 1048576)
        output.add(await _bytes(peer, source, info['tag'] as String, offset,
            math.min(size - offset, 1048576)));
      await output.close();
      await temporary.rename(file.path);
      return file.path;
    } catch (_) {
      await output.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> _cacheArtwork(String peer, List<JsonMap> records) async {
    for (final record in records) {
      final value = record['value'] as JsonMap;
      final paths =
          record['kind'] == 'work' ? value['artwork'] as JsonMap : value;
      for (final key in record['kind'] == 'work'
          ? ['poster', 'backdrop', 'logo']
          : ['still']) {
        if (paths[key] case final String asset)
          paths[key] = await cacheAsset(peer, asset);
      }
    }
  }

  Future<JsonMap> readable(String id) async {
    await prepareIndex();
    final target = _aliases[id] ?? id;
    final candidates = _locations[target];
    if ((candidates == null || candidates.isEmpty) &&
        _localTargets[target] != null) {
      final rows = await db.rawQuery(
          'SELECT l.locator,l.file_id AS fileId,f.attributes FROM media_locations l JOIN media_file_episodes e ON e.file_id=l.file_id JOIN media_entities f ON f.id=l.file_id WHERE e.episode_id=? AND l.owner_device_id=? AND l.available=1 ORDER BY l.id',
          [_localTargets[target], ui.media.store.ownerDeviceId]);
      if (rows.isNotEmpty)
        return {
          'episodeId': target,
          'path': rows.first['locator'],
          'fileId': rows.first['fileId'],
          'sourceInfo': (jsonDecode(rows.first['attributes'] as String)
              as Map)['remoteSource']
        };
    }
    if (candidates == null || candidates.isEmpty)
      throw const Failure(
          FailureCode.notFound, 'No recorded native file for episode.');
    final location = candidates.where((l) => l['online'] == true).firstOrNull;
    if (location == null)
      throw const Failure(FailureCode.unavailable, 'Source device is offline.');
    if (location['local'] == true)
      return {
        'episodeId': target,
        'path': await _source(location),
        ...location
      };
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
    if (_closed)
      throw const Failure(FailureCode.unavailable, 'File proxy is closed.');
    if (peer == own) return {'path': await _source(source)};
    final info = await mesh.rpc(peer, 'mesh/library/file', source);
    await _ensureHttp();
    if (_closed)
      throw const Failure(FailureCode.unavailable, 'File proxy is closed.');
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
    if (_closed)
      throw const Failure(FailureCode.unavailable, 'File proxy is closed.');
    if (_http != null) return;
    await (_httpBinding ??=
        _bindHttp().whenComplete(() => _httpBinding = null));
  }

  Future<void> _hostConfigurationChanged() async {
    final configured = mesh.hostConfiguration['fileProxyPort'] ?? 0;
    if (configured == _requestedPort) return;
    await _httpBinding;
    await _http?.close(force: true);
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
    final target = _aliases[id] ?? id;
    if (_works.containsKey(target)) return {'workId': target};
    if (!_locations.containsKey(target)) return null;
    final result = await readable(target);
    if (result['url'] != null) {
      final bundle = await mesh.rpc(
          result['deviceId'] as String,
          'mesh/library/play',
          {'fileId': result['fileId'], 'episodeId': result['sourceEpisodeId']});
      result['bundle'] = bundle;
      playback[result['url'] as String] = result;
    }
    final ep = _episodes.values
        .expand((e) => e)
        .singleWhere((e) => e.episodeId == target);
    result['resumeMs'] = (result['startMs'] as int? ?? 0) +
        ((ep.progress ?? 0) < 1
            ? ((ep.progress ?? 0) * (ep.runtime?.inMilliseconds ?? 0)).round()
            : 0);
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
      if (match[1]!.isEmpty)
        start = math.max(0, size - int.parse(match[2]!));
      else {
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
    try {
      if (request.method == 'GET') {
        for (var offset = start; offset <= end; offset += 1048576) {
          response.add(await _bytes(
              record['deviceId'] as String,
              record['source'] as JsonMap,
              record['tag'] as String,
              offset,
              math.min(1048576, end - offset + 1)));
          await response.flush();
        }
      }
      await response.close();
    } on Object catch (error) {
      lastError =
          error is Failure ? error.message : error.runtimeType.toString();
      response.detachSocket().then((socket) => socket.destroy());
    }
  }

  /// Next's interface is closed: the merged library is not refreshed until
  /// [start] again.
  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    await _sync;
    await _building;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _sync;
    await _building;
    await _httpBinding;
    await _http?.close(force: true);
    _http = null;
    _readers.clear();
    playback.clear();
    _proxyState = 'closed';
    await _composing;
    await worker.close();
    ui.state.queryWorker = null;
    await files.close();
    mesh.libraryRequest = null;
    mesh.hostConfigurationChanged = null;
  }
}

(String, String) _encode(Object payload) {
  final encoded = jsonEncode(payload);
  return (encoded, sha256.convert(utf8.encode(encoded)).toString());
}
