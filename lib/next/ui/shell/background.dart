import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../chat/transcript.dart' show Shimmer;
import '../conversation/chat_turn.dart';
import '../downloads/task_open.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import 'shell_controller.dart';

/// The top bar's way into what goes on in the background: NipaPlay's tasks
/// and the helpers Nipa sent off. Background work is of many kinds and most
/// has no single progress worth summing, so it shows that things are going
/// on and how many.
class BackgroundEntry extends StatelessWidget {
  const BackgroundEntry({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final active = shell.activeTasks;
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
              const _WorkGlyph(),
              const SizedBox(width: 8),
              Text('${active.length}',
                  style: NextText.num(12, color: NextColors.p2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A short list whose points light up one after another: work going on.
class _WorkGlyph extends StatefulWidget {
  const _WorkGlyph();

  @override
  State<_WorkGlyph> createState() => _WorkGlyphState();
}

class _WorkGlyphState extends State<_WorkGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
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
          painter: _WorkPainter(NextMotion.reduced(context) ? null : _c.value),
        ),
      );
}

class _WorkPainter extends CustomPainter {
  _WorkPainter(this.phase);

  /// Where the light is, 0..1 over the three rows; null keeps all lit.
  final double? phase;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 16;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * unit
      ..strokeCap = StrokeCap.round
      ..color = NextColors.p3;
    for (var row = 0; row < 3; row++) {
      final y = (3.5 + row * 4.5) * unit;
      final lit = phase == null
          ? 1.0
          : math.max(0.0, 1 - (phase! * 3 - row) % 3 * 1.2);
      canvas.drawCircle(
          Offset(3 * unit, y),
          1.7 * unit,
          Paint()
            ..color = Color.lerp(NextColors.p3, NextColors.accent, lit)!);
      canvas.drawLine(
          Offset(7 * unit, y), Offset((row == 1 ? 11.5 : 14) * unit, y), line);
    }
  }

  @override
  bool shouldRepaint(_WorkPainter old) => old.phase != phase;
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
    final services = shell.services;
    void control(UiTask t, String command) =>
        unawaited(controlTasks(services, [t], command));
    final callbacks = CardCallbacks(
      onPauseTask: (t) => control(t, 'pause'),
      onResumeTask: (t) => control(t, 'resume'),
      // A download's × takes the task away and keeps its files, as the
      // detail page's 移除任务 does; deleting files is asked there.
      onCancelTask: (t) => isDownload(t)
          ? unawaited(services.downloads.remove(t.taskId, files: false))
          : control(t, 'cancel'),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: SizedBox(
        width: 360,
        child: ValueListenableBuilder(
          valueListenable: shell.tasks,
          builder: (context, _, __) {
            final items = shell.backgroundItems;
            // Another device's tasks are shown, not controlled, here.
            final tasks = [
              for (final t in shell.activeTasks)
                if (t.kind == UiTaskKind.background && t.device == null) t
            ];
            final running =
                tasks.where((t) => t.state == UiTaskState.running).toList();
            final paused =
                tasks.where((t) => t.state == UiTaskState.paused).toList();
            return Column(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
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
                            onStop: () => control(task, 'cancel'),
                          )
                        else
                          Pressable(
                            onTap: task.device != null
                                ? null
                                : () {
                                    shell.closePopover();
                                    unawaited(openTask(services, task));
                                  },
                            semanticLabel: task.title,
                            pressScale: 0.99,
                            builder: (context, hovered) =>
                                TaskRow(task: task, callbacks: callbacks),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                  height: 1,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  color: NextColors.line),
              Row(children: [
                if (running.isNotEmpty)
                  _FootButton(
                      label: '全部暂停',
                      onTap: () => unawaited(
                          controlTasks(services, running, 'pause')))
                else if (paused.isNotEmpty)
                  _FootButton(
                      label: '全部继续',
                      onTap: () => unawaited(
                          controlTasks(services, paused, 'resume'))),
                const Spacer(),
                _FootButton(
                    label: '动态',
                    arrow: true,
                    onTap: () => shell.go(NextSection.activity)),
              ]),
            ]);
          },
        ),
      ),
    );
  }
}

/// A quiet word at the panel's foot.
class _FootButton extends StatelessWidget {
  const _FootButton(
      {required this.label, required this.onTap, this.arrow = false});
  final String label;
  final VoidCallback onTap;
  final bool arrow;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: NextText.sans(12.5,
                    color: hovered ? NextColors.paper : NextColors.p3)),
            if (arrow) ...[
              const SizedBox(width: 4),
              NextIcon(NextGlyph.chevronRight,
                  size: 11, color: hovered ? NextColors.paper : NextColors.p3),
            ],
          ]),
        ),
      );
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
