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
import '../harness_hooks.dart' show HarnessHooks;
import '../harness_redaction.dart';
import '../state/views.dart' show publicTaskFacts;
import '../state/query.dart';

part 'download_returns.dart';
part 'library_arrivals.dart';
part 'program_returns.dart';
part 'user_task_returns.dart';

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
///
/// Nothing here polls. A sweep runs when something it waits on happened (a
/// task changed, the conversation host ended a turn or failed, an occurrence
/// was recorded, a followup was registered or arrived) or when a time it
/// waits for comes (one timer, at the earliest). A sweep reads the
/// followups still in play and the tasks that changed since the sweep
/// before; finished followups and tasks are found by key when a fact needs
/// them, never read whole.
final class Followups {
  Followups(this.database, this.engine, this.location) {
    // Changes are noted from the start, so the sweep after them looks at them.
    _jobs = engine.changes.listen((job) {
      _changed[job.jobId] = job;
      if (_started) _schedule();
    });
  }
  final Database database;
  final TaskEngine engine;
  final RepositoryLocation location;
  ChatHost? _host;

  /// The running conversation host; null while none is attached.
  ChatHost? get chatHost => _host;
  Helpers? helpers;
  void Function()? eventCommitted;
  String? Function()? agentDevice;
  Future<JsonMap> Function(String, JsonMap)? _deliverRemote;
  Future<JsonMap> Function(String, JsonMap)? get deliverRemote =>
      _deliverRemote;

  /// Rows held for a way to their device go once there is one.
  set deliverRemote(Future<JsonMap> Function(String, JsonMap)? value) {
    _deliverRemote = value;
    if (value != null && _started) _schedule();
  }

  /// Whether files entering the library are reported to Nipa; on when unset.
  bool Function()? libraryEnabled;

  /// The library's present facts about files that just entered, one per entry.
  Future<List<JsonMap>> Function(List<JsonMap> entries)? describeLibraryFiles;

  /// Starts a background helper that returns to no conversation. Defaults to
  /// [Helpers.dispatchBackground].
  Future<String> Function(
      {required String jobId,
      required String title,
      required String instruction})? backgroundDispatch;

  /// Files stop arriving for this long, or this long passes since the first,
  /// or the batch is full: the batch is delivered. A scan or sync ending
  /// delivers at once.
  Duration libraryQuiet = const Duration(seconds: 30);
  Duration libraryMaxWait = const Duration(minutes: 5);
  int libraryBatchLimit = 100;
  bool _libraryHeld = false;
  Future<JsonMap> turnProcess(String threadId, String turnId) async {
    await location.ready;
    final host = _host;
    if (host != null) return host.turnProcess(threadId, turnId);
    final saved = await TurnProcessStore.readSaved(
        File(database.path).parent, location.path, threadId, turnId);
    return {'found': saved != null, 'process': saved};
  }

  String _unavailable = 'Embedded chat host is not running.';
  late final StreamSubscription<Job> _jobs;
  StreamSubscription<ChatMessage>? _chatEvents;

  /// How turns actually ended, as the host reported them live: a thread
  /// read back from history can show a turn the provider failed as completed.
  final _ended = <String, Map>{};
  Future<void> _operations = Future.value();

  /// Tasks changed since a sweep last took them: the job as committed, or
  /// null when only its id is known (an occurrence about it was recorded).
  final _changed = <String, Job?>{};

  /// The next sweep looks at every task once, as after a start.
  bool _reconcile = true;

  /// Waiting rows already checked against every task once; after that a
  /// row only needs the tasks that changed.
  final _checked = <String>{};
  bool _started = false, _closed = false, _queued = false;

  /// The one timer: the earliest time a row waits for, or a retry after a
  /// failure that only trying again resolves.
  Timer? _wake;
  DateTime? _due;
  bool _retry = false;
  static const _retryDelay = Duration(seconds: 2);
  int _sweeps = 0, _decoded = 0;

  /// Sweeps run and stored followups decoded so far, for measuring what a
  /// sweep costs.
  int get sweeps => _sweeps;
  int get decoded => _decoded;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      // The caller receives the error; the next operation still gets its turn.
    });
    return result;
  }

  /// From now on task changes and due times sweep by themselves. The first
  /// sweep looks at every task once.
  void start() {
    _started = true;
    _schedule();
  }

  /// Asks for a sweep. At most one waits behind the one running; asking
  /// again before it starts is the same request.
  void _schedule() {
    if (_closed || _queued) return;
    _queued = true;
    unawaited(_serial(() {
      _queued = false;
      return _sweep();
    }).catchError((Object error, StackTrace stack) {
      // A sweep still running as the engine closes has nothing left to read.
      if (_engineClosed(error)) return;
      // Infrastructure failures are visible rather than dropping a condition.
      Zone.current.handleUncaughtError(error, stack);
    }));
  }

  static bool _engineClosed(Object error) =>
      error is Failure && error.message == 'Task engine is closed.';

  /// [at] is a time some row waits for: the timer wakes the sweep then.
  void _until(DateTime at) {
    final due = _due;
    if (due == null || at.isBefore(due)) _due = at;
  }

  void _arm() {
    _wake?.cancel();
    _wake = null;
    if (!_started || _closed) return;
    var at = _due;
    if (_retry) {
      final soon = DateTime.now().toUtc().add(_retryDelay);
      if (at == null || soon.isBefore(at)) at = soon;
    }
    if (at == null) return;
    // A millisecond late, so the sweep it wakes finds the time passed.
    final wait =
        at.difference(DateTime.now().toUtc()) + const Duration(milliseconds: 1);
    _wake = Timer(wait.isNegative ? Duration.zero : wait, _schedule);
  }

  /// Told whenever the conversation host comes, goes or is replaced (what
  /// else follows the host, such as delegated conversations).
  final chatListeners = <Future<void> Function(ChatHost?)>[];

  /// Why there is no conversation host, in a sentence; null while there is one.
  String? get unavailableReason =>
      _host != null && _host!.available ? null : _unavailable;

  Future<void> attach(ChatHost? host, {String? reason}) async {
    await _chatEvents?.cancel();
    _host = host;
    helpers?.attach(host);
    for (final listener in chatListeners) {
      try {
        await listener(host);
      } catch (_) {
        // What follows the host never keeps the host from being attached.
      }
    }
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
      // A turn ended, the host failed, or it came back with another model:
      // what waited for an idle host may go now.
      if (const {'turn/completed', 'host/error', 'host/modelChanged'}
          .contains(message['method'])) {
        _schedule();
      }
    });
    await sweep();
  }

  /// Completes once the work asked of this service so far is done.
  Future<void> settled() => _serial(() async {});

  JsonMap _decode(Map<String, Object?> row) {
    _decoded++;
    return jsonDecode(row['snapshot'] as String) as JsonMap;
  }

  Future<List<JsonMap>> _read(Future<List<Map<String, Object?>>> rows) async {
    final slice = _Slice();
    final result = <JsonMap>[];
    for (final row in await rows) {
      if (slice.due) await slice.breathe();
      result.add(_decode(row));
    }
    return result;
  }

  Future<List<JsonMap>> _rows() => _read(
      database.query('followups', columns: ['snapshot'], orderBy: 'rowid'));

  /// States a sweep acts on; the others are where a followup ends.
  static const _inPlay = ['waiting', 'ready', 'dispatching', 'started'];

  Future<List<JsonMap>> _active() => _read(database.query('followups',
      columns: ['snapshot'],
      where: 'state IN (?, ?, ?, ?)',
      whereArgs: _inPlay,
      orderBy: 'rowid'));

  Future<List<JsonMap>> list() async =>
      [for (final row in await _rows()) _public(row)];

  /// The followups that are not completed or cancelled, as [list] gives
  /// them: those still in play and deliveries that failed. Reads only those.
  Future<List<JsonMap>> activeList() async => [
        for (final row in await _read(database.query('followups',
            columns: ['snapshot'],
            where: 'state IN (?, ?, ?, ?, ?)',
            whereArgs: [..._inPlay, 'execution_failed'],
            orderBy: 'rowid')))
          _public(row)
      ];

  /// The followups registered for the end of task [jobId], oldest first.
  Future<List<JsonMap>> forJob(String jobId) async =>
      [for (final row in await _forJob(jobId)) _public(row)];

  Future<List<JsonMap>> _forJob(String jobId) =>
      _read(database.query('followups',
          columns: ['snapshot'],
          where: "json_extract(snapshot, '\$.condition.jobId') = ?",
          whereArgs: [jobId],
          orderBy: 'rowid'));

  static StateView viewForDatabase(Database database,
      {Future<List<JsonMap>> Function(Future<List<Map<String, Object?>>>)?
          decode}) {
    Future<List<JsonMap>> readRows(Future<List<Map<String, Object?>>> rows) =>
        decode != null
            ? decode(rows)
            : () async {
                final slice = _Slice();
                final result = <JsonMap>[];
                for (final row in await rows) {
                  if (slice.due) await slice.breathe();
                  result.add(jsonDecode(row['snapshot'] as String) as JsonMap);
                }
                return result;
              }();
    return StateView(
      name: 'followups',
      background: true,
      description:
          'Durable one-shot Agent followups. waiting awaits condition; ready awaits an idle chat host. '
          'execution_failed retains the delivery error; started/completed identify the actual thread and turn. '
          'waitingFor and title are suitable for progress UI.',
      fields: followupFields,
      read: (offset, limit) async => [
        for (final row in await readRows(database.query('followups',
            columns: ['snapshot'],
            orderBy: 'rowid',
            limit: limit,
            offset: offset)))
          {...row}..remove('hookCursor')
      ],
      readAll: () async => StateRows([
        for (final row in await readRows(database.query('followups',
            columns: ['snapshot'], orderBy: 'rowid')))
          {...row}..remove('hookCursor')
      ]),
    );
  }

  StateView get view => viewForDatabase(database, decode: _read);

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
    final result = switch (operation) {
      'main' => await host.getMainSession(),
      'new' => await host.newConversation(),
      'switch' => await host.switchSession(threadId!),
      _ => await host.listSessions(cursor: cursor),
    };
    // Another conversation is current: one that waited for a busy one may go.
    if (operation != 'list' && _started) _schedule();
    return result;
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
            ? await downloadReturnTarget(invocation)
            : null;
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

  Future<void> consumeHelperResult(String jobId, JsonMap taken) =>
      _serial(() async {
        for (final row in await _forJob(jobId)) {
          if ({'waiting', 'ready'}.contains(row['state'])) {
            row['consumedBy'] = taken;
            await _save(row, 'cancelled', 'consumed',
                origin: 'codex_native:wait',
                reason: 'Parent collected this result with wait.');
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
        if ((event == 'download.file_completed' ||
                event == 'download.stalled') &&
            (await database.query('followup_hook_events',
                    where: 'event=? AND object_id=?',
                    whereArgs: [event, objectId],
                    limit: 1))
                .isNotEmpty) {
          return;
        }
        await database.insert('followup_hook_events', {
          'event': event,
          'object_id': objectId,
          'payload': await redactAndEncodeHarnessJsonOffMain(payload),
        });
        if (event == 'download.stalled') _stallRecorded(payload);
        eventCommitted?.call();
        _schedule();
      });

  /// A download's stall goes back to its conversation once its event is
  /// recorded: that download is looked at again.
  void _stallRecorded(Map fact) {
    if ((fact['data'] as Map?)?['jobId'] case final String job) {
      _changed.putIfAbsent(job, () => null);
    }
  }

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

  Future<void> sweep() => _serial(_sweep);

  Future<void> _sweep() async {
    _sweeps++;
    _libraryHeld = false;
    _due = null;
    _retry = false;
    final reconcile = _reconcile;
    _reconcile = false;
    final changed = Map.of(_changed);
    _changed.clear();
    try {
      final tasks = _Tasks(engine, changed, reconcile);
      await _collectDownloadReturns(tasks);
      await _collectProgramReturns(tasks);
      await _collectUserTaskReturns(tasks);
      await _deliver(tasks);
    } catch (error) {
      // What this sweep took is looked at again by the next one.
      _reconcile = _reconcile || reconcile;
      for (final entry in changed.entries) {
        _changed.putIfAbsent(entry.key, () => entry.value);
      }
      if (!_engineClosed(error)) _retry = true;
      rethrow;
    } finally {
      _arm();
    }
  }

  /// What [row] waits for, if it happened. A row not checked before looks
  /// at every task once; after that, at the tasks that changed.
  Future<JsonMap?> _occurred(JsonMap row, _Tasks tasks,
      {required bool fresh}) async {
    final condition = row['condition'] as Map;
    if (condition['jobId'] case final String id) {
      if (!fresh && !tasks.changed.containsKey(id)) return null;
      final job = await engine.get(id);
      if (!job.state.isTerminal) return null;
      return {
        'kind': 'task.terminal',
        'occurredAt': job.updatedAt.toIso8601String(),
        ...publicTaskFacts(job.toJson()),
      };
    }
    final matches = await database.query('followup_hook_events',
        where:
            'sequence>? AND event=?${condition['objectId'] == null ? '' : condition['event'] == 'download.stalled' ? " AND (object_id=? OR json_extract(payload,'\$.data.jobId')=?)" : ' AND object_id=?'}'
            '${condition['event'] == 'download.file_completed' ? " AND json_extract(payload,'\$.occurredAt')>=?" : ""}',
        whereArgs: [
          row['hookCursor'],
          condition['event'],
          if (condition['objectId'] != null) condition['objectId'],
          if (condition['objectId'] != null &&
              condition['event'] == 'download.stalled')
            condition['objectId'],
          if (condition['event'] == 'download.file_completed') row['createdAt']
        ],
        orderBy: 'sequence',
        limit: 1);
    if (matches.isNotEmpty) {
      return jsonDecode(matches.single['payload'] as String) as JsonMap;
    }
    final event = condition['event'];
    if (!const {
      'download.file_completed',
      'download.stalled',
      'download.completed'
    }.contains(event)) {
      return null;
    }
    final downloads =
        fresh ? await tasks.allDownloads() : await tasks.changedDownloads();
    final slice = _Slice();
    // Download completion can be reconstructed from the persisted task.
    if (event == 'download.file_completed') {
      for (final job in downloads) {
        if (slice.due) await slice.breathe();
        for (final file in (job.checkpoint['completedFiles'] as List? ?? [])
            .cast<JsonMap>()) {
          final objectId = file['objectId'] as String;
          if (file['verification'] != 'verified' ||
              condition['objectId'] != null &&
                  condition['objectId'] != objectId ||
              DateTime.parse(file['completedAt'] as String)
                  .isBefore(DateTime.parse(row['createdAt'] as String))) {
            continue;
          }
          return {
            'event': 'download.file_completed',
            'objectId': objectId,
            'occurredAt': file['completedAt'],
            'data': {
              'jobId': file['jobId'],
              'infoHash': job.input['infoHash'],
              'backend': job.details['backend'],
              'file': file
            }
          };
        }
      }
    }
    // A stall persisted before its event was published.
    if (event == 'download.stalled') {
      for (final job in downloads) {
        if (slice.due) await slice.breathe();
        if (job.state.isTerminal) continue;
        for (final stall
            in (job.checkpoint['stalls'] as List? ?? []).cast<Map>()) {
          final objectId =
              HarnessHooks.stallObjectId(job.jobId, stall['index']);
          if (stall['resumedAt'] != null ||
              condition['objectId'] != null &&
                  condition['objectId'] != objectId &&
                  condition['objectId'] != job.jobId ||
              DateTime.parse(stall['at'] as String)
                  .isBefore(DateTime.parse(row['createdAt'] as String))) {
            continue;
          }
          return {
            'event': 'download.stalled',
            'objectId': objectId,
            'occurredAt': stall['at'],
            'data': {
              'jobId': job.jobId,
              'infoHash': job.input['infoHash'],
              'title': job.title,
              ...Map<String, Object?>.from(stall)
                ..remove('index')
                ..remove('resumedAt'),
            }
          };
        }
      }
    }
    if (event == 'download.completed') {
      for (final job in downloads) {
        if (job.state != JobState.succeeded) continue;
        if (condition['objectId'] != null &&
            condition['objectId'] != job.jobId) {
          continue;
        }
        if (job.updatedAt
            .isBefore(DateTime.parse(row['createdAt'] as String))) {
          continue;
        }
        return {
          'event': 'download.completed',
          'objectId': job.jobId,
          'occurredAt': job.updatedAt.toIso8601String(),
          'data': publicTaskFacts(job.toJson())
        };
      }
    }
    return null;
  }

  Future<void> _deliver(_Tasks tasks) async {
    final rows = await _active();
    _checked.retainAll({
      for (final row in rows)
        if (row['state'] == 'waiting') row['id']
    });
    // Resolve one-shot subscriptions before deciding which facts they own.
    for (final row in [
      ...rows.where((row) => row['automatic'] != 'download'),
      ...rows.where((row) => row['automatic'] == 'download'),
    ]) {
      if (row['state'] == 'waiting') {
        final id = row['id'] as String;
        final trigger =
            await _occurred(row, tasks, fresh: !_checked.contains(id));
        _checked.add(id);
        if (trigger == null) continue;
        row['trigger'] = redactHarnessJson(trigger);
        await _save(row, 'ready', 'triggered',
            reason: 'Waiting for an idle chat host.');
      }
      final host = _host;
      if (row['state'] == 'ready') {
        if (row['automatic'] == 'library' && !await _libraryGate(row)) {
          continue;
        }
        if (_taskReturn(row)) {
          await _filterDownloadReturn(row);
          if (row['state'] == 'cancelled') continue;
          final due = DateTime.parse(row['deliverAfter'] as String);
          if (DateTime.now().toUtc().isBefore(due)) {
            _until(due);
            final reason =
                'Batching download facts until ${row['deliverAfter']}.';
            if (row['reason'] != reason) {
              await _save(row, 'ready', 'pending', reason: reason);
            }
            continue;
          }
        }
        if (row['remoteDeviceId'] case final String peer) {
          final retryAt = row['remoteRetryAt'] as String?;
          if (retryAt != null &&
              DateTime.now().toUtc().isBefore(DateTime.parse(retryAt))) {
            _until(DateTime.parse(retryAt));
            continue;
          }
          final deliver = _deliverRemote;
          if (deliver == null) continue;
          try {
            if (row['remoteSealed'] != true) {
              row['remoteSealed'] = true;
              await _save(row, 'ready', 'sealed');
            }
            row['remoteReceipt'] = await deliver(peer, row);
            row['dispatchedAt'] = DateTime.now().toUtc().toIso8601String();
            row['deliveryState'] = 'forwarded';
            await _save(row, 'completed', 'forwarded',
                reason:
                    'Destination durably accepted this delivery; its conversation state is owned there.');
          } on Failure catch (error) {
            final retry =
                DateTime.now().toUtc().add(const Duration(seconds: 30));
            row['remoteRetryAt'] = retry.toIso8601String();
            _until(retry);
            await _save(row, 'ready', 'pending', reason: error.message);
          }
          continue;
        }
        if (row['retryAt'] case final String retryAt
            when DateTime.now().toUtc().isBefore(DateTime.parse(retryAt))) {
          _until(DateTime.parse(retryAt));
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
          // A running turn takes the facts at its next step instead of
          // making them wait for its end.
          if (host != null &&
              host.available &&
              host.busy &&
              host.repository.path == row['repository'] &&
              await _steerIntoTurn(row, host)) {
            continue;
          }
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
                  origin: 'codex_native:wait',
                  reason: 'Parent collected this result with wait.');
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
              await helpers?.shareCards(job, target, row['turnId'] as String);
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
          final thread = await host.readThread(row['threadId'] as String,
              withProcess: false);
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
            _until(retryAt);
            await _save(row, 'ready', 'retrying',
                reason:
                    'The model provider failed this turn; delivering again at ${row['retryAt']}.');
          } else if (row['steered'] == true &&
              status != 'completed' &&
              !(turn['items'] as List).cast<Map>().any((item) =>
                  item['type'] == 'userMessage' &&
                  jsonEncode(item['content']).contains(_marker(row)))) {
            // Put into a turn that ended before reading it (an interrupt
            // clears what was waiting): nobody saw these facts yet.
            row
              ..remove('steered')
              ..['turnId'] = null
              ..['turnStatus'] = null
              ..['failedTurns'] = [...failed, turn['id']];
            await _save(row, 'ready', 'pending',
                reason: 'The turn ended before it read these facts.');
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
          // A failure that left the row as it was is tried again shortly.
          if (error is! ChatRpcError) _retry = true;
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
  }

  /// Delivers [row] into the turn now running on its conversation, as the same
  /// text a new turn would have opened with. True when the row is dealt with
  /// (taken into the turn, or left for reconciliation after an unknown
  /// outcome); false when it must wait for the turn to end as before.
  ///
  /// The turn then owns the row exactly as it would own a turn it opened:
  /// `started` with that turnId, and once the host is idle again the ordinary
  /// reconciliation reads the turn and completes the row (or redelivers it
  /// when the provider failed that turn). Nothing is sent a second time:
  /// the row is `dispatching` before the text leaves, sweeps are serialized,
  /// and the host only reports a turn when the runner took the text.
  Future<bool> _steerIntoTurn(JsonMap row, ChatHost host) async {
    if (host.dsh == null) return false;
    // A helper result the parent already collected is recorded by the idle path.
    if ((row['condition'] as Map)['jobId'] case final String jobId) {
      final job = await engine.get(jobId);
      if (await helpers?.nativeResultTaken(job, host) != null) return false;
    }
    final target =
        row['threadId'] as String? ?? host.mainThreadId ?? host.threadId;
    if (target == null || !host.busyFor(target)) return false;
    final before = {
      for (final key in ['threadId', 'dispatchedAt']) key: row[key]
    };
    row['threadId'] = target;
    if (_taskReturn(row)) {
      row['dispatchedAt'] = DateTime.now().toUtc().toIso8601String();
    }
    await _save(row, 'dispatching', 'dispatching');
    try {
      final turnId = await host.steerFollowup(target, _prompt(row));
      if (turnId == null) {
        for (final entry in before.entries) {
          if (entry.value == null) {
            row.remove(entry.key);
          } else {
            row[entry.key] = entry.value;
          }
        }
        await _save(row, 'ready', 'pending',
            reason: 'Chat host has an active turn; waiting until idle.');
        return false;
      }
      row['turnId'] = turnId;
      row['turnStatus'] = 'inProgress';
      row['steered'] = true;
      if ((row['condition'] as Map)['jobId'] case final String jobId) {
        final job = await engine.get(jobId);
        if (job.type == 'agent.helper') {
          await helpers?.shareCards(job, target, turnId);
        }
      }
      await _save(row, 'started', 'started',
          origin: 'harness_cli:chat:${host.sessionId}');
    } catch (error) {
      // The runner may have taken the text before the answer was lost:
      // reconcile from history instead of sending it again.
      await _save(row, 'dispatching', 'execution_failed',
          reason: redactHarnessText(error.toString()));
    }
    return true;
  }

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

  /// Next's interface is closed: no sweeps until [start] again. Task
  /// changes are still noted, so the first sweep after it looks at them.
  Future<void> pause() async {
    _started = false;
    _wake?.cancel();
    _wake = null;
    await _operations;
  }

  Future<void> close() async {
    _closed = true;
    _wake?.cancel();
    await _jobs.cancel();
    await _chatEvents?.cancel();
    await _operations;
    _wake?.cancel();
    _host = null;
  }

  /// Ids already among followups, of [ids].
  Future<Set<String>> _existing(List<String> ids) async => {
        for (final chunk in _chunks(ids))
          for (final row in await database.query('followups',
              columns: ['id'],
              where: 'id IN (${_marks(chunk.length)})',
              whereArgs: chunk))
            row['id'] as String
      };

  /// Of [objects], those some followup already reported as [kind]
  /// (see followup_objects).
  Future<Set<String>> _reported(String kind, Iterable<String> objects) async =>
      {
        for (final chunk in _chunks(objects.toSet().toList()))
          for (final row in await database.rawQuery(
              'SELECT DISTINCT object FROM followup_objects '
              'WHERE kind = ? AND object IN (${_marks(chunk.length)})',
              [kind, ...chunk]))
            row['object'] as String
      };

  /// The followups that reported any of [objects] as [kind].
  Future<List<JsonMap>> _reporting(
      String kind, Iterable<String> objects) async {
    final rows = <String, JsonMap>{};
    for (final chunk in _chunks(objects.toSet().toList())) {
      for (final row in await _read(database.rawQuery(
          'SELECT snapshot FROM followups WHERE id IN (SELECT followup_id '
          'FROM followup_objects WHERE kind = ? AND object IN (${_marks(chunk.length)}))',
          [kind, ...chunk]))) {
        rows[row['id'] as String] = row;
      }
    }
    return rows.values.toList();
  }
}

/// SQLite takes a bounded number of parameters per statement.
Iterable<List<T>> _chunks<T>(List<T> items, [int size = 400]) sync* {
  for (var start = 0; start < items.length; start += size) {
    yield items.sublist(start, min(start + size, items.length));
  }
}

String _marks(int count) => List.filled(count, '?').join(', ');

/// The tasks one sweep looks at: every task once after a start, otherwise
/// those that changed since the sweep before, as stored now.
final class _Tasks {
  _Tasks(this.engine, this.changed, this.all);
  final TaskEngine engine;
  final Map<String, Job?> changed;

  /// This sweep reconciles: it looks at every task.
  final bool all;
  final _stored = <String, Job?>{};
  List<Job>? _allDownloads, _changedDownloads;

  /// [id] as stored now; null when there is no such task.
  Future<Job?> stored(String id) async {
    if (_stored.containsKey(id)) return _stored[id];
    Job? job;
    try {
      job = await engine.get(id);
    } on Failure catch (error) {
      if (error.code != FailureCode.notFound) rethrow;
    }
    return _stored[id] = job;
  }

  /// The changed tasks [wanted] keeps, as stored now, in the order the
  /// engine lists tasks. [wanted] first sees the change itself, when it is
  /// known, so a change that cannot matter costs no read.
  Future<List<Job>> changedWhere(bool Function(Job job) wanted) async {
    final jobs = <Job>[];
    for (final entry in changed.entries) {
      if (entry.value case final job? when !wanted(job)) continue;
      final job = await stored(entry.key);
      if (job != null && wanted(job)) jobs.add(job);
    }
    return jobs
      ..sort((a, b) {
        final at = a.createdAt.compareTo(b.createdAt);
        return at != 0 ? at : a.jobId.compareTo(b.jobId);
      });
  }

  Future<List<Job>> allDownloads() async =>
      _allDownloads ??= await engine.list(type: 'download');

  Future<List<Job>> changedDownloads() async =>
      _changedDownloads ??= await changedWhere((job) => job.type == 'download');

  /// Tasks of [types], in the order the engine lists them: every one when
  /// reconciling, else the changed ones.
  Future<List<Job>> ofTypes(
      List<String> types, bool Function(Job) wanted) async {
    if (!all) {
      final jobs =
          await changedWhere((job) => types.contains(job.type) && wanted(job));
      // The engine lists per type; within a type, by creation.
      return [
        for (final type in types) ...jobs.where((job) => job.type == type)
      ];
    }
    return [
      for (final type in types)
        for (final job in type == 'download'
            ? await allDownloads()
            : await engine.list(type: type))
          if (wanted(job)) job
    ];
  }
}

/// Gives the event loop a turn once [budget] of work ran without one, so a
/// long pass never holds the isolate for longer than about that.
final class _Slice {
  static const budget = Duration(milliseconds: 2);
  final _clock = Stopwatch()..start();
  bool get due => _clock.elapsed >= budget;
  Future<void> breathe() async {
    await Future<void>.delayed(Duration.zero);
    _clock.reset();
  }
}
