import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../cards/card_views.dart';
import '../data/background.dart';
import '../data/gui_calls.dart';
import '../downloads/download_list.dart';
import '../downloads/limits_sheet.dart';
import '../downloads/task_open.dart';
import '../settings/controls.dart' show PillButton;
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/sheet.dart';
import '../widgets/words.dart';
import 'history_view.dart';

enum ActivityTab { now, downloads, history }

/// What the debug driver may do with 动态.
abstract interface class ActivityDebug {
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

/// 动态: what runs now (all of it can be paused, resumed or stopped
/// together, and how much runs at once changed), the downloads, and what
/// was watched.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    implements ActivityDebug {
  ActivityTab _tab = ActivityTab.now;
  bool _capacity = false;
  String? _said;

  static const _titles = {
    ActivityTab.now: '进行中',
    ActivityTab.downloads: '下载',
    ActivityTab.history: '观看记录',
  };

  Future<void> _all(List<UiTask> tasks, String command) async {
    final shell = NextShellScope.of(context);
    if (command == 'cancel') {
      final sure = await chooseSheet(
        title: '停止全部后台任务？',
        choices: const [SheetChoice('全部停止', danger: true)],
      );
      if (sure == null) return;
    }
    setState(() => _said = null);
    try {
      final refused = await controlTasks(shell.services, tasks, command);
      if (mounted && refused.isNotEmpty) {
        setState(() => _said = '${refused.length} 个不能${switch (command) {
              'pause' => '暂停',
              'resume' => '继续',
              _ => '停止',
            }}');
      }
    } catch (e) {
      if (mounted) setState(() => _said = callFailure(e));
    }
  }

  // —— debug ——

  @override
  Future<void> debug(Map<String, String> p) async {
    if (p['tab'] case final tab?) {
      setState(() => _tab = ActivityTab.values.byName(tab));
    }
    if (p['capacity'] case final open?) {
      setState(() => _capacity = open == 'true');
    }
    if (p['all'] case final command?) {
      unawaited(_all(NextShellScope.of(context).activeTasks, command));
    }
    if (p['open'] case final i?) {
      final shell = NextShellScope.of(context);
      final task = shell.activeTasks[int.parse(i)];
      unawaited(openTask(shell.services, task));
    }
  }

  @override
  Map<String, Object?> debugStatus() => {
        'tab': _tab.name,
        'capacity': _capacity,
        'said': _said,
        'types': [
          for (final t in NextShellScope.of(context).activeTasks) t.type
        ],
      };

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              NextLayout.gutter(context), NextLayout.underBar(context) + 40, NextLayout.end(context), 26),
          child: ValueListenableBuilder(
            valueListenable: shell.tasks,
            builder: (context, _, __) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final tab in ActivityTab.values) ...[
                  _Tab(
                    label: _titles[tab]!,
                    count: tab == ActivityTab.now
                        ? shell.activeTasks.length
                        : null,
                    on: tab == _tab,
                    onTap: () => setState(() => _tab = tab),
                  ),
                  const SizedBox(width: 28),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: switch (_tab) {
            ActivityTab.now => _now(shell),
            ActivityTab.downloads => const DownloadList(),
            ActivityTab.history => const HistoryView(),
          },
        ),
      ],
    );
  }

  Widget _now(NextShellController shell) => ListenableBuilder(
        listenable: Listenable.merge([shell.tasks, shell.chat]),
        builder: (context, _) {
          final tasks = shell.activeTasks;
          final background = [
            for (final t in tasks)
              if (t.kind == UiTaskKind.background) t
          ];
          // What this device runs; another device's are controlled there.
          final mine = [
            for (final t in tasks)
              if (t.device == null) t
          ];
          final c = shell.chat;
          final line = c.doing ?? c.latestLine;
          void control(UiTask t, String command) => unawaited(
              controlTasks(shell.services, [t], command));
          final callbacks = CardCallbacks(
            onPauseTask: (t) => control(t, 'pause'),
            onResumeTask: (t) => control(t, 'resume'),
            onCancelTask: (t) => control(t, 'cancel'),
          );
          return ListView(
            key: const PageStorageKey('activity/now'),
            padding: EdgeInsets.fromLTRB(NextLayout.gutter(context), 0, NextLayout.end(context), 64 + NextLayout.foot(context)),
            children: [
              if (line != null) ...[
                Row(children: [
                  NipaAvatar(
                      size: 28,
                      mood: c.mood,
                      sentence: c.moodSentence,
                      onTap: shell.openChat),
                  const SizedBox(width: 12),
                  Expanded(child: NipaSentence(line)),
                ]),
                const SizedBox(height: 28),
              ],
              if (tasks.isEmpty)
                Text('现在没有在忙的事。',
                    style: NextText.sans(14.5, color: NextColors.p3))
              else
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 560,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (mine.isNotEmpty)
                          Row(children: [
                            if (mine.any((t) => t.state == UiTaskState.running))
                              PillButton(
                                  label: '全部暂停',
                                  onTap: () => _all(
                                      mine
                                          .where((t) =>
                                              t.state == UiTaskState.running)
                                          .toList(),
                                      'pause')),
                            if (mine.any((t) => t.state == UiTaskState.paused))
                              ...[
                              const SizedBox(width: 8),
                              PillButton(
                                  label: '全部继续',
                                  onTap: () => _all(
                                      mine
                                          .where((t) =>
                                              t.state == UiTaskState.paused)
                                          .toList(),
                                      'resume')),
                            ],
                            const SizedBox(width: 8),
                            PillButton(
                                label: '全部停止',
                                danger: true,
                                onTap: () => _all(mine, 'cancel')),
                            const SizedBox(width: 14),
                            if (_said != null)
                              Flexible(
                                child: Text(_said!,
                                    style: NextText.sans(12.5,
                                        color: NextColors.accent2)),
                              ),
                          ]),
                          const SizedBox(height: 16),
                          for (final (i, task) in background.indexed) ...[
                            if (i > 0) const SizedBox(height: 10),
                            Pressable(
                              onTap: task.device != null
                                  ? null
                                  : () => openTask(shell.services, task),
                              semanticLabel: task.title,
                              pressScale: 0.995,
                              builder: (context, hovered) => CardSurface(
                                selected: hovered,
                                padding: const EdgeInsets.all(14),
                                child:
                                    TaskRow(task: task, callbacks: callbacks),
                              ),
                            ),
                          ],
                          for (final task in tasks)
                            if (task.kind == UiTaskKind.helper) ...[
                              const SizedBox(height: 10),
                              CardSurface(
                                padding: const EdgeInsets.all(14),
                                child: _Helper(
                                    task: task,
                                    onOpen: task.threadId == null
                                        ? null
                                        : () => shell
                                            .openConversation(task.threadId!),
                                    onStop: () => control(task, 'cancel')),
                              ),
                            ],
                        ]),
                  ),
                ),
              const SizedBox(height: 40),
              _CapacityFold(
                open: _capacity,
                onToggle: () => setState(() => _capacity = !_capacity),
              ),
            ],
          );
        },
      );
}

class _Tab extends StatelessWidget {
  const _Tab(
      {required this.label, required this.on, required this.onTap, this.count});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: on ? null : onTap,
        semanticLabel: label,
        pressScale: 0.98,
        builder: (context, hovered) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: NextText.sans(28,
                  weight: FontWeight.w600,
                  color: on
                      ? NextColors.paper
                      : hovered
                          ? NextColors.p3
                          : NextColors.p4),
              child: Text(label),
            ),
            if (count != null && count! > 0)
              Padding(
                padding: const EdgeInsets.only(left: 5, top: 3),
                child: Text('$count',
                    style: NextText.num(13,
                        color: on ? NextColors.accent2 : NextColors.p4)),
              ),
          ],
        ),
      );
}

/// A helper Nipa sent off, as in the background panel: its title and
/// what it does now; it opens to its conversation.
class _Helper extends StatelessWidget {
  const _Helper({required this.task, this.onOpen, required this.onStop});
  final UiTask task;
  final VoidCallback? onOpen;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onOpen,
        semanticLabel: task.title,
        pressScale: 0.995,
        builder: (context, hovered) => Row(children: [
          NipaAvatar(
              size: 30,
              mood: task.state == UiTaskState.running
                  ? NipaMood.acting
                  : NipaMood.idle),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13.5, weight: FontWeight.w600)),
                if (task.currentActivity != null) ...[
                  const SizedBox(height: 5),
                  Text(task.currentActivity!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.sans(12, color: NextColors.p3)),
                ],
              ],
            ),
          ),
          NextIconButton(
              glyph: NextGlyph.close, label: '停止', size: 28, onTap: onStop),
        ]),
      );
}

/// How much runs at once, folded away: each kind of work with its
/// capacity (changeable), what runs and what waits; and download limits.
class _CapacityFold extends StatefulWidget {
  const _CapacityFold({required this.open, required this.onToggle});
  final bool open;
  final VoidCallback onToggle;

  @override
  State<_CapacityFold> createState() => _CapacityFoldState();
}

class _CapacityFoldState extends State<_CapacityFold> {
  List<UiPool>? _pools;
  String? _said;
  Timer? _poll;

  @override
  void didUpdateWidget(_CapacityFold old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) _start();
    if (!widget.open) _poll?.cancel();
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) _start();
  }

  void _start() {
    _load();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pools =
          await NextShellScope.of(context).services.background.pools();
      if (mounted) setState(() => _pools = pools);
    } catch (e) {
      if (mounted) setState(() => _said = callFailure(e));
    }
  }

  Future<void> _set(UiPool pool, int value) async {
    setState(() => _said = null);
    try {
      await NextShellScope.of(context)
          .services
          .background
          .setCapacity(pool.kind, value);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _said = callFailure(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pools = _pools;
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Pressable(
              onTap: widget.onToggle,
              semanticLabel: '容量',
              builder: (context, hovered) => Row(children: [
                Text('容量',
                    style: NextText.sans(13,
                        weight: FontWeight.w500,
                        color: hovered ? NextColors.p2 : NextColors.p3)),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: widget.open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const NextIcon(NextGlyph.chevronRight,
                      size: 11, color: NextColors.p3),
                ),
                if (_said != null) ...[
                  const SizedBox(width: 14),
                  Text(_said!,
                      style: NextText.sans(12, color: NextColors.accent2)),
                ],
              ]),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: NextMotion.ease,
              alignment: Alignment.topLeft,
              child: !widget.open
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(children: [
                        for (final pool in pools ?? const <UiPool>[])
                          _PoolRow(
                              pool: pool,
                              onSet: (v) => _set(pool, v)),
                        _LimitsRow(
                            onTap: () => openLimits(
                                NextShellScope.of(context).services)),
                      ]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One kind of work: its name, what runs and waits (as dots), and how many
/// may run at once.
class _PoolRow extends StatelessWidget {
  const _PoolRow({required this.pool, required this.onSet});
  final UiPool pool;
  final ValueChanged<int> onSet;

  @override
  Widget build(BuildContext context) => Container(
        height: 46,
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: NextColors.line))),
        child: Row(children: [
          SizedBox(
            width: 72,
            child: Text(pool.title,
                style: NextText.sans(13.5, color: NextColors.p2)),
          ),
          Expanded(
            child: Row(children: [
              for (var i = 0; i < pool.capacity.clamp(0, 12); i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        i < pool.active ? NextColors.mint : const Color(0x00000000),
                    border: Border.all(
                        color:
                            i < pool.active ? NextColors.mint : NextColors.p4),
                  ),
                ),
              if (pool.queued > 0) ...[
                const SizedBox(width: 8),
                Text('+${pool.queued}',
                    style: NextText.num(12, color: NextColors.p3)),
              ],
            ]),
          ),
          _Step(label: '减少', minus: true, onTap: pool.capacity > 1
              ? () => onSet(pool.capacity - 1)
              : null),
          SizedBox(
            width: 34,
            child: Text('${pool.capacity}',
                textAlign: TextAlign.center, style: NextText.num(14)),
          ),
          _Step(label: '增加', onTap: () => onSet(pool.capacity + 1)),
        ]),
      );
}

class _LimitsRow extends StatelessWidget {
  const _LimitsRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: '下载限速',
        pressScale: 1,
        builder: (context, hovered) => SizedBox(
          height: 46,
          child: Row(children: [
            Text('下载限速',
                style: NextText.sans(13.5,
                    color: hovered ? NextColors.paper : NextColors.p2)),
            const Spacer(),
            NextIcon(NextGlyph.chevronRight,
                size: 12, color: hovered ? NextColors.p2 : NextColors.p4),
          ]),
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.onTap, this.minus = false});
  final String label;
  final VoidCallback? onTap;
  final bool minus;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered && onTap != null
                ? const Color(0x1FFFFFFF)
                : const Color(0x0AFFFFFF),
            border: Border.all(color: NextColors.line),
          ),
          child: Text(minus ? '−' : '+',
              style: NextText.num(14,
                  color: onTap == null ? NextColors.p4 : NextColors.p2)),
        ),
      );
}
