import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';

import '../data/gui_calls.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'glass.dart';

/// Sheets over the whole Next window: a download's files, a new download,
/// a question before something is deleted. The shell mounts the layer
/// once, above everything; [showNextSheet] puts one up. Esc or the dimmed
/// window around it closes the top one.
class NextSheetLayer extends StatefulWidget {
  const NextSheetLayer({super.key});

  /// How many sheets are up (debug).
  static int get open => _layer?._sheets.length ?? 0;

  /// Closes the top sheet with no answer (debug, Esc).
  static bool closeTop() {
    final layer = _layer;
    if (layer == null || layer._sheets.isEmpty) return false;
    layer._close(layer._sheets.last, null);
    return true;
  }

  @override
  State<NextSheetLayer> createState() => _NextSheetLayerState();
}

_NextSheetLayerState? _layer;

final class _Sheet {
  _Sheet(this.builder, this.width);
  final Widget Function(BuildContext context, void Function([Object?]) close)
      builder;
  final double width;
  final done = Completer<Object?>();
  final focus = FocusNode(debugLabel: 'next.sheet');
}

/// Puts up a sheet [width] wide; what it was closed with.
Future<T?> showNextSheet<T>(
  Widget Function(BuildContext context, void Function([T? value]) close)
      builder, {
  double width = 520,
}) async {
  final layer = _layer;
  if (layer == null) return null;
  final sheet = _Sheet(
      (context, close) => builder(context, ([T? value]) => close(value)),
      width);
  layer._add(sheet);
  return await sheet.done.future as T?;
}

class _NextSheetLayerState extends State<NextSheetLayer> {
  final _sheets = <_Sheet>[];

  @override
  void initState() {
    super.initState();
    _layer = this;
  }

  @override
  void dispose() {
    if (identical(_layer, this)) _layer = null;
    for (final s in _sheets) {
      if (!s.done.isCompleted) s.done.complete(null);
      s.focus.dispose();
    }
    super.dispose();
  }

  void _add(_Sheet sheet) {
    setState(() => _sheets.add(sheet));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => sheet.focus.requestFocus());
  }

  void _close(_Sheet sheet, Object? value) {
    if (!_sheets.contains(sheet)) return;
    setState(() => _sheets.remove(sheet));
    if (!sheet.done.isCompleted) sheet.done.complete(value);
    WidgetsBinding.instance.addPostFrameCallback((_) => sheet.focus.dispose());
  }

  @override
  Widget build(BuildContext context) {
    if (_sheets.isEmpty) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    return Stack(children: [
      for (final (i, sheet) in _sheets.indexed)
        Positioned.fill(
          key: ObjectKey(sheet),
          child: _SheetFrame(
            top: i == _sheets.length - 1,
            onDismiss: () => _close(sheet, null),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _close(sheet, null),
              },
              child: Focus(
                focusNode: sheet.focus,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: sheet.width,
                    maxHeight: size.height - NextMetrics.topBar * 2,
                  ),
                  child: Builder(
                      builder: (context) => sheet.builder(
                          context, ([value]) => _close(sheet, value))),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// The dimmed, softened window and the sheet rising into the middle.
class _SheetFrame extends StatefulWidget {
  const _SheetFrame(
      {required this.top, required this.onDismiss, required this.child});
  final bool top;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<_SheetFrame>
    with SingleTickerProviderStateMixin {
  late final _in = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260))
    ..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    final t = CurvedAnimation(parent: _in, curve: NextMotion.ease);
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.top ? widget.onDismiss : null,
          child: FadeTransition(
            opacity: t,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const ColoredBox(color: Color(0x8C050507)),
            ),
          ),
        ),
      ),
      Center(
        child: FadeTransition(
          opacity: t,
          child: reduced
              ? widget.child
              : ScaleTransition(
                  scale: Tween(begin: 0.97, end: 1.0).animate(t),
                  child: widget.child,
                ),
        ),
      ),
    ]);
  }
}

/// The sheet's own surface: frosted, rounded, padded.
class SheetSurface extends StatelessWidget {
  const SheetSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.fromLTRB(26, 24, 26, 22)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Glass(
        blur: 36,
        color: const Color(0xD912121A),
        borderColor: const Color(0x1FFFFFFF),
        radius: BorderRadius.circular(22),
        shadows: const [
          BoxShadow(
              color: Color(0x99000000), blurRadius: 70, offset: Offset(0, 28))
        ],
        padding: padding,
        child: child,
      );
}

/// One way out of a [chooseSheet].
final class SheetChoice {
  const SheetChoice(this.label, {this.detail, this.danger = false});
  final String label;
  final String? detail;
  final bool danger;
}

/// Asks before something that cannot be taken back; the index of the
/// choice made, null when dismissed.
Future<int?> chooseSheet({
  required String title,
  String? detail,
  required List<SheetChoice> choices,
}) =>
    showNextSheet<int>(
      width: 380,
      (context, close) => SheetSurface(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style: NextText.sans(16, weight: FontWeight.w600, height: 1.4)),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail,
                  textAlign: TextAlign.center,
                  style:
                      NextText.sans(13, color: NextColors.p3, height: 1.5)),
            ],
            const SizedBox(height: 20),
            for (final (i, c) in choices.indexed) ...[
              _ChoiceButton(choice: c, onTap: () => close(i)),
              const SizedBox(height: 8),
            ],
            _ChoiceButton(
                choice: const SheetChoice('取消'), quiet: true, onTap: close),
          ],
        ),
      ),
    );

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton(
      {required this.choice, required this.onTap, this.quiet = false});
  final SheetChoice choice;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: choice.label,
        pressScale: 0.98,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: choice.detail == null ? 42 : 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: quiet
                ? (hovered ? const Color(0x0FFFFFFF) : const Color(0x00FFFFFF))
                : choice.danger
                    ? (hovered ? const Color(0x3DFF2E55) : NextColors.accentSoft)
                    : (hovered
                        ? const Color(0x24FFFFFF)
                        : const Color(0x14FFFFFF)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(choice.label,
                style: NextText.sans(14,
                    weight: quiet ? FontWeight.w400 : FontWeight.w500,
                    color: choice.danger
                        ? NextColors.accent2
                        : quiet
                            ? NextColors.p3
                            : NextColors.paper)),
            if (choice.detail != null) ...[
              const SizedBox(height: 2),
              Text(choice.detail!,
                  style: NextText.sans(11.5, color: NextColors.p3)),
            ],
          ]),
        ),
      );
}

/// Runs [action]; an Action that stops to ask puts its question up, and
/// the option chosen runs (asking again if it asks again). Null when the
/// person backed out.
Future<JsonMap?> withDecisions(
    GuiCalls calls, Future<JsonMap> Function() action) async {
  try {
    return await action();
  } on DecisionNeeded catch (asked) {
    final option = await decisionSheet(asked.decision);
    if (option == null) return null;
    return withDecisions(calls, () => calls.choose(option));
  }
}

/// An Action's question, its options as they are.
Future<DecisionOption?> decisionSheet(Decision decision) async {
  final options = decision.options;
  final i = await chooseSheet(
    title: decision.prompt,
    choices: [
      for (final o in options)
        SheetChoice(o.label,
            detail: o.detail,
            danger: RegExp(r'删|移除|覆盖|丢弃').hasMatch(o.label)),
    ],
  );
  return i == null ? null : options[i];
}
