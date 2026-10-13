import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';

/// The source's name as the page's title, with ⌄: it opens the sources.
class SourceTitle extends StatelessWidget {
  const SourceTitle(
      {super.key, required this.name, required this.open, required this.onTap});
  final String name;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: name,
        pressScale: 0.98,
        builder: (context, hovered) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: NextText.sans(28, weight: FontWeight.w600)),
            const SizedBox(width: 10),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              curve: NextMotion.ease,
              child: RotatedBox(
                quarterTurns: 1,
                child: NextIcon(NextGlyph.chevronRight,
                    size: 18,
                    color: hovered || open ? NextColors.paper : NextColors.p3),
              ),
            ),
          ],
        ),
      );
}

/// A quiet pill that opens a menu, e.g. the order: “最近添加 ⌄”.
class MenuPill extends StatelessWidget {
  const MenuPill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 32,
          padding: const EdgeInsets.only(left: 14, right: 11),
          decoration: BoxDecoration(
            color: hovered ? const Color(0x1AFFFFFF) : const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NextColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: NextText.sans(13,
                    color: hovered ? NextColors.paper : NextColors.p2)),
            const SizedBox(width: 6),
            RotatedBox(
              quarterTurns: 1,
              child: NextIcon(NextGlyph.chevronRight,
                  size: 12,
                  color: hovered ? NextColors.paper : NextColors.p3),
            ),
          ]),
        ),
      );
}

/// A menu under [link]'s target, for a page's Stack: a click outside or Esc
/// closes it. [right] lines its right edge up with the target's.
List<Widget> anchoredMenu({
  required LayerLink link,
  required Widget menu,
  required VoidCallback close,
  bool right = false,
}) =>
    [
      Positioned.fill(
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: close),
      ),
      Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: link,
          targetAnchor: right ? Alignment.bottomRight : Alignment.bottomLeft,
          followerAnchor: right ? Alignment.topRight : Alignment.topLeft,
          offset: const Offset(0, 10),
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                close();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(
                    scale: 0.97 + 0.03 * t,
                    alignment: right ? Alignment.topRight : Alignment.topLeft,
                    child: child),
              ),
              child: menu,
            ),
          ),
        ),
      ),
    ];
