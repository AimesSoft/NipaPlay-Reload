import 'dart:async';
import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import '../media/identity_store.dart';
import 'source.dart';
import 'store.dart';
import 'export.dart';

final class DanmakuPlaybackTarget {
  const DanmakuPlaybackTarget(this.path, this.generation);
  final String path;
  final int generation;
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
      required String requestId}) async {
    final src = source(video.sourceId);
    final end = endMs ?? video.durationMs;
    src.planFetch(video, startMs, end);
    if (src.describe.access == 'requiredSession' && access == null) {
      throw const Failure(FailureCode.unavailable,
          'authenticationRequired: this source needs a host session reference.');
    }
    final key = stableMediaId('danmaku-fetch', [
      requestId,
      video.toJson(),
      bindingId,
      access?.credentialRef,
      startMs,
      end
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
            'endMs': end
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
      Invocation invocation) async {
    source(video.sourceId).planFetch(video, 0, video.durationMs);
    if (source(video.sourceId).describe.access == 'requiredSession' &&
        access == null) {
      throw const Failure(FailureCode.unavailable,
          'authenticationRequired: this source needs a host session reference.');
    }
    final id = await store.attach(entityId, video, reason, url, invocation);
    final job =
        await fetch(video, bindingId: id, access: access, requestId: requestId);
    return {'bindingId': id, 'jobId': job.jobId};
  }

  Future<Job> align(
      String bindingId, List<JsonMap> anchors, String requestId) async {
    final previous = _submissions;
    final done = Completer<void>();
    _submissions = done.future;
    await previous;
    try {
      final key =
          stableMediaId('danmaku-align', [requestId, bindingId, anchors]);
      final existing = await engine.store.get(key);
      if (existing != null) return existing;
      final b = await store.binding(bindingId);
      return await engine.submit(
          type: 'danmaku.align',
          jobId: key,
          title: 'Propose danmaku alignment',
          input: {
            'bindingId': bindingId,
            'bindingRevision': b['revision'],
            'anchors': anchors,
            'requestId': requestId
          });
    } finally {
      done.complete();
    }
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
            ref == null ? null : DanmakuAccess(ref));
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
  Future<void> refreshCurrent() async {
    final target = player.target;
    if (target == null) return;
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
            b['cache_key'] != null) {
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
              b['cache_key'] != null) {
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
    return {
      'tracks': [
        for (final b in rows)
          {
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
      ]
    };
  }
}
