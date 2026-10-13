import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import '../harness_redaction.dart';
import 'runtime.dart';
import 'library_codec.dart';
import '../ui_data/library_index.dart';
import 'files.dart';

String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
bool _newer(JsonMap a, JsonMap b) {
  final compared = DateTime.parse(a['at'] as String)
      .compareTo(DateTime.parse(b['at'] as String));
  return compared > 0 ||
      (compared == 0 &&
          (a['writer'] as String).compareTo(b['writer'] as String) > 0);
}

String _ref(String device, String id) =>
    'mesh-ref:${base64Url.encode(utf8.encode(jsonEncode([
              device,
              id
            ]))).replaceAll('=', '')}';

/// A projection of each owner's catalogue, never a copy of its database.
final class MeshLibrary {
  MeshLibrary(this.ui, this.mesh) {
    files = MeshFiles(mesh, fileReadable, ui.media.store.ownerDeviceId);
    mesh.libraryRequest = request;
  }
  late final MeshFiles files;
  final UiDataService ui;
  final MeshRuntime mesh;
  final _peers = <String, JsonMap>{};
  final _online = <String, bool>{};
  final _assets = <String, String>{};
  final _samples = <String, (String, String)>{};
  final _added = <String, int>{};
  final _progress = <String, JsonMap>{};
  final _works = <String, UiWork>{};
  final _episodes = <String, List<UiEpisode>>{};
  final _aliases = <String, String>{};
  final _historicalIds = <String, List<String>>{};
  final _locations = <String, List<JsonMap>>{};
  final _episodeKeys = <String, List<String>>{};
  final _localTargets = <String, String>{};
  final _evidence = <String, JsonMap>{};
  JsonMap _local = {'records': <JsonMap>[]};
  Future<void>? _sync, _building;
  String? _builtStamp;
  String? _composedStamp;
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
    for (final row in await db.query('ui_cache', where: "id LIKE 'mesh:%'")) {
      final id = row['id'] as String;
      final value = jsonDecode(row['payload'] as String);
      if (id == 'mesh:added') _added.addAll((value as Map).cast<String, int>());
      if (id == 'mesh:progress')
        _progress.addAll((value as Map).cast<String, JsonMap>());
      if (id == 'mesh:aliases') {
        for (final e in (value as Map).entries)
          _historicalIds[e.key as String] = (e.value as List).cast<String>();
      }
      if (id.startsWith('mesh:peer:'))
        _peers[id.substring(10)] = value as JsonMap;
    }
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
    final encoded = jsonEncode(payload), fingerprint = _hash(payload);
    final old = await db.query('ui_cache',
        columns: ['fingerprint'], where: 'id=?', whereArgs: [id]);
    if (old.isNotEmpty && old.single['fingerprint'] == fingerprint) return;
    await db.insert(
        'ui_cache', {'id': id, 'fingerprint': fingerprint, 'payload': encoded},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> _identities(String id) async => [
        for (final b in await db.rawQuery(
            "SELECT o.* FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id=? AND b.status='accepted' AND b.relation IN ('exact','contains') AND o.provider IN ('dandanplay','tmdb','bangumi')",
            [id]))
          jsonEncode([
            b['provider'],
            b['object_type'] == 'anime' ? 'work' : b['object_type'],
            b['scope'],
            b['external_id']
          ])
      ];
  Future<String> _sample(String path) async {
    final file = File(path), stat = await File(path).stat();
    final stamp = '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    if (_samples[path]?.$1 == stamp) return _samples[path]!.$2;
    final input = await file.open();
    try {
      final head = await input.read(math.min(stat.size, 65536));
      await input.setPosition(math.max(0, stat.size - 65536));
      final tail = await input.read(65536);
      final value = _hash([
        stat.size,
        sha256.convert(head).toString(),
        sha256.convert(tail).toString()
      ]);
      _samples[path] = (stamp, value);
      return value;
    } finally {
      await input.close();
    }
  }

  Future<String?> _asset(String? path) async {
    if (path == null) return null;
    final real = await File(path).resolveSymbolicLinks();
    final stat = await File(real).stat();
    final id = 'asset:${_hash([
          real,
          stat.size,
          stat.modified.microsecondsSinceEpoch
        ])}';
    _assets[id] = real;
    return id;
  }

  Future<String> _stamp() async => _hash([
        own,
        await db.rawQuery('SELECT total_changes() AS total'),
        await db.rawQuery('PRAGMA data_version'),
        ui.sources.history?.call()
      ]);
  Future<void> _build() => _building ??= (() async {
        if (_builtStamp != await _stamp()) {
          await _buildLocal();
          _builtStamp = await _stamp();
        }
      })()
          .whenComplete(() => _building = null);
  Future<void> _buildLocal() async {
    final records = <JsonMap>[];
    final files = await ui.localFiles();
    for (final row in await db.query('media_entities',
        where: "kind='work'", orderBy: 'rowid')) {
      final id = row['id'] as String;
      final work = workJson((await ui.localWork(id))!);
      work.remove('next');
      final art = work['artwork'] as JsonMap;
      for (final kind in ['poster', 'backdrop', 'logo'])
        art[kind] = await _asset(art[kind] as String?);
      if (!_added.containsKey(id)) {
        final observed = await db.rawQuery(
            'WITH RECURSIVE children(id) AS (SELECT ? UNION ALL SELECT e.id FROM media_entities e JOIN children c ON e.parent_id=c.id) SELECT MIN(created_at) AS added FROM media_bindings WHERE entity_id IN (SELECT id FROM children)',
            [id]);
        _added[id] =
            DateTime.tryParse(observed.single['added'] as String? ?? '')
                    ?.microsecondsSinceEpoch ??
                DateTime.now().microsecondsSinceEpoch;
      }
      final identities = await _identities(id);
      for (final release in await db.query('media_entities',
          where: "kind='release' AND parent_id=?", whereArgs: [id])) {
        identities.addAll((await _identities(release['id'] as String)).where(
            (k) =>
                ['work', 'tv', 'movie'].contains((jsonDecode(k) as List)[1])));
      }
      records.add({
        'kind': 'work',
        'id': id,
        'keys': identities,
        'added': _added[id],
        'value': work,
        'metadata': publicHarnessFacts(await ui.media.store.mergedMetadata(id)),
        'attributes': jsonDecode(row['attributes'] as String)
      });
      final sourceIds = <String>{};
      for (final f in await db.rawQuery("SELECT f.attributes FROM media_entities f JOIN media_file_episodes fe ON fe.file_id=f.id JOIN media_entities e ON e.id=fe.episode_id JOIN media_entities r ON r.id=e.parent_id WHERE r.parent_id=?", [id])) {
        final remote = (jsonDecode(f['attributes'] as String) as Map)['remoteSource'] as Map?;
        sourceIds.add(remote?['sourceId'] as String? ?? 'local');
      }
      records.last['sourceIds'] = sourceIds.toList();
      for (final episode in await ui.localEpisodes(id)) {
        final value = episodeJson(episode);
        value['still'] = await _asset(episode.still);
        final locations = <JsonMap>[];
        final nativeFiles = await db.rawQuery(
            "SELECT l.locator,l.file_id AS fileId,e.start_ms AS startMs,e.end_ms AS endMs FROM media_locations l JOIN media_file_episodes e ON e.file_id=l.file_id WHERE e.episode_id=? AND l.owner_device_id=? AND l.source='local' AND l.available=1",
            [episode.episodeId, ui.media.store.ownerDeviceId]);
        for (final f in nativeFiles) {
          final path = f['locator'] as String;
          if (!await File(path).exists()) continue;
          locations.add({
            'fileId': f['fileId'],
            'sample': await _sample(path),
            'startMs': f['startMs'] ?? 0,
            'endMs': f['endMs']
          });
        }
        if (nativeFiles.isNotEmpty) value['playable'] = locations.isNotEmpty;
        final stamp = files
            .where((f) => f['episodeId'] == episode.episodeId)
            .map((f) => ((f['progress'] as Map?)?['lastWatchedAt'] ??
                (f['progress'] as Map?)?['lastWatchTime']) as String?)
            .whereType<String>()
            .toList()
          ..sort();
        final tracks = <JsonMap>[];
        for (final t in await ui.heat.tracks(episode.episodeId)) {
          final local = t['local_file'] as JsonMap?,
              video = t['video'] as JsonMap;
          tracks.add({
            'bindingId': t['id'],
            'source': video['sourceId'],
            'platform': local?['platform'] ?? video['sourceId'],
            'platformVideoId': local?['platformVideoId'] ?? video['videoId'],
            'count': local?['count'] ??
                (await ui.heat.store.entries(t['cache_key'] as String)).length,
            'enabled': t['enabled'] == 1,
            'origin': local != null
                ? 'sidecar'
                : t['provenance'] != null
                    ? 'import'
                    : 'binding'
          });
        }
        records.add({
          'kind': 'episode',
          'id': episode.episodeId,
          'workId': id,
          'keys': await _identities(episode.episodeId),
          'files': locations,
          'metadata': publicHarnessFacts(
              await ui.media.store.mergedMetadata(episode.episodeId)),
          'danmaku': tracks,
          'subtitles': [
            for (final t
                in await ui.subtitles?.episodeTracks(episode.episodeId) ??
                    <JsonMap>[])
              publicHarnessFacts(t)
          ],
          'subtitleFiles': [
            for (final t
                in await ui.subtitles?.episodeFiles(episode.episodeId) ??
                    <JsonMap>[])
              publicHarnessFacts(t)
          ],
          'watchedAt': stamp.isEmpty
              ? null
              : DateTime.parse(stamp.last).toUtc().toIso8601String(),
          'value': value
        });
      }
    }
    if (_added.isNotEmpty) await _save('mesh:added', _added);
    records.addAll([
      for (final e in _progress.entries)
        {'kind': 'watch', 'id': e.key, 'value': e.value}
    ]);
    _local = {'records': records};
    _local['version'] = _hash(_local);
  }

  Future<void> refresh() =>
      _sync ??= _refresh().whenComplete(() => _sync = null);
  Future<void> _refresh() async {
    final before = _hash([_local, _peers, _online, _progress]);
    _builtStamp = null;
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
          final first =
              await mesh.rpc(id, 'mesh/library/snapshot', {'offset': 0});
          final old = _peers[id];
          if (old?['version'] != first['version']) {
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
    if (before != _hash([_local, _peers, _online, _progress]))
      ui.notifyLibraryChanged();
  }

  Future<void> _mergeProgress(Map<String, JsonMap> values) async {
    var changed = false;
    for (final entry in values.entries) {
      final value = entry.value;
      if (value['at'] is! String ||
          value['writer'] is! String ||
          value['progress'] is! num ||
          (value['progress'] as num) < 0 ||
          (value['progress'] as num) > 1 ||
          DateTime.tryParse(value['at'] as String) == null) {
        throw const FormatException('Invalid watch observation.');
      }
      final old = _progress[entry.key];
      if (old == null || _newer(value, old)) {
        _progress[entry.key] = value;
        changed = true;
      }
    }
    if (changed) await _save('mesh:progress', _progress);
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
    await library();
    if (entries.isEmpty)
      throw const Failure(
          FailureCode.invalidInput, 'Supply at least one episode observation.');
    final prepared = <String, JsonMap>{};
    final at = DateTime.now().toUtc().toIso8601String();
    for (final e in entries) {
      if (e['progress'] is! num ||
          !(e['progress'] as num).isFinite ||
          (e['progress'] as num) < 0 ||
          (e['progress'] as num) > 1) {
        throw const Failure(FailureCode.invalidInput,
            'Progress must be finite and within 0..1.');
      }
      final id = _aliases[e['episodeId']] ?? e['episodeId'] as String;
      final keys = _episodeKeys[id];
      if (keys == null)
        throw const Failure(FailureCode.notFound, 'Unknown merged episode.');
      final value = <String, Object?>{
        'progress': e['progress'],
        'at': at,
        'writer': own,
        'positionMs': e['positionMs'],
        'durationMs': e['durationMs']
      };
      for (final key in keys) {
        if (prepared[key] != null &&
            jsonEncode(prepared[key]) != jsonEncode(value))
          throw const Failure(FailureCode.conflict,
              'Conflicting episode observations in batch.');
        prepared[key] = value;
      }
    }
    final merged = {..._progress, ...prepared};
    await _save('mesh:progress', merged);
    _progress.addAll(prepared);
    await _compose();
    ui.notifyLibraryChanged();
  }

  Future<List<UiWork>> library() async {
    await prepareIndex();
    return _works.values.toList();
  }

  Future<void> prepareIndex() async {
    await _build();
    await _compose();
  }

  String? localEpisodeId(String id) => _localTargets[_aliases[id] ?? id];

  Future<UiWork?> work(String id) async {
    await library();
    return _works[_aliases[id] ?? id];
  }

  Future<String> canonical(String id) async {
    await library();
    return _aliases[id] ?? id;
  }

  String resolvedId(String id) => _aliases[id] ?? id;
  Future<List<UiEpisode>> episodes(String id, {int? season}) async {
    await library();
    return (_episodes[_aliases[id] ?? id] ?? [])
        .where((e) => season == null || e.season == season)
        .toList();
  }

  Future<String?> parent(String id) async {
    await library();
    final target = _aliases[id] ?? id;
    if (_works.containsKey(target)) return target;
    for (final entry in _episodes.entries)
      if (entry.value.any((e) => e.episodeId == target)) return entry.key;
    return null;
  }

  Future<JsonMap> evidence(String id) async {
    await library();
    final result = _evidence[_aliases[id] ?? id];
    if (result == null)
      throw const Failure(FailureCode.notFound, 'Unknown catalogue entity.');
    return result;
  }

  Future<void> _compose() async {
    final composition = _hash([own, _local, _peers, _online, _progress]);
    if (_composedStamp == composition) return;
    final indexRows = <JsonMap>[];
    final records = <JsonMap>[
      for (final r in (_local['records'] as List)
          .cast<JsonMap>()
          .where((r) => r['kind'] != 'watch'))
        {
          ...jsonDecode(jsonEncode(r)) as JsonMap,
          'deviceId': own,
          'name': '',
          'online': true,
          'local': true
        },
      for (final peer in _peers.entries)
        if (mesh.accountId == null || peer.value['account'] == mesh.accountId)
          for (final r in (peer.value['records'] as List).cast<JsonMap>())
            {
              ...jsonDecode(jsonEncode(r)) as JsonMap,
              'deviceId': peer.key,
              'name': peer.value['name'],
              'online': _online[peer.key] == true,
              'local': false
            }
    ];
    for (final r in records.where((r) => r['local'] == true)) {
      final value = r['value'] as JsonMap;
      final paths = r['kind'] == 'work' ? value['artwork'] as JsonMap : value;
      for (final key
          in r['kind'] == 'work' ? ['poster', 'backdrop', 'logo'] : ['still']) {
        if (paths[key] case final String token) paths[key] = _assets[token];
      }
    }
    final works = records.where((r) => r['kind'] == 'work').toList();
    final roots = List.generate(works.length, (i) => i);
    int root(int i) {
      while (roots[i] != i) {
        roots[i] = roots[roots[i]];
        i = roots[i];
      }
      return i;
    }

    final owners = <String, int>{};
    final workIndex = <String, int>{};
    for (var i = 0; i < works.length; i++) {
      final w = works[i],
          ref = _ref(w['deviceId'] as String, w['id'] as String);
      workIndex[ref] = i;
      final keys = (w['keys'] as List).cast<String>().toList();
      for (final e in records.where((e) =>
          e['kind'] == 'episode' &&
          e['deviceId'] == w['deviceId'] &&
          e['workId'] == w['id'])) {
        keys.addAll(
            (e['files'] as List).cast<Map>().map((f) => 'file:${f['sample']}'));
      }
      for (final key in keys) {
        final old = owners[key];
        if (old != null)
          roots[root(i)] = root(old);
        else
          owners[key] = i;
      }
    }
    final groups = <int, List<JsonMap>>{};
    for (var i = 0; i < works.length; i++)
      (groups[root(i)] ??= []).add(works[i]);
    _works.clear();
    _episodes.clear();
    _aliases.clear();
    _locations.clear();
    _episodeKeys.clear();
    _localTargets.clear();
    _evidence.clear();
    final sorted = groups.entries.toList()
      ..sort((a, b) => b.value
          .map((w) => w['added'] as int)
          .reduce(math.max)
          .compareTo(a.value.map((w) => w['added'] as int).reduce(math.max)));
    for (final group in sorted) {
      final members = group.value
        ..sort((a, b) =>
            (a['local'] == true ? 0 : 1).compareTo(b['local'] == true ? 0 : 1));
      final keys = members
          .expand((w) => (w['keys'] as List).cast<String>())
          .toSet()
          .toList()
        ..sort();
      final id = keys.isEmpty
          ? (members.first['local'] == true
              ? members.first['id'] as String
              : _ref(members.first['deviceId'] as String,
                  members.first['id'] as String))
          : 'mesh-work:${_hash(keys.first)}';
      _historicalIds[id] = members
          .map((w) => _ref(w['deviceId'] as String, w['id'] as String))
          .toList();
      for (final w in members) {
        _aliases[_ref(w['deviceId'] as String, w['id'] as String)] = id;
        if (w['local'] == true) _aliases[w['id'] as String] = id;
      }
      final sourceEpisodes = records
          .where((e) =>
              e['kind'] == 'episode' &&
              root(workIndex[
                      _ref(e['deviceId'] as String, e['workId'] as String)]!) ==
                  group.key)
          .toList();
      final episodeRoots = List.generate(sourceEpisodes.length, (i) => i);
      int episodeRoot(int i) {
        while (episodeRoots[i] != i) {
          episodeRoots[i] = episodeRoots[episodeRoots[i]];
          i = episodeRoots[i];
        }
        return i;
      }

      final contentOwners = <String, int>{};
      final episodeTokens = <List<String>>[];
      for (var i = 0; i < sourceEpisodes.length; i++) {
        final e = sourceEpisodes[i];
        final v = e['value'] as JsonMap;
        final identity = (e['keys'] as List).cast<String>().toList()..sort();
        final numbered = v['number'] as int > 0
            ? '${v['season'] ?? 1}:${v['number']}'
            : null;
        final tokens = [
          if (numbered != null) 'number:$numbered',
          ...identity.map((k) => 'identity:$k'),
          for (final f in (e['files'] as List).cast<Map>())
            'file:${f['sample']}:${f['startMs']}:${f['endMs']}'
        ];
        episodeTokens.add(tokens);
        for (final token in tokens) {
          final old = contentOwners[token];
          if (old != null)
            episodeRoots[episodeRoot(i)] = episodeRoot(old);
          else
            contentOwners[token] = i;
        }
      }
      final groupedEpisodes = <int, List<JsonMap>>{};
      final groupedTokens = <int, Set<String>>{};
      for (var i = 0; i < sourceEpisodes.length; i++) {
        (groupedEpisodes[episodeRoot(i)] ??= []).add(sourceEpisodes[i]);
        (groupedTokens[episodeRoot(i)] ??= {}).addAll(episodeTokens[i]);
      }
      final episodeGroups = <String, List<JsonMap>>{};
      for (final g in groupedEpisodes.entries) {
        final tokens = groupedTokens[g.key]!.toList()..sort();
        final key = tokens.firstOrNull ??
            _ref(g.value.first['deviceId'] as String,
                g.value.first['id'] as String);
        episodeGroups[key] = g.value;
      }
      final episodes = <UiEpisode>[];
      for (final entry in episodeGroups.entries) {
        final es = entry.value
          ..sort((a, b) => (a['local'] == true
                  ? 0
                  : a['online'] == true
                      ? 1
                      : 2)
              .compareTo(b['local'] == true
                  ? 0
                  : b['online'] == true
                      ? 1
                      : 2));
        final selected = es.firstWhere(
            (e) =>
                (e['value'] as Map)['playable'] == true && e['online'] == true,
            orElse: () => es.first);
        final eid = 'mesh-episode:${_hash([id, entry.key])}';
        _historicalIds[eid] = es
            .map((e) => _ref(e['deviceId'] as String, e['id'] as String))
            .toList();
        _evidence[eid] = selected;
        if (selected['local'] == true)
          _localTargets[eid] = selected['id'] as String;
        final watchKeys = <String>{'episode:$eid'};
        final locations = <JsonMap>[];
        JsonMap? watched;
        for (final e in es) {
          _aliases[_ref(e['deviceId'] as String, e['id'] as String)] = eid;
          if (e['local'] == true) _aliases[e['id'] as String] = eid;
          watchKeys.add(_ref(e['deviceId'] as String, e['id'] as String));
          for (final f in (e['files'] as List).cast<JsonMap>()) {
            watchKeys.add('file:${f['sample']}:${f['startMs']}:${f['endMs']}');
            if (!locations.any((l) =>
                l['sample'] == f['sample'] &&
                l['startMs'] == f['startMs'] &&
                l['endMs'] == f['endMs']))
              locations.add({
                ...f,
                'deviceId': e['deviceId'],
                'sourceEpisodeId': e['id'],
                'local': e['local'],
                'online': e['online']
              });
          }
          final value = e['value'] as Map;
          if (value['progress'] != null && e['watchedAt'] != null) {
            final observation = <String, Object?>{
              'progress': value['progress'],
              'at': e['watchedAt'],
              'writer': e['deviceId']
            };
            if (watched == null || _newer(observation, watched))
              watched = observation;
          }
        }
        for (final key in watchKeys) {
          final observation = _progress[key];
          if (observation != null &&
              (watched == null || _newer(observation, watched)))
            watched = observation;
        }
        final value = <String, Object?>{
          ...selected['value'] as JsonMap,
          'episodeId': eid,
          'workId': id,
          if (watched != null) 'progress': watched['progress']
        };
        _episodeKeys[eid] = watchKeys.toList();
        _locations[eid] = locations;
        episodes.add(episodeValue(value,
            device: selected['local'] == true
                ? null
                : UiDevice(
                    name: selected['name'] as String,
                    online: selected['online'] as bool)));
      }
      episodes.sort((a, b) => (a.season ?? 1).compareTo(b.season ?? 1) != 0
          ? (a.season ?? 1).compareTo(b.season ?? 1)
          : a.number.compareTo(b.number));
      final value = <String, Object?>{
        ...members.first['value'] as JsonMap,
        'workId': id
      };
      _evidence[id] = members.first;
      for (final w in members.skip(1)) {
        final other = w['value'] as JsonMap;
        if (value['title'] == '未命名作品') value['title'] = other['title'];
        for (final field in ['originalTitle', 'year', 'studio', 'overview'])
          value[field] ??= other[field];
        final art = value['artwork'] as JsonMap,
            otherArt = other['artwork'] as JsonMap;
        for (final field in ['poster', 'backdrop', 'logo', 'tint'])
          art[field] ??= otherArt[field];
        for (final field in ['genres', 'ratings', 'danmaku'])
          if ((value[field] as List).isEmpty) value[field] = other[field];
      }
      _episodes[id] = episodes;
      value['episodeCount'] = math.max(
          episodes.length,
          members
              .map((w) => ((w['value'] as Map)['episodeCount'] as int?) ?? 0)
              .reduce(math.max));
      final devices = <String, UiDevice>{};
      for (final w in members)
        if (w['local'] != true)
          devices[w['deviceId'] as String] =
              UiDevice(name: w['name'] as String, online: w['online'] as bool);
      _works[id] = workValue(value, episodes, devices.values.toList());
      final types = <String>{};
      for (final member in members) {
        final attrs = member['attributes'] as Map;
        final fields = (member['metadata'] as Map)['fields'] as Map;
        final type = fields['type'] ?? attrs['type'] ?? attrs['workType'];
        if (const {'anime', 'series', 'movie'}.contains(type)) types.add(type as String);
        for (final key in (member['keys'] as List).cast<String>()) {
          final identity = jsonDecode(key) as List;
          if (identity[1] == 'movie') types.add('movie');
          if (identity[1] == 'tv') types.add('series');
          if (identity[0] == 'dandanplay' || identity[0] == 'bangumi') types.add('anime');
        }
      }
      indexRows.add({'id': id,
        'added': members.map((w) => w['added'] as int).reduce(math.max),
        'payload': workJson(_works[id]!),
        'facts': {
          'sourceIds': members.expand((w) => (w['sourceIds'] as List? ?? []).cast<String>()).toSet().toList(),
          'deviceIds': members.map((w) => w['deviceId']).toSet().toList(),
          'types': types.toList(), 'identified': keys.isNotEmpty,
          'watch': episodes.any((e) => (e.progress ?? 0) > 0 && (e.progress ?? 0) < 1) ? 'watching' :
              episodes.isNotEmpty && episodes.every((e) => (e.progress ?? 0) >= 1) ? 'watched' : 'unwatched',
          'year': value['year'], 'genres': value['genres'],
          'rating': (value['ratings'] as List).isEmpty ? null : ((value['ratings'] as List).first as Map)['value'],
          'ratingSource': (value['ratings'] as List).isEmpty ? null : ((value['ratings'] as List).first as Map)['source']
        }});
    }
    for (final e in _historicalIds.entries) {
      final ref = e.value.where(_aliases.containsKey).firstOrNull;
      if (ref != null &&
          !_works.containsKey(e.key) &&
          !_locations.containsKey(e.key)) _aliases[e.key] = _aliases[ref]!;
    }
    if (_historicalIds.isNotEmpty) await _save('mesh:aliases', _historicalIds);
    await replaceLibraryIndex(db, indexRows);
    _composedStamp = composition;
  }

  Future<JsonMap> request(String method, JsonMap input, String peer) async {
    if (method.startsWith('mesh/library/files/'))
      return files.request(method.split('/').last, input, peer);
    switch (method) {
      case 'mesh/library/snapshot':
        await _build();
        if (input['version'] != null && input['version'] != _local['version'])
          throw const Failure(
              FailureCode.conflict, 'Catalogue version changed.');
        final records = (_local['records'] as List).cast<JsonMap>();
        final offset = input['offset'];
        if (offset is! int || offset < 0 || offset > records.length)
          throw const FormatException('Invalid catalogue offset.');
        final page = <JsonMap>[];
        var size = 0, next = offset;
        while (next < records.length && size < 262144) {
          final record = records[next];
          size += utf8.encode(jsonEncode(record)).length;
          if (size > 524288)
            throw const FormatException('Catalogue record too large.');
          page.add(record);
          next++;
        }
        return {
          'version': _local['version'],
          'records': page,
          'next': next == records.length ? null : next
        };
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
      final path = _assets[id];
      if (path == null) {
        await _build();
      }
      final found = _assets[id];
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
    await library();
    final target = _aliases[id] ?? id;
    final candidates = _locations[target];
    if ((candidates == null || candidates.isEmpty) &&
        _localTargets[target] != null) {
      final rows = await db.rawQuery(
          'SELECT l.locator,l.file_id AS fileId,f.attributes FROM media_locations l JOIN media_file_episodes e ON e.file_id=l.file_id JOIN media_entities f ON f.id=l.file_id WHERE e.episode_id=? AND l.owner_device_id=? AND l.available=1 ORDER BY l.id',
          [_localTargets[target], ui.media.store.ownerDeviceId]);
      if (rows.isNotEmpty)
        return {'episodeId': target, 'path': rows.first['locator'], 'fileId': rows.first['fileId'],
          'sourceInfo': (jsonDecode(rows.first['attributes'] as String) as Map)['remoteSource']};
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
    await library();
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
    await files.close();
    mesh.libraryRequest = null;
  }
}
