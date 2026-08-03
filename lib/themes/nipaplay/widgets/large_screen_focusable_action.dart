import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class NipaplayLargeScreenFocusableStyle {
  const NipaplayLargeScreenFocusableStyle({
    this.focusStrokeColor,
    this.focusStrokeWidth = 2,
    this.idleBackgroundDark = const Color(0x0AFFFFFF),
    this.idleBackgroundLight = const Color(0x08000000),
    this.contentColorDark = Colors.white,
    this.contentColorLight = Colors.black87,
  });

  final Color? focusStrokeColor;
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
    this.isSelected,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.style = const NipaplayLargeScreenFocusableStyle(),
    this.focusScale = 1.0,
  }) : assert(isSelected == null || onActivate != null);

  final Widget child;
  final VoidCallback? onActivate;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool? isSelected;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final NipaplayLargeScreenFocusableStyle style;

  /// Scale applied to the content while the button surface stays fixed.
  final double focusScale;

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
    final isSelected = widget.isSelected == true;
    final Color idleOverlay =
        isDarkMode ? style.idleBackgroundDark : style.idleBackgroundLight;
    final bool isActive = _isFocused || _isHovered || isSelected;
    final Color backgroundColor = isSelected
        ? AppAccentColors.current.withValues(alpha: isDarkMode ? 0.16 : 0.1)
        : idleOverlay;
    final Color contentColor =
        isDarkMode ? style.contentColorDark : style.contentColorLight;

    final scaledContent = AnimatedScale(
      scale: isActive ? widget.focusScale : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );
    final buttonSurface = AnimatedContainer(
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
          color: isActive
              ? (style.focusStrokeColor ?? AppAccentColors.current)
              : Colors.transparent,
          width: style.focusStrokeWidth,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: contentColor),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: contentColor),
          child: scaledContent,
        ),
      ),
    );

    final focusableAction = FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus || isSelected,
      enabled: widget.onActivate != null,
      onFocusChange: (value) {
        if (value && widget.isSelected == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Scrollable.ensureVisible(context, alignment: 0.5);
            }
          });
        }
      },
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
        child: buttonSurface,
      ),
    );

    if (widget.isSelected == null) {
      return focusableAction;
    }
    return Semantics(
      button: true,
      selected: widget.isSelected,
      child: focusableAction,
    );
  }
}
