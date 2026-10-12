import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../chat/transcript.dart' show Shimmer;
import '../conversation/chat_turn.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/progress.dart';
import 'shell_controller.dart';

/// The top bar's way into what goes on in the background: NipaPlay's tasks
/// and the helpers Nipa sent off. A ring with the overall progress of what
/// has progress; when nothing running has any, the ring turns and counts.
class BackgroundEntry extends StatelessWidget {
  const BackgroundEntry({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final active = shell.activeTasks;
    final measured = [
      for (final t in active)
        if (t.progress != null) t
    ];
    final progress = measured.isEmpty
        ? null
        : measured.fold<double>(0, (a, t) => a + t.progress!) /
            measured.length;
    return Pressable(
      onTap: onTap,
      semanticLabel: '后台',
      builder: (context, hovered) => Glass(
        blur: 18,
        saturate: 1.5,
        color: hovered ? const Color(0x8C1A1A22) : const Color(0x6B0A0A0E),
        borderColor: NextColors.line2,
        radius: BorderRadius.circular(16),
        highlight: false,
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (progress != null)
                ProgressRing(progress: progress)
              else
                const _TurningRing(),
              const SizedBox(width: 10),
              Text(
                  progress != null
                      ? '${(progress * 100).round()}%'
                      : '${active.length}',
                  style: NextText.num(12, color: NextColors.p2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A ring for work without progress: a short arc going round.
class _TurningRing extends StatefulWidget {
  const _TurningRing();

  @override
  State<_TurningRing> createState() => _TurningRingState();
}

class _TurningRingState extends State<_TurningRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: const Size.square(16),
          painter: _ArcPainter(
              NextMotion.reduced(context) ? 0 : _c.value * 2 * math.pi),
        ),
      );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.angle);
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero), radius: size.width / 2 - 1.5);
    canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0x24FFFFFF));
    canvas.drawArc(
        rect,
        angle,
        math.pi * 0.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = NextColors.accent);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.angle != angle;
}

/// What goes on in the background, latest first: helpers say what they
/// are doing and for how long, and open to their own conversation; tasks
/// show their progress. Each can be stopped. Helpers that finished
/// recently stay a while with what they came back with.
class BackgroundPanel extends StatelessWidget {
  const BackgroundPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final actions = shell.services.actions;
    final callbacks = CardCallbacks(
      onPauseTask: (t) => actions.pauseTask(t.taskId),
      onResumeTask: (t) => actions.resumeTask(t.taskId),
      onCancelTask: (t) => actions.cancelTask(t.taskId),
    );
    return Glass(
      blur: 30,
      color: const Color(0xC2121218),
      borderColor: const Color(0x1AFFFFFF),
      radius: BorderRadius.circular(18),
      shadows: const [
        BoxShadow(
            color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 20))
      ],
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: SizedBox(
        width: 360,
        child: ValueListenableBuilder(
          valueListenable: shell.tasks,
          builder: (context, _, __) {
            final items = shell.backgroundItems;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, task) in items.indexed) ...[
                      if (i > 0)
                        Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            color: NextColors.line),
                      if (task.kind == UiTaskKind.helper)
                        _HelperRow(
                          task: task,
                          onOpen: task.threadId == null
                              ? null
                              : () => shell.openConversation(task.threadId!),
                          onStop: () => actions.cancelTask(task.taskId),
                        )
                      else
                        TaskRow(task: task, callbacks: callbacks),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A helper: what it was sent to do, what it is doing now and for how
/// long; afterwards what it came back with. Tapped, its conversation.
class _HelperRow extends StatelessWidget {
  const _HelperRow({required this.task, this.onOpen, this.onStop});
  final UiTask task;
  final VoidCallback? onOpen;
  final VoidCallback? onStop;

  bool get _running =>
      task.state == UiTaskState.running || task.state == UiTaskState.queued;

  @override
  Widget build(BuildContext context) {
    final running = _running;
    final line = running
        ? (task.state == UiTaskState.queued
            ? 'Queued'
            : (task.currentActivity ?? 'Working'))
        : (task.summary ??
            (task.state == UiTaskState.failed
                ? 'Failed'
                : task.cancelled
                    ? 'Stopped'
                    : 'Done'));
    return Pressable(
      onTap: onOpen,
      semanticLabel: task.title,
      pressScale: 0.99,
      builder: (context, hovered) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: NipaAvatar(
                size: 26,
                mood: running ? NipaMood.acting : NipaMood.idle),
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
                    style: NextText.sans(13.5,
                        weight: FontWeight.w600,
                        color: hovered ? NextColors.paper : NextColors.p2)),
                const SizedBox(height: 5),
                Row(children: [
                  Flexible(
                    child: running
                        ? Shimmer(
                            text: line,
                            style: NextText.sans(12),
                            still: task.state == UiTaskState.queued)
                        : Text(line,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: NextText.sans(12,
                                color: NextColors.p3, height: 1.5)),
                  ),
                  if (running && task.startedAt != null) ...[
                    Text('  ·  ',
                        style: NextText.sans(12, color: NextColors.p4)),
                    _Since(task.startedAt!),
                  ],
                ]),
              ],
            ),
          ),
          if (running && onStop != null) ...[
            const SizedBox(width: 10),
            NextIconButton(
                glyph: NextGlyph.close, label: '停止', size: 26, onTap: onStop),
          ],
        ],
      ),
    );
  }
}

/// How long since [from], m:ss, ticking.
class _Since extends StatefulWidget {
  const _Since(this.from);
  final DateTime from;

  @override
  State<_Since> createState() => _SinceState();
}

class _SinceState extends State<_Since> {
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
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.from);
    return Text(ChatTurn.clock(d.isNegative ? Duration.zero : d),
        style: NextText.num(12, color: NextColors.p3));
  }
}
