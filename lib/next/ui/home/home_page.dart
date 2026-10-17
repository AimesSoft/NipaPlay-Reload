import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../chat/chat_frame.dart';
import '../conversation/nipa_chat.dart';
import '../shell/nipa_setup.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../settings/section_accounts.dart' show SourcesSection;
import '../settings/settings_layout.dart' show SettingsSection;
import '../widgets/attachments.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/drop_zone.dart';
import '../widgets/icons.dart';
import '../widgets/shelf.dart';
import '../widgets/words.dart';
import 'ask_bar.dart';
import 'hero_backdrop.dart';
import 'hero_copy.dart';
import 'hero_danmaku.dart';

/// The home: the hero, the input bar and the shelves; and the conversation
/// with Nipa, expanded over them or folded away. Saying something on the
/// bar goes into the conversation and expands it; folding it leaves it
/// going on, with Nipa's line on the hero telling what it is doing and,
/// afterwards, how it ended.
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

  /// The shelf card held for 600 ms, previewed in the hero.
  UiWork? _shelfFocus;
  Timer? _focusTimer;
  Timer? _seenTimer;

  /// The card hovered in the expanded conversation.
  UiWork? _chatFocus;

  /// After a conversation, the work it settled on.
  UiWork? _heroOverride;
  bool _wasOpen = false;

  /// Shelves rebuild only when the home data changes, not per reply delta.
  Widget? _shelves;
  UiHome? _shelvesFor;

  NipaChat get _chat => _shell!.chat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell?.homeChatOpen.removeListener(_openChanged);
    _changes?.cancel();
    _shell = shell;
    _wasOpen = shell.homeChatOpen.value;
    shell.homeChatOpen.addListener(_openChanged);
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

  void _openChanged() {
    final open = _shell!.homeChatOpen.value;
    if (open == _wasOpen) return;
    _wasOpen = open;
    _focusTimer?.cancel();
    _shelfFocus = null;
    _chatFocus = null;
    if (!open) {
      // Folded: the work the conversation settled on takes the hero.
      final settled = _chat.settledWork;
      if (settled != null && settled.workId != _baseHero()?.workId) {
        _heroOverride = settled;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _shell?.homeChatOpen.removeListener(_openChanged);
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

  /// The shelf work previewed in place of [hero]: not with reduced motion,
  /// and not when it is the hero already.
  UiWork? _preview(UiWork? hero, {required bool reduced}) =>
      reduced || _shelfFocus?.workId == hero?.workId ? null : _shelfFocus;

  /// The work the expanded conversation is about: hovered, else the first
  /// one its last turn presented.
  UiWork? _chatWork() {
    if (_chatFocus != null) return _chatFocus;
    for (final card in _chat.turns.lastOrNull?.cards ?? const <UiCard>[]) {
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

  // —— Interaction ——

  /// Said on the bar: into the conversation, which opens.
  void _say(String text) {
    _heroOverride = null;
    unawaited(_chat.say(text));
    _shell!.openChat();
  }

  /// A card held still for 600 ms is previewed; 300 ms after the pointer
  /// leaves the shelf the hero returns. Crossing cards only restarts the
  /// wait, so a quick pass changes nothing.
  void _hoverShelf(UiWork work, bool on) {
    if (NextMotion.reduced(context) || _shell!.homeChatOpen.value) return;
    _focusTimer?.cancel();
    _focusTimer = Timer(on ? NextMotion.hoverFocus : _previewLinger, () {
      if (mounted) setState(() => _shelfFocus = on ? work : null);
    });
  }

  CardCallbacks get _chatCallbacks => CardCallbacks(
        onOpen: _shell!.openWork,
        onPlay: (work, episode) => _shell!.play(work, episode: episode),
        onFocus: (work) {
          if (_chatFocus?.workId != work.workId) {
            setState(() => _chatFocus = work);
          }
        },
        onPauseTask: (t) => _shell!.services.actions.pauseTask(t.taskId),
        onResumeTask: (t) => _shell!.services.actions.resumeTask(t.taskId),
        onCancelTask: (t) => _shell!.services.actions.cancelTask(t.taskId),
        onChoose: (answer) => unawaited(_shell!.chat.say(answer)),
      );

  // —— Building ——

  @override
  Widget build(BuildContext context) {
    final shell = _shell!;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return ListenableBuilder(
        listenable: Listenable.merge([_chat, shell.homeChatOpen]),
        builder: (context, _) {
          final open = shell.homeChatOpen.value;
          final reduced = NextMotion.reduced(context);
          final hero = _heroWork();
          final preview = open ? null : _preview(hero, reduced: reduced);
          final backdropWork = open
              ? (reduced ? hero : (_chatWork() ?? hero))
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
                staged: open,
                scroll: _scroll,
                viewport: size,
                fade: open ? NextMotion.crossfade : _previewFade,
              ),
            ),
            if (!open) _danmaku(size, preview ?? hero),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: open
                  ? _HomeChat(key: const ValueKey('chat'), page: this)
                  : CustomScrollView(
                      key: const ValueKey('home'),
                      controller: _scroll,
                      slivers: [
                        SliverToBoxAdapter(child: _region(size, hero, preview)),
                        SliverToBoxAdapter(child: _shelvesWidget()),
                        const SliverToBoxAdapter(child: SizedBox(height: 64)),
                      ],
                    ),
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

  /// Nothing in the library yet: no hero and no shelves to show.
  bool get _isEmpty {
    final home = _home;
    return home != null && home.hero == null && home.shelves.isEmpty;
  }

  Widget _shelvesWidget() {
    if (_shelves == null || !identical(_shelvesFor, _home)) {
      _shelvesFor = _home;
      _shelves = _Shelves(home: _home, page: this);
    }
    return _shelves!;
  }

  /// The hero with Nipa's line, then the input bar.
  Widget _region(Size size, UiWork? hero, UiWork? preview) {
    final c = _chat;
    final h = size.height;
    final shell = _shell!;
    final heroNote = _heroOverride == null ? _home?.hero?.note : null;
    final line = c.doing ?? c.latestLine ?? heroNote;
    // The line on the home is the news itself: once it has been on screen
    // for a moment, the avatar's dot goes away.
    if (c.unseen &&
        line == c.latestLine &&
        TickerMode.valuesOf(context).enabled) {
      _seenTimer ??= Timer(const Duration(seconds: 3), () {
        _seenTimer = null;
        if (mounted && TickerMode.valuesOf(context).enabled) c.markSeen();
      });
    }
    final top = ConstrainedBox(
      constraints: BoxConstraints(minHeight: h - 338, minWidth: size.width),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.only(
              left: NextMetrics.gutter, top: NextMetrics.topBar + 40),
          child: hero == null
              ? (_isEmpty ? _EmptyStart(shell: shell) : const SizedBox.shrink())
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        top,
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.only(left: NextMetrics.gutter),
          child: ListenableBuilder(
            listenable: shell.nipaSetup,
            builder: (context, _) => AskBar(
                focusNode: shell.askFocus,
                controller: shell.askText,
                onSay: _say,
                mood: c.mood,
                moodSentence: c.moodSentence,
                hint: c.running ? '补充，或者改主意' : '今天想看什么？',
                suggestions: _suggestions(),
                aside: shell.nipaSetup.needsModel ? const NipaSetupChip() : null,
                maxWidth: size.width - NextMetrics.gutter - 32,
                attachments: c.attachments,
                onAttach: c.attach,
                onDetach: c.detach,
                running: c.running,
                onStop: c.stop,
                onExpand: c.turns.isEmpty && !c.loading ? null : shell.openChat,
              ),
          ),
        ),
        const SizedBox(height: 34),
      ],
    );
  }
}

/// The conversation expanded over the home: the backdrop stays, dimmed;
/// the conversation takes the page, the composer at its foot. The chevron
/// (or Esc) folds it away again.
class _HomeChat extends StatelessWidget {
  const _HomeChat({super.key, required this.page});
  final _NextHomePageState page;

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    return NextDropZone(
      onDrop: shell.chat.attach,
      builder: (context, over) => Stack(fit: StackFit.expand, children: [
        // The picture stays as the room's light; the words need the dark.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x9908080B), Color(0xC708080B), Color(0xE008080B)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: NextMetrics.topBar + 6),
          child: ChatFrame(
            focusNode: shell.homeChatFocus,
            columnWidth: 780,
            textSize: 15.5,
            posterWidth: 168,
            sidePadding: 40,
            callbacks: page._chatCallbacks,
            trailing: FrameButton(
              glyph: NextGlyph.chevronRight,
              turns: 1,
              label: '收起',
              onTap: shell.foldHomeChat,
            ),
          ),
        ),
        Positioned.fill(child: DropGlow(over: over, radius: BorderRadius.zero)),
      ]),
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


/// The home before there is anything to watch: two ways in besides asking
/// Nipa below.
class _EmptyStart extends StatelessWidget {
  const _EmptyStart({required this.shell});
  final NextShellController shell;

  Future<void> _addFolder() async {
    final folders = shell.services.folders;
    try {
      final added = await folders.add();
      if (added.isNotEmpty) await folders.scan(added);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('片库还是空的',
                style: NextText.sans(34, weight: FontWeight.w700)),
            const SizedBox(height: 22),
            Row(mainAxisSize: MainAxisSize.min, children: [
              NextButton(label: '添加文件夹', onTap: _addFolder),
              const SizedBox(width: 12),
              NextButton.ghost(
                label: '添加来源',
                onTap: () => shell.openSettings(
                    section: SettingsSection.sources,
                    key: SourcesSection.addKey),
              ),
            ]),
          ],
        ),
      );
}
