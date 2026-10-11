import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'icons.dart';

/// Hover and press feedback shared by all Next buttons: brightness and a
/// slight press scale, transform and opacity only.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.onHover,
    this.cursor = SystemMouseCursors.click,
    this.pressScale = 0.97,
    this.semanticLabel,
  });
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final MouseCursor cursor;
  final double pressScale;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;

  void _hover(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    widget.onHover?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? widget.cursor : MouseCursor.defer,
        onEnter: (_) => _hover(true),
        onExit: (_) {
          _hover(false);
          if (_pressed) setState(() => _pressed = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? widget.pressScale : 1,
            duration: const Duration(milliseconds: 140),
            curve: NextMotion.ease,
            child: widget.builder(context, _hovered && enabled),
          ),
        ),
      ),
    );
  }
}

enum NextButtonKind { primary, ghost }

/// `.btn.play` / `.btn.ghost`: 46 high, fully rounded.
class NextButton extends StatelessWidget {
  const NextButton({
    super.key,
    required this.label,
    this.kind = NextButtonKind.primary,
    this.leading,
    this.onTap,
    this.height = 46,
  });
  const NextButton.ghost({
    super.key,
    required this.label,
    this.leading,
    this.onTap,
    this.height = 46,
  }) : kind = NextButtonKind.ghost;

  final String label;
  final NextButtonKind kind;
  final Widget? leading;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final primary = kind == NextButtonKind.primary;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: primary
              ? (hovered ? const Color(0xFFFFFFFF) : NextColors.paper)
              : (hovered ? const Color(0x24FFFFFF) : const Color(0x1AFFFFFF)),
          borderRadius: BorderRadius.circular(height / 2),
          border: primary ? null : Border.all(color: NextColors.line2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Text(label,
                style: NextText.sans(15,
                    weight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color:
                        primary ? const Color(0xFF111111) : NextColors.paper)),
          ],
        ),
      ),
    );
  }
}

/// "播放 第 1 集": play glyph plus label with SF numbers.
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => NextButton(
        label: label,
        onTap: onTap,
        leading:
            const NextIcon(NextGlyph.play, size: 14, color: Color(0xFF111111)),
      );
}

/// `.btn.ghost.round`.
class RoundGhostButton extends StatelessWidget {
  const RoundGhostButton(
      {super.key, required this.child, this.onTap, this.size = 46, this.label});
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0x24FFFFFF) : const Color(0x1AFFFFFF),
            border: Border.all(color: NextColors.line2),
          ),
          child: child,
        ),
      );
}

/// `.ico`: a quiet 32px round icon button in the top bar.
class NextIconButton extends StatelessWidget {
  const NextIconButton(
      {super.key, required this.glyph, this.onTap, this.size = 32, this.label});
  final NextGlyph glyph;
  final VoidCallback? onTap;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0x14FFFFFF) : const Color(0x00FFFFFF),
          ),
          child: NextIcon(glyph,
              size: 17, color: hovered ? NextColors.paper : NextColors.p2),
        ),
      );
}

/// `.send`: the crimson round send button.
class SendButton extends StatelessWidget {
  const SendButton({super.key, this.onTap, this.size = 38});
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: '发送',
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0xFFFF4567) : NextColors.accent,
            boxShadow: const [
              BoxShadow(
                  color: Color(0x73FF2E55),
                  blurRadius: 20,
                  offset: Offset(0, 6)),
            ],
          ),
          child: const NextIcon(NextGlyph.send,
              size: 16, color: Color(0xFFFFFFFF)),
        ),
      );
}

/// `.sug`: a suggestion chip. Tapping one says it.
class SuggestionChip extends StatelessWidget {
  const SuggestionChip({super.key, required this.text, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: text,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // No backdrop blur here: three chips would mean three blur
            // passes; the darker fill reads the same over the shaded hero.
            color: hovered ? const Color(0x24FFFFFF) : const Color(0x1C1C1C24),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NextColors.line2),
          ),
          child: Text(text,
              maxLines: 1,
              style: NextText.sans(13,
                  color: hovered ? NextColors.paper : NextColors.p2)),
        ),
      );
}

/// `.kbd`: a keyboard hint.
class KeyHint extends StatelessWidget {
  const KeyHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: NextColors.line2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: NextText.num(11.5, color: NextColors.p3)),
      );
}

/// The round play button that appears over a hovered card.
class HoverPlayButton extends StatelessWidget {
  const HoverPlayButton({super.key, this.onTap, this.size = 46});
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: '播放',
        pressScale: 0.92,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0xFFFFFFFF) : const Color(0xEBF5F1EA),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 6))
            ],
          ),
          child: Padding(
            padding: EdgeInsets.only(left: size * 0.06),
            child: NextIcon(NextGlyph.play,
                size: size * 0.36, color: const Color(0xFF111111)),
          ),
        ),
      );
}
