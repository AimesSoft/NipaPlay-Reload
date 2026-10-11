import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'buttons.dart';
import 'glass.dart';

/// A small frosted menu (the avatar's menu, the detail page's ⋯).
class MenuPanel extends StatelessWidget {
  const MenuPanel({super.key, required this.children, this.width = 208});
  final List<Widget> children;
  final double width;

  @override
  Widget build(BuildContext context) => Glass(
        blur: 30,
        color: const Color(0xC2121218),
        borderColor: const Color(0x1AFFFFFF),
        radius: BorderRadius.circular(16),
        shadows: const [
          BoxShadow(
              color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 20))
        ],
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: width,
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}

class MenuItem extends StatelessWidget {
  const MenuItem(
      {super.key,
      required this.label,
      required this.onTap,
      this.trailing,
      this.selected = false});
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hovered ? const Color(0x14FFFFFF) : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  style: NextText.sans(13.5,
                      color: hovered || selected
                          ? NextColors.paper
                          : NextColors.p2)),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      );
}
