import 'package:flutter/material.dart';

class BounceHoverScale extends StatefulWidget {
  final Widget child;
  final bool isHovered;
  final bool isPressed;
  final Duration duration;
  final Curve curve;

  const BounceHoverScale({
    super.key,
    required this.child,
    required this.isHovered,
    required this.isPressed,
    this.duration = const Duration(milliseconds: 150),
    this.curve = Curves.easeOutBack,
  });

  @override
  State<BounceHoverScale> createState() => _BounceHoverScaleState();
}

class _BounceHoverScaleState extends State<BounceHoverScale> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(BounceHoverScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHovered != oldWidget.isHovered) {
      if (widget.isHovered) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedScale(
        scale: widget.isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
} 