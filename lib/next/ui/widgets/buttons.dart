import 'package:flutter/widgets.dart';

import '../theme/layout.dart';
import '../theme/tokens.dart';
import 'icons.dart';
import 'television_focus.dart';

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
    this.focusScale = 1.06,
    this.focusRadius = const BorderRadius.all(Radius.circular(999)),
    this.focusRing = true,
    this.autofocus = false,
  });
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final MouseCursor cursor;
  final double pressScale;
  final String? semanticLabel;

  /// On a television, focused: how much it rises, the ring's corners, and
  /// whether it wears the ring at all (not when its face turns over).
  final double focusScale;
  final BorderRadius focusRadius;
  final bool focusRing;

  /// A remote's focus starts here (the page's main action).
  final bool autofocus;

  /// Whether focus here comes from a remote (the hover a builder gets is
  /// then the focus, and should read from across the room).
  static bool get television => TelevisionFocusable.television;

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
    return TelevisionFocusable(
        onActivate: widget.onTap,
        onFocusChange: _hover,
        autofocus: widget.autofocus,
        child: Semantics(
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
              onTapDown:
                  enabled ? (_) => setState(() => _pressed = true) : null,
              onTapCancel:
                  enabled ? () => setState(() => _pressed = false) : null,
              onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
              onTap: widget.onTap,
              child: AnimatedScale(
                scale: _pressed ? widget.pressScale : 1,
                duration: const Duration(milliseconds: 140),
                curve: NextMotion.ease,
                child: Pressable.television
                    ? TelevisionFocusFrame(
                        focused: _hovered && enabled,
                        scale: widget.focusScale,
                        radius: widget.focusRadius,
                        ring: widget.focusRing,
                        child: widget.builder(context, _hovered && enabled))
                    : widget.builder(context, _hovered && enabled),
              ),
            ),
          ),
        ));
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
    this.glyph,
    this.onTap,
    this.height = 46,
    this.expand = false,
    this.autofocus = false,
  });
  const NextButton.ghost({
    super.key,
    required this.label,
    this.leading,
    this.glyph,
    this.onTap,
    this.height = 46,
    this.expand = false,
    this.autofocus = false,
  }) : kind = NextButtonKind.ghost;

  final String label;
  final NextButtonKind kind;
  final Widget? leading;

  /// A glyph before the label, in the label's colour.
  final NextGlyph? glyph;
  final VoidCallback? onTap;
  final double height;

  /// Fills the width it is given, its words in the middle (a phone's
  /// main action under the thumb).
  final bool expand;

  /// A remote's focus starts here.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final primary = kind == NextButtonKind.primary;
    // On a television only the focused button is paper: the others are
    // glass, the primary a little brighter.
    final tv = Pressable.television;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      focusRing: false,
      autofocus: autofocus,
      builder: (context, hovered) {
        final paper = tv ? hovered : primary;
        final ink = paper ? const Color(0xFF111111) : NextColors.paper;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: height,
          alignment: expand ? Alignment.center : null,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: paper
                ? (hovered && !tv ? const Color(0xFFFFFFFF) : NextColors.paper)
                : tv
                    ? (primary ? const Color(0x33F5F1EA) : const Color(0x1FF5F1EA))
                    : (hovered ? const Color(0x24FFFFFF) : const Color(0x1AFFFFFF)),
            borderRadius: BorderRadius.circular(height / 2),
            border: paper ? null : Border.all(color: NextColors.line2),
            boxShadow: tv && hovered
                ? const [
                    BoxShadow(
                        color: Color(0x73000000),
                        blurRadius: 24,
                        offset: Offset(0, 10))
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                NextIcon(glyph!, size: 14, color: ink),
                const SizedBox(width: 10),
              ],
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Text(label,
                  style: NextText.sans(15,
                      weight: FontWeight.w600, letterSpacing: 0.3, color: ink)),
            ],
          ),
        );
      },
    );
  }
}

/// "播放 第 1 集": play glyph plus label with SF numbers.
class PlayButton extends StatelessWidget {
  const PlayButton(
      {super.key,
      required this.label,
      this.onTap,
      this.expand = false,
      this.autofocus = false});
  final String label;
  final VoidCallback? onTap;
  final bool expand;

  /// A remote's focus starts here.
  final bool autofocus;

  @override
  Widget build(BuildContext context) => NextButton(
        label: label,
        onTap: onTap,
        expand: expand,
        glyph: NextGlyph.play,
        autofocus: autofocus,
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
        focusRing: false,
        focusScale: 1.1,
        builder: (context, hovered) {
          // On a television the focused one turns paper, its glyph ink.
          final tv = Pressable.television && hovered;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tv
                  ? NextColors.paper
                  : hovered
                      ? const Color(0x24FFFFFF)
                      : const Color(0x1AFFFFFF),
              border: tv ? null : Border.all(color: NextColors.line2),
            ),
            child: tv
                ? ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                        Color(0xFF111111), BlendMode.srcIn),
                    child: child)
                : child,
          );
        },
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
  Widget build(BuildContext context) {
    // On a television the focused one is a paper disc.
    final tv = Pressable.television;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      focusRing: false,
      focusScale: 1.14,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hovered
              ? (tv ? NextColors.paper : const Color(0x14FFFFFF))
              : const Color(0x00FFFFFF),
        ),
        child: NextIcon(glyph,
            size: 17,
            color: hovered
                ? (tv ? const Color(0xFF111111) : NextColors.paper)
                : NextColors.p2),
      ),
    );
  }
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
        focusRing: false,
        builder: (context, hovered) {
          // On a television the focused chip turns paper.
          final tv = Pressable.television && hovered;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // No backdrop blur here: three chips would mean three blur
              // passes; the darker fill reads the same over the shaded hero.
              color: tv
                  ? NextColors.paper
                  : hovered
                      ? const Color(0x24FFFFFF)
                      : const Color(0x1C1C1C24),
              borderRadius: BorderRadius.circular(18),
              border: tv ? null : Border.all(color: NextColors.line2),
            ),
            child: Text(text,
                maxLines: 1,
                style: NextText.sans(13,
                    color: tv
                        ? const Color(0xFF111111)
                        : hovered
                            ? NextColors.paper
                            : NextColors.p2)),
          );
        },
      );
}

/// `.kbd`: a keyboard hint. A phone has no keyboard to hint at.
class KeyHint extends StatelessWidget {
  const KeyHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => NextLayout.compact(context)
      ? const SizedBox.shrink()
      : Container(
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
