import 'dart:async';
import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import '../media/identity_store.dart';
import 'source.dart';
import 'store.dart';
import 'export.dart';
import 'alignment.dart';

final class DanmakuPlaybackTarget {
  const DanmakuPlaybackTarget(this.path, this.generation,
      {this.durationMs = 0});
  final String path;
  final int generation;
  final int durationMs;
}

abstract interface class DanmakuTrackRegistry {
  List<JsonMap> get registry;
  bool reuse(DanmakuPlaybackTarget target, JsonMap binding);
  Future<bool> restoreClassic(DanmakuPlaybackTarget target, JsonMap binding);
}

abstract interface class DanmakuPlayerPort {
  DanmakuPlaybackTarget? get target;
  Set<String> get managedTracks;
  JsonMap? loaded(String bindingId);
  bool install(
      DanmakuPlaybackTarget target, JsonMap binding, List<DanmakuEntry> entries,
      {int startMs = 0, int? endMs});
  void remove(String bindingId);
}

abstract interface class DanmakuTrackUpdater {
  bool updateTrack(
      DanmakuPlaybackTarget target, String trackId, JsonMap properties);
}

final class DanmakuService {
  DanmakuService(
      {required this.store,
      required Iterable<DanmakuSource> sources,
      required this.host,
      required this.player})
      : sources = {for (final source in sources) source.describe.id: source};
  final DanmakuStore store;
  final Map<String, DanmakuSource> sources;
  final DanmakuHost host;
  final DanmakuPlayerPort player;
  final Map<String, JsonMap> _localCacheProvenance = {};
  Future<JsonMap> _provenance(JsonMap binding) async {
    final video = binding['video'] as JsonMap;
    if (video['sourceId'] == 'local') {
      if (binding['cache_key'] == null) {
        return {'platform': 'unknown', 'platformVideoId': null};
      }
      final key = '${binding['cache_key']}:${binding['cache_revision']}';
      final cached = _localCacheProvenance[key];
      if (cached != null) return cached;
      return _localCacheProvenance[key] = localDanmakuProvenance(
          await store.entries(binding['cache_key'] as String));
    }
    return {'platform': video['sourceId'], 'platformVideoId': video['videoId']};
  }

  Future<String> _trackIdentity(JsonMap binding) async {
    final provenance = await _provenance(binding);
    if (provenance['platform'] == 'dandanplay') {
      return jsonEncode(['dandanplay', null]);
    }
    if (provenance['platform'] != 'unknown' &&
        provenance['platformVideoId'] != null) {
      return jsonEncode([
        provenance['platform'],
        provenance['platform'] == 'dandanplay'
            ? null
            : provenance['platformVideoId']
      ]);
    }
    final video = binding['video'] as JsonMap;
    return jsonEncode([video['sourceId'], video['videoId']]);
  }

  List<JsonMap> get registry => player is DanmakuTrackRegistry
      ? (player as DanmakuTrackRegistry).registry
      : const [];
  Future<String> resolveEntity(JsonMap input) async {
    final id = input['entityId'] as String?;
    final path = input['path'] as String?;
    if (path != null && id != null ||
        input['current'] == true && (path != null || id != null)) {
      throw const Failure(
          FailureCode.invalidInput, 'Choose entityId, path or current.');
    }
    if (id != null && id != 'current') return id;
    final locator = path ?? player.target?.path;
    if (locator == null) {
      throw const Failure(FailureCode.notFound, 'No current video.');
    }
    return store.identities.ensureFile(locator);
  }

  Future<bool> _isCurrentEntity(String id) async {
    final path = player.target?.path;
    if (path == null) return false;
    final rows = await store.db.rawQuery(
        'SELECT l.id FROM media_locations l LEFT JOIN media_file_episodes e ON e.file_id=l.file_id WHERE l.owner_device_id=? AND l.locator=? AND (l.file_id=? OR e.episode_id=?)',
        [store.identities.ownerDeviceId, path, id, id]);
    return rows.isNotEmpty;
  }

  late TaskEngine engine;
  DanmakuExporter? exporter;
  Future<void> _submissions = Future.value();
  DanmakuSource source(String id) {
    final found = sources[id];
    if (found == null) {
      throw const Failure(
          FailureCode.notFound, 'Danmaku source is not registered.');
    }
    return found;
  }

  Future<Job> fetch(DanmakuVideo video,
      {String? bindingId,
      DanmakuAccess? access,
      int startMs = 0,
      int? endMs,
      int? localDurationMs,
      bool refresh = false,
      required String requestId}) async {
    final src = source(video.sourceId);
    final end = endMs ?? video.durationMs;
    src.planFetch(video, startMs, end);
    if (src.describe.access == 'requiredSession' && access == null) {
      throw const Failure(
          FailureCode.unavailable,
          'authenticationRequired: 在 NipaPlay「设置 → 实验室 → 平台登录」中登录（仅 macOS），'
          '或由 ui.open_platform_login 打开；用 sessions.status 返回的 accessRef 作为 credentialRef。');
    }
    final key = stableMediaId('danmaku-fetch', [
      requestId,
      video.toJson(),
      bindingId,
      access?.credentialRef,
      startMs,
      end,
      if (localDurationMs != null || refresh)
        {'localDurationMs': localDurationMs, 'refresh': refresh}
    ]);
    final previous = _submissions;
    final done = Completer<void>();
    _submissions = done.future;
    await previous;
    try {
      final existing = await engine.store.get(key);
      if (existing != null) return existing;
      if (bindingId != null) {
        final b = await store.binding(bindingId);
        if (jsonEncode(b['video']) != jsonEncode(video.toJson())) {
          throw const Failure(
              FailureCode.conflict, 'Fetch video differs from binding.');
        }
      }
      return await engine.submit(
          type: 'danmaku.fetch',
          title: 'Fetch ${video.sourceId} danmaku',
          jobId: key,
          input: {
            'video': video.toJson(),
            'bindingId': bindingId,
            'credentialRef': access?.credentialRef,
            'startMs': startMs,
            'endMs': end,
            'localDurationMs': localDurationMs,
            'refresh': refresh
          });
    } finally {
      done.complete();
    }
  }

  Future<JsonMap> attach(
      String entityId,
      DanmakuVideo video,
      String reason,
      String? url,
      DanmakuAccess? access,
      String requestId,
      Invocation invocation,
      {bool refresh = false}) async {
    source(video.sourceId);
    final target = player.target;
    if (await _isCurrentEntity(entityId) &&
        target?.path == player.target?.path &&
        target?.generation == player.target?.generation) {
      final existing = registry.where((t) =>
          (t['platform'] == video.sourceId &&
              t['platformVideoId'] == video.videoId) ||
          video.sourceId == 'local' && t['filePath'] == video.videoId);
      if (existing.isNotEmpty && !refresh) {
        final track = existing.first;
        if (video.sourceId != 'dandanplay') {
          return {
            'bindingId': track['bindingId'],
            'jobId': null,
            'status': 'alreadyExists',
            'trackId': track['trackId']
          };
        }
        final id = await store.attach(entityId, video, reason, url, invocation);
        final reused = (player as DanmakuTrackRegistry)
            .reuse(target!, await store.binding(id));
        return {
          'bindingId': id,
          'jobId': null,
          'status': reused ? 'reused' : 'recorded',
          'trackId': track['trackId']
        };
      }
    }
    source(video.sourceId).planFetch(video, 0, video.durationMs);
    if (source(video.sourceId).describe.access == 'requiredSession' &&
        access == null) {
      throw const Failure(
          FailureCode.unavailable,
          'authenticationRequired: 在 NipaPlay「设置 → 实验室 → 平台登录」中登录（仅 macOS），'
          '或由 ui.open_platform_login 打开；用 sessions.status 返回的 accessRef 作为 credentialRef。');
    }
    final id = await store.attach(entityId, video, reason, url, invocation);
    final job = await fetch(video,
        bindingId: id,
        access: access,
        requestId: requestId,
        refresh: refresh,
        localDurationMs:
            await _isCurrentEntity(entityId) && player.target!.durationMs > 0
                ? player.target!.durationMs
                : null);
    return {'bindingId': id, 'jobId': job.jobId};
  }

  Future<Job> align(
      String bindingId, List<JsonMap> anchors, String requestId) async {
    final key = stableMediaId('danmaku-align', [requestId, bindingId, anchors]);
    final existing = await engine.store.get(key);
    if (existing != null) return existing;
    throw const Failure(FailureCode.unavailable,
        'danmaku.align is retired. Use danmaku.analyze_alignment for data and danmaku.update to set offsetMs. Existing requestId tasks remain readable.');
  }

  Future<JsonMap> analyzeAlignment(
      String bindingId, List<JsonMap> anchors) async {
    final analysis = analyzeDanmakuAnchors(anchors);
    final binding = await store.binding(bindingId);
    return {
      'bindingId': bindingId,
      'observedRevision': binding['revision'],
      'currentOffsetMs': binding['offset_ms'],
      ...analysis
    };
  }

  Future<JsonMap> update(List<JsonMap> changes, Invocation invocation) async {
    if (changes.isEmpty || changes.length > 100) {
      throw const Failure(FailureCode.invalidInput, 'Supply 1 to 100 changes.');
    }
    final results = <JsonMap>[];
    for (var index = 0; index < changes.length; index++) {
      final change = changes[index];
      try {
        results.add({
          'index': index,
          'status': 'completed',
          'result': await updateProperties(change, invocation)
        });
      } on Failure catch (failure) {
        results.add(
            {'index': index, 'status': 'failed', 'error': failure.toJson()});
      }
    }
    return {'results': results};
  }

  Future<JsonMap> updateProperties(
      JsonMap change, Invocation invocation) async {
    final properties = {
      for (final key in ['enabled', 'offsetMs', 'displayFold'])
        if (change.containsKey(key)) key: change[key]
    };
    if (properties.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Supply an update property.');
    }
    String? bindingId = change['bindingId'] as String?;
    final trackId = change['trackId'] as String?;
    final target = player.target;
    if (trackId != null) {
      final track = registry.where((t) => t['trackId'] == trackId).firstOrNull;
      if (track == null || target == null) {
        throw const Failure(
            FailureCode.notFound, 'Current player track not found.');
      }
      bindingId = track['bindingId'] as String?;
      if (bindingId == null) {
        if (change.containsKey('expectedRevision')) {
          throw const Failure(FailureCode.invalidInput,
              'Unbound player tracks have no persistent binding revision.');
        }
        if (player is! DanmakuTrackUpdater) {
          throw const Failure(FailureCode.unavailable,
              'Host does not support updating unbound player tracks.');
        }
        if (!(player as DanmakuTrackUpdater)
            .updateTrack(target, trackId, properties)) {
          throw const Failure(
              FailureCode.conflict, 'Player target or track changed.');
        }
        final updated = registry.singleWhere((t) => t['trackId'] == trackId);
        return {
          'trackId': trackId,
          'enabled': updated['enabled'],
          'offsetMs': updated['offsetMs'],
          'displayFold': updated['deduplicate'],
          'persistence': 'playback'
        };
      }
    }
    final revision = change['expectedRevision'] as int?;
    if (revision == null) {
      throw const Failure(FailureCode.invalidInput,
          'expectedRevision is required for a persistent binding.');
    }
    final updated = await store.change(
        bindingId!,
        revision,
        {
          if (properties.containsKey('enabled'))
            'enabled': properties['enabled'] == true ? 1 : 0,
          if (properties.containsKey('displayFold'))
            'deduplicate': properties['displayFold'] == true ? 1 : 0,
          if (properties.containsKey('offsetMs'))
            'offset_ms': properties['offsetMs']
        },
        invocation,
        reason: change['reason'] as String?,
        alignment: properties.containsKey('offsetMs')
            ? {
                'method': 'manualOffset',
                'confirmed': true,
                'offsetMs': properties['offsetMs'],
                'confirmedBy': invocation.origin == 'gui' ? 'user' : 'agent'
              }
            : null);
    await refreshCurrent();
    return {
      'bindingId': bindingId,
      if (trackId != null) 'trackId': trackId,
      'revision': updated['revision'],
      'enabled': updated['enabled'] == 1,
      'offsetMs': updated['offset_ms'],
      'displayFold': updated['deduplicate'] == 1,
      'persistence': 'binding'
    };
  }

  Future<Job> chooseAlignment(
          String jobId, int revision, bool apply, Invocation invocation) =>
      engine.resolveDecision(jobId,
          revision: revision,
          call: ActionCall(apply ? 'danmaku.align_apply' : 'danmaku.align_keep',
              {'jobId': jobId, 'revision': revision}),
          checkpoint: {
            'choice': apply ? 'apply' : 'keep',
            'invocationId': invocation.id,
            'boundBy': invocation.origin == 'gui' ? 'user' : 'agent'
          });

  Future<void> deleteCache(String key) async {
    final previous = _submissions;
    final done = Completer<void>();
    _submissions = done.future;
    await previous;
    try {
      for (final job in await engine.list(type: 'danmaku.fetch')) {
        if (job.state.isTerminal) continue;
        final video = DanmakuVideo.fromJson(
            Map<String, Object?>.from(job.input['video'] as Map));
        final ref = job.input['credentialRef'] as String?;
        final jobKey = store.cacheKey(video, source(video.sourceId),
            ref == null ? null : DanmakuAccess(ref),
            refreshJobId: job.input['refresh'] == true ? job.jobId : null);
        if (jobKey == key) {
          throw const Failure(FailureCode.conflict,
              'Stop active fetch tasks before deleting their cache.');
        }
      }
      await store.deleteCache(key);
      await refreshCurrent();
    } finally {
      done.complete();
    }
  }

  /// Rebuild from committed cache, never start network work on a player callback.
  Future<void> refreshCurrent({String? replaceBindingId}) async {
    final target = player.target;
    if (target == null) return;
    await store.identities.ensureFile(target.path);
    final locations = await store.db.query('media_locations',
        where: 'locator = ? AND owner_device_id = ? AND available = ?',
        whereArgs: [target.path, store.identities.ownerDeviceId, 1]);
    final mounts = <String, ({JsonMap binding, int start, int? end})>{};
    for (final location in locations) {
      final fileId = location['file_id'] as String;
      final file = await store.identities.entity(fileId);
      for (final b in await store.bindings(fileId)) {
        if (b['status'] == 'accepted' &&
            b['entity_revision'] == file['revision'] &&
            (b['cache_key'] != null ||
                (b['video'] as JsonMap)['sourceId'] == 'dandanplay')) {
          mounts[b['id'] as String] = (binding: b, start: 0, end: null);
        }
      }
      final links = await store.db.query('media_file_episodes',
          where: 'file_id = ?', whereArgs: [fileId]);
      for (final link in links) {
        // A collection cannot be assigned an invented episode timeline.
        if (links.length > 1 &&
            (link['start_ms'] == null || link['end_ms'] == null)) {
          continue;
        }
        for (final b in await store.bindings(link['episode_id'] as String)) {
          final entity =
              await store.identities.entity(link['episode_id'] as String);
          if (b['status'] == 'accepted' &&
              b['entity_revision'] == entity['revision'] &&
              (b['cache_key'] != null ||
                  (b['video'] as JsonMap)['sourceId'] == 'dandanplay')) {
            mounts[b['id'] as String] = (
              binding: b,
              start: link['start_ms'] as int? ?? 0,
              end: link['end_ms'] as int?
            );
          }
        }
      }
    }
    if (player.target?.path != target.path ||
        player.target?.generation != target.generation) {
      return;
    }
    final loadedIds = registry.map((track) => track['bindingId']).toSet();
    final ordered = mounts.keys.toList();
    final positions = {for (var i = 0; i < ordered.length; i++) ordered[i]: i};
    int priority(String id) => id == replaceBindingId
        ? 0
        : loadedIds.contains(id)
            ? 1
            : (mounts[id]!.binding['video'] as JsonMap)['sourceId'] == 'local'
                ? 2
                : 3;
    ordered.sort((a, b) {
      final order = priority(a).compareTo(priority(b));
      return order == 0 ? positions[a]!.compareTo(positions[b]!) : order;
    });
    final seenVideos = <String>{};
    for (final id in ordered) {
      if (!seenVideos.add(await _trackIdentity(mounts[id]!.binding))) {
        mounts.remove(id);
      }
    }
    if (player.target?.path != target.path ||
        player.target?.generation != target.generation) {
      return;
    }
    for (final id in player.managedTracks.difference(mounts.keys.toSet())) {
      player.remove(id);
    }
    for (final mount in mounts.values) {
      final b = mount.binding, id = b['id'] as String;
      final loaded = player.loaded(id);
      if (loaded?['revision'] == b['revision'] &&
          loaded?['cacheRevision'] == b['cache_revision'] &&
          loaded?['cacheKey'] == b['cache_key'] &&
          loaded?['startMs'] == mount.start &&
          loaded?['endMs'] == mount.end) {
        continue;
      }
      final video = b['video'] as JsonMap;
      final existing = registry
          .where((t) =>
              t['platform'] == video['sourceId'] &&
              t['platformVideoId'] == video['videoId'])
          .firstOrNull;
      if (id != replaceBindingId &&
          existing != null &&
          existing['origin'] != 'binding' &&
          (existing['source'] == 'local' || b['cache_key'] == null) &&
          mount.start == 0) {
        (player as DanmakuTrackRegistry).reuse(target, b);
        continue;
      }
      if (b['cache_key'] == null) {
        if (player is DanmakuTrackRegistry) {
          if (!(player as DanmakuTrackRegistry).reuse(target, b)) {
            await (player as DanmakuTrackRegistry).restoreClassic(target, b);
          }
        }
        continue;
      }
      final entries = await store.entries(b['cache_key'] as String);
      final current = await store.binding(id, active: false);
      final entity =
          await store.identities.entity(current['entity_id'] as String);
      if (current['status'] != 'accepted' ||
          current['entity_revision'] != entity['revision']) {
        player.remove(id);
        continue;
      }
      if (current['revision'] != b['revision'] ||
          current['cache_key'] != b['cache_key']) {
        continue;
      }
      player.install(target, b, entries,
          startMs: mount.start, endMs: mount.end);
    }
  }

  Future<JsonMap> tracks(String entityId) async {
    final entity = await store.identities.entity(entityId);
    final rows = await store.bindings(entityId);
    final currentTracks =
        await _isCurrentEntity(entityId) ? registry : <JsonMap>[];
    final candidates = <JsonMap>[
      for (final track in currentTracks)
        if (!rows.any((b) => b['id'] == track['bindingId']))
          {...track, 'entityId': track['entityId'] ?? entityId, 'loaded': true},
      for (final b in rows)
        {
          'origin': (b['video'] as JsonMap)['sourceId'] == 'local'
              ? 'manual_import'
              : 'binding',
          'source': (b['video'] as JsonMap)['sourceId'],
          if ((b['video'] as JsonMap)['sourceId'] == 'local')
            'filePath': (b['video'] as JsonMap)['videoId'],
          ...await _provenance(b),
          ...?currentTracks.where((t) => t['bindingId'] == b['id']).firstOrNull,
          'bindingId': b['id'],
          'entityId': b['entity_id'],
          'revision': b['revision'],
          'status': b['status'],
          'stale': b['entity_revision'] != entity['revision'],
          'video': b['video'],
          'enabled': b['enabled'] == 1,
          'deduplicate': b['deduplicate'] == 1,
          'offsetMs': b['offset_ms'],
          'alignment': b['alignment'],
          'evidence': b['evidence'],
          'boundBy': b['bound_by'],
          'cacheKey': b['cache_key'],
          'loaded': player.loaded(b['id'] as String) != null,
          'coverage': b['cache_key'] == null
              ? <JsonMap>[]
              : await store.coverage(b['cache_key'] as String)
        }
    ];
    final groups = <String, JsonMap>{};
    final bindingIds = <String, Set<String>>{};
    int priority(JsonMap track) => track['loaded'] == true
        ? 0
        : track['status'] == 'accepted' && track['stale'] == false
            ? 1
            : 2;
    for (final track in candidates) {
      final key = track['platform'] == 'dandanplay'
          ? 'dandanplay'
          : track['platform'] != 'unknown' && track['platformVideoId'] != null
              ? jsonEncode([track['platform'], track['platformVideoId']])
              : '${track['trackId'] ?? track['bindingId']}';
      final ids = bindingIds[key] ??= {};
      if (track['bindingId'] case final String id) ids.add(id);
      final previous = groups[key];
      if (previous == null || priority(track) < priority(previous)) {
        groups[key] = track;
      }
    }
    return {
      'tracks': [
        for (final group in groups.entries)
          {
            ...group.value,
            'displayFold': group.value['deduplicate'] != false,
            'bindingIds': bindingIds[group.key]!.toList()
          }
      ]
    };
  }
}
