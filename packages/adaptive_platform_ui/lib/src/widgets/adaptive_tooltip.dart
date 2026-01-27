import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// An adaptive tooltip that renders platform-specific tooltip styles
///
/// On iOS: Uses custom iOS-style tooltip with Cupertino design
/// On Android: Uses Material Design Tooltip
///
/// Example:
/// ```dart
/// AdaptiveTooltip(
///   message: 'This is a tooltip',
///   child: Icon(Icons.info),
/// )
/// ```
class AdaptiveTooltip extends StatelessWidget {
  /// Creates an adaptive tooltip
  const AdaptiveTooltip({
    super.key,
    required this.message,
    this.preferBelow = true,
    this.verticalOffset,
    this.padding,
    this.margin,
    this.height,
    this.decoration,
    this.textStyle,
    this.waitDuration,
    this.showDuration,
    required this.child,
  });

  /// The text to display in the tooltip
  final String message;

  /// Whether the tooltip defaults to being displayed below the widget
  ///
  /// Defaults to true. If there isn't enough space to display the tooltip in
  /// the preferred direction, the tooltip will be displayed in the opposite
  /// direction.
  final bool preferBelow;

  /// The vertical gap between the widget and the displayed tooltip
  final double? verticalOffset;

  /// The amount of space by which to inset the tooltip's child
  final EdgeInsetsGeometry? padding;

  /// The empty space that surrounds the tooltip
  final EdgeInsetsGeometry? margin;

  /// The height of the tooltip's child
  final double? height;

  /// The decoration for the tooltip
  final Decoration? decoration;

  /// The style to use for the text in the tooltip
  final TextStyle? textStyle;

  /// The duration that must elapse before the tooltip appears
  final Duration? waitDuration;

  /// The duration that the tooltip will be shown after long press is released
  final Duration? showDuration;

  /// The widget below this widget in the tree
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // iOS - Use custom iOS-style tooltip
    if (PlatformInfo.isIOS) {
      return _IOSTooltip(
        message: message,
        preferBelow: preferBelow,
        verticalOffset: verticalOffset,
        padding: padding,
        margin: margin,
        height: height,
        decoration: decoration,
        textStyle: textStyle,
        waitDuration: waitDuration,
        showDuration: showDuration,
        child: child,
      );
    }

    // Android and fallback - Use Material Design Tooltip
    return Tooltip(
      message: message,
      preferBelow: preferBelow,
      verticalOffset: verticalOffset,
      padding: padding,
      margin: margin,
      constraints: height != null
          ? BoxConstraints(minHeight: height!, maxHeight: height!)
          : null,
      decoration: decoration,
      textStyle: textStyle,
      waitDuration: waitDuration,
      showDuration: showDuration,
      child: child,
    );
  }
}

/// iOS-style tooltip widget
class _IOSTooltip extends StatefulWidget {
  const _IOSTooltip({
    required this.message,
    required this.preferBelow,
    required this.verticalOffset,
    required this.padding,
    required this.margin,
    required this.height,
    required this.decoration,
    required this.textStyle,
    required this.waitDuration,
    required this.showDuration,
    required this.child,
  });

  final String message;
  final bool preferBelow;
  final double? verticalOffset;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? height;
  final Decoration? decoration;
  final TextStyle? textStyle;
  final Duration? waitDuration;
  final Duration? showDuration;
  final Widget child;

  @override
  State<_IOSTooltip> createState() => _IOSTooltipState();
}

class _IOSTooltipState extends State<_IOSTooltip> {
  final GlobalKey _key = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isVisible = false;

  @override
  void dispose() {
    _removeTooltip();
    super.dispose();
  }

  void _showTooltip() {
    if (_isVisible) return;

    final overlay = Overlay.of(context);
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _TooltipOverlay(
        message: widget.message,
        position: position,
        size: size,
        preferBelow: widget.preferBelow,
        verticalOffset: widget.verticalOffset ?? 24,
        padding:
            widget.padding ??
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 16),
        height: widget.height,
        decoration: widget.decoration,
        textStyle: widget.textStyle,
      ),
    );

    overlay.insert(_overlayEntry!);
    _isVisible = true;

    // Auto-hide tooltip after duration
    final showDuration = widget.showDuration ?? const Duration(seconds: 2);
    Future.delayed(showDuration, _removeTooltip);
  }

  void _removeTooltip() {
    if (!_isVisible) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      onLongPress: _showTooltip,
      onTap: _showTooltip,
      child: widget.child,
    );
  }
}

class _TooltipOverlay extends StatefulWidget {
  const _TooltipOverlay({
    required this.message,
    required this.position,
    required this.size,
    required this.preferBelow,
    required this.verticalOffset,
    required this.padding,
    required this.margin,
    required this.height,
    required this.decoration,
    required this.textStyle,
  });

  final String message;
  final Offset position;
  final Size size;
  final bool preferBelow;
  final double verticalOffset;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? height;
  final Decoration? decoration;
  final TextStyle? textStyle;

  @override
  State<_TooltipOverlay> createState() => _TooltipOverlayState();
}

class _TooltipOverlayState extends State<_TooltipOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    // Calculate tooltip position
    final screenSize = MediaQuery.sizeOf(context);

    double top;
    if (widget.preferBelow) {
      top = widget.position.dy + widget.size.height + widget.verticalOffset;
    } else {
      top =
          widget.position.dy - widget.verticalOffset - 40; // Approximate height
    }

    // Default iOS tooltip style
    final defaultDecoration = BoxDecoration(
      color: isDark
          ? CupertinoColors.systemGrey.darkColor
          : CupertinoColors.systemGrey,
      borderRadius: BorderRadius.circular(8),
    );

    final defaultTextStyle = TextStyle(
      color: CupertinoColors.white,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        return Positioned(
          top: top,
          left: 0,
          right: 0,
          child: Opacity(opacity: _opacity.value, child: child!),
        );
      },
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: screenSize.width - 32),
          margin: widget.margin,
          height: widget.height,
          padding: widget.padding,
          decoration: widget.decoration ?? defaultDecoration,
          child: Text(
            widget.message,
            style: widget.textStyle ?? defaultTextStyle,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
