import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_tooltip_bubble.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class FloatingActionGlassButton extends StatefulWidget {
  final IconData iconData;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? description; // 新增：悬浮气泡描述
  final double size;
  final double iconSize;

  const FloatingActionGlassButton({
    super.key,
    required this.iconData,
    required this.onPressed,
    this.tooltip,
    this.description, // 新增：悬浮气泡描述
    this.size = 64,
    this.iconSize = 28,
  });

  @override
  State<FloatingActionGlassButton> createState() =>
      _FloatingActionGlassButtonState();
}

class _FloatingActionGlassButtonState extends State<FloatingActionGlassButton> {
  bool _isHovered = false;
  bool _isFocused = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ?? colorScheme.onSurface;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppAccentColors.current;
    final isActive = _isHovered || _isFocused;
    final Color baseBackground = Color.alphaBlend(
      colorScheme.onSurface.withOpacity(isDark ? 0.12 : 0.06),
      colorScheme.surface,
    );
    final iconColor = isActive ? accentColor : textColor;
    final double buttonSize = widget.size;

    final Widget button = FocusableActionDetector(
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
            widget.onPressed();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        scale: isActive ? 1.08 : 1.0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              color: baseBackground,
              shape: BoxShape.circle,
              border: Border.all(
                color: _isFocused ? accentColor : Colors.transparent,
                width: _isFocused ? 1.5 : 0,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                widget.iconData,
                color: iconColor,
                size: widget.iconSize,
              ),
            ),
          ),
        ),
      ),
    );

    // 如果有描述信息，则用HoverTooltipBubble包装
    if (widget.description != null && widget.description!.isNotEmpty) {
      return HoverTooltipBubble(
        text: widget.description!,
        showDelay: const Duration(milliseconds: 500),
        hideDelay: const Duration(milliseconds: 100),
        cursor: SystemMouseCursors.click,
        onHoverChanged: _setHovered,
        child: button,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: button,
    );
  }
}
