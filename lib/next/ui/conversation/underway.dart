import '../../ui_data/ui_data.dart';
import '../widgets/words.dart';

/// Something a conversation set going that is still under way, as one
/// short line: “下载 47% · 然后补上弹幕”.
final class Underway {
  const Underway(this.title, this.now,
      {this.then, this.progress, this.artwork, this.isWork = true});

  /// The work it is for, or what it does when the work is not known.
  final String title;

  /// [title] names a work.
  final bool isWork;

  /// What happens now: “下载 47%”.
  final String now;

  /// What waits after it: “然后补上弹幕”.
  final String? then;
  final double? progress;
  final UiArtwork? artwork;

  String get line => then == null ? now : '$now · $then';

  /// From a card's live state: a preparation with steps left (none failed),
  /// or a task still queued, running or paused.
  static Underway? of(UiCard card) {
    switch (card) {
      case UiPreparationCard(:final steps, :final work, :final title):
        if (steps.any((s) => s.state == UiStepState.failed)) return null;
        final running =
            steps.where((s) => s.state == UiStepState.running).firstOrNull;
        final waiting =
            steps.where((s) => s.state == UiStepState.waiting).toList();
        if (running == null && waiting.isEmpty) return null;
        final progress = running?.progress;
        return Underway(
          work?.title ?? title,
          running == null
              ? '等着${waiting.first.label}'
              : progress == null
                  ? '正在${running.label}'
                  : '${running.label} ${(progress * 100).round()}%',
          then: running != null && waiting.isNotEmpty
              ? '然后${waiting.first.label}'
              : null,
          progress: progress,
          artwork: work?.artwork,
        );
      case UiTaskCard(:final task)
          when task.state == UiTaskState.queued ||
              task.state == UiTaskState.running ||
              task.state == UiTaskState.paused:
        final action = task.action ?? task.title;
        return Underway(
            task.workTitle ?? action,
            task.workTitle == null
                ? Words.task(task)
                : '$action ${Words.task(task)}',
            isWork: task.workTitle != null,
            progress: task.progress,
            artwork: task.artwork);
      default:
        return null;
    }
  }
}
