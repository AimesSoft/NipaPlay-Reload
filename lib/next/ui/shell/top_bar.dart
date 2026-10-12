import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../cards/card_views.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/progress.dart';
import 'shell_controller.dart';
import 'window_chrome.dart';

/// `.chrome`: navigation left, background work / search / Nipa right, all
/// on the centre line of the bar, which on macOS is also the traffic
/// lights' (see [NextWindowChrome]). The empty bar drags the window; double
/// click zooms it.
class NextTopBar extends StatelessWidget {
  const NextTopBar({super.key});

  static const _sections = [
    (NextSection.home, '首页'),
    (NextSection.discover, '发现'),
    (NextSection.library, '片库'),
    (NextSection.activity, '动态'),
  ];

  /// Space between the traffic lights and the first section.
  static const _afterLights = 16.0;
  static const _avatar = 28.0;
  static const _search = 32.0;
  static const _gap = 12.0;

  /// Right edges of the popovers' anchors, from the window's right edge.
  static const avatarRight = NextMetrics.chromeEdge;
  static const tasksRight =
      NextMetrics.chromeEdge + _avatar + _gap + _search + _gap;

  /// Sections line up with the content column, past the traffic lights
  /// when they would reach it; in full screen there are none.
  static double _left(NextChromeLayout chrome) => chrome.fullScreen
      ? NextMetrics.gutter
      : math.max(NextMetrics.gutter, chrome.leading + _afterLights);

  Future<void> _zoom() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    return SizedBox(
      height: NextMetrics.topBar,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: _zoom,
          ),
        ),
        Positioned.fill(
          child: ValueListenableBuilder(
            valueListenable: NextWindowChrome.layout,
            builder: (context, chrome, row) => AnimatedPadding(
              duration: NextMotion.page,
              curve: NextMotion.ease,
              padding: EdgeInsets.only(
                  left: _left(chrome), right: NextMetrics.chromeEdge),
              child: row,
            ),
            child: ListenableBuilder(
              listenable: shell,
              builder: (context, _) => Row(children: [
                for (final (i, (section, label)) in _sections.indexed) ...[
                  if (i > 0) const SizedBox(width: 30),
                  _NavItem(
                    label: label,
                    active: shell.section == section,
                    onTap: () => shell.go(section),
                  ),
                ],
                const Spacer(),
                ValueListenableBuilder(
                  valueListenable: shell.tasks,
                  builder: (context, _, __) {
                    final active = shell.activeTasks;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      child: active.isEmpty
                          ? const SizedBox.shrink()
                          : Padding(
                              key: const ValueKey('tasks'),
                              padding: const EdgeInsets.only(right: _gap),
                              child: _TaskPill(
                                progress: shell.totalProgress,
                                onTap: () =>
                                    shell.togglePopover(NextPopover.tasks),
                              ),
                            ),
                    );
                  },
                ),
                NextIconButton(
                    glyph: NextGlyph.search,
                    label: '搜索',
                    size: _search,
                    onTap: shell.ask),
                const SizedBox(width: _gap),
                ListenableBuilder(
                  listenable: shell.chat,
                  builder: (context, _) {
                    final c = shell.chat;
                    // Click: the conversation; right click or long press:
                    // the menu (back to Classic).
                    return GestureDetector(
                      onSecondaryTap: () =>
                          shell.togglePopover(NextPopover.nipa),
                      onLongPress: () => shell.togglePopover(NextPopover.nipa),
                      child: Pressable(
                        onTap: shell.toggleChat,
                        semanticLabel: 'Nipa',
                        pressScale: 0.94,
                        builder: (context, hovered) => NipaAvatar(
                          size: _avatar,
                          mood: c.mood,
                          hasNews: c.unseen,
                          sentence: c.moodSentence,
                        ),
                      ),
                    );
                  },
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A section: the label on the bar's centre line, the crimson dot a fixed
/// distance under the glyphs when it is the current one. The whole bar
/// height is the target.
class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.96,
        builder: (context, hovered) => SizedBox(
          height: NextMetrics.topBar,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: NextText.sans(14,
                      weight: FontWeight.w500,
                      letterSpacing: 0.28,
                      height: 20 / 14,
                      color:
                          active || hovered ? NextColors.paper : NextColors.p3),
                  child: Text(label),
                ),
                Positioned(
                  bottom: -7,
                  child: AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: NextColors.accent,
                        boxShadow: [
                          BoxShadow(color: NextColors.accent, blurRadius: 10)
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// `.task-pill`: a ring with the overall percentage.
class _TaskPill extends StatelessWidget {
  const _TaskPill({required this.progress, required this.onTap});
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: '后台任务',
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
                ProgressRing(progress: progress),
                const SizedBox(width: 10),
                Text('${(progress * 100).round()}%',
                    style: NextText.num(12, color: NextColors.p2)),
              ]),
            ),
          ),
        ),
      );
}

/// Popovers under the top bar. A transparent barrier closes them.
class NextPopovers extends StatelessWidget {
  const NextPopovers({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final which = shell.popover;
        return Stack(children: [
          if (which != NextPopover.none)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: shell.closePopover,
              ),
            ),
          Positioned(
            top: NextMetrics.topBar + 4,
            right: which == NextPopover.tasks
                ? NextTopBar.tasksRight - 14
                : NextTopBar.avatarRight - 8,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.97, end: 1.0).animate(animation),
                  alignment: Alignment.topRight,
                  child: child,
                ),
              ),
              child: switch (which) {
                NextPopover.tasks => const _TaskPanel(key: ValueKey('tasks')),
                NextPopover.nipa => const _NipaMenu(key: ValueKey('nipa')),
                NextPopover.none => const SizedBox.shrink(),
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final actions = shell.services.actions;
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
        width: 340,
        child: ValueListenableBuilder(
          valueListenable: shell.tasks,
          builder: (context, _, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, task) in shell.activeTasks.indexed) ...[
                if (i > 0)
                  Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      color: NextColors.line),
                TaskRow(
                  task: task,
                  callbacks: CardCallbacks(
                    onPauseTask: (t) => actions.pauseTask(t.taskId),
                    onResumeTask: (t) => actions.resumeTask(t.taskId),
                    onCancelTask: (t) => actions.cancelTask(t.taskId),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NipaMenu extends StatelessWidget {
  const _NipaMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    return MenuPanel(children: [
      MenuItem(
        label: '问 Nipa',
        trailing: const KeyHint('⌘ K'),
        onTap: shell.openChat,
      ),
      MenuItem(
        label: '回到经典界面',
        onTap: () {
          shell.closePopover();
          shell.onLeave();
        },
      ),
    ]);
  }
}
