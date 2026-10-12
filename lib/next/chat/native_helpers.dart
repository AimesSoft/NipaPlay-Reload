part of 'helpers.dart';

final class _NativeHelpers {
  _NativeHelpers(this.helpers);
  final Helpers helpers;
  StreamSubscription<ChatMessage>? _events;
  Future<void> _operations = Future.value();
  final _parents = <String, String>{};
  final _firstTurns = <String, String>{};

  void _schedule(Future<void> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      Zone.current.handleUncaughtError(error, stack);
    });
  }

  void attach(ChatHost? chat) {
    unawaited(_events?.cancel());
    _events = chat?.events.listen((message) {
      if (message['method'] == 'item/completed') {
        final params = message['params'] as Map;
        final item = params['item'] as Map;
        if (item['type'] == 'collabAgentToolCall' &&
            item['status'] == 'completed') {
          final turns = <String, String?>{
            for (final child in item['receiverThreadIds'] as List)
              child as String: chat.livenessFor(child).turnId
          };
          _schedule(() => _collaboration(chat, params, item, turns));
        }
      }
      if (message['method'] == 'turn/started') {
        final params = message['params'] as Map;
        final child = params['threadId'] as String;
        _firstTurns.putIfAbsent(child, () => params['turn']['id'] as String);
        _schedule(() async {
          if (_parents[child] case final parent?) {
            await _adopt(chat, child, parent,
                turnId: params['turn']['id'] as String);
          }
        });
      }
    });
    if (chat != null) _schedule(() => _restore(chat));
  }

  Future<void> _restore(ChatHost chat) async {
    String? cursor;
    do {
      if (helpers.host != chat || !chat.available) return;
      final page = await chat
          .listThreads(cursor: cursor, sourceKinds: ['subAgentThreadSpawn']);
      for (final thread in (page['data'] as List).cast<Map>()) {
        final parent = thread['parentThreadId'] as String;
        final history = await chat.readThread(thread['id'] as String);
        final first = (history['turns'] as List).cast<Map>().firstOrNull;
        if (first != null) {
          _firstTurns.putIfAbsent(
              thread['id'] as String, () => first['id'] as String);
        }
        final latest = (history['turns'] as List).cast<Map>().lastOrNull;
        await _adopt(chat, thread['id'] as String, parent,
            prompt: thread['preview'] as String,
            turnId: latest?['id'] as String?);
      }
      cursor = page['nextCursor'] as String?;
    } while (cursor != null);
  }

  Future<void> _collaboration(
      ChatHost chat, Map params, Map item, Map<String, String?> turns) async {
    if (helpers.host != chat) return;
    final parent = item['senderThreadId'] as String;
    if (item['tool'] == 'spawnAgent') {
      for (final child in (item['receiverThreadIds'] as List).cast<String>()) {
        await _adopt(chat, child, parent,
            prompt: item['prompt'] as String?,
            parentTurnId: params['turnId'] as String);
      }
    }
    if (item['tool'] == 'wait') {
      for (final job in await helpers.engine.list(type: helpers.type)) {
        final child = job.input['threadId'];
        final state = (item['agentsStates'] as Map)[child] as Map?;
        if (job.input['source'] == 'codexNative' &&
            job.input['parentThreadId'] == parent &&
            state?['status'] == 'completed' &&
            state?['message'] != null &&
            turns[child] ==
                (job.checkpoint['turnId'] ??
                    job.input['turnId'] ??
                    turns[child])) {
          await helpers.followups.consumeHelperResult(job.jobId, {
            'threadId': parent,
            'turnId': params['turnId'],
            'itemId': item['id'],
            'helperTurnId': turns[child]
          });
        }
      }
    }
  }

  String _sentence(String text, int limit) {
    final sentence = text.trim().split(RegExp(r'[\n。！？]')).first.trim();
    return sentence.length > limit
        ? '${sentence.substring(0, limit)}…'
        : sentence;
  }

  Future<void> _adopt(ChatHost chat, String child, String parent,
      {String? prompt, String? turnId, String? parentTurnId}) async {
    if (helpers.host != chat) return;
    _parents[child] = parent;
    final existing = (await helpers.engine.list(type: helpers.type))
        .where((job) =>
            job.input['source'] == 'codexNative' &&
            job.input['repository'] == chat.repository.path &&
            job.input['threadId'] == child)
        .toList();
    if (existing.any((job) =>
        turnId == null ||
        (!job.state.isTerminal &&
            job.checkpoint['turnId'] == null &&
            job.input['turnId'] == null &&
            turnId == _firstTurns[child]) ||
        (job.checkpoint['turnId'] ?? job.input['turnId']) == turnId)) {
      return;
    }
    final title = _sentence(prompt ?? existing.lastOrNull?.title ?? '后台帮手', 48);
    final history = await chat.readThread(parent);
    final previousWaitIds = [
      for (final turn in (history['turns'] as List).cast<Map>())
        for (final item in (turn['items'] as List).cast<Map>())
          if (item['type'] == 'collabAgentToolCall' && item['tool'] == 'wait')
            item['id']
    ];
    final job = await runZoned(
        () => helpers.engine.submit(
                type: helpers.type,
                jobId:
                    'native-helper-$child${turnId == null ? '' : '-$turnId'}',
                title: title.isEmpty ? '后台帮手' : title,
                sideEffectCommitted: true,
                input: publicHarnessFacts({
                  'source': 'codexNative',
                  'previousWaitIds': previousWaitIds,
                  'observedSessionId': chat.sessionId,
                  'threadId': child,
                  'parentThreadId': parent,
                  'parentTurnId': parentTurnId,
                  'turnId': turnId,
                  'repository': chat.repository.path,
                  'origin': 'codex_native:$child'
                }) as JsonMap,
                details: {
                  'source': 'codexNative',
                  'threadId': child,
                  'parentThreadId': parent,
                  'currentActivity': '帮手正在接手'
                }),
        zoneValues: {
          BodyChanges.invocationKey: Invocation(origin: 'codex_native:$child')
        });
    chat.threadOrigins[child] = 'codex_native:$child';
    await helpers._returnFor(job);
  }

  Future<Map?> taken(Job job, ChatHost chat) async {
    if (job.input['source'] != 'codexNative') return null;
    final history =
        await chat.readThread(job.input['parentThreadId'] as String);
    final finished = job.receipt?.details['completedAt'] as int?;
    for (final turn in (history['turns'] as List).cast<Map>()) {
      if (turn['completedAt'] == null ||
          finished == null ||
          (turn['completedAt'] as int) < finished) {
        continue;
      }
      for (final item in (turn['items'] as List).cast<Map>()) {
        if (item['type'] != 'collabAgentToolCall' ||
            item['tool'] != 'wait' ||
            item['status'] != 'completed' ||
            (job.input['previousWaitIds'] as List).contains(item['id'])) {
          continue;
        }
        final state =
            (item['agentsStates'] as Map)[job.input['threadId']] as Map?;
        if (state?['status'] == 'completed' &&
            state?['message'] != null &&
            state!['message'] == job.receipt?.details['summary']) {
          return {
            'threadId': history['id'],
            'turnId': turn['id'],
            'itemId': item['id'],
            'helperTurnId': job.checkpoint['turnId']
          };
        }
      }
    }
    return null;
  }

  Future<void> run(JobContext context) async {
    await helpers._returnFor(context.job);
    final chat = helpers.host;
    if (chat == null ||
        !chat.available ||
        chat.repository.path != context.job.input['repository']) {
      await context.retryAt(
          DateTime.now().toUtc().add(const Duration(seconds: 2)),
          const Failure(FailureCode.unavailable, 'Chat host is not attached.'),
          checkpoint: context.job.checkpoint);
      return;
    }
    if (context.job.state == JobState.interrupted) {
      await context.running(phase: 'working');
    }
    final child = context.job.input['threadId'] as String;
    chat.threadOrigins[child] = 'codex_native:$child';
    final detached = helpers._attachment.future;
    var changed = Completer<void>();
    final subscription = chat.events.listen((message) {
      if (message['params']?['threadId'] == child &&
          const {'turn/started', 'turn/completed'}
              .contains(message['method']) &&
          !changed.isCompleted) {
        changed.complete();
      }
    });
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!changed.isCompleted) changed.complete();
    });
    String? activity;
    String? activityItemId;
    var activityText = StringBuffer();
    final activitySubscription = chat.events.listen((message) {
      if (message['method'] == 'item/agentMessage/delta' &&
          message['params']['threadId'] == child) {
        final params = message['params'] as Map;
        if (activityItemId != params['itemId']) {
          activityItemId = params['itemId'] as String;
          activityText = StringBuffer();
        }
        activityText.write(params['delta']);
        activity = _sentence(activityText.toString(), 160);
      }
      if (message['method'] == 'item/completed' &&
          message['params']['threadId'] == child) {
        final item = message['params']['item'] as Map;
        if (item['type'] == 'agentMessage') {
          activity = _sentence(item['text'] as String, 160);
        } else if (item['type'] == 'commandExecution') {
          activity = '帮手正在查询和整理';
        }
      }
    });
    try {
      while (true) {
        final change = changed.future;
        final initializing =
            context.job.input['observedSessionId'] == chat.sessionId &&
                context.job.checkpoint['turnId'] == null &&
                chat.livenessFor(child).turnId == null;
        final history = initializing ? null : await chat.readThread(child);
        final turns = (history?['turns'] as List? ?? []).cast<Map>();
        final target = context.job.checkpoint['turnId'] ??
            context.job.input['turnId'] ??
            _firstTurns[child];
        final turn = target == null
            ? turns.firstOrNull
            : turns.where((turn) => turn['id'] == target).firstOrNull;
        if (turn != null) {
          final started = turn['startedAt'] as int?;
          await context.report(phase: 'working', checkpoint: {
            ...context.job.checkpoint,
            'threadId': child,
            'turnId': turn['id']
          }, details: {
            ...context.job.details,
            if (started != null)
              'startedAt': DateTime.fromMillisecondsSinceEpoch(started * 1000,
                      isUtc: true)
                  .toIso8601String(),
            'currentActivity':
                activity ?? context.job.details['currentActivity'] ?? '帮手正在处理'
          });
          if (turn['status'] != 'inProgress') {
            final finalMessages = (turn['items'] as List).cast<Map>().where(
                (item) =>
                    item['type'] == 'agentMessage' &&
                    item['phase'] != 'commentary');
            final summary = finalMessages.lastOrNull?['text'] as String? ??
                (context.job.cancelRequestedAt != null
                    ? '帮手任务已停止'
                    : '帮手这一轮已结束');
            final receipt = helpers._receipt({
              'summary': summary,
              'threadId': child,
              'turnId': turn['id'],
              'turnStatus': turn['status'],
              'completedAt': turn['completedAt'],
              'resultVerification': 'unverified',
              'source': 'codexNative'
            },
                verification: turn['status'] == 'completed'
                    ? VerificationLevel.verified
                    : VerificationLevel.unverified);
            await context.report(details: {
              ...context.job.details,
              'currentActivity':
                  turn['status'] == 'completed' ? '帮手已完成' : '帮手已结束'
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
            return;
          }
          if (context.job.cancelRequestedAt != null) {
            await chat.interrupt(onThread: child);
          }
        }
        final next = await Future.any<Object>([
          change.then((_) => 'changed'),
          detached.then((_) => 'detached'),
          if (context.job.cancelRequestedAt == null)
            context.stopRequested.then((_) => 'stop')
        ]);
        if (next == 'detached' || !chat.available) {
          await context.retryAt(
              DateTime.now().toUtc().add(const Duration(seconds: 2)),
              const Failure(FailureCode.unavailable, 'Chat host was detached.'),
              checkpoint: context.job.checkpoint);
          return;
        }
        if (next == 'stop') {
          final snapshot = await context.snapshot();
          if (chat.busyFor(child) &&
              chat.livenessFor(child).turnId ==
                  (context.job.checkpoint['turnId'] ??
                      context.job.input['turnId'])) {
            await chat.interrupt(onThread: child);
          }
          if (snapshot.state == JobState.paused) return;
        }
        if (changed.isCompleted) changed = Completer<void>();
      }
    } finally {
      timer.cancel();
      await subscription.cancel();
      await activitySubscription.cancel();
    }
  }
}
