import 'package:flutter/material.dart';

/// 统一的媒体库操作按钮：悬停时图标放大并变色为 #ff2e55
class SearchBarActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;
  final Color? color;

  const SearchBarActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 20,
    this.tooltip,
    this.color,
  });

  @override
  State<SearchBarActionButton> createState() => _SearchBarActionButtonState();
}

class _SearchBarActionButtonState extends State<SearchBarActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isEnabled = widget.onPressed != null;
    
    // 默认颜色：深色模式白色透明度，浅色模式黑色透明度
    Color idleColor = widget.color ?? 
        (isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6));
    
    if (!isEnabled) {
      idleColor = idleColor.withValues(alpha: 0.3);
    }
    
    const activeColor = Color(0xFFFF2E55);

    Widget result = MouseRegion(
      onEnter: (_) => isEnabled ? setState(() => _isHovered = true) : null,
      onExit: (_) => isEnabled ? setState(() => _isHovered = false) : null,
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _isHovered ? 1.25 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Icon(
            widget.icon,
            size: widget.size,
            color: _isHovered ? activeColor : idleColor,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(
        message: widget.tooltip!,
        child: result,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: result,
    );
  }
}
