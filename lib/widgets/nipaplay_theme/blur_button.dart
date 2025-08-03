import 'package:flutter/material.dart';
import 'dart:ui';

class BlurButton extends StatefulWidget {
  final IconData? icon;
  final String text;
  final VoidCallback onTap;
  final double iconSize;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? width;
  final bool expandHorizontally;
  final BorderRadius? borderRadius;
  
  const BlurButton({
    super.key,
    this.icon,
    required this.text,
    required this.onTap,
    this.iconSize = 16,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.margin = EdgeInsets.zero,
    this.width,
    this.expandHorizontally = false,
    this.borderRadius,
  });

  @override
  State<BlurButton> createState() => _BlurButtonState();
}

class _BlurButtonState extends State<BlurButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Widget buttonContent = MouseRegion(
      onEnter: (_) {
        setState(() {
          _isHovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _isHovered = false;
        });
      },
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: widget.padding,
            width: widget.width,
            decoration: BoxDecoration(
              color: _isHovered 
                ? Colors.white.withOpacity(0.4) 
                : Colors.white.withOpacity(0.18),
              borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
              border: Border.all(
                color: _isHovered 
                  ? Colors.white.withOpacity(0.7) 
                  : Colors.white.withOpacity(0.25),
                width: _isHovered ? 1.0 : 0.5,
              ),
              boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.25),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : [],
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                color: _isHovered
                  ? Colors.white 
                  : Colors.white.withOpacity(0.8),
                fontSize: widget.fontSize,
                fontWeight: _isHovered ? FontWeight.w500 : FontWeight.normal,
              ),
              child: InkWell(
                onTap: widget.onTap,
                child: Row(
                  mainAxisSize: widget.expandHorizontally ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: widget.expandHorizontally ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    if (widget.icon != null) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          widget.icon,
                          size: _isHovered ? widget.iconSize + 1 : widget.iconSize,
                          color: _isHovered
                            ? Colors.white 
                            : Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(widget.text),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 如果需要扩展填满容器宽度
    if (widget.expandHorizontally && widget.width == null) {
      buttonContent = SizedBox(
        width: double.infinity,
        child: buttonContent,
      );
    }

    return Padding(
      padding: widget.margin,
      child: buttonContent,
    );
  }
} 