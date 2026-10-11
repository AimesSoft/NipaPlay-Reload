import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../theme/tokens.dart';
import '../widgets/art_origin.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import '../widgets/words.dart';

/// Callbacks a rendered card may use. Cards reference objects; their live
/// state comes from NipaPlay, and tapping goes to the object's page.
class CardCallbacks {
  const CardCallbacks({
    this.onOpen,
    this.onPlay,
    this.onFocus,
    this.onPauseTask,
    this.onResumeTask,
    this.onCancelTask,
  });
  final void Function(UiWork work)? onOpen;
  final void Function(UiWork work, UiEpisode? episode)? onPlay;

  /// Hovered or selected work: the backdrop follows it.
  final void Function(UiWork work)? onFocus;
  final void Function(UiTask task)? onPauseTask;
  final void Function(UiTask task)? onResumeTask;
  final void Function(UiTask task)? onCancelTask;
}

/// Agent-presented cards, appearing one by one (12 px rise and fade, 60 ms
/// apart). Candidates lie in a row; other cards stack.
class CardStack extends StatelessWidget {
  const CardStack({
    super.key,
    required this.cards,
    required this.callbacks,
    this.focusedWorkId,
    this.width = 460,
  });

  final List<UiCard> cards;
  final CardCallbacks callbacks;
  final String? focusedWorkId;
  final double width;

  @override
  Widget build(BuildContext context) {
    var flat = 0;
    final children = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      if (i > 0) children.add(const SizedBox(height: 14));
      switch (card) {
        case UiCandidatesCard(:final items):
          children.add(Wrap(spacing: 18, runSpacing: 18, children: [
            for (var j = 0; j < items.length; j++)
              StaggerIn(
                key: ValueKey('pick-$i-$j-${items[j].work.workId}'),
                index: flat++,
                child: PosterCard(
                  workId: items[j].work.workId,
                  image: items[j].work.artwork.poster,
                  tint: items[j].work.artwork.tint,
                  title: items[j].work.title,
                  reason: items[j].reason,
                  selected: items[j].work.workId == focusedWorkId,
                  onOpen: callbacks.onOpen == null
                      ? null
                      : () => callbacks.onOpen!(items[j].work),
                  onPlay: callbacks.onPlay == null ||
                          !Words.canPlay(items[j].work)
                      ? null
                      : () =>
                          callbacks.onPlay!(items[j].work, items[j].work.next),
                  onHover: (on) {
                    if (on) callbacks.onFocus?.call(items[j].work);
                  },
                ),
              ),
          ]));
        default:
          children.add(StaggerIn(
            key: ValueKey('card-$i-${card.runtimeType}'),
            index: flat++,
            child: SizedBox(
              width: width,
              child: switch (card) {
                UiWorkCard(:final work) => WorkRowCard(
                    work: work,
                    selected: work.workId == focusedWorkId,
                    callbacks: callbacks),
                UiEpisodeCard(:final work, :final episode) => EpisodeCardView(
                    work: work, episode: episode, callbacks: callbacks),
                UiPreparationCard() => PreparationCardView(card: card),
                UiTaskCard(:final task) => CardSurface(
                    padding: const EdgeInsets.all(12),
                    child: TaskRow(task: task, callbacks: callbacks)),
                UiCandidatesCard() => const SizedBox.shrink(),
              },
            ),
          ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// Appears once, [index] × 60 ms after mounting: rise 12 px and fade in.
class StaggerIn extends StatefulWidget {
  const StaggerIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: NextMotion.ease);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(NextMotion.cardStagger * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: reduced
            ? child
            : Transform.translate(
                offset: Offset(0, 12 * (1 - _t.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// `.cardx`: the quiet card surface.
class CardSurface extends StatelessWidget {
  const CardSurface(
      {super.key,
      required this.child,
      this.padding = EdgeInsets.zero,
      this.selected = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? const Color(0x14FFFFFF) : const Color(0x0BFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: selected ? NextColors.line2 : NextColors.line),
        ),
        child: child,
      );
}

/// `.cardx.work`: poster, title, one meta line, a chevron.
class WorkRowCard extends StatelessWidget {
  const WorkRowCard(
      {super.key,
      required this.work,
      required this.callbacks,
      this.selected = false});
  final UiWork work;
  final CardCallbacks callbacks;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (work.ratings.isNotEmpty)
        '★ ${work.ratings.first.value.toStringAsFixed(1)}',
      if (work.year != null) '${work.year}',
      if (work.episodeCount != null) '${work.episodeCount} 集',
    ].join(' · ');
    return Pressable(
      onTap: callbacks.onOpen == null ? null : () => callbacks.onOpen!(work),
      onHover: (on) {
        if (on) callbacks.onFocus?.call(work);
      },
      pressScale: 0.99,
      builder: (context, hovered) => CardSurface(
        selected: selected || hovered,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 52,
            height: 74,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 6))
              ],
            ),
            child: ArtOrigin(
              workId: work.workId,
              image: work.artwork.poster,
              tint: work.artwork.tint,
              shape: ArtShape.poster,
              radius: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: NextImage(work.artwork.poster,
                    shape: ArtShape.poster, tint: work.artwork.tint),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(15, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                NumText(meta,
                    style:
                        NextText.sans(12, color: NextColors.p3, height: 1.6)),
              ],
            ),
          ),
          NextIcon(NextGlyph.chevronRight,
              size: 14, color: hovered ? NextColors.paper : NextColors.p2),
        ]),
      ),
    );
  }
}

/// An episode: 16:9 still with the big number; below, the work (or the
/// episode title when [showWork] is off) and runtime.
class EpisodeCardView extends StatelessWidget {
  const EpisodeCardView(
      {super.key,
      required this.work,
      required this.episode,
      required this.callbacks,
      this.width = 256,
      this.showWork = true});
  final UiWork work;
  final UiEpisode episode;
  final CardCallbacks callbacks;
  final double width;
  final bool showWork;

  @override
  Widget build(BuildContext context) {
    final number = episode.number.toString().padLeft(2, '0');
    final second = [
      if (showWork) Words.episode(episode.number),
      if (episode.title != null && episode.title!.isNotEmpty) episode.title!,
    ].join(' · ');
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(children: [
              WideCard(
                workId: work.workId,
                image: episode.still ?? work.artwork.backdrop,
                tint: work.artwork.tint,
                width: width,
                height: width * 9 / 16,
                progress: episode.progress,
                selected: false,
                onOpen: callbacks.onOpen == null
                    ? null
                    : () => callbacks.onOpen!(work),
                onPlay: callbacks.onPlay == null || !episode.playable
                    ? null
                    : () => callbacks.onPlay!(work, episode),
                onHover: (on) {
                  if (on) callbacks.onFocus?.call(work);
                },
              ),
              Positioned(
                left: 12,
                bottom: episode.progress == null ? 10 : 20,
                child: IgnorePointer(
                  child: Text(number,
                      style: NextText.num(28,
                          weight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: const Color(0xEBFFFFFF))),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(showWork ? work.title : (episode.title ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13.5, weight: FontWeight.w600)),
              ),
              if (episode.runtime != null)
                NumText(Words.runtime(episode.runtime!),
                    style: NextText.sans(12, color: NextColors.p3)),
            ]),
            if (showWork && second.isNotEmpty) ...[
              const SizedBox(height: 3),
              NumText(second, style: NextText.sans(12, color: NextColors.p3)),
            ],
          ],
        ),
      ),
    );
  }
}

/// `.prep`: steps with marks, a connecting line, live progress.
class PreparationCardView extends StatelessWidget {
  const PreparationCardView(
      {super.key, required this.card, this.surface = true});
  final UiPreparationCard card;
  final bool surface;

  static StepMarkState mark(UiStepState s) => switch (s) {
        UiStepState.done => StepMarkState.done,
        UiStepState.running => StepMarkState.running,
        UiStepState.waiting => StepMarkState.waiting,
        UiStepState.failed => StepMarkState.failed,
      };

  @override
  Widget build(BuildContext context) {
    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < card.steps.length; i++)
          _StepRow(step: card.steps[i], last: i == card.steps.length - 1),
      ],
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(card.title,
              style: NextText.sans(13, weight: FontWeight.w600)),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: steps),
      ],
    );
    return surface ? CardSurface(child: body) : body;
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.last});
  final UiStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final waiting = step.state == UiStepState.waiting;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(children: [
              const SizedBox(height: 6),
              StepMark(PreparationCardView.mark(step.state)),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.only(top: 3),
                    color: NextColors.line2,
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6, bottom: last ? 0 : 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.label,
                      style: NextText.sans(13.5,
                          weight: FontWeight.w600,
                          color: waiting ? NextColors.p2 : NextColors.paper)),
                  if (step.detail != null && step.detail!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    NumText(step.detail!,
                        style: NextText.sans(12,
                            color: NextColors.p3, height: 1.55)),
                  ],
                  if (step.state == UiStepState.running &&
                      step.progress != null) ...[
                    const SizedBox(height: 9),
                    ThinBar(
                        progress: step.progress!,
                        height: 4,
                        live: true,
                        track: const Color(0x1AFFFFFF)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A background task: thumbnail, name, thin bar, remaining time, pause and
/// cancel.
class TaskRow extends StatelessWidget {
  const TaskRow({super.key, required this.task, required this.callbacks});
  final UiTask task;
  final CardCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final running = task.state == UiTaskState.running;
    final paused = task.state == UiTaskState.paused;
    return Row(children: [
      Container(
        width: 64,
        height: 36,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        clipBehavior: Clip.antiAlias,
        child: NextImage(task.artwork?.backdrop ?? task.artwork?.poster,
            tint: task.artwork?.tint),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(13.5, weight: FontWeight.w600)),
            const SizedBox(height: 7),
            ThinBar(
              progress: task.progress ?? 0,
              live: running,
              fill: running ? null : NextColors.p3,
              track: const Color(0x1AFFFFFF),
            ),
            const SizedBox(height: 6),
            NumText(Words.task(task),
                style: NextText.sans(11.5, color: NextColors.p3)),
          ],
        ),
      ),
      const SizedBox(width: 10),
      if (running && callbacks.onPauseTask != null)
        _MiniButton(
            glyph: NextGlyph.pause,
            label: '暂停',
            onTap: () => callbacks.onPauseTask!(task)),
      if (paused && callbacks.onResumeTask != null)
        _MiniButton(
            glyph: NextGlyph.play,
            label: '继续',
            onTap: () => callbacks.onResumeTask!(task)),
      if (callbacks.onCancelTask != null) ...[
        const SizedBox(width: 6),
        _MiniButton(
            glyph: NextGlyph.close,
            label: '取消',
            onTap: () => callbacks.onCancelTask!(task)),
      ],
    ]);
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton(
      {required this.glyph, required this.label, required this.onTap});
  final NextGlyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0x1FFFFFFF) : const Color(0x0DFFFFFF),
            border: Border.all(color: NextColors.line),
          ),
          child: NextIcon(glyph,
              size: 12, color: hovered ? NextColors.paper : NextColors.p2),
        ),
      );
}
