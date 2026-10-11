import 'dart:async';

import 'package:flutter/widgets.dart';

import '../conversation/turn_activity.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'icons.dart';
import 'nipa_avatar.dart';
import 'progress.dart';

/// One line showing that Nipa is working: while the turn runs, a small
/// avatar, what it is doing and a clock (“在查资料 · 0:32”); afterwards
/// “想了 32 秒 · 5 步”. With [expandable] it opens to the steps: thinking
/// as merged text, commands in monospace with how they ended, each output
/// folded. Only the avatar and the clock move.
class ActivityLine extends StatefulWidget {
  const ActivityLine(
      {super.key,
      required this.activity,
      this.expandable = true,
      this.asking = false});
  final TurnActivity activity;
  final bool expandable;

  /// Nipa asked something and waits for your answer.
  final bool asking;

  @override
  State<ActivityLine> createState() => _ActivityLineState();
}

class _ActivityLineState extends State<ActivityLine> {
  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final open = a.shown;
    final canOpen = widget.expandable && a.steps.isNotEmpty;
    final Widget line;
    if (a.running) {
      final doing = widget.asking ? '在等你回答' : a.doing;
      line = Row(mainAxisSize: MainAxisSize.min, children: [
        NipaAvatar(
            size: 20,
            mood: widget.asking
                ? NipaMood.waiting
                : doing != '在想'
                    ? NipaMood.acting
                    : NipaMood.thinking),
        const SizedBox(width: 10),
        Flexible(
          child: Text(doing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(13, color: NextColors.p2)),
        ),
        Text('  ·  ', style: NextText.sans(13, color: NextColors.p4)),
        _Clock(since: a.startedAt),
      ]);
    } else {
      line = Text(a.summary, style: NextText.sans(12.5, color: NextColors.p3));
    }
    final head = !canOpen
        ? line
        : Pressable(
            onTap: () => setState(() => a.shown = !a.shown),
            semanticLabel: open ? '收起' : '展开',
            pressScale: 0.99,
            builder: (context, hovered) =>
                Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: line),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: const Duration(milliseconds: 160),
                child: NextIcon(NextGlyph.chevronRight,
                    size: 10, color: hovered ? NextColors.p2 : NextColors.p4),
              ),
            ]),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(alignment: Alignment.centerLeft, child: head),
        if (open && canOpen)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 2),
            child: _Steps(activity: a),
          ),
      ],
    );
  }
}

/// m:ss since [since]; only this text rebuilds each second.
class _Clock extends StatefulWidget {
  const _Clock({required this.since});
  final DateTime since;

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
        TurnActivity.clock(DateTime.now().difference(widget.since)),
        style: NextText.num(12.5, color: NextColors.p3),
      );
}

class _Steps extends StatelessWidget {
  const _Steps({required this.activity});
  final TurnActivity activity;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: NextColors.line2, width: 1.5))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, step) in activity.steps.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              switch (step) {
                ThoughtStep() => step.text.isEmpty
                    ? const SizedBox.shrink()
                    : Text(step.text.toString().trim(),
                        style: NextText.sans(12.5,
                            color: NextColors.p3, height: 1.6)),
                CommandStep() => _Command(key: ObjectKey(step), step: step),
                ToolStep() => Text(step.label,
                    style: NextText.sans(12.5, color: NextColors.p2)),
              },
            ],
          ],
        ),
      );
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
              child: Text(TurnActivity.bare(step.command),
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
                          style: NextText.sans(11.5, color: NextColors.accent2)),
            ),
          ]),
          if (output.isNotEmpty) ...[
            const SizedBox(height: 6),
            Pressable(
              onTap: () => setState(() => step.outputShown = !shown),
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
