import '../../ui_data/ui_data.dart';
import '../data/services.dart';
import '../widgets/sheet.dart';
import 'download_sheet.dart';

/// Whether the task is a download (its executor's type).
bool isDownload(UiTask task) => task.type == 'download';

/// A background task tapped: a download opens its own sheet; a task that
/// waits for the person puts its question up, and the answer runs.
Future<void> openTask(NextUiServices services, UiTask task) async {
  // One another device runs opens there.
  if (task.device != null) return;
  if (isDownload(task)) return openDownload(services, task.taskId);
  final question = await services.background.question(task.taskId);
  if (question == null) return;
  final option = await decisionSheet(services.calls, question);
  if (option != null) await services.calls.choose(option);
}

/// Pauses, resumes or cancels tasks together: downloads through their own
/// Action (it pauses the transfer too), the rest through `task.control`.
/// What could not be done this way.
Future<List<String>> controlTasks(
    NextUiServices services, Iterable<UiTask> tasks, String command) async {
  // Only this device's: another device's are controlled there.
  tasks = [for (final t in tasks) if (t.device == null) t];
  final ids = [for (final t in tasks) t.taskId];
  final transfers = command == 'cancel'
      ? const <String>[]
      : [
          for (final t in tasks)
            if (isDownload(t)) t.taskId
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
