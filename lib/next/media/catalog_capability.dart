import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../capabilities/classic_action.dart';
import 'identity_store.dart';
import 'media_service.dart';

const _text = StringSchema(minLength: 1);
const _entry = ObjectSchema({
  'entityId': _text,
  'kind': StringSchema(values: ['work', 'release', 'episode']),
  'parentId': _text,
  'title': _text,
  'number': StringSchema(),
  'season': IntegerSchema(),
  'fileIds': ArraySchema(_text),
  'expectedRevision': IntegerSchema(minimum: 0),
}, required: [
  'entityId',
  'kind',
  'title'
]);

final class CatalogCapability implements Capability {
  CatalogCapability(MediaService media) {
    final store = media.store;
    actions = [
      ClassicAction(
          const ActionSpec(
              id: 'media.entities.put_batch',
              title: '建立或修改本地目录',
              description:
                  'Atomically create/update local-only work → release → episode entities without external IDs. Caller assigns stable entityIds; parents must exist or precede children in entries. Updates require expectedRevision. fileIds on episodes replace local file associations. Changes to existing associations require preview:true first, then the returned expectedPlan. Files and watch history are retained. requestId deduplicates the entire batch.',
              effect: Effect.write,
              input: ObjectSchema({
                'entries': ArraySchema(_entry),
                'requestId': _text,
                'reason': _text,
                'preview': BooleanSchema(),
                'expectedPlan': _text,
              }, required: [
                'entries',
                'requestId',
                'reason'
              ]),
              output: ObjectSchema({}, additionalProperties: true)),
          (input, invocation) => media.mutate(() async =>
              _put(store, input, invocation, await media.classic.history()))),
      ClassicAction(
          const ActionSpec(
              id: 'media.entities.remove_batch',
              title: '解除本地目录关联',
              description:
                  'Preview (default) or remove local-only catalog associations. Recursively includes children. Retains entity tombstones, files, watch progress and provenance; never deletes disk files or external identities. Apply with preview:false and expectedPlan from preview. Returns an undoId usable with media.entities.restore. requestId is idempotent.',
              effect: Effect.write,
              input: ObjectSchema({
                'entityIds': ArraySchema(_text),
                'requestId': _text,
                'reason': _text,
                'preview': BooleanSchema(),
                'expectedPlan': _text,
              }, required: [
                'entityIds',
                'requestId',
                'reason'
              ]),
              output: ObjectSchema({}, additionalProperties: true)),
          (input, invocation) => media.mutate(() async => _remove(
              store, input, invocation, await media.classic.history()))),
      ClassicAction(
          const ActionSpec(
              id: 'media.entities.restore',
              title: '撤回目录移除',
              description:
                  'Restore the exact catalog rows and associations retained by remove_batch. Refuses if any affected entity or file association changed after removal; preserves current watch progress.',
              effect: Effect.write,
              input: ObjectSchema({'undoId': _text}, required: ['undoId']),
              output: ObjectSchema({}, additionalProperties: true)),
          (input, invocation) =>
              media.mutate(() => _restore(store, input, invocation))),
      ClassicAction(
          const ActionSpec(
              id: 'media.metadata.override_batch',
              title: '批量编辑文字',
              description:
                  'Atomic batch of text edits. Same lifetimes and shared work/release semantics as override. Host retains actor, origin and previous edits. clear removes active edits, never their audit history.',
              effect: Effect.write,
              input: ObjectSchema({
                'entries': ArraySchema(ObjectSchema({
                  'entityId': _text,
                  'field': StringSchema(values: [
                    'title',
                    'originalTitle',
                    'overview',
                    'imageUrl'
                  ]),
                  'value': StringSchema(nullable: true),
                  'language': _text,
                  'mode': StringSchema(
                      values: ['persistent', 'correction', 'clear']),
                }, required: [
                  'entityId',
                  'field',
                  'value'
                ]))
              }, required: [
                'entries'
              ]),
              output: ObjectSchema({}, additionalProperties: true)),
          (input, invocation) async {
        final entries = (input['entries'] as List).cast<JsonMap>();
        _batch(entries);
        final expanded = <JsonMap>[];
        for (final e in entries) {
          expanded.add(e);
          if (e['field'] == 'title' || e['field'] == 'overview') {
            expanded.add({
              ...e,
              'field': '${e['field']}Language',
              'value': e['language']
            });
          }
        }
        await store.overrideFields(expanded, invocation);
        return {'atomic': true, 'entries': entries};
      }),
    ];
  }
  @override
  late final List<Action> actions;
}

Future<List<JsonMap>> _impact(
    IdentityStore store, List<String> ids, List<JsonMap> history) async {
  final result = <JsonMap>[];
  for (final id in ids) {
    final row = await store.entity(id);
    if (row['id'] != id) {
      throw const Failure(FailureCode.conflict, 'This catalog ID was merged; use its surviving ID or undo the merge first.');
    }
    final attrs = row['attributes'] as JsonMap;
    if (attrs['localOnly'] != true) {
      throw const Failure(FailureCode.conflict,
          'This operation requires local-only catalog entities.');
    }
    final links = await store.database
        .query('media_file_episodes', where: 'episode_id=?', whereArgs: [id]);
    final files = <JsonMap>[];
    for (final link in links) {
      final locations = await store.database.query('media_locations',
          where: 'file_id=?', whereArgs: [link['file_id']]);
      files.add({
        'link': link,
        'associations': await store.database.query('media_file_episodes',
            where: 'file_id=?',
            whereArgs: [link['file_id']],
            orderBy: 'episode_id'),
        'locations': locations,
        'progress': [
          for (final location in locations)
            {
              'locationId': location['id'],
              'observed':
                  history.any((h) => h['filePath'] == location['locator']),
              'source': 'classic_watch_history',
              for (final key in [
                'lastPosition',
                'watchProgress',
                'duration',
                'lastWatchTime'
              ])
                key: history
                    .where((h) => h['filePath'] == location['locator'])
                    .map((h) => h[key])
                    .firstOrNull,
            }
        ]
      });
    }
    result.add({
      'entity': row,
      'files': files,
      'sources': await store.database
          .query('media_metadata_edits', where: 'entity_id=?', whereArgs: [id])
    });
  }
  return result;
}

String _impactPlan(List<JsonMap> impact) => stableMediaId('plan', [
      for (final item in impact)
        {
          ...item,
          'files': [
            for (final file in (item['files'] as List).cast<JsonMap>())
              {
                for (final e in file.entries)
                  if (e.key != 'progress') e.key: e.value
              }
          ]
        }
    ]);

Future<JsonMap> _operation(
    IdentityStore store,
    String action,
    JsonMap input,
    Invocation invocation,
    Future<JsonMap> Function(Transaction tx, String operationId) run) async {
  final id = stableMediaId(action, [invocation.origin, input['requestId']]);
  final fingerprint = stableMediaId('input', input);
  return store.database.transaction((tx) async {
    final old = await tx
        .query('media_binding_operations', where: 'id=?', whereArgs: [id]);
    if (old.isNotEmpty) {
      if (old.single['fingerprint'] != fingerprint) {
        throw const Failure(FailureCode.conflict,
            'requestId already used with different input.');
      }
      return decodeMediaJson(old.single['result']);
    }
    final result = await run(tx, id);
    await tx.insert('media_binding_operations',
        {'id': id, 'fingerprint': fingerprint, 'result': jsonEncode(result)});
    await tx.insert('body_changes', {
      'at': DateTime.now().toUtc().toIso8601String(),
      'type': action,
      'subject_id': id,
      'actor': invocation.origin == 'gui' ? 'user' : 'agent',
      'origin': invocation.origin,
      'invocation_id': invocation.id,
      'facts': jsonEncode({'reason': input['reason'], ...result})
    });
    return result;
  });
}

Future<JsonMap> _put(IdentityStore store, JsonMap input, Invocation invocation,
    List<JsonMap> history) async {
  final saved =
      await _saved(store, 'media.entities.put_batch', input, invocation);
  if (saved != null) return saved;
  final entries = (input['entries'] as List).cast<JsonMap>();
  _batch(entries);
  final existing = <String>[];
  for (final e in entries) {
    if ((await store.database
            .query('media_entities', where: 'id=?', whereArgs: [e['entityId']]))
        .isNotEmpty) {
      existing.add(e['entityId'] as String);
    }
  }
  final impact = await _impact(store, existing, history);
  final plan = _impactPlan(impact);
  if (input['preview'] == true) {
    return {'preview': impact, 'expectedPlan': plan, 'entries': entries};
  }
  if (existing.isNotEmpty && input['expectedPlan'] != plan) {
    throw const Failure(FailureCode.conflict,
        'Preview existing entities before changing them; expectedPlan is stale or missing.');
  }
  return _operation(store, 'media.entities.put_batch', input, invocation,
      (tx, op) async {
    final result = <JsonMap>[];
    final seen = <String>{};
    for (final e in entries) {
      final id = e['entityId'] as String, kind = e['kind'] as String;
      if ((await tx.query('media_entity_aliases', where: 'old_id=?', whereArgs: [id])).isNotEmpty) {
        throw const Failure(FailureCode.conflict, 'This entity was merged; edit its surviving ID or undo the merge first.');
      }
      if (!seen.add(id)) {
        throw const Failure(
            FailureCode.invalidInput, 'Duplicate entityId in batch.');
      }
      final old =
          await tx.query('media_entities', where: 'id=?', whereArgs: [id]);
      final parent = e['parentId'];
      if (kind == 'work' && parent != null ||
          kind != 'work' && parent == null) {
        throw const Failure(FailureCode.invalidInput,
            'work has no parent; release/episode require parentId.');
      }
      if (parent != null) {
        final rows = await tx
            .query('media_entities', where: 'id=?', whereArgs: [parent]);
        if (rows.isEmpty ||
            rows.single['kind'] != (kind == 'release' ? 'work' : 'release') ||
            decodeMediaJson(rows.single['attributes'])['removed'] == true) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid or removed catalog parent.');
        }
      }
      final attrs = old.isEmpty
          ? <String, Object?>{}
          : decodeMediaJson(old.single['attributes']);
      if (old.isNotEmpty &&
          (old.single['kind'] != kind ||
              attrs['localOnly'] != true ||
              e['expectedRevision'] != old.single['revision'])) {
        throw const Failure(
            FailureCode.conflict, 'Catalog kind/revision changed.');
      }
      if (e['fileIds'] != null && kind != 'episode') {
        throw const Failure(
            FailureCode.invalidInput, 'Only episodes accept fileIds.');
      }
      final revision = old.isEmpty ? 0 : (old.single['revision'] as int) + 1;
      final row = {
        'id': id,
        'kind': kind,
        'parent_id': parent,
        'revision': revision,
        'attributes': jsonEncode({
          ...attrs,
          'localOnly': true,
          'removed': false,
          'title': e['title'],
          if (e.containsKey('number')) 'number': e['number'],
          if (e.containsKey('season')) 'season': e['season']
        })
      };
      if (old.isEmpty) {
        await tx.insert('media_entities', row);
      } else {
        await tx.update('media_entities', row, where: 'id=?', whereArgs: [id]);
      }
      if (e['fileIds'] != null) {
        await tx.delete('media_file_episodes',
            where: 'episode_id=?', whereArgs: [id]);
        var ordinal = 0;
        final seenFiles = <String>{};
        for (final fileId in (e['fileIds'] as List).cast<String>()) {
          if (!seenFiles.add(fileId)) {
            throw const Failure(FailureCode.invalidInput,
                'Duplicate fileId in episode associations.');
          }
          final file = await tx.query('media_entities',
              where: 'id=? AND kind=?', whereArgs: [fileId, 'file']);
          if (file.isEmpty) {
            throw const Failure(
                FailureCode.notFound, 'Unknown indexed fileId.');
          }
          await tx.insert('media_file_episodes', {
            'file_id': fileId,
            'episode_id': id,
            'relation': 'local_catalog',
            'ordinal': ordinal++
          });
        }
      }
      result
          .add({'entityId': id, 'created': old.isEmpty, 'revision': revision});
    }
    return {'atomic': true, 'entries': result, 'before': impact};
  });
}

Future<JsonMap> _remove(IdentityStore store, JsonMap input,
    Invocation invocation, List<JsonMap> history) async {
  final saved =
      await _saved(store, 'media.entities.remove_batch', input, invocation);
  if (saved != null) return saved;
  _batch(input['entityIds'] as List);
  final ids = (input['entityIds'] as List).cast<String>().toSet();
  final queue = ids.toList();
  for (var i = 0; i < queue.length; i++) {
    for (final child in await store.database
        .query('media_entities', where: 'parent_id=? AND id NOT IN (SELECT old_id FROM media_entity_aliases)', whereArgs: [queue[i]])) {
      if (ids.add(child['id'] as String)) queue.add(child['id'] as String);
    }
  }
  final impact = await _impact(store, queue, history);
  final plan = _impactPlan(impact);
  if (input['preview'] != false) {
    return {
      'preview': impact,
      'expectedPlan': plan,
      'filesRetained': true,
      'progressRetained': true
    };
  }
  if (input['expectedPlan'] != plan) {
    throw const Failure(
        FailureCode.conflict, 'Removal preview is missing or stale.');
  }
  return _operation(store, 'media.entities.remove_batch', input, invocation,
      (tx, op) async {
    for (final item in impact) {
      final row = item['entity'] as JsonMap;
      await tx.update(
          'media_entities',
          {
            'revision': (row['revision'] as int) + 1,
            'attributes':
                jsonEncode({...row['attributes'] as JsonMap, 'removed': true})
          },
          where: 'id=?',
          whereArgs: [row['id']]);
      await tx.delete('media_file_episodes',
          where: 'episode_id=?', whereArgs: [row['id']]);
    }
    return {
      'undoId': op,
      'before': impact,
      'filesRetained': true,
      'progressRetained': true
    };
  });
}

void _batch(List entries) {
  if (entries.isEmpty || entries.length > 100) {
    throw const Failure(
        FailureCode.invalidInput, 'Batch must contain 1 to 100 entries.');
  }
}

Future<JsonMap?> _saved(IdentityStore store, String action, JsonMap input,
    Invocation invocation) async {
  final id = stableMediaId(action, [invocation.origin, input['requestId']]);
  final rows = await store.database
      .query('media_binding_operations', where: 'id=?', whereArgs: [id]);
  if (rows.isEmpty) return null;
  if (rows.single['fingerprint'] != stableMediaId('input', input)) {
    throw const Failure(
        FailureCode.conflict, 'requestId already used with different input.');
  }
  return decodeMediaJson(rows.single['result']);
}

Future<JsonMap> _restore(
    IdentityStore store, JsonMap input, Invocation invocation) async {
  final id = input['undoId'] as String;
  final rows = await store.database
      .query('media_binding_operations', where: 'id=?', whereArgs: [id]);
  if (rows.isEmpty || !id.startsWith('media.entities.remove_batch-')) {
    throw const Failure(FailureCode.notFound, 'Unknown catalog removal.');
  }
  final receipt = decodeMediaJson(rows.single['result']);
  final before = (receipt['before'] as List).cast<JsonMap>();
  return _operation(
      store, 'media.entities.restore', {'requestId': id}, invocation,
      (tx, op) async {
    final affected = {
      for (final item in before) (item['entity'] as JsonMap)['id']
    };
    final checked = <String>{};
    for (final item in before) {
      for (final file in (item['files'] as List).cast<JsonMap>()) {
        final fileId = (file['link'] as JsonMap)['file_id'] as String;
        if (!checked.add(fileId)) continue;
        final remaining = (file['associations'] as List)
            .cast<JsonMap>()
            .where((link) => !affected.contains(link['episode_id']))
            .toList();
        final current = await tx.query('media_file_episodes',
            where: 'file_id=?', whereArgs: [fileId], orderBy: 'episode_id');
        if (stableMediaId('links', current) !=
            stableMediaId('links', remaining)) {
          throw const Failure(
              FailureCode.conflict, 'File associations changed after removal.');
        }
      }
    }
    for (final item in before) {
      final row = item['entity'] as JsonMap;
      final current = (await tx
              .query('media_entities', where: 'id=?', whereArgs: [row['id']]))
          .single;
      if (current['revision'] != (row['revision'] as int) + 1 ||
          decodeMediaJson(current['attributes'])['removed'] != true) {
        throw const Failure(
            FailureCode.conflict, 'Catalog changed after removal.');
      }
      await tx.update(
          'media_entities',
          {
            'attributes': jsonEncode(row['attributes']),
            'revision': (current['revision'] as int) + 1
          },
          where: 'id=?',
          whereArgs: [row['id']]);
      for (final file in (item['files'] as List).cast<JsonMap>()) {
        final link = file['link'] as JsonMap;
        await tx.insert('media_file_episodes', link);
      }
    }
    return {
      'restored': true,
      'entityIds': [
        for (final item in before) (item['entity'] as JsonMap)['id']
      ]
    };
  });
}
