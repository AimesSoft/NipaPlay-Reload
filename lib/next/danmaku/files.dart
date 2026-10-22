import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'source.dart';

/// File publication and collection run under the same database transaction as
/// their references. Readers also hold that transaction until content is read.
final class DanmakuFiles {
  DanmakuFiles(this.db);
  final Database db;
  Directory get root => File(db.path).parent;
  Directory get directory => Directory('${root.path}/danmaku');
  static const cacheBudget = 128 * 1024 * 1024;

  Future<Map<String, Object?>> write(List<Object?> entries, String kind) {
    final path = root.path;
    return _encodeAndPublish(path, entries, kind);
  }

  /// One chunk's raw entries. A content file is read, checked against its
  /// name and counts, and decoded on a background isolate.
  Future<List<Object?>> read(Map<String, Object?> row) async {
    final relative = row['file_path'] as String?;
    if (relative == null) return jsonDecode(row['payload'] as String) as List;
    _checkReference(relative);
    final path = root.path;
    final byteCount = row['byte_count'], entryCount = row['entry_count'];
    return Isolate.run(
        () => _readContent(path, relative, byteCount, entryCount));
  }

  /// Entries of one cache key, read from its chunk [rows] in chunk order,
  /// without duplicates, sorted by time. Content files are named by the
  /// SHA-256 of what they hold, so the same rows always hold the same
  /// entries: the result is kept per key for those rows and only read and
  /// decoded again, off the main isolate, when the rows change.
  Future<List<DanmakuEntry>> entries(
      String key, List<Map<String, Object?>> rows) async {
    final signature = _signature(rows);
    final id = '${root.path}\u0000$key';
    final hit = _decoded.remove(id);
    if (hit != null &&
        signature != null &&
        hit.signature == signature &&
        await _unchanged(hit.files)) {
      _decoded[id] = hit;
      return List.of(hit.entries);
    }
    for (final row in rows) {
      if (row['file_path'] case final String relative) {
        _checkReference(relative);
      }
    }
    final read = await _decodeChunks(
        root.path, [for (final row in rows) Map<String, Object?>.of(row)]);
    final entries = read.entries;
    if (signature != null && read.files != null) {
      _decoded[id] =
          (signature: signature, files: read.files!, entries: entries);
      var total = 0;
      for (final value in _decoded.values) {
        total += value.entries.length;
      }
      while (_decoded.length > 1 &&
          (total > decodedEntryBudget || _decoded.length > 32)) {
        total -= _decoded.remove(_decoded.keys.first)!.entries.length;
      }
    }
    return List.of(entries);
  }

  /// Kept decoded entries, least recently read first; at most 32 keys and
  /// [decodedEntryBudget] entries.
  static final _decoded = <String,
      ({
        String signature,
        Map<String, String> files,
        List<DanmakuEntry> entries
      })>{};

  /// A content file checked when it was read must still be that file: any
  /// write to it changes its size, modification or change time, and is read
  /// and checked again (so a damaged file still fails visibly).
  static Future<bool> _unchanged(Map<String, String> files) async {
    for (final MapEntry(key: path, value: stamp) in files.entries) {
      if (_stamp(await File(path).stat()) != stamp) return false;
    }
    return true;
  }

  static const decodedEntryBudget = 200000;

  /// Rows that keep their content inline (before migration) are not kept.
  static String? _signature(List<Map<String, Object?>> rows) {
    final parts = <String>[];
    for (final row in rows) {
      final path = row['file_path'];
      if (path == null) return null;
      parts.add('${row['chunk_index']}:$path:${row['byte_count']}:'
          '${row['entry_count']}');
    }
    return parts.join('|');
  }

  /// Commit one legacy row at a time; a crash leaves either its JSON or its
  /// verified file reference. The VACUUM marker survives interrupted compaction.
  Future<void> migrate() async {
    while (true) {
      final moved = await db.transaction((tx) async {
        final rows = await tx.query('danmaku_cache_chunks',
            where: 'file_path IS NULL', limit: 1);
        if (rows.isEmpty) return false;
        final row = rows.single;
        final bindings = await tx.query('danmaku_bindings',
            columns: ['provenance'],
            where: 'cache_key=?',
            whereArgs: [row['cache_key']]);
        final playbackOnly = bindings.isNotEmpty &&
            bindings.every((b) =>
                b['provenance'] != null &&
                (jsonDecode(b['provenance'] as String) as Map)['origin'] ==
                    'application:playback');
        final kind = row['coverage'] == 'importedPool' && !playbackOnly
            ? 'imported'
            : 'cache';
        final path = root.path, payload = row['payload'] as String;
        final reference = await _publishInIsolate(path, payload, kind);
        await tx.update('danmaku_cache_chunks', reference,
            where: 'cache_key=? AND chunk_index=?',
            whereArgs: [row['cache_key'], row['chunk_index']]);
        await tx.update('danmaku_storage_state', {'needs_vacuum': 1});
        return true;
      });
      if (!moved) break;
    }
    final state = await db.query('danmaku_storage_state');
    if (state.single['needs_vacuum'] == 1) {
      await db.execute('VACUUM');
      await db.update('danmaku_storage_state', {'needs_vacuum': 0});
    }
    await collect();
  }

  /// Release only keys explicitly replaced or revoked; shared pools survive.
  Future<void> release(DatabaseExecutor tx, Iterable<String> keys) async {
    for (final key in keys.toSet()) {
      final refs = await tx.query('danmaku_bindings',
          columns: ['id'],
          where: "cache_key=? AND status='accepted'",
          whereArgs: [key],
          limit: 1);
      if (refs.isEmpty) {
        await tx.delete('danmaku_cache_chunks',
            where: "cache_key=? AND storage_kind='imported'", whereArgs: [key]);
      }
    }
  }

  Future<void> collect() => db.transaction(collectInTransaction);

  Future<void> collectInTransaction(Transaction tx) async {
    if (!await directory.exists()) return;
    final referenced = (await tx.query('danmaku_cache_chunks',
            columns: ['file_path'], where: 'file_path IS NOT NULL'))
        .map((r) => r['file_path'])
        .toSet();
    await for (final file in directory.list(followLinks: false)) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      if ((RegExp(r'^[0-9a-f]{64}\.json$').hasMatch(name) ||
              name.endsWith('.tmp')) &&
          !referenced.contains('danmaku/$name')) {
        await file.delete();
      }
    }
  }

  /// Imported content never participates in the cache budget. Acquisition jobs
  /// retain their checkpoints and receipts until they finish.
  Future<Map<String, Object?>> prune({int maxBytes = cacheBudget, Set<String>? cacheKeys}) =>
      db.transaction((tx) async {
        final active = await tx.query('jobs',
            columns: ['job_id'],
            where:
                "type='danmaku.fetch' AND state NOT IN ('succeeded','failed','cancelled')",
            limit: 1);
        if (active.isNotEmpty) {
          return {'deferred': true, 'reclaimedBytes': 0, 'deletedPools': 0};
        }
        final pools = await tx.rawQuery(
            "SELECT cache_key,MIN(fetched_at) AS oldest "
            "FROM danmaku_cache_chunks GROUP BY cache_key "
            "HAVING SUM(CASE WHEN storage_kind='imported' THEN 1 ELSE 0 END)=0 "
            'ORDER BY oldest,cache_key');
        final rows = await tx.query('danmaku_cache_chunks');
        final protected = rows
            .where((r) => r['storage_kind'] == 'imported')
            .map((r) => r['file_path'])
            .toSet();
        final references = <Object?, int>{}, sizes = <Object?, int>{};
        for (final row in rows.where((r) => r['storage_kind'] == 'cache')) {
          final path = row['file_path'];
          references[path] = (references[path] ?? 0) + 1;
          sizes[path] = row['byte_count'] as int;
        }
        var remaining = sizes.entries
            .where((e) => !protected.contains(e.key))
            .fold<int>(0, (n, e) => n + e.value);
        var reclaimed = 0, deleted = 0;
        for (final pool in pools) {
          if (remaining <= maxBytes) break;
          final key = pool['cache_key'];
          if (cacheKeys != null && !cacheKeys.contains(key)) continue;
          await tx.delete('danmaku_cache_chunks',
              where: 'cache_key=?', whereArgs: [key]);
          await tx.update('danmaku_bindings', {'cache_key': null},
              where: 'cache_key=?', whereArgs: [key]);
          for (final row in rows.where((r) => r['cache_key'] == key)) {
            final path = row['file_path'];
            references[path] = references[path]! - 1;
            if (references[path] == 0 && !protected.contains(path)) {
              final bytes = sizes[path]!;
              remaining -= bytes;
              reclaimed += bytes;
            }
          }
          deleted++;
        }
        await collectInTransaction(tx);
        return {
          'deferred': false,
          'reclaimedBytes': reclaimed,
          'deletedPools': deleted,
          'remainingBytes': remaining
        };
      });
}

Future<Map<String, Object?>> _encodeAndPublish(
        String root, List<Object?> entries, String kind) =>
    Isolate.run(() => _publish(root, jsonEncode(entries), kind));

Future<Map<String, Object?>> _publishInIsolate(
        String root, String payload, String kind) =>
    Isolate.run(() => _publish(root, payload, kind));

Future<Map<String, Object?>> _publish(
    String root, String payload, String kind) async {
  final entries = jsonDecode(payload) as List;
  final bytes = utf8.encode(payload);
  final hash = sha256.convert(bytes).toString();
  final directory = Directory('$root/danmaku');
  await directory.create(recursive: true);
  final file = File('${directory.path}/$hash.json');
  if (await file.exists()) {
    if (sha256.convert(await file.readAsBytes()).toString() != hash) {
      throw const FormatException(
          'Existing danmaku content checksum mismatch.');
    }
  } else {
    final temp =
        File('${directory.path}/$hash-${Invocation(origin: 'storage').id}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (sha256.convert(await temp.readAsBytes()).toString() != hash) {
        throw const FormatException(
            'Danmaku content write verification failed.');
      }
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
  return {
    'payload': '[]',
    'file_path': 'danmaku/$hash.json',
    'entry_count': entries.length,
    'byte_count': bytes.length,
    'storage_kind': kind
  };
}

final _reference = RegExp(r'^danmaku/[0-9a-f]{64}\.json$');

void _checkReference(String relative) {
  if (!_reference.hasMatch(relative)) {
    throw const FormatException('Invalid danmaku content reference.');
  }
}

/// Reads and checks one content file; runs on a background isolate.
List<Object?> _readContent(
    String root, String relative, Object? byteCount, Object? entryCount) {
  final bytes = File('$root/$relative').readAsBytesSync();
  if ('danmaku/${sha256.convert(bytes)}.json' != relative ||
      bytes.length != byteCount) {
    throw const FormatException('Danmaku content checksum mismatch.');
  }
  final entries = jsonDecode(utf8.decode(bytes)) as List;
  if (entries.length != entryCount) {
    throw const FormatException('Danmaku content count mismatch.');
  }
  return entries;
}

String _stamp(FileStat stat) => '${stat.type}:${stat.size}:'
    '${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}';

/// Entries of [rows] with the stamp of every content file as it was read;
/// files is null when one changed while it was being read.
Future<({List<DanmakuEntry> entries, Map<String, String>? files})>
    _decodeChunks(String root, List<Map<String, Object?>> rows) =>
        Isolate.run(() {
          Map<String, String>? files = {};
          for (final row in rows) {
            if (row['file_path'] case final String relative) {
              files[relative] = _stamp(File('$root/$relative').statSync());
            }
          }
          final entries = decodeDanmakuChunks(root, rows);
          for (final MapEntry(key: relative, value: stamp)
              in files!.entries.toList()) {
            if (_stamp(File('$root/$relative').statSync()) != stamp) {
              files = null;
              break;
            }
          }
          return (
            entries: entries,
            files: files == null
                ? null
                : {
                    for (final e in files.entries) '$root/${e.key}': e.value
                  }
          );
        });

/// The entries of [rows] (one cache key's chunks in chunk order): each chunk
/// read and checked, entries the source identifies alike kept once, sorted
/// by time.
List<DanmakuEntry> decodeDanmakuChunks(
    String root, List<Map<String, Object?>> rows) {
  final entries = <DanmakuEntry>[];
  final seen = <String>{};
  for (final row in rows) {
    final relative = row['file_path'] as String?;
    final raws = relative == null
        ? jsonDecode(row['payload'] as String) as List
        : _readContent(root, relative, row['byte_count'], row['entry_count']);
    for (final raw in raws) {
      final e = DanmakuEntry.fromJson(Map<String, Object?>.from(raw as Map));
      final identity = e.sourceEntryId != null
          ? jsonEncode([e.sourceId, e.videoId, e.sourceEntryId])
          : e.platformId != null
              ? jsonEncode([
                  e.sourceId,
                  e.videoId,
                  e.platform,
                  e.originVideoId,
                  e.platformId
                ])
              : e.sender != null
                  ? jsonEncode([
                      e.sourceId,
                      e.videoId,
                      e.platform,
                      e.sender,
                      e.sourceTimeMs,
                      e.text,
                      e.mode,
                      e.colorRgb
                    ])
                  : null;
      if (identity == null || seen.add(identity)) {
        entries.add(e);
      }
    }
  }
  entries.sort((a, b) => a.sourceTimeMs.compareTo(b.sourceTimeMs));
  return entries;
}
