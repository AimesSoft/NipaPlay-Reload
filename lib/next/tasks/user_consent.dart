import 'package:flutter/material.dart' hide Action;
import 'dart:convert';
import '../media/identity_store.dart' show stableMediaId, newMediaId;
import 'package:nipa_harness/nipa_harness.dart';

import '../media_sources/login_dialog.dart';

Future<bool> showUserConsent(String title, String message, String accept,
        {Future<void>? stopped}) async =>
    await showNextLogin<bool>((_) => _ConsentDialog(
        title: title, message: message, accept: accept, stopped: stopped)) ??
    false;

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog(
      {required this.title,
      required this.message,
      required this.accept,
      this.stopped});
  final String title, message, accept;
  final Future<void>? stopped;
  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  bool answered = false;
  @override
  void initState() {
    super.initState();
    widget.stopped?.then((_) {
      if (mounted && !answered) {
        Navigator.of(context).removeRoute(ModalRoute.of(context)!);
      }
    });
  }

  void answer(bool value) {
    answered = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Text(widget.message),
        actions: [
          TextButton(onPressed: () => answer(false), child: const Text('取消')),
          FilledButton(
              onPressed: () => answer(true), child: Text(widget.accept)),
        ],
      );
}

/// Only this application-owned executor holds the underlying deletion actions.
/// No Action can supply, persist or resolve an approval on the user's behalf.
final class DiskDeletion implements JobExecutor {
  DiskDeletion({Future<bool> Function(String, String, Future<void>)? prompt})
      : prompt = prompt ??
            ((title, message, stopped) =>
                showUserConsent(title, message, '删除', stopped: stopped));
  final Future<bool> Function(String, String, Future<void>) prompt;
  late TaskEngine engine;
  late Harness _execution;
  final _previews = <String, JsonMap>{};
  @override
  String get type => 'disk_deletion';

  List<Capability> protect(List<Capability> capabilities) {
    _execution = Harness(capabilities);
    return [
      _ProtectedCapability([_RequestDownloadDeletion(this)]),
      for (final capability in capabilities)
        _ProtectedCapability([
          for (final action in capability.actions)
            if (const {'download.delete', 'plugins.delete'}
                .contains(action.spec.id))
              _DeletionAction(this, action.spec)
            else
              action
        ])
    ];
  }

  Future<JsonMap> downloadPreview(JsonMap arguments) async {
    final read = await _execution.invokeJson('download.read', arguments,
      Invocation(origin: 'application:delete_preview'));
    if (read case Failed(:final failure)) throw failure;
    if (read is! Completed) throw StateError('Download read needs a completed manifest.');
    JsonMap manifest(JsonMap result) {
      final task = result['task'] as JsonMap?;
      return {'jobId': (result['job'] as Map?)?['jobId'],
        'infoHash': task?['infoHash'], 'outputDirectory': task?['outputDirectory'],
        'files': [for (final file in (task?['files'] as List? ?? []).cast<Map>())
          {for (final key in ['path', 'local', 'expectedSize', 'included']) key: file[key]}]};
    }
    final result = read.value.toJson();
    if (result['results'] case final List items) {
      if (items.any((item) => (item as Map)['status'] == 'failed')) {
        throw const Failure(FailureCode.unavailable, 'Some downloads cannot be previewed; read each task before deleting.');
      }
      return {'downloads': [for (final item in items.cast<JsonMap>()) manifest(item)]};
    }
    return {'downloads': [manifest(result)]};
  }

  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) => _run(context);

  Future<void> _run(JobContext context) async {
    if (context.job.phase == 'deleting') {
      await context.fail(
          const Failure(FailureCode.conflict,
              'Deletion was interrupted after approval; inspect the actual files before retrying.'),
          JobReceipt(
              verification: VerificationLevel.unverified,
              details: {'reason': 'interrupted_deletion'}));
      return;
    }
    if (context.job.cancelRequestedAt != null) {
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.verified,
          details: {'deleted': false}));
      return;
    }
    await context.waitingUser();
    final action = context.job.input['action'] as String;
    final approved = await prompt(
        '删除文件',
        action == 'download.delete'
            ? '将删除下载的文件，无法恢复。${context.job.input['preview'] == null ? '' : '\n${jsonEncode(context.job.input['preview'])}'}\n要删除吗？'
            : '将删除插件文件，无法恢复。要删除吗？',
        context.stopRequested);
    final current = await context.snapshot();
    if (current.cancelRequestedAt != null) {
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.verified,
          details: {'deleted': false}));
      return;
    }
    if (!approved) {
      await context.fail(
          const Failure(FailureCode.conflict, '用户没有同意删除'),
          JobReceipt(
              verification: VerificationLevel.verified,
              details: {'deleted': false, 'reason': 'user_declined'}));
      return;
    }
    if (action == 'download.delete' && context.job.input['expectedPlan'] != null) {
      final current = await downloadPreview(context.job.input['arguments'] as JsonMap);
      if (stableMediaId('delete-plan', current) != context.job.input['expectedPlan']) {
        throw const Failure(FailureCode.conflict, 'Download targets changed after preview; preview again.');
      }
    }
    await context.running(phase: 'deleting');
    final outcome = await _execution.invokeJson(
        action,
        context.job.input['arguments'] as JsonMap,
        Invocation(
            origin: context.job.input['origin'] as String,
            id: context.job.input['invocationId'] as String));
    switch (outcome) {
      case Completed(:final value):
        final result = value.toJson();
        final failures = (result['results'] as List?)
                ?.where((item) => (item as Map)['status'] == 'failed')
                .toList() ??
            [];
        if (failures.isNotEmpty) {
          await context.fail(
              const Failure(FailureCode.unavailable,
                  'Some requested files could not be deleted; inspect the per-item results.'),
              JobReceipt(
                  verification: VerificationLevel.acknowledged,
                  details: {'action': action, 'result': result}));
          return;
        }
        await context.markSideEffectCommitted();
        await context.succeed(
            JobReceipt(
                verification: VerificationLevel.verified,
                details: {'action': action, 'result': result}),
            phase: 'deleted');
      case Failed(:final failure):
        await context.fail(
            failure,
            JobReceipt(
                verification: VerificationLevel.unverified,
                details: {'action': action, 'reason': 'deletion_failed'}));
      case NeedsDecision():
        throw StateError(
            'A disk deletion cannot delegate approval to an Agent.');
    }
  }
}

final class _ProtectedCapability implements Capability {
  _ProtectedCapability(this.actions);
  @override
  final List<Action> actions;
}

final class _Json implements JsonEncodable {
  _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _DeletionAction extends Action<_Json, _Json> {
  _DeletionAction(this.deletion, this.original);
  final DiskDeletion deletion;
  final ActionSpec original;
  @override
  ActionSpec get spec => ActionSpec(
      id: original.id,
      title: original.title,
      effect: original.effect,
      input: original.input,
      description:
          '${original.description} download.delete returns NeedsDecision with the current file manifest. '
          'Its option download.delete.request creates a disk_deletion task; only the local user can approve it. '
          'For download.delete, input jobId/jobIds identify downloads; the returned job.jobId identifies a separate deletion task. One user prompt covers the entire requested batch. '
          'Only a person clicking Delete in NipaPlay can authorize disk deletion. '
          'waiting_user means no deletion has run; task.wait and followup.register '
          'can observe it. A refusal fails with 用户没有同意删除. No confirmation or execute argument bypasses this gate.',
      output: const ObjectSchema(
          {'job': ObjectSchema({}, additionalProperties: true)},
          required: ['job']));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    if (original.id == 'download.delete') {
      final preview = await deletion.downloadPreview(input.value);
      final id = newMediaId('delete-preview');
      deletion._previews[id] = {'arguments': input.value, 'preview': preview,
        'origin': invocation.origin, 'invocationId': invocation.id};
      return NeedsDecision(Decision(prompt: '删除这些下载文件：${jsonEncode(preview)}',
        options: [DecisionOption(label: '请求删除', call: ActionCall('download.delete.request', {'previewId': id}))]));
    }
    final job = await deletion.engine
        .submit(type: deletion.type, title: '删除文件', input: {
      'action': original.id,
      'arguments': input.value,
      'origin': invocation.origin,
      'invocationId': invocation.id
    });
    return Completed(_Json({'job': job.toJson()}));
  }
}

final class _RequestDownloadDeletion extends Action<_Json, _Json> {
  _RequestDownloadDeletion(this.deletion);
  final DiskDeletion deletion;
  @override
  ActionSpec get spec => const ActionSpec(id: 'download.delete.request',
    title: '请求删除预览中的下载文件',
    description: 'Use the option returned by download.delete. The process-local preview is single-use and caller-bound. '
      'Creates a persistent disk_deletion task, asks the user in NipaPlay, then checks the manifest again. '
      'This action cannot approve deletion. Restart before requesting requires a new preview.',
    effect: Effect.destructive,
    input: ObjectSchema({'previewId': StringSchema(minLength: 1)}, required: ['previewId']),
    output: ObjectSchema({'job': ObjectSchema({}, additionalProperties: true)}, required: ['job']));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final id = input.value['previewId'] as String;
    final plan = deletion._previews[id];
    if (plan == null || plan['origin'] != invocation.origin) {
      throw const Failure(FailureCode.conflict, 'Deletion preview is missing or belongs to another caller.');
    }
    final current = await deletion.downloadPreview(plan['arguments'] as JsonMap);
    final fingerprint = stableMediaId('delete-plan', plan['preview']!);
    if (stableMediaId('delete-plan', current) != fingerprint) {
      throw const Failure(FailureCode.conflict, 'Download targets changed after preview; preview again.');
    }
    deletion._previews.remove(id);
    final job = await deletion.engine.submit(type: deletion.type, title: '删除下载文件', input: {
      'action': 'download.delete', 'arguments': plan['arguments'],
      'origin': invocation.origin, 'invocationId': plan['invocationId'],
      'expectedPlan': fingerprint, 'preview': plan['preview'],
    });
    return Completed(_Json({'job': job.toJson()}));
  }
}
