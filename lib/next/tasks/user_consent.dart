import 'package:flutter/material.dart' hide Action;
import 'dart:convert';
import '../media/identity_store.dart' show stableMediaId, newMediaId;
import 'package:nipa_harness/nipa_harness.dart';

import '../downloads/download_paths.dart';
import '../media_sources/login_dialog.dart';
import '../ui/theme/tokens.dart';
import '../ui/widgets/dialog.dart';

/// Asks the person at NipaPlay; true only when they press [accept]. Closing
/// the window, or [stopped], is a no. [destructive] answers cannot be
/// undone: under Next their button is crimson rather than plain.
Future<bool> showUserConsent(String title, String message, String accept,
        {Future<void>? stopped, bool destructive = false}) async =>
    await showNextLogin<bool>((_) => _ConsentDialog(
        title: title,
        message: message,
        accept: accept,
        stopped: stopped,
        destructive: destructive)) ??
    false;

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog(
      {required this.title,
      required this.message,
      required this.accept,
      this.stopped,
      this.destructive = false});
  final String title, message, accept;
  final Future<void>? stopped;
  final bool destructive;
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
  Widget build(BuildContext context) => NextDialogRoute.of(context)
      ? NextDialog(
          title: widget.title,
          width: 440,
          autofocus: true,
          onCancel: () => answer(false),
          body: [_ConsentWords(widget.message)],
          actions: [
            NextDialogButton(label: '取消', onTap: () => answer(false)),
            NextDialogButton(
                label: widget.accept,
                kind: widget.destructive
                    ? NextDialogButtonKind.danger
                    : NextDialogButtonKind.plain,
                onTap: () => answer(true)),
          ],
        )
      : AlertDialog(
          title: Text(widget.title),
          content: Text(widget.message),
          actions: [
            TextButton(onPressed: () => answer(false), child: const Text('取消')),
            FilledButton(
                onPressed: () => answer(true), child: Text(widget.accept)),
          ],
        );
}

/// A question's words under Next: its sentences, and the lines that list
/// things (“· name”) set apart in a quiet well, one per row. What follows
/// the list (how much in all) reads quieter.
class _ConsentWords extends StatelessWidget {
  const _ConsentWords(this.message);
  final String message;

  static final _more = RegExp(r'^还有 \d+ 个');

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    final items = <String>[];
    var listed = false;
    void flush() {
      if (items.isEmpty) return;
      blocks.add(Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NextColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(item,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _more.hasMatch(item)
                        ? NextText.sans(12.5,
                            color: NextColors.p3, height: 1.45)
                        : NextText.sans(13,
                            color: NextColors.paper, height: 1.45)),
              ),
          ],
        ),
      ));
      items.clear();
      listed = true;
    }

    for (final line in message.split('\n')) {
      final text = line.trim();
      if (text.isEmpty) continue;
      if (text.startsWith('·')) {
        items.add(text.substring(1).trim());
        continue;
      }
      flush();
      blocks.add(Text(text,
          style: listed
              ? NextText.sans(12.5, color: NextColors.p3, height: 1.5)
              : NextText.sans(14, color: NextColors.p2, height: 1.6)));
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, b) in blocks.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          b,
        ],
      ],
    );
  }
}

/// Only this application-owned executor holds the underlying deletion actions.
/// No Action can supply, persist or resolve an approval on the user's behalf.
final class DiskDeletion implements JobExecutor {
  DiskDeletion({Future<bool> Function(String, String, Future<void>)? prompt})
      : prompt = prompt ??
            ((title, message, stopped) => showUserConsent(title, message, '删除',
                stopped: stopped, destructive: true));
  final Future<bool> Function(String, String, Future<void>) prompt;
  late final Iterable<Capability> _unprotected;

  /// The conversation behind a request, so the answer comes back to it.
  Future<JsonMap?> Function(Invocation)? returnTarget;
  late TaskEngine engine;
  late final Harness _execution = Harness(_unprotected);
  final _previews = <String, JsonMap>{};
  @override
  String get type => 'disk_deletion';

  List<Capability> protect(List<Capability> capabilities) {
    _unprotected = capabilities;
    return [
      _ProtectedCapability([_RequestDownloadDeletion(this)]),
      for (final capability in capabilities)
        if (_protectDeletion(capability) case final protected?)
          _ProtectedCapability(protected)
        else
          capability
    ];
  }

  List<Action>? _protectDeletion(Capability capability) {
    var protected = false;
    final actions = <Action>[];
    for (final action in capability.actions) {
      if (const {'download.delete', 'plugins.delete'}
          .contains(action.spec.id)) {
        protected = true;
        actions.add(_DeletionAction(this, action.spec));
      } else {
        actions.add(action);
      }
    }
    return protected ? actions : null;
  }

  Future<JsonMap> downloadPreview(JsonMap arguments) async {
    final wanted = (arguments['fileIndices'] as List?)?.cast<int>();
    if (wanted != null) return _filesPreview(arguments, wanted);
    final read = await _execution.invokeJson('download.read', arguments,
        Invocation(origin: 'application:delete_preview'));
    if (read case Failed(:final failure)) throw failure;
    if (read is! Completed)
      throw StateError('Download read needs a completed manifest.');
    JsonMap manifest(JsonMap result) {
      final task = result['task'] as JsonMap?;
      return {
        'jobId': (result['job'] as Map?)?['jobId'],
        'infoHash': task?['infoHash'],
        'outputDirectory': task?['outputDirectory'],
        'files': [
          for (final file in (task?['files'] as List? ?? []).cast<Map>())
            {
              for (final key in ['path', 'local', 'expectedSize', 'included'])
                key: file[key]
            }
        ]
      };
    }

    final result = read.value.toJson();
    if (result['results'] case final List items) {
      if (items.any((item) => (item as Map)['status'] == 'failed')) {
        throw const Failure(FailureCode.unavailable,
            'Some downloads cannot be previewed; read each task before deleting.');
      }
      return {
        'downloads': [for (final item in items.cast<JsonMap>()) manifest(item)]
      };
    }
    return {
      'downloads': [manifest(result)]
    };
  }

  /// Only the chosen files of one download: what the person is asked about,
  /// and what must still be true when they answer.
  Future<JsonMap> _filesPreview(JsonMap arguments, List<int> wanted) async {
    final jobId = arguments['jobId'];
    if (jobId is! String || arguments.containsKey('jobIds')) {
      throw const Failure(FailureCode.invalidInput,
          'fileIndices apply to one download: pass jobId only.');
    }
    if (wanted.isEmpty || wanted.toSet().length != wanted.length) {
      throw const Failure(FailureCode.invalidInput,
          'fileIndices must be unique and not empty.');
    }
    final read = await _execution.invokeJson('download.read', {'jobId': jobId},
        Invocation(origin: 'application:delete_preview'));
    if (read case Failed(:final failure)) throw failure;
    if (read is! Completed)
      throw StateError('Download read needs a completed manifest.');
    final result = read.value.toJson();
    final task = result['task'] as JsonMap?;
    final all = (task?['files'] as List? ?? []).cast<Map>();
    if (task == null || wanted.any((i) => i < 0 || i >= all.length)) {
      throw const Failure(FailureCode.invalidInput,
          'fileIndices must be manifest indices of the download.');
    }
    final output = task['outputDirectory'] as String;
    final files = <JsonMap>[];
    for (final index in wanted) {
      final file = all[index];
      if (file['local'] != true) {
        throw const Failure(
            FailureCode.invalidInput, 'Only local files can be deleted.');
      }
      await checkedDownloadPath(output, file['path'] as String);
      files.add({
        'index': index,
        for (final key in ['path', 'local', 'expectedSize', 'included'])
          key: file[key]
      });
    }
    return {
      'downloads': [
        {
          'jobId': (result['job'] as Map?)?['jobId'],
          'infoHash': task['infoHash'],
          'outputDirectory': output,
          'partial': true,
          'files': files
        }
      ]
    };
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
            ? downloadDeletionWords(context.job.input['preview'])
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
    if (action == 'download.delete' &&
        context.job.input['expectedPlan'] != null) {
      final current =
          await downloadPreview(context.job.input['arguments'] as JsonMap);
      if (stableMediaId('delete-plan', current) !=
          context.job.input['expectedPlan']) {
        throw const Failure(FailureCode.conflict,
            'Download targets changed after preview; preview again.');
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
          'With fileIndices (one jobId), only those files of the download are previewed, asked about and deleted; the rest of the download stays. '
          'Only a person clicking Delete in NipaPlay can authorize disk deletion. '
          'waiting_user means no deletion has run; task.wait and followup.register '
          'can observe it. A refusal fails with 用户没有同意删除. When the user answers, the outcome returns to the requesting conversation. No confirmation or execute argument bypasses this gate.',
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
      deletion._previews[id] = {
        'arguments': input.value,
        'preview': preview,
        'origin': invocation.origin,
        'invocationId': invocation.id
      };
      final partial = input.value['fileIndices'] != null;
      return NeedsDecision(Decision(
          prompt:
              '${partial ? '删除这个下载里的这些文件' : '删除这些下载文件'}：${jsonEncode(preview)}',
          options: [
            DecisionOption(
                label: '请求删除',
                call: ActionCall('download.delete.request', {'previewId': id}))
          ]));
    }
    final target = await deletion.returnTarget?.call(invocation);
    final job = await deletion.engine
        .submit(type: deletion.type, title: '删除文件', input: {
      'action': original.id,
      'arguments': input.value,
      'origin': invocation.origin,
      'invocationId': invocation.id,
      if (target != null) 'returnTo': target
    });
    return Completed(_Json({'job': job.toJson()}));
  }
}

final class _RequestDownloadDeletion extends Action<_Json, _Json> {
  _RequestDownloadDeletion(this.deletion);
  final DiskDeletion deletion;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'download.delete.request',
      title: '请求删除预览中的下载文件',
      description:
          'Use the option returned by download.delete. The process-local preview is single-use and caller-bound. '
          'Creates a persistent disk_deletion task, asks the user in NipaPlay, then checks the manifest again. '
          'When the user answers (Delete, Cancel or closing the window) the outcome returns to the requesting conversation, queued while a turn is active; a followup you registered on the task jobId replaces that return. The facts carry state, whether it was deleted, and deletedFiles. '
          'This action cannot approve deletion. Restart before requesting requires a new preview.',
      effect: Effect.destructive,
      input: ObjectSchema({'previewId': StringSchema(minLength: 1)},
          required: ['previewId']),
      output: ObjectSchema(
          {'job': ObjectSchema({}, additionalProperties: true)},
          required: ['job']));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final id = input.value['previewId'] as String;
    final plan = deletion._previews[id];
    if (plan == null || plan['origin'] != invocation.origin) {
      throw const Failure(FailureCode.conflict,
          'Deletion preview is missing or belongs to another caller.');
    }
    final current =
        await deletion.downloadPreview(plan['arguments'] as JsonMap);
    final fingerprint = stableMediaId('delete-plan', plan['preview']!);
    if (stableMediaId('delete-plan', current) != fingerprint) {
      throw const Failure(FailureCode.conflict,
          'Download targets changed after preview; preview again.');
    }
    deletion._previews.remove(id);
    final target = await deletion.returnTarget?.call(invocation);
    final job = await deletion.engine
        .submit(type: deletion.type, title: '删除下载文件', input: {
      'action': 'download.delete',
      'arguments': plan['arguments'],
      'origin': invocation.origin,
      'invocationId': plan['invocationId'],
      'expectedPlan': fingerprint,
      'preview': plan['preview'],
      if (target != null) 'returnTo': target,
    });
    return Completed(_Json({'job': job.toJson()}));
  }
}

/// What a download deletion removes, in words a person reads: a few file
/// names, how many more, and roughly how much space.
String downloadDeletionWords(Object? preview) {
  final downloads =
      ((preview is Map ? preview['downloads'] : null) as List? ?? const [])
          .cast<Map>();
  // Some files of one download: every file listed is deleted, whether or not
  // it is still selected.
  final partial = downloads.length == 1 && downloads.single['partial'] == true;
  final files = [
    for (final d in downloads)
      for (final f in (d['files'] as List? ?? const []).cast<Map>())
        if (partial || f['included'] != false) f
  ];
  String name(Map f) {
    final path = '${f['path'] ?? ''}';
    return path.split(RegExp(r'[\\/]')).last;
  }

  final names = [
    for (final f in files)
      if (name(f).isNotEmpty) name(f)
  ];
  final bytes =
      files.fold<num>(0, (sum, f) => sum + ((f['expectedSize'] as num?) ?? 0));
  String size(num b) => b >= 1 << 30
      ? '${(b / (1 << 30)).toStringAsFixed(1)} GB'
      : '${(b / (1 << 20)).toStringAsFixed(0)} MB';
  final lines = StringBuffer();
  if (names.isEmpty) {
    lines.write(downloads.length <= 1
        ? '将删除这个下载留下的数据，无法恢复。'
        : '将删除 ${downloads.length} 个下载留下的数据，无法恢复。');
  } else {
    lines.writeln(partial
        ? (names.length == 1 ? '将删除这个下载里的这个文件，无法恢复：' : '将删除这个下载里的这几个文件，无法恢复：')
        : '将删除这些下载的文件，无法恢复：');
    for (final n in names.take(3)) {
      lines.writeln('· $n');
    }
    if (names.length > 3) lines.writeln('· 还有 ${names.length - 3} 个文件');
    if (bytes > 0) lines.write('共约 ${size(bytes)}。');
    if (partial) lines.write('下载里的其他文件不动。');
  }
  return lines.toString().trimRight();
}
