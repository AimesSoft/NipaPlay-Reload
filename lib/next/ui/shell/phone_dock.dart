import 'package:adaptive_platform_ui/adaptive_platform_ui.dart'
    show AdaptiveNavigationDestination, IOS26Glass, IOS26NativeTabBar;
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import 'shell_controller.dart';

/// Glass on the black of Next where the system has none of its own: the
/// same material Classic's phone bar uses there.
const phoneGlass = LiquidGlassSettings(
  thickness: 30,
  blur: 6,
  chromaticAberration: 0.2,
  lightIntensity: 0.45,
  refractiveIndex: 1.5,
  saturation: 0.9,
  ambientStrength: 0.35,
  glassColor: Color(0x52000000),
  backerColor: Color(0x99000000),
);

/// A phone's foot: the line to Nipa above the sections, and search beside
/// them. The line says what she is doing while she works; a tap opens the
/// conversation, the microphone opens it listening.
class PhoneDock extends StatelessWidget {
  const PhoneDock({super.key});

  static const _sections = [
    (NextSection.home, '首页', NextGlyph.home, 'house.fill'),
    (NextSection.discover, '发现', NextGlyph.discover, 'safari.fill'),
    (NextSection.library, '媒体库', NextGlyph.library, 'rectangle.stack.fill'),
    (NextSection.activity, '动态', NextGlyph.activity, 'waveform.path.ecg'),
  ];

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    if (IOS26Glass.supported) {
      // Under the conversation's sheet, out of sight: not on screen at all
      // (see [PhoneGlass]).
      return ValueListenableBuilder<bool>(
          valueListenable: shell.panelOpen,
          builder: (context, open, _) =>
              open ? const SizedBox.shrink() : _system(shell));
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(
          left: NextLayout.dockSide,
          right: NextLayout.dockSide,
          bottom: bottom > 0 ? bottom - 8 : 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _NipaLine(shell: shell),
        const SizedBox(height: NextLayout.dockGap),
        ListenableBuilder(
          listenable: shell,
          builder: (context, _) {
            final index =
                _sections.indexWhere((s) => s.$1 == shell.section);
            return GlassTabBar.bottom(
              tabs: [
                for (final (_, label, glyph, _) in _sections)
                  GlassTab(
                    icon: NextIcon(glyph,
                        size: 24, color: NextColors.paper, stroke: 1.7),
                    activeIcon: NextIcon(glyph,
                        size: 24, color: NextColors.accent, stroke: 1.9),
                    label: label,
                  ),
              ],
              selectedIndex: index < 0 ? 0 : index,
              onTabSelected: (i) => shell.go(_sections[i].$1),
              extraButton: GlassTabBarExtraButton(
                icon: const NextIcon(NextGlyph.search,
                    size: 24, color: NextColors.paper, stroke: 1.8),
                onTap: shell.openSearch,
                label: '搜索',
                size: NextLayout.tabBar,
              ),
              horizontalPadding: 0,
              verticalPadding: 0,
              spacing: 10,
              barHeight: NextLayout.tabBar,
              settings: phoneGlass,
              selectedLabelColor: NextColors.accent,
              unselectedLabelColor: NextColors.paper,
              labelFontSize: 10.5,
              quality: GlassQuality.standard,
            );
          },
        ),
      ]),
    );
  }

  /// iOS 26: the system's tab bar (its search apart, as in the system's
  /// apps), under the line to Nipa on the system's glass.
  Widget _system(NextShellController shell) => Builder(
        builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NextLayout.dockSide),
            child: _NipaLine(shell: shell),
          ),
          const SizedBox(height: NextLayout.dockGap - 4),
          ListenableBuilder(
            listenable: shell,
            builder: (context, _) {
              final index = _sections.indexWhere((s) => s.$1 == shell.section);
              return MediaQuery(
                // Next is dark whatever the system's appearance.
                data: MediaQuery.of(context)
                    .copyWith(platformBrightness: Brightness.dark),
                child: IOS26NativeTabBar(
                  destinations: [
                    for (final (_, label, _, symbol) in _sections)
                      AdaptiveNavigationDestination(icon: symbol, label: label),
                    const AdaptiveNavigationDestination(
                        icon: 'magnifyingglass', label: '搜索', isSearch: true),
                  ],
                  selectedIndex: index < 0 ? 0 : index,
                  tint: NextColors.accent,
                  unselectedItemTint: NextColors.paper,
                  onTap: (i) => i < _sections.length
                      ? shell.go(_sections[i].$1)
                      : shell.openSearch(),
                ),
              );
            },
          ),
        ]),
      );
}

/// A phone's glass for what Flutter draws on it (the line to Nipa, round
/// buttons, the player's capsule): a dark tint with a fine light edge and
/// nothing behind it computed. The system's glass would be a view of its
/// own, composed again every frame anything under it moves, at 120 Hz; the
/// shader glass is redrawn as often. Only the tab bar is the system's.
/// A capsule (a circle when square) unless [radius] is given.
class PhoneGlass extends StatelessWidget {
  const PhoneGlass(
      {super.key,
      this.width,
      this.height,
      this.radius,
      this.alignment,
      this.padding,
      this.child});
  final double? width;
  final double? height;
  final double? radius;
  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  static const _side = BorderSide(color: Color(0x2EFFFFFF), width: 0.8);

  @override
  Widget build(BuildContext context) {
    final square = width != null && width == height && radius == null;
    final ShapeBorder shape = square
        ? const CircleBorder(side: _side)
        : radius == null
            ? const StadiumBorder(side: _side)
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius!), side: _side);
    return Container(
      width: width,
      height: height,
      padding: padding,
      alignment: alignment,
      decoration: ShapeDecoration(
        shape: shape,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xD12A2A31), Color(0xD11A1A20)],
        ),
      ),
      child: child,
    );
  }
}

/// The line to Nipa: her face, what she is doing (or the question the
/// home asks), and the microphone.
class _NipaLine extends StatelessWidget {
  const _NipaLine({required this.shell});
  final NextShellController shell;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([shell.chat, shell.tasks]),
        builder: (context, _) {
          final c = shell.chat;
          final doing = c.moodSentence;
          final task = shell.activeTasks.firstOrNull;
          final live = doing ?? (task == null ? null : '正在准备《${task.title}》');
          return Pressable(
            onTap: shell.openChat,
            semanticLabel: '和梨花说话',
            pressScale: 0.98,
            builder: (context, _) => PhoneGlass(
              height: NextLayout.dockLine,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                NipaAvatar(size: 38, mood: c.mood, hasNews: c.unseen),
                const SizedBox(width: 10),
                if (live != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: NextColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    live ?? '今天想看什么？',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(15,
                        color: live == null ? NextColors.p2 : NextColors.paper),
                  ),
                ),
                Pressable(
                  onTap: shell.speak,
                  semanticLabel: '说话',
                  pressScale: 0.9,
                  builder: (context, _) => Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                        color: Color(0x1FFFFFFF), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const NextIcon(NextGlyph.mic,
                        size: 19, color: NextColors.paper, stroke: 1.8),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}

/// A round glass button at a phone's top: the menu, back, more.
class PhoneGlassCircle extends StatelessWidget {
  const PhoneGlassCircle(
      {super.key, required this.child, this.onTap, this.label, this.size = 40});
  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.92,
        builder: (context, _) => PhoneGlass(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: child,
        ),
      );
}
