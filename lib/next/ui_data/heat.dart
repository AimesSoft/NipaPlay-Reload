import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../danmaku/store.dart';
import '../media/library_reads.dart';
import '../media/file_identity_merge.dart';

final class EpisodeHeat {
  const EpisodeHeat(this.store);
  final DanmakuStore store;

  Future<List<JsonMap>> tracks(String id, {LibraryReads? reads}) =>
      reads == null
          ? _tracks(id)
          : reads.once(('tracks', id), () => _tracks(id));

  /// The danmaku tracks of an episode and of its files, in three queries:
  /// the files it is in, those entities' revisions, their bindings.
  Future<List<JsonMap>> _tracks(String id) async {
    id = await canonicalFileId(store.db, id);
    final links = await store.db.rawQuery(
        'SELECT fe.*,(SELECT COUNT(*) FROM media_file_episodes x WHERE x.file_id=fe.file_id) AS episode_count '
        'FROM media_file_episodes fe WHERE fe.episode_id=? ORDER BY fe.file_id',
        [id]);
    final targets = [id, for (final l in links) l['file_id'] as String];
    // A target named by a merged file's old ID is the file it became.
    final entities = {
      for (final e in await store.db.rawQuery(
          'SELECT t.id AS asked, e.id, e.revision FROM media_entities e '
          'JOIN (SELECT value AS id FROM json_each(?)) t '
          'ON e.id = COALESCE((SELECT file_id FROM media_file_aliases WHERE old_id = t.id), t.id)',
          [jsonEncode(targets)]))
        e['asked'] as String: e
    };
    final ids = {for (final e in entities.values) e['id'] as String}.toList();
    final bindings = <String, List<JsonMap>>{};
    if (ids.isNotEmpty) {
      for (final b in await store.db.rawQuery(
          'SELECT * FROM danmaku_bindings WHERE entity_id IN (${List.filled(ids.length, '?').join(',')}) '
          'ORDER BY entity_id,created_at,id',
          ids)) {
        (bindings[b['entity_id'] as String] ??= []).add(store.decodeBinding(b));
      }
    }
    final tracks = <JsonMap>[];
    for (final target in targets) {
      final entity = entities[target];
      // An entity that is not there was an error before; it still is.
      if (entity == null) {
        await store.identities.entity(target);
        continue;
      }
      for (final binding in bindings[entity['id']] ?? const <JsonMap>[]) {
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
    return tracks;
  }

  Future<List<double>?> load(String id, int? runtimeMs,
      {LibraryReads? reads}) async {
    final tracks = await this.tracks(id, reads: reads);
    if (tracks.isEmpty) return null;
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
      final local = track['local_file'] as JsonMap?;
      final counts = local != null
          ? Map<String, Object?>.from(local['timeCounts'] as Map)
          : <String, Object?>{};
      if (local == null) {
        for (final entry in await store.entries(track['cache_key'] as String)) {
          final t = entry.sourceTimeMs.toString();
          counts[t] = (counts[t] as int? ?? 0) + 1;
        }
      }
      for (final entry in counts.entries) {
        final fileTime = int.parse(entry.key) + (track['offset_ms'] as int);
        if (fileTime < start || end != null && fileTime >= end) continue;
        final time = fileTime - start;
        if (runtimeMs == null || time < runtimeMs) {
          times.addAll(List<int>.filled(entry.value as int, time));
        }
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

  Future<List<String>> comments(List<(String, int?)> episodes,
      {Duration openingWindow = const Duration(minutes: 3),
      int maxEpisodes = 3,
      LibraryReads? reads}) async {
    final result = <String>[], seen = <String>{}, seenTracks = <String>{};
    for (final (id, duration) in episodes.take(maxEpisodes)) {
      final candidates = <({String text, int time})>[];
      for (final track in await tracks(id, reads: reads)) {
        final start = track['start'] as int, end = track['end'] as int?;
        if (!seenTracks.add(
            jsonEncode([track['cache_key'], start, end, track['offset_ms']]))) {
          continue;
        }
        for (final entry in await store.entries(track['cache_key'] as String)) {
          final time = entry.sourceTimeMs + (track['offset_ms'] as int) - start;
          if (time < 0 ||
              time >= openingWindow.inMilliseconds ||
              end != null && time >= end - start ||
              duration != null && time >= duration) {
            continue;
          }
          final text = entry.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (text.runes.length < 2 ||
              text.runes.length > 18 ||
              RegExp(r'(?:https?://|www\.|(?:[a-z0-9-]+\.)+[a-z]{2,24}\b|\b(?:\d{1,3}\.){3}\d{1,3}\b)',
                      caseSensitive: false)
                  .hasMatch(text) ||
              RegExp(r'(.)\1{3,}', unicode: true).hasMatch(text) ||
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
            continue;
          }
          final normalized = text
              .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')
              .toLowerCase();
          if (normalized.runes.length < 2 ||
              RegExp(r'^(.{1,3})\1{2,}$', unicode: true).hasMatch(normalized)) {
            continue;
          }
          candidates.add((text: text, time: time));
        }
      }
      candidates.sort((a, b) => a.time.compareTo(b.time) != 0
          ? a.time.compareTo(b.time)
          : a.text.compareTo(b.text));
      for (final c in candidates) {
        final normalized = c.text
            .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')
            .toLowerCase();
        if (!seen.add(normalized)) continue;
        result.add(c.text);
        if (result.length == 6) return result;
      }
    }
    return result;
  }
}
