import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../ui_data/service.dart';
import '../ui_data/ui_data.dart';
import '../ui_data/library_index.dart';
import '../ui_data/library_search.dart';
import '../ui_data/work_more.dart';
import '../media/library_reads.dart';
import '../media/metadata_provider.dart';
import '../harness_redaction.dart';
import 'library_codec.dart';
import 'library_transfer.dart';

String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
bool _newer(JsonMap a, JsonMap b) {
  final compared = DateTime.parse(a['at'] as String)
      .compareTo(DateTime.parse(b['at'] as String));
  return compared > 0 ||
      (compared == 0 &&
          (a['writer'] as String).compareTo(b['writer'] as String) > 0);
}

// Evidence from another device may carry identities/credits absent locally.
// Keep each provider object, rather than letting the selected file owner hide it.
JsonMap _combinedEvidence(JsonMap primary, List<JsonMap> members) {
  final sources = <String, Map>{};
  final ratings = <String, Map>{};
  for (final member in members) {
    final metadata = member['metadata'] as Map;
    for (final row
        in (metadata['sources'] as List? ?? const []).whereType<Map>()) {
      final key = jsonEncode([
        row['provider'],
        row['objectType'],
        row['externalId'],
        row['scope'],
        row['language']
      ]);
      final old = sources[key];
      if (old == null) {
        sources[key] = row;
      } else {
        final newer =
            '${row['fetchedAt']}'.compareTo('${old['fetchedAt']}') > 0;
        final latest = newer ? row : old, earlier = newer ? old : row;
        sources[key] = {
          ...latest,
          'fields': {
            ...?earlier['fields'] as Map?,
            ...?latest['fields'] as Map?
          },
          'fieldProvenance': {
            for (final field in (earlier['fields'] as Map? ?? {}).keys)
              field: (earlier['fieldProvenance'] as Map?)?[field] ??
                  {
                    'snapshotId': earlier['snapshotId'],
                    'fetchedAt': earlier['fetchedAt']
                  },
            for (final field in (latest['fields'] as Map? ?? {}).keys)
              field: (latest['fieldProvenance'] as Map?)?[field] ??
                  {
                    'snapshotId': latest['snapshotId'],
                    'fetchedAt': latest['fetchedAt']
                  },
          },
        };
      }
    }
    for (final row
        in (metadata['ratings'] as List? ?? const []).whereType<Map>()) {
      ratings.putIfAbsent(
          jsonEncode([row['source'], row['ref'], row['language']]), () => row);
    }
  }
  return {
    ...primary,
    'keys': members
        .expand((m) => (m['keys'] as List).cast<String>())
        .toSet()
        .toList(),
    'metadata': <String, Object?>{
      ...(primary['metadata'] as Map).cast<String, Object?>(),
      'sources': sources.values.toList(),
      'ratings': ratings.values.toList()
    },
  };
}

String _ref(String device, String id) =>
    'mesh-ref:${base64Url.encode(utf8.encode(jsonEncode([
              device,
              id
            ]))).replaceAll('=', '')}';

/// Owned exclusively by the library isolate. No timers or GUI/native handles.
final class LibraryProjection {
  LibraryProjection(this.ui, this.own);
  final UiDataService ui;
  final String own;
  Database get db => ui.db;
  String? accountId;
  Map<String, JsonMap> _peers = {}, _progress = {};
  Map<String, bool> _online = {};
  Map<String, String> _assets = {};
  final _samples = <String, (String, String)>{};
  final _added = <String, int>{};
  Map<String, List<String>> _historicalIds = {};
  JsonMap _local = {'records': <JsonMap>[]};
  final _wireSnapshots = LibraryPublications();
  Map<String, UiWork> _works = {};
  Map<String, List<UiEpisode>> _episodes = {};
  Map<String, String> _aliases = {}, _localTargets = {};
  Map<String, List<JsonMap>> _locations = {}, _management = {};
  Map<String, List<String>> _episodeKeys = {};
  Map<String, JsonMap> _evidence = {};
  LibrarySearchIndex searchIndex = LibrarySearchIndex();
  List<UiWork> _orderedWorks = [];
  Map<String, int> _workOffsets = {};
  Future<void> initialize() async {
    for (final row in await db.query('ui_cache',
        where: "id IN ('mesh:added','mesh:aliases','mesh:progress')")) {
      final value = jsonDecode(row['payload'] as String) as Map;
      switch (row['id']) {
        case 'mesh:added':
          _added.addAll(value.cast<String, int>());
        case 'mesh:aliases':
          _historicalIds = value
              .map((k, v) => MapEntry(k as String, (v as List).cast<String>()));
        case 'mesh:progress':
          _progress = value.cast<String, JsonMap>();
      }
    }
  }

  Future<void> build(String stamp) => _buildLocal(stamp);
  String? get builtStamp => _local['version'] as String?;
  Map<String, JsonMap> get peers => _peers;
  Map<String, bool> get online => _online;

  /// Resolves both the current aliases and canonical IDs retired by an earlier
  /// composition. A merge can otherwise leave one old public ID looking like a
  /// peer reference even though this device remembers which members it joined.
  String canonical(String id) {
    final visited = <String>{id};
    var current = id;
    while (true) {
      final next = _aliases[current];
      if (next != null && next != current && visited.add(next)) {
        current = next;
        continue;
      }
      String? retired;
      for (final ref in _historicalIds[current] ?? const <String>[]) {
        final target = _aliases[ref];
        if (target != null && target != current && !visited.contains(target)) {
          retired = target;
          break;
        }
      }
      if (retired == null) return current;
      visited.add(retired);
      current = retired;
    }
  }

  Future<bool> mergeProgress(Map<String, JsonMap> observations) async {
    var changed = false;
    for (final entry in observations.entries) {
      final value = entry.value;
      if (value['at'] is! String ||
          value['writer'] is! String ||
          value['progress'] is! num ||
          !(value['progress'] as num).isFinite ||
          (value['progress'] as num) < 0 ||
          (value['progress'] as num) > 1 ||
          DateTime.tryParse(value['at'] as String) == null) {
        throw const FormatException('Invalid watch observation.');
      }
      final old = _progress[entry.key];
      if (old == null || _newer(value, old)) changed = true;
    }
    if (changed) {
      final merged = {..._progress};
      for (final entry in observations.entries) {
        final old = merged[entry.key];
        if (old == null || _newer(entry.value, old)) {
          merged[entry.key] = entry.value;
        }
      }
      await _save('mesh:progress', merged);
      _progress = merged;
    }
    return changed;
  }

  JsonMap page(JsonMap input, int revision) {
    final separateProgress = input['progressSeparately'] == true;
    final version =
        "${_local['version']}:${separateProgress ? 'content' : revision}";
    final peer = input['_peerId'] as String? ?? 'local';
    final progress = <String, Object?>{
      if (separateProgress && input['offset'] == 0) ...{
        'progress': _progress,
        'progressRevision': revision,
        'progressSeparately': true,
      },
    };
    // Progress can advance while another device downloads a large catalogue.
    // Finish that immutable publication rather than making every page chase
    // the playing device's latest progress revision.
    if (input['encoding'] == librarySnapshotEncoding &&
        input['version'] is String) {
      final offset = input['offset'];
      if (offset is! int)
        throw const FormatException('Invalid catalogue byte offset.');
      final page =
          _wireSnapshots.read(input['version'] as String, offset, peer);
      if (page != null) return {...page, ...progress};
    }
    if (input['known'] == version) {
      return {
        'version': version,
        'records': <JsonMap>[],
        'next': null,
        'unchanged': true,
        ...progress,
      };
    }
    if (input['version'] != null && input['version'] != version) {
      throw const Failure(FailureCode.conflict, 'Catalogue version changed.');
    }
    final records = [
      ...(_local['records'] as List).cast<JsonMap>(),
      if (!separateProgress)
        for (final entry in _progress.entries)
          {'kind': 'watch', 'id': entry.key, 'value': entry.value}
    ];
    if (input['encoding'] == librarySnapshotEncoding) {
      final offset = input['offset'];
      if (offset is! int)
        throw const FormatException('Invalid catalogue byte offset.');
      return {
        ..._wireSnapshots.publish(version, records, offset, peer),
        ...progress
      };
    }
    final offset = input['offset'];
    if (offset is! int || offset < 0 || offset > records.length) {
      throw const FormatException('Invalid catalogue offset.');
    }
    final page = <JsonMap>[];
    var size = 0, next = offset;
    while (next < records.length && size < 262144) {
      final record = records[next];
      size += utf8.encode(jsonEncode(record)).length;
      if (size > 524288) {
        throw const FormatException('Catalogue record too large.');
      }
      page.add(record);
      next++;
    }
    return {
      'version': version,
      'records': page,
      'next': next == records.length ? null : next
    };
  }

  int compositions = 0;
  Future<LibraryProgress> progress(List<JsonMap> entries) async {
    if (entries.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Supply at least one episode observation.');
    }
    final at = DateTime.now().toUtc().toIso8601String();
    final prepared = <String, JsonMap>{}, changed = <String, double>{};
    for (final entry in entries) {
      final fraction = entry['progress'];
      if (fraction is! num ||
          !fraction.isFinite ||
          fraction < 0 ||
          fraction > 1) {
        throw const Failure(FailureCode.invalidInput,
            'Progress must be finite and within 0..1.');
      }
      final asked = entry['episodeId'] as String;
      final id = _aliases[asked] ?? asked;
      final keys = _episodeKeys[id];
      if (keys == null) {
        throw const Failure(FailureCode.notFound, 'Unknown merged episode.');
      }
      final value = <String, Object?>{
        'progress': fraction,
        'at': at,
        'writer': own,
        'positionMs': entry['positionMs'],
        'durationMs': entry['durationMs']
      };
      for (final key in keys) {
        if (prepared[key] != null &&
            jsonEncode(prepared[key]) != jsonEncode(value)) {
          throw const Failure(FailureCode.conflict,
              'Conflicting episode observations in batch.');
        }
        prepared[key] = value;
      }
      changed[id] = fraction.toDouble();
    }
    // Persist before changing the published projection. A failed batch leaves
    // every observation and displayed progress unchanged.
    await _save('mesh:progress', {..._progress, ...prepared});
    _progress.addAll(prepared);
    final workIds = <String>{};
    for (final id in changed.keys) {
      workIds.add(_episodeParents[id]!);
    }
    final works = <String, UiWork>{}, episodes = <String, List<UiEpisode>>{};
    for (final workId in workIds) {
      final previous = _works[workId]!;
      final updated = episodes[workId] = [
        for (final episode in _episodes[workId]!)
          if (changed.containsKey(episode.episodeId))
            episodeValue({
              ...episodeJson(episode),
              'progress': changed[episode.episodeId],
              'positionMs': prepared[_episodeKeys[episode.episodeId]!.first]
                  ?['positionMs'],
              'lastPlayedAt': at,
            }, device: episode.device)
          else
            episode
      ];
      final value = workJson(previous);
      final work = works[workId] = workValue(value, updated, previous.devices);
      _works[workId] = work;
      _orderedWorks[_workOffsets[workId]!] = work;
      _episodes[workId] = updated;
      final rows = await db
          .query('next_library_index', where: 'id=?', whereArgs: [workId]);
      if (rows.isNotEmpty) {
        final facts = jsonDecode(rows.single['facts'] as String) as JsonMap;
        facts['watch'] = updated
                .any((e) => (e.progress ?? 0) > 0 && (e.progress ?? 0) < 1)
            ? 'watching'
            : updated.isNotEmpty && updated.every((e) => (e.progress ?? 0) >= 1)
                ? 'watched'
                : 'unwatched';
        for (final item in (facts['searchEpisodes'] as List).cast<JsonMap>()) {
          final episode = item['episode'] as JsonMap;
          if (changed.containsKey(episode['episodeId'])) {
            episode['progress'] = changed[episode['episodeId']];
          }
        }
        await db.update('next_library_index',
            {'payload': jsonEncode(workJson(work)), 'facts': jsonEncode(facts)},
            where: 'id=?', whereArgs: [workId]);
      }
      searchIndex.updateProgress(
          workJson(work), updated.map(episodeJson).toList());
    }
    return LibraryProgress(works, episodes,
        {for (final work in works.values) _workOffsets[work.workId]!: work});
  }

  final _episodeParents = <String, String>{};
  Future<LibrarySnapshot> compose(Map<String, JsonMap> peers,
      Map<String, bool> online, String? account) async {
    _peers = peers;
    _online = online;
    accountId = account;
    await _composeNow();
    return snapshot;
  }

  Future<void> _save(String id, Object payload) async {
    final encoded = jsonEncode(payload);
    final fingerprint = _hash(payload);
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

  Future<void> _buildLocal(String stamp) async {
    final records = <JsonMap>[];
    final entityAliases = <String, List<String>>{};
    for (final row in await db.query('media_entity_aliases')) {
      (entityAliases[row['entity_id'] as String] ??= [])
          .add(row['old_id'] as String);
    }
    final reads = LibraryReads(ui.media.store);
    final files = await ui.localFiles();
    for (final row in await db.query('media_entities',
        where: "kind='work'", orderBy: 'rowid')) {
      final id = row['id'] as String;
      if ((jsonDecode(row['attributes'] as String) as Map)['removed'] == true)
        continue;
      // A work made from identities alone, left with none and with no file,
      // is nothing the viewer has. It stays stored (progress, provenance)
      // and shows again when it is bound again.
      if ((jsonDecode(row['attributes'] as String) as Map)['localOnly'] !=
              true &&
          (await db.rawQuery(
                      'WITH RECURSIVE t(id) AS (SELECT ? UNION ALL SELECT e.id FROM media_entities e JOIN t ON e.parent_id=t.id) '
                      "SELECT EXISTS(SELECT 1 FROM media_bindings WHERE entity_id IN (SELECT id FROM t) AND status='accepted') "
                      'OR EXISTS(SELECT 1 FROM media_file_episodes WHERE episode_id IN (SELECT id FROM t)) AS kept',
                      [id]))
                  .single['kept'] ==
              0) {
        continue;
      }
      final episodes = await ui.localEpisodes(id, files: files, reads: reads);
      final work = workJson((await ui.localWork(id,
          files: files, episodes: episodes, reads: reads))!);
      work.remove('next');
      final art = work['artwork'] as JsonMap;
      for (final kind in ['poster', 'backdrop', 'logo']) {
        art[kind] = await _asset(art[kind] as String?);
      }
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
        'aliases': entityAliases[id] ?? <String>[],
        'keys': identities,
        'added': _added[id],
        'value': work,
        'metadata': publicHarnessFacts(await reads.metadata(id)),
        'attributes': jsonDecode(row['attributes'] as String)
      });
      records.last['searchTitles'] = [
        for (final snapshot in await db.rawQuery(
            "SELECT s.fields FROM media_snapshots s JOIN media_bindings b ON b.object_id=s.object_id JOIN media_entities e ON e.id=b.entity_id WHERE b.status='accepted' AND b.relation IN ('exact','contains') AND (e.id=? OR (e.kind='release' AND e.parent_id=?))",
            [
              id,
              id
            ]))
          ...librarySearchTitles((jsonDecode(snapshot['fields'] as String)
                  as Map)['metadata'] as Map? ??
              jsonDecode(snapshot['fields'] as String) as Map)
      ];
      final sourceIds = <String>{};
      for (final f in await db.rawQuery(
          "SELECT f.attributes FROM media_entities f JOIN media_file_episodes fe ON fe.file_id=f.id JOIN media_entities e ON e.id=fe.episode_id JOIN media_entities r ON r.id=e.parent_id WHERE r.parent_id=?",
          [id])) {
        final remote = (jsonDecode(f['attributes'] as String)
            as Map)['remoteSource'] as Map?;
        sourceIds.add(remote?['sourceId'] as String? ?? 'local');
      }
      records.last['sourceIds'] = sourceIds.toList();
      for (final episode in episodes) {
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
        final tracks = <JsonMap>[];
        for (final t in await ui.heat.tracks(episode.episodeId, reads: reads)) {
          final local = t['local_file'] as JsonMap?,
              video = t['video'] as JsonMap;
          tracks.add({
            'bindingId': t['id'],
            'source': video['sourceId'],
            'platform': local?['platform'] ?? video['sourceId'],
            'platformVideoId': local?['platformVideoId'] ?? video['videoId'],
            'count': local?['count'] ??
                await ui.heat.store.entryCount(t['cache_key'] as String),
            'enabled': t['enabled'] == 1,
            'origin': local != null
                ? 'sidecar'
                : t['provenance'] != null
                    ? 'import'
                    : 'binding'
          });
        }
        final subtitles =
            await ui.subtitles?.episodeSubtitles(episode.episodeId);
        records.add({
          'kind': 'episode',
          'id': episode.episodeId,
          'aliases': entityAliases[episode.episodeId] ?? <String>[],
          'workId': id,
          'keys': await _identities(episode.episodeId),
          'files': locations,
          'metadata':
              publicHarnessFacts(await reads.metadata(episode.episodeId)),
          'danmaku': tracks,
          'subtitles': [
            for (final t in subtitles?.tracks ?? <JsonMap>[])
              publicHarnessFacts(t)
          ],
          'subtitleFiles': [
            for (final t in subtitles?.files ?? <JsonMap>[])
              publicHarnessFacts(t)
          ],
          'watchedAt': episode.lastPlayedAt?.toUtc().toIso8601String(),
          'value': value
        });
      }
    }
    if (_added.isNotEmpty) await _save('mesh:added', _added);
    final local = <String, Object?>{'records': records};
    local['version'] = stamp;
    _local = local;
  }

  Future<void> _composeNow() async {
    compositions++;
    final indexRows = <JsonMap>[];
    // Records are not copied deeply: what is changed below is copied where
    // it is changed.
    final records = <JsonMap>[];
    for (final r in (_local['records'] as List).cast<JsonMap>()) {
      if (r['kind'] == 'watch') continue;
      final value = {...r['value'] as JsonMap};
      final isWork = r['kind'] == 'work';
      final paths = isWork ? {...value['artwork'] as JsonMap} : value;
      if (isWork) value['artwork'] = paths;
      for (final key in isWork ? ['poster', 'backdrop', 'logo'] : ['still']) {
        if (paths[key] case final String token) paths[key] = _assets[token];
      }
      records.add({
        ...r,
        'value': value,
        'deviceId': own,
        'name': '',
        'online': true,
        'local': true
      });
    }
    for (final peer in _peers.entries) {
      if (accountId != null && peer.value['account'] != accountId) {
        continue;
      }
      for (final r in (peer.value['records'] as List).cast<JsonMap>()) {
        records.add({
          ...r,
          'deviceId': peer.key,
          'name': peer.value['name'],
          'online': _online[peer.key] == true,
          'local': false
        });
      }
    }
    final works = <JsonMap>[], episodesOf = <String, List<JsonMap>>{};
    String ownerOf(Object? device, Object? work) => '$device\u0000$work';
    for (final r in records) {
      if (r['kind'] == 'work') {
        works.add(r);
      } else if (r['kind'] == 'episode') {
        (episodesOf[ownerOf(r['deviceId'], r['workId'])] ??= []).add(r);
      }
    }
    final roots = List.generate(works.length, (i) => i);
    int root(int i) {
      while (roots[i] != i) {
        roots[i] = roots[roots[i]];
        i = roots[i];
      }
      return i;
    }

    final owners = <String, List<int>>{};
    final workMembers = {
      for (var i = 0; i < works.length; i++) i: <int>[i]
    };
    final workIndex = <String, int>{};
    for (var i = 0; i < works.length; i++) {
      final w = works[i],
          ref = _ref(w['deviceId'] as String, w['id'] as String);
      workIndex[ref] = i;
      final keys = (w['keys'] as List).cast<String>().toList();
      for (final e
          in episodesOf[ownerOf(w['deviceId'], w['id'])] ?? <JsonMap>[]) {
        keys.addAll((e['files'] as List)
            .cast<Map>()
            .where((f) =>
                f['sample'] is String && (f['sample'] as String).isNotEmpty)
            .map(_fileToken));
      }
      for (final key in keys) {
        final candidates = owners.putIfAbsent(key, () => []);
        for (final old in candidates) {
          final a = root(i), b = root(old);
          if (a == b) continue;
          if (workMembers[a]!.every((x) => workMembers[b]!
              .every((y) => _compatibleIdentities(works[x], works[y])))) {
            roots[a] = b;
            workMembers[b]!.addAll(workMembers.remove(a)!);
          }
        }
        candidates.add(i);
      }
    }
    final groups = <int, List<JsonMap>>{};
    for (var i = 0; i < works.length; i++) {
      (groups[root(i)] ??= []).add(works[i]);
    }
    // Every episode under the group its work is in, in the order of records.
    final episodesIn = <int, List<JsonMap>>{};
    for (final w in works) {
      final group =
          root(workIndex[_ref(w['deviceId'] as String, w['id'] as String)]!);
      (episodesIn[group] ??= [])
          .addAll(episodesOf[ownerOf(w['deviceId'], w['id'])] ?? const []);
    }
    final newWorks = <String, UiWork>{};
    final newManagement = <String, List<JsonMap>>{};
    final newEpisodes = <String, List<UiEpisode>>{};
    final newAliases = <String, String>{};
    final newLocations = <String, List<JsonMap>>{};
    final newEpisodeKeys = <String, List<String>>{};
    final newLocalTargets = <String, String>{};
    final newEvidence = <String, JsonMap>{};
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
        newAliases[_ref(w['deviceId'] as String, w['id'] as String)] = id;
        if (w['local'] == true) newAliases[w['id'] as String] = id;
        for (final old in (w['aliases'] as List? ?? []).cast<String>()) {
          newAliases[_ref(w['deviceId'] as String, old)] = id;
          if (w['local'] == true) newAliases[old] = id;
        }
      }
      final sourceEpisodes = episodesIn[group.key] ?? <JsonMap>[];
      final episodeRoots = List.generate(sourceEpisodes.length, (i) => i);
      int episodeRoot(int i) {
        while (episodeRoots[i] != i) {
          episodeRoots[i] = episodeRoots[episodeRoots[i]];
          i = episodeRoots[i];
        }
        return i;
      }

      final contentOwners = <String, List<int>>{};
      final episodeMembers = {
        for (var i = 0; i < sourceEpisodes.length; i++) i: <int>[i]
      };
      final episodeTokens = <List<String>>[];
      for (var i = 0; i < sourceEpisodes.length; i++) {
        final e = sourceEpisodes[i];
        final v = e['value'] as JsonMap;
        final identity = (e['keys'] as List).cast<String>().toList()..sort();
        final numbered = switch (v['number']) {
          final int n when n > 0 => '${v['season'] ?? 1}:$n',
          _ => null,
        };
        final tokens = [
          if (numbered != null) 'number:$numbered',
          ...identity.map((k) => 'identity:$k'),
          for (final f in (e['files'] as List).cast<Map>())
            if (f['sample'] is String && (f['sample'] as String).isNotEmpty)
              _fileToken(f)
        ];
        episodeTokens.add(tokens);
        for (final token in tokens) {
          final candidates = contentOwners.putIfAbsent(token, () => []);
          for (final old in candidates) {
            final a = episodeRoot(i), b = episodeRoot(old);
            if (a == b) continue;
            if (episodeMembers[a]!.every((x) => episodeMembers[b]!.every((y) =>
                _compatibleIdentities(sourceEpisodes[x], sourceEpisodes[y],
                    episode: true) &&
                _compatibleRanges(sourceEpisodes[x], sourceEpisodes[y])))) {
              episodeRoots[a] = b;
              episodeMembers[b]!.addAll(episodeMembers.remove(a)!);
            }
          }
          candidates.add(i);
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
      final searchTitles = <String, Set<String>>{};
      final mergedIds = <String, String>{};
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
        newEvidence[eid] = _combinedEvidence(selected, es);
        if (selected['local'] == true) {
          newLocalTargets[eid] = selected['id'] as String;
        }
        final watchKeys = <String>{'episode:$eid'};
        final locations = <JsonMap>[];
        JsonMap? watched;
        final titles = searchTitles[eid] = {};
        for (final e in es) {
          final ref = _ref(e['deviceId'] as String, e['id'] as String);
          newAliases[ref] = eid;
          mergedIds[ref] = eid;
          if (e['local'] == true) newAliases[e['id'] as String] = eid;
          watchKeys.add(ref);
          for (final old in (e['aliases'] as List? ?? []).cast<String>()) {
            final previous = _ref(e['deviceId'] as String, old);
            newAliases[previous] = eid;
            watchKeys.add(previous);
            if (e['local'] == true) newAliases[old] = eid;
          }
          titles.addAll(librarySearchTitles(e['value'] as Map));
          for (final f in (e['files'] as List).cast<JsonMap>()) {
            watchKeys
                .add('file:$id:${f['sample']}:${f['startMs']}:${f['endMs']}');
            if (!locations.any((l) =>
                l['sample'] == f['sample'] &&
                l['startMs'] == f['startMs'] &&
                l['endMs'] == f['endMs'])) {
              locations.add({
                ...f,
                'deviceId': e['deviceId'],
                'sourceEpisodeId': e['id'],
                'local': e['local'],
                'online': e['online']
              });
            }
          }
          final value = e['value'] as Map;
          if (value['progress'] != null &&
              e['watchedAt'] != null &&
              ((value['progress'] as num) > 0 ||
                  value['lastPlayedAt'] != null ||
                  ((value['positionMs'] as num?) ?? 0) > 0)) {
            final observation = <String, Object?>{
              'progress': value['progress'],
              'at': e['watchedAt'],
              'writer': e['deviceId'],
              'positionMs': value['positionMs'],
            };
            if (watched == null || _newer(observation, watched)) {
              watched = observation;
            }
          }
        }
        for (final key in watchKeys) {
          final observation = _progress[key];
          if (observation != null &&
              (watched == null || _newer(observation, watched))) {
            watched = observation;
          }
        }
        final value = <String, Object?>{
          ...selected['value'] as JsonMap,
          'episodeId': eid,
          'workId': id,
          if (watched != null) ...{
            'progress': watched['progress'],
            'positionMs': watched['positionMs'],
            'lastPlayedAt': watched['at'],
          }
        };
        newEpisodeKeys[eid] = watchKeys.toList();
        newLocations[eid] = locations;
        episodes.add(episodeValue(value,
            device: selected['local'] == true
                ? null
                : UiDevice(
                    name: selected['name'] as String,
                    online: selected['online'] as bool)));
      }
      sortEpisodes(episodes, seasonless: 1);
      final value = <String, Object?>{
        ...members.first['value'] as JsonMap,
        'workId': id
      };
      newEvidence[id] = _combinedEvidence(members.first, members);
      final sourceEpisodesOf = <String, List<JsonMap>>{};
      for (final e in sourceEpisodes) {
        (sourceEpisodesOf[ownerOf(e['deviceId'], e['workId'])] ??= []).add(e);
      }
      newManagement[id] = [
        for (final member in members)
          {
            'deviceId': member['deviceId'],
            'workId': member['id'],
            'local': member['local'],
            'online': member['online'],
            'reason': member['online'] == true ? null : 'source_device_offline',
            'episodes': [
              for (final e in sourceEpisodesOf[
                      ownerOf(member['deviceId'], member['id'])] ??
                  <JsonMap>[])
                {
                  'episodeId': e['id'],
                  'mergedEpisodeId': newAliases[
                      _ref(e['deviceId'] as String, e['id'] as String)],
                  'fileIds': (e['files'] as List)
                      .cast<Map>()
                      .map((f) => f['fileId'])
                      .toSet()
                      .toList()
                }
            ],
          }
      ];
      // The first member's artwork is copied: the others fill its gaps.
      value['artwork'] = {...value['artwork'] as JsonMap};
      for (final w in members.skip(1)) {
        final other = w['value'] as JsonMap;
        if (value['title'] == '未命名作品') value['title'] = other['title'];
        for (final field in [
          'originalTitle',
          'year',
          'studio',
          'overview',
          'runtimeMs'
        ]) {
          value[field] ??= other[field];
        }
        final art = value['artwork'] as JsonMap,
            otherArt = other['artwork'] as JsonMap;
        for (final field in ['poster', 'backdrop', 'logo', 'tint']) {
          art[field] ??= otherArt[field];
        }
        for (final field in ['genres', 'ratings', 'danmaku']) {
          if ((value[field] as List).isEmpty) value[field] = other[field];
        }
      }
      // A film when an identity is a TMDB movie and none a TMDB series, as
      // `IdentityStore.workIsFilm` tells it for one device.
      final tmdb = {
        for (final key in keys)
          if (jsonDecode(key) case ['tmdb', final String type, ...]) type
      };
      value['film'] = tmdb.contains('movie') && !tmdb.contains('tv');
      newEpisodes[id] = episodes;
      value['episodeCount'] = math.max(
          episodes.length,
          members
              .map((w) => ((w['value'] as Map)['episodeCount'] as int?) ?? 0)
              .reduce(math.max));
      final devices = <String, UiDevice>{};
      for (final w in members) {
        if (w['local'] != true) {
          devices[w['deviceId'] as String] =
              UiDevice(name: w['name'] as String, online: w['online'] as bool);
        }
      }
      final work =
          newWorks[id] = workValue(value, episodes, devices.values.toList());
      final types = <String>{};
      for (final member in members) {
        final attrs = member['attributes'] as Map;
        final fields = (member['metadata'] as Map)['fields'] as Map;
        final type = fields['type'] ?? attrs['type'] ?? attrs['workType'];
        if (const {'anime', 'series', 'movie'}.contains(type)) {
          types.add(type as String);
        }
        for (final key in (member['keys'] as List).cast<String>()) {
          final identity = jsonDecode(key) as List;
          if (identity[1] == 'movie') types.add('movie');
          if (identity[1] == 'tv') types.add('series');
          if (identity[0] == 'dandanplay' || identity[0] == 'bangumi') {
            types.add('anime');
          }
        }
      }
      indexRows.add({
        'id': id,
        'added': members.map((w) => w['added'] as int).reduce(math.max),
        'payload': workJson(work),
        'facts': {
          'sourceIds': members
              .expand((w) => (w['sourceIds'] as List? ?? []).cast<String>())
              .toSet()
              .toList(),
          'deviceIds': members.map((w) => w['deviceId']).toSet().toList(),
          'types': types.toList(),
          'identified': keys.isNotEmpty,
          'identityKeys': keys,
          'searchTitles': <String>{
            for (final member in members) ...[
              ...librarySearchTitles(member['value'] as Map),
              ...librarySearchTitles(member['attributes'] as Map),
              ...librarySearchTitles(
                  (member['metadata'] as Map)['fields'] as Map),
              ...(member['searchTitles'] as List? ?? []).cast<String>(),
            ]
          }.toList(),
          'searchYears': <int>{
            for (final member in members)
              if ((member['value'] as Map)['year'] case final int year) year
          }.toList(),
          'searchEpisodes': [
            for (final episode in episodes)
              {
                'episode': episodeJson(episode),
                'titles':
                    (searchTitles[episode.episodeId] ?? <String>{}).toList(),
              }
          ],
          'watch': episodes
                  .any((e) => (e.progress ?? 0) > 0 && (e.progress ?? 0) < 1)
              ? 'watching'
              : episodes.isNotEmpty &&
                      episodes.every((e) => (e.progress ?? 0) >= 1)
                  ? 'watched'
                  : 'unwatched',
          'year': value['year'],
          'genres': value['genres'],
          'rating': (value['ratings'] as List).isEmpty
              ? null
              : ((value['ratings'] as List).first as Map)['value'],
          'ratingSource': (value['ratings'] as List).isEmpty
              ? null
              : ((value['ratings'] as List).first as Map)['source']
        }
      });
    }
    for (final e in _historicalIds.entries) {
      final ref = e.value.where(newAliases.containsKey).firstOrNull;
      if (ref != null &&
          !newWorks.containsKey(e.key) &&
          !newLocations.containsKey(e.key)) {
        newAliases[e.key] = newAliases[ref]!;
      }
    }
    // Publish only complete background projections.
    _works = newWorks;
    _orderedWorks = newWorks.values.toList();
    _workOffsets = {
      for (var i = 0; i < _orderedWorks.length; i++) _orderedWorks[i].workId: i
    };
    _management = newManagement;
    _episodes = newEpisodes;
    _aliases = newAliases;
    _locations = newLocations;
    _episodeKeys = newEpisodeKeys;
    _localTargets = newLocalTargets;
    _evidence = newEvidence;
    _episodeParents
      ..clear()
      ..addEntries(newEpisodes.entries.expand((entry) => entry.value
          .map((episode) => MapEntry(episode.episodeId, entry.key))));
    if (_historicalIds.isNotEmpty) await _save('mesh:aliases', _historicalIds);
    await replaceLibraryIndex(db, indexRows);
    await searchIndex.replace(indexRows);
  }

  JsonMap search(String query, int limit, int? episodeLimit) =>
      searchIndex.search(query, limit: limit, episodeLimit: episodeLimit);

  List<String?> searchWorkIds(List<ExternalRef> refs) =>
      refs.map(searchIndex.workId).toList();

  JsonMap managementTargets(List<String> ids) => {
        'entries': [
          for (final id in ids)
            {
              'workId': id,
              'targets': _management[_aliases[id] ?? id] ?? [],
              if (!_management.containsKey(_aliases[id] ?? id))
                'error':
                    const Failure(FailureCode.notFound, 'Unknown merged work.')
                        .toJson()
            }
        ]
      };

  JsonMap evidence(String id) {
    final result = _evidence[_aliases[id] ?? id];
    if (result == null) {
      throw const Failure(FailureCode.notFound, 'Unknown catalogue entity.');
    }
    return result;
  }

  /// What a work's page shows below its episodes ([buildWorkMore]), from
  /// the metadata this catalogue already holds for it.
  JsonMap workMore(String id) {
    final key = _aliases[id] ?? id;
    final metadata = (evidence(key)['metadata'] as Map?) ?? const {};
    return buildWorkMore(metadata, film: _works[key]?.film ?? false);
  }

  /// Works whose sources credit [person] (cast, crew, creators, voices),
  /// in the catalogue's order.
  List<String> worksCrediting(String provider, String person) {
    bool credits(Map fields) {
      bool listed(Object? list, [String key = 'id']) =>
          list is List &&
          list.whereType<Map>().any((p) => '${p[key]}' == person);
      if (provider == 'tmdb') {
        final credits = fields['credits'];
        return credits is Map &&
                (listed(credits['cast']) || listed(credits['crew'])) ||
            listed(fields['creators']);
      }
      return listed(fields['staff']) ||
          (fields['characters'] is List &&
              (fields['characters'] as List)
                  .whereType<Map>()
                  .any((c) => listed(c['actors'])));
    }

    return [
      for (final work in _orderedWorks)
        if ((_evidence[work.workId]?['metadata'] as Map?)?['sources']
            case final List sources)
          if (sources.whereType<Map>().any((s) =>
              s['provider'] == provider &&
              s['fields'] is Map &&
              credits(s['fields'] as Map)))
            work.workId
    ];
  }

  LibrarySnapshot get snapshot => LibrarySnapshot(_assets, _works, _episodes,
      _aliases, _locations, _localTargets, _orderedWorks, _episodeParents);
}

final class LibrarySnapshot {
  const LibrarySnapshot(this.assets, this.works, this.episodes, this.aliases,
      this.locations, this.localTargets, this.orderedWorks, this.episodeParents,
      {this.packedWorks,
      this.builtStamp,
      this.compositionStamp,
      this.builds = 0,
      this.composed = false});
  final Map<String, String> assets, aliases, localTargets;
  final Map<String, UiWork> works;
  final Map<String, List<UiEpisode>> episodes;
  final Map<String, List<JsonMap>> locations;
  final List<UiWork> orderedWorks;
  final Map<String, String> episodeParents;
  final PackedWorks? packedWorks;
  final String? builtStamp, compositionStamp;
  final int builds;
  final bool composed;
}

/// The published catalogue without its materialised object graph. Records are
/// transferred as one binary block and decoded one work at a time when a view
/// asks for that reference. A single [TransferableTypedData] avoids copying
/// hundreds of separate strings through the UI isolate during startup.
final class PackedWorks {
  PackedWorks._(this.length, TransferableTypedData packed) : _packed = packed;

  static const _headerBytes = 16;
  static const _entryBytes = 16;

  factory PackedWorks.pack(List<String> orderedIds, List<String> records) {
    if (orderedIds.length != records.length) {
      throw ArgumentError('Every ordered work needs exactly one record.');
    }
    final ids = [for (final id in orderedIds) utf8.encode(id)];
    final encoded = [for (final record in records) utf8.encode(record)];
    var buckets = 1;
    while (buckets < orderedIds.length * 2) {
      buckets <<= 1;
    }
    final idsLength = ids.fold<int>(0, (total, id) => total + id.length);
    final recordsLength =
        encoded.fold<int>(0, (total, record) => total + record.length);
    final entriesAt = _headerBytes;
    final idsAt = entriesAt + orderedIds.length * _entryBytes;
    final bucketsAt = idsAt + idsLength;
    final recordsAt = bucketsAt + buckets * 4;
    final bytes = Uint8List(recordsAt + recordsLength);
    final header = ByteData.sublistView(bytes);
    header.setUint32(0, orderedIds.length, Endian.little);
    header.setUint32(4, buckets, Endian.little);
    header.setUint32(8, bucketsAt, Endian.little);
    var idOffset = idsAt;
    var recordOffset = recordsAt;
    for (var i = 0; i < encoded.length; i++) {
      final entry = entriesAt + i * _entryBytes;
      header.setUint32(entry, idOffset, Endian.little);
      header.setUint32(entry + 4, ids[i].length, Endian.little);
      header.setUint32(entry + 8, recordOffset, Endian.little);
      header.setUint32(entry + 12, encoded[i].length, Endian.little);
      bytes.setRange(idOffset, idOffset + ids[i].length, ids[i]);
      bytes.setRange(
          recordOffset, recordOffset + encoded[i].length, encoded[i]);
      idOffset += ids[i].length;
      recordOffset += encoded[i].length;
    }
    // The worker builds the lookup table while holding the packed binary. The
    // UI isolate can then resolve a record without decoding every work ID.
    final bucketMask = buckets - 1;
    for (var i = 0; i < orderedIds.length; i++) {
      var bucket = _hash(orderedIds[i]) & bucketMask;
      while (header.getUint32(bucketsAt + bucket * 4, Endian.little) != 0) {
        bucket = (bucket + 1) & bucketMask;
      }
      header.setUint32(bucketsAt + bucket * 4, i + 1, Endian.little);
    }
    return PackedWorks._(
        orderedIds.length, TransferableTypedData.fromList([bytes]));
  }

  final int length;
  final TransferableTypedData _packed;
  Uint8List? _bytes;
  ByteData? _header;

  void _open() {
    if (_bytes != null) return;
    final bytes = _bytes = _packed.materialize().asUint8List();
    final header = _header = ByteData.sublistView(bytes);
    final count = header.getUint32(0, Endian.little);
    if (count != length) {
      throw StateError('Packed work count does not match its order.');
    }
  }

  int? _indexOf(String workId) {
    _open();
    final buckets = _header!.getUint32(4, Endian.little);
    final bucketsAt = _header!.getUint32(8, Endian.little);
    final bucketMask = buckets - 1;
    var bucket = _hash(workId) & bucketMask;
    for (var probe = 0; probe < buckets; probe++) {
      final value = _header!.getUint32(bucketsAt + bucket * 4, Endian.little);
      if (value == 0) return null;
      final index = value - 1;
      final entry = _headerBytes + index * _entryBytes;
      final idStart = _header!.getUint32(entry, Endian.little);
      final idLength = _header!.getUint32(entry + 4, Endian.little);
      final candidate = utf8
          .decode(Uint8List.sublistView(_bytes!, idStart, idStart + idLength));
      if (candidate == workId) return index;
      bucket = (bucket + 1) & bucketMask;
    }
    return null;
  }

  static int _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ (unit & 0xff)) * 0x01000193) & 0xffffffff;
      hash = ((hash ^ (unit >> 8)) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  String? record(String workId) {
    final index = _indexOf(workId);
    return index == null ? null : recordAt(index);
  }

  bool contains(String workId) => _indexOf(workId) != null;

  String idAt(int index) {
    _open();
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this);
    }
    final entry = _headerBytes + index * _entryBytes;
    final idStart = _header!.getUint32(entry, Endian.little);
    final idLength = _header!.getUint32(entry + 4, Endian.little);
    return utf8
        .decode(Uint8List.sublistView(_bytes!, idStart, idStart + idLength));
  }

  String recordAt(int index) {
    _open();
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this);
    }
    final entry = _headerBytes + index * _entryBytes;
    final start = _header!.getUint32(entry + 8, Endian.little);
    final recordLength = _header!.getUint32(entry + 12, Endian.little);
    return utf8
        .decode(Uint8List.sublistView(_bytes!, start, start + recordLength));
  }
}

final class LibraryProgress {
  const LibraryProgress(this.works, this.episodes, this.orderedUpdates);
  final Map<String, UiWork> works;
  final Map<String, List<UiEpisode>> episodes;
  final Map<int, UiWork> orderedUpdates;
}

// A content sample identifies bytes, not an episode or a work. Compilation
// ranges and explicit source identities must agree across the entire union,
// including when an unbound record would otherwise bridge conflicting groups.
String _fileToken(Map file) =>
    'file:${file['sample']}:${file['startMs'] ?? 0}:${file['endMs']}';

bool _compatibleIdentities(JsonMap a, JsonMap b, {bool episode = false}) {
  Map<String, Set<String>> identities(JsonMap record) {
    final result = <String, Set<String>>{};
    for (final key in (record['keys'] as List).cast<String>()) {
      final parts = jsonDecode(key);
      if (parts is! List || parts.length != 4) continue;
      (result[jsonEncode(parts.take(episode ? 2 : 3).toList())] ??= {})
          .add(jsonEncode(parts.skip(episode ? 2 : 3).toList()));
    }
    return result;
  }

  final left = identities(a), right = identities(b);
  return left.entries.every((entry) =>
      !right.containsKey(entry.key) ||
      entry.value.intersection(right[entry.key]!).isNotEmpty);
}

bool _compatibleRanges(JsonMap a, JsonMap b) {
  for (final left in (a['files'] as List).cast<Map>()) {
    if (left['sample'] == null) continue;
    for (final right in (b['files'] as List).cast<Map>()) {
      if (left['sample'] == right['sample'] &&
          _fileToken(left) != _fileToken(right)) {
        return false;
      }
    }
  }
  return true;
}
