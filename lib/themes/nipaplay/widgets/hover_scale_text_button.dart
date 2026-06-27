import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class HoverScaleTextButton extends StatefulWidget {
  final String? text;
  final Widget? child;
  final VoidCallback? onPressed;
  final Color? idleColor;
  final Color? hoverColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry padding;
  final double hoverScale;
  final Duration duration;
  final Curve curve;

  const HoverScaleTextButton({
    super.key,
    this.text,
    this.child,
    required this.onPressed,
    this.idleColor,
    this.hoverColor,
    this.textStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.hoverScale = 1.1,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutBack,
  }) : assert(text != null || child != null);

  @override
  State<HoverScaleTextButton> createState() => _HoverScaleTextButtonState();
}

class _HoverScaleTextButtonState extends State<HoverScaleTextButton> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null;
    final bool isLargeScreenModeActive =
        NipaplayLargeScreenModeScope.isActiveOf(context);
    final bool isActive = isEnabled && (_isHovered || _isFocused);
    TextStyle? childTextStyle;
    Color? childTextColor;
    if (widget.child is Text) {
      final textChild = widget.child as Text;
      childTextStyle = textChild.style;
      childTextColor = textChild.style?.color;
    }

    final Color baseColor = widget.idleColor ??
        childTextColor ??
        Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    final Color resolvedBaseColor =
        isEnabled ? baseColor : baseColor.withOpacity(0.5);
    final Color hoverColor = widget.hoverColor ?? AppAccentColors.current;
    final Color textColor = isActive ? hoverColor : resolvedBaseColor;
    final TextStyle defaultStyle =
        Theme.of(context).textTheme.labelLarge ?? TextStyle(fontSize: 14);
    final TextStyle effectiveBaseStyle =
        childTextStyle ?? widget.textStyle ?? defaultStyle;

    final Widget content = _buildContent(
      textColor: textColor,
      baseStyle: effectiveBaseStyle,
    );

    return FocusableActionDetector(
      enabled: isEnabled,
      onShowFocusHighlight: (value) {
        if (_isFocused == value) return;
        setState(() {
          _isFocused = value;
        });
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => isEnabled ? setState(() => _isHovered = true) : null,
        onExit: (_) => isEnabled ? setState(() => _isHovered = false) : null,
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isLargeScreenModeActive && _isFocused
                    ? AppAccentColors.current
                    : Colors.transparent,
                width: isLargeScreenModeActive && _isFocused ? 1.5 : 0,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: AnimatedScale(
              scale: isActive ? widget.hoverScale : 1.0,
              duration: widget.duration,
              curve: widget.curve,
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent({
    required Color textColor,
    required TextStyle baseStyle,
  }) {
    if (widget.child is Text) {
      final textChild = widget.child as Text;
      final TextStyle resolvedStyle = baseStyle.copyWith(color: textColor);

      if (textChild.data != null) {
        return IconTheme(
          data: IconThemeData(color: textColor),
          child: Text(
            textChild.data!,
            key: textChild.key,
            style: resolvedStyle,
            strutStyle: textChild.strutStyle,
            textAlign: textChild.textAlign,
            textDirection: textChild.textDirection,
            locale: textChild.locale,
            softWrap: textChild.softWrap,
            overflow: textChild.overflow,
            textScaleFactor: textChild.textScaleFactor,
            maxLines: textChild.maxLines,
            semanticsLabel: textChild.semanticsLabel,
            textWidthBasis: textChild.textWidthBasis,
            textHeightBehavior: textChild.textHeightBehavior,
          ),
        );
      }

      if (textChild.textSpan != null) {
        return IconTheme(
          data: IconThemeData(color: textColor),
          child: Text.rich(
            textChild.textSpan!,
            key: textChild.key,
            style: resolvedStyle,
            strutStyle: textChild.strutStyle,
            textAlign: textChild.textAlign,
            textDirection: textChild.textDirection,
            locale: textChild.locale,
            softWrap: textChild.softWrap,
            overflow: textChild.overflow,
            textScaleFactor: textChild.textScaleFactor,
            maxLines: textChild.maxLines,
            semanticsLabel: textChild.semanticsLabel,
            textWidthBasis: textChild.textWidthBasis,
            textHeightBehavior: textChild.textHeightBehavior,
          ),
        );
      }
    }

    if (widget.text != null) {
      return IconTheme(
        data: IconThemeData(color: textColor),
        child: Text(
          widget.text!,
          style: baseStyle.copyWith(color: textColor),
        ),
      );
    }

    return IconTheme(
      data: IconThemeData(color: textColor),
      child: DefaultTextStyle.merge(
        style: baseStyle.copyWith(color: textColor),
        child: widget.child!,
      ),
    );
  }
}
