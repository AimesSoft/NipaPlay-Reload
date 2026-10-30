part of 'identity_store.dart';

/// Native server IDs are scoped to the connection and actual server. They
/// describe the server's catalogue, not an inferred TMDB/Bangumi identity.
String sourceCatalogId(String kind, String sourceId, String itemId,
        {String? serverId}) =>
    'source-$kind:${base64Url.encode(utf8.encode(jsonEncode([
      sourceId, itemId, if (serverId != null) serverId,
    ])))}';

extension SourceCatalogStore on IdentityStore {
  Future<void> observeSourceCatalog(List<JsonMap> records) =>
      _transaction((tx) async {
        for (final record in records) {
          final nativeId = record['id'] as String;
          final id = await canonicalFileId(tx, nativeId);
          final parent = record['parentId'] as String?;
          final fields = record['fields'] as JsonMap;
          final source = record['source'] as JsonMap;
          final attrs = <String, Object?>{
            'title': fields['title'],
            'type': 'regular',
            'number': fields['number'],
            'season': fields['season'],
            'order': 'aired',
            'sourceCatalog': source,
            if (record['film'] == true) 'film': true,
          };
          final existing = await tx.query('media_entities', where: 'id=?', whereArgs: [id]);
          if (existing.isEmpty) {
            await tx.insert('media_entities', {
              'id': id, 'kind': record['kind'],
              'parent_id': parent == null ? null : await canonicalFileId(tx, parent),
              'revision': 0, 'attributes': jsonEncode(attrs),
            });
          }
          // A placeholder parent never replaces the parent's detailed snapshot.
          if (record['placeholder'] != true) {
            final ref = ExternalRef('https://sources.nipaplay.app',
                record['objectType'] as String, source['itemId'] as String,
                scope: jsonEncode([ownerDeviceId, source['sourceId'], source['serverId']]));
            final object = await _object(tx, ref);
            final fingerprint = stableMediaId('source-observation', fields);
            final previous = await tx.query('media_snapshots', columns: ['fields'],
                where: "object_id=? AND json_extract(fields,'\$.details.sourceFingerprint') IS NOT NULL", whereArgs: [object], orderBy: 'fetched_at DESC', limit: 1);
            final invocation = BodyChanges.invocation ?? Invocation(origin: 'source_catalog');
            final metadata = MetadataRecord(
                ref: ref, title: fields['title'] as String, kind: record['objectType'] as String,
                language: 'und', details: {...fields, 'sourceFingerprint': fingerprint},
                acquisition: const {'kind': 'detail', 'sections': {'source_catalogue': 'received'}},
                fetchedAt: DateTime.now().toUtc());
            if ((await tx.query('media_bindings', columns: ['id'], where: 'entity_id=? AND object_id=? AND source=?', whereArgs: [id, object, 'source_catalog'])).isEmpty) {
              await _bindRecord(tx, id, metadata, 'exact', {}, 'automatic',
                  'source_catalog', invocation, nativeId, 0, saveMetadata: false);
            }
            if (previous.isEmpty ||
                (decodeMediaJson(previous.single['fields'])['details'] as Map?)?['sourceFingerprint'] != fingerprint) {
              await _snapshot(tx, object, metadata);
            }
          }
          if (record['fileId'] case final String fileId) {
            final links = await tx.query('media_file_episodes', where: 'file_id=?', whereArgs: [fileId]);
            // Explicitly assigned files keep their existing episode and ranges.
            if (links.isEmpty) {
              await tx.insert('media_file_episodes', {
                'file_id': fileId, 'episode_id': id, 'relation': 'source_catalog',
                'ordinal': 0, 'start_ms': null, 'end_ms': null,
              });
            }
          }
        }
      });

  Future<void> observeSourceArtwork(String id, String kind, String path) =>
      _transaction((tx) async {
        id = await canonicalFileId(tx, id);
        final rows = await tx.rawQuery(
            "SELECT o.* FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.entity_id=? AND b.source='source_catalog' AND b.status='accepted' LIMIT 1", [id]);
        if (rows.isEmpty) return;
        final object = rows.single;
        final uri = Uri.file(path).toString();
        final previous = await tx.rawQuery(
            "SELECT json_extract(fields,'\$.details.artworkUrls.$kind') AS value FROM media_snapshots WHERE object_id=? AND json_extract(fields,'\$.details.artworkUrls.$kind') IS NOT NULL ORDER BY fetched_at DESC LIMIT 1", [object['id']]);
        if (previous.firstOrNull?['value'] == uri) return;
        await _snapshot(tx, object['id'] as String, MetadataRecord(
            ref: ExternalRef(object['provider'] as String, object['object_type'] as String,
                object['external_id'] as String, scope: object['scope'] as String),
            title: '', kind: object['object_type'] as String, language: 'und',
            details: {'artworkUrls': {kind: uri}}, fetchedAt: DateTime.now().toUtc()));
      });
}
