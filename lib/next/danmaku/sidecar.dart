import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../platform/report_error.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/local_danmaku_bytes.dart';
import 'package:nipaplay/utils/local_danmaku_match.dart';
import 'package:nipaplay/utils/danmaku_parser.dart';

import 'import.dart';
import 'source.dart';
import 'store.dart';

Future<({JsonMap facts, List<DanmakuEntry> entries})> readSidecar(
        String path) =>
    Isolate.run(() async {
      final watch = Stopwatch()..start();
      final file = File(path), before = await File(path).stat();
      final data = parseLocalDanmakuBytes(await file.readAsBytes());
      final rows = parseDanmakuListInBackground(data['comments'] as List);
      if (rows.isEmpty) throw const FormatException('No playable comments');
      final platform = data['platform'] as String;
      final videoId = data['platformVideoId'] as String?;
      final entries = [
        for (var i = 0; i < rows.length; i++)
          classicDanmakuEntry(rows[i], i, 'local', path,
              platform: platform == 'unknown'
                  ? rows[i]['source'] as String? ?? 'unknown'
                  : platform,
              originVideoId: videoId ?? rows[i]['platformVideoId'] as String?,
              preserveDeclaredOrigin: true)
      ];
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        throw const FileSystemException('Danmaku changed while reading');
      }
      final times = <String, int>{};
      for (final e in entries) {
        final t = e.sourceTimeMs.toString();
        times[t] = (times[t] ?? 0) + 1;
      }
      return (
        facts: <String, Object?>{
          'path': path,
          'available': true,
          'platform': platform,
          'platformVideoId': videoId,
          'size': after.size,
          'modifiedAt': after.modified.toUtc().toIso8601String(),
          'readAt': DateTime.now().toUtc().toIso8601String(),
          'readMs': watch.elapsedMilliseconds,
          'count': entries.length,
          'timeCounts': times,
        },
        entries: entries
      );
    });

final _entryCache =
    <String, ({int size, DateTime modified, List<DanmakuEntry> entries})>{};

Future<List<DanmakuEntry>> readSidecarEntries(String path) async {
  final stat = await File(path).stat();
  final cached = _entryCache[path];
  if (cached != null &&
      cached.size == stat.size &&
      cached.modified == stat.modified) {
    return cached.entries;
  }
  final read = await readSidecar(path);
  if (_entryCache.length == 4) _entryCache.remove(_entryCache.keys.first);
  _entryCache[path] =
      (size: stat.size, modified: stat.modified, entries: read.entries);
  return read.entries;
}

/// One reader at a time; indexing never waits for SMB comment reads.
final class SidecarIndexer {
  SidecarIndexer(this.store, this.onChanged);
  final DanmakuStore store;
  final Future<void> Function() onChanged;
  final Map<String, JsonMap> _pending = {};
  StreamSubscription<JsonMap>? _events;
  Timer? _timer;
  Future<void>? _worker;
  bool _closed = false;
  bool enabled = true;
  String? lastRun, lastError;
  JsonMap get status => {'kind': 'danmaku.sidecar', 'enabled': enabled,
    'running': _worker != null, 'queue': _pending.length, 'lastRun': lastRun,
    'nextRun': enabled ? 'within 30 seconds or on file change' : null, 'error': lastError};
  Future<void> setEnabled(bool value) async {
    enabled = value;
    if (value) {
      await reconcile();
      if (_pending.isNotEmpty && _worker == null) _worker = _drain().whenComplete(() => _worker = null);
    }
  }

  void start() {
    _events = store.identities.fileChanges.listen(enqueue);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => reconcile());
    unawaited(reconcile());
  }

  Future<void> reconcile() async {
    if (!enabled || _closed) return;
    for (final row in await store.db.query('media_locations',
        where: 'source=? AND owner_device_id=?',
        whereArgs: ['local', store.identities.ownerDeviceId])) {
      enqueue({'fileId': row['file_id'], 'path': row['locator']});
    }
  }

  void enqueue(JsonMap file) {
    if (_closed || (file['path'] as String).contains('://')) return;
    _pending[file['fileId'] as String] = file;
    if (!enabled) return;
    _worker ??= _drain().whenComplete(() => _worker = null);
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_closed && enabled) {
      final id = _pending.keys.first,
          file = _pending.remove(_pending.keys.first)!;
      try {
        await inspect(id, file['path'] as String);
        lastRun = DateTime.now().toUtc().toIso8601String();
        lastError = null;
      } catch (error, stack) {
        lastError = error.runtimeType.toString();
        reportNextError(error, stack, 'Next sidecar indexing');
      }
    }
  }

  final _reads = <String, Future<bool>>{};
  Future<bool> inspect(String id, String path) => _reads.putIfAbsent(
      id,
      () => _inspect(id, path).whenComplete(() {
            _reads.remove(id);
          }));

  Future<bool> _inspect(String id, String path) async {
    final bindings = await store.bindings(id);
    final previous = bindings.where((b) => b['local_file'] != null).firstOrNull;
    final old = previous?['local_file'] as JsonMap?;
    final candidates = await localDanmakuCandidates(path);
    for (final candidate in candidates) {
      final revision = (await store.identities.entity(id))['revision'];
      if (bindings.any((b) =>
          b['status'] == 'accepted' &&
          b['entity_revision'] == revision &&
          b['local_file'] == null &&
          b['cache_key'] != null &&
          (b['provenance'] as JsonMap?)?['filePath'] == candidate)) {
        return true;
      }
      final stat = await File(candidate).stat();
      if (old?['path'] == candidate &&
          old?['available'] == true &&
          old?['size'] == stat.size &&
          old?['modifiedAt'] == stat.modified.toUtc().toIso8601String() &&
          previous?['entity_revision'] ==
              (await store.identities.entity(id))['revision']) {
        return true;
      }
      try {
        final read = await readSidecar(candidate);
        await store.recordSidecar(id, read.facts);
        await onChanged();
        return true;
      } on FormatException catch (error) {
        if (old?['path'] == candidate) {
          await store.recordSidecar(id, {
            ...old!,
            'available': false,
            'checkedAt': store.now,
            'error': error.message.toString()
          });
        }
      } on FileSystemException catch (error) {
        if (old?['path'] == candidate) {
          await store.recordSidecar(id, {
            ...old!,
            'available': false,
            'checkedAt': store.now,
            'error': error.message
          });
        }
      }
    }
    if (old != null && old['available'] == true) {
      await store.recordSidecar(id, {
        ...old,
        'available': false,
        'checkedAt': store.now,
        'error': 'No readable matching file'
      });
      await onChanged();
    }
    return false;
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _events?.cancel();
    await _worker;
    await Future.wait(_reads.values);
  }
}
