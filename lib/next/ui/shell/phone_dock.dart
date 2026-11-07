import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import 'shell_controller.dart';

/// Glass on the black of Next: the same material Classic's phone bar uses.
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
    (NextSection.home, '首页', NextGlyph.home),
    (NextSection.discover, '发现', NextGlyph.discover),
    (NextSection.library, '媒体库', NextGlyph.library),
    (NextSection.activity, '动态', NextGlyph.activity),
  ];

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
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
                for (final (_, label, glyph) in _sections)
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
            builder: (context, _) => GlassContainer(
              height: NextLayout.dockLine,
              shape: const LiquidRoundedSuperellipse(
                  borderRadius: NextLayout.dockLine / 2),
              settings: phoneGlass,
              quality: GlassQuality.standard,
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
        builder: (context, _) => GlassContainer(
          width: size,
          height: size,
          shape: const LiquidOval(),
          settings: phoneGlass,
          quality: GlassQuality.standard,
          alignment: Alignment.center,
          child: child,
        ),
      );
}
