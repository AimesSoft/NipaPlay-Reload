import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../capabilities/classic_action.dart';
import '../events/signals.dart';
import '../harness_redaction.dart';
import 'identity_store.dart';
import 'media_service.dart';

const _text = StringSchema(minLength: 1, maxLength: 4096);
const _output = ObjectSchema({}, additionalProperties: true);

/// Merging is an explicit graph rewrite, never an identity inference. The
/// preview, stale check, row changes and durable receipt use one SQLite view.
final class WorkMergeCapability implements Capability {
  WorkMergeCapability(MediaService service) {
    final merger = WorkMerger(service);
    actions = [
      ClassicAction(
          const ActionSpec(
              id: 'media.management.merge_work',
              title: '预览或合并重复作品',
              description:
                  'Merge sourceWorkId into targetWorkId on the owning device. '
                  'New requests without expectedPlan preview only; an already committed requestId always returns its durable receipt. Resubmit the same requestId, reason and mapping with expectedPlan to commit atomically. '
                  'mappings explicitly pair source release/episode IDs with target IDs of the same kind; unmapped children keep their IDs and move under the surviving hierarchy. '
                  'Never guesses from titles or episode numbers. Preview lists same-file/range suggestions, retained children and conflicts. '
                  'metadataPolicy defaults to reject conflicting attributes/overrides; prefer_target or prefer_source is an explicit choice, with both prior values retained in the undo journal. '
                  'Conflicting external identities, different ranges of one file, ambiguous duplicate danmaku settings and active danmaku jobs are refused. '
                  'Preserves files, file IDs, subtitle selections, file/range progress, source snapshots and audit; moves bindings, overrides and episode danmaku together. '
                  'Old entity IDs become aliases. Does not call Classic recognition, import history or write Classic projections. '
                  'Use source-device IDs through mesh.invoke; no cross-device transaction. Same-origin retries return the durable receipt, including after restart. Undo with media.management.undo_merge.',
              effect: Effect.write,
              input: ObjectSchema({
                'sourceWorkId': _text,
                'targetWorkId': _text,
                'mappings': ArraySchema(
                    ObjectSchema({
                      'sourceId': _text,
                      'targetId': _text,
                    }, required: [
                      'sourceId',
                      'targetId'
                    ]),
                    maxItems: 1000),
                'metadataPolicy': StringSchema(
                    values: ['reject', 'prefer_target', 'prefer_source']),
                'requestId': _text,
                'reason': _text,
                'expectedPlan': _text,
              }, required: [
                'sourceWorkId',
                'targetWorkId',
                'requestId',
                'reason'
              ]),
              output: _output),
          merger.merge),
      ClassicAction(
          const ActionSpec(
              id: 'media.management.undo_merge',
              title: '预览或撤回作品合并',
              description:
                  'New requests preview by default; pass expectedPlan to restore the exact pre-merge rows atomically. Already committed requestIds return the durable receipt. '
                  'Refuses if the affected hierarchy, bindings, aliases, edits, danmaku or file ranges changed after the merge. '
                  'Current file progress, subtitles and downloaded cache bodies are retained. New active danmaku work blocks undo. '
                  'mergeId, requestId and reason are required; same-origin retries recover the durable undo receipt. '
                  'The original merge and undo audit stay stored.',
              effect: Effect.write,
              input: ObjectSchema({
                'mergeId': _text,
                'requestId': _text,
                'reason': _text,
                'expectedPlan': _text,
              }, required: [
                'mergeId',
                'requestId',
                'reason'
              ]),
              output: _output),
          merger.undo),
    ];
  }
  @override
  late final List<Action> actions;
}

const _keys = <String, List<String>>{
  'media_entities': ['id'],
  'media_bindings': ['id'],
  'media_file_episodes': ['file_id', 'episode_id'],
  'media_overrides': ['entity_id', 'field'],
  'danmaku_bindings': ['id'],
  'media_entity_aliases': ['old_id'],
};

String _digest(Object? value) => stableMediaId('work-merge-state', [value]);
JsonMap _request(JsonMap input) => {...input}..remove('expectedPlan');
List<JsonMap> _rows(JsonMap snapshot, String table) => (snapshot[table] as List)
    .map((r) => Map<String, Object?>.from(r as Map))
    .toList();
String _where(List<String> columns) => columns.map((k) => '$k=?').join(' AND ');

final class WorkMerger {
  WorkMerger(this.service);
  final MediaService service;
  IdentityStore get store => service.store;

  Future<JsonMap> merge(JsonMap input, Invocation invocation) =>
      service.mutate(() async {
        final request = _request(input);
        final fingerprint = _digest(request);
        final id = stableMediaId(
            'work-merge', [invocation.origin, input['requestId']]);
        return BodySignals.transaction(store.database, (tx) async {
          final old = await tx
              .query('media_work_merges', where: 'id=?', whereArgs: [id]);
          if (old.isNotEmpty) {
            if (old.single['fingerprint'] != fingerprint) {
              throw const Failure(FailureCode.conflict,
                  'requestId was used for a different merge.');
            }
            return {
              ...decodeMediaJson(old.single['result']),
              'mergeState': old.single['state']
            };
          }
          final source = input['sourceWorkId'] as String,
              target = input['targetWorkId'] as String;
          final before = await _capture(tx, [source, target]);
          final planned = await _plan(tx, before, request);
          final plan = _digest([request, before, planned]);
          final conflicts = planned['conflicts'] as List;
          final preview = {
            'sourceWorkId': source,
            'targetWorkId': target,
            ...({...planned}..remove('after')),
            'diskFilesDeleted': false,
            'classicChanged': false,
            'progressPolicy':
                'Retain file/range observations; Mesh selects the newest observation. No position arithmetic or file replacement.',
            'undoAvailable': true,
          };
          if (input['expectedPlan'] == null) {
            return publicHarnessFacts({
              'preview': preview,
              'expectedPlan': plan,
              'canCommit': conflicts.isEmpty
            }) as JsonMap;
          }
          if (input['expectedPlan'] != plan || conflicts.isNotEmpty) {
            throw Failure(FailureCode.conflict,
                'Merge plan changed or has unresolved conflicts.',
                details: {'expectedPlan': plan, 'conflicts': conflicts});
          }
          final after = planned['after'] as JsonMap;
          await _replace(tx, before, after);
          final result = <String, Object?>{
            'committed': true,
            'mergeId': id,
            'sourceWorkId': source,
            'targetWorkId': target,
            'mapping': planned['mapping'],
            'retainedIds': planned['retainedIds'],
            'mergeState': 'committed',
            'undoAction': 'media.management.undo_merge',
          };
          final committed = await _capture(tx, [source, target]);
          await tx.insert('media_work_merges', {
            'id': id,
            'origin': invocation.origin,
            'request_id': input['requestId'],
            'fingerprint': fingerprint,
            'snapshot': jsonEncode({'before': before, 'after': committed}),
            'result': jsonEncode(result),
            'state': 'committed',
          });
          await _audit(
              tx, id, 'merge', request, invocation, planned['mapping']);
          _announce(target, id);
          return result;
        });
      });

  Future<JsonMap> undo(JsonMap input, Invocation invocation) =>
      service.mutate(() => BodySignals.transaction(store.database, (tx) async {
            final request = _request(input),
                fingerprint = _digest(_request(input));
            final key = stableMediaId(
                'undo-work-merge', [invocation.origin, input['requestId']]);
            final recovered = await store.operation(key, fingerprint, db: tx);
            if (recovered != null) return recovered;
            final records = await tx.query('media_work_merges',
                where: 'id=?', whereArgs: [input['mergeId']]);
            if (records.isEmpty) {
              throw const Failure(FailureCode.notFound, 'Unknown mergeId.');
            }
            final record = records.single,
                receipt = decodeMediaJson(record['result']);
            final saved = decodeMediaJson(record['snapshot']);
            final before = Map<String, Object?>.from(saved['before'] as Map);
            final after = Map<String, Object?>.from(saved['after'] as Map);
            final current =
                await _capture(tx, (before['roots'] as List).cast<String>());
            final busy =
                await _activeDanmaku(tx, _rows(current, 'danmaku_bindings'));
            final unchanged = _digest(current) == _digest(after);
            final plan = _digest([request, current, record['state'], busy]);
            final canUndo =
                record['state'] == 'committed' && unchanged && busy.isEmpty;
            if (input['expectedPlan'] == null) {
              return {
                'expectedPlan': plan,
                'canCommit': canUndo,
                'preview': {
                  'mergeId': record['id'],
                  'state': record['state'],
                  'unchanged': unchanged,
                  'activeDanmakuJobs': busy,
                  'progressChanged': false,
                  'diskFilesDeleted': false
                }
              };
            }
            if (!canUndo || input['expectedPlan'] != plan) {
              throw const Failure(FailureCode.conflict,
                  'Merge cannot be undone: its affected data changed, a danmaku job is active, or the preview is stale.');
            }
            await _replace(tx, current, before);
            await tx.update('media_work_merges', {'state': 'undone'},
                where: 'id=?', whereArgs: [record['id']]);
            final result = <String, Object?>{
              'committed': true,
              'mergeId': record['id'],
              'mergeState': 'undone'
            };
            await tx.insert('media_binding_operations', {
              'id': key,
              'fingerprint': fingerprint,
              'result': jsonEncode(result)
            });
            await _audit(tx, record['id'] as String, 'undo_merge', request,
                invocation, receipt['mapping']);
            _announce(
                receipt['targetWorkId'] as String, record['id'] as String);
            return result;
          }));

  void _announce(String target, String id) {
    BodySignals.changed('media.identity.changed', target,
        {'operation': 'work_merge', 'mergeId': id});
    BodySignals.changed(
        'media.assets.changed', target, {'kind': 'metadata', 'mergeId': id});
    BodySignals.changed(
        'danmaku.changed', target, {'operation': 'work_merge', 'mergeId': id});
  }

  Future<void> _audit(Transaction tx, String id, String event, JsonMap request,
          Invocation invocation, Object? mapping) =>
      tx.insert('media_evidence', {
        'id': newMediaId('merge-evidence'),
        'source': 'work_merge',
        'payload': jsonEncode({
          'event': event,
          'mergeId': id,
          'mapping': mapping,
          'request': request,
          'origin': invocation.origin,
          'invocationId': invocation.id
        }),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).then((_) {});

  Future<JsonMap> _capture(DatabaseExecutor db, List<String> roots) async {
    final entities = await db.rawQuery(
        'WITH RECURSIVE tree(id) AS ('
        'SELECT id FROM media_entities WHERE id IN (?,?) UNION '
        'SELECT e.id FROM media_entities e JOIN tree t ON e.parent_id=t.id) '
        'SELECT * FROM media_entities WHERE id IN (SELECT id FROM tree) ORDER BY id LIMIT 1001',
        roots);
    if (entities.length > 1000) {
      throw const Failure(FailureCode.invalidInput,
          'A merge is limited to 1000 hierarchy entities.');
    }
    final ids = entities.map((e) => e['id']).toList();
    final marks = List.filled(ids.length, '?').join(',');
    final snapshot = <String, Object?>{
      'roots': roots,
      'media_entities': entities
    };
    for (final (table, column) in [
      ('media_bindings', 'entity_id'),
      ('media_file_episodes', 'episode_id'),
      ('media_overrides', 'entity_id'),
      ('danmaku_bindings', 'entity_id'),
    ]) {
      snapshot[table] = await db.query(table,
          where: '$column IN ($marks)',
          whereArgs: ids,
          orderBy: _keys[table]!.join(','));
    }
    snapshot['media_entity_aliases'] = await db.query('media_entity_aliases',
        where: 'old_id IN ($marks) OR entity_id IN ($marks)',
        whereArgs: [...ids, ...ids],
        orderBy: 'old_id');
    // Edit history is immutable, but new edits invalidate a preview or undo.
    snapshot['edits'] = await db.query('media_metadata_edits',
        where: 'entity_id IN ($marks)', whereArgs: ids, orderBy: 'sequence');
    snapshot['objects'] = await db.rawQuery(
        'SELECT * FROM media_external_objects WHERE id IN '
        '(SELECT object_id FROM media_bindings WHERE entity_id IN ($marks)) ORDER BY id',
        ids);
    final encoded = jsonEncode(snapshot);
    if (utf8.encode(encoded).length > 4 * 1024 * 1024) {
      throw const Failure(FailureCode.invalidInput,
          'Affected merge state exceeds 4 MiB; use a smaller explicit operation.');
    }
    return snapshot;
  }

  Future<List<String>> _activeDanmaku(
      DatabaseExecutor db, List<JsonMap> bindings) async {
    final ids = bindings.map((b) => b['id']).toList();
    if (ids.isEmpty) return [];
    final marks = List.filled(ids.length, '?').join(',');
    final jobs = await db.rawQuery(
        'SELECT DISTINCT j.job_id,j.state FROM jobs j WHERE '
        "(j.type='danmaku.fetch' AND json_extract(j.snapshot,'\$.input.bindingId') IN ($marks)) OR "
        'j.job_id IN (SELECT cache_job_id FROM danmaku_bindings WHERE id IN ($marks) '
        'UNION SELECT job_id FROM danmaku_alignment_candidates WHERE binding_id IN ($marks))',
        [...ids, ...ids, ...ids]);
    return [
      for (final j in jobs)
        if (!['succeeded', 'failed', 'cancelled'].contains(j['state']))
          j['job_id'] as String
    ];
  }

  Future<JsonMap> _plan(
      DatabaseExecutor db, JsonMap before, JsonMap request) async {
    final source = request['sourceWorkId'] as String,
        target = request['targetWorkId'] as String;
    final entities = {
      for (final row in _rows(before, 'media_entities'))
        row['id'] as String: row
    };
    final aliases = _rows(before, 'media_entity_aliases');
    for (final id in [source, target]) {
      if (entities[id]?['kind'] != 'work' ||
          aliases.any((a) => a['old_id'] == id) ||
          decodeMediaJson(entities[id]?['attributes'])['removed'] == true) {
        throw const Failure(FailureCode.invalidInput,
            'Both works must be current source-device work IDs. Resolve aliases and Mesh projection IDs first.');
      }
    }
    if (source == target) {
      throw const Failure(
          FailureCode.invalidInput, 'Cannot merge a work into itself.');
    }
    String root(String id) {
      final visited = <String>{};
      while (entities[id]?['parent_id'] != null) {
        if (!visited.add(id)) {
          throw const Failure(FailureCode.conflict, 'Cyclic media hierarchy.');
        }
        id = entities[id]!['parent_id'] as String;
      }
      return id;
    }

    final mapping = <String, String>{source: target};
    for (final raw in request['mappings'] as List? ?? []) {
      final entry = raw as Map,
          from = entry['sourceId'] as String,
          to = entry['targetId'] as String;
      if (mapping.containsKey(from) ||
          entities[from] == null ||
          entities[to] == null ||
          !['release', 'episode'].contains(entities[from]!['kind']) ||
          entities[from]!['kind'] != entities[to]!['kind'] ||
          root(from) != source ||
          root(to) != target ||
          [from, to].any((id) =>
              aliases.any((a) => a['old_id'] == id) ||
              decodeMediaJson(entities[id]!['attributes'])['removed'] ==
                  true)) {
        throw const Failure(FailureCode.invalidInput,
            'Mappings must pair current source descendants with same-kind target descendants, once per source ID.');
      }
      mapping[from] = to;
    }
    final conflicts = <JsonMap>[], choices = <JsonMap>[];
    final after =
        Map<String, Object?>.from(jsonDecode(jsonEncode(before)) as Map);
    final nextEntities = {
      for (final e in _rows(after, 'media_entities')) e['id'] as String: e
    };
    final policy = request['metadataPolicy'] ?? 'reject';
    void conflict(String kind, JsonMap data) =>
        conflicts.add({'kind': kind, ...data});
    // An explicit release correspondence must agree with its episode pairs.
    // Omitting the release pair still allows intentional cross-release moves.
    for (final pair in mapping.entries) {
      final parent = entities[pair.key]!['parent_id'];
      final mappedParent = mapping[parent];
      if (mappedParent != null &&
          mappedParent != entities[pair.value]!['parent_id']) {
        conflict('parent_mapping', {
          'sourceId': pair.key,
          'targetId': pair.value,
          'expectedParentId': mappedParent,
          'actualParentId': entities[pair.value]!['parent_id'],
        });
      }
    }
    Object? choose(String section, String from, String to, String field,
        Object? a, Object? b) {
      if (_digest(a) == _digest(b)) return b;
      choices.add({
        'section': section,
        'sourceId': from,
        'targetId': to,
        'field': field,
        'source': a,
        'target': b,
        'resolution': policy
      });
      if (policy == 'reject') {
        conflict(
            'metadata', {'sourceId': from, 'targetId': to, 'field': field});
      }
      return policy == 'prefer_source' ? a : b;
    }

    for (final entry in mapping.entries) {
      final src = nextEntities[entry.key]!, dst = nextEntities[entry.value]!;
      final sa = decodeMediaJson(src['attributes']),
          ta = decodeMediaJson(dst['attributes']);
      for (final f in sa.entries) {
        if (const {'removed', 'mergedInto', 'localOnly', 'bindingRevision'}
            .contains(f.key)) {
          continue;
        }
        ta[f.key] = !ta.containsKey(f.key)
            ? f.value
            : choose('attributes', entry.key, entry.value, f.key, f.value,
                ta[f.key]);
      }
      dst['attributes'] = jsonEncode(ta);
      dst['revision'] = (entities[entry.value]!['revision'] as int) + 1;
      src['attributes'] =
          jsonEncode({...sa, 'removed': true, 'mergedInto': entry.value});
      src['revision'] = (src['revision'] as int) + 1;
    }
    final retained = <String>[];
    for (final e in nextEntities.values) {
      if (mapping.containsKey(e['id'])) continue;
      final parent = mapping[e['parent_id']];
      if (parent != null) {
        e['parent_id'] = parent;
        retained.add(e['id'] as String);
      }
    }
    after['media_entities'] = nextEntities.values.toList();
    final bindings = _rows(after, 'media_bindings');
    final objects = {for (final o in _rows(before, 'objects')) o['id']: o};
    for (final b in bindings) {
      if (mapping[b['entity_id']] case final String to) {
        b['entity_id'] = to;
        b['revision'] = (b['revision'] as int) + 1;
      }
    }
    final identities = <String, Object?>{};
    for (final b in bindings.where((b) => b['status'] == 'accepted')) {
      final o = objects[b['object_id']]!;
      final k = jsonEncode([b['entity_id'], o['provider']]);
      if (identities.containsKey(k) && identities[k] != b['object_id']) {
        conflict('external_identity', {
          'entityId': b['entity_id'],
          'provider': o['provider'],
          'objectIds': [identities[k], b['object_id']]
        });
      }
      identities[k] = b['object_id'];
    }
    after['media_bindings'] = bindings;
    final links = <String, JsonMap>{};
    for (final row in _rows(after, 'media_file_episodes')) {
      final original = row['episode_id'];
      row['episode_id'] = mapping[original] ?? original;
      final key = jsonEncode([row['file_id'], row['episode_id']]);
      final existing = links[key];
      if (existing != null) {
        if (existing['start_ms'] != row['start_ms'] ||
            existing['end_ms'] != row['end_ms'] ||
            existing['ordinal'] != row['ordinal']) {
          conflict('file_range', {
            'fileId': row['file_id'],
            'episodeId': row['episode_id'],
            'links': [existing, row]
          });
        }
        // Keep a local catalogue association if either one was explicit local
        // placement; later identity revocation must not erase it.
        if (row['relation'] == 'local_catalog') {
          existing['relation'] = 'local_catalog';
        }
      } else {
        links[key] = row;
      }
    }
    after['media_file_episodes'] = links.values.toList();
    final overrides = <String, JsonMap>{};
    final ordered = _rows(after, 'media_overrides')
      ..sort((a, b) => (mapping.containsKey(a['entity_id']) ? 1 : 0)
          .compareTo(mapping.containsKey(b['entity_id']) ? 1 : 0));
    for (final row in ordered) {
      final from = row['entity_id'] as String, to = mapping[from] ?? from;
      final key = jsonEncode([to, row['field']]);
      final old = overrides[key];
      if (old != null &&
          (old['value'] != row['value'] || old['mode'] != row['mode'])) {
        choose(
            'overrides',
            from,
            to,
            row['field'] as String,
            {'value': row['value'], 'mode': row['mode']},
            {'value': old['value'], 'mode': old['mode']});
        if (policy != 'prefer_source') continue;
      } else if (old != null) {
        continue;
      }
      overrides[key] = {...row, 'entity_id': to};
    }
    after['media_overrides'] = overrides.values.toList();
    final danmaku = _rows(after, 'danmaku_bindings');
    final activeJobs = await _activeDanmaku(db, danmaku);
    if (activeJobs.isNotEmpty) {
      conflict('active_danmaku_jobs', {'jobIds': activeJobs});
    }
    final pools = <String, JsonMap>{};
    for (final b in danmaku) {
      final from = b['entity_id'] as String, to = mapping[from] ?? from;
      if (mapping.containsKey(from) || mapping.containsValue(from)) {
        b['entity_id'] = to;
        b['entity_revision'] =
            b['entity_revision'] == entities[from]!['revision']
                ? nextEntities[to]!['revision']
                : -1;
        b['revision'] = (b['revision'] as int) + 1;
      }
      if (b['status'] != 'accepted' ||
          b['entity_revision'] != nextEntities[to]!['revision']) {
        continue;
      }
      final key = jsonEncode([to, b['object_id']]);
      if (pools[key] case final JsonMap other) {
        for (final field in [
          'video',
          'enabled',
          'deduplicate',
          'offset_ms',
          'alignment',
          'local_file'
        ]) {
          if (other[field] != b[field]) {
            conflict('danmaku_settings', {
              'bindingIds': [other['id'], b['id']],
              'field': field
            });
            break;
          }
        }
        // Identical pools retain both provenance records and cache references.
      } else {
        pools[key] = b;
      }
    }
    after['danmaku_bindings'] = danmaku;
    for (final a in aliases) {
      a['entity_id'] = mapping[a['entity_id']] ?? a['entity_id'];
    }
    after['media_entity_aliases'] = [
      ...aliases,
      for (final m in mapping.entries) {'old_id': m.key, 'entity_id': m.value}
    ];
    final suggested = <JsonMap>[];
    final originalLinks = _rows(before, 'media_file_episodes');
    List<String> segments(String id) => [
          for (final r in originalLinks.where((r) => r['episode_id'] == id))
            jsonEncode([r['file_id'], r['start_ms'], r['end_ms'], r['ordinal']])
        ]..sort();
    for (final e in entities.values.where((e) =>
        e['kind'] == 'episode' &&
        root(e['id'] as String) == source &&
        !mapping.containsKey(e['id']))) {
      final files = segments(e['id'] as String);
      if (files.isEmpty) continue;
      final matches = [
        for (final t in entities.values.where(
            (t) => t['kind'] == 'episode' && root(t['id'] as String) == target))
          if (_digest(segments(t['id'] as String)) == _digest(files)) t['id']
      ];
      if (matches.isNotEmpty) {
        suggested.add({
          'sourceId': e['id'],
          'targetIds': matches,
          'basis': 'identical_file_ranges'
        });
      }
    }
    for (final table in _keys.keys) {
      final rows = _rows(after, table)
        ..sort((a, b) => jsonEncode([for (final k in _keys[table]!) a[k]])
            .compareTo(jsonEncode([for (final k in _keys[table]!) b[k]])));
      after[table] = rows;
    }
    return {
      'mapping': mapping,
      'retainedIds': retained,
      'suggestedMappings': suggested,
      'entities': [
        for (final e in entities.values)
          {
            'id': e['id'],
            'kind': e['kind'],
            'parentId': e['parent_id'],
            'revision': e['revision'],
            'title': decodeMediaJson(e['attributes'])['title'],
            'resultId': mapping[e['id']] ?? e['id'],
            'resultParentId':
                nextEntities[mapping[e['id']] ?? e['id']]!['parent_id'],
          }
      ],
      'identities': [
        for (final b in _rows(before, 'media_bindings'))
          {
            'bindingId': b['id'],
            'entityId': b['entity_id'],
            'resultEntityId': mapping[b['entity_id']] ?? b['entity_id'],
            'status': b['status'],
            'provider': objects[b['object_id']]!['provider'],
            'objectType': objects[b['object_id']]!['object_type'],
            'externalId': objects[b['object_id']]!['external_id'],
            'scope': objects[b['object_id']]!['scope'],
          }
      ],
      'fileRanges': originalLinks,
      'metadataChoices': choices,
      'conflicts': conflicts,
      'counts': {
        for (final t in _keys.keys)
          t: {
            'before': (before[t] as List).length,
            'after': (after[t] as List).length
          }
      },
      'after': after
    };
  }

  /// Only changed rows are touched. History, files, subtitles, progress and
  /// downloaded pools live outside these rows and are never rewritten.
  Future<void> _replace(Transaction tx, JsonMap before, JsonMap after) async {
    for (final table in _keys.keys) {
      final keys = _keys[table]!;
      String key(JsonMap row) => jsonEncode([for (final k in keys) row[k]]);
      final old = {for (final r in _rows(before, table)) key(r): r};
      final next = {for (final r in _rows(after, table)) key(r): r};
      for (final entry in old.entries) {
        if (!next.containsKey(entry.key)) {
          await tx.delete(table,
              where: _where(keys),
              whereArgs: [for (final k in keys) entry.value[k]]);
        }
      }
      for (final entry in next.entries) {
        final prev = old[entry.key];
        if (prev == null) {
          await tx.insert(table, entry.value);
        } else if (_digest(prev) != _digest(entry.value)) {
          await tx.update(table, entry.value,
              where: _where(keys), whereArgs: [for (final k in keys) prev[k]]);
        }
      }
    }
  }
}
