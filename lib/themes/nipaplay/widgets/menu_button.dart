// ignore: file_names
import 'package:flutter/material.dart';

class WindowControlButtons extends StatelessWidget {
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowControlIconButton(
          icon: Icons.remove_rounded,
          size: 22,
          tooltip: '最小化',
          onPressed: onMinimize,
        ),
        const SizedBox(width: 8),
        _WindowControlIconButton(
          icon: isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
          size: isMaximized ? 18 : 22,
          isFlipped: isMaximized,
          tooltip: isMaximized ? '还原' : '最大化',
          onPressed: onMaximizeRestore,
        ),
        const SizedBox(width: 8),
        _WindowControlIconButton(
          icon: Icons.close_rounded,
          size: 22,
          tooltip: '关闭',
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _WindowControlIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final bool isFlipped;
  final String tooltip;
  final VoidCallback onPressed;

  const _WindowControlIconButton({
    required this.icon,
    this.size = 22,
    this.isFlipped = false,
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

  void _setHovered(bool value) {
    if (_isHovered == value) {
      return;
    }
    setState(() {
      _isHovered = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final double scale = _isPressed ? 0.92 : (_isHovered ? 1.1 : 1.0);
    final Color iconColor = _isHovered
        ? const Color(0xFFFF2E55)
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
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            child: iconWidget,
          ),
        ),
      ),
    );
  }
}
