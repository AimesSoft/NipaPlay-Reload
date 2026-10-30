import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseException;
import '../harness_redaction.dart';
import '../ui_data/library_service.dart' show sourceEntityId;
import 'metadata.dart';
import 'service.dart';

Future<JsonMap> searchSources(MediaSourcesService service, String query,
    {List<String>? sourceIds, int limit = 12}) async {
  final term = query.trim();
  if (term.isEmpty) {
    throw const Failure(
        FailureCode.invalidInput, 'Search query must not be blank.');
  }
  final rows = await service.list();
  final ids = sourceIds?.toSet().toList() ??
      [
        for (final row in rows)
          if ({'jellyfin', 'emby', 'smb', 'webdav', 'dandanplay_remote'}.contains(row['type']))
            row['sourceId'] as String
      ];
  return {
    'sources': await Future.wait([
      for (final id in ids)
        service.serial(() async {
          final row = rows.where((r) => r['sourceId'] == id).firstOrNull;
          final summary = <String, Object?>{
            'sourceId': id,
            'name': row?['name'],
            'type': row?['type'],
            'connectionState': row?['connectionState'] ?? 'unknown',
            'basis': row?['type'] == 'smb' || row?['type'] == 'webdav'
                ? 'indexed'
                : 'server',
          };
          try {
            if (row == null) {
              throw const Failure(
                  FailureCode.notFound, 'Unknown media source.');
            }
            final type = row['type'] as String;
            final JsonMap page;
            if (type == 'jellyfin' || type == 'emby') {
              await service.activate(row);
              final server = service.server(type);
              final result = await server.catalogPage(
                  recursive: true,
                  limit: limit,
                  searchTerm: term,
                  includeItemTypes: 'Series,Movie,Episode,Video',
                  fields: catalogMetadataFields);
              final serverId = server.currentProfile!.serverId;
              final entries = <JsonMap>[];
              for (final item in (result['Items'] as List).cast<Map>()) {
                final itemId = item['Id'] as String;
                final directory = item['Type'] == 'Series';
                final existing = await service.store.database.rawQuery(
                    "SELECT f.id AS fileId,r.parent_id AS workId,fe.episode_id AS episodeId FROM media_entities f LEFT JOIN media_file_episodes fe ON fe.file_id=f.id LEFT JOIN media_entities e ON e.id=fe.episode_id LEFT JOIN media_entities r ON r.id=e.parent_id WHERE f.kind='file' AND json_extract(f.attributes,'\$.remoteSource.sourceId')=? AND json_extract(f.attributes,'\$.remoteSource.serverId')=? AND (json_extract(f.attributes,'\$.remoteSource.itemId')=? OR (?=1 AND json_extract(f.attributes,'\$.remoteSource.seriesId')=?))",
                    [id, serverId, itemId, directory ? 1 : 0, itemId]);
                final local =
                    existing.where((e) => e['workId'] != null).firstOrNull;
                entries.add({
                  'itemId': itemId,
                  'title': item['Name'],
                  'kind': item['Type'],
                  'year': item['ProductionYear'],
                  'originalTitle': item['OriginalTitle'],
                  'metadata': serverMetadata(Map<String, dynamic>.from(item)),
                  'poster': await service.cachedPoster?.call(id, {
                    'id': itemId, 'serverId': serverId,
                    'metadata': serverMetadata(Map<String, dynamic>.from(item)),
                  }) ?? (local == null ? null :
                    (await service.cachedArtwork?.call(local['workId'] as String))?['poster']),
                  'workTitle': local == null ? null :
                    ((await service.store.mergedMetadata(local['workId'] as String))['fields'] as Map)['title'],
                  'fileId': directory ? null : existing.firstOrNull?['fileId'],
                  'workId': local == null
                      ? null
                      : await _canonical(service, local['workId'] as String),
                  'episodeId': directory || local?['episodeId'] == null
                      ? null
                      : await _canonical(
                          service, local!['episodeId'] as String),
                  'sourceWorkId': item['Type'] == 'Episode'
                      ? (item['SeriesId'] == null
                          ? null
                          : sourceEntityId(
                              'work', id, item['SeriesId'] as String,
                              serverId: serverId))
                      : sourceEntityId('work', id, itemId, serverId: serverId),
                  'sourceEpisodeId': directory
                      ? null
                      : sourceEntityId('episode', id, itemId,
                          serverId: serverId),
                  'playable': !directory,
                  'provenance': sourceProvenance(
                      row, itemId, DateTime.now().toUtc().toIso8601String()),
                });
              }
              summary['connectionState'] = 'connected';
              page = {'entries': entries, 'total': result['TotalRecordCount']};
            } else if (type == 'dandanplay_remote') {
              await service.dandanRemote.refreshLibrary();
              final episodes = service.dandanRemote.cachedEpisodes;
              final serverId = row['url'] as String?;
              final all = [
                ...dandanCatalogEntries(episodes, null, serverId: serverId),
                ...dandanCatalogEntries(episodes, null, itemIds: episodes.map((e) => e.entryId).toList(), serverId: serverId),
              ].where((e) => e['kind'] != 'Folder' && '${e['name']}'.toLowerCase().contains(term.toLowerCase())).toList();
              page = {'total': all.length, 'entries': [
                for (final e in all.take(limit)) {
                  'itemId': e['id'], 'title': e['name'], 'kind': e['kind'],
                  'metadata': e['metadata'], 'playable': e['isDirectory'] != true,
                  'workId': null, 'episodeId': null, 'fileId': null,
                  'sourceWorkId': sourceEntityId('work', id, e['kind'] == 'Series' ? e['id'] as String : (e['metadata'] as Map)['SeriesId'] as String, serverId: serverId),
                  if (e['kind'] == 'Episode') 'sourceEpisodeId': sourceEntityId('episode', id, e['id'] as String, serverId: serverId),
                  'poster': await service.cachedPoster?.call(id, e),
                  'provenance': sourceProvenance(row, e['id'] as String, DateTime.now().toUtc().toIso8601String()),
                },
              ]};
              summary['connectionState'] = 'connected';
            } else if (type == 'smb' || type == 'webdav') {
              page = await _indexed(service, row, term, limit);
              if (row['connectionState'] == 'failed') {
                summary['error'] = const Failure(FailureCode.unavailable,
                        'Source connection failed; results are previously indexed files.')
                    .toJson();
              }
            } else {
              throw const Failure(FailureCode.invalidInput,
                  'Search supports Jellyfin, Emby, SMB and WebDAV.');
            }
            return publicHarnessFacts({...summary, ...page}) as JsonMap;
          } on Failure catch (error) {
            return publicHarnessFacts({
              ...summary,
              if (error.code == FailureCode.unavailable) 'connectionState': 'failed',
              'entries': <JsonMap>[],
              'total': null,
              'error': error.toJson()
            }) as JsonMap;
          } catch (error) {
            // Transport errors belong to this source, and never expose URLs/credentials.
            if (error is! Exception ||
                error is FormatException ||
                error is DatabaseException ||
                error is FileSystemException) {
              rethrow;
            }
            return {
              ...summary,
              'connectionState': 'failed',
              'entries': <JsonMap>[],
              'total': null,
              'error': const Failure(FailureCode.unavailable,
                      'Source search could not connect or authenticate.')
                  .toJson()
            };
          }
        })
    ])
  };
}

Future<String> _canonical(MediaSourcesService service, String id) async =>
    service.canonicalEntityId == null
        ? id
        : await service.canonicalEntityId!(id);

Future<JsonMap> _indexed(
    MediaSourcesService service, JsonMap source, String term, int limit) async {
  final pattern =
      '%${term.toLowerCase().replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
  const clause =
      "FROM media_entities f WHERE f.kind='file' AND json_extract(f.attributes,'\$.remoteSource.sourceId')=? AND (lower(json_extract(f.attributes,'\$.remoteSource.name')) LIKE ? ESCAPE '\\' OR lower(json_extract(f.attributes,'\$.remoteSource.itemId')) LIKE ? ESCAPE '\\')";
  final db = service.store.database,
      args = [source['sourceId'], pattern, pattern];
  final total =
      (await db.rawQuery('SELECT COUNT(*) AS n $clause', args)).single['n'];
  final entries = <JsonMap>[];
  for (final row in await db.rawQuery(
      'SELECT f.id,f.attributes $clause ORDER BY f.id LIMIT ?',
      [...args, limit])) {
    final remote =
        (jsonDecode(row['attributes'] as String) as Map)['remoteSource'] as Map;
    final bindings = await db.rawQuery(
        "SELECT fe.episode_id AS episodeId,r.parent_id AS workId FROM media_file_episodes fe JOIN media_entities e ON e.id=fe.episode_id JOIN media_entities r ON r.id=e.parent_id WHERE fe.file_id=? ORDER BY fe.episode_id",
        [row['id']]);
    entries.add({
      'itemId': remote['itemId'],
      'title': remote['name'],
      'kind': 'File',
      'fileId': row['id'],
      'year': null,
      'poster': bindings.isEmpty ? null :
        (await service.cachedArtwork?.call(bindings.first['workId'] as String))?['poster'],
      'workTitle': bindings.isEmpty ? null :
        ((await service.store.mergedMetadata(bindings.first['workId'] as String))['fields'] as Map)['title'],
      'workId': bindings.isEmpty
          ? null
          : await _canonical(service, bindings.first['workId'] as String),
      'episodeId': bindings.length == 1
          ? await _canonical(service, bindings.single['episodeId'] as String)
          : null,
      'playable': source['connected'] == true,
      'provenance': {
        'sourceId': source['sourceId'],
        'name': source['name'],
        'type': source['type'],
        'itemId': remote['itemId']
      },
    });
  }
  return {'entries': entries, 'total': total};
}
