import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import 'playback.dart';

/// The frosted surface the player's menus sit on, as the shell's popovers.
class PlayerMenuSurface extends StatelessWidget {
  const PlayerMenuSurface(
      {super.key, required this.width, required this.child});
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => Glass(
        blur: 30,
        color: const Color(0xD1121218),
        borderColor: const Color(0x1AFFFFFF),
        radius: BorderRadius.circular(16),
        shadows: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 12))
        ],
        padding: const EdgeInsets.all(6),
        child: SizedBox(width: width, child: child),
      );
}

class PlayerMenuHeading extends StatelessWidget {
  const PlayerMenuHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Text(text,
            style: NextText.sans(12,
                weight: FontWeight.w600,
                letterSpacing: 0.8,
                color: NextColors.p3)),
      );
}

/// A page's heading with the way back: ‹ 倍速.
class PlayerMenuBack extends StatelessWidget {
  const PlayerMenuBack(this.text, {super.key, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: '返回',
        pressScale: 0.98,
        builder: (context, hovered) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          child: Row(children: [
            NextIcon(NextGlyph.chevronLeft,
                size: 14, color: hovered ? NextColors.paper : NextColors.p3),
            const SizedBox(width: 4),
            Text(text,
                style: NextText.sans(12,
                    weight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: hovered ? NextColors.paper : NextColors.p3)),
          ]),
        ),
      );
}

class PlayerMenuDivider extends StatelessWidget {
  const PlayerMenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: NextColors.line);
}

/// A row that opens a page: what it is, what it is now, ›.
class PlayerMenuLink extends StatelessWidget {
  const PlayerMenuLink(
      {super.key, required this.label, this.value, required this.onTap});
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(
            color: hovered ? const Color(0x14FFFFFF) : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Text(label,
                style: NextText.sans(13.5,
                    color: hovered ? NextColors.paper : NextColors.p2)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value ?? '',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(12.5, color: NextColors.p3)),
            ),
            const SizedBox(width: 4),
            NextIcon(NextGlyph.chevronRight,
                size: 14, color: hovered ? NextColors.p2 : NextColors.p4),
          ]),
        ),
      );
}

/// A row of a page that sets something: its name, then the control.
class PlayerMenuRow extends StatelessWidget {
  const PlayerMenuRow({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 42,
          child: Row(children: [
            SizedBox(
              width: 46,
              child:
                  Text(label, style: NextText.sans(13.5, color: NextColors.p2)),
            ),
            Expanded(child: child),
          ]),
        ),
      );
}

/// How a dial reads: 80%, 30, 1.25×, +0.5s.
String dialText(DialUnit unit, double v) => switch (unit) {
      DialUnit.percent => '${(v * 100).round()}%',
      DialUnit.points => '${v.round()}',
      DialUnit.times => '${v.toStringAsFixed(2)}×',
      DialUnit.seconds => v.abs() < 0.001
          ? '0s'
          : '${v > 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}s',
    };

/// − value +: a step a click, faster while held. A click on the value
/// brings it back to [rest].
class PlayerMenuStepper extends StatefulWidget {
  const PlayerMenuStepper({
    super.key,
    required this.label,
    required this.dial,
    required this.onChanged,
    this.rest = 0,
  });
  final String label;
  final PlayerDial dial;
  final ValueChanged<double> onChanged;
  final double rest;

  @override
  State<PlayerMenuStepper> createState() => _PlayerMenuStepperState();
}

class _PlayerMenuStepperState extends State<PlayerMenuStepper> {
  Timer? _hold;
  bool _held = false;

  // What was asked last: the dial catches up after Classic notifies.
  double? _asked;

  double get _value => _asked ?? widget.dial.value;

  @override
  void didUpdateWidget(PlayerMenuStepper old) {
    super.didUpdateWidget(old);
    if (_hold == null) _asked = null;
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _step(int by) {
    final next = widget.dial.clamp(_value + by * widget.dial.step);
    if ((next - _value).abs() < 0.0001) return;
    setState(() => _asked = next);
    widget.onChanged(next);
  }

  void _press(int by) {
    _held = false;
    _hold?.cancel();
    _hold = Timer(const Duration(milliseconds: 420), () {
      _held = true;
      _hold =
          Timer.periodic(const Duration(milliseconds: 90), (_) => _step(by));
    });
  }

  void _release() {
    _hold?.cancel();
    _hold = null;
  }

  Widget _button(NextGlyph glyph, int by, String name) => Listener(
        onPointerDown: (_) => _press(by),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: Pressable(
          onTap: () {
            if (!_held) _step(by);
            _held = false;
          },
          semanticLabel: '${widget.label}$name',
          pressScale: 0.9,
          builder: (context, hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  hovered ? const Color(0x1FFFFFFF) : const Color(0x0DFFFFFF),
            ),
            child: NextIcon(glyph,
                size: 13,
                stroke: 2,
                color: hovered ? NextColors.paper : NextColors.p2),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final atRest = (v - widget.rest).abs() < 0.0001;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _button(NextGlyph.minus, -1, '减'),
      Pressable(
        onTap: atRest
            ? null
            : () {
                setState(() => _asked = widget.rest);
                widget.onChanged(widget.rest);
              },
        semanticLabel: '${widget.label}复原',
        pressScale: 0.96,
        builder: (context, hovered) => SizedBox(
          width: 68,
          child: Text(dialText(widget.dial.unit, v),
              textAlign: TextAlign.center,
              style: NextText.num(13,
                  color: hovered
                      ? NextColors.paper
                      : atRest
                          ? NextColors.p3
                          : NextColors.paper)),
        ),
      ),
      _button(NextGlyph.plus, 1, '加'),
    ]);
  }
}

/// A slim slider with what it is set to beside it: the change shows while
/// dragged, [onEnd] keeps it.
class PlayerMenuSlider extends StatefulWidget {
  const PlayerMenuSlider({
    super.key,
    required this.label,
    required this.dial,
    required this.onChanged,
    this.onEnd,
  });
  final String label;
  final PlayerDial dial;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onEnd;

  @override
  State<PlayerMenuSlider> createState() => _PlayerMenuSliderState();
}

class _PlayerMenuSliderState extends State<PlayerMenuSlider> {
  double? _dragging;

  double get _value => _dragging ?? widget.dial.value;

  double _fraction(double v) {
    final d = widget.dial;
    return d.max == d.min ? 0 : ((v - d.min) / (d.max - d.min)).clamp(0.0, 1.0);
  }

  double _at(Offset local, double width) {
    final d = widget.dial;
    final t = width <= 0 ? 0.0 : (local.dx / width).clamp(0.0, 1.0);
    return d.clamp(d.min + t * (d.max - d.min));
  }

  void _move(double v) {
    if (_dragging != null && (v - _dragging!).abs() < 0.0001) return;
    setState(() => _dragging = v);
    widget.onChanged(v);
  }

  void _end() {
    final v = _dragging;
    if (v == null) return;
    (widget.onEnd ?? widget.onChanged)(v);
    setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    return Row(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final width = c.maxWidth;
          final t = _fraction(v);
          return Semantics(
            label: widget.label,
            slider: true,
            value: dialText(widget.dial.unit, v),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (e) => _move(_at(e.localPosition, width)),
                onTapUp: (_) => _end(),
                onHorizontalDragStart: (e) =>
                    _move(_at(e.localPosition, width)),
                onHorizontalDragUpdate: (e) =>
                    _move(_at(e.localPosition, width)),
                onHorizontalDragEnd: (_) => _end(),
                onHorizontalDragCancel: _end,
                child: SizedBox(
                  height: 28,
                  child: Stack(alignment: Alignment.centerLeft, children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: t,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: NextColors.paper,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: t * (width - 11),
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: NextColors.paper,
                          boxShadow: [
                            BoxShadow(color: Color(0x55000000), blurRadius: 4)
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }),
      ),
      SizedBox(
        width: 48,
        child: Text(dialText(widget.dial.unit, v),
            textAlign: TextAlign.right,
            style: NextText.num(12.5, color: NextColors.p2)),
      ),
    ]);
  }
}

/// One of a few, side by side, the chosen one lit.
class PlayerMenuChoices<T> extends StatelessWidget {
  const PlayerMenuChoices({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: NextColors.line),
        ),
        child: Row(children: [
          for (final (option, label) in options)
            Expanded(
              child: Pressable(
                onTap: option == value ? null : () => onChanged(option),
                semanticLabel: label,
                pressScale: 0.96,
                builder: (context, hovered) {
                  final on = option == value;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on
                          ? const Color(0x29FFFFFF)
                          : hovered
                              ? const Color(0x0FFFFFFF)
                              : const Color(0x00FFFFFF),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(label,
                        maxLines: 1,
                        style: NextText.sans(12,
                            weight: on ? FontWeight.w600 : FontWeight.w400,
                            color: on || hovered
                                ? NextColors.paper
                                : NextColors.p3)),
                  );
                },
              ),
            ),
        ]),
      );
}

/// Words that are each on or off, lit when on.
class PlayerMenuChips<T> extends StatelessWidget {
  const PlayerMenuChips({
    super.key,
    required this.options,
    required this.on,
    required this.onChanged,
  });
  final List<(T, String)> options;
  final bool Function(T option) on;
  final void Function(T option, bool on) onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final (i, (option, label)) in options.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Pressable(
            onTap: () => onChanged(option, !on(option)),
            semanticLabel: label,
            pressScale: 0.95,
            builder: (context, hovered) {
              final lit = on(option);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lit
                      ? const Color(0x29FFFFFF)
                      : hovered
                          ? const Color(0x0FFFFFFF)
                          : const Color(0x00FFFFFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: lit ? const Color(0x00FFFFFF) : NextColors.line2),
                ),
                child: Text(label,
                    style: NextText.sans(12,
                        weight: lit ? FontWeight.w600 : FontWeight.w400,
                        color:
                            lit || hovered ? NextColors.paper : NextColors.p3)),
              );
            },
          ),
        ],
      ]);
}
