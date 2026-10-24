import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart' show CredentialRef;
import 'package:nipaplay/security/secret_redactor.dart';

import '../repository_location.dart';
import '../capabilities/local_operation_titles.dart';
import 'activity_invocations.dart';
import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../settings/denylist.dart';
import '../settings/registry.dart';
import 'change_history.dart';
import 'query.dart';
import 'views.dart';

export 'activity_invocations.dart'
    show
        ActivityInvocations,
        activityRecordsInvocation,
        activityKeepsResult,
        nextJournal;

const _text = StringSchema(nullable: true);
const _facts = ObjectSchema({}, additionalProperties: true);
const activityFields = ObjectSchema({
  'id': StringSchema(description: 'Stable source-qualified event ID.'),
  'at': StringSchema(description: 'UTC ISO-8601 event time, not query time.'),
  'type': StringSchema(
      description: 'Domain.operation; filter with eq/in/contains.'),
  'title': StringSchema(
      description: 'Display-ready statement of the recorded fact.'),
  'actor': StringSchema(description: 'user, agent, hook, system or unknown.'),
  'origin': _text,
  'deviceId': _text,
  'originDeviceId': _text,
  'invocationId': _text,
  'entityId': _text,
  'entityIds': ArraySchema(StringSchema()),
  'jobId': _text,
  'subjectId': _text,
  'source':
      StringSchema(description: 'Original store, not a second event ledger.'),
  'facts': _facts,
});

String _actor(String? origin) => switch (origin) {
      null => 'unknown',
      'gui' => 'user',
      'application' || 'migration' || 'classic_history' => 'system',
      String() when origin.startsWith('hook:') => 'hook',
      _ => 'agent',
    };

typedef ActivityHostContext = (
  String repository,
  String journalPath,
  String ownerDeviceId,
  Map<String, CredentialRef> remembered,
  Map<String, (String, Schema)> settings,
);

typedef PackedActivityRows = (
  List<JsonMap> head,
  List<String> chunks,
  int total,
  List<String> warnings,
);

PackedActivityRows packActivityRows(
    List<JsonMap> events, List<String> warnings) {
  final head = events.take(20).toList();
  final chunks = <String>[];
  for (var start = 20; start < events.length; start += 64) {
    chunks.add(jsonEncode(
        events.sublist(start, (start + 64).clamp(20, events.length))));
  }
  return (head, chunks, events.length, warnings);
}

StateRows unpackActivityRows(PackedActivityRows packed) {
  final (head, chunks, total, warnings) = packed;
  return StateRows(_ChunkedJsonList(head, chunks, total),
      warnings: warnings, total: total);
}

final class _ChunkedJsonList extends ListBase<JsonMap> {
  _ChunkedJsonList(this._head, this._chunks, this.length)
      : _decoded = List<List<JsonMap>?>.filled(_chunks.length, null);
  final List<JsonMap> _head;
  final List<String> _chunks;
  final List<List<JsonMap>?> _decoded;
  @override
  final int length;
  @override
  set length(int _) =>
      throw UnsupportedError('Cannot modify unmodifiable activity rows.');
  @override
  JsonMap operator [](int index) {
    RangeError.checkValidIndex(index, this);
    if (index < _head.length) return _head[index];
    final rel = index - _head.length;
    final chunkIndex = rel ~/ 64;
    final decoded = _decoded[chunkIndex] ??=
        (jsonDecode(_chunks[chunkIndex]) as List).cast<JsonMap>();
    return decoded[rel % 64];
  }

  @override
  void operator []=(int index, JsonMap value) =>
      throw UnsupportedError('Cannot modify unmodifiable activity rows.');
}

Future<(String?, List<String>)> _gitLogForRepository(String repository) async {
  if (await Directory('$repository/.git').exists() ||
      await File('$repository/.git').exists()) {
    final result = await Process.run('git', [
      '-C',
      repository,
      'log',
      '--format=%H%x00%cI%x00%an%x00%aI%x00%s',
      '-z'
    ]);
    return (
      result.stdout as String,
      [
        if (result.exitCode != 0)
          'activity.harness_git_log_failed:${result.exitCode}'
      ]
    );
  }
  return (null, ['activity.harness_no_repository']);
}

Future<_ActivitySources> _readActivitySources(
    Database db, ActivityHostContext context,
    {bool includeGit = true}) async {
  final (repository, journalPath, ownerDeviceId, remembered, shown) = context;
  Future<List<JsonMap>> rows(String table, {String? orderBy}) async => [
        for (final row in await db.query(table, orderBy: orderBy))
          Map<String, Object?>.of(row)
      ];
  Future<List<JsonMap>> raw(String sql) async =>
      [for (final row in await db.rawQuery(sql)) Map<String, Object?>.of(row)];
  return _ActivitySources(
    journalPresent: await File(journalPath).exists(),
    invocations: await rows('activity_invocations'),
    invocationOrigins: await rows('invocation_origins'),
    ownerDeviceId: ownerDeviceId,
    remembered: remembered,
    settings: shown,
    discoveries: await rows('harness_discoveries'),
    jobs: await rows('jobs'),
    followupEvents: await rows('followup_events', orderBy: 'sequence'),
    origins: await rows('task_origins'),
    locations: await rows('media_locations'),
    jobEvents: await rows('job_events', orderBy: 'at,job_id,revision'),
    evidence: await raw('''SELECT e.*,b.entity_id,b.object_id,b.relation,
      o.provider,o.external_id,o.object_type FROM media_evidence e
      JOIN media_bindings b ON b.id=e.binding_id JOIN media_external_objects o ON o.id=b.object_id'''),
    danmaku: await raw(
        '''SELECT e.*,b.entity_id,b.video FROM danmaku_binding_events e
      JOIN danmaku_bindings b ON b.id=e.binding_id'''),
    snapshots:
        await raw('''SELECT s.*,o.provider,o.external_id FROM media_snapshots s
      JOIN media_external_objects o ON o.id=s.object_id'''),
    bindings: await raw('SELECT object_id,entity_id FROM media_bindings'),
    edits: await rows('media_metadata_edits'),
    settingsChanges: await rows('settings_changes'),
    bodyChanges: await rows('body_changes'),
    repository: repository,
    git: includeGit ? await _gitLogForRepository(repository) : (null, const []),
  );
}

Future<(List<JsonMap>, List<String>)> readActivityFromDatabase(
    Database db, ActivityHostContext context) async {
  final sources = await _readActivitySources(db, context, includeGit: true);
  return _compose(sources);
}

final class ActivityView {
  ActivityView(
      this.media, this.settings, this.invocations, this.location, this.history);
  final MediaService media;
  final SettingsRegistry settings;
  final ActivityInvocations invocations;
  final RepositoryLocation location;
  final ChangeHistory history;
  Future<PackedActivityRows?> Function(ActivityHostContext)? workerRead;
  Future<StateRows?> Function(ActivityHostContext, int offset, int limit)?
      workerReadPage;

  StateView get view => StateView(
      name: 'activity',
      background: true,
      description:
          'Newest-first body changes derived from domain histories, invocation journal and active harness git log. '
          'entityId matches the primary entity; entityIds lists all related entities. Unknown legacy provenance stays unknown. '
          'Cursors paginate live observations; concurrent inserts may shift pages. No credentials or comment bodies.',
      fields: activityFields,
      readAll: read,
      readPage: readPage,
      read: (offset, limit) async => (await readPage(offset, limit)).rows);

  Future<ActivityHostContext> prepare() async {
    await history.drain();
    await invocations.settled();
    await location.ready;
    // The worker already reads settings_changes from its own connection.
    // Send the fixed registry metadata, not the changing database keys.
    final shown = <String, (String, Schema)>{
      for (final s in settings.entries)
        if (!isSettingDenied(s.key) && s.visible()) s.key: (s.title, s.schema)
    };
    return (
      location.path,
      invocations.journal.path,
      media.store.ownerDeviceId,
      SecretRedactor.remembered(),
      shown,
    );
  }

  /// When the library worker is running, SQL reads, git log and event
  /// composition run on its persistent connection; otherwise composition and
  /// git log run on a background isolate.
  Future<StateRows> read() async {
    final context = await prepare();
    if (workerRead case final delegate?) {
      if (await delegate(context) case final packed?) {
        return unpackActivityRows(packed);
      }
    }
    final sources = await _readActivitySources(media.store.database, context,
        includeGit: false);
    final packed = await _composeOffMain(sources);
    return unpackActivityRows(packed);
  }

  /// A query page crosses the isolate without its complete history. The
  /// worker still composes from its own database view; the UI only decodes the
  /// requested window.
  Future<StateRows> readPage(int offset, int limit) async {
    final context = await prepare();
    if (workerReadPage case final delegate?) {
      if (await delegate(context, offset, limit) case final page?) {
        return page;
      }
    }
    final all = await read();
    return StateRows(all.rows.skip(offset).take(limit).toList(),
        warnings: all.warnings, total: all.total ?? all.rows.length);
  }
}

/// What the activity view is composed from, read on the main isolate.
final class _ActivitySources {
  _ActivitySources(
      {required this.journalPresent,
      required this.invocations,
      required this.invocationOrigins,
      required this.ownerDeviceId,
      required this.remembered,
      required this.settings,
      required this.discoveries,
      required this.jobs,
      required this.followupEvents,
      required this.origins,
      required this.locations,
      required this.jobEvents,
      required this.evidence,
      required this.danmaku,
      required this.snapshots,
      required this.bindings,
      required this.edits,
      required this.settingsChanges,
      required this.bodyChanges,
      required this.repository,
      required this.git});
  final bool journalPresent;
  final String ownerDeviceId, repository;
  final Map<String, CredentialRef> remembered;

  /// Title and schema of each setting shown in activity, by key.
  final Map<String, (String, Schema)> settings;
  final List<JsonMap> invocations,
      invocationOrigins,
      discoveries,
      jobs,
      followupEvents,
      origins,
      locations,
      jobEvents,
      evidence,
      danmaku,
      snapshots,
      bindings,
      edits,
      settingsChanges,
      bodyChanges;

  /// git log output (null without a repository) and its warnings.
  final (String?, List<String>) git;
}

Future<PackedActivityRows> _composeOffMain(_ActivitySources sources) =>
    Isolate.run(() async {
      final git = await _gitLogForRepository(sources.repository);
      final withGit = _ActivitySources(
        journalPresent: sources.journalPresent,
        invocations: sources.invocations,
        invocationOrigins: sources.invocationOrigins,
        ownerDeviceId: sources.ownerDeviceId,
        remembered: sources.remembered,
        settings: sources.settings,
        discoveries: sources.discoveries,
        jobs: sources.jobs,
        followupEvents: sources.followupEvents,
        origins: sources.origins,
        locations: sources.locations,
        jobEvents: sources.jobEvents,
        evidence: sources.evidence,
        danmaku: sources.danmaku,
        snapshots: sources.snapshots,
        bindings: sources.bindings,
        edits: sources.edits,
        settingsChanges: sources.settingsChanges,
        bodyChanges: sources.bodyChanges,
        repository: sources.repository,
        git: git,
      );
      final (events, warnings) = _compose(withGit);
      return packActivityRows(events, warnings);
    });

(List<JsonMap>, List<String>) _compose(_ActivitySources sources) {
  for (final MapEntry(key: value, value: ref) in sources.remembered.entries) {
    SecretRedactor.remember(ref, value);
  }
  final invocations = <String, JsonMap>{
    for (final row in sources.invocations)
      row['invocation_id'] as String: activityInvocationRecord(row)
  };
  final invocationOrigins = <String, String>{
    for (final row in sources.invocationOrigins)
      row['invocation_id'] as String: row['origin'] as String
  };
  final warnings = <String>[];
  if (!sources.journalPresent) warnings.add('activity.journal_absent');
  final events = <JsonMap>[];
  void add(String id, String at, String type, String title, String source,
      JsonMap facts,
      {String? origin,
      String? actor,
      String? invocationId,
      String? entityId,
      List<String> entityIds = const [],
      String? jobId,
      String? subjectId,
      String? deviceId}) {
    origin ??= invocations[invocationId]?['origin'] as String? ??
        invocationOrigins[invocationId];
    final ids = {...entityIds, if (entityId != null) entityId}.toList();
    events.add({
      'id': id,
      'at': DateTime.parse(at).toUtc().toIso8601String(),
      'type': type,
      'title': title,
      'actor': actor == 'system' || actor == 'hook' || origin == 'git'
          ? actor
          : origin != null
              ? _actor(origin)
              : actor == 'automatic'
                  ? 'system'
                  : actor ?? 'unknown',
      'origin': origin,
      'deviceId': deviceId ?? sources.ownerDeviceId,
      'originDeviceId':
          origin?.startsWith('mesh:') == true ? origin!.substring(5) : null,
      'invocationId': invocationId,
      'entityId': entityId ?? ids.firstOrNull,
      'entityIds': ids,
      'jobId': jobId,
      'subjectId': subjectId,
      'source': source,
      'facts': publicValue(SecretRedactor.json(facts), _facts),
    });
  }

  for (final row in sources.discoveries) {
    add(
        'discovery:${row['sequence']}',
        row['at'] as String,
        'harness.discovery',
        row['title'] as String,
        'harness_discoveries',
        {
          'source': row['source'],
          'repository': row['repository'],
          'facts': decodeMediaJson(row['facts'])
        },
        origin: row['origin'] as String,
        invocationId: row['invocation_id'] as String);
  }
  final jobs = {
    for (final row in sources.jobs)
      row['job_id'] as String: decodeMediaJson(row['snapshot'])
  };
  for (final row in sources.followupEvents) {
    final facts = decodeMediaJson(row['facts']);
    add(
        'followup:${row['sequence']}',
        row['at'] as String,
        row['type'] as String,
        '${facts['title']} · ${facts['state']}',
        'followup_events',
        facts,
        origin: row['origin'] as String,
        actor: row['type'] == 'followup.registered' ||
                row['type'] == 'followup.cancelled'
            ? null
            : 'system',
        invocationId: row['invocation_id'] as String?,
        jobId: (facts['condition'] as Map)['jobId'] as String?,
        subjectId: row['followup_id'] as String);
  }
  final origins = {
    for (final row in sources.origins) row['job_id'] as String: row
  };
  final locationFiles = <String, List<String>>{};
  for (final row in sources.locations) {
    (locationFiles[row['locator'] as String] ??= [])
        .add(row['file_id'] as String);
  }
  final receiptSeen = <String, Object?>{};
  for (final row in sources.jobEvents) {
    final jobId = row['job_id'] as String;
    final snapshot = decodeMediaJson(row['snapshot']);
    final input = jobs[jobId]?['input'] as Map? ?? {};
    final details = (snapshot['receipt'] as Map?)?['details'] as Map? ?? {};
    final entities = <String>{
      for (final key in ['entityId', 'fileId'])
        if (input[key] is String) input[key] as String,
      for (final id in input['fileIds'] as List? ?? []) id as String,
      for (final key in ['entityId', 'fileId'])
        if (details[key] is String) details[key] as String,
      for (final id in details['fileIds'] as List? ?? []) id as String,
      if (snapshot['type'] == 'harness.hook')
        ...?locationFiles[input['objectId']],
    }.toList();
    final origin = origins[jobId];
    final eventOrigin =
        row['origin'] as String? ?? origin?['origin'] as String?;
    final eventInvocation =
        row['invocation_id'] as String? ?? origin?['invocation_id'] as String?;
    final isHook = snapshot['type'] == 'harness.hook';
    final facts = publicTaskFacts(snapshot);
    facts['initiatedBy'] = {
      'actor': _actor(origin?['origin'] as String?),
      'origin': origin?['origin'],
      'invocationId': origin?['invocation_id']
    };
    if (isHook) {
      facts['hook'] = {'event': input['event'], 'objectId': input['objectId']};
    }
    final prefix = isHook ? 'hook' : 'task';
    add(
        'job:$jobId:${row['revision']}',
        row['at'] as String,
        '$prefix.${row['revision'] == 0 ? 'created' : 'changed'}',
        '${snapshot['title']} · ${snapshot['state']} · ${snapshot['phase']}',
        'job_events',
        {'kind': row['kind'], ...facts},
        jobId: jobId,
        entityIds: entities,
        origin: eventOrigin,
        invocationId: eventInvocation,
        actor: isHook
            ? 'hook'
            : ['submitted', 'cancel_requested', 'paused', 'resumed']
                    .contains(row['kind'])
                ? _actor(eventOrigin)
                : 'system',
        deviceId: snapshot['ownerDeviceId'] as String?);
    final receipt = snapshot['receipt'];
    if (receipt != null &&
        jsonEncode(receipt) != jsonEncode(receiptSeen[jobId])) {
      add(
          'receipt:$jobId:${row['revision']}',
          row['at'] as String,
          '$prefix.receipt',
          '${snapshot['title']} · 回执 ${((receipt as Map)['verification'])}',
          'job_events',
          {'state': snapshot['state'], 'receipt': facts['receipt']},
          jobId: jobId,
          entityIds: entities,
          origin: eventOrigin,
          invocationId: eventInvocation,
          actor: isHook ? 'hook' : 'system');
    }
    receiptSeen[jobId] = receipt;
  }
  for (final row in sources.evidence) {
    final payload = decodeMediaJson(row['payload']);
    final operation = switch (payload['event']) {
      'unbind' => 'revoked',
      'restore' => 'restored',
      _ => 'bound',
    };
    add(
        'identity:${row['id']}',
        row['created_at'] as String,
        'identity.$operation',
        '${row['entity_id']} · ${row['provider']}:${row['external_id']} · $operation',
        'media_evidence',
        {
          'bindingId': row['binding_id'],
          'objectId': row['object_id'],
          'provider': row['provider'],
          'externalId': row['external_id'],
          'objectType': row['object_type'],
          'relation': row['relation'],
          'operation': operation,
          'reason': payload['reason'],
        },
        entityId: row['entity_id'] as String,
        origin: payload['origin'] as String?,
        actor: payload['boundBy'] as String?,
        invocationId: payload['invocationId'] as String?,
        jobId: row['job_id'] as String?,
        subjectId: row['binding_id'] as String?);
  }
  for (final row in sources.danmaku) {
    final payload = decodeMediaJson(row['payload']);
    final video = payload['video'] as Map? ?? decodeMediaJson(row['video']);
    final operation = payload['operation'] ??
        (payload['status'] == 'revoked' ? 'revoked' : 'changed');
    add(
        'danmaku:${row['id']}',
        row['created_at'] as String,
        'danmaku.$operation',
        '${video['sourceId']} · ${video['title'] ?? video['videoId']} · $operation',
        'danmaku_binding_events',
        {
          'bindingId': row['binding_id'],
          'revision': row['revision'],
          'video': video,
          ...payload,
        },
        entityId: row['entity_id'] as String,
        invocationId: row['invocation_id'] as String?,
        origin: payload['origin'] as String?,
        subjectId: row['binding_id'] as String?);
  }
  final bound = <Object?, List<JsonMap>>{};
  for (final row in sources.bindings) {
    (bound[row['object_id']] ??= []).add(row);
  }
  for (final row in sources.snapshots) {
    final payload = decodeMediaJson(row['fields']);
    final bindings = bound[row['object_id']] ?? const <JsonMap>[];
    final relatedJob = jobs.values
        .where((j) => (j['checkpoint'] as Map?)?['snapshotId'] == row['id'])
        .firstOrNull;
    final origin = origins[relatedJob?['jobId']];
    add(
        'snapshot:${row['id']}',
        payload['receivedAt'] as String? ?? row['fetched_at'] as String,
        'metadata.snapshot',
        '${row['provider']}:${row['external_id']} · 元数据快照',
        'media_snapshots',
        {
          'snapshotId': row['id'],
          'objectId': row['object_id'],
          'provider': row['provider'],
          'externalId': row['external_id'],
          'language': row['language'],
          'metadata': payload['metadata'] ??
              {
                for (final key in [
                  'title',
                  'originalTitle',
                  'overview',
                  'imageUrl',
                  'year'
                ])
                  key: payload[key],
              },
          'fetchedAt': payload['fetchedAt'],
          'receivedAt': payload['receivedAt'],
        },
        entityIds: [for (final b in bindings) b['entity_id'] as String],
        origin: payload['origin'] as String? ?? origin?['origin'] as String?,
        invocationId: payload['invocationId'] as String? ??
            origin?['invocation_id'] as String?,
        jobId: relatedJob?['jobId'] as String?,
        subjectId: row['id'] as String?);
  }
  for (final row in sources.edits) {
    add(
        'edit:${row['sequence']}',
        row['changed_at'] as String,
        'metadata.edited',
        '${row['entity_id']} · ${row['field']} · ${row['mode']}',
        'media_metadata_edits',
        {
          'field': row['field'],
          'mode': row['mode'],
          'value': jsonDecode(row['value'] as String)
        },
        entityId: row['entity_id'] as String,
        origin: row['origin'] as String?,
        invocationId: row['invocation_id'] as String?);
  }
  for (final row in sources.settingsChanges) {
    final key = row['key'] as String;
    final shown = sources.settings[key];
    if (shown == null) continue;
    final (title, schema) = shown;
    add(
        'setting:${row['sequence']}',
        row['changed_at'] as String,
        'settings.changed',
        '$title · 设置修改',
        'settings_changes',
        {
          'key': key,
          'revision': row['revision'],
          'reason': row['reason'],
          'before':
              publicValue(jsonDecode(row['previous_value'] as String), schema),
          'after': publicValue(jsonDecode(row['value'] as String), schema),
        },
        origin: row['origin'] as String?,
        invocationId: row['invocation_id'] as String?,
        jobId: (row['origin'] as String?)?.startsWith('hook:') == true &&
                jobs.containsKey((row['origin'] as String).substring(5))
            ? (row['origin'] as String).substring(5)
            : null,
        subjectId: key);
  }
  for (final row in sources.bodyChanges) {
    final facts = decodeMediaJson(row['facts']);
    final after = facts['after'];
    final before = facts['before'];
    final recordedType = row['type'] as String;
    final type = recordedType == 'account.changed' &&
            before is Map &&
            after is Map &&
            before['loggedIn'] != after['loggedIn']
        ? after['loggedIn'] == true
            ? 'account.logged_in'
            : 'account.logged_out'
        : recordedType;
    add(
        'body:${row['sequence']}',
        row['at'] as String,
        type,
        recordedType.startsWith('ui.shelf_') ||
                recordedType.startsWith('ui.library_') ||
                recordedType.startsWith('db.') ||
                recordedType == 'history.watched'
            ? facts['title'] as String
            : '${(after is Map ? after['name'] : null) ?? (before is Map ? before['name'] : null) ?? row['subject_id']} · $type',
        'body_changes',
        facts,
        origin: row['origin'] as String?,
        actor: row['actor'] as String?,
        entityId: facts['fileId'] as String?,
        entityIds: (facts['entityIds'] as List?)?.cast<String>() ?? const [],
        invocationId: row['invocation_id'] as String?,
        subjectId: row['subject_id'] as String?);
  }
  // Attempts remain distinct from committed domain changes, including previews.
  for (final invocation in invocations.values) {
    final action = invocation['actionId'] as String;
    final result = invocation['result'] as Map?;
    final interfaceTitle = action == 'ui.capture'
        ? (result?['path'] != null ? '界面已截取' : '界面暂时无法截取')
        : action == 'ui.close'
            ? (result?['closed'] == true ? '窗口已关闭' : '没有可关闭的窗口')
            : action.startsWith('ui.')
                ? (result?['opened'] != true
                    ? '暂时无法打开界面'
                    : (result?['actual'] as Map?)?['kind'] ==
                            'native_picker_request'
                        ? '已发起视频选择'
                        : (result?['actual'] as Map?)?['kind'] ==
                                'folder_request'
                            ? '已请求打开文件夹'
                            : (result?['actual'] as Map?)?['kind'] ==
                                    'webpage_request'
                                ? '已请求打开网页'
                                : '界面已打开')
                : action == 'discover.refresh'
                    ? (result?['refreshed'] == true ? '首页已刷新' : '首页暂时无法刷新')
                    : action == 'discover.recommendations' &&
                            (invocation['input'] as Map?)?['next'] == true
                        ? (result?['changed'] == true ? '推荐已更新' : '推荐暂时无法更新')
                        : invocation['status'] == 'completed'
                            ? '发现内容已载入'
                            : '发现内容暂时无法载入';
    final conflict = invocation['failureCode'] == 'conflict';
    if (!activityRecordsInvocation(action, conflict: conflict)) continue;
    final input = invocation['input'] as Map? ?? {};
    final finished = DateTime.parse(invocation['startedAt'] as String)
        .add(Duration(milliseconds: invocation['elapsedMs'] as int));
    add(
        'invocation:${invocation['invocationId']}',
        finished.toIso8601String(),
        conflict
            ? action.startsWith('media.identity.')
                ? 'identity.conflict'
                : 'invocation.conflict'
            : 'invocation.result',
        localOperationTitles.containsKey(action)
            ? '${localOperationTitles[action]}${invocation['status'] == 'failed' ? '失败' : invocation['status'] == 'completed' ? '完成' : '等待选择'}'
            : action.startsWith('ui.') || action.startsWith('discover.')
                ? interfaceTitle
                : '$action · ${invocation['status']}${conflict ? ' · 冲突' : ''}',
        'journal',
        {
          'action': action,
          'status': invocation['status'],
          'failureCode': invocation['failureCode'],
          'provider': input['provider'],
          'sourceId': input['sourceId'],
          if (conflict)
            'attempts': [
              for (final e in input['entries'] as List? ?? [])
                {
                  for (final key in [
                    'entityId',
                    'kind',
                    'ref',
                    'workRef',
                    'releaseRef',
                    'episodeRefs',
                    'reason'
                  ])
                    if ((e as Map).containsKey(key)) key: e[key],
                }
            ],
          'result': invocation['result'],
        },
        origin: invocation['origin'] as String?,
        invocationId: invocation['invocationId'] as String?,
        subjectId: input['sourceId'] as String? ?? input['provider'] as String?,
        entityId: input['entityId'] as String?,
        entityIds: [
          for (final e in input['entries'] as List? ?? [])
            if ((e as Map)['entityId'] is String) e['entityId'] as String
        ]);
  }
  final (log, gitWarnings) = sources.git;
  warnings.addAll(gitWarnings);
  if (log != null) {
    final parts = log.split('\x00');
    for (var index = 0; index + 4 < parts.length; index += 5) {
      add(
          'git:${parts[index]}',
          parts[index + 1],
          'harness.commit',
          parts[index + 4],
          'git log',
          {
            'hash': parts[index],
            'author': parts[index + 2],
            'authoredAt': parts[index + 3],
            'repository': sources.repository,
            'subject': parts[index + 4]
          },
          actor: parts[index + 2],
          origin: 'git',
          subjectId: parts[index]);
    }
  }
  events.sort((a, b) {
    final at = (b['at'] as String).compareTo(a['at'] as String);
    return at != 0 ? at : (b['id'] as String).compareTo(a['id'] as String);
  });
  return (events, warnings);
}
