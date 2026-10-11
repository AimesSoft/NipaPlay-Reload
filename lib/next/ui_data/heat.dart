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

  Future<List<String>> comments(List<(String, int?)> episodes) async {
    final candidates = <({String text, int bucket, int episode})>[];
    final density = <(int, int), int>{};
    final seenTracks = <String>{};
    for (var index = 0; index < episodes.length; index++) {
      final (id, duration) = episodes[index];
      for (final track in await _tracks(id)) {
        final start = track['start'] as int, end = track['end'] as int?;
        if (!seenTracks.add(jsonEncode([track['cache_key'], start, end, track['offset_ms']]))) continue;
        for (final entry in await store.entries(track['cache_key'] as String)) {
          final time = entry.sourceTimeMs + (track['offset_ms'] as int) - start;
          if (time < 0 || end != null && time >= end - start || duration != null && time >= duration) continue;
          final bucket = duration == null ? time ~/ 30000 : math.min(59, time * 60 ~/ math.max(1, duration));
          final key = (index, bucket);
          density[key] = (density[key] ?? 0) + 1;
          final text = entry.text.trim();
          // Restrict to reactions that do not describe characters or events.
          if (text.runes.length < 2 || text.runes.length > 18 ||
              !RegExp(r'^[\p{Script=Han}a-zA-Z\s，。！？!~～]+$', unicode: true).hasMatch(text) ||
              RegExp(r'(.)\1{3,}').hasMatch(text) ||
              !RegExp(r'^(好看|太好看了|真好看|画面好美|好美|太美了|这画面真美|音乐好好听|音乐真好听|好听|这首歌好听|喜欢这个画风|这个画风好棒|制作好棒|制作真好|氛围真好|氛围感好棒|好治愈|太治愈了|笑死我了|哈哈哈|来了|前排|一起看)[，。！？!~～]*$').hasMatch(text)) continue;
          candidates.add((text: text, bucket: bucket, episode: index));
        }
      }
    }
    candidates.sort((a, b) {
      final hot = density[(b.episode, b.bucket)]!.compareTo(density[(a.episode, a.bucket)]!);
      if (hot != 0) return hot;
      final ep = a.episode.compareTo(b.episode);
      return ep != 0 ? ep : a.bucket.compareTo(b.bucket);
    });
    final seen = <String>{}, counts = <(int, int), int>{};
    final result = <String>[];
    for (final c in candidates) {
      final key = (c.episode, c.bucket);
      final normalized = c.text.replaceAll(RegExp(r'[\s，。！？!~～]'), '').toLowerCase();
      if ((counts[key] ?? 0) >= 2 || !seen.add(normalized)) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      result.add(c.text);
      if (result.length == 6) break;
    }
    return result;
  }
}
