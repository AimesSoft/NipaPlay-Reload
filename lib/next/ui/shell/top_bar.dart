import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:window_manager/window_manager.dart';

import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/nipa_avatar.dart';
import '../settings/settings_layout.dart';
import 'background.dart';
import 'nipa_setup.dart';
import 'shell_controller.dart';
import 'window_buttons.dart';
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
    (NextSection.library, '媒体库'),
    (NextSection.activity, '动态'),
  ];

  /// Space between the traffic lights and the first section.
  static const _afterLights = 16.0;
  static const _avatar = 28.0;
  static const _search = 32.0;
  static const _gap = 12.0;

  /// Right edges of the popovers' anchors, from the window's right edge.
  static double get avatarRight =>
      NextMetrics.chromeEdge + NextWindowButtons.width;
  static double get tasksRight =>
      avatarRight + _avatar + _gap + _search + _gap + _search + _gap;

  /// Sections line up with the content column, past the traffic lights
  /// when they would reach it; in full screen there are none.
  static double _left(NextChromeLayout chrome) => chrome.fullScreen
      ? NextMetrics.gutter
      : math.max(NextMetrics.gutter, chrome.leading + _afterLights);


  /// Background work, settings, search and Nipa, on the right of either bar.
  static List<Widget> _trailing(NextShellController shell, {bool compact = false}) => [
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
                          child: BackgroundEntry(
                            onTap: () =>
                                shell.togglePopover(NextPopover.tasks),
                          ),
                        ),
                );
              },
            ),
            NextIconButton(
                glyph: NextGlyph.settings,
                label: '设置',
                size: _search,
                onTap: shell.openSettings),
            const SizedBox(width: _gap),
            NextIconButton(
                glyph: NextGlyph.search,
                label: '搜索',
                size: _search,
                onTap: shell.openSearch),
            const SizedBox(width: _gap),
            if (compact) ...[
              NextIconButton(
                  glyph: NextGlyph.more,
                  label: '菜单',
                  size: _search,
                  onTap: () => shell.togglePopover(NextPopover.nipa)),
              const SizedBox(width: _gap),
            ],
            ListenableBuilder(
              listenable: Listenable.merge([shell.chat, shell.nipaSetup]),
              builder: (context, _) {
                final c = shell.chat;
                final unset = shell.nipaSetup.needsModel;
                // Click: the conversation; right click or long press:
                // the menu (settings, back to Classic).
                return GestureDetector(
                  onSecondaryTap: () =>
                      shell.togglePopover(NextPopover.nipa),
                  onLongPress: () => shell.togglePopover(NextPopover.nipa),
                  child: Pressable(
                    onTap: shell.toggleChat,
                    semanticLabel: '梨花',
                    pressScale: 0.94,
                    builder: (context, hovered) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NipaAvatar(
                          size: _avatar,
                          mood: c.mood,
                          hasNews: c.unseen,
                          sentence: c.moodSentence ??
                              (unset ? '还没有模型' : null),
                        ),
                        if (unset)
                          const Positioned(
                              right: -1, bottom: -1, child: NipaSetupDot()),
                      ],
                    ),
                  ),
                );
              },
            ),
      ];

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
    // A phone: the sections are at its foot ([NextTabBar]); the bar keeps
    // what is always at hand, under the status bar.
    if (NextLayout.compact(context)) return _CompactBar(shell: shell);
    final top = NextLayout.barTop(context);
    return SizedBox(
      height: top + NextMetrics.topBar,
      child: Stack(children: [
        // Only a desktop window is dragged and zoomed by its bar.
        if (globals.isDesktop)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _zoom,
            ),
          ),
        Positioned.fill(
          top: top,
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
                ..._trailing(shell),
                if (NextWindowButtons.wanted) const NextWindowButtons(),
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
      {required this.label,
      required this.active,
      required this.onTap,
      this.height = NextMetrics.topBar,
      this.size = 14});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final double height;
  final double size;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.96,
        builder: (context, hovered) => SizedBox(
          height: height,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: NextText.sans(size,
                      weight: FontWeight.w500,
                      letterSpacing: 0.28,
                      height: 20 / size,
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
            top: NextLayout.underBar(context) + 4,
            right: (which == NextPopover.tasks
                    ? NextTopBar.tasksRight - 14 +
                        (NextLayout.compact(context)
                            ? NextTopBar._search + NextTopBar._gap
                            : 0)
                    : NextTopBar.avatarRight - 8) -
                (NextLayout.compact(context)
                    ? NextMetrics.chromeEdge - NextLayout.compactGutter
                    : 0),
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
                NextPopover.tasks =>
                  const BackgroundPanel(key: ValueKey('tasks')),
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

class _NipaMenu extends StatelessWidget {
  const _NipaMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    // A phone has no keyboard to hint at.
    final keys = !NextLayout.compact(context);
    return MenuPanel(children: [
      if (shell.nipaSetup.needsModel)
        MenuItem(
          label: '设置梨花',
          trailing: const NipaSetupDot(),
          onTap: () => shell.openSettings(section: SettingsSection.nipa),
        ),
      MenuItem(
        label: '问梨花',
        trailing: keys ? const KeyHint('⌘ K') : null,
        onTap: shell.openChat,
      ),
      MenuItem(
        label: '设置',
        trailing: keys ? const KeyHint('⌘ ,') : null,
        onTap: shell.openSettings,
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

/// A phone's top bar, under the status bar: background work, search, the
/// menu (settings, back to Classic) and Nipa on the right. The page's own
/// words start under it.
class _CompactBar extends StatelessWidget {
  const _CompactBar({required this.shell});
  final NextShellController shell;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
            top: NextLayout.barTop(context),
            left: NextLayout.compactGutter,
            right: NextLayout.compactGutter),
        child: SizedBox(
          height: NextMetrics.topBar,
          child: Row(children: [
            const Spacer(),
            ...NextTopBar._trailing(shell, compact: true),
          ]),
        ),
      );
}

/// A phone's sections, at its foot over the page: the same four words as
/// the window's bar, the current one in paper with the crimson dot, on
/// frosted glass above the home indicator.
class NextTabBar extends StatelessWidget {
  const NextTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Glass(
      radius: BorderRadius.zero,
      blur: 24,
      color: const Color(0xB30C0C10),
      borderColor: null,
      highlight: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SizedBox(
            height: NextLayout.tabBar,
            child: ListenableBuilder(
              listenable: shell,
              builder: (context, _) => Row(children: [
                for (final (section, label) in NextTopBar._sections)
                  Expanded(
                    child: _NavItem(
                      label: label,
                      active: shell.section == section,
                      onTap: () => shell.go(section),
                      height: NextLayout.tabBar,
                      size: 15,
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
