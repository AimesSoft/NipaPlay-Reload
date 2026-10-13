import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smb_connect/src/exceptions.dart'
    show SmbException, SmbConnectException;
import '../harness_redaction.dart';
import 'library_service.dart';

/// Last successful directory observations, scoped to the actual server.
final class LibrarySourceCache implements LibrarySourcePort {
  LibrarySourceCache(this.delegate, this.db);
  final LibrarySourcePort delegate;
  final Database db;
  final Map<String, String> _offline = {};

  String _key(List<Object?> parts) =>
      'library:source-cache:${base64Url.encode(utf8.encode(jsonEncode(parts)))}';
  Future<String> _scope(String id) async {
    final source = (await delegate.sources(initialize: false))
        .firstWhere((s) => s['sourceId'] == id);
    return _key([id, source['serverId']]);
  }

  Future<Object?> _saved(String key) async {
    final rows = await db.query('ui_cache', where: 'id=?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.single['payload'] as String);
  }

  Future<void> _save(String key, Object? value) async {
    final payload =
        jsonEncode((publicHarnessFacts({'value': value}) as Map)['value']);
    final old = await db.query('ui_cache',
        where: 'id=? AND fingerprint=?', whereArgs: [key, payload]);
    if (old.isEmpty) {
      await db.insert(
          'ui_cache', {'id': key, 'fingerprint': payload, 'payload': payload},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<(T, bool)> _read<T>(String id, String scope,
      Future<T> Function() fetch, Future<T> Function() cached,
      {bool retry = false}) async {
    if (!retry && _offline[id] == scope) return (await cached(), false);
    late T value;
    try {
      value = await fetch();
    } catch (error) {
      // Classic transport clients also wrap network/authentication failures
      // in plain Exception. Invalid JSON and domain-reference errors propagate.
      if (!(error is Exception ||
              error is SmbException ||
              error is SmbConnectException) ||
          error is FormatException ||
          error is DatabaseException ||
          error is FileSystemException ||
          (error is Failure && error.code != FailureCode.unavailable)) {
        rethrow;
      }
      _offline[id] = scope;
      return (await cached(), false);
    }
    _offline.remove(id);
    return (value, true);
  }

  @override
  Future<List<JsonMap>> sources({bool initialize = true}) async => [
        for (final s in await delegate.sources(initialize: initialize))
          {
            ...s,
            if (_offline[s['sourceId']] == _key([s['sourceId'], s['serverId']]))
              'connected': false
          }
      ];

  @override
  Future<List<JsonMap>> roots(String sourceId) async {
    final scope = await _scope(sourceId);
    final key = _key([scope, 'roots']);
    final (value, fresh) = await _read(
        sourceId,
        scope,
        () => delegate.roots(sourceId),
        () async => ((await _saved(key)) as List? ?? []).cast<JsonMap>(),
        retry: true);
    if (fresh) await _save(key, value);
    return value;
  }

  @override
  Future<JsonMap> browse(String sourceId, String parentId,
      {int offset = 0,
      int limit = 60,
      String? sort,
      bool recursive = false,
      String? filters}) async {
    final scope = await _scope(sourceId);
    sort ??= await delegate.currentSort(sourceId, parentId);
    final key = _key([scope, 'directory', parentId, sort, recursive, filters]);
    final (value, fresh) = await _read(
        sourceId,
        scope,
        () => delegate.browse(sourceId, parentId,
            offset: offset,
            limit: limit,
            sort: sort,
            recursive: recursive,
            filters: filters), () async {
      final header = await _saved(key) as Map?;
      final rows = await db.query('ui_cache',
          where: 'id>=? AND id<?',
          whereArgs: [
            '$key:${offset.toString().padLeft(12, '0')}',
            '$key:${(offset + limit).toString().padLeft(12, '0')}'
          ],
          orderBy: 'id',
          limit: limit);
      return {
        'entries': [
          for (final r in rows) jsonDecode(r['payload'] as String) as JsonMap
        ],
        'total': header?['total'] ?? 0
      };
    });
    if (fresh) {
      await db.transaction((tx) async {
        final batch = tx.batch();
        final header = jsonEncode({'total': value['total']});
        final savedHeader =
            await tx.query('ui_cache', where: 'id=?', whereArgs: [key]);
        if (savedHeader.isEmpty ||
            savedHeader.single['fingerprint'] != header) {
          batch.insert(
              'ui_cache', {'id': key, 'fingerprint': header, 'payload': header},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        final savedEntries = {
          for (final r in await tx.query('ui_cache',
              where: 'id>=? AND id<?',
              whereArgs: [
                '$key:${offset.toString().padLeft(12, '0')}',
                '$key:${(offset + limit).toString().padLeft(12, '0')}'
              ],
              limit: limit))
            r['id']: r['fingerprint']
        };
        var index = offset;
        for (final entry in value['entries'] as List) {
          final payload = jsonEncode(publicHarnessFacts(entry));
          final id = '$key:${index.toString().padLeft(12, '0')}';
          if (savedEntries[id] != payload)
            batch.insert('ui_cache',
                {'id': id, 'fingerprint': payload, 'payload': payload},
                conflictAlgorithm: ConflictAlgorithm.replace);
          index++;
        }
        final total = value['total'] as int?;
        if (total != null) {
          batch.delete('ui_cache', where: 'id>=? AND id<?', whereArgs: [
            '$key:${total.toString().padLeft(12, '0')}',
            '$key:~'
          ]);
        }
        await batch.commit(noResult: true);
      });
    }
    return value;
  }

  @override
  Future<JsonMap> item(String sourceId, String itemId) async {
    final scope = await _scope(sourceId);
    final key = _key([scope, 'item', itemId]);
    final (value, fresh) = await _read(
        sourceId, scope, () => delegate.item(sourceId, itemId), () async {
      final saved = await _saved(key);
      if (saved == null) {
        throw const Failure(FailureCode.notFound, 'No cached source item.');
      }
      return Map<String, Object?>.from(saved as Map);
    });
    if (fresh) await _save(key, value);
    return value;
  }

  @override
  Future<String?> image(String sourceId, JsonMap item, String kind) async {
    final scope = await _scope(sourceId);
    final m = item['metadata'] as Map? ?? {};
    final key = _key([
      scope,
      'image',
      item['id'],
      kind,
      m['ImageTags'],
      m['BackdropImageTags']
    ]);
    final saved = await _saved(key) as String?;
    if (saved != null && await File(saved).exists()) return saved;
    final (value, fresh) = await _read<String?>(sourceId, scope,
        () => delegate.image(sourceId, item, kind), () async => null);
    if (fresh) await _save(key, value);
    return value;
  }

  @override
  Future<String?> currentSort(String sourceId, String parentId) =>
      delegate.currentSort(sourceId, parentId);
}
