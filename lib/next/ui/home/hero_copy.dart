import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/progress.dart';
import '../widgets/words.dart';

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
                            size: 28, mood: mood, sentence: moodSentence),
                        const SizedBox(width: 12),
                        Expanded(
                          child: NipaSentence(line!,
                              lead: leadWithTitle ? work.title : null,
                              maxLines: 1),
                        ),
                      ]),
                    ),
            ),
          ),
          if (preparing != null) preparing!,
          _Title(work: work),
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

/// `.logo` (96 high, drop shadow) or the Songti title when there is none.
class _Title extends StatelessWidget {
  const _Title({required this.work});
  final UiWork work;

  /// 64 px as in the concept; long titles step down to stay within two
  /// lines of the 600 px column.
  static double _serifSize(String title) => title.characters.length <= 8
      ? 64
      : title.characters.length <= 12
          ? 52
          : 44;

  @override
  Widget build(BuildContext context) {
    final serif = Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(work.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: NextText.serif(_serifSize(work.title),
              letterSpacing: _serifSize(work.title) * 0.04, height: 1.08)),
    );
    final logo = work.artwork.logo;
    if (logo == null) return serif;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: Transform.translate(
        offset: const Offset(-6, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 96),
          child: SizedBox(
            height: 96,
            child: Stack(clipBehavior: Clip.none, children: [
              // drop-shadow(0 6px 24px rgba(0,0,0,.45)), one small layer.
              Positioned.fill(
                top: 6,
                bottom: -6,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                        Color(0x73000000), BlendMode.srcIn),
                    child: NextImage(logo,
                        shape: ArtShape.logo,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft),
                  ),
                ),
              ),
              Positioned.fill(
                child: NextImage(logo,
                    shape: ArtShape.logo,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft),
              ),
            ]),
          ),
        ),
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
                    child: NextImage(
                        task.artwork?.poster ?? task.artwork?.backdrop,
                        shape: ArtShape.poster,
                        tint: task.artwork?.tint),
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
