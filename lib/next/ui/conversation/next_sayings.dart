import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../widgets/words.dart';

/// What you might say next. The rules are the interface's own: they read
/// Nipa's last reply and the cards it showed, and ask nothing of the agent.
/// Tapping one says it, like typing it.
abstract final class NextSayings {
  static List<String> after(String reply, List<UiCard> cards) {
    final candidates = [
      for (final c in cards.whereType<UiCandidatesCard>()) ...c.items
    ];
    final works = [for (final c in cards.whereType<UiWorkCard>()) c.work];
    final episodes = cards.whereType<UiEpisodeCard>().toList();
    final underway = cards.map(Underway.of).whereType<Underway>();
    final text = reply.trimRight();
    final asks = text.endsWith('？') || text.endsWith('?');
    final out = <String>[];
    if (underway.isNotEmpty) {
      // Something is being prepared: how long, or something else meanwhile.
      out.addAll(['还要多久', '先看点别的']);
    } else if (candidates.length > 1) {
      out.addAll([_take(candidates.first.work, '就第一部'), '换一批']);
    } else if (candidates.length == 1 || works.length == 1) {
      final work = candidates.firstOrNull?.work ?? works.single;
      out.addAll(Words.canPlay(work)
          ? ['就这部', '换一部']
          : ['就这部', '先下第一集', '换一部']);
    } else if (episodes.length == 1) {
      out.addAll(['就看这集', '换一部']);
    } else if (episodes.length > 1) {
      out.add(_take(episodes.first.work, '从第一个开始', verb: '先看'));
      out.add(episodes.any((e) => !e.episode.playable) ? '都下下来' : '还有别的吗');
    } else if (asks) {
      out.addAll(['好', '不用了']);
    }
    return out.take(3).toList();
  }

  /// “就《迷宫饭》”; a long title reads [otherwise].
  static String _take(UiWork work, String otherwise, {String verb = '就'}) =>
      work.title.characters.length <= 8 ? '$verb《${work.title}》' : otherwise;
}

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
