import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nipaplay/security/secret_redactor.dart';

import '../chat/chat_host.dart';
import '../chat/helpers.dart';
import '../chat/turn_process_store.dart';
import '../repository_location.dart';
import '../harness_redaction.dart';
import '../state/views.dart' show publicTaskFacts;
import '../state/query.dart';

part 'download_returns.dart';
part 'program_returns.dart';

const followupFields = ObjectSchema({
  'id': StringSchema(),
  'state': StringSchema(),
  'title': StringSchema(),
  'instruction': StringSchema(),
  'condition': ObjectSchema({}, additionalProperties: true),
  'waitingFor': StringSchema(nullable: true),
  'repository': StringSchema(),
  'threadId': StringSchema(nullable: true),
  'turnId': StringSchema(nullable: true),
  'origin': StringSchema(),
  'invocationId': StringSchema(),
  'createdAt': StringSchema(),
  'updatedAt': StringSchema(),
  'trigger': ObjectSchema({}, additionalProperties: true, nullable: true),
  'reason': StringSchema(nullable: true),
  'turnStatus': StringSchema(nullable: true),
  'remoteDeviceId': StringSchema(nullable: true),
  'sourceDeviceId': StringSchema(nullable: true),
  'sourceFollowupId': StringSchema(nullable: true),
  'deliveryState': StringSchema(nullable: true),
  'remoteReceipt': ObjectSchema({}, additionalProperties: true, nullable: true),
});

/// Durable conditions and one delivery. Agent instructions remain opaque text.
final class Followups {
  Followups(this.database, this.engine, this.location);
  final Database database;
  final TaskEngine engine;
  final RepositoryLocation location;
  ChatHost? _host;
  Helpers? helpers;
  void Function()? eventCommitted;
  String? Function()? agentDevice;
  Future<JsonMap> Function(String, JsonMap)? deliverRemote;
  Future<JsonMap> turnProcess(String threadId, String turnId) async {
    await location.ready;
    final host = _host;
    if (host != null) return host.turnProcess(threadId, turnId);
    final saved = TurnProcessStore(TurnProcessStore.fileFor(
        File(database.path).parent, location.path)).read(threadId, turnId);
    return {'found': saved != null, 'process': saved};
  }
  String _unavailable = 'Embedded chat host is not running.';
  StreamSubscription<Job>? _jobs;
  StreamSubscription<ChatMessage>? _chatEvents;

  /// How turns actually ended, as the host reported them live: a thread
  /// read back from history can show a turn the provider failed as completed.
  final _ended = <String, Map>{};
  Timer? _timer;
  Future<void> _operations = Future.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      // The caller receives the error; the next operation still gets its turn.
    });
    return result;
  }

  void start() {
    _jobs = engine.changes.listen((_) => _schedule());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _schedule());
    _schedule();
  }

  void _schedule() {
    unawaited(sweep().catchError((Object error, StackTrace stack) {
      // Infrastructure failures are visible rather than dropping a condition.
      Zone.current.handleUncaughtError(error, stack);
    }));
  }

  Future<void> attach(ChatHost? host, {String? reason}) async {
    await _chatEvents?.cancel();
    _host = host;
    helpers?.attach(host);
    _unavailable = reason ?? 'Embedded chat host is not running.';
    _chatEvents = host?.events.listen((message) {
      if (message['method'] == 'turn/completed') {
        final turn = (message['params'] as Map?)?['turn'];
        if (turn is Map && turn['id'] is String) {
          _ended[turn['id'] as String] = {
            'status': turn['status'],
            'error': turn['error']
          };
          if (_ended.length > 64) _ended.remove(_ended.keys.first);
        }
      }
      if (message['method'] == 'turn/completed' ||
          message['method'] == 'host/error') {
        _schedule();
      }
    });
    await sweep();
  }

  Future<List<JsonMap>> _rows() async => [
        for (final row in await database.query('followups', orderBy: 'rowid'))
          jsonDecode(row['snapshot'] as String) as JsonMap
      ];

  Future<List<JsonMap>> list() async =>
      [for (final row in await _rows()) _public(row)];

  StateView get view => StateView(
        name: 'followups',
        description:
            'Durable one-shot Agent followups. waiting awaits condition; ready awaits an idle chat host. '
            'execution_failed retains the delivery error; started/completed identify the actual thread and turn. '
            'waitingFor and title are suitable for progress UI.',
        fields: followupFields,
        read: (offset, limit) async =>
            (await list()).skip(offset).take(limit).toList(),
        readAll: () async => StateRows(await list()),
      );

  Future<JsonMap> register(JsonMap input, Invocation invocation) =>
      _register(input, invocation, false);

  Future<JsonMap> wake(JsonMap input, Invocation invocation) =>
      _register(input, invocation, true);

  Future<JsonMap> session(String operation,
      {String? threadId, String? cursor}) async {
    final host = _host;
    if (host == null || !host.available) {
      throw Failure(FailureCode.unavailable, _unavailable);
    }
    return switch (operation) {
      'main' => await host.getMainSession(),
      'new' => await host.newConversation(),
      'switch' => await host.switchSession(threadId!),
      _ => await host.listSessions(cursor: cursor),
    };
  }

  Future<JsonMap> discover(JsonMap input, Invocation invocation) async {
    await location.ready;
    final safe = publicHarnessFacts(input) as JsonMap;
    final at = DateTime.now().toUtc().toIso8601String();
    final sequence = await database.insert('harness_discoveries', {
      'at': at,
      'origin': invocation.origin,
      'invocation_id': invocation.id,
      'repository': location.path,
      'title': safe['title'],
      'source': safe['source'],
      'facts': jsonEncode(safe['facts']),
    });
    return {'id': 'discovery:$sequence', 'at': at, ...safe};
  }

  Future<JsonMap> _register(
          JsonMap input, Invocation invocation, bool immediate) =>
      _serial(() async {
        final condition = immediate
            ? <String, Object?>{'kind': 'wake'}
            : Map<String, Object?>.from(input['when'] as Map);
        final task = condition['jobId'] as String?;
        final event = condition['event'] as String?;
        if (!immediate &&
            ((task == null) == (event == null) ||
                (task != null && condition.containsKey('objectId')))) {
          throw const Failure(FailureCode.invalidInput,
              'when must contain exactly jobId, or event with optional objectId.');
        }
        if (task != null) await engine.get(task);
        await location.ready;
        final returnTo = !immediate && invocation.origin.startsWith('mesh:')
            ? await downloadReturnTarget(invocation) : null;
        String? threadId = input['threadId'] as String?;
        if (returnTo != null) {
          if (threadId != null && threadId != returnTo['threadId']) {
            throw const Failure(FailureCode.invalidInput,
                'Remote subscription thread must match the originating conversation.');
          }
          threadId = returnTo['threadId'] as String;
        }
        if (!immediate &&
            threadId == null &&
            (invocation.origin.startsWith('harness_cli:chat:') ||
                invocation.origin.startsWith('harness_cli:helper:'))) {
          threadId = _host?.threadForOrigin(invocation.origin);
          if (threadId == null) {
            throw const Failure(FailureCode.unavailable,
                'Chat session has no selected thread; specify threadId explicitly.');
          }
        }
        final cursor = (await database.rawQuery(
                'SELECT COALESCE(MAX(sequence),0) AS cursor FROM followup_hook_events'))
            .single['cursor'];
        final now = DateTime.now().toUtc().toIso8601String();
        final row = <String, Object?>{
          'id': 'followup-${DateTime.now().microsecondsSinceEpoch}-'
              '${Random.secure().nextInt(1 << 32).toRadixString(16)}',
          'state': immediate ? 'ready' : 'waiting',
          'title': input['title'] ?? input['instruction'],
          'instruction': input['instruction'],
          'condition': condition,
          'hookCursor': cursor,
          'waitingFor': immediate
              ? 'Waiting for an idle chat host.'
              : task != null
                  ? 'task $task enters succeeded/failed/cancelled'
                  : '$event${condition['objectId'] == null ? '' : ' for ${condition['objectId']}'}',
          'repository': returnTo?['repository'] ?? location.path,
          'threadId': threadId,
          'turnId': null,
          'origin': invocation.origin,
          'invocationId': invocation.id,
          'createdAt': now,
          'updatedAt': now,
          'trigger': immediate
              ? {
                  'kind': 'agent.wake',
                  'occurredAt': now,
                  'facts': publicHarnessFacts(input['facts'])
                }
              : null,
          'reason': null,
          'turnStatus': null,
          if (immediate && agentDevice?.call() != null)
            'remoteDeviceId': agentDevice!.call(),
          if (returnTo != null) ...{
            'automatic': 'subscription',
            'remoteDeviceId': returnTo['deviceId'],
            'returnTicket': returnTo['returnTicket'],
          },
        };
        final safe = SecretRedactor.json(row) as JsonMap;
        await database.transaction((tx) async {
          await tx.insert('followups', {
            'id': safe['id'],
            'state': safe['state'],
            'snapshot': jsonEncode(safe)
          });
          await _event(
              tx, safe, 'registered', invocation.origin, invocation.id);
        });
        // Delivery is asynchronous; registration never holds the Agent's turn.
        _schedule();
        return _public(safe);
      });

  Future<JsonMap> cancel(String id, Invocation invocation) => _serial(() async {
        final row = await _get(id);
        if (row['state'] == 'cancelled') return _public(row);
        if (!{'waiting', 'ready', 'execution_failed'}.contains(row['state'])) {
          throw const Failure(FailureCode.conflict,
              'Delivery already began; a followup cannot interrupt its turn.');
        }
        await _save(row, 'cancelled', 'cancelled',
            origin: invocation.origin,
            invocationId: invocation.id,
            reason: 'Cancelled by caller.');
        return _public(row);
      });

  Future<void> consumeHelperResult(String jobId, JsonMap taken) => _serial(() async {
        for (final row in await _rows()) {
          if ((row['condition'] as Map)['jobId'] == jobId &&
              {'waiting', 'ready'}.contains(row['state'])) {
            row['consumedBy'] = taken;
            await _save(row, 'cancelled', 'consumed',
                origin: 'codex_native:wait', reason: 'Parent collected this result with wait.');
          }
        }
      });

  Future<JsonMap> _get(String id) async {
    final rows =
        await database.query('followups', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const Failure(FailureCode.notFound, 'Followup not found.');
    }
    return jsonDecode(rows.single['snapshot'] as String) as JsonMap;
  }

  Future<void> hookEvent(String event, String objectId, JsonMap payload) =>
      _serial(() async {
        if (event == 'download.file_completed' && (await database.query(
            'followup_hook_events', where: 'event=? AND object_id=?',
            whereArgs: [event, objectId], limit: 1)).isNotEmpty) {
          return;
        }
        await database.insert('followup_hook_events', {
          'event': event,
          'object_id': objectId,
          'payload': jsonEncode(redactHarnessJson(payload)),
        });
        eventCommitted?.call();
        _schedule();
      });

  Future<void> _event(DatabaseExecutor tx, JsonMap row, String type,
          String origin, String? invocationId) =>
      tx.insert('followup_events', {
        'followup_id': row['id'],
        'at': row['updatedAt'],
        'type': 'followup.$type',
        'origin': origin,
        'invocation_id': invocationId,
        'facts': jsonEncode(_public(row)),
      }).then((_) {});

  JsonMap _public(JsonMap row) => {...row}..remove('hookCursor');

  Future<void> _save(JsonMap row, String state, String event,
      {String origin = 'application',
      String? invocationId,
      String? reason}) async {
    row['state'] = state;
    row['reason'] = reason;
    row['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    if (state != 'waiting') {
      row['waitingFor'] = state == 'ready' ? reason : null;
    }
    await database.transaction((tx) async {
      await tx.update(
          'followups', {'state': state, 'snapshot': jsonEncode(row)},
          where: 'id=?', whereArgs: [row['id']]);
      await _event(tx, row, event, origin, invocationId);
    });
  }

  Future<void> sweep() => _serial(() async {
        await _collectDownloadReturns();
        await _collectProgramReturns();
        final rows = await _rows();
        // Resolve one-shot subscriptions before deciding which facts they own.
        for (final row in [
          ...rows.where((row) => row['automatic'] != 'download'),
          ...rows.where((row) => row['automatic'] == 'download'),
        ]) {
          if (row['state'] == 'waiting') {
            final condition = row['condition'] as Map;
            JsonMap? trigger;
            if (condition['jobId'] case final String id) {
              final job = await engine.get(id);
              if (job.state.isTerminal) {
                trigger = {
                  'kind': 'task.terminal',
                  'occurredAt': job.updatedAt.toIso8601String(),
                  ...publicTaskFacts(job.toJson()),
                };
              }
            } else {
              final matches = await database.query('followup_hook_events',
                  where:
                      'sequence>? AND event=?${condition['objectId'] == null ? '' : ' AND object_id=?'}'
                      '${condition['event'] == 'download.file_completed' ? " AND json_extract(payload,'\$.occurredAt')>=?" : ""}',
                  whereArgs: [
                    row['hookCursor'],
                    condition['event'],
                    if (condition['objectId'] != null) condition['objectId']
                    ,if (condition['event'] == 'download.file_completed') row['createdAt']
                  ],
                  orderBy: 'sequence',
                  limit: 1);
              if (matches.isNotEmpty) {
                trigger =
                    jsonDecode(matches.single['payload'] as String) as JsonMap;
              }
              // Download completion can be reconstructed from the persisted task.
              if (trigger == null &&
                  condition['event'] == 'download.file_completed') {
                for (final job in await engine.list(type: 'download')) {
                  for (final file in (job.checkpoint['completedFiles'] as List? ?? []).cast<JsonMap>()) {
                    final objectId = file['objectId'] as String;
                    if (file['verification'] != 'verified' ||
                        condition['objectId'] != null && condition['objectId'] != objectId ||
                        DateTime.parse(file['completedAt'] as String)
                            .isBefore(DateTime.parse(row['createdAt'] as String))) {
                      continue;
                    }
                    trigger = {'event': 'download.file_completed', 'objectId': objectId,
                      'occurredAt': file['completedAt'],
                      'data': {'jobId': file['jobId'], 'infoHash': job.input['infoHash'], 'file': file}};
                    break;
                  }
                  if (trigger != null) break;
                }
              }
              if (trigger == null &&
                  condition['event'] == 'download.completed') {
                for (final job in await engine.list(
                    type: 'download', state: JobState.succeeded)) {
                  if (condition['objectId'] != null &&
                      condition['objectId'] != job.jobId) {
                    continue;
                  }
                  if (job.updatedAt
                      .isBefore(DateTime.parse(row['createdAt'] as String))) {
                    continue;
                  }
                  trigger = {
                    'event': 'download.completed',
                    'objectId': job.jobId,
                    'occurredAt': job.updatedAt.toIso8601String(),
                    'data': publicTaskFacts(job.toJson())
                  };
                  break;
                }
              }
            }
            if (trigger == null) continue;
            row['trigger'] = redactHarnessJson(trigger);
            await _save(row, 'ready', 'triggered',
                reason: 'Waiting for an idle chat host.');
          }
          final host = _host;
          if (row['state'] == 'ready') {
            if (_taskReturn(row)) {
              await _filterDownloadReturn(row, await _rows());
              if (row['state'] == 'cancelled') continue;
              if (DateTime.now().toUtc().isBefore(
                  DateTime.parse(row['deliverAfter'] as String))) {
                final reason = 'Batching download facts until ${row['deliverAfter']}.';
                if (row['reason'] != reason) {
                  await _save(row, 'ready', 'pending', reason: reason);
                }
                continue;
              }
            }
            if (row['remoteDeviceId'] case final String peer) {
              final retryAt = row['remoteRetryAt'] as String?;
              if (retryAt != null && DateTime.now().toUtc().isBefore(DateTime.parse(retryAt))) continue;
              if (deliverRemote == null) continue;
              try {
                if (row['remoteSealed'] != true) {
                  row['remoteSealed'] = true;
                  await _save(row, 'ready', 'sealed');
                }
                row['remoteReceipt'] = await deliverRemote!(peer, row);
                row['dispatchedAt'] = DateTime.now().toUtc().toIso8601String();
                row['deliveryState'] = 'forwarded';
                await _save(row, 'completed', 'forwarded', reason: 'Destination durably accepted this delivery; its conversation state is owned there.');
              } on Failure catch (error) {
                row['remoteRetryAt'] = DateTime.now().toUtc().add(const Duration(seconds: 30)).toIso8601String();
                await _save(row, 'ready', 'pending', reason: error.message);
              }
              continue;
            }
            if (row['retryAt'] case final String retryAt
                when DateTime.now().toUtc().isBefore(DateTime.parse(retryAt))) {
              continue;
            }
            final reason = host == null || !host.available
                ? host?.liveness.latestError ?? _unavailable
                : host.repository.path != row['repository']
                    ? 'The registered harness is not active.'
                    : host.busy
                        ? 'Chat host has an active turn; waiting until idle.'
                        : null;
            if (reason != null) {
              if (row['reason'] != reason) {
                await _save(row, 'ready', 'pending', reason: reason);
              }
              continue;
            }
            try {
              final target =
                  await host!.prepareFollowup(row['threadId'] as String?);
              if (target == null) continue;
              if ((row['condition'] as Map)['jobId'] case final String jobId) {
                final job = await engine.get(jobId);
                final taken = await helpers?.nativeResultTaken(job, host);
                if (taken != null) {
                  row['consumedBy'] = taken;
                  await _save(row, 'cancelled', 'consumed',
                      origin: 'codex_native:wait', reason: 'Parent collected this result with wait.');
                  continue;
                }
              }
              row['threadId'] = target;
              if (_taskReturn(row)) {
                row['dispatchedAt'] = DateTime.now().toUtc().toIso8601String();
              }
              await _save(row, 'dispatching', 'dispatching');
              final response = await host.startFollowup(target, _prompt(row));
              if (response == null) {
                await _save(row, 'ready', 'pending',
                    reason: 'Chat host became busy before delivery.');
                continue;
              }
              row['turnId'] = response['turn']['id'];
              row['turnStatus'] = response['turn']['status'];
              if ((row['condition'] as Map)['jobId'] case final String jobId) {
                final job = await engine.get(jobId);
                if (job.type == 'agent.helper') {
                  await helpers?.shareCards(
                      job, target, row['turnId'] as String);
                }
              }
              await _save(row, 'started', 'started',
                  origin: 'harness_cli:chat:${host.sessionId}');
            } catch (error) {
              // An RPC can commit before its response is lost. Reconcile from history
              // instead of retrying turn/start and opening a duplicate turn.
              await _save(
                  row,
                  row['state'] == 'dispatching' && error is! ChatRpcError
                      ? 'dispatching'
                      : 'execution_failed',
                  'execution_failed',
                  reason: redactHarnessText(error.toString()));
            }
          }
          if ((row['state'] == 'dispatching' || row['state'] == 'started') &&
              host != null &&
              host.available &&
              !host.busy &&
              host.repository.path == row['repository']) {
            try {
              final thread = await host.readThread(row['threadId'] as String);
              final turns = thread['turns'] as List;
              final failed = [
                for (final id in row['failedTurns'] as List? ?? []) id
              ];
              final matches = turns.cast<Map>().where((turn) =>
                  !failed.contains(turn['id']) &&
                  (row['turnId'] != null
                      ? turn['id'] == row['turnId']
                      : (turn['items'] as List).cast<Map>().any((item) =>
                          item['type'] == 'userMessage' &&
                          jsonEncode(item['content']).contains(_marker(row)))));
              if (matches.isEmpty) {
                if (row['state'] == 'dispatching') {
                  await _save(row, 'execution_failed', 'execution_failed',
                      reason:
                          'Delivery acknowledgement was lost and no matching turn is in history; not replayed.');
                }
                continue;
              }
              final turn = matches.first;
              final ended = _ended[turn['id']];
              final status = ended?['status'] ?? turn['status'];
              final error = ended == null ? turn['error'] : ended['error'];
              row['turnId'] = turn['id'];
              row['turnStatus'] = status;
              if ((row['condition'] as Map)['jobId'] case final String jobId) {
                final job = await engine.get(jobId);
                if (job.type == 'agent.helper') {
                  await helpers?.shareCards(
                      job, row['threadId'] as String, turn['id'] as String);
                }
              }
              final attempts = row['attempts'] as int? ?? 0;
              if (status == 'inProgress') {
                if (row['state'] == 'dispatching') {
                  await _save(row, 'started', 'started');
                }
              } else if (status == 'failed' &&
                  _providerHiccup(error) &&
                  attempts < 5) {
                // The model never answered these facts; they still matter.
                final retryAt = DateTime.now()
                    .toUtc()
                    .add(Duration(minutes: 2 * (attempts + 1)));
                row['attempts'] = attempts + 1;
                row['failedTurns'] = [...failed, turn['id']];
                row['turnId'] = null;
                row['retryAt'] = retryAt.toIso8601String();
                await _save(row, 'ready', 'retrying',
                    reason:
                        'The model provider failed this turn; delivering again at ${row['retryAt']}.');
              } else {
                await _save(
                    row,
                    status == 'completed' ? 'completed' : 'execution_failed',
                    'finished',
                    reason: error == null
                        ? status == 'completed'
                            ? null
                            : 'Agent turn ended with status $status.'
                        : redactHarnessText(jsonEncode(error)));
              }
            } catch (error) {
              final reason = redactHarnessText(error.toString());
              if (row['reason'] != reason) {
                await _save(
                    row,
                    error is ChatRpcError
                        ? 'execution_failed'
                        : row['state'] as String,
                    error is ChatRpcError ? 'execution_failed' : 'pending',
                    reason: reason);
              }
            }
          }
        }
      });

  /// Errors that say the model provider was briefly unavailable (rate limits,
  /// server errors, a dropped stream), not that the turn itself went wrong.
  static bool _providerHiccup(Object? error) {
    if (error is! Map) return false;
    return RegExp(r'\b(429|5\d\d)\b|responseTooManyFailedAttempts|'
            r'httpConnectionFailed|responseStream|serverOverloaded|'
            r'internalServerError')
        .hasMatch(jsonEncode(error['codexErrorInfo'] ?? error['message']));
  }

  String _marker(JsonMap row) => '[NipaPlay followup ${row['id']}]';
  String _prompt(JsonMap row) => '${_marker(row)}\n'
      '这是宿主派发的新回合。说明和触发事实如下，下一步由你决定。\n'
      '登记来源：${row['origin']}\n登记说明：\n${row['instruction']}\n'
      '触发事实（任务终态不等于成功，请依据状态与回执判断）：\n${jsonEncode(row['trigger'])}';

  Future<void> close() async {
    _timer?.cancel();
    await _jobs?.cancel();
    await _chatEvents?.cancel();
    await _operations;
    _host = null;
  }
}
