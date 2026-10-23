part of 'service.dart';

extension DownloadReturns on Followups {
  /// Resolve once, while the invocation still has its originating conversation.
  Future<JsonMap?> downloadReturnTarget(Invocation invocation) async {
    final origin = invocation.origin;
    if (origin.startsWith('mesh:')) {
      final target = Zone.current[#meshReturnTarget] as JsonMap?;
      return target == null ? null : Map<String, Object?>.from(target);
    }
    String? thread;
    String? repository;
    if (origin.startsWith('harness_cli:chat:')) {
      thread = _host?.threadForOrigin(origin);
      repository = _host?.repository.path;
    } else if (origin.startsWith('harness_cli:helper:') ||
        origin.startsWith('codex_native:')) {
      final helper = await _helperFor(origin);
      thread = helper?.input['parentThreadId'] as String?;
      repository = helper?.input['repository'] as String?;
    }
    if (thread == null || repository == null) return null;
    return {
      'threadId': thread,
      'repository': repository,
      'origin': origin,
      'invocationId': invocation.id
    };
  }

  /// The helper an invocation [origin] comes from: by its task id, or the
  /// latest one running in that native thread.
  Future<Job?> _helperFor(String origin) async {
    String? id;
    if (origin.startsWith('harness_cli:helper:')) {
      id = origin.substring('harness_cli:helper:'.length);
    } else {
      id = (await database.rawQuery(
              "SELECT job_id FROM jobs WHERE type = 'agent.helper' AND "
              "json_extract(snapshot, '\$.input.threadId') = ? "
              'ORDER BY created_at DESC, job_id DESC LIMIT 1',
              [origin.substring('codex_native:'.length)]))
          .firstOrNull?['job_id'] as String?;
    }
    if (id == null) return null;
    try {
      final job = await engine.get(id);
      return job.type == 'agent.helper' ? job : null;
    } on Failure catch (error) {
      if (error.code == FailureCode.notFound) return null;
      rethrow;
    }
  }

  bool _manualCovers(JsonMap row, JsonMap fact, JsonMap target) {
    if (row['automatic'] != null && row['automatic'] != 'subscription' ||
        row['state'] == 'cancelled' ||
        row['state'] == 'execution_failed' ||
        row['threadId'] != target['threadId'] ||
        row['repository'] != target['repository']) {
      return false;
    }
    final condition = row['condition'] as Map;
    if (fact['event'] == 'task.terminal' &&
        condition['jobId'] == fact['objectId']) {
      return true;
    }
    final event = fact['event'] == 'task.terminal'
        ? (fact['data'] as Map)['state'] == 'succeeded' &&
                (fact['data'] as Map)['type'] == 'download'
            ? 'download.completed'
            : null
        : fact['event'];
    if (event == null ||
        condition['event'] != event ||
        condition['objectId'] != null &&
            condition['objectId'] != fact['objectId'] &&
            // One download's next stall may be awaited by its job id.
            !(event == 'download.stalled' &&
                condition['objectId'] == (fact['data'] as Map)['jobId']) ||
        DateTime.parse(row['createdAt'] as String)
            .isAfter(DateTime.parse(fact['occurredAt'] as String))) {
      return false;
    }
    // A broad one-shot subscription covers only the occurrence it actually takes.
    final trigger = row['trigger'] as Map?;
    if (trigger != null) return trigger['objectId'] == fact['objectId'];
    return row['state'] == 'waiting' && condition['objectId'] != null;
  }

  Future<void> _collectDownloadReturns(_Tasks tasks) async {
    final jobs = await tasks.ofTypes(
        const ['download'], (job) => job.input['returnTo'] != null);
    final slice = _Slice();
    for (final chunk in _chunks(jobs, 200)) {
      // What these could report, and which of it is reported or published.
      final objects = <String>[], stalls = <String>[];
      for (final job in chunk) {
        for (final file in (job.checkpoint['completedFiles'] as List? ?? [])
            .cast<JsonMap>()) {
          if (file['objectId'] case final String id) objects.add(id);
        }
        if (!job.state.isTerminal) {
          for (final stall
              in (job.checkpoint['stalls'] as List? ?? []).cast<Map>()) {
            stalls.add(HarnessHooks.stallObjectId(job.jobId, stall['index']));
          }
        }
        objects.add('terminal:${job.jobId}');
      }
      final covered = await _reported('download', [...objects, ...stalls]);
      // A stall is delivered after its public event is recorded, so a
      // registered followup waiting for it has already been triggered and
      // owns it.
      final published = {
        for (final part in _chunks(stalls))
          for (final row in await database.rawQuery(
              'SELECT DISTINCT object_id FROM followup_hook_events '
              "WHERE event = 'download.stalled' AND object_id IN (${_marks(part.length)})",
              part))
            row['object_id'] as String
      };
      for (final job in chunk) {
        if (slice.due) await slice.breathe();
        await _returnDownload(job, covered, published);
      }
    }
  }

  /// Adds what [job] has newly to say to its conversation's download
  /// return, opening one when none is waiting. [covered] grows by it.
  Future<void> _returnDownload(
      Job job, Set<String> covered, Set<String> published) async {
    final target = job.input['returnTo'] as Map?;
    if (target == null) return;
    final facts = <JsonMap>[
      for (final file in (job.checkpoint['completedFiles'] as List? ?? [])
          .cast<JsonMap>())
        if (file['isVideo'] == true &&
            file['imported'] == true &&
            file['verification'] == 'verified' &&
            !covered.contains(file['objectId']))
          {
            'event': 'download.file_completed',
            'objectId': file['objectId'],
            'occurredAt': file['completedAt'],
            'data': {
              'jobId': file['jobId'],
              'infoHash': job.input['infoHash'],
              'title': job.title,
              'file': {
                ...file,
                'playable': file['local'] == true && file['complete'] == true
              }
            }
          },
      // A stall that already passed, or a download that ended, has
      // nothing left to say about it.
      if (!job.state.isTerminal)
        for (final stall
            in (job.checkpoint['stalls'] as List? ?? []).cast<Map>())
          if (stall['resumedAt'] == null &&
              published.contains(
                  HarnessHooks.stallObjectId(job.jobId, stall['index'])) &&
              !covered.contains(
                  HarnessHooks.stallObjectId(job.jobId, stall['index'])))
            {
              'event': 'download.stalled',
              'objectId': HarnessHooks.stallObjectId(job.jobId, stall['index']),
              'occurredAt': stall['at'],
              'data': {
                'jobId': job.jobId,
                'infoHash': job.input['infoHash'],
                'title': job.title,
                ...Map<String, Object?>.from(stall)..remove('index'),
              }
            },
      // A download someone cancelled is news to no one: whoever cancelled
      // it knows. Files that finished before still arrive above.
      if (job.state.isTerminal &&
          job.state != JobState.cancelled &&
          !covered.contains('terminal:${job.jobId}'))
        {
          'event': 'task.terminal',
          'objectId': job.jobId,
          'occurredAt': job.updatedAt.toIso8601String(),
          'data': publicTaskFacts(job.toJson())
        }
    ];
    if (facts.isEmpty) return;
    final automatic = [
      for (final row in await _read(database.query('followups',
          columns: ['snapshot'],
          where: "json_extract(snapshot, '\$.condition.downloadJobId') = ?",
          whereArgs: [job.jobId],
          orderBy: 'rowid')))
        if (row['automatic'] == 'download') row
    ];
    final pending = automatic.where((r) => r['state'] == 'ready' && r['remoteSealed'] != true).lastOrNull;
    final now = DateTime.now().toUtc();
    final last = automatic.lastOrNull;
    // The first file is news: it can be watched. Later ones are progress
    // the download page already shows, so they wait and come together.
    final due = last == null
        ? now
        : DateTime.parse(
                (last['dispatchedAt'] ?? last['createdAt']) as String)
            .add(const Duration(minutes: 10));
    final row = pending ??
        <String, Object?>{
          'id': 'followup-download-${job.jobId}-${automatic.length}',
          'automatic': 'download',
          'state': 'ready',
          'title': '下载事实：${job.title}',
          'instruction':
              '由此会话发起的下载有新事实：完成时的校验、入库与播放，或很久没有进展。作品和剧集未知时保留未知。之后完成的文件、下载结束或停滞，NipaPlay 都会再送回这里。下一步由你决定。',
          'condition': {'downloadJobId': job.jobId},
          'downloadObjects': <Object?>[],
          'deliverAfter': due.toIso8601String(),
          'waitingFor': 'Waiting for an idle chat host.',
          'repository': target['repository'],
          'threadId': target['threadId'],
          'turnId': null,
          'origin': target['origin'],
          'invocationId': target['invocationId'],
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'reason': null,
          'turnStatus': null,
          if (target['deviceId'] != null) 'remoteDeviceId': target['deviceId'],
          if (target['returnTicket'] != null) 'returnTicket': target['returnTicket'],
          'trigger': {
            'kind': 'download.facts',
            'jobId': job.jobId,
            'title': job.title,
            'facts': <JsonMap>[]
          }
        };
    (row['downloadObjects'] as List).addAll(facts.map((fact) =>
        fact['event'] == 'task.terminal'
            ? 'terminal:${fact['objectId']}'
            : fact['objectId']));
    ((row['trigger'] as Map)['facts'] as List).addAll(facts);
    if (job.state.isTerminal ||
        facts.any((fact) => fact['event'] == 'download.stalled')) {
      row['deliverAfter'] = now.toIso8601String();
    }
    final safe = redactHarnessJson(row) as JsonMap;
    if (pending == null) {
      await database.transaction((tx) async {
        await tx.insert('followups', {
          'id': safe['id'],
          'state': 'ready',
          'snapshot': jsonEncode(safe)
        });
        await _event(tx, safe, 'registered', target['origin'] as String,
            target['invocationId'] as String);
      });
    } else {
      await _save(safe, 'ready', 'coalesced');
    }
    covered.addAll((safe['downloadObjects'] as List).whereType<String>());
  }

  /// An authenticated device delivers an immutable batch. Repeated delivery
  /// returns the original receipt, including after the conversation completed.
  Future<JsonMap> acceptMeshDelivery(String peer, JsonMap delivery,
      {JsonMap? target}) => _serial(() async {
    final remote = delivery['row'] as JsonMap;
    final id = 'followup-mesh-$peer-${remote['id']}';
    final existing = await database.query('followups', where: 'id=?', whereArgs: [id]);
    if (existing.isNotEmpty) return {'id': id, 'accepted': true};
    final wake = target == null;
    final now = DateTime.now().toUtc().toIso8601String();
    await location.ready;
    final row = <String, Object?>{
      ...remote, 'id': id, 'state': 'ready', 'turnId': null, 'turnStatus': null,
      'repository': wake ? location.path : target['repository'],
      'threadId': wake ? remote['threadId'] : target['threadId'],
      'origin': 'mesh:$peer', 'createdAt': now, 'updatedAt': now,
      'sourceDeviceId': peer, 'sourceFollowupId': remote['id'],
      'reason': null, 'waitingFor': 'Waiting for an idle chat host.',
    }..remove('remoteDeviceId')..remove('remoteRetryAt')..remove('remoteReceipt');
    if (!wake) {
      row['automatic'] = switch (remote['automatic']) {
        'program' => 'meshProgram',
        'subscription' => 'meshSubscription',
        'userTask' => 'meshUserTask',
        _ => 'meshDownload',
      };
      row['condition'] = {'kind': 'mesh.${remote['automatic']}.facts'};
      row['trigger'] = {...remote['trigger'] as JsonMap, 'sourceDeviceId': peer};
    }
    final safe = redactHarnessJson(row) as JsonMap;
    await database.transaction((tx) async {
      if (!wake && remote['automatic'] != 'subscription') {
        for (final fact in ((safe['trigger'] as Map)['facts'] as List).cast<JsonMap>()) {
          final event = remote['automatic'] == 'download' && fact['event'] == 'task.terminal' && (fact['data'] as Map)['state'] == 'succeeded' ? 'download.completed' : fact['event'];
          await tx.insert('followup_hook_events', {
            'event': event,
            'object_id': fact['objectId'], 'payload': jsonEncode(fact),
          });
          if (event == 'download.stalled') _stallRecorded(fact);
        }
      }
      await tx.insert('followups', {'id': id, 'state': 'ready', 'snapshot': jsonEncode(safe)});
      await _event(tx, safe, 'received', 'mesh:$peer', remote['invocationId'] as String);
    });
    _schedule();
    return {'id': id, 'accepted': true};
  });

  Future<void> _filterDownloadReturn(JsonMap row) async {
    final trigger = row['trigger'] as Map;
    final facts = (trigger['facts'] as List).cast<JsonMap>();
    final rows = await _owners(facts);
    // Resolve waiting broad subscriptions in occurrence order, just like sweep.
    final claimed = <String>{};
    final remaining = <JsonMap>[];
    for (final fact in facts) {
      final manual = rows
          .where(
              (r) => !claimed.contains(r['id']) && _manualCovers(r, fact, row))
          .firstOrNull;
      if (manual == null) {
        remaining.add(fact);
      } else {
        claimed.add(manual['id'] as String);
      }
    }
    if (remaining.length == facts.length) return;
    trigger['facts'] = remaining;
    await _save(row, remaining.isEmpty ? 'cancelled' : 'ready', 'deduplicated',
        reason: remaining.isEmpty
            ? 'Matching Agent followup owns these facts.'
            : null);
  }

  /// Every followup that could own one of [facts], oldest first: registered
  /// for the end of its task, triggered by it, or still waiting. Which one
  /// does is [_manualCovers]'s to say.
  Future<List<JsonMap>> _owners(List<JsonMap> facts) async {
    final objects = {
      for (final fact in facts)
        if (fact['objectId'] case final String id) id
    }.toList();
    final rows = <int, JsonMap>{};
    Future<void> add(String where, List<Object?> args) async {
      for (final row in await database.rawQuery(
          'SELECT rowid AS position, snapshot FROM followups WHERE $where',
          args)) {
        rows[row['position'] as int] ??= _decode(row);
      }
    }

    await add("state = 'waiting'", const []);
    for (final chunk in _chunks(objects)) {
      await add(
          "json_extract(snapshot, '\$.condition.jobId') IN (${_marks(chunk.length)})",
          chunk);
      await add(
          "json_extract(snapshot, '\$.trigger.objectId') IN (${_marks(chunk.length)})",
          chunk);
    }
    return [for (final position in rows.keys.toList()..sort()) rows[position]!];
  }
}
