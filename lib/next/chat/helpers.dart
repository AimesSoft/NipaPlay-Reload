import 'dart:async';
import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import '../followups/service.dart';
import '../harness_redaction.dart';
import '../state/change_history.dart';
import 'chat_host.dart';

part 'native_helpers.dart';

/// Capacity and receipts, with no policy about which work to delegate.
final class Helpers implements JobExecutor {
  static const limit = 2;
  @override
  String get type => 'agent.helper';
  late TaskEngine engine;
  late Followups followups;
  ChatHost? host;
  late final _native = _NativeHelpers(this);
  Future<Map?> nativeResultTaken(Job job, ChatHost chat) =>
      _native.taken(job, chat);
  final _slots = <String>{};
  Completer<void> _attachment = Completer<void>();

  void attach(ChatHost? value) {
    host = value;
    _attachment.complete();
    _attachment = Completer<void>();
    _native.attach(value);
  }

  Future<JsonMap> delegate(JsonMap input, Invocation invocation) async {
    final chat = host;
    if (chat == null || !chat.available) {
      throw const Failure(FailureCode.unavailable, 'Chat host is not running.');
    }
    final parent = input['threadId'] as String? ??
        chat.threadForOrigin(invocation.origin) ??
        chat.mainThreadId;
    if (parent == null) {
      throw const Failure(FailureCode.unavailable, 'No return conversation.');
    }
    await chat.readThread(parent);
    final safe = publicHarnessFacts(input) as JsonMap;
    final job =
        await engine.submit(type: type, title: safe['title'] as String, input: {
      ...safe,
      'parentThreadId': parent,
      'parentTurnId': chat.livenessFor(parent).turnId,
      'repository': chat.repository.path,
      'origin': invocation.origin,
      'invocationId': invocation.id
    }, details: {
      'source': 'host',
      'parentThreadId': parent,
      'currentActivity': '等待帮手接手'
    });
    await _returnFor(job);
    return {'jobId': job.jobId, 'parentThreadId': parent, 'helperLimit': limit};
  }

  Future<void> _returns = Future.value();
  Future<void> _returnFor(Job job) {
    final result = _returns.then((_) => _registerReturn(job));
    _returns = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  Future<void> _registerReturn(Job job) async {
    if ((await followups.list()).any((row) =>
        (row['condition'] as Map)['jobId'] == job.jobId &&
        row['instruction'] == '帮手已结束，请根据它的结果回应用户。')) return;
    await followups.register(
        {
          'when': {'jobId': job.jobId},
          'threadId': job.input['parentThreadId'],
          'title': job.title,
          'instruction': '帮手已结束，请根据它的结果回应用户。',
        },
        Invocation(
            origin: job.input['source'] == 'codexNative'
                ? 'codex_native:${job.input['threadId']}'
                : 'harness_cli:helper:${job.jobId}'));
  }

  Future<JsonMap> report(JsonMap input, Invocation invocation) async {
    final id = input['jobId'] as String? ??
        (invocation.origin.startsWith('harness_cli:helper:')
            ? invocation.origin.substring('harness_cli:helper:'.length)
            : null);
    final context = id == null ? null : _contexts[id];
    if (context == null || invocation.origin != 'harness_cli:helper:$id') {
      throw const Failure(FailureCode.conflict,
          'Only the running helper can report its current activity.');
    }
    await context.report(details: {
      ...context.job.details,
      'currentActivity':
          (publicHarnessFacts({'currentActivity': input['currentActivity']})
              as Map)['currentActivity']
    });
    return {'jobId': id};
  }

  final _contexts = <String, JobContext>{};
  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) => _run(context);

  Future<void> _run(JobContext context) async {
    if (context.job.input['source'] == 'codexNative') {
      await _native.run(context);
      return;
    }
    final job = context.job;
    final chat = host;
    await _returnFor(job);
    if (job.cancelRequestedAt != null && job.checkpoint['threadId'] == null) {
      await context.cancelled(_receipt({'summary': '帮手任务已停止'}));
      return;
    }
    final pending = (await engine.list(type: type))
        .where((j) =>
            j.input['repository'] == job.input['repository'] &&
            !j.state.isTerminal &&
            j.state != JobState.paused &&
            !_slots.contains(j.jobId))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (chat == null ||
        !chat.available ||
        chat.repository.path != job.input['repository'] ||
        _slots.length >= limit ||
        pending.firstOrNull?.jobId != job.jobId) {
      await context.retryAt(
          DateTime.now().toUtc().add(const Duration(seconds: 2)),
          const Failure(FailureCode.unavailable, 'Waiting for a helper slot.'),
          checkpoint: job.checkpoint);
      return;
    }
    _slots.add(job.jobId);
    _contexts[job.jobId] = context;
    final detached = _attachment.future;
    StreamSubscription<ChatMessage>? subscription;
    try {
      if (context.job.state == JobState.interrupted) {
        await context.running(phase: 'working');
      }
      final id = await chat.helperThread(job.jobId, job.title,
          resumeId: job.checkpoint['threadId'] as String?);
      await context.report(phase: 'working', checkpoint: {
        ...job.checkpoint,
        'threadId': id
      }, details: {
        ...job.details,
        'threadId': id,
        'startedAt': job.details['startedAt'] ??
            DateTime.now().toUtc().toIso8601String(),
        'currentActivity': '帮手正在处理'
      });
      ChatMessage? turn;
      if (job.checkpoint['threadId'] != null) {
        final history = await chat.readThread(id);
        turn = (history['turns'] as List)
            .cast<ChatMessage>()
            .where((t) => (t['items'] as List).cast<Map>().any((item) =>
                item['type'] == 'userMessage' &&
                jsonEncode(item['content'])
                    .contains('[NipaPlay helper ${job.jobId}]')))
            .lastOrNull;
      }
      final ended = Completer<ChatMessage>();
      subscription = chat.events.listen((message) {
        if (message['method'] == 'turn/completed' &&
            message['params']['threadId'] == id &&
            !ended.isCompleted) {
          ended.complete(
              Map<String, dynamic>.from(message['params']['turn'] as Map));
        }
        if (message['method'] == 'host/error' && !ended.isCompleted) {
          ended.completeError(
              StateError(message['params']['message'] as String));
        }
      });
      if (turn == null) {
        // Record the dispatch intent before RPC. On recovery, history supplies
        // the acknowledgement; a missing acknowledgement is never replayed.
        if (job.checkpoint['dispatched'] == true) {
          throw StateError(
              'Helper acknowledgement lost; no matching turn in history.');
        }
        if (context.job.cancelRequestedAt != null) {
          await context
              .cancelled(_receipt({'threadId': id, 'summary': '帮手任务已停止'}));
          return;
        }
        await context.report(
            checkpoint: {...context.job.checkpoint, 'dispatched': true});
        turn = Map<String, dynamic>.from((await chat.startThreadTurn(id,
                '[NipaPlay helper ${job.jobId}]\n${job.input['instruction']}'))[
            'turn'] as Map);
      }
      await context.report(
          checkpoint: {...context.job.checkpoint, 'turnId': turn['id']},
          details: {...context.job.details, 'turnId': turn['id']});
      if (turn['status'] == 'inProgress') {
        final event = await Future.any<Object>([
          ended.future,
          context.stopRequested.then((_) => 'stop'),
          detached.then((_) => 'detached'),
        ]);
        if (event == 'detached') {
          await context.retryAt(
              DateTime.now().toUtc().add(const Duration(seconds: 2)),
              const Failure(FailureCode.unavailable, 'Chat host was detached.'),
              checkpoint: context.job.checkpoint);
          return;
        }
        if (event == 'stop') {
          if (chat.busyFor(id)) await chat.interrupt(onThread: id);
          final current = await context.snapshot();
          if (current.state == JobState.paused) return;
          turn = await ended.future;
        } else {
          turn = event as ChatMessage;
        }
      }
      final history = await chat.readThread(id);
      final completed = (history['turns'] as List)
          .cast<Map>()
          .firstWhere((t) => t['id'] == turn!['id']);
      final messages = (completed['items'] as List)
          .cast<Map>()
          .where((i) => i['type'] == 'agentMessage')
          .map((i) => i['text'] as String);
      final text = messages.join('\n');
      final summary = text.isNotEmpty
          ? text
          : context.job.cancelRequestedAt != null
              ? '帮手任务已停止'
              : turn['status'] == 'completed'
                  ? '帮手已完成这一轮'
                  : '帮手这一轮未能完成';
      final receipt = _receipt({
        'threadId': id,
        'turnId': turn['id'],
        'turnStatus': turn['status'],
        'summary':
            summary.length > 8192 ? '${summary.substring(0, 8192)}…' : summary,
        'resultVerification': 'unverified'
      },
          verification: turn['status'] == 'completed'
              ? VerificationLevel.verified
              : VerificationLevel.unverified);
      await context.report(details: {
        ...context.job.details,
        'currentActivity': turn['status'] == 'completed' ? '帮手已完成' : '帮手已结束',
        'summary': receipt.details['summary']
      });
      if (context.job.cancelRequestedAt != null) {
        await context.cancelled(receipt);
      } else if (turn['status'] == 'completed') {
        await context.succeed(receipt);
      } else {
        await context.fail(
            Failure(FailureCode.unavailable,
                'Helper turn ended: ${turn['status']}'),
            receipt);
      }
    } finally {
      await subscription?.cancel();
      _contexts.remove(job.jobId);
      _slots.remove(job.jobId);
    }
  }

  JobReceipt _receipt(JsonMap details,
          {VerificationLevel verification = VerificationLevel.unverified}) =>
      JobReceipt(
          verification: verification,
          details: publicHarnessFacts(details) as JsonMap);

  Future<void> shareCards(
      Job job, String parentThread, String parentTurn) async {
    final db = followups.database;
    await db.transaction((tx) async {
      final cards = await tx.query('ui_presentations',
          where: 'thread_id=?', whereArgs: [job.checkpoint['threadId']]);
      for (final card in cards) {
        final origin = 'helper-result:${job.jobId}:${card['id']}';
        if ((await tx.query('ui_presentations',
                where: 'origin=?', whereArgs: [origin]))
            .isNotEmpty) continue;
        await tx.insert(
            'ui_presentations',
            {...card}
              ..remove('id')
              ..['thread_id'] = parentThread
              ..['turn_id'] = parentTurn
              ..['origin'] = origin);
      }
    });
  }
}
