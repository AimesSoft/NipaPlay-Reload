import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../danmaku/store.dart';

final class EpisodeHeat {
  const EpisodeHeat(this.store);
  final DanmakuStore store;

  Future<List<double>?> load(String id, int? runtimeMs) async {
    final links = await store.db.rawQuery(
        'SELECT fe.*,(SELECT COUNT(*) FROM media_file_episodes x WHERE x.file_id=fe.file_id) AS episode_count '
        'FROM media_file_episodes fe WHERE fe.episode_id=? ORDER BY fe.file_id',
        [id]);
    final tracks = <JsonMap>[];
    for (final target in [id, for (final l in links) l['file_id'] as String]) {
      final entity = await store.identities.entity(target);
      for (final binding in await store.bindings(target)) {
        if (binding['status'] != 'accepted' ||
            binding['entity_revision'] != entity['revision'] ||
            binding['cache_key'] == null) {
          continue;
        }
        final link = links.where((l) => l['file_id'] == target).firstOrNull;
        // Multi-episode files need a known episode range.
        if (link != null &&
            link['episode_count'] != 1 &&
            (link['start_ms'] == null || link['end_ms'] == null)) {
          continue;
        }
        tracks.add({
          ...binding,
          'start': link?['start_ms'] ?? 0,
          'end': link?['end_ms']
        });
      }
    }
    final chunks = <JsonMap>[];
    for (final key in tracks.map((b) => b['cache_key']).toSet()) {
      chunks.addAll(await store.db.query('danmaku_cache_chunks',
          where: 'cache_key=?', whereArgs: [key], orderBy: 'chunk_index'));
    }
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode([runtimeMs, tracks, chunks])))
        .toString();
    final cacheId = 'heat:$id';
    final saved = await store.db.query('ui_cache',
        where: 'id=? AND fingerprint=?', whereArgs: [cacheId, fingerprint]);
    if (saved.isNotEmpty) {
      final payload = jsonDecode(saved.single['payload'] as String);
      return payload == null
          ? null
          : [for (final v in payload as List) (v as num).toDouble()];
    }
    final times = <int>[];
    final seenTracks = <String>{};
    for (final track in tracks) {
      final start = track['start'] as int, end = track['end'] as int?;
      if (!seenTracks.add(
          jsonEncode([track['cache_key'], start, end, track['offset_ms']]))) {
        continue;
      }
      for (final entry in await store.entries(track['cache_key'] as String)) {
        final fileTime = entry.sourceTimeMs + (track['offset_ms'] as int);
        if (fileTime < start || end != null && fileTime >= end) continue;
        final time = fileTime - start;
        if (runtimeMs == null || time < runtimeMs) times.add(time);
      }
    }
    List<double>? result;
    if (times.isNotEmpty) {
      final duration = runtimeMs ?? times.reduce(math.max) + 1;
      final buckets = List<int>.filled(60, 0);
      for (final t in times) {
        buckets[math.min(59, t * 60 ~/ math.max(1, duration))]++;
      }
      final peak = buckets.reduce(math.max);
      result = [for (final n in buckets) n / peak];
    }
    await store.db.insert(
        'ui_cache',
        {
          'id': cacheId,
          'fingerprint': fingerprint,
          'payload': jsonEncode(result)
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    return result;
  }
}
