import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tooltip_bubble.dart';
import 'control_shadow.dart';

class ShadowActionButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final EdgeInsetsGeometry padding;

  const ShadowActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 28,
    this.padding = const EdgeInsets.all(8.0),
  });

  @override
  State<ShadowActionButton> createState() => _ShadowActionButtonState();
}

class _ShadowActionButtonState extends State<ShadowActionButton> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _isHovered || _isFocused;
    return FocusableActionDetector(
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: TooltipBubble(
          text: widget.tooltip,
          showOnRight: false,
          verticalOffset: 8,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapCancel: () => setState(() => _isPressed = false),
            onTapUp: (_) {
              setState(() => _isPressed = false);
              widget.onPressed();
            },
            child: Padding(
              padding: widget.padding,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 100),
                scale: _isPressed ? 0.9 : (isActive ? 1.1 : 1.0),
                child: ControlIconShadow(
                  child: Icon(
                    widget.icon,
                    color: Colors.white,
                    size: widget.iconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
