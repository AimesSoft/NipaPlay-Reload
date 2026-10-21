import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../chat/transcript.dart' show Shimmer;
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/poster_art.dart';
import '../widgets/progress.dart';
import '../widgets/words.dart';
import '../widgets/work_title.dart';

/// State A's copy (`.copy`): Nipa's line, logo or Songti title, one meta
/// line, two lines of overview, play and detail.
class HeroCopy extends StatelessWidget {
  const HeroCopy({
    super.key,
    required this.work,
    required this.line,
    required this.mood,
    required this.moodSentence,
    required this.onPlay,
    required this.onDetail,
    this.preparing,
    this.leadWithTitle = false,
  });

  final UiWork work;

  /// Nipa's sentence; nothing is shown when there is nothing to say.
  final String? line;
  final NipaMood mood;
  final String? moodSentence;
  final VoidCallback onPlay;
  final VoidCallback onDetail;

  /// State C: background work under Nipa's line.
  final Widget? preparing;

  /// The line is about this work but does not name it (the hero's note).
  final bool leadWithTitle;

  @override
  Widget build(BuildContext context) {
    final overview = work.overview;
    return SizedBox(
      width: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: NextMotion.ease,
            alignment: Alignment.topLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: line == null || line!.isEmpty
                  ? const SizedBox(key: ValueKey('none'), width: 600)
                  : Padding(
                      key: ValueKey(line),
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        NipaAvatar(
                            size: 28,
                            mood: mood,
                            sentence: moodSentence,
                            onTap: NextShellScope.of(context).openChat),
                        const SizedBox(width: 12),
                        Expanded(
                          // While Nipa works, light passes over what it is
                          // doing.
                          child: mood == NipaMood.thinking ||
                                  mood == NipaMood.acting
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: Shimmer(
                                      text: line!,
                                      style: NextText.sans(15.5)),
                                )
                              : NipaSentence(line!,
                                  lead: leadWithTitle ? work.title : null,
                                  maxLines: 1),
                        ),
                      ]),
                    ),
            ),
          ),
          if (preparing != null) preparing!,
          WorkTitle(work: work),
          MetaLine(work),
          if (overview != null && overview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(14.5,
                        color: NextColors.p2, height: 1.75)),
              ),
            ),
          const SizedBox(height: 26),
          Row(children: [
            if (work.next?.playable ?? false) ...[
              PlayButton(label: Words.play(work), onTap: onPlay),
              const SizedBox(width: 12),
            ],
            NextButton.ghost(label: '详情', onTap: onDetail),
          ]),
        ],
      ),
    );
  }
}

/// State C: “正在准备” under Nipa's line — cover, name, a thin bar; tap to
/// see the steps.
class PreparingLine extends StatefulWidget {
  const PreparingLine({super.key, required this.tasks, this.preparation});
  final List<UiTask> tasks;
  final UiPreparationCard? preparation;

  @override
  State<PreparingLine> createState() => _PreparingLineState();
}

class _PreparingLineState extends State<PreparingLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.tasks.firstWhere((t) => t.state == UiTaskState.running,
        orElse: () => widget.tasks.first);
    final prep = widget.preparation;
    return Padding(
      padding: const EdgeInsets.only(left: 40, top: 4, bottom: 4),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: NextMotion.ease,
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Pressable(
              onTap: () => setState(() => _open = !_open),
              pressScale: 0.99,
              semanticLabel: '正在准备',
              builder: (context, hovered) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 32,
                    decoration:
                        BoxDecoration(borderRadius: BorderRadius.circular(4)),
                    clipBehavior: Clip.antiAlias,
                    child: PosterArt(
                        task.artwork?.poster ?? task.artwork?.backdrop,
                        tint: task.artwork?.tint,
                        read: false),
                  ),
                  const SizedBox(width: 12),
                  Text('正在准备',
                      style: NextText.sans(12.5,
                          weight: FontWeight.w600, color: NextColors.accent2)),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NextText.sans(12.5,
                            color: hovered ? NextColors.paper : NextColors.p2)),
                  ),
                  const SizedBox(width: 12),
                  ThinBar(
                      progress: task.progress ?? 0,
                      width: 120,
                      live: task.state == UiTaskState.running),
                  const SizedBox(width: 12),
                  NumText(Words.task(task),
                      style: NextText.sans(12.5, color: NextColors.p2)),
                ],
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: 420,
                  child: prep != null
                      ? PreparationCardView(card: prep)
                      : CardSurface(
                          padding: const EdgeInsets.all(12),
                          child: Column(children: [
                            for (final (i, t) in widget.tasks.indexed) ...[
                              if (i > 0) const SizedBox(height: 12),
                              TaskRow(
                                  task: t, callbacks: const CardCallbacks()),
                            ]
                          ]),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
