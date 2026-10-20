part of 'service.dart';

extension ProgramReturns on Followups {
  Future<void> _collectProgramReturns() async {
    final rows = await _rows();
    for (final job in await engine.list(type: 'program')) {
      final target = job.input['returnTo'] as Map?;
      if (!job.state.isTerminal ||
          target == null ||
          rows.any((row) =>
              row['automatic'] == 'program' &&
              (row['condition'] as Map)['programJobId'] == job.jobId)) {
        continue;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final row = redactHarnessJson({
        'id': 'followup-program-${job.jobId}',
        'automatic': 'program',
        'state': 'ready',
        'title': '程序回执：${job.title}',
        'instruction': '此会话发起的程序已经结束。以下是执行设备的退出码、耗时和输出末尾。',
        'condition': {'programJobId': job.jobId},
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
          'kind': 'program.facts',
          'jobId': job.jobId,
          'title': job.title,
          'facts': [
            {
              'event': 'task.terminal',
              'objectId': job.jobId,
              'occurredAt': job.updatedAt.toIso8601String(),
              'data': publicTaskFacts(job.toJson())
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

bool _taskReturn(JsonMap row) => const {
      'download',
      'meshDownload',
      'program',
      'meshProgram',
      'userTask',
      'meshUserTask'
    }.contains(row['automatic']);
