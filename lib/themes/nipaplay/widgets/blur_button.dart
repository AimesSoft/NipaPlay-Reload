import 'package:flutter/material.dart';
import 'dart:ui';

import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

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
  final bool flatStyle;
  final double hoverScale;
  final Color? foregroundColor;
  final Color? hoverForegroundColor;

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
    this.flatStyle = false,
    this.hoverScale = 1.0,
    this.foregroundColor,
    this.hoverForegroundColor,
  });

  @override
  State<BlurButton> createState() => _BlurButtonState();
}

class _BlurButtonState extends State<BlurButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final blurValue = appearanceSettings.enableWidgetBlurEffect ? 25.0 : 0.0;
    final theme = Theme.of(context);
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(8);
    final baseForegroundColor = widget.foregroundColor ??
        (widget.flatStyle
            ? theme.colorScheme.onSurface
            : Colors.white.withOpacity(0.8));
    final hoverForegroundColor = widget.hoverForegroundColor ??
        (widget.flatStyle ? const Color(0xFFFF2E55) : Colors.white);
    final effectiveForegroundColor =
        _isHovered ? hoverForegroundColor : baseForegroundColor;

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
      child: _buildButtonBody(
        blurValue: blurValue,
        borderRadius: borderRadius,
        effectiveForegroundColor: effectiveForegroundColor,
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

  Widget _buildButtonBody({
    required double blurValue,
    required BorderRadius borderRadius,
    required Color effectiveForegroundColor,
  }) {
    final row = Row(
      mainAxisSize:
          widget.expandHorizontally ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: widget.expandHorizontally
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (widget.icon != null) ...[
          Icon(
            widget.icon,
            size: _isHovered ? widget.iconSize + 1 : widget.iconSize,
            color: effectiveForegroundColor,
          ),
          const SizedBox(width: 4),
        ],
        Text(widget.text),
      ],
    );

    final content = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      style: TextStyle(
        color: effectiveForegroundColor,
        fontSize: widget.fontSize,
        fontWeight: _isHovered ? FontWeight.w500 : FontWeight.normal,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: borderRadius,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Padding(
            padding: widget.padding,
            child: AnimatedScale(
              scale: _isHovered ? widget.hoverScale : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: row,
            ),
          ),
        ),
      ),
    );

    if (widget.flatStyle) {
      if (widget.width == null) {
        return content;
      }
      return SizedBox(width: widget.width, child: content);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: widget.width,
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withOpacity(0.4)
                : Colors.white.withOpacity(0.18),
            borderRadius: borderRadius,
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
          child: content,
        ),
      ),
    );
  }
}
