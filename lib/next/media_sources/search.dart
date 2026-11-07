import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseException;
import '../harness_redaction.dart';
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
          if ({'smb', 'webdav'}.contains(row['type'])) row['sourceId'] as String
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
            'basis': 'indexed',
          };
          try {
            if (row == null) {
              throw const Failure(
                  FailureCode.notFound, 'Unknown media source.');
            }
            final type = row['type'] as String;
            final JsonMap page;
            if (type == 'smb' || type == 'webdav') {
              page = await _indexed(service, row, term, limit);
              if (row['connectionState'] == 'failed') {
                summary['error'] = const Failure(FailureCode.unavailable,
                        'Source connection failed; results are previously indexed files.')
                    .toJson();
              }
            } else {
              throw const Failure(
                  FailureCode.invalidInput, 'Search supports SMB and WebDAV.');
            }
            return publicHarnessFacts({...summary, ...page}) as JsonMap;
          } on Failure catch (error) {
            return publicHarnessFacts({
              ...summary,
              if (error.code == FailureCode.unavailable)
                'connectionState': 'failed',
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
      'poster': bindings.isEmpty
          ? null
          : (await service.cachedArtwork
              ?.call(bindings.first['workId'] as String))?['poster'],
      'workTitle': bindings.isEmpty
          ? null
          : ((await service.store
                  .mergedMetadata(bindings.first['workId'] as String))['fields']
              as Map)['title'],
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
