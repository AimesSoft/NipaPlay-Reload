import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../cards/card_views.dart';
import '../conversation/nipa_chat.dart';
import '../data/login_requests.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/attachments.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';

/// The conversation itself: every turn in order, then whatever waits for
/// you. It stays where you are reading: it follows new words only while
/// you are at the bottom; scrolled up, it holds still and offers the way
/// back down. Unfolding something never moves what you are looking at.
class ChatTranscript extends StatefulWidget {
  const ChatTranscript({
    super.key,
    required this.chat,
    required this.callbacks,
    required this.logins,
    this.columnWidth = 720,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 24),
    this.textSize = 15,
    this.posterWidth = 150,
  });

  final NipaChat chat;
  final CardCallbacks callbacks;
  final LoginRequests logins;
  final double columnWidth;
  final EdgeInsets padding;
  final double textSize;
  final double posterWidth;

  /// The latest transcript's scroller, for the debug driver.
  static ScrollController? debugController;

  @override
  State<ChatTranscript> createState() => _ChatTranscriptState();
}

class _ChatTranscriptState extends State<ChatTranscript> {
  final _scroll = ScrollController();

  /// At the bottom, following what arrives.
  bool _pinned = true;
  bool _away = false;
  String? _thread;
  int _turns = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    ChatTranscript.debugController = _scroll;
    _thread = widget.chat.thread;
    _turns = widget.chat.turns.length;
    _jumpSoon();
  }

  @override
  void dispose() {
    if (identical(ChatTranscript.debugController, _scroll)) {
      ChatTranscript.debugController = null;
    }
    _scroll.dispose();
    super.dispose();
  }

  bool get _atBottom {
    if (!_scroll.hasClients) return true;
    final p = _scroll.position;
    return p.pixels >= p.maxScrollExtent - 24;
  }

  void _onScroll() {
    final bottom = _atBottom;
    final away = !bottom &&
        _scroll.position.maxScrollExtent - _scroll.position.pixels > 160;
    if (away != _away) setState(() => _away = away);
  }

  bool _jumping = false;

  void _jumpSoon() {
    if (_jumping) return;
    _jumping = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _jumping = false;
      if (!mounted || !_scroll.hasClients || !_pinned) return;
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.position.pixels != max) _scroll.jumpTo(max);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification && n.dragDetails != null ||
        n is UserScrollNotification && n.direction != ScrollDirection.idle) {
      _pinned = false;
    } else if (n is ScrollEndNotification) {
      _pinned = _atBottom;
    }
    return false;
  }

  /// You unfolded something: what you are looking at stays put.
  void _hold() => _pinned = false;

  void _toLatest() {
    _pinned = true;
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 360), curve: NextMotion.ease);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    // Another session, or something new said: to the bottom.
    if (chat.thread != _thread || chat.turns.length > _turns) {
      _thread = chat.thread;
      _pinned = true;
      _away = false;
      _jumpSoon();
    }
    _turns = chat.turns.length;
    final text = NextText.sans(widget.textSize, height: 1.7);
    final shown = chat.visibleTurns;
    final children = <Widget>[
      for (final (i, turn) in shown.indexed)
        _TurnView(
          key: ObjectKey(turn),
          turn: turn,
          last: i == shown.length - 1,
          chat: chat,
          callbacks: widget.callbacks,
          text: text,
          width: widget.columnWidth,
          posterWidth: widget.posterWidth,
        ),
      if (chat.questionItems.isNotEmpty) _Question(chat: chat),
      for (final request in widget.logins.pending)
        LoginCard(
            key: ObjectKey(request),
            request: request,
            onOpen: () => widget.logins.open(request)),
      if (chat.quiet) _Quiet(chat: chat),
      if (chat.trouble != null)
        Text(chat.trouble!, style: NextText.sans(14, color: NextColors.p2)),
    ];
    return _Hold(
      hold: _hold,
      child: Stack(children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            // Words fade out under the title rather than being cut.
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [Color(0x00000000), Color(0xFF000000)],
                stops: [0, (18 / rect.height).clamp(0.0, 1.0)],
              ).createShader(rect),
              child: ListView.builder(
                controller: _scroll,
                physics: _TranscriptPhysics(
                  follow: () => _pinned,
                  parent:
                      ScrollConfiguration.of(context).getScrollPhysics(context),
                ),
                padding: widget.padding,
                itemCount: children.length,
                findChildIndexCallback: (key) {
                  final index = children.indexWhere((child) =>
                      child.key == (key is ValueKey<Key> ? key.value : key));
                  return index < 0 ? null : index;
                },
                itemBuilder: (context, index) => Padding(
                  key: children[index].key == null
                      ? null
                      : ValueKey<Key>(children[index].key!),
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 26),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: widget.columnWidth),
                      child: SizedBox(
                          width: double.infinity, child: children[index]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child: Center(
            child: IgnorePointer(
              ignoring: !_away,
              child: AnimatedOpacity(
                opacity: _away ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: _ToLatest(onTap: _toLatest),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Follow a growing reply during layout, without cancelling a drag, inertia,
/// or the platform's overscroll spring with a post-frame jumpTo.
class _TranscriptPhysics extends ScrollPhysics {
  const _TranscriptPhysics({required this.follow, super.parent});
  final bool Function() follow;

  @override
  _TranscriptPhysics applyTo(ScrollPhysics? ancestor) =>
      _TranscriptPhysics(follow: follow, parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (follow() &&
        !isScrolling &&
        !oldPosition.outOfRange &&
        newPosition.maxScrollExtent != oldPosition.maxScrollExtent) {
      return newPosition.maxScrollExtent;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

/// Lets an unfolding keep the transcript where it is.
class _Hold extends InheritedWidget {
  const _Hold({required this.hold, required super.child});
  final VoidCallback hold;

  static void of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Hold>()?.hold();

  @override
  bool updateShouldNotify(_Hold old) => false;
}

class _ToLatest extends StatelessWidget {
  const _ToLatest({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: '回到最新',
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0xFF2A2A33) : const Color(0xFF1E1E26),
            border: Border.all(color: NextColors.line2),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 16,
                  offset: Offset(0, 6)),
            ],
          ),
          child: const RotatedBox(
            quarterTurns: 1,
            child: NextIcon(NextGlyph.chevronRight,
                size: 14, color: NextColors.paper),
          ),
        ),
      );
}

/// One turn: what you said, then Nipa's words and steps as they came,
/// and how long it has been at it; once it answered, the work before the
/// answer folds into one line that opens again.
class _TurnView extends StatefulWidget {
  const _TurnView({
    super.key,
    required this.turn,
    required this.last,
    required this.chat,
    required this.callbacks,
    required this.text,
    required this.width,
    required this.posterWidth,
  });
  final ChatTurn turn;
  final bool last;
  final NipaChat chat;
  final CardCallbacks callbacks;
  final TextStyle text;
  final double width;
  final double posterWidth;

  @override
  State<_TurnView> createState() => _TurnViewState();
}

class _TurnViewState extends State<_TurnView> {
  void _toggle(VoidCallback change) {
    _Hold.of(context);
    setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final children = <Widget>[];
    var foldPlaced = false;
    final answer = turn.answer;
    final lastPart = turn.parts.lastOrNull;
    for (final part in turn.parts) {
      if (turn.foldable &&
          !foldPlaced &&
          part is! SaidPart &&
          part is! NoticePart &&
          !identical(part, answer)) {
        foldPlaced = true;
        children.add(_Fold(
          label: 'Worked for ${ChatTurn.span(turn.elapsed())}',
          open: turn.unfolded,
          onTap: () => _toggle(() => turn.unfolded = !turn.unfolded),
        ));
      }
      if (turn.folded(part)) continue;
      children.add(switch (part) {
        SaidPart() => _You(
            key: ObjectKey(part),
            part: part,
            width: widget.width,
            showAbout: part.about != widget.chat.about?.title,
            showWatched: part.watched != widget.chat.watched),
        ReplyPart() => ReplyText(
            key: ObjectKey(part),
            text: part.text,
            style: widget.text,
          ),
        NoticePart() => Text(
            key: ObjectKey(part),
            part.text,
            style: NextText.sans(13.5, color: NextColors.p2, height: 1.5),
          ),
        StepsPart() => _Steps(
            key: ObjectKey(part),
            group: part,
            live: turn.running && identical(part, lastPart),
            onToggle: () => _toggle(() => part.open = !part.open),
          ),
      });
    }
    if (turn.running) {
      children.add(_Status(
          turn: turn, asking: widget.last && widget.chat.question != null));
    } else if (turn.status == 'interrupted' && answer == null) {
      children.add(
          Text('Stopped', style: NextText.sans(12.5, color: NextColors.p3)));
    }
    if (turn.cards.isNotEmpty) {
      children.add(CardStack(
        cards: turn.cards,
        callbacks: widget.callbacks,
        width: widget.width,
        posterWidth: widget.posterWidth,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          child,
        ],
      ],
    );
  }
}

/// “Worked for 1m 23s ›”: the work before the answer, folded.
class _Fold extends StatelessWidget {
  const _Fold({required this.label, required this.open, required this.onTap});
  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Pressable(
          onTap: onTap,
          semanticLabel: open ? '收起' : '展开',
          pressScale: 0.99,
          builder: (context, hovered) =>
              Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: NextText.sans(13,
                    color: hovered ? NextColors.p2 : NextColors.p3)),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 160),
              child: NextIcon(NextGlyph.chevronRight,
                  size: 10, color: hovered ? NextColors.p2 : NextColors.p4),
            ),
          ]),
        ),
      );
}

/// The running turn's state and clock: “Thinking · 0:42”.
class _Status extends StatelessWidget {
  const _Status({required this.turn, required this.asking});
  final ChatTurn turn;
  final bool asking;

  @override
  Widget build(BuildContext context) {
    final waiting = asking || turn.waiting;
    final label = turn.queued
        ? 'Queued'
        : waiting
            ? 'Waiting for you'
            : (turn.doing != null ? 'Working' : 'Thinking');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Shimmer(
          text: label,
          style: NextText.sans(13, weight: FontWeight.w500),
          still: waiting || turn.queued),
      if (!waiting && !turn.queued) ...[
        Text('  ·  ', style: NextText.sans(13, color: NextColors.p4)),
        _Clock(turn: turn),
      ],
    ]);
  }
}

/// Text with light passing over it, while something is under way.
class Shimmer extends StatefulWidget {
  const Shimmer(
      {super.key, required this.text, required this.style, this.still = false});
  final String text;
  final TextStyle style;
  final bool still;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style.copyWith(color: NextColors.p3));
    if (widget.still || NextMotion.reduced(context)) return text;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final x = -1.0 + 3.0 * _c.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            colors: const [NextColors.p3, NextColors.paper, NextColors.p3],
            stops: const [0.3, 0.5, 0.7],
          ).createShader(rect),
          child: child,
        );
      },
      child: text,
    );
  }
}

/// m:ss of the turn's work; only this text rebuilds each second.
class _Clock extends StatefulWidget {
  const _Clock({required this.turn});
  final ChatTurn turn;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        ChatTurn.clock(widget.turn.elapsed()),
        style: NextText.num(12.5, color: NextColors.p3),
      );
}

/// Steps in a row, folded to one line (“查资料、看片库 · 5 步”); a dot
/// while one of them runs. Unfolded: thoughts as text, commands with how
/// they ended and their output (folded too).
class _Steps extends StatelessWidget {
  const _Steps(
      {super.key,
      required this.group,
      required this.live,
      required this.onToggle});
  final StepsPart group;
  final bool live;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final running = live && group.steps.any((s) => s.running);
    final head = Pressable(
      onTap: onToggle,
      semanticLabel: group.open ? '收起' : '展开',
      pressScale: 0.99,
      builder: (context, hovered) => Row(children: [
        SizedBox(
          width: 14,
          child: running
              ? const Center(child: PulseDot(size: 5))
              : Center(
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: NextColors.p4),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(ChatTurn.summary(group),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(13,
                  color: hovered ? NextColors.paper : NextColors.p2)),
        ),
        const SizedBox(width: 6),
        AnimatedRotation(
          turns: group.open ? 0.25 : 0,
          duration: const Duration(milliseconds: 160),
          child: NextIcon(NextGlyph.chevronRight,
              size: 10, color: hovered ? NextColors.p2 : NextColors.p4),
        ),
      ]),
    );
    Widget stepAt(int i) {
      final step = group.steps[i];
      return switch (step) {
        ThoughtStep() => _Thought(step: step),
        CommandStep() => _Command(key: ObjectKey(step), step: step),
        ToolStep() =>
          Text(step.label, style: NextText.sans(12.5, color: NextColors.p2)),
        HelperStep() => _Helper(step: step),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(alignment: Alignment.centerLeft, child: head),
        if (group.open)
          Container(
            margin: const EdgeInsets.only(top: 10, left: 6),
            padding: const EdgeInsets.only(left: 14),
            decoration: const BoxDecoration(
                border: Border(
                    left: BorderSide(color: NextColors.line2, width: 1.5))),
            child: group.steps.length > 10
                ? SizedBox(
                    height: (MediaQuery.sizeOf(context).height * 0.6)
                        .clamp(160.0, 480.0),
                    child: ListView.separated(
                      primary: false,
                      itemCount: group.steps.length,
                      itemBuilder: (context, index) => stepAt(index),
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < group.steps.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        stepAt(i),
                      ],
                    ],
                  ),
          ),
      ],
    );
  }
}

class _Thought extends StatelessWidget {
  const _Thought({required this.step});
  final ThoughtStep step;

  @override
  Widget build(BuildContext context) {
    final text = step.text.toString().trim();
    if (text.isEmpty) {
      return Text('…', style: NextText.sans(12.5, color: NextColors.p3));
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        child: Text(text,
            style: NextText.sans(12.5, color: NextColors.p3, height: 1.6)),
      ),
    );
  }
}

/// Work handed to a helper: what it was asked, and its conversation.
class _Helper extends StatelessWidget {
  const _Helper({required this.step});
  final HelperStep step;

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final title =
        step.prompt.isEmpty ? null : ChatTurn.helperTitle(step.prompt);
    return Row(children: [
      Flexible(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: ChatTurn.phrase(step),
                style: NextText.sans(12.5, color: NextColors.p2)),
            if (title != null)
              TextSpan(
                  text: '  $title',
                  style: NextText.sans(12.5, color: NextColors.p3)),
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (final thread in step.threads.take(1)) ...[
        const SizedBox(width: 10),
        Pressable(
          onTap: () => shell.openConversation(thread),
          semanticLabel: '打开帮手的对话',
          builder: (context, hovered) => Text('打开',
              style: NextText.sans(12.5,
                  color: hovered ? NextColors.paper : NextColors.accent2)),
        ),
      ],
    ]);
  }
}

/// A command, how it ended, and its output (folded).
class _Command extends StatefulWidget {
  const _Command({super.key, required this.step});
  final CommandStep step;

  @override
  State<_Command> createState() => _CommandState();
}

class _CommandState extends State<_Command> {
  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final shown = step.outputShown;
    final output = step.output.toString().trimRight();
    final ok = step.exitCode == null || step.exitCode == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NextColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(ChatTurn.bare(step.command),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.mono(11.5)),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: step.running
                  ? const PulseDot(size: 6)
                  : ok
                      ? const NextIcon(NextGlyph.check,
                          size: 12, color: NextColors.mint)
                      : Text('退出 ${step.exitCode}',
                          style:
                              NextText.sans(11.5, color: NextColors.accent2)),
            ),
          ]),
          if (output.isNotEmpty) ...[
            const SizedBox(height: 6),
            Pressable(
              onTap: () {
                _Hold.of(context);
                setState(() => step.outputShown = !shown);
              },
              semanticLabel: shown ? '收起输出' : '输出',
              pressScale: 0.99,
              builder: (context, hovered) => Text(shown ? '收起输出' : '输出',
                  style: NextText.sans(11.5,
                      color: hovered ? NextColors.p2 : NextColors.p3)),
            ),
            if (shown)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Text(
                      output.length > 6000
                          ? '…${output.substring(output.length - 6000)}'
                          : output,
                      style: NextText.mono(11, color: NextColors.p3)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// What you said, a light bubble on the right; above it the work it was
/// about, what played under the conversation, the files that went with it.
/// Faint until Nipa has it.
class _You extends StatelessWidget {
  const _You(
      {super.key,
      required this.part,
      required this.width,
      this.showAbout = true,
      this.showWatched = true});
  final SaidPart part;
  final double width;
  final bool showAbout;

  /// Not while the same still plays under the conversation.
  final bool showWatched;

  static Widget _context(String words) => Padding(
        padding: const EdgeInsets.only(bottom: 6, right: 4),
        child: Text(words,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NextText.sans(11.5, color: NextColors.p3)),
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (part.about case final title? when showAbout)
            _context('关于《$title》'),
          if (part.watched case final named? when showWatched)
            _context('看$named时'),
          if (part.files.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: part.text.isEmpty ? 0 : 6),
              child: SentFiles(paths: part.files),
            ),
          if (part.text.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.78),
              child: AnimatedOpacity(
                opacity: part.echoed ? 1 : 0.7,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x17FFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: NextColors.line),
                  ),
                  child:
                      Text(part.text, style: NextText.sans(14.5, height: 1.6)),
                ),
              ),
            ),
        ],
      );
}

/// Nipa's words, revealed as they stream, as light markdown.
class ReplyText extends StatefulWidget {
  const ReplyText({super.key, required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<ReplyText> createState() => _ReplyTextState();
}

class _ReplyTextState extends State<ReplyText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _shown = 0;
  Duration _last = Duration.zero;
  String? _renderedText;
  TextStyle? _renderedStyle;
  Widget? _markdown;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    // Already said: shown whole.
    _shown = widget.text.length.toDouble();
  }

  @override
  void didUpdateWidget(ReplyText old) {
    super.didUpdateWidget(old);
    final kept = _shown.floor().clamp(0, old.text.length);
    if (!widget.text.startsWith(old.text.substring(0, kept))) _shown = 0;
    if (_shown < widget.text.length && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    // Markdown parsing/layout is expensive for long replies. Coalesce reveal
    // updates instead of parsing the entire reply on every display frame.
    if (elapsed - _last < const Duration(milliseconds: 80)) return;
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final target = widget.text.length;
    final behind = target - _shown;
    if (behind <= 0) {
      _ticker.stop();
      return;
    }
    // At least 40 characters a second; faster when far behind.
    final rate = behind * 5 > 40 ? behind * 5 : 40.0;
    setState(() => _shown = (_shown + rate * dt).clamp(0, target.toDouble()));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        widget.text.substring(0, _shown.floor().clamp(0, widget.text.length));
    final base = widget.style;
    if (_renderedText == visible && _renderedStyle == base) return _markdown!;
    _renderedText = visible;
    _renderedStyle = base;
    final size = base.fontSize ?? 15;
    return _markdown = MarkdownBody(
      data: visible,
      softLineBreak: true,
      fitContent: false,
      styleSheet: MarkdownStyleSheet(
        p: base,
        strong: const TextStyle(fontWeight: FontWeight.w600),
        em: const TextStyle(fontStyle: FontStyle.italic),
        a: const TextStyle(color: NextColors.accent2),
        code: NextText.mono(size * 0.86, color: NextColors.paper)
            .copyWith(backgroundColor: const Color(0x14FFFFFF)),
        h1: base.copyWith(fontSize: size * 1.3, fontWeight: FontWeight.w600),
        h2: base.copyWith(fontSize: size * 1.18, fontWeight: FontWeight.w600),
        h3: base.copyWith(fontSize: size * 1.06, fontWeight: FontWeight.w600),
        listBullet: base,
        blockquote: base.copyWith(color: NextColors.p2),
        blockquoteDecoration: const BoxDecoration(
            border:
                Border(left: BorderSide(color: NextColors.line2, width: 2))),
        blockquotePadding: const EdgeInsets.only(left: 12),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NextColors.line),
        ),
        horizontalRuleDecoration: const BoxDecoration(
            border: Border(top: BorderSide(color: NextColors.line2))),
        tableBody: base.copyWith(fontSize: size * 0.92),
        tableHead:
            base.copyWith(fontSize: size * 0.92, fontWeight: FontWeight.w600),
        tableBorder: const TableBorder(
          horizontalInside: BorderSide(color: NextColors.line),
          top: BorderSide(color: NextColors.line),
          bottom: BorderSide(color: NextColors.line),
        ),
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        pPadding: EdgeInsets.zero,
        blockSpacing: size * 0.7,
        listIndent: size * 1.4,
      ),
    );
  }
}

/// Three minutes without any event: say so, and let you choose.
class _Quiet extends StatelessWidget {
  const _Quiet({required this.chat});
  final NipaChat chat;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('好像没有回应', style: NextText.sans(14, color: NextColors.p2)),
          const SizedBox(height: 10),
          Row(children: [
            NextButton.ghost(label: '再等等', height: 34, onTap: chat.keepWaiting),
            const SizedBox(width: 10),
            NextButton.ghost(label: '重新发', height: 34, onTap: chat.resend),
          ]),
        ],
      );
}

/// What Nipa asks (`requestUserInput`): the options are buttons; typing
/// answers too.
class _Question extends StatelessWidget {
  const _Question({required this.chat});
  final NipaChat chat;

  @override
  Widget build(BuildContext context) {
    final items = chat.questionItems;
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
                  chosen: chat.chosen[q['id']] == option,
                  onTap: () => chat.choose(q['id'] as String, option),
                ),
              if (q['isSecret'] == true)
                _Choice(label: '跳过', chosen: false, onTap: chat.skip),
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
            border:
                Border.all(color: chosen ? NextColors.paper : NextColors.line2),
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
