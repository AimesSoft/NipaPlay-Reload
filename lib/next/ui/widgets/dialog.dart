import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart'
    show InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'buttons.dart';
import 'sheet.dart' show SheetSurface;

/// NipaPlay's own windows (a login, a question before deleting) while Next
/// is the interface: the window dims and softens as under a sheet, and the
/// dialog rises into the middle. A route of its own, over everything,
/// since these come from the body at any moment, video or not. Only Esc
/// or the dialog's own buttons close it: a click that brings the window
/// forward must not answer for the user.
class NextDialogRoute<T> extends RawDialogRoute<T> {
  NextDialogRoute({required WidgetBuilder builder})
      : super(
          barrierDismissible: false,
          barrierColor: const Color(0x00000000),
          transitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (context, _, __) => builder(context),
          transitionBuilder: _rise,
        );

  /// Whether [context] is inside one: the dialog then wears Next's look.
  static bool of(BuildContext context) =>
      ModalRoute.of(context) is NextDialogRoute;

  static Widget _rise(BuildContext context, Animation<double> animation,
      Animation<double> secondary, Widget child) {
    final t = CurvedAnimation(parent: animation, curve: NextMotion.ease);
    final dialog = Center(child: child);
    return Stack(fit: StackFit.expand, children: [
      FadeTransition(
        opacity: t,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: const ColoredBox(color: Color(0x8C050507)),
        ),
      ),
      FadeTransition(
        opacity: t,
        child: NextMotion.reduced(context)
            ? dialog
            : ScaleTransition(
                scale: Tween(begin: 0.97, end: 1.0).animate(t),
                child: dialog,
              ),
      ),
    ]);
  }
}

/// A dialog's surface: the title, what it asks, and the answers on the
/// bottom right. Esc is [onCancel].
class NextDialog extends StatelessWidget {
  const NextDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.body = const [],
    required this.actions,
    required this.onCancel,
    this.width = 420,
    this.autofocus = false,
  });

  final String title;

  /// One quiet line under the title, e.g. the server's address.
  final String? subtitle;
  final List<Widget> body;
  final List<Widget> actions;
  final VoidCallback onCancel;
  final double width;

  /// Takes the keyboard itself (for Esc) when no field of it does.
  final bool autofocus;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onCancel,
        },
        child: Focus(
          autofocus: autofocus,
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: width,
              child: SheetSurface(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title,
                        style: NextText.sans(17,
                            weight: FontWeight.w600, height: 1.3)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NextText.sans(12.5, color: NextColors.p3)),
                    ],
                    for (final (i, b) in body.indexed) ...[
                      SizedBox(height: i == 0 ? 18 : 14),
                      b,
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final (i, a) in actions.indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          a,
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

enum NextDialogButtonKind {
  /// Backing out: quiet.
  cancel,

  /// Going ahead with something the user asked for (登录).
  primary,

  /// Going ahead with something that has a cost (替换, 开启): as
  /// prominent as [cancel] and no more.
  plain,

  /// Going ahead with something that cannot be undone (删除): crimson, so
  /// it is seen, but never the white of a recommendation.
  danger,
}

class NextDialogButton extends StatelessWidget {
  const NextDialogButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = NextDialogButtonKind.cancel,
  });
  final String label;

  /// Null while it cannot be pressed yet.
  final VoidCallback? onTap;
  final NextDialogButtonKind kind;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: onTap == null ? 0.4 : 1,
        duration: const Duration(milliseconds: 160),
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          pressScale: 0.97,
          builder: (context, hovered) {
            final (fill, border, text) = switch (kind) {
              NextDialogButtonKind.cancel => (
                  hovered ? const Color(0x14FFFFFF) : const Color(0x00FFFFFF),
                  NextColors.line2,
                  hovered ? NextColors.paper : NextColors.p2,
                ),
              NextDialogButtonKind.plain => (
                  hovered ? const Color(0x2EFFFFFF) : const Color(0x1FFFFFFF),
                  NextColors.line2,
                  NextColors.paper,
                ),
              NextDialogButtonKind.primary => (
                  hovered ? const Color(0xFFFFFFFF) : NextColors.paper,
                  null,
                  const Color(0xFF111111),
                ),
              NextDialogButtonKind.danger => (
                  hovered ? const Color(0x3DFF2E55) : NextColors.accentSoft,
                  const Color(0x4DFF2E55),
                  hovered ? const Color(0xFFFF8BA0) : NextColors.accent2,
                ),
            };
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 36,
              constraints: const BoxConstraints(minWidth: 76),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(18),
                border: border == null ? null : Border.all(color: border),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(label,
                    style: NextText.sans(13.5,
                        weight: kind == NextDialogButtonKind.cancel
                            ? FontWeight.w500
                            : FontWeight.w600,
                        letterSpacing: 0.2,
                        color: text)),
              ),
            );
          },
        ),
      );
}

/// A field of a dialog: its name above, quiet until focused. A read-only
/// one shows what is already known and takes no typing.
class NextDialogField extends StatefulWidget {
  const NextDialogField({
    super.key,
    required this.label,
    this.controller,
    this.value,
    this.obscure = false,
    this.autofocus = false,
    this.onSubmitted,
  }) : assert((controller == null) != (value == null),
            'A field types into a controller or shows a value');

  final String label;
  final TextEditingController? controller;

  /// Shown read-only.
  final String? value;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<NextDialogField> createState() => _NextDialogFieldState();
}

class _NextDialogFieldState extends State<NextDialogField> {
  late final _own = widget.controller == null
      ? TextEditingController(text: widget.value)
      : null;
  final _focus = FocusNode(debugLabel: 'next.dialog.field');

  bool get _readOnly => widget.controller == null;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _own?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus && !_readOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label,
            style: NextText.sans(12.5,
                weight: FontWeight.w500, color: NextColors.p3)),
        const SizedBox(height: 7),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: _readOnly
                ? const Color(0x05FFFFFF)
                : focused
                    ? const Color(0x14FFFFFF)
                    : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: focused ? const Color(0x59FF2E55) : NextColors.line),
          ),
          child: TextField(
            controller: widget.controller ?? _own,
            focusNode: _focus,
            readOnly: _readOnly,
            autofocus: widget.autofocus,
            obscureText: widget.obscure,
            enableSuggestions: !widget.obscure,
            autocorrect: false,
            cursorColor: NextColors.accent,
            cursorWidth: 1.5,
            style: NextText.sans(14,
                color: _readOnly ? NextColors.p2 : NextColors.paper,
                letterSpacing: widget.obscure ? 1.5 : 0),
            onSubmitted: widget.onSubmitted,
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ),
      ],
    );
  }
}
