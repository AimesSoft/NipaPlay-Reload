import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/services.dart';
import '../shell/shell_controller.dart';
import '../widgets/sheet.dart';
import 'download_sheet.dart';

/// A background task tapped: a download opens its own sheet; a task that
/// waits for the person puts its question up, and the answer runs.
Future<void> openTask(NextUiServices services, UiTask task,
    {required bool download}) async {
  if (download) return openDownload(services, task.taskId);
  final question = await services.background.question(task.taskId);
  if (question == null) return;
  final option = await decisionSheet(question);
  if (option != null) await services.calls.choose(option);
}

/// Pauses, resumes or cancels tasks together: downloads through their own
/// Action (it pauses the transfer too), the rest through `task.control`.
/// What could not be done this way.
Future<List<String>> controlTasks(NextUiServices services,
    Iterable<String> taskIds, String command, Set<String> downloads) async {
  final ids = taskIds.toList();
  final transfers = command == 'cancel'
      ? const <String>[]
      : [
          for (final id in ids)
            if (downloads.contains(id)) id
        ];
  if (transfers.isNotEmpty) {
    await services.downloads.setPaused(transfers, command == 'pause');
  }
  final results = await services.background
      .control(ids.where((id) => !transfers.contains(id)), command);
  return [
    for (final r in results)
      if (!r.accepted) r.taskId
  ];
}

/// Which of the shell's tasks are downloads, kept as the tasks change.
mixin DownloadTasks<T extends StatefulWidget> on State<T> {
  Set<String> downloads = const {};
  NextShellController? _watched;
  String _asked = '';

  void watchDownloads(NextShellController shell) {
    if (identical(shell, _watched)) return;
    _watched?.tasks.removeListener(_check);
    _watched = shell..tasks.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    _watched?.tasks.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final shell = _watched!;
    final ids = [
      for (final t in shell.tasks.value)
        if (t.kind == UiTaskKind.background) t.taskId
    ]..sort();
    final key = ids.join('|');
    if (key == _asked) return;
    _asked = key;
    unawaited(shell.services.downloads.which(ids).then((found) {
      if (mounted && _asked == key) setState(() => downloads = found);
    }, onError: (Object e) => debugPrint('[NextUi] downloads: $e')));
  }
}
