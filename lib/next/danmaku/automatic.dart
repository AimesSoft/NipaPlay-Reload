import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'service.dart';
import 'source.dart';

/// One on-demand preparation path for local playback and the Mesh file owner.
/// Matching uses the existing hash-only provider, never a guessed title result.
final class AutomaticDanmaku {
  AutomaticDanmaku(this.service,
      {required this.matchHash, this.readSettings = settings});
  final DanmakuService service;
  final Future<List<DanmakuVideo>> Function(String path) matchHash;
  final Future<DanmakuAutoLoadSettings> Function() readSettings;
  final _pending = <String, Future<bool>>{};

  static Future<DanmakuAutoLoadSettings> settings() async {
    final prefs = await SharedPreferences.getInstance();
    return resolveDanmakuAutoLoadSettings(
        persistedStrategy:
            prefs.getString(SettingsKeys.danmakuAutoLoadStrategy),
        persistedSkipMatching: prefs.getBool(SettingsKeys.skipDanmakuMatching),
        legacyAutoMatchOnPlay:
            prefs.getBool(SettingsKeys.autoMatchDanmakuOnPlay));
  }

  Future<bool> prepare(String path, {String? fileId, String? episodeId}) {
    // A Mesh receiver must ask the owner, never hash the loopback grant URL.
    if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();
    if (path.contains('://') && fileId == null) return Future.value(false);
    final key = '$path\u0000$fileId\u0000$episodeId';
    final pending = _pending.putIfAbsent(
        key,
        () => _safePrepare(path, fileId: fileId, episodeId: episodeId)
                .whenComplete(() {
              _pending.remove(key);
            }));
    // Acquisition may finish and persist in the background after this bound.
    return pending.timeout(const Duration(seconds: 12), onTimeout: () => false);
  }

  Future<bool> _safePrepare(String path,
      {String? fileId, String? episodeId, bool allowHash = true}) async {
    try {
      final policy = await readSettings();
      if (policy.strategy == DanmakuAutoLoadStrategy.local) {
        return false;
      }
      final store = service.store;
      fileId ??= await store.identities.ensureFile(path);
      final entities = <String>{fileId};
      if (episodeId != null) {
        entities.add(episodeId);
      } else {
        final links = await store.db.query('media_file_episodes',
            where: 'file_id=?', whereArgs: [fileId]);
        // Do not attach a whole-file hash to an invented collection timeline.
        if (links.length == 1) {
          entities.add(links.single['episode_id'] as String);
        }
      }
      Future<List<JsonMap>> bindings() async {
        final result = <JsonMap>[];
        for (final id in entities) {
          final entity = await store.identities.entity(id);
          result.addAll((await store.bindings(id))
              .where((b) => b['entity_revision'] == entity['revision']));
        }
        return result;
      }

      var existing = await bindings();
      final accepted =
          existing.where((b) => b['status'] == 'accepted').toList();
      final remote = accepted
          .where((b) => (b['video'] as JsonMap)['sourceId'] == 'dandanplay')
          .toList();
      if (remote.isNotEmpty) {
        var available = false;
        for (final b in remote) {
          if (b['cache_key'] != null &&
              (await store.coverage(b['cache_key'] as String)).isNotEmpty) {
            available = true;
          } else if (b['enabled'] == 1) {
            // Old evicted bindings retain the exact source; no rematch needed.
            available = await _fetch(b) || available;
          }
        }
        return available;
      }
      // Preserve manual sources and explicit detach decisions.
      if (existing.any((b) => b['local_file'] == null)) return false;
      // A confirmed metadata episode is already a stable Dandanplay video
      // identity. Reuse it before considering hash matching (including when
      // the user disabled matching). Never derive episodes from a work ID.
      final known = <String, ({String entityId, JsonMap binding})>{};
      for (final id in entities) {
        final identity = await store.identities.identity(id);
        for (final b in (identity['bindings'] as List).cast<JsonMap>()) {
          if (b['status'] == 'accepted' &&
              b['provider'] == 'dandanplay' &&
              b['object_type'] == 'episode' &&
              b['relation'] == 'exact') {
            known[b['external_id'] as String] = (entityId: id, binding: b);
          }
        }
      }
      if (known.length > 1) return false;
      if (known.length == 1) {
        final exact = known.values.single;
        final identity = await store.identities.identity(exact.entityId);
        if (!(identity['bindings'] as List).cast<JsonMap>().any((b) =>
            b['id'] == exact.binding['id'] && b['status'] == 'accepted')) {
          return false;
        }
        if ((await bindings()).any((b) => b['local_file'] == null)) {
          return false;
        }
        final fields = (identity['metadata'] as JsonMap)['fields'] as JsonMap;
        final video = DanmakuVideo(
          sourceId: 'dandanplay',
          videoId: exact.binding['external_id'] as String,
          objectType: 'episode',
          title: fields['title'] as String? ?? '',
          durationMs: (fields['runtimeMs'] as num?)?.toInt() ?? 0,
        );
        final bindingId = await store.attach(
            exact.entityId,
            video,
            'Confirmed Dandanplay metadata episode identity',
            null,
            Invocation(origin: 'application:playback'));
        return _fetch(await store.binding(bindingId));
      }
      if (!allowHash || policy.skipMatching || path.contains('://'))
        return false;
      final candidates = await matchHash(path);
      final distinct = <String, DanmakuVideo>{
        for (final v in candidates)
          if (v.sourceId == 'dandanplay' && v.objectType == 'episode')
            v.videoId: v
      };
      if (distinct.length != 1) return false;
      // A manual change made while the network request ran wins.
      existing = await bindings();
      if (existing.any((b) => b['local_file'] == null)) return false;
      // Metadata identity may have been confirmed while hashing, without any
      // danmaku binding being written yet. Re-enter the exact-identity path;
      // never accept the obsolete hash candidate or launch another hash.
      for (final entityId in entities) {
        final identity = await store.identities.identity(entityId);
        if ((identity['bindings'] as List).cast<JsonMap>().any((b) =>
            b['status'] == 'accepted' &&
            b['provider'] == 'dandanplay' &&
            b['object_type'] == 'episode' &&
            b['relation'] == 'exact')) {
          return _safePrepare(path,
              fileId: fileId, episodeId: episodeId, allowHash: false);
        }
      }
      final video = distinct.values.single;
      final id = await store.attach(
          fileId,
          video,
          'Automatic Dandanplay file hash match',
          null,
          Invocation(origin: 'application:playback'));
      return await _fetch(await store.binding(id));
    } catch (error) {
      debugPrint('[NextDanmaku] automatic acquisition: ${error.runtimeType}');
      return false;
    }
  }

  Future<bool> _fetch(JsonMap binding) async {
    final video = DanmakuVideo.fromJson(binding['video'] as JsonMap);
    var job = await service.fetch(video,
        bindingId: binding['id'] as String,
        requestId: Invocation(origin: 'application:playback').id);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!job.state.isTerminal) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return false;
      job = await service.engine
          .wait(job.jobId, afterRevision: job.revision, timeout: remaining);
    }
    return job.state == JobState.succeeded;
  }
}
