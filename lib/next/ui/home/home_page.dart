import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../conversation/conversation.dart';
import '../conversation/next_sayings.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/shelf.dart';
import '../widgets/words.dart';
import 'ask_bar.dart';
import 'hero_backdrop.dart';
import 'hero_copy.dart';
import 'hero_danmaku.dart';
import 'stage.dart';

/// The home: state A (hero, input, shelves), B (talking in place) and C
/// (background work and follow-ups), per INTERACTION.md.
class NextHomePage extends StatefulWidget {
  const NextHomePage({super.key});

  @override
  State<NextHomePage> createState() => _NextHomePageState();
}

class _NextHomePageState extends State<NextHomePage> {
  final _scroll = ScrollController();
  NextShellController? _shell;
  StreamSubscription<void>? _changes;
  UiHome? _home;

  /// A: the shelf card held for 600 ms, previewed in the hero.
  UiWork? _shelfFocus;
  Timer? _focusTimer;
  Timer? _seenTimer;

  /// B: the card hovered or selected on the stage.
  UiWork? _stageFocus;

  /// After a conversation, the work it settled on.
  UiWork? _heroOverride;
  bool _wasStaged = false;

  /// Shelves rebuild only when the home data changes, not per reply delta.
  Widget? _shelves;
  UiHome? _shelvesFor;

  Conversation get _conv => _shell!.conversation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell?.conversation.removeListener(_conversationChanged);
    _changes?.cancel();
    _shell = shell;
    shell.conversation.addListener(_conversationChanged);
    _changes = shell.services.data.changes.listen((_) => _load());
    _load();
  }

  Future<void> _load() async {
    try {
      final home = await _shell!.services.data.home();
      if (mounted) setState(() => _home = home);
    } catch (error) {
      debugPrint('[NextUi] home failed: $error');
    }
  }

  void _conversationChanged() {
    final staged = _conv.staged;
    if (staged == _wasStaged) return;
    _wasStaged = staged;
    if (staged) {
      _stageFocus = null;
      _focusTimer?.cancel();
      _shelfFocus = null;
      if (_scroll.hasClients && _scroll.offset > 0) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 420),
            curve: NextMotion.ease);
      }
    } else {
      final settled = _settledWork();
      if (settled != null && settled.workId != _baseHero()?.workId) {
        _heroOverride = settled;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _shell?.conversation.removeListener(_conversationChanged);
    _changes?.cancel();
    _focusTimer?.cancel();
    _seenTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // —— What to show ——

  UiWork? _baseHero() {
    final home = _home;
    if (home == null) return null;
    if (home.hero != null) return home.hero!.work;
    // Nipa put nothing up: recently ready, then updated, then continue.
    UiShelfItem? first(bool Function(UiShelfItem) test) {
      for (final shelf in home.shelves) {
        for (final item in shelf.items) {
          if (test(item)) return item;
        }
      }
      return null;
    }

    final recent = home.shelves
        .where((s) => s.kind == UiShelfKind.recent)
        .expand((s) => s.items)
        .firstOrNull;
    final airing = home.shelves
        .where((s) => s.kind == UiShelfKind.airing)
        .expand((s) => s.items)
        .firstOrNull;
    return (recent ??
            airing ??
            first((i) => i.badge != null) ??
            home.shelves
                .where((s) => s.kind == UiShelfKind.continueWatching)
                .expand((s) => s.items)
                .firstOrNull)
        ?.work;
  }

  UiWork? _heroWork() => _heroOverride ?? _baseHero();

  /// The shelf work previewed in place of [hero]: not while talking, not
  /// with reduced motion, and not when it is the hero already.
  UiWork? _preview(UiWork? hero,
          {required bool staged, required bool reduced}) =>
      staged || reduced || _shelfFocus?.workId == hero?.workId
          ? null
          : _shelfFocus;

  /// The one work a conversation ended on (a single work or episode card),
  /// which then takes the hero. Candidates or a mere hover settle nothing.
  UiWork? _settledWork() {
    final works = <UiWork>[];
    for (final card in _conv.cards) {
      switch (card) {
        case UiCandidatesCard():
          return null;
        case UiWorkCard(:final work):
          works.add(work);
        case UiEpisodeCard(:final work, :final episode):
          works.add(UiWork(
            workId: work.workId,
            title: work.title,
            originalTitle: work.originalTitle,
            year: work.year,
            genres: work.genres,
            episodeCount: work.episodeCount,
            studio: work.studio,
            overview: work.overview,
            ratings: work.ratings,
            artwork: work.artwork,
            next: episode,
          ));
        default:
      }
    }
    final ids = works.map((w) => w.workId).toSet();
    return ids.length == 1 ? works.last : null;
  }

  /// B's focused work: hovered/selected, else the first one presented.
  UiWork? _stageWork() {
    if (_stageFocus != null) return _stageFocus;
    for (final card in _conv.cards) {
      switch (card) {
        case UiCandidatesCard(:final items) when items.isNotEmpty:
          return items.first.work;
        case UiWorkCard(:final work):
          return work;
        case UiEpisodeCard(:final work):
          return work;
        default:
      }
    }
    return null;
  }

  List<String> _suggestions() {
    final home = _home;
    final out = <String>[];
    if (home != null) {
      final watching = home.shelves
          .where((s) => s.kind == UiShelfKind.continueWatching)
          .expand((s) => s.items)
          .firstOrNull;
      if (watching != null) out.add('接着看《${watching.work.title}》');
      bool other(UiShelfItem i) => i.work.workId != watching?.work.workId;
      final updated = home.shelves
              .where((s) => s.kind == UiShelfKind.airing)
              .expand((s) => s.items)
              .where(other)
              .firstOrNull ??
          home.shelves
              .expand((s) => s.items)
              .where((i) => i.badge != null && other(i))
              .firstOrNull;
      if (updated != null) out.add('${updated.work.title}更新了');
    }
    out.add('来点轻松的');
    return out;
  }

  /// After a round on the stage: what you might say next (the same rules
  /// as the side panel's).
  List<String> _nextSayings() {
    final c = _conv;
    if (c.inProgress || c.question != null || c.reply.isEmpty) return const [];
    return NextSayings.after(c.reply, c.cards);
  }

  // —— Interaction ——

  void _say(String text) {
    _heroOverride = null;
    final files = _shell!.askFiles.value;
    _shell!.askFiles.value = const [];
    _conv.say(text, files: files);
  }

  /// A card held still for 600 ms is previewed; 300 ms after the pointer
  /// leaves the shelf the hero returns. Crossing cards only restarts the
  /// wait, so a quick pass changes nothing.
  void _hoverShelf(UiWork work, bool on) {
    if (NextMotion.reduced(context) || _conv.staged) return;
    _focusTimer?.cancel();
    _focusTimer = Timer(on ? NextMotion.hoverFocus : _previewLinger, () {
      if (mounted) setState(() => _shelfFocus = on ? work : null);
    });
  }

  CardCallbacks get _stageCallbacks => CardCallbacks(
        onOpen: _shell!.openWork,
        onPlay: (work, episode) => _shell!.play(work, episode: episode),
        onFocus: (work) {
          if (_stageFocus?.workId != work.workId) {
            setState(() => _stageFocus = work);
          }
        },
        onPauseTask: (t) => _shell!.services.actions.pauseTask(t.taskId),
        onResumeTask: (t) => _shell!.services.actions.resumeTask(t.taskId),
        onCancelTask: (t) => _shell!.services.actions.cancelTask(t.taskId),
      );

  // —— Building ——

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return ListenableBuilder(
        listenable: _conv,
        builder: (context, _) {
          final staged = _conv.staged;
          final reduced = NextMotion.reduced(context);
          final hero = _heroWork();
          final preview = _preview(hero, staged: staged, reduced: reduced);
          final backdropWork = staged
              ? (reduced ? hero : (_stageWork() ?? hero))
              : (preview ?? hero);
          return Stack(fit: StackFit.expand, children: [
            // The push-in animates every frame: keep it off the page's layer.
            RepaintBoundary(
              child: HeroBackdrop(
                workId: backdropWork?.workId,
                image: backdropWork?.artwork.backdrop ??
                    backdropWork?.artwork.poster,
                soft: backdropWork != null &&
                    backdropWork.artwork.backdrop == null,
                tint: backdropWork?.artwork.tint,
                staged: staged,
                scroll: _scroll,
                viewport: size,
                fade: staged ? NextMotion.crossfade : _previewFade,
              ),
            ),
            if (!staged) _danmaku(size, preview ?? hero),
            CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(child: _region(size, hero, preview)),
                SliverToBoxAdapter(child: _shelvesWidget()),
                const SliverToBoxAdapter(child: SizedBox(height: 64)),
              ],
            ),
          ]);
        },
      );
    });
  }

  /// The hero work's danmaku in the sky, scrolling away with the hero.
  Widget _danmaku(Size size, UiWork? work) {
    final area = HeroDanmaku.area(size);
    return Positioned.fromRect(
      rect: area,
      child: AnimatedBuilder(
        animation: _scroll,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _scroll.hasClients ? -_scroll.offset : 0),
          child: child,
        ),
        child: AnimatedSwitcher(
          duration: _previewFade,
          child: HeroDanmaku(
              key: ValueKey(work?.workId), lines: work?.danmaku ?? const []),
        ),
      ),
    );
  }

  Widget _shelvesWidget() {
    if (_shelves == null || !identical(_shelvesFor, _home)) {
      _shelvesFor = _home;
      _shelves = _Shelves(home: _home, page: this);
    }
    return _shelves!;
  }

  Widget _region(Size size, UiWork? hero, UiWork? preview) {
    final c = _conv;
    final staged = c.staged;
    final h = size.height;
    final shell = _shell!;
    final Widget top;
    if (staged) {
      top = ConstrainedBox(
        key: const ValueKey('stage'),
        constraints: BoxConstraints(minHeight: h - 288, minWidth: size.width),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: NextMetrics.gutter, top: 118),
            child: ConverseStage(
              conversation: c,
              callbacks: _stageCallbacks,
              focusedWorkId: _stageWork()?.workId,
              onViewAll: c.threadId == null
                  ? null
                  : () => shell.openPanelOn(c.threadId!),
            ),
          ),
        ),
      );
    } else {
      final heroNote = _heroOverride == null ? _home?.hero?.note : null;
      final line = c.backgroundActive
          ? (c.activity ?? '在忙')
          : (c.latestLine ?? heroNote);
      // The line on the home is the news itself: once it has been on
      // screen for a moment, the avatar's dot goes away.
      if (c.unseen &&
          line == c.latestLine &&
          TickerMode.valuesOf(context).enabled) {
        _seenTimer ??= Timer(const Duration(seconds: 3), () {
          _seenTimer = null;
          if (mounted && TickerMode.valuesOf(context).enabled) c.markSeen();
        });
      }
      top = ConstrainedBox(
        key: const ValueKey('hero'),
        constraints: BoxConstraints(minHeight: h - 338, minWidth: size.width),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(
                left: NextMetrics.gutter, top: NextMetrics.topBar + 40),
            child: hero == null
                ? const SizedBox.shrink()
                : ValueListenableBuilder(
                    valueListenable: shell.tasks,
                    builder: (context, _, __) {
                      final active = shell.activeTasks;
                      return _HeroPreview(
                        preview: preview == null
                            ? null
                            : HeroCopy(
                                key: ValueKey(preview.workId),
                                work: preview,
                                line: null,
                                mood: c.mood,
                                moodSentence: c.moodSentence,
                                onPlay: () => shell.play(preview),
                                onDetail: () => shell.openWork(preview),
                              ),
                        child: HeroCopy(
                          work: hero,
                          line: line,
                          leadWithTitle: line != null && line == heroNote,
                          mood: c.mood,
                          moodSentence: c.moodSentence,
                          onPlay: () => shell.play(hero),
                          onDetail: () => shell.openWork(hero),
                          preparing: active.isEmpty
                              ? null
                              : PreparingLine(
                                  tasks: active,
                                  preparation: c.latestPreparation),
                        ),
                      );
                    },
                  ),
          ),
        ),
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 480),
      curve: NextMotion.ease,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, if (current != null) current],
            ),
            child: top,
          ),
          SizedBox(height: staged ? 28 : 32),
          Padding(
            padding: const EdgeInsets.only(left: NextMetrics.gutter),
            child: ListenableBuilder(
              listenable: Listenable.merge([shell.askFiles, shell.panelOpen]),
              builder: (context, _) => AskBar(
                focusNode: shell.askFocus,
                controller: shell.askText,
                onSay: _say,
                mood: c.mood,
                moodSentence: c.moodSentence,
                hint: c.question != null
                    ? '也可以直接说'
                    : (staged ? '继续说…' : '今天想看什么？'),
                suggestions: staged ? _nextSayings() : _suggestions(),
                maxWidth: size.width - NextMetrics.gutter - 32,
                attachments: shell.askFiles.value,
                // While the panel is open, files go there.
                onAttach: shell.panelOpen.value
                    ? null
                    : (paths) => shell.askFiles.value = [
                          ...shell.askFiles.value,
                          for (final p in paths)
                            if (!shell.askFiles.value.contains(p)) p
                        ],
                onDetach: (path) => shell.askFiles.value = [
                  for (final p in shell.askFiles.value)
                    if (p != path) p
                ],
              ),
            ),
          ),
          SizedBox(height: staged ? 40 : 34),
        ],
      ),
    );
  }
}

const _previewFade = Duration(milliseconds: 400);
const _previewLinger = Duration(milliseconds: 300);

/// The hero's copy with a shelf preview over it. The copy keeps its place,
/// so the shelves (and the card under the pointer) never move, and fades
/// out with Nipa's line and the preparing line; the previewed work's copy,
/// bottom-aligned with it, fades in.
class _HeroPreview extends StatelessWidget {
  const _HeroPreview({required this.preview, required this.child});
  final Widget? preview;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomLeft,
        children: [
          AnimatedOpacity(
            opacity: preview == null ? 1 : 0,
            duration: _previewFade,
            curve: Curves.easeInOut,
            child: IgnorePointer(ignoring: preview != null, child: child),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: _previewFade,
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              layoutBuilder: (current, previous) => Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomLeft,
                children: [...previous, if (current != null) current],
              ),
              child: preview ?? const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
        ],
      );
}

/// The shelves: continue watching (16:9 with progress), Nipa's shelves
/// (posters with a reason), recently added.
class _Shelves extends StatelessWidget {
  const _Shelves({required this.home, required this.page});
  final UiHome? home;
  final _NextHomePageState page;

  @override
  Widget build(BuildContext context) {
    final shelves =
        home?.shelves.where((s) => s.items.isNotEmpty).toList() ?? const [];
    final shell = NextShellScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, shelf) in shelves.indexed) ...[
          if (i > 0) const SizedBox(height: 40),
          if (shelf.kind == UiShelfKind.agent)
            Shelf(
              title: shelf.title,
              storageKey: 'shelf-${shelf.id}',
              height: 252 + 12 + 22 + 4 + 40,
              gap: 18,
              itemCount: shelf.items.length,
              itemBuilder: (context, j) {
                final item = shelf.items[j];
                return PosterCard(
                  workId: item.work.workId,
                  image: item.work.artwork.poster,
                  tint: item.work.artwork.tint,
                  title: item.work.title,
                  reason: item.caption,
                  onOpen: () => shell.openWork(item.work),
                  onPlay: Words.canPlay(item.work, item.episode)
                      ? () => shell.play(item.work, episode: item.episode)
                      : null,
                  onHover: (on) => page._hoverShelf(item.work, on),
                );
              },
            )
          else
            Shelf(
              title: shelf.title,
              storageKey: 'shelf-${shelf.id}',
              height: 150,
              itemCount: shelf.items.length,
              itemBuilder: (context, j) {
                final item = shelf.items[j];
                final progress = item.episode?.progress;
                return WideCard(
                  workId: item.work.workId,
                  image: item.episode?.still != null &&
                          shelf.kind == UiShelfKind.continueWatching &&
                          item.work.artwork.backdrop == null
                      ? item.episode!.still
                      : item.work.artwork.backdrop,
                  poster: item.work.artwork.poster,
                  tint: item.work.artwork.tint,
                  title: item.work.title,
                  caption: item.caption,
                  badge: item.badge,
                  progress: progress != null && progress < 1 ? progress : null,
                  onOpen: () => shell.openWork(item.work),
                  onPlay: Words.canPlay(item.work, item.episode)
                      ? () => shell.play(item.work, episode: item.episode)
                      : null,
                  onHover: (on) => page._hoverShelf(item.work, on),
                );
              },
            ),
        ],
      ],
    );
  }
}
