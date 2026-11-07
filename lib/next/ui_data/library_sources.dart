import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../media_sources/service.dart';
import '../harness_redaction.dart';
import 'library_service.dart';

final class ClassicLibrarySources implements LibrarySourcePort {
  ClassicLibrarySources(this.service, this.root);
  final MediaSourcesService service;
  final Directory root;
  @override
  Future<String?> currentSort(String sourceId, String parentId) async =>
      'SortName:Ascending';
  @override
  Future<List<JsonMap>> sources({bool initialize = true}) async {
    if (initialize) await service.ensureInitialized();
    return service.list();
  }

  @override
  Future<List<JsonMap>> roots(String sourceId) async {
    final row = await service.source(sourceId);
    await browse(sourceId, '/', limit: 1);
    return [
      {'id': '/', 'name': row['name']}
    ];
  }

  @override
  Future<JsonMap> browse(String sourceId, String parentId,
      {int offset = 0,
      int limit = 60,
      String? sort,
      bool recursive = false,
      String? filters}) async {
    final row = await service.source(sourceId);
    final type = row['type'] as String;
    final db = service.store.database;
    final prefix =
        'library:directory:${base64Url.encode(utf8.encode(jsonEncode([
          sourceId,
          parentId
        ])))}:';
    const where = 'id>=? AND id<?';
    final args = [prefix, '$prefix~'];
    if (offset == 0 ||
        (await db.query('ui_cache', where: where, whereArgs: args, limit: 1))
            .isEmpty) {
      final result = await service.browse(sourceId, parentId);
      final entries = (result['entries'] as List<JsonMap>).where((e) =>
          e['isDirectory'] == true ||
          (type == 'smb'
              ? service.smb.isVideoFile(e['name'] as String)
              : service.webdav.isVideoFile(e['name'] as String)));
      await db.transaction((tx) async {
        final batch = tx.batch();
        final existing = {
          for (final r
              in await tx.query('ui_cache', where: where, whereArgs: args))
            r['id']: r['payload']
        };
        for (final entry in entries) {
          final id =
              '$prefix${base64Url.encode(utf8.encode(entry['id'] as String))}';
          final payload = jsonEncode(publicHarnessFacts(entry));
          final previous = existing.remove(id);
          if (previous == payload) continue;
          batch.insert('ui_cache',
              {'id': id, 'fingerprint': 'directory', 'payload': payload},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final id in existing.keys) {
          batch.delete('ui_cache', where: 'id=?', whereArgs: [id]);
        }
        await batch.commit(noResult: true);
      });
    }
    final order = sort == 'DateCreated:Descending'
        ? "json_extract(payload,'\$.metadata.LastModified') DESC,id"
        : "json_extract(payload,'\$.isDirectory') DESC,json_extract(payload,'\$.name') COLLATE NOCASE,id";
    final count = (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM ui_cache WHERE $where', args))
        .single['n'];
    final rows = await db.query('ui_cache',
        where: where,
        whereArgs: args,
        orderBy: order,
        offset: offset,
        limit: limit);
    return {
      'entries': [
        for (final r in rows) jsonDecode(r['payload'] as String) as JsonMap
      ],
      'total': count
    };
  }

  @override
  Future<JsonMap> item(String sourceId, String itemId) async {
    final slash = itemId.lastIndexOf('/');
    final result = await service.browse(
        sourceId, slash <= 0 ? '/' : itemId.substring(0, slash));
    return (result['entries'] as List<JsonMap>)
        .firstWhere((e) => e['id'] == itemId);
  }

  @override
  Future<String?> image(String sourceId, JsonMap item, String kind) async =>
      null;
}
