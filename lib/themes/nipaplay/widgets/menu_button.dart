// ignore: file_names
import 'package:flutter/material.dart';
import 'keyboard_activatable.dart';

class WindowControlButtons extends StatelessWidget {
  static const double buttonWidth = 46;
  static const double buttonHeight = 40;
  static const double totalWidth = buttonWidth * 3;

  final bool isMaximized;
  final VoidCallback onMinimize;
  final VoidCallback onMaximizeRestore;
  final VoidCallback onClose;

  const WindowControlButtons({
    super.key,
    required this.isMaximized,
    required this.onMinimize,
    required this.onMaximizeRestore,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: totalWidth,
      height: buttonHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowControlIconButton(
            icon: Icons.remove_rounded,
            size: 22,
            tooltip: '最小化',
            onPressed: onMinimize,
          ),
          _WindowControlIconButton(
            icon: isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            size: isMaximized ? 18 : 22,
            isFlipped: isMaximized,
            tooltip: isMaximized ? '还原' : '最大化',
            onPressed: onMaximizeRestore,
          ),
          _WindowControlIconButton(
            icon: Icons.close_rounded,
            size: 22,
            tooltip: '关闭',
            isCloseButton: true,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _WindowControlIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final bool isFlipped;
  final bool isCloseButton;
  final String tooltip;
  final VoidCallback onPressed;

  const _WindowControlIconButton({
    required this.icon,
    this.size = 22,
    this.isFlipped = false,
    this.isCloseButton = false,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_WindowControlIconButton> createState() =>
      _WindowControlIconButtonState();
}

class _WindowControlIconButtonState extends State<_WindowControlIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  void _setHovered(bool value) {
    if (_isHovered == value) {
      return;
    }
    setState(() {
      _isHovered = value;
    });
  }

  void _setFocused(bool value) {
    if (_isFocused == value) {
      return;
    }
    setState(() {
      _isFocused = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color hoverBackground = isDarkMode
        ? Colors.white.withOpacity(0.12)
        : Colors.black.withOpacity(0.08);
    final Color pressedBackground = isDarkMode
        ? Colors.white.withOpacity(0.18)
        : Colors.black.withOpacity(0.14);
    final bool showActiveState = _isHovered || _isFocused || _isPressed;
    final Color backgroundColor = widget.isCloseButton && showActiveState
        ? (_isPressed ? const Color(0xFFC50F1F) : const Color(0xFFE81123))
        : (_isPressed
            ? pressedBackground
            : ((_isHovered || _isFocused)
                ? hoverBackground
                : Colors.transparent));
    final Color iconColor = widget.isCloseButton && showActiveState
        ? Colors.white
        : (isDarkMode ? Colors.white : Colors.black87);

    Widget iconWidget = Icon(
      widget.icon,
      size: widget.size,
      color: iconColor,
    );

    // 如果需要翻转（垂直+水平翻转等同于旋转180度）
    if (widget.isFlipped) {
      iconWidget = Transform.rotate(
        angle: 3.14159, // 180度 (PI)
        child: iconWidget,
      );
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: KeyboardActivatable(
          onActivate: widget.onPressed,
          onFocusChange: _setFocused,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: widget.onPressed,
            child: AnimatedContainer(
              width: WindowControlButtons.buttonWidth,
              height: WindowControlButtons.buttonHeight,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOutCubic,
              color: backgroundColor,
              alignment: Alignment.center,
              child: iconWidget,
            ),
          ),
        ),
      ),
    );
  }
}
