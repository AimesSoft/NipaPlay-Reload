part of 'service.dart';

/// Durable viewer messages. Asking returns immediately; only an explicit
/// answer creates a followup, atomically with recording that answer.
extension AgentInbox on Followups {
  Future<void> _inboxReady() => _inboxSchema ??= () async {
        await database.execute('CREATE TABLE IF NOT EXISTS agent_inbox '
            '(id TEXT PRIMARY KEY, state TEXT NOT NULL, created_at TEXT NOT NULL, snapshot TEXT NOT NULL)');
        await database
            .execute('CREATE TABLE IF NOT EXISTS agent_inbox_preferences '
                '(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      }();

  Future<Object?> inboxPreference(String key, Object? fallback) async {
    await _inboxReady();
    final rows = await database
        .query('agent_inbox_preferences', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? fallback : jsonDecode(rows.single['value'] as String);
  }

  Future<void> setInboxPreference(String key, Object? value) async {
    await _inboxReady();
    await database.insert(
        'agent_inbox_preferences', {'key': key, 'value': jsonEncode(value)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<JsonMap?> folderRequest(Invocation invocation) async {
    if (await inboxPreference('library.organizeAddedFolders', true) != true) {
      return null;
    }
    await location.ready;
    final target = await _inboxTarget(invocation, required: false);
    return {
      ...target,
      'origin': invocation.origin,
      'invocationId': invocation.id,
      'fileOrganization':
          await inboxPreference('library.fileOrganization', 'ask'),
      'rules': await inboxPreference(
          'library.fileOrganizationRules', defaultFolderRules),
    };
  }

  Future<JsonMap> _inboxTarget(Invocation invocation,
      {bool required = true}) async {
    await location.ready;
    final remote = invocation.origin.startsWith('mesh:')
        ? await downloadReturnTarget(invocation)
        : null;
    if (remote != null) return Map.of(remote);
    final boundary = TurnBoundaries.latest(
        File('${File(database.path).parent.path}/journal.jsonl'),
        invocation.origin);
    final thread = _host?.threadForOrigin(invocation.origin) ??
        (boundary != null && boundary['phase'] == 'started'
            ? (boundary['threadId'] as String?)
            : null);
    if (required && thread == null) {
      throw const Failure(FailureCode.unavailable,
          'An asynchronous question needs an originating embedded conversation.');
    }
    return {
      'repository': _host?.repository.path ?? location.path,
      'threadId': thread,
      if (thread == null && agentDevice?.call() != null)
        'deviceId': agentDevice!.call(),
    };
  }

  Future<JsonMap> publishInbox(JsonMap input, Invocation invocation,
          {required bool question}) =>
      _serial(() async {
        await _inboxReady();
        final target = await _inboxTarget(invocation, required: question);
        final id = 'inbox-${sha256.convert(utf8.encode(jsonEncode([
              target['repository'],
              target['threadId'],
              target['deviceId'],
              invocation.origin,
              input['requestId']
            ])))}';
        final existing =
            await database.query('agent_inbox', where: 'id=?', whereArgs: [id]);
        if (existing.isNotEmpty) {
          final old =
              jsonDecode(existing.single['snapshot'] as String) as JsonMap;
          if (_inboxCanonical(old['request']) != _inboxCanonical(input) ||
              old['kind'] != (question ? 'question' : 'notice')) {
            throw const Failure(FailureCode.conflict,
                'requestId already names a different message.');
          }
          return old;
        }
        final options = (input['options'] as List? ?? const []).cast<String>();
        if (options.toSet().length != options.length) {
          throw const Failure(
              FailureCode.invalidInput, 'Question options must be distinct.');
        }
        final count = (await database.rawQuery(
                "SELECT COUNT(*) AS n FROM agent_inbox WHERE state IN ('pending','unread')"))
            .single['n'] as int;
        if (count >= 500) {
          throw const Failure(FailureCode.conflict,
              'Read or resolve existing reminders first (limit 500).');
        }
        final now = DateTime.now().toUtc().toIso8601String();
        final row = <String, Object?>{
          'id': id,
          'kind': question ? 'question' : 'notice',
          'state': question ? 'pending' : 'unread',
          'hidden': false,
          'title': input['title'],
          'body': input['body'],
          'options': options,
          'severity': input['severity'] ?? 'info',
          'createdAt': now,
          'target': target,
          'origin': invocation.origin,
          'request': input,
        };
        await database.insert('agent_inbox', {
          'id': id,
          'state': row['state'],
          'created_at': now,
          'snapshot': jsonEncode(row)
        });
        return row;
      });

  Future<JsonMap> inboxList(
      {int offset = 0, int limit = 30, bool includeResolved = false}) async {
    await _inboxReady();
    final where = includeResolved ? null : "state IN ('pending','unread')";
    final rows = await database.query('agent_inbox',
        where: where,
        orderBy: 'created_at DESC, id',
        limit: limit + 1,
        offset: offset);
    return {
      'items': [
        for (final row in rows.take(limit))
          jsonDecode(row['snapshot'] as String)
      ],
      'nextOffset': rows.length > limit ? offset + limit : null,
      'popupsEnabled': await inboxPreference('notification.agentPopups', true),
    };
  }

  Future<JsonMap> answerInbox(
          String id, String answer, Invocation invocation) =>
      _serial(() async {
        await _inboxReady();
        final rows =
            await database.query('agent_inbox', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          throw const Failure(FailureCode.notFound, 'Question not found.');
        }
        final row = jsonDecode(rows.single['snapshot'] as String) as JsonMap;
        if (row['state'] == 'answered' && row['answer'] == answer) return row;
        if (row['kind'] != 'question' || row['state'] != 'pending') {
          throw const Failure(FailureCode.conflict,
              'Question is no longer awaiting an answer.');
        }
        final now = DateTime.now().toUtc().toIso8601String();
        final target = Map<String, Object?>.from(row['target'] as Map);
        final delivery = _inboxFollowup(
            'followup-answer-$id',
            target,
            '用户回答：${row['title']}',
            '用户已回答此前的问题。只据此继续对应工作，不重做已完成步骤。答案只授权其明确表达的范围。',
            {'questionId': id, 'question': row['body'], 'answer': answer},
            now,
            automatic: 'inboxAnswer',
            origin: invocation.origin);
        row.addAll({
          'state': 'answered',
          'answer': answer,
          'answeredAt': now,
          'hidden': true,
          'deliveryId': delivery['id']
        });
        await database.transaction((tx) async {
          await tx.update(
              'agent_inbox', {'state': 'answered', 'snapshot': jsonEncode(row)},
              where: 'id=?', whereArgs: [id]);
          await tx.insert('followups', {
            'id': delivery['id'],
            'state': 'ready',
            'snapshot': jsonEncode(delivery)
          });
          await _event(
              tx, delivery, 'registered', invocation.origin, invocation.id);
        });
        _schedule();
        return row;
      });

  /// Hiding a question never answers or cancels it. Cancelling does not grant consent.
  Future<JsonMap> dismissInbox(String id, {bool cancel = false}) =>
      _serial(() async {
        await _inboxReady();
        final rows =
            await database.query('agent_inbox', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          throw const Failure(FailureCode.notFound, 'Reminder not found.');
        }
        final row = jsonDecode(rows.single['snapshot'] as String) as JsonMap;
        row['hidden'] = true;
        if (row['state'] == 'unread') row['state'] = 'read';
        if (cancel && row['state'] == 'pending') row['state'] = 'cancelled';
        await database.update(
            'agent_inbox', {'state': row['state'], 'snapshot': jsonEncode(row)},
            where: 'id=?', whereArgs: [id]);
        return row;
      });

  JsonMap _inboxFollowup(String id, JsonMap target, String title,
          String instruction, JsonMap facts, String now,
          {required String automatic, String origin = 'gui'}) =>
      {
        'id': id,
        'automatic': automatic,
        'state': 'ready',
        'title': title,
        'instruction': instruction,
        'condition': {'kind': automatic},
        'repository': target['repository'],
        'threadId': target['threadId'],
        'origin': origin,
        'invocationId': id,
        'createdAt': now,
        'updatedAt': now,
        'turnId': null,
        'turnStatus': null,
        'reason': null,
        'waitingFor': 'Waiting for the originating Agent conversation.',
        if (target['deviceId'] != null) 'remoteDeviceId': target['deviceId'],
        if (target['returnTicket'] != null)
          'returnTicket': target['returnTicket'],
        'trigger': {'kind': automatic, 'facts': facts},
      };

  Future<void> _collectInboxErrors(_Tasks tasks) async {
    final jobs = await tasks
        .changedWhere((j) => j.state == JobState.failed && j.error != null);
    if (jobs.isEmpty) return;
    await _inboxReady();
    for (final job in jobs) {
      final id = 'inbox-error-${job.jobId}';
      final now = DateTime.now().toUtc().toIso8601String();
      final row = {
        'id': id,
        'kind': 'notice',
        'severity': 'error',
        'state': 'unread',
        'title': job.title,
        'body': const JsonEncoder.withIndent('  ').convert(job.error!.toJson()),
        'hidden': false,
        'createdAt': now,
        'jobId': job.jobId,
        'options': <String>[]
      };
      await database.insert(
          'agent_inbox',
          {
            'id': id,
            'state': 'unread',
            'created_at': now,
            'snapshot': jsonEncode(row)
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _collectFolderRequests(_Tasks tasks) async {
    final jobs = await tasks.ofTypes(['media.scan'],
        (j) => j.state.isTerminal && j.input['folderRequest'] is Map);
    for (final job in jobs) {
      final id = 'followup-folder-${job.jobId}';
      if ((await _existing([id])).isNotEmpty) continue;
      final target =
          Map<String, Object?>.from(job.input['folderRequest'] as Map);
      final now = DateTime.now().toUtc().toIso8601String();
      final row = _inboxFollowup(
          id,
          target,
          '整理新添加的文件夹',
          '用户明确添加了这个文件夹，请处理本次扫描范围内的文件。先核查扫描回执；失败或取消时报告原始错误，不开始移动文件。'
              '扫描成功后识别作品和分集、补齐资料，独立工作尽量批量并行。只索引不代表已整理。'
              '先读取 settings 中 library.fileOrganization 与 library.fileOrganizationRules 的当前值：'
              'off 保持磁盘路径，ask 用 ui.ask 询问本次或以后是否自动整理目录和文件名，auto 表示用户已保存长期授权。'
              '询问后继续资料整理，只让依赖回答的磁盘修改等待。没有回答不移动文件。'
              '允许时按规则处理此根目录内的文件，先核对身份、同名目标和正在使用的文件，保留字幕弹幕及身份进度关联，记录可回查的旧新路径。'
              '不要删除、覆盖、跨根目录搬运或破坏做种；无法保持关联时停下该项并说明。'
              '阶段和结束是否提醒、提醒内容由你决定，用 ui.notify；问题用 ui.ask，查参数用 describe。',
          {
            'root': job.input['root'],
            'jobId': job.jobId,
            'state': job.state.name,
            'receipt': job.receipt?.toJson(),
            'failure': job.error?.toJson(),
            'request': target
          },
          now,
          automatic: 'folderRequest');
      if (await inboxPreference('library.organizeAddedFolders', true) != true) {
        row['state'] = 'cancelled';
        row['reason'] = 'Folder organization disabled before dispatch.';
      }
      await database.transaction((tx) async {
        await tx.insert('followups',
            {'id': id, 'state': row['state'], 'snapshot': jsonEncode(row)});
        await _event(tx, row, 'registered', 'gui', id);
      });
    }
  }
}

const defaultFolderRules = '仅整理本次添加的根目录内已确认身份的视频；按作品/季组织，文件名保留集号、版本和扩展名。'
    '同名字幕和弹幕一起处理，保留身份与观看进度。跳过身份不明、重名目标、播放中、下载中或做种的文件；不删除、不覆盖、不移出根目录。';

// Transport tickets and map insertion order can change when a call is retried.
String _inboxCanonical(Object? value) {
  Object? normalize(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: normalize(item[key])};
    }
    if (item is List) return item.map(normalize).toList();
    return item;
  }

  return jsonEncode(normalize(value));
}
