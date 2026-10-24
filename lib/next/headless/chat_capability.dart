import 'dart:async';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';

import '../capabilities/classic_action.dart';
import '../chat/chat_host.dart';
import '../harness_redaction.dart';
import 'model.dart';
import 'nipa.dart';

const _output = ObjectSchema({}, additionalProperties: true);

/// How Nipa on this host is talked to and read back from the command line:
/// `chat.send`, `chat.status`, `chat.read`, `chat.stop`, with the existing
/// `chat.session.*` and `chat.turn.process`; and `app.runtime`, which says
/// whether she is running and what she lacks.
///
/// A turn runs in the host in the background. `chat.send` returns as soon as
/// the runtime has taken it; nothing here holds a turn open.
final class HeadlessChatCapability implements Capability {
  HeadlessChatCapability(this.nipa, {required this.model, required this.programsEnabled});

  final HeadlessNipa nipa;
  final HeadlessModel model;
  final bool Function() programsEnabled;

  /// Who may speak as the person at this host. A turn a conversation, a
  /// helper, a hook or another device asks for is theirs, not the person's:
  /// those go through `agent.dispatch`, `agent.wake` and `followup.register`.
  static const _personOrigins = {'harness_cli', 'mcp', 'gui', 'application'};

  static void _person(Invocation invocation, String action) {
    if (_personOrigins.contains(invocation.origin)) return;
    throw Failure(
        FailureCode.unavailable,
        '$action speaks for the person at this host; a call from Nipa herself, '
        'a helper, a hook or another device (origin ${invocation.origin}) is not '
        'theirs. Use agent.dispatch for a helper turn, agent.wake or '
        'followup.register to start one later.');
  }

  ChatHost _host() {
    final host = nipa.host;
    if (host == null) {
      throw Failure(
          FailureCode.unavailable,
          nipa.reason ?? 'Nipa is not running on this host.');
    }
    return host;
  }

  /// The thread [id] names, else the one the person last used (the main
  /// conversation when none yet).
  Future<String> _thread(ChatHost host, String? id) async {
    if (id != null) return id;
    if (host.threadId == null) await host.getMainSession();
    return host.threadId!;
  }

  Future<JsonMap> _send(JsonMap input, Invocation invocation) async {
    _person(invocation, 'chat.send');
    final host = _host();
    final text = input['text'] as String;
    final id = input['threadId'] as String?;
    final threadId = await _thread(host, id);
    if (host.busyFor(threadId)) {
      throw Failure(
          FailureCode.conflict,
          'A turn is already running on this conversation '
          '(${host.livenessFor(threadId).turnId ?? 'starting'}); '
          'wait for it (chat.status waitSeconds) or stop it (chat.stop).',
          details: {'threadId': threadId});
    }
    final started = id == null
        ? await host.startTurn(text)
        : await host.startThreadTurn(id, text);
    final turn = started['turn'] as Map?;
    return {
      'threadId': threadId,
      'turnId': turn?['id'] ?? host.livenessFor(threadId).turnId,
      'status': turn?['status'] ?? host.livenessFor(threadId).status,
    };
  }

  Future<JsonMap> _status(JsonMap input) async {
    final host = _host();
    final threadId = await _thread(host, input['threadId'] as String?);
    final waitSeconds = input['waitSeconds'] as int? ?? 0;
    if (waitSeconds > 0) {
      final deadline = DateTime.now().add(Duration(seconds: waitSeconds));
      while (host.available && host.busyFor(threadId)) {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) break;
        // Pushed by the host's own events; no polling.
        await host.events
            .firstWhere((event) =>
                event['method'] == 'host/error' ||
                event['method'] == 'turn/completed' &&
                    (event['params'] as Map)['threadId'] == threadId)
            .timeout(left, onTimeout: () => <String, dynamic>{});
      }
    }
    final live = host.livenessFor(threadId).snapshot(DateTime.now());
    return {
      'threadId': threadId,
      'isMain': threadId == host.mainThreadId,
      'mainThreadId': host.mainThreadId,
      'busy': host.busyFor(threadId),
      'model': host.model,
      'provider': host.provider,
      // How the latest turn on this thread stands, from the runtime's own
      // events; null fields when no turn has run since the host started.
      'turn': live,
    };
  }

  Future<JsonMap> _read(JsonMap input) async {
    final host = _host();
    final threadId = await _thread(host, input['threadId'] as String?);
    final count = input['turns'] as int? ?? 3;
    final thread = await host.readThread(threadId, withProcess: false);
    final all = (thread['turns'] as List? ?? const []).cast<Map>();
    final shown = all.length > count ? all.sublist(all.length - count) : all;
    String clip(String text) =>
        text.length > 8000 ? '${text.substring(0, 8000)}…' : text;
    final result = {
      'threadId': threadId,
      'name': thread['name'],
      'turnCount': all.length,
      'omittedTurns': all.length - shown.length,
      'turns': [
        for (final turn in shown)
          {
            'id': turn['id'],
            'status': turn['status'],
            if (turn['error'] != null) 'error': turn['error'],
            if (turn['durationMs'] != null) 'durationMs': turn['durationMs'],
            'items': [
              for (final item in (turn['items'] as List? ?? const []).cast<Map>())
                switch (item['type']) {
                  'userMessage' => {
                      'type': 'userMessage',
                      'text': clip([
                        for (final part in (item['content'] as List? ?? const []))
                          if ((part as Map)['text'] is String) part['text']
                      ].join('\n'))
                    },
                  'agentMessage' => {
                      'type': 'agentMessage',
                      'text': clip(item['text'] as String? ?? '')
                    },
                  'commandExecution' => {
                      'type': 'commandExecution',
                      'command': clip(item['command'] as String? ?? ''),
                      'status': item['status'],
                      'exitCode': item['exitCode'],
                    },
                  _ => {'type': item['type'], 'status': item['status']},
                }
            ],
          }
      ],
    };
    return await redactHarnessJsonOffMain(result) as JsonMap;
  }

  Future<JsonMap> _stop(JsonMap input, Invocation invocation) async {
    _person(invocation, 'chat.stop');
    final host = _host();
    final threadId = await _thread(host, input['threadId'] as String?);
    if (!host.busyFor(threadId)) {
      return {'threadId': threadId, 'stopped': false, 'reason': 'No turn is running on this conversation.'};
    }
    await host.interrupt(onThread: threadId);
    return {
      'threadId': threadId,
      'stopped': true,
      'turnId': host.livenessFor(threadId).turnId,
    };
  }

  Future<JsonMap> _runtime() async {
    final model = await this.model.facts();
    return redactHarnessJson({
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'host': 'headless',
      'platform': Platform.operatingSystem,
      'agent': {
        'switchOn': nipa.facts()['enabled'],
        'programExecutionAllowed': programsEnabled(),
      },
      // Whether Nipa is running here, and if not, what she lacks.
      'conversationHost': nipa.facts(),
      'runtime': {'selected': await nipa.runtimeFacts()},
      'model': model.toJson(),
    }) as JsonMap;
  }

  @override
  late final List<Action> actions = [
    ClassicAction(
        const ActionSpec(
            id: 'app.runtime',
            title: 'Read how Nipa is set up on this host',
            description:
                'Read the non-secret facts of the settings only the person at this host can change. '
                'conversationHost: enabled (the host\'s agent switch), state (disabled, missing, starting, running or failed), runs (whether Nipa is running here now), '
                'reason and missing (what she lacks: model, key, runtime, agentAssets) while she is not, and while she is: model, provider, busy, mainThreadId. '
                'runtime.selected: the runtime Nipa thinks with (kind dsh), whether it is installed here, its version and where it came from (installed or environment). '
                'model: provider, baseUrl without credentials, model, api, reasoning, keyConfigured and missing. '
                'agent: switchOn and programExecutionAllowed. The key is never returned; none of this can be changed through Actions.',
            effect: Effect.read,
            input: ObjectSchema({}),
            output: _output),
        (_, __) => _runtime()),
    ClassicAction(
        const ActionSpec(
            id: 'chat.send',
            title: 'Say something to Nipa on this host',
            description:
                'Start a turn with the text as the person at this host. Returns as soon as the runtime took it: {threadId, turnId, status}; the turn runs in the background. '
                'Without threadId it goes to the conversation last used (the main conversation at first). chat.status waits for it to end (waitSeconds), chat.read gives the reply, chat.turn.process the steps. '
                'Refused with conflict while that conversation already has a turn running. Only the person at the host can send: a call from Nipa herself, a helper, a hook or another device is refused.',
            effect: Effect.write,
            input: ObjectSchema({
              'text': StringSchema(minLength: 1, maxLength: 200000),
              'threadId': StringSchema(minLength: 1),
            }, required: ['text']),
            output: _output),
        _send),
    ClassicAction(
        const ActionSpec(
            id: 'chat.status',
            title: 'How the turn on a conversation stands',
            description:
                'The latest turn of a conversation (default: the one last used), from the runtime\'s own events: status (starting, inProgress, completed, failed, interrupted), turnId, startedAt, endedAt, elapsedMs, hasContent, eventCount, latestError, and whether the conversation is busy. '
                'waitSeconds (up to 55) holds the answer until the turn ends or the time is up; it is a wait on the host\'s events, not polling. A timeout is not a failure: the turn is still running.',
            effect: Effect.read,
            input: ObjectSchema({
              'threadId': StringSchema(minLength: 1),
              'waitSeconds': IntegerSchema(minimum: 0, maximum: 55),
            }),
            output: _output),
        (input, _) => _status(input)),
    ClassicAction(
        const ActionSpec(
            id: 'chat.read',
            title: 'Read the latest turns of a conversation',
            description:
                'The latest turns (default 3, up to 50) of a conversation: the person\'s message, Nipa\'s replies and the commands she ran (command, status, exit code; their output and her reasoning are in chat.turn.process). Texts over 8000 characters are clipped. Redacted.',
            effect: Effect.read,
            input: ObjectSchema({
              'threadId': StringSchema(minLength: 1),
              'turns': IntegerSchema(minimum: 1, maximum: 50),
            }),
            output: _output),
        (input, _) => _read(input)),
    ClassicAction(
        const ActionSpec(
            id: 'chat.stop',
            title: 'Stop the turn running on a conversation',
            description:
                'Interrupt the turn running on a conversation (default: the one last used). stopped is false when none was running. Only the person at the host can stop a turn.',
            effect: Effect.write,
            input: ObjectSchema({'threadId': StringSchema(minLength: 1)}),
            output: _output),
        _stop),
  ];
}
