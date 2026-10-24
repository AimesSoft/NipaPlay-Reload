import 'dart:async';
import 'dart:math';

import 'package:nipa_harness/nipa_harness.dart';

import '../followups/service.dart';
import '../harness_redaction.dart';

/// The task type of a delegation, on the device that handed the work over.
const delegateJobType = 'agent.delegate';

/// A call to a host method of another device (`MeshRuntime.rpc`).
typedef MeshCall = Future<JsonMap> Function(
    String peer, String method, JsonMap params);

const _taskLimit = 60000;
const _summaryLimit = 16000;

/// Handing work to the Nipa of another device, and following it.
///
/// This is a primitive and nothing more: whether to delegate, to which device
/// and how to write the task are the sending Nipa's. The task is a local
/// background task (`agent.delegate`) that follows the other device's turn:
/// its state, its step count and its last sentence are the task's details,
/// its end is the task's receipt, and the end returns to the conversation that
/// delegated through a followup like any other task's. Cancelling the task
/// stops the other device's turn.
final class MeshDelegations implements JobExecutor {
  MeshDelegations(
      {required this.call,
      required this.devices,
      required this.selfDeviceId,
      this.retryBase = const Duration(seconds: 5)});

  /// How long the first retry waits when the other device cannot be reached;
  /// each next one waits twice as long, up to a minute.
  final Duration retryBase;

  final MeshCall call;

  /// Devices of the account as the mesh knows them
  /// (`deviceId`, `name`, `revoked`).
  final List<JsonMap> Function() devices;
  final String? Function() selfDeviceId;
  late TaskEngine engine;
  late Followups followups;
  final _random = Random.secure();

  @override
  String get type => delegateJobType;

  JsonMap _device(String wanted) {
    final self = selfDeviceId();
    final live = [
      for (final device in devices())
        if (device['revoked'] != true) device
    ];
    final byId = live.where((d) => d['deviceId'] == wanted).toList();
    final matches = byId.isNotEmpty
        ? byId
        : live.where((d) => d['name'] == wanted).toList();
    if (matches.isEmpty) {
      throw const Failure(FailureCode.notFound,
          'No such device in this account (use a deviceId from mesh.devices).');
    }
    if (matches.length > 1) {
      throw Failure(
          FailureCode.invalidInput,
          'More than one device is called "$wanted"; use its deviceId: '
          '${matches.map((d) => d['deviceId']).join(', ')}.');
    }
    if (matches.single['deviceId'] == self) {
      throw const Failure(FailureCode.invalidInput,
          'This is the device itself; there is nothing to hand over.');
    }
    return matches.single;
  }

  String _newId() =>
      'delegate-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${List.generate(6, (_) => _random.nextInt(16).toRadixString(16)).join()}';

  /// Hands [input] (`deviceId`, `task`, `references`) to the Nipa of that
  /// device and returns the local task that follows it. Fails at once, with
  /// the other device's own words, when she cannot take it.
  Future<JsonMap> delegate(JsonMap input, Invocation invocation) async {
    final device = _device(input['deviceId'] as String);
    final peer = device['deviceId'] as String;
    final name = device['name'] as String? ?? '另一台设备';
    final task = redactHarnessText(input['task'] as String);
    final references = input['references'] == null
        ? null
        : [
            for (final reference in input['references'] as List)
              publicHarnessFacts(reference)
          ];
    if (task.trim().isEmpty || task.length > _taskLimit) {
      throw const Failure(FailureCode.invalidInput,
          'task must be 1 to 60000 characters.');
    }
    final id = _newId();
    final JsonMap started;
    try {
      started = await call(peer, 'mesh/agent/turn', {
        'delegationId': id,
        'text': task,
        if (references != null) 'refs': references,
      });
    } on Failure catch (failure) {
      throw Failure(failure.code, '$name did not take the task: ${failure.message}',
          retryable: failure.retryable);
    } catch (error) {
      throw Failure(FailureCode.unavailable,
          '$name did not take the task: ${redactHarnessText('$error')}',
          retryable: true);
    }
    final first = task.trim().split('\n').first;
    final title = '交给 $name：${first.length > 24 ? '${first.substring(0, 24)}…' : first}';
    final Job job;
    try {
      job = await engine.submit(
          jobId: id,
          type: type,
          title: title,
          input: {
            'deviceId': peer,
            'deviceName': name,
            'task': task,
            if (references != null) 'references': references,
            'remoteThreadId': started['threadId'],
            'remoteTurnId': started['turnId'],
          },
          details: {
            'source': 'mesh',
            'deviceId': peer,
            'deviceName': name,
            'remoteThreadId': started['threadId'],
            'remoteTurnId': started['turnId'],
            'remoteState': started['state'] ?? 'inProgress',
            'steps': started['steps'] ?? 0,
            'currentActivity': '$name 正在处理',
          },
          // The other device is already working: this task is never a
          // not-yet-started one that cancellation could drop unseen.
          sideEffectCommitted: true);
    } catch (_) {
      try {
        await call(peer, 'mesh/agent/interrupt', {'delegationId': id});
      } catch (_) {}
      rethrow;
    }
    String? returnsTo, returnNote;
    try {
      final row = await followups.register({
        'when': {'jobId': id},
        'title': title,
        'instruction': '交给 $name 上 Nipa 的任务已结束（完成、失败或被取消），'
            '请根据回执回应用户。',
      }, invocation);
      returnsTo = row['threadId'] as String?;
    } on Failure catch (failure) {
      returnNote = failure.message;
    }
    return {
      'jobId': job.jobId,
      'deviceId': peer,
      'deviceName': name,
      'remote': {
        'threadId': started['threadId'],
        'turnId': started['turnId'],
        'conversationContinued': started['conversationContinued'] == true,
      },
      'returnsTo': returnsTo,
      if (returnNote != null) 'returnNote': returnNote,
    };
  }

  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) => _run(context);

  Future<Job?> _current(JobContext context) async {
    try {
      return await context.snapshot();
    } on Failure {
      // The engine is closing.
      return null;
    }
  }

  /// A turn that completed is a verified end of the *turn*; what it says is
  /// the other Nipa's word, which `resultVerification` says plainly.
  JobReceipt _receipt(JsonMap details, {bool done = false}) => JobReceipt(
      verification:
          done ? VerificationLevel.verified : VerificationLevel.unverified,
      details: publicHarnessFacts({
        ...details,
        if (details.containsKey('summary')) 'resultVerification': 'unverified',
      }) as JsonMap);

  Future<void> _run(JobContext context) async {
    // Picked up again after a restart or a wait for the device.
    if (context.job.state == JobState.interrupted) {
      await context.running(phase: 'working');
    }
    final job = context.job;
    final peer = job.input['deviceId'] as String;
    final name = job.input['deviceName'] as String? ?? '另一台设备';
    var since = job.checkpoint['version'] as int? ?? -1;
    var attempts = job.checkpoint['attempts'] as int? ?? 0;
    JsonMap? last;

    JsonMap facts(JsonMap snapshot) => {
          'deviceId': peer,
          'deviceName': name,
          'threadId': snapshot['threadId'],
          'turnId': snapshot['turnId'],
          'turnStatus': snapshot['state'],
          'steps': snapshot['steps'],
          if (snapshot['lastSentence'] != null)
            'lastSentence': snapshot['lastSentence'],
          if (snapshot['error'] != null) 'remoteError': snapshot['error'],
          if (snapshot['startedTasks'] != null)
            'startedTasks': snapshot['startedTasks'],
        };

    while (true) {
      final current = await _current(context);
      if (current == null) return;
      if (current.cancelRequestedAt != null) {
        await _cancel(context, peer, name, last, facts);
        return;
      }
      final asked = call(peer, 'mesh/agent/wait', {
        'delegationId': job.jobId,
        'since': since,
        'waitSeconds': 50,
      }).then<Object>((reply) => reply, onError: (Object error) => error);
      final result = await Future.any<Object>([
        asked,
        context.stopRequested.then<Object>((_) => #stopped),
      ]);
      if (result == #stopped) {
        final now = await _current(context);
        if (now == null) return;
        if (now.cancelRequestedAt != null) {
          await _cancel(context, peer, name, last, facts);
        }
        // Otherwise the task was paused: it goes on when it is resumed.
        return;
      }
      if (result is! Map) {
        // The other device could not be asked.
        final failure = result is Failure
            ? result
            : Failure(FailureCode.unavailable, redactHarnessText('$result'),
                retryable: true);
        if (failure.code == FailureCode.notFound ||
            failure.code == FailureCode.invalidInput) {
          await context.fail(
              failure,
              _receipt({
                'deviceId': peer,
                'deviceName': name,
                'remoteError': failure.message,
                if (last != null) ...facts(last),
              }));
          return;
        }
        attempts++;
        final wait = Duration(
            milliseconds: min(60000, retryBase.inMilliseconds << min(attempts - 1, 4)));
        await context.report(details: {
          ...context.job.details,
          'remoteState': 'unreachable',
          'currentActivity': '$name 暂时连不上，稍后再试',
        });
        await context.retryAt(
            DateTime.now().toUtc().add(wait),
            Failure(failure.code, failure.message, retryable: true),
            checkpoint: {'version': since, 'attempts': attempts});
        return;
      }
      final reply = Map<String, Object?>.from(result);
      attempts = 0;
      last = reply;
      final version = reply['version'] as int? ?? since + 1;
      final state = reply['state'] as String? ?? 'inProgress';
      if (state == 'inProgress') {
        if (version != since ||
            context.job.details['remoteState'] != 'inProgress') {
          since = version;
          await context.report(checkpoint: {
            'version': since,
            'attempts': 0
          }, details: {
            ...context.job.details,
            'remoteThreadId': reply['threadId'],
            'remoteTurnId': reply['turnId'],
            'remoteState': state,
            'steps': reply['steps'],
            if (reply['lastSentence'] != null)
              'lastSentence': reply['lastSentence'],
            'currentActivity':
                (reply['lastSentence'] as String?) ?? '$name 正在处理',
          });
        }
        continue;
      }
      final text = (reply['reply'] as String?) ?? '';
      final clipped = text.length > _summaryLimit;
      final summary = text.isNotEmpty
          ? (clipped ? '${text.substring(0, _summaryLimit)}…' : text)
          : state == 'completed'
              ? '对方完成了这一轮，没有文字回复'
              : '对方这一轮没有完成';
      final details = {
        ...facts(reply),
        'summary': summary,
        if (clipped || reply['replyTruncated'] == true) 'summaryTruncated': true,
      };
      await context.report(details: {
        ...context.job.details,
        'remoteState': state,
        'steps': reply['steps'],
        'currentActivity': state == 'completed' ? '$name 已完成' : '$name 已结束',
        'summary': summary,
      });
      if (state == 'completed') {
        await context.succeed(_receipt(details, done: true));
      } else {
        await context.fail(
            Failure(FailureCode.unavailable,
                'The delegated turn on $name ended: $state'),
            _receipt(details));
      }
      return;
    }
  }

  /// The local task was cancelled: the other device's turn is stopped, and the
  /// task says what was and was not confirmed.
  Future<void> _cancel(JobContext context, String peer, String name,
      JsonMap? last, JsonMap Function(JsonMap) facts) async {
    JsonMap? remote;
    String? unreached;
    try {
      remote = await call(
          peer, 'mesh/agent/interrupt', {'delegationId': context.job.jobId});
      if (remote['state'] == 'inProgress') {
        remote = await call(peer, 'mesh/agent/wait', {
          'delegationId': context.job.jobId,
          'since': remote['version'],
          'waitSeconds': 20,
        });
      }
    } on Failure catch (failure) {
      unreached = failure.message;
    } catch (error) {
      unreached = redactHarnessText('$error');
    }
    final seen = remote ?? last;
    await context.cancelled(_receipt({
      'deviceId': peer,
      'deviceName': name,
      if (seen != null) ...facts(seen),
      'remoteStopped': remote != null && remote['state'] != 'inProgress',
      if (unreached != null) 'remoteUnreached': unreached,
    }));
  }
}

final class MeshDelegationCapability implements Capability {
  MeshDelegationCapability(MeshDelegations delegations)
      : actions = [_DelegateAction(delegations)];
  @override
  final List<Action> actions;
}

final class _DelegateAction extends Action<_Json, _Json> {
  const _DelegateAction(this.delegations);
  final MeshDelegations delegations;

  @override
  ActionSpec get spec => const ActionSpec(
      id: 'mesh.delegate',
      title: 'Hand a task to the Nipa of another device',
      description:
          'Give a task to the Nipa that runs on another device of this account, to be done there with that device\'s own tools '
          '(mesh.devices says which devices run her: description.agent.runs, and why not in agent.reason). '
          'You write the whole task: the receiving Nipa knows only what you put in it, plus the references you attach. '
          'It opens a conversation on that device (one conversation per sending device, continued while idle) that begins with where it came from; '
          'the person at that device sees it in the conversation list and can read it and speak in it. '
          'Returns at once with jobId, a local background task of type agent.delegate: task.get shows the other turn\'s state (remoteState), steps and lastSentence; '
          'it ends with her final reply (receipt summary), the tasks she started there (startedTasks) and the conversation to read more from (threadId, via mesh.invoke chat.read on that device); '
          'a failure or a stop ends it too. The end returns to your conversation through a followup, like any task\'s. task.cancel stops the other turn. '
          'Fails at once, with her device\'s own reason, when Nipa is not running there. '
          'The user\'s preference: for work to be done on another device, hand it to the Nipa there rather than calling that device\'s actions one by one yourself; remote calls remain available. '
          'Nothing here decides whether to delegate, to whom or how to split the work.',
      effect: Effect.write,
      input: ObjectSchema({
        'deviceId': StringSchema(
            minLength: 1,
            description: 'deviceId from mesh.devices (a unique device name also works).'),
        'task': StringSchema(
            minLength: 1,
            maxLength: 60000,
            description: 'The complete task, as you would tell a person who has none of your context.'),
        'references': ArraySchema(
            ObjectSchema({}, additionalProperties: true),
            maxItems: 32,
            description:
                'Optional facts the task refers to (work ids, file paths with their device, task ids...), passed on as they are; the receiver does not verify them.'),
      }, required: [
        'deviceId',
        'task'
      ]),
      output: ObjectSchema({}, additionalProperties: true));

  @override
  _Json decodeInput(JsonMap input) => _Json(input);

  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      Completed(_Json(await delegations.delegate(input.value, invocation)));
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}
