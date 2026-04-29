import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NipaplayLargeScreenFocusableStyle {
  const NipaplayLargeScreenFocusableStyle({
    this.focusStrokeColor = const Color(0xFFFF2E55),
    this.focusStrokeWidth = 2,
    this.idleBackgroundDark = const Color(0x0AFFFFFF),
    this.idleBackgroundLight = const Color(0x08000000),
    this.contentColorDark = Colors.white,
    this.contentColorLight = Colors.black87,
  });

  final Color focusStrokeColor;
  final double focusStrokeWidth;
  final Color idleBackgroundDark;
  final Color idleBackgroundLight;
  final Color contentColorDark;
  final Color contentColorLight;
}

class NipaplayLargeScreenFocusableAction extends StatefulWidget {
  const NipaplayLargeScreenFocusableAction({
    super.key,
    required this.child,
    this.onActivate,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.style = const NipaplayLargeScreenFocusableStyle(),
  });

  final Widget child;
  final VoidCallback? onActivate;
  final FocusNode? focusNode;
  final bool autofocus;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final NipaplayLargeScreenFocusableStyle style;

  @override
  State<NipaplayLargeScreenFocusableAction> createState() =>
      _NipaplayLargeScreenFocusableActionState();
}

class _NipaplayLargeScreenFocusableActionState
    extends State<NipaplayLargeScreenFocusableAction> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final style = widget.style;
    final Color idleOverlay =
        isDarkMode ? style.idleBackgroundDark : style.idleBackgroundLight;
    final bool isActive = _isFocused || _isHovered;
    final Color backgroundColor = idleOverlay;
    final Color contentColor =
        isDarkMode ? style.contentColorDark : style.contentColorLight;

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onShowFocusHighlight: (value) {
        if (_isFocused == value) return;
        setState(() {
          _isFocused = value;
        });
      },
      onShowHoverHighlight: (value) {
        if (_isHovered == value) return;
        setState(() {
          _isHovered = value;
        });
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onActivate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: widget.borderRadius,
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: isActive ? style.focusStrokeColor : Colors.transparent,
              width: style.focusStrokeWidth,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: contentColor),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: contentColor),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
