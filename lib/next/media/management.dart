import 'package:nipa_harness/nipa_harness.dart';
import 'identity_store.dart';
import 'media_service.dart';
import 'work_merge.dart';
import 'file_identity_merge.dart';
import '../harness_redaction.dart';

/// The user-facing association protocol; low-level identity primitives retain
/// their existing idempotent contracts for explicit and persisted operations.
final class MediaManagementCapability implements Capability {
  MediaManagementCapability(this.service, Iterable<Action> primitives)
      : actions = [
          ...WorkMergeCapability(service).actions,
          for (final operation in ['bind', 'unbind'])
            _Manage(
                service,
                operation,
                primitives
                    .singleWhere(
                        (a) => a.spec.id == 'media.identity.${operation}_batch')
                    .spec
                    .input)
        ];
  final MediaService service;
  @override
  final List<Action> actions;
}

Future<JsonMap> associationImpact(MediaService service, JsonMap input) async {
  final store = service.store, db = store.database;
  final ids = <String>{};
  for (final e in (input['entries'] as List).cast<JsonMap>()) {
    for (final key in ['entityId', 'workId', 'releaseId']) {
      if (e[key] case final String id)
        ids.add((await store.entity(id))['id'] as String);
    }
    for (final id in (e['localEpisodeIds'] as List? ?? []).cast<String>()) {
      ids.add(await canonicalFileId(db, id));
    }
    if (e['path'] case final String path) {
      ids.addAll((await db.query('media_locations',
              columns: ['file_id'], where: 'locator=?', whereArgs: [path]))
          .map((r) => r['file_id'] as String));
    }
    for (final ref in [
      e['ref'],
      e['workRef'],
      e['releaseRef'],
      ...(e['episodeRefs'] as List? ?? [])
    ].whereType<Map>()) {
      final rows = await db.rawQuery(
          'SELECT b.entity_id FROM media_bindings b '
          'JOIN media_external_objects o ON o.id=b.object_id WHERE b.status=? '
          'AND o.provider=? AND o.object_type=? AND o.external_id=? AND o.scope=?',
          [
            'accepted',
            ref['provider'],
            ref['objectType'],
            ref['externalId'],
            ref['scope'] ?? ''
          ]);
      ids.addAll(rows.map((r) => r['entity_id'] as String));
    }
  }
  final initial = ids.toList()..sort();
  for (final id in initial) {
    ids.addAll((await db.rawQuery(
            'WITH RECURSIVE children AS ('
            'SELECT id FROM media_entities WHERE id=? UNION ALL SELECT e.id FROM media_entities e '
            'JOIN children c ON e.parent_id=c.id) SELECT id FROM children',
            [id]))
        .map((r) => r['id'] as String));
  }
  final related = ids.toList();
  for (final id in related) {
    ids.addAll((await db.query('media_file_episodes',
            where: 'episode_id=?', whereArgs: [id]))
        .map((r) => r['file_id'] as String));
    ids.addAll((await db
            .query('media_file_episodes', where: 'file_id=?', whereArgs: [id]))
        .map((r) => r['episode_id'] as String));
  }
  final history = await service.classic.history();
  final impact = <JsonMap>[];
  final sorted = ids.toList()..sort();
  for (final id in sorted) {
    final entity = await store.entity(id);
    final locations = await store.locations(id);
    impact.add({
      'entity': entity,
      'associations': await db.query('media_file_episodes',
          where: 'file_id=? OR episode_id=?',
          whereArgs: [id, id],
          orderBy: 'file_id,episode_id'),
      'sources': await db.rawQuery(
          'SELECT b.*,o.provider,o.object_type,o.external_id,o.scope AS object_scope '
          'FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id '
          'WHERE b.entity_id=? ORDER BY b.id',
          [id]),
      'locations': locations,
      'progress': [
        for (final location in locations)
          {
            for (final key in [
              'lastPosition',
              'duration',
              'watchProgress',
              'lastWatchTime'
            ])
              key: history
                  .where((h) => h['filePath'] == location['locator'])
                  .firstOrNull?[key]
          }
      ],
    });
  }
  return {
    'entities': impact,
    'diskFilesDeleted': false,
    'progressChanged': false
  };
}

String associationPlan(JsonMap input, JsonMap impact) =>
    stableMediaId('association-plan', [
      {...input}..remove('expectedPlan'),
      for (final entity in (impact['entities'] as List).cast<JsonMap>())
        {...entity}..remove('progress'),
    ]);

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Manage extends Action<_Json, _Json> {
  const _Manage(this.service, this.operation, this.original);
  final MediaService service;
  final String operation;
  final ObjectSchema original;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'media.management.${operation}_batch',
      title: operation == 'bind' ? '预览或修改作品匹配' : '预览或解除作品匹配',
      description:
          'Same entries/requestId as media.identity.${operation}_batch, supports multiple works. '
          'Without expectedPlan returns affected entities/episodes, locations, progress and identity sources, '
          'without changing associations. Resubmit with expectedPlan to apply; stale associations are rejected '
          'inside the media writer. Never deletes files or changes progress, no NeedsDecision. '
          'This changes explicit identity associations, not a full entity merge: it does not move metadata edits, danmaku, subtitles or progress between entities. '
          'Writes use existing identity audit and deliver the committed identity to Classic without importing Classic matches; withdrawn identities can be rebuilt with bind_batch. '
          'For another device invoke this action through mesh.invoke using that device\'s original entity IDs. '
          'Local-only catalogue removal/restoration uses media.entities.remove_batch/restore.',
      effect: Effect.write,
      input: ObjectSchema({
        ...original.properties,
        'expectedPlan': const StringSchema(minLength: 1)
      }, required: original.required),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final request = {...input.value}..remove('expectedPlan');
    if (input.value['expectedPlan'] == null) {
      final impact =
          await service.mutate(() => associationImpact(service, request));
      return Completed(_Json(publicHarnessFacts({
        'preview': impact,
        'expectedPlan': associationPlan(request, impact)
      }) as JsonMap));
    }
    return Completed(_Json(operation == 'bind'
        ? await service.bindBatch(request, invocation,
            expectedPlan: input.value['expectedPlan'] as String)
        : await service.unbindBatch(request, invocation,
            expectedPlan: input.value['expectedPlan'] as String)));
  }
}
