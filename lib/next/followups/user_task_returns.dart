part of 'service.dart';

/// Tasks that wait for the person at NipaPlay, not for the machine: their
/// end is news to the conversation that asked, whichever way it ended.
const userTaskTypes = {
  'accounts.login',
  'media.sources.login',
  'disk_deletion',
  'setting_consent'
};

extension UserTaskReturns on Followups {
  /// What the conversation is told about [job]: the public task facts, and for
  /// a deletion which files are gone. Account names and secrets are not among
  /// the public fields and never enter the receipt it reads from.
  JsonMap userTaskFacts(Job job) {
    final data = publicTaskFacts(job.toJson());
    if (job.type == 'setting_consent') {
      return {
        ...data,
        'action': 'settings.set',
        'changed': job.state == JobState.succeeded,
        'keys': job.input['keys'],
      };
    }
    if (job.type != 'disk_deletion') return data;
    final result = job.receipt?.details['result'];
    final batch = result is Map && result['results'] is List;
    final items = result is Map
        ? [
            if (batch)
              ...(result['results'] as List).whereType<Map>()
            else
              result
          ]
        : const <Map>[];
    return {
      ...data,
      'action': job.input['action'],
      'deleted': job.state == JobState.succeeded,
      'deletedFiles': [
        for (final item in items)
          for (final file in (item['deletedFiles'] as List? ?? const []))
            if (file is Map) {'index': file['index'], 'path': file['path']}
      ],
      if (batch)
        'items': [
          for (final item in items)
            {
              if (item['jobId'] != null) 'jobId': item['jobId'],
              'status': item['status'] ?? 'succeeded'
            }
        ],
    };
  }

  /// The row's id is the task's, so asking for it is the check.
  Future<void> _collectUserTaskReturns(_Tasks tasks) async {
    final jobs = await tasks.ofTypes(userTaskTypes.toList(),
        (job) => job.state.isTerminal && job.input['returnTo'] != null);
    final existing = await _existing(
        [for (final job in jobs) 'followup-user-task-${job.jobId}']);
    for (final job in jobs) {
      final target = job.input['returnTo'] as Map?;
      if (target == null ||
          existing.contains('followup-user-task-${job.jobId}')) {
        continue;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final row = redactHarnessJson({
        'id': 'followup-user-task-${job.jobId}',
        'automatic': 'userTask',
        'state': 'ready',
        'title': '用户操作的结果：${job.title}',
        'instruction':
            '由此会话发起、需要用户本人完成的事有了结果：账号或媒体来源的登录，磁盘文件删除的确认，或会把密钥、流量送往别处的设置修改的确认。任务终态不等于成功，以状态与回执为准。下一步由你决定。',
        'condition': {'userTaskJobId': job.jobId},
        'deliverAfter': now,
        'repository': target['repository'],
        'threadId': target['threadId'],
        'origin': target['origin'],
        'invocationId': target['invocationId'],
        'createdAt': now,
        'updatedAt': now,
        'turnId': null,
        'turnStatus': null,
        'reason': null,
        'waitingFor': 'Waiting for an idle chat host.',
        if (target['deviceId'] != null) 'remoteDeviceId': target['deviceId'],
        if (target['returnTicket'] != null)
          'returnTicket': target['returnTicket'],
        'trigger': {
          'kind': 'task.facts',
          'jobId': job.jobId,
          'title': job.title,
          'facts': [
            {
              'event': 'task.terminal',
              'objectId': job.jobId,
              'occurredAt': job.updatedAt.toIso8601String(),
              'data': userTaskFacts(job)
            }
          ]
        }
      }) as JsonMap;
      await database.transaction((tx) async {
        await tx.insert('followups',
            {'id': row['id'], 'state': 'ready', 'snapshot': jsonEncode(row)});
        await _event(tx, row, 'registered', target['origin'] as String,
            target['invocationId'] as String);
      });
    }
  }
}
