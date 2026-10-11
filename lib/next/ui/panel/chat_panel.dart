import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../conversation/next_sayings.dart';
import '../conversation/panel_chat.dart';
import '../data/login_requests.dart';
import '../home/stage.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/activity_line.dart';
import '../widgets/artwork.dart';
import '../widgets/attachments.dart';
import '../widgets/buttons.dart';
import '../widgets/drop_zone.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/progress.dart';
import '../widgets/words.dart';

/// The conversation side panel (INTERACTION.md「对话侧面板」, concept
/// `?v=chat`): it slides in from the right on a 420 ms spring while the page
/// behind blurs and darkens; Esc or a click outside closes it.
class ChatPanelLayer extends StatefulWidget {
  const ChatPanelLayer({super.key});

  @override
  State<ChatPanelLayer> createState() => _ChatPanelLayerState();
}

class _ChatPanelLayerState extends State<ChatPanelLayer>
    with SingleTickerProviderStateMixin {
  static const _open = Duration(milliseconds: 420);
  static const _spring = _SpringCurve();
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: _open,
      reverseDuration: const Duration(milliseconds: 260));
  NextShellController? _shell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell?.panelOpen.removeListener(_sync);
    _shell = shell..panelOpen.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (_shell!.panelOpen.value) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _shell?.panelOpen.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = _shell!;
    const sheet = RepaintBoundary(child: _Sheet());
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.isDismissed) return const SizedBox.shrink();
        final t = _c.value;
        final reduced = NextMotion.reduced(context);
        final closing = _c.status == AnimationStatus.reverse;
        final slide = reduced
            ? 1.0
            : (closing
                ? Curves.easeOutCubic.transform(t)
                : _spring.transform(t));
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: shell.closePanel,
              child: _Dim(t),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            bottom: 12,
            width: 496,
            child: Opacity(
              opacity: reduced ? t : math.min(1, t * 3),
              child: Transform.translate(
                offset: Offset((1 - slide) * 540, 0),
                child: sheet,
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// A damped spring that settles within the animation's 420 ms, with a
/// slight overshoot.
class _SpringCurve extends Curve {
  const _SpringCurve();
  static final _sim = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 188, damping: 21.9), 0, 1, 0);

  @override
  double transformInternal(double t) => _sim.x(t * 0.42);
}

/// `.dim`: the page behind blurs (6) and darkens (35 %).
class _Dim extends StatelessWidget {
  const _Dim(this.t);
  final double t;

  @override
  Widget build(BuildContext context) {
    final shade = ColoredBox(color: Color.fromRGBO(6, 6, 9, 0.35 * t));
    if (t <= 0.01) return shade;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: Glass.saturation(1 + 0.2 * t),
          inner: ui.ImageFilter.blur(
              sigmaX: 6 * t, sigmaY: 6 * t, tileMode: TileMode.clamp),
        ),
        child: shade,
      ),
    );
  }
}

/// `.sheet`: header, the work it is about, the thread (with the session
/// menu over it), what is under way, the input. Files dropped anywhere on
/// it go with what you say next.
class _Sheet extends StatelessWidget {
  const _Sheet();

  static final _radius = BorderRadius.circular(24);

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    return NextDropZone(
      onDrop: shell.panel.attach,
      builder: (context, over) => Stack(children: [
        Positioned.fill(child: _body(shell)),
        Positioned.fill(child: DropGlow(over: over, radius: _radius)),
      ]),
    );
  }

  Widget _body(NextShellController shell) => Glass(
        blur: 40,
        color: const Color(0xBD121218), // rgba(18,18,24,.74)
        borderColor: const Color(0x1AFFFFFF),
        radius: _radius,
        highlight: false,
        shadows: const [
          BoxShadow(
              color: Color(0x80000000), blurRadius: 80, offset: Offset(-30, 0)),
        ],
        child: ListenableBuilder(
          listenable: Listenable.merge([shell.panel, shell.services.logins]),
          builder: (context, _) {
            final panel = shell.panel;
            final underway = panel.underway;
            return Column(children: [
              _Header(panel: panel, logins: shell.services.logins),
              if (panel.about case final work?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _AboutTag(work: work, onRemove: panel.dropAbout),
                  ),
                ),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(child: _Thread(panel: panel)),
                  if (panel.menuOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: panel.closeMenu,
                      ),
                    ),
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 6,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale:
                              Tween(begin: 0.98, end: 1.0).animate(animation),
                          alignment: Alignment.topLeft,
                          child: child,
                        ),
                      ),
                      child: panel.menuOpen
                          ? _SessionMenu(
                              key: const ValueKey('menu'), panel: panel)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ]),
              ),
              if (underway.isNotEmpty) _UnderwayBar(items: underway),
              _Compose(panel: panel),
            ]);
          },
        ),
      );
}

/// “关于《X》”: the panel was opened from this work's page, and what you say
/// goes with it until × takes it off.
class _AboutTag extends StatelessWidget {
  const _AboutTag({required this.work, required this.onRemove});
  final UiWork work;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.fromLTRB(5, 5, 4, 5),
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NextColors.line2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 15,
              height: 22,
              child: NextImage(work.artwork.poster,
                  shape: ArtShape.poster, tint: work.artwork.tint),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text('关于《${work.title}》',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(12.5, color: NextColors.p2)),
          ),
          const SizedBox(width: 2),
          Pressable(
            onTap: onRemove,
            semanticLabel: '不再关于这部',
            builder: (context, hovered) => Padding(
              padding: const EdgeInsets.all(6),
              child: NextIcon(NextGlyph.close,
                  size: 10,
                  color: hovered ? NextColors.paper : NextColors.p3),
            ),
          ),
        ]),
      );
}

/// `.sh`: Nipa's avatar and name (the name opens the sessions), close.
/// Away from the main session the name gives way to that session's title.
class _Header extends StatelessWidget {
  const _Header({required this.panel, required this.logins});
  final PanelChat panel;
  final LoginRequests logins;

  static String _title(PanelChat panel) {
    if (panel.choice.onMain) return 'Nipa';
    final id = panel.thread;
    if (id == null) return '新的对话';
    return panel.sessions.where((s) => s.id == id).firstOrNull?.title ??
        'Nipa';
  }

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final mood = logins.pending.isNotEmpty ? NipaMood.waiting : panel.mood;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NextColors.line))),
      child: Row(children: [
        NipaAvatar(
          size: 42,
          mood: mood,
          sentence: switch (mood) {
            NipaMood.waiting => '在等你',
            NipaMood.acting => '在忙',
            NipaMood.thinking => '在想',
            NipaMood.idle => null,
          },
        ),
        const SizedBox(width: 14),
        Pressable(
          onTap: panel.toggleMenu,
          semanticLabel: '对话',
          pressScale: 0.98,
          builder: (context, hovered) => Row(children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(_title(panel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(16, weight: FontWeight.w600)),
            ),
            const SizedBox(width: 7),
            AnimatedRotation(
              turns: panel.menuOpen ? -0.25 : 0.25,
              duration: const Duration(milliseconds: 180),
              child: NextIcon(NextGlyph.chevronRight,
                  size: 11,
                  color: hovered || panel.menuOpen
                      ? NextColors.p2
                      : NextColors.p4),
            ),
          ]),
        ),
        const Spacer(),
        Pressable(
          onTap: shell.closePanel,
          semanticLabel: '关闭',
          builder: (context, hovered) => NextIcon(NextGlyph.close,
              size: 18, color: hovered ? NextColors.paper : NextColors.p3),
        ),
      ]),
    );
  }
}

/// The main session on top, then a new conversation, then the others,
/// latest first, each titled by its first sentence.
class _SessionMenu extends StatelessWidget {
  const _SessionMenu({super.key, required this.panel});
  final PanelChat panel;

  static String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    String two(int n) => n.toString().padLeft(2, '0');
    if (days == 0) return '${two(at.hour)}:${two(at.minute)}';
    if (days == 1) return '昨天';
    if (at.year == now.year) return '${at.month} 月 ${at.day} 日';
    return '${at.year} 年 ${at.month} 月';
  }

  @override
  Widget build(BuildContext context) {
    final main = panel.choice.main;
    final mainSession =
        panel.sessions.where((s) => s.id == main).firstOrNull;
    final others = [
      for (final s in panel.sessions)
        if (s.id != main) s
    ];
    Widget divider() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        color: NextColors.line);
    return Container(
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NextColors.line2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 16)),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _MenuRow(
            title: '主对话',
            when: _when(mainSession?.at),
            current: panel.choice.onMain,
            onTap: panel.selectMain,
          ),
          _MenuRow(
            title: '新的对话',
            glyph: NextGlyph.plus,
            current: panel.choice.fresh,
            onTap: panel.startNew,
          ),
          if (others.isNotEmpty) divider(),
          for (final s in others)
            _MenuRow(
              title: s.title,
              when: _when(s.at),
              current: s.id == panel.thread && !panel.choice.onMain,
              onTap: () => panel.select(s.id),
            ),
        ]),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
      {required this.title,
      required this.current,
      required this.onTap,
      this.when,
      this.glyph});
  final String title;
  final String? when;
  final NextGlyph? glyph;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: title,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hovered || current
                ? const Color(0x12FFFFFF)
                : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            if (glyph case final g?) ...[
              NextIcon(g,
                  size: 12,
                  color: current || hovered ? NextColors.paper : NextColors.p3),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13.5,
                      weight: current ? FontWeight.w600 : FontWeight.w400,
                      color: current || hovered
                          ? NextColors.paper
                          : NextColors.p2)),
            ),
            if (when != null && when!.isNotEmpty) ...[
              const SizedBox(width: 12),
              NumText(when!, style: NextText.sans(11.5, color: NextColors.p3)),
            ],
          ]),
        ),
      );
}

/// `.thread`: your bubbles, Nipa's words, the cards between them; then
/// whatever waits for you, and the waiting itself.
class _Thread extends StatelessWidget {
  const _Thread({required this.panel});
  final PanelChat panel;

  static const width = 456.0;

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final logins = shell.services.logins;
    final actions = shell.services.actions;
    final callbacks = CardCallbacks(
      onOpen: (work) {
        shell.closePanel();
        shell.openWork(work);
      },
      onPlay: (work, episode) => shell.play(work, episode: episode),
      onPauseTask: (t) => actions.pauseTask(t.taskId),
      onResumeTask: (t) => actions.resumeTask(t.taskId),
      onCancelTask: (t) => actions.cancelTask(t.taskId),
    );
    final children = <Widget>[
      for (final entry in panel.entries)
        switch (entry) {
          YouEntry() => _You(
              key: ObjectKey(entry),
              entry: entry,
              // The tag above already says which work.
              showAbout: entry.about != panel.about?.title),
          NipaEntry() => StreamingReply(
              key: ObjectKey(entry),
              text: entry.text,
              thinking: false,
              style: NextText.sans(14.5, height: 1.7),
            ),
          ActivityEntry() => ActivityLine(
              key: ObjectKey(entry),
              activity: entry.activity,
              asking: panel.question != null),
          CardsEntry() => CardStack(
              key: ObjectKey(entry),
              cards: entry.cards,
              callbacks: callbacks,
              width: width,
              posterWidth: 136,
            ),
        },
      if (panel.questionItems.isNotEmpty) _Question(panel: panel),
      for (final request in logins.pending)
        LoginCard(
            key: ObjectKey(request),
            request: request,
            onOpen: () => logins.open(request)),
      if (panel.quiet) _Quiet(panel: panel),
      if (panel.trouble != null)
        Text(panel.trouble!, style: NextText.sans(14, color: NextColors.p2)),
      if (panel.nextSayings case final sayings when sayings.isNotEmpty)
        _NextSayings(
            key: ValueKey(sayings.join('|')),
            sayings: sayings,
            onSay: panel.say),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Each session opens at its latest message.
        key: ValueKey(panel.thread ?? 'new'),
        reverse: true,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 36)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) const SizedBox(height: 14),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.u`: what you said, a light bubble on the right; above it the work it
/// was about and the files that went with it.
class _You extends StatelessWidget {
  const _You({super.key, required this.entry, this.showAbout = true});
  final YouEntry entry;
  final bool showAbout;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.about case final title? when showAbout)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 4),
              child: Text('关于《$title》',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(11.5, color: NextColors.p3)),
            ),
          if (entry.files.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: entry.text.isEmpty ? 0 : 6),
              child: SentFiles(paths: entry.files),
            ),
          if (entry.text.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _Thread.width * 0.78),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0x17FFFFFF),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(6),
                  ),
                  border: Border.all(color: NextColors.line),
                ),
                child: Text(entry.text, style: NextText.sans(14.5, height: 1.6)),
              ),
            ),
        ],
      );
}

/// What you might say next, under Nipa's reply; tapping one says it.
class _NextSayings extends StatelessWidget {
  const _NextSayings({super.key, required this.sayings, required this.onSay});
  final List<String> sayings;
  final ValueChanged<String> onSay;

  @override
  Widget build(BuildContext context) => StaggerIn(
        index: 2,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in sayings)
            _Choice(label: s, chosen: false, onTap: () => onSay(s)),
        ]),
      );
}

/// What this conversation set going that is still under way, in one thin
/// line over the input (“《迷宫饭》下载 47% · 然后补上弹幕”); tapped, every
/// one of them with its progress.
class _UnderwayBar extends StatefulWidget {
  const _UnderwayBar({required this.items});
  final List<Underway> items;

  @override
  State<_UnderwayBar> createState() => _UnderwayBarState();
}

class _UnderwayBarState extends State<_UnderwayBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final first = items.first;
    final more = items.length - 1;
    final head = Pressable(
      onTap: () => setState(() => _open = !_open),
      semanticLabel: '后台的事',
      pressScale: 0.99,
      builder: (context, hovered) => SizedBox(
        height: 34,
        child: Row(children: [
          const SizedBox(width: 2),
          const PulseDot(size: 6),
          const SizedBox(width: 10),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                if (!_open)
                  TextSpan(
                      text: '《${first.title}》 ',
                      style: NextText.sans(12.5,
                          weight: FontWeight.w600, color: NextColors.paper)),
                TextSpan(
                    text: _open ? '这次对话在后台做的事' : first.line,
                    style: NextText.sans(12.5, color: NextColors.p2)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (more > 0 && !_open) ...[
            const SizedBox(width: 8),
            NumText('还有 $more 件',
                style: NextText.sans(12, color: NextColors.p3)),
          ],
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: _open ? 0.25 : -0.25,
            duration: const Duration(milliseconds: 160),
            child: NextIcon(NextGlyph.chevronRight,
                size: 10, color: hovered ? NextColors.p2 : NextColors.p4),
          ),
        ]),
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NextColors.line),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: NextMotion.ease,
        alignment: Alignment.bottomCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          head,
          if (_open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12, top: 2),
                child: Column(children: [
                  for (final (i, item) in items.indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _UnderwayRow(item: item),
                  ],
                ]),
              ),
            )
          else if (first.progress case final progress?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ThinBar(
                  progress: progress,
                  height: 2,
                  live: true,
                  track: const Color(0x14FFFFFF)),
            ),
        ]),
      ),
    );
  }
}

class _UnderwayRow extends StatelessWidget {
  const _UnderwayRow({required this.item});
  final Underway item;

  @override
  Widget build(BuildContext context) => Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 30,
            height: 44,
            child: NextImage(item.artwork?.poster,
                shape: ArtShape.poster, tint: item.artwork?.tint),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13, weight: FontWeight.w600)),
              const SizedBox(height: 3),
              NumText(item.line,
                  style: NextText.sans(12, color: NextColors.p3)),
              if (item.progress case final progress?) ...[
                const SizedBox(height: 7),
                ThinBar(
                    progress: progress,
                    height: 3,
                    live: true,
                    track: const Color(0x1AFFFFFF)),
              ],
            ],
          ),
        ),
      ]);
}

/// Three minutes without any event: say so, and let you choose.
class _Quiet extends StatelessWidget {
  const _Quiet({required this.panel});
  final PanelChat panel;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('好像没有回应', style: NextText.sans(14, color: NextColors.p2)),
          const SizedBox(height: 10),
          Row(children: [
            NextButton.ghost(
                label: '再等等', height: 34, onTap: panel.keepWaiting),
            const SizedBox(width: 10),
            NextButton.ghost(label: '重新发', height: 34, onTap: panel.resend),
          ]),
        ],
      );
}

/// What Nipa asks (`requestUserInput`): the options are buttons; typing
/// answers too.
class _Question extends StatelessWidget {
  const _Question({required this.panel});
  final PanelChat panel;

  @override
  Widget build(BuildContext context) {
    final items = panel.questionItems;
    return CardSurface(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, q) in items.indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            if (q['question'] case final String text when text.isNotEmpty)
              Text(text,
                  style: NextText.sans(14.5,
                      weight: FontWeight.w600, height: 1.6)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final option in (q['options'] as List? ?? const [])
                  .whereType<Map>()
                  .map((o) => o['label'] as String? ?? '')
                  .where((label) => label.isNotEmpty))
                _Choice(
                  label: option,
                  chosen: panel.chosen[q['id']] == option,
                  onTap: () => panel.choose(q['id'] as String, option),
                ),
              if (q['isSecret'] == true)
                _Choice(label: '跳过', chosen: false, onTap: panel.skip),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice(
      {required this.label, required this.chosen, required this.onTap});
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: chosen
                ? NextColors.paper
                : (hovered ? const Color(0x24FFFFFF) : const Color(0x12FFFFFF)),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
                color: chosen ? NextColors.paper : NextColors.line2),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(label,
                maxLines: 1,
                style: NextText.sans(13,
                    weight: chosen ? FontWeight.w600 : FontWeight.w400,
                    color: chosen
                        ? const Color(0xFF111111)
                        : (hovered ? NextColors.paper : NextColors.p2))),
          ),
        ),
      );
}

/// “需要登录 某平台”: the button opens NipaPlay's own login window; the
/// secret is typed there, never in the conversation.
class LoginCard extends StatelessWidget {
  const LoginCard({super.key, required this.request, required this.onOpen});
  final LoginRequest request;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => CardSurface(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(children: [
          Expanded(
            child: Text('需要登录 ${request.platform}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(14.5, weight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          NextButton(
            label: request.opening ? '已打开' : '打开登录窗口',
            height: 36,
            onTap: request.opening ? null : onOpen,
          ),
        ]),
      );
}

/// `.compose`: one line; Enter sends (an answer, a steer, or a new turn).
/// Files dropped on the panel wait above it until then.
class _Compose extends StatelessWidget {
  const _Compose({required this.panel});
  final PanelChat panel;

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    void send([String? value]) {
      final text = (value ?? shell.panelText.text).trim();
      if ((text.isEmpty && panel.attachments.isEmpty) ||
          !panel.acceptsTyping) {
        return;
      }
      shell.panelText.clear();
      panel.say(text);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (panel.attachments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AttachmentStrip(
                paths: panel.attachments, onRemove: panel.detach),
          ),
        ),
      Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        height: 54,
        padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: NextColors.line2),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: shell.panelText,
              focusNode: shell.panelFocus,
              onSubmitted: send,
              // Keep the focus after sending: the conversation goes on.
              onEditingComplete: () {},
              textInputAction: TextInputAction.send,
              maxLines: 1,
              cursorColor: NextColors.accent,
              cursorWidth: 1.5,
              cursorHeight: 17,
              style: NextText.sans(14),
              decoration: InputDecoration.collapsed(
                hintText: panel.attachments.isNotEmpty && panel.question == null
                    ? '想让 Nipa 做什么？'
                    : panel.hint,
                hintStyle: NextText.sans(14, color: NextColors.p3),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SendButton(onTap: send),
        ]),
      ),
    ]);
  }
}
