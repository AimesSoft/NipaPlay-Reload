import 'dart:math' as math;

import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../library/library_controls.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/menu.dart';
import '../widgets/segmented.dart';

/// A group of rows on one quiet card, its title above it.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null && title!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(title!,
                    style: NextText.sans(12.5,
                        weight: FontWeight.w500,
                        letterSpacing: 0.4,
                        color: NextColors.p3)),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x08FFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NextColors.line),
              ),
              child: Column(children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0)
                    Container(
                        height: 1,
                        margin: const EdgeInsets.only(left: 18),
                        color: NextColors.line),
                  child,
                ],
              ]),
            ),
          ],
        ),
      );
}

/// One row: what it is on the left, its control on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.mark,
    this.trailing,
    this.below,
    this.onTap,
    this.highlight = false,
    this.dim = false,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Right after the title (Nipa's mark).
  final Widget? mark;
  final Widget? trailing;

  /// Under the row, inside it (an editor, a note).
  final Widget? below;
  final VoidCallback? onTap;

  /// Just arrived at from elsewhere (search, Nipa's list).
  final bool highlight;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    Widget row(bool hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: NextMotion.ease,
          decoration: BoxDecoration(
            color: highlight
                ? NextColors.accentSoft
                : hovered
                    ? const Color(0x08FFFFFF)
                    : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(16),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                child: Row(children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NextText.sans(14,
                                    color: dim
                                        ? NextColors.p3
                                        : NextColors.paper)),
                          ),
                          if (mark != null) ...[
                            const SizedBox(width: 8),
                            mark!
                          ],
                        ]),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: NextText.sans(12, color: NextColors.p3)),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 16),
                    trailing!
                  ],
                ]),
              ),
            ),
            if (below != null) below!,
          ]),
        );
    if (onTap == null) return row(false);
    return Pressable(
        onTap: onTap,
        semanticLabel: title,
        pressScale: 1,
        builder: (context, hovered) => row(hovered));
  }
}

/// The page's switch: crimson when on.
class NextToggle extends StatelessWidget {
  const NextToggle(
      {super.key, required this.value, this.onChanged, this.label});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        semanticLabel: label,
        pressScale: 0.94,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: NextMotion.ease,
          width: 40,
          height: 24,
          padding: const EdgeInsets.all(3),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value
                ? (onChanged == null
                    ? const Color(0x66FF2E55)
                    : NextColors.accent)
                : (hovered ? const Color(0x2EFFFFFF) : const Color(0x1FFFFFFF)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onChanged == null ? NextColors.p3 : NextColors.paper,
              boxShadow: const [
                BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 4,
                    offset: Offset(0, 1))
              ],
            ),
          ),
        ),
      );
}

/// A choice among a few: side by side when they fit, otherwise a menu.
class ChoiceControl<T> extends StatelessWidget {
  const ChoiceControl(
      {super.key,
      required this.value,
      required this.options,
      required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final letters = options.fold<int>(0, (n, o) => n + o.$2.length);
    if (options.length <= 4 && letters <= 12) {
      return Segmented<T>(
        value: value,
        options: [
          for (final (v, label) in options)
            (
              v,
              label,
              (color) => Text(label, style: NextText.sans(12.5, color: color))
            )
        ],
        onChanged: onChanged,
      );
    }
    return MenuChoice<T>(value: value, options: options, onChanged: onChanged);
  }
}

/// “自动 ⌄”: the chosen one, a menu of the rest.
class MenuChoice<T> extends StatefulWidget {
  const MenuChoice(
      {super.key,
      required this.value,
      required this.options,
      required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  State<MenuChoice<T>> createState() => _MenuChoiceState<T>();
}

class _MenuChoiceState<T> extends State<MenuChoice<T>> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final label = widget.options
            .where((o) => o.$1 == widget.value)
            .map((o) => o.$2)
            .firstOrNull ??
        '${widget.value}';
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Stack(
          children: anchoredMenu(
            link: _link,
            right: true,
            close: _portal.hide,
            menu: MenuPanel(width: 220, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final (v, text) in widget.options)
                      MenuItem(
                        label: text,
                        selected: v == widget.value,
                        trailing: v == widget.value
                            ? const NextIcon(NextGlyph.check,
                                size: 14, color: NextColors.accent)
                            : null,
                        onTap: () {
                          _portal.hide();
                          if (v != widget.value) widget.onChanged(v);
                        },
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        child: MenuPill(label: label, onTap: _portal.toggle),
      ),
    );
  }
}

/// A slim slider with its value beside it. Commits when let go.
class SliderControl extends StatefulWidget {
  const SliderControl({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.step,
    this.integer = false,
    required this.onChanged,
  });
  final num value;
  final num min;
  final num max;
  final num? step;
  final bool integer;
  final ValueChanged<num> onChanged;

  @override
  State<SliderControl> createState() => _SliderControlState();
}

class _SliderControlState extends State<SliderControl> {
  double? _dragging;
  static const _width = 180.0;

  num _snap(double raw) {
    final span = widget.max - widget.min;
    num v = widget.min + raw.clamp(0.0, 1.0) * span;
    final step = widget.step ?? (widget.integer ? 1 : null);
    if (step != null && step > 0) {
      v = widget.min + ((v - widget.min) / step).round() * step;
    } else if (span <= 2) {
      v = (v * 100).round() / 100;
    } else if (span <= 20) {
      v = (v * 10).round() / 10;
    } else {
      v = v.round();
    }
    v = v.clamp(widget.min, widget.max);
    return widget.integer ? v.round() : v;
  }

  String _text(num v) {
    // 0–1 reads better as a percentage.
    if (widget.min == 0 && widget.max == 1) return '${(v * 100).round()}%';
    if (widget.integer || v == v.roundToDouble()) return '${v.round()}';
    final digits = (widget.step ?? 0.01) < 0.1 ? 2 : 1;
    return v.toStringAsFixed(digits);
  }

  double _fraction(num v) => widget.max == widget.min
      ? 0
      : ((v - widget.min) / (widget.max - widget.min))
          .clamp(0.0, 1.0)
          .toDouble();

  void _update(Offset local) =>
      setState(() => _dragging = (local.dx / _width).clamp(0.0, 1.0));

  void _end() {
    final value = _dragging;
    if (value == null) return;
    setState(() => _dragging = null);
    final snapped = _snap(value);
    if (snapped != widget.value) widget.onChanged(snapped);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _dragging == null ? widget.value : _snap(_dragging!);
    final t = _fraction(shown);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 52,
        child: Text(_text(shown),
            textAlign: TextAlign.right,
            style: NextText.num(12.5, color: NextColors.p2)),
      ),
      const SizedBox(width: 14),
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _update(d.localPosition),
          onHorizontalDragUpdate: (d) => _update(d.localPosition),
          onHorizontalDragEnd: (_) => _end(),
          onTapDown: (d) => _update(d.localPosition),
          onTapUp: (_) => _end(),
          child: SizedBox(
            width: _width,
            height: 28,
            child: CustomPaint(painter: _SliderPainter(t, _dragging != null)),
          ),
        ),
      ),
    ]);
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.t, this.active);
  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track =
        RRect.fromLTRBR(0, y - 2, size.width, y + 2, const Radius.circular(2));
    canvas.drawRRect(track, Paint()..color = const Color(0x24FFFFFF));
    final x = size.width * t;
    canvas.drawRRect(
        RRect.fromLTRBR(0, y - 2, x, y + 2, const Radius.circular(2)),
        Paint()..color = NextColors.accent);
    final knob = Offset(x.clamp(8, size.width - 8), y);
    canvas.drawCircle(
        knob,
        active ? 9 : 8,
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(knob, active ? 8 : 7, Paint()..color = NextColors.paper);
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.t != t || old.active != active;
}

/// A quiet one-line field. Commits on Enter or when focus leaves.
class FieldControl extends StatefulWidget {
  const FieldControl({
    super.key,
    required this.value,
    required this.onCommit,
    this.width = 260,
    this.hint,
    this.numeric = false,
    this.obscure = false,
    this.mono = false,
    this.align = TextAlign.left,
  });
  final String value;
  final ValueChanged<String> onCommit;
  final double width;
  final String? hint;
  final bool numeric;
  final bool obscure;
  final bool mono;
  final TextAlign align;

  @override
  State<FieldControl> createState() => _FieldControlState();
}

class _FieldControlState extends State<FieldControl> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode(debugLabel: 'settings.field');
  bool _focused = false;

  /// What was last handed over, until the next keystroke: Enter and
  /// leaving the field do not send it twice, and what NipaPlay answers
  /// replaces it.
  String? _sent;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focused == _focus.hasFocus) return;
      setState(() => _focused = _focus.hasFocus);
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(FieldControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // NipaPlay answered something else than what was handed over (it
    // refused, or kept it its own way): show its answer.
    final answered =
        _sent != null && _text.text == _sent && widget.value != _sent;
    if (answered || (oldWidget.value != widget.value && !_focus.hasFocus)) {
      _text.text = widget.value;
    }
  }

  void _commit() {
    final text = _text.text;
    if (text == widget.value || text == _sent) return;
    _sent = text;
    widget.onCommit(text);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: widget.width,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: _focused ? const Color(0x14FFFFFF) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _focused ? const Color(0x59FF2E55) : NextColors.line),
        ),
        child: TextField(
          controller: _text,
          focusNode: _focus,
          obscureText: widget.obscure,
          textAlign: widget.align,
          keyboardType: widget.numeric
              ? const TextInputType.numberWithOptions(
                  decimal: true, signed: true)
              : null,
          inputFormatters: widget.numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))]
              : null,
          cursorColor: NextColors.accent,
          cursorWidth: 1.5,
          style: widget.mono
              ? NextText.mono(12.5, color: NextColors.paper)
              : NextText.num(13.5),
          onChanged: (_) => _sent = null,
          onSubmitted: (_) => _commit(),
          decoration: InputDecoration.collapsed(
            hintText: widget.hint,
            hintStyle: NextText.sans(13, color: NextColors.p4),
          ),
        ),
      );
}

/// A quiet field that reports every change (forms saved together).
class LiveTextField extends StatefulWidget {
  const LiveTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.width = 320,
    this.obscure = false,
    this.lines = 1,
    this.mono = false,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final double? width;
  final bool obscure;
  final int lines;
  final bool mono;

  @override
  State<LiveTextField> createState() => _LiveTextFieldState();
}

class _LiveTextFieldState extends State<LiveTextField> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode(debugLabel: 'settings.live');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(LiveTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _text.text && !_focus.hasFocus) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final multi = widget.lines > 1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: widget.width,
      height: multi ? null : 34,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: multi ? 12 : 0),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: focused ? const Color(0x14FFFFFF) : const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(multi ? 12 : 10),
        border: Border.all(
            color: focused ? const Color(0x59FF2E55) : NextColors.line),
      ),
      child: TextField(
        controller: _text,
        focusNode: _focus,
        obscureText: widget.obscure,
        minLines: multi ? widget.lines : 1,
        maxLines: multi ? null : 1,
        cursorColor: NextColors.accent,
        cursorWidth: 1.5,
        style: widget.mono
            ? NextText.mono(12.5, color: NextColors.paper, height: 1.6)
            : NextText.sans(13.5, height: multi ? 1.65 : null),
        onChanged: widget.onChanged,
        decoration: InputDecoration.collapsed(
          hintText: widget.hint,
          hintStyle: NextText.sans(13, color: NextColors.p4),
        ),
      ),
    );
  }
}

/// A small pill button for an action on a row: “登录”, “选择”.
class PillButton extends StatelessWidget {
  const PillButton(
      {super.key,
      required this.label,
      this.onTap,
      this.primary = false,
      this.danger = false,
      this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: busy ? null : onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary
                ? (hovered ? const Color(0xFFFFFFFF) : NextColors.paper)
                : danger && hovered
                    ? const Color(0x24FF2E55)
                    : hovered
                        ? const Color(0x1FFFFFFF)
                        : const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(15),
            border: primary ? null : Border.all(color: NextColors.line2),
          ),
          child: busy
              ? const _Dots()
              : Text(label,
                  style: NextText.sans(12.5,
                      weight: FontWeight.w500,
                      color: primary
                          ? const Color(0xFF111111)
                          : danger
                              ? NextColors.accent2
                              : onTap == null
                                  ? NextColors.p4
                                  : NextColors.paper)),
        ),
      );
}

/// Waiting: three dots breathing.
class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NextColors.paper.withValues(
                    alpha: 0.3 +
                        0.7 *
                            (0.5 +
                                0.5 *
                                    math.sin(
                                        (_c.value - i / 6) * 2 * math.pi))),
              ),
            ),
        ]),
      );
}

/// A coloured dot: the state of a connection or device.
class StateDot extends StatelessWidget {
  const StateDot(this.color, {super.key, this.glow = true});
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: glow ? [BoxShadow(color: color, blurRadius: 8)] : null,
        ),
      );
}

/// A path: its last part, the picker, and × to clear it.
class PathControl extends StatelessWidget {
  const PathControl(
      {super.key, required this.value, required this.onPick, this.onClear});
  final String value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final parts = value.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
    final name = parts.isEmpty ? '' : parts.last;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (name.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(13, color: NextColors.p2)),
        ),
      if (name.isNotEmpty && onClear != null)
        NextIconButton(
            glyph: NextGlyph.close, size: 26, label: '清除', onTap: onClear),
      const SizedBox(width: 8),
      PillButton(label: '选择', onTap: onPick),
    ]);
  }
}

/// Colour swatches (the values a setting allows), or one swatch with its
/// hex for any colour.
class ColorControl extends StatelessWidget {
  const ColorControl(
      {super.key,
      required this.value,
      this.choices = const [],
      required this.onChanged});
  final Object? value;
  final List<Object?> choices;
  final ValueChanged<Object?> onChanged;

  static bool _same(Object? a, Object? b) =>
      '$a' == '$b' || (a is num && b is num && a.toInt() == b.toInt());

  static Color? parse(Object? v) {
    if (v is int) return Color(v);
    if (v is num) return Color(v.toInt());
    if (v is String) {
      final hex = v.replaceFirst('#', '');
      final n = int.tryParse(hex, radix: 16);
      if (n == null) return null;
      // #RRGGBBAA (the registry's subtitle colours) → ARGB.
      if (hex.length == 8) {
        return Color(((n & 0xFF) << 24) | (n >> 8));
      }
      if (hex.length == 6) return Color(0xFF000000 | n);
    }
    return null;
  }

  Widget _swatch(Color color, bool on, VoidCallback? tap) => Pressable(
        onTap: tap,
        pressScale: 0.9,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
                color: on
                    ? NextColors.paper
                    : hovered
                        ? NextColors.p3
                        : const Color(0x33FFFFFF),
                width: on ? 2 : 1),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (choices.isNotEmpty) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (final c in choices)
          if (parse(c) case final color?)
            _swatch(color, _same(c, value), () => onChanged(c)),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _swatch(parse(value) ?? const Color(0x00000000), false, null),
      const SizedBox(width: 10),
      FieldControl(
        value: '${value ?? ''}',
        width: 112,
        mono: true,
        onCommit: onChanged,
      ),
    ]);
  }
}

/// Words, as chips; × takes one away, the field adds one.
class ListControl extends StatefulWidget {
  const ListControl({super.key, required this.values, required this.onChanged});
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<ListControl> createState() => _ListControlState();
}

class _ListControlState extends State<ListControl> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final word = _text.text.trim();
    _text.clear();
    if (word.isEmpty || widget.values.contains(word)) return;
    widget.onChanged([...widget.values, word]);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final word in widget.values)
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 12, right: 4),
                decoration: BoxDecoration(
                  color: const Color(0x12FFFFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(word, style: NextText.sans(12.5, color: NextColors.p2)),
                  NextIconButton(
                    glyph: NextGlyph.close,
                    size: 22,
                    label: '移除',
                    onTap: () =>
                        widget.onChanged([...widget.values]..remove(word)),
                  ),
                ]),
              ),
            Container(
              width: 140,
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NextColors.line),
              ),
              child: TextField(
                controller: _text,
                cursorColor: NextColors.accent,
                style: NextText.sans(12.5),
                onSubmitted: (_) => _add(),
                decoration: InputDecoration.collapsed(
                  hintText: '添加',
                  hintStyle: NextText.sans(12.5, color: NextColors.p4),
                ),
              ),
            ),
          ],
        ),
      );
}

/// A shortcut in NipaPlay's own notation (`Shift+←`), shown with the Mac's
/// symbols; click it, then press the new one.
class KeyRecorder extends StatefulWidget {
  const KeyRecorder({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  /// `Shift+←` → `⇧ ←`.
  static String display(String value) => value
      .split('+')
      .map((p) => switch (p.toLowerCase()) {
            'shift' => '⇧',
            'ctrl' => '⌃',
            'alt' => '⌥',
            'meta' => '⌘',
            _ => p,
          })
      .join(' ');

  @override
  State<KeyRecorder> createState() => _KeyRecorderState();
}

class _KeyRecorderState extends State<KeyRecorder> {
  final _focus = FocusNode(debugLabel: 'settings.shortcut');
  bool _listening = false;

  static final _names = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.space: '空格',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.backspace: '退格',
    LogicalKeyboardKey.delete: 'Del',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.pageUp: 'PageUp',
    LogicalKeyboardKey.pageDown: 'PageDown',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.bracketLeft: '[',
    LogicalKeyboardKey.bracketRight: ']',
    LogicalKeyboardKey.minus: '-',
    LogicalKeyboardKey.equal: '=',
    LogicalKeyboardKey.comma: ',',
    LogicalKeyboardKey.period: '.',
    LogicalKeyboardKey.slash: '/',
    LogicalKeyboardKey.semicolon: ';',
    LogicalKeyboardKey.quote: '\'',
    LogicalKeyboardKey.backquote: '`',
    LogicalKeyboardKey.backslash: '\\',
  };

  static final _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  static String? _name(LogicalKeyboardKey key) {
    if (_names[key] case final name?) return name;
    final label = key.keyLabel;
    if (RegExp(r'^[A-Za-z0-9]$').hasMatch(label)) return label.toUpperCase();
    if (RegExp(r'^F([1-9]|1[0-2])$').hasMatch(label)) return label;
    return null;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!_listening || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _listening = false);
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (_modifiers.contains(event.logicalKey)) return KeyEventResult.handled;
    final name = _name(event.logicalKey);
    if (name == null) return KeyEventResult.handled;
    final keys = HardwareKeyboard.instance;
    final combo = [
      if (keys.isControlPressed) 'Ctrl',
      if (keys.isAltPressed) 'Alt',
      if (keys.isMetaPressed) 'Meta',
      if (keys.isShiftPressed) 'Shift',
      name,
    ].join('+');
    setState(() => _listening = false);
    _focus.unfocus();
    if (combo != widget.value) widget.onChanged(combo);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        onFocusChange: (on) {
          if (!on && _listening) setState(() => _listening = false);
        },
        child: Pressable(
          onTap: () {
            setState(() => _listening = true);
            _focus.requestFocus();
          },
          semanticLabel: widget.value,
          builder: (context, hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minWidth: 64),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _listening
                  ? NextColors.accentSoft
                  : hovered
                      ? const Color(0x14FFFFFF)
                      : const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color:
                      _listening ? const Color(0x80FF2E55) : NextColors.line2),
            ),
            child: Text(
                _listening ? '按下新的组合' : KeyRecorder.display(widget.value),
                style: _listening
                    ? NextText.sans(12.5, color: NextColors.accent2)
                    : NextText.num(13, color: NextColors.paper)),
          ),
        ),
      );
}

/// “更多 ⌄”: what is folded away in a section.
class FoldButton extends StatelessWidget {
  const FoldButton(
      {super.key, required this.open, required this.onTap, this.label = '更多'});
  final bool open;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Pressable(
            onTap: onTap,
            semanticLabel: label,
            builder: (context, hovered) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(open ? '收起' : label,
                    style: NextText.sans(13,
                        weight: FontWeight.w500,
                        color: hovered ? NextColors.paper : NextColors.p3)),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: open ? -0.25 : 0.25,
                  duration: const Duration(milliseconds: 200),
                  curve: NextMotion.ease,
                  child: NextIcon(NextGlyph.chevronRight,
                      size: 12,
                      color: hovered ? NextColors.paper : NextColors.p3),
                ),
              ]),
            ),
          ),
        ),
      );
}
