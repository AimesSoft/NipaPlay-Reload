import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import 'file_identity_merge.dart';
import 'identity_store.dart';

/// What the library holds about files that just came in, as it is now.
/// Each entry is `{path, via, enteredAt, fileId?}`; nothing is filtered and
/// no entry is judged. A file with no episode link has empty `episodes`.
///
/// - `via`: the door, as far as the code can tell: `local_scan` (a local
///   folder scan), `classic_history` (Classic's scan or watch history),
///   `media_source` (a media source's listing), `download_import`,
///   `metadata_put`, or `path` (some operation named the path).
/// - `source`: the location's source (`local`, `remote`, or a media source
///   scope) and, for a media source entry, which source and item.
/// - `episodes[].identitySources`: where each file-episode link came from.
/// - `works[].identities.tmdb`: whether that work has an accepted TMDB
///   identity (the same test as `media.metadata.ui_facts`).
Future<List<JsonMap>> describeLibraryArrivals(
    IdentityStore store, List<JsonMap> entries) async {
  final facts = <JsonMap>[];
  for (final entry in entries) {
    final path = entry['path'] as String;
    final location = (await store.database.query('media_locations',
            where: 'owner_device_id=? AND locator=?',
            whereArgs: [store.ownerDeviceId, path]))
        .firstOrNull;
    final recorded = entry['fileId'] as String? ??
        location?['file_id'] as String?;
    final fileId =
        recorded == null ? null : await canonicalFileId(store.database, recorded);
    final links = fileId == null
        ? const <Map<String, Object?>>[]
        : await store.database.rawQuery(
            'SELECT DISTINCT r.parent_id AS workId, e.id AS episodeId, '
            'e.attributes AS episodeFacts FROM media_file_episodes fe '
            'JOIN media_entities e ON e.id=fe.episode_id '
            'JOIN media_entities r ON r.id=e.parent_id WHERE fe.file_id=?',
            [fileId]);
    final sources =
        fileId == null ? const <String, List<JsonMap>>{} : await store.linkSources(fileId);
    final remote = fileId == null
        ? null
        : ((await store.entity(fileId))['attributes'] as JsonMap)['remoteSource']
            as Map?;
    final workIds = {for (final row in links) row['workId'] as String}.toList();
    facts.add({
      'path': path,
      'fileId': fileId,
      'via': entry['via'],
      'enteredAt': entry['enteredAt'],
      'source': {
        if (location != null) 'location': location['source'],
        if (remote != null)
          'mediaSource': {
            for (final key in ['sourceId', 'type', 'itemId', 'serverId', 'name'])
              if (remote[key] != null) key: remote[key]
          },
      },
      'workIds': workIds,
      'works': [
        for (final id in workIds)
          {
            'workId': id,
            'identities': {'tmdb': await store.workHasTmdb(id)}
          }
      ],
      'episodes': [
        for (final row in links)
          {
            'episodeId': row['episodeId'],
            'workId': row['workId'],
            'facts': jsonDecode(row['episodeFacts'] as String),
            'identitySources': sources[row['episodeId']] ?? <JsonMap>[]
          }
      ],
    });
  }
  return facts;
}
