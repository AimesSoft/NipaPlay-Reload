import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';

import '../repository_location.dart';
import '../capabilities/local_operation_titles.dart';
import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../settings/denylist.dart';
import '../settings/registry.dart';
import 'change_history.dart';
import 'query.dart';
import 'views.dart';

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

final class ActivityView {
  const ActivityView(
      this.media, this.settings, this.journal, this.location, this.history);
  final MediaService media;
  final SettingsRegistry settings;
  final File journal;
  final RepositoryLocation location;
  final ChangeHistory history;

  StateView get view => StateView(
      name: 'activity',
      description:
          'Newest-first body changes derived from domain histories, invocation journal and active harness git log. '
          'entityId matches the primary entity; entityIds lists all related entities. Unknown legacy provenance stays unknown. '
          'Cursors paginate live observations; concurrent inserts may shift pages. No credentials or comment bodies.',
      fields: activityFields,
      readAll: read,
      read: (offset, limit) async =>
          (await read()).rows.skip(offset).take(limit).toList());

  Future<StateRows> read() async {
    await history.drain();
    final db = media.store.database;
    final invocations = <String, JsonMap>{};
    final warnings = <String>[];
    if (await journal.exists()) {
      for (final line in await journal.readAsLines()) {
        if (line.isEmpty) continue;
        final record = decodeMediaJson(line);
        if (record['invocationId'] case final String id) invocations[id] = record;
      }
    } else {
      warnings.add('activity.journal_absent');
    }
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
      origin ??= invocations[invocationId]?['origin'] as String?;
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
        'deviceId': deviceId ?? media.store.ownerDeviceId,
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

    for (final row in await db.query('harness_discoveries')) {
      add('discovery:${row['sequence']}', row['at'] as String,
          'harness.discovery', row['title'] as String, 'harness_discoveries',
          {'source': row['source'], 'repository': row['repository'],
            'facts': decodeMediaJson(row['facts'])},
          origin: row['origin'] as String,
          invocationId: row['invocation_id'] as String);
    }
    final jobs = {
      for (final row in await db.query('jobs'))
        row['job_id'] as String: decodeMediaJson(row['snapshot'])
    };
    for (final row in await db.query('followup_events', orderBy: 'sequence')) {
      final facts = decodeMediaJson(row['facts']);
      add('followup:${row['sequence']}', row['at'] as String,
          row['type'] as String, '${facts['title']} · ${facts['state']}',
          'followup_events', facts,
          origin: row['origin'] as String,
          actor: row['type'] == 'followup.registered' || row['type'] == 'followup.cancelled'
              ? null : 'system',
          invocationId: row['invocation_id'] as String?,
          jobId: (facts['condition'] as Map)['jobId'] as String?,
          subjectId: row['followup_id'] as String);
    }
    final origins = {
      for (final row in await db.query('task_origins'))
        row['job_id'] as String: row
    };
    final locationFiles = <String, List<String>>{};
    for (final row in await db.query('media_locations')) {
      (locationFiles[row['locator'] as String] ??= [])
          .add(row['file_id'] as String);
    }
    final receiptSeen = <String, Object?>{};
    for (final row
        in await db.query('job_events', orderBy: 'at,job_id,revision')) {
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
      final eventInvocation = row['invocation_id'] as String? ??
          origin?['invocation_id'] as String?;
      final isHook = snapshot['type'] == 'harness.hook';
      final facts = publicTaskFacts(snapshot);
      facts['initiatedBy'] = {
        'actor': _actor(origin?['origin'] as String?),
        'origin': origin?['origin'],
        'invocationId': origin?['invocation_id']
      };
      if (isHook) {
        facts['hook'] = {
          'event': input['event'],
          'objectId': input['objectId']
        };
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
    for (final row
        in await db.rawQuery('''SELECT e.*,b.entity_id,b.object_id,b.relation,
        o.provider,o.external_id,o.object_type FROM media_evidence e
        JOIN media_bindings b ON b.id=e.binding_id JOIN media_external_objects o ON o.id=b.object_id''')) {
      final payload = decodeMediaJson(row['payload']);
      final operation = payload['event'] == 'unbind' ? 'revoked' : 'bound';
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
    for (final row in await db.rawQuery(
        '''SELECT e.*,b.entity_id,b.video FROM danmaku_binding_events e
        JOIN danmaku_bindings b ON b.id=e.binding_id''')) {
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
    for (final row in await db
        .rawQuery('''SELECT s.*,o.provider,o.external_id FROM media_snapshots s
        JOIN media_external_objects o ON o.id=s.object_id''')) {
      final payload = decodeMediaJson(row['fields']);
      final bindings = await db.query('media_bindings',
          columns: ['entity_id'],
          where: 'object_id=?',
          whereArgs: [row['object_id']]);
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
    for (final row in await db.query('media_metadata_edits')) {
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
    for (final row in await db.query('settings_changes')) {
      final entry = settings.entries
          .where((s) =>
              s.key == row['key'] && s.visible() && !isSettingDenied(s.key))
          .firstOrNull;
      if (entry == null) continue;
      add(
          'setting:${row['sequence']}',
          row['changed_at'] as String,
          'settings.changed',
          '${entry.title} · 设置修改',
          'settings_changes',
          {
            'key': entry.key,
            'revision': row['revision'],
            'reason': row['reason'],
            'before': publicValue(
                jsonDecode(row['previous_value'] as String), entry.schema),
            'after':
                publicValue(jsonDecode(row['value'] as String), entry.schema),
          },
          origin: row['origin'] as String?,
          invocationId: row['invocation_id'] as String?,
          jobId: (row['origin'] as String?)?.startsWith('hook:') == true &&
                  jobs.containsKey((row['origin'] as String).substring(5))
              ? (row['origin'] as String).substring(5)
              : null,
          subjectId: entry.key);
    }
    for (final row in await db.query('body_changes')) {
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
          recordedType.startsWith('ui.shelf_') || recordedType.startsWith('ui.library_') || recordedType == 'history.watched' ? facts['title'] as String :
          '${(after is Map ? after['name'] : null) ?? (before is Map ? before['name'] : null) ?? row['subject_id']} · $type',
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
              ? (result?['opened'] != true ? '暂时无法打开界面'
                  : (result?['actual'] as Map?)?['kind'] == 'native_picker_request' ? '已发起视频选择'
                  : (result?['actual'] as Map?)?['kind'] == 'folder_request' ? '已请求打开文件夹'
                  : (result?['actual'] as Map?)?['kind'] == 'webpage_request' ? '已请求打开网页'
                  : '界面已打开')
              : action == 'discover.refresh'
                  ? (result?['refreshed'] == true ? '首页已刷新' : '首页暂时无法刷新')
                  : action == 'discover.recommendations' && (invocation['input'] as Map?)?['next'] == true
                      ? (result?['changed'] == true ? '推荐已更新' : '推荐暂时无法更新')
                      : invocation['status'] == 'completed' ? '发现内容已载入' : '发现内容暂时无法载入';
      final conflict = invocation['failureCode'] == 'conflict';
      if (!conflict &&
          !action.startsWith('media.sources.') &&
          !action.startsWith('ui.') &&
          !action.startsWith('discover.') &&
          !action.startsWith('accounts.') &&
          !localOperationTitles.containsKey(action)) {
        continue;
      }
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
          subjectId:
              input['sourceId'] as String? ?? input['provider'] as String?,
          entityId: input['entityId'] as String?,
          entityIds: [
            for (final e in input['entries'] as List? ?? [])
              if ((e as Map)['entityId'] is String) e['entityId'] as String
          ]);
    }
    await location.ready;
    if (await Directory('${location.path}/.git').exists() ||
        await File('${location.path}/.git').exists()) {
      final result = await Process.run('git', [
        '-C',
        location.path,
        'log',
        '--format=%H%x00%cI%x00%an%x00%aI%x00%s',
        '-z'
      ]);
      if (result.exitCode != 0) {
        warnings.add('activity.harness_git_log_failed:${result.exitCode}');
      }
      final parts = (result.stdout as String).split('\x00');
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
              'repository': location.path,
              'subject': parts[index + 4]
            },
            actor: parts[index + 2],
            origin: 'git',
            subjectId: parts[index]);
      }
    } else {
      warnings.add('activity.harness_no_repository');
    }
    events.sort((a, b) {
      final at = (b['at'] as String).compareTo(a['at'] as String);
      return at != 0 ? at : (b['id'] as String).compareTo(a['id'] as String);
    });
    return StateRows(events, warnings: warnings);
  }
}
