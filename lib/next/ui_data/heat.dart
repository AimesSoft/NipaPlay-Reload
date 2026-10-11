import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../danmaku/store.dart';

final class EpisodeHeat {
  const EpisodeHeat(this.store);
  final DanmakuStore store;

  Future<List<JsonMap>> _tracks(String id) async {
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
    return tracks;
  }

  Future<List<double>?> load(String id, int? runtimeMs) async {
    final tracks = await _tracks(id);
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

  Future<List<String>> comments(List<(String, int?)> episodes,
      {Duration openingWindow = const Duration(minutes: 3), int maxEpisodes = 3}) async {
    final result = <String>[], seen = <String>{}, seenTracks = <String>{};
    for (final (id, duration) in episodes.take(maxEpisodes)) {
      final candidates = <({String text, int time})>[];
      for (final track in await _tracks(id)) {
        final start = track['start'] as int, end = track['end'] as int?;
        if (!seenTracks.add(jsonEncode([track['cache_key'], start, end, track['offset_ms']]))) continue;
        for (final entry in await store.entries(track['cache_key'] as String)) {
          final time = entry.sourceTimeMs + (track['offset_ms'] as int) - start;
          if (time < 0 || time >= openingWindow.inMilliseconds ||
              end != null && time >= end - start || duration != null && time >= duration) continue;
          final text = entry.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (text.runes.length < 2 || text.runes.length > 18 ||
              RegExp(r'(?:https?://|www\.|(?:[a-z0-9-]+\.)+[a-z]{2,24}\b|\b(?:\d{1,3}\.){3}\d{1,3}\b)', caseSensitive: false).hasMatch(text) ||
              RegExp(r'(.)\1{3,}', unicode: true).hasMatch(text) ||
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) continue;
          final normalized = text.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').toLowerCase();
          if (normalized.runes.length < 2 || RegExp(r'^(.{1,3})\1{2,}$', unicode: true).hasMatch(normalized)) continue;
          candidates.add((text: text, time: time));
        }
      }
      candidates.sort((a, b) => a.time.compareTo(b.time) != 0 ? a.time.compareTo(b.time) : a.text.compareTo(b.text));
      for (final c in candidates) {
        final normalized = c.text.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').toLowerCase();
        if (!seen.add(normalized)) continue;
        result.add(c.text);
        if (result.length == 6) return result;
      }
    }
    return result;
  }
}
