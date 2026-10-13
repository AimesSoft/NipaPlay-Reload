import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../media_sources/service.dart';
import '../media_sources/metadata.dart';
import '../harness_redaction.dart';
import 'library_service.dart';
import 'raster_io.dart' if (dart.library.ui) 'raster_flutter.dart';

final class ClassicLibrarySources implements LibrarySourcePort {
  ClassicLibrarySources(this.service, this.root);
  final MediaSourcesService service;
  final Directory root;
  final _parents = <String, String>{};
  String _parentKey(String sourceId, String itemId) =>
      'library:parent:${base64Url.encode(utf8.encode(jsonEncode([
            sourceId,
            itemId
          ])))}';
  @override
  Future<String?> currentSort(String sourceId, String parentId) =>
      _sort(sourceId, parentId);
  @override
  Future<List<JsonMap>> sources({bool initialize = true}) async {
    if (initialize) await service.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    return [
      for (final r in await service.list())
        if (const {'smb', 'webdav', 'jellyfin', 'emby'}.contains(r['type']))
          {
            ...r,
            'sortSettings':
                prefs.getString('${r['type']}_library_sort_settings'),
            if (r['type'] == 'jellyfin' || r['type'] == 'emby')
              'serverId': service.profiles
                  .getProfileById(service.key(r['sourceId'] as String))!
                  .serverId
          }
    ];
  }

  @override
  Future<List<JsonMap>> roots(String sourceId) async {
    final row = await service.source(sourceId);
    if (row['type'] == 'smb' || row['type'] == 'webdav') {
      await browse(sourceId, '/', limit: 1);
      return [
        {'id': '/', 'name': row['name']}
      ];
    }
    final result = await service.libraries(sourceId);
    final selected = (result['selectedLibraries'] as List).cast<String>();
    return [
      for (final l in result['libraries'] as List<JsonMap>)
        if (selected.contains(l['id']))
          {
            ...l,
            'sort': await _sort(sourceId, l['id'] as String),
            'serverId':
                service.server(row['type'] as String).currentProfile!.serverId
          }
    ];
  }

  Future<String> _sort(String sourceId, String parentId) async {
    final type = sourceId.split(':').first;
    final prefs = await SharedPreferences.getInstance();
    final settings =
        jsonDecode(prefs.getString('${type}_library_sort_settings') ?? '{}')
            as Map;
    var parent = parentId;
    while (!settings.containsKey(parent)) {
      var next = _parents['$sourceId:$parent'];
      if (next == null) {
        final saved = await service.store.database.query('ui_cache',
            where: 'id=?', whereArgs: [_parentKey(sourceId, parent)]);
        if (saved.isNotEmpty)
          next = jsonDecode(saved.single['payload'] as String) as String;
      }
      if (next == null) break;
      parent = next;
    }
    final s = settings[parent] as Map?;
    return '${s?['sortBy'] ?? 'SortName'}:${s?['sortOrder'] ?? 'Ascending'}';
  }

  JsonMap _entry(Map<String, dynamic> item) => {
        'id': item['Id'],
        'name': item['Name'],
        'kind': item['Type'],
        'isDirectory': item['IsFolder'] == true ||
            const {'CollectionFolder', 'Folder', 'Series', 'Season'}
                .contains(item['Type']),
        'metadata': serverMetadata(item)
      };
  @override
  Future<JsonMap> browse(String sourceId, String parentId,
      {int offset = 0,
      int limit = 60,
      String? sort,
      bool recursive = false,
      String? filters}) async {
    final row = await service.source(sourceId);
    final type = row['type'] as String;
    if (type == 'smb' || type == 'webdav') {
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
    return service.serial(() async {
      await service.activate(row);
      final ordering = (sort ?? await _sort(sourceId, parentId)).split(':');
      final result = await service.server(type).catalogPage(
          parentId: parentId,
          offset: offset,
          limit: limit,
          fields: catalogMetadataFields,
          recursive: recursive,
          filters: filters,
          sortBy: ordering[0],
          sortOrder: ordering[1]);
      final entries = (result['Items'] as List).cast<Map<String, dynamic>>();
      for (final item in entries) {
        final itemId = item['Id'] as String;
        _parents['$sourceId:$itemId'] = parentId;
        final saved = await service.store.database.query('ui_cache',
            where: 'id=? AND fingerprint=?',
            whereArgs: [_parentKey(sourceId, itemId), parentId]);
        if (saved.isEmpty)
          await service.store.database.insert(
              'ui_cache',
              {
                'id': _parentKey(sourceId, itemId),
                'fingerprint': parentId,
                'payload': jsonEncode(parentId)
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final projected = <JsonMap>[];
      for (final item in entries) {
        final entry = {
          ..._entry(item),
          'serverId': service.server(type).currentProfile!.serverId
        };
        if (entry['isDirectory'] != true)
          entry['fileId'] = await service.store
              .ensureRemoteFile('$type://${item['Id']}', sourceId, {
            'type': type,
            'serverId': service.server(type).currentProfile!.serverId,
            'itemId': item['Id'],
            'seriesId': item['SeriesId'],
            'seasonId': item['SeasonId'],
            'number': item['IndexNumber'],
            'name': item['Name']
          });
        projected.add(entry);
      }
      return {'entries': projected, 'total': result['TotalRecordCount']};
    });
  }

  @override
  Future<JsonMap> item(String sourceId, String itemId) async {
    final row = await service.source(sourceId);
    if (row['type'] == 'smb' || row['type'] == 'webdav') {
      final slash = itemId.lastIndexOf('/');
      final result = await service.browse(
          sourceId, slash <= 0 ? '/' : itemId.substring(0, slash));
      return (result['entries'] as List<JsonMap>)
          .firstWhere((e) => e['id'] == itemId);
    }
    return service.serial(() async {
      await service.activate(row);
      final result = await service.server(row['type'] as String).catalogPage(
          itemIds: [itemId], fields: catalogMetadataFields, limit: 1);
      final items = result['Items'] as List;
      if (items.isEmpty)
        throw const Failure(FailureCode.notFound, 'Server item was removed.');
      return {
        ..._entry(items.single as Map<String, dynamic>),
        'serverId':
            service.server(row['type'] as String).currentProfile!.serverId
      };
    });
  }

  @override
  Future<String?> image(String sourceId, JsonMap item, String kind) async {
    final type = sourceId.split(':').first;
    if (type != 'jellyfin' && type != 'emby') return null;
    final m = item['metadata'] as Map;
    final tag = kind == 'Backdrop'
        ? (m['BackdropImageTags'] as List?)?.firstOrNull
        : (m['ImageTags'] as Map?)?[kind];
    if (tag == null) return null;
    final key = sha256.convert(utf8.encode(
        jsonEncode([sourceId, item['serverId'], item['id'], kind, tag])));
    final file = File('${root.path}/source-artwork/$key');
    if (await file.exists()) return file.path;
    return service.serial(() async {
      final row = await service.source(sourceId);
      await service.activate(row);
      final bytes = await service
          .server(type)
          .catalogImage(item['id'] as String, kind, tag as String);
      await validateRaster(bytes);
      await file.parent.create(recursive: true);
      final staging = File('${file.path}.part');
      await staging.writeAsBytes(bytes, flush: true);
      await staging.rename(file.path);
      return file.path;
    });
  }
}
