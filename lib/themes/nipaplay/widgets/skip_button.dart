import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'tooltip_bubble.dart';
import 'package:nipaplay/utils/shortcut_tooltip_manager.dart';
import 'control_shadow.dart';

class SkipButton extends StatefulWidget {
  final VoidCallback onPressed;

  const SkipButton({
    super.key,
    required this.onPressed,
  });

  @override
  State<SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<SkipButton> 
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  bool _isHovered = false;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tooltipManager = ShortcutTooltipManager();
    final shortcutText = tooltipManager.getShortcutText('skip');
    final tooltipText = shortcutText.isEmpty ? '跳过' : '跳过 ($shortcutText)';
    
    return SlideTransition(
      position: _slideAnimation,
      child: TooltipBubble(
        text: tooltipText,
        showOnRight: false,
        verticalOffset: 8,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) {
              setState(() => _isPressed = false);
              widget.onPressed();
            },
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: _isPressed ? 0.9 : (_isHovered ? 1.1 : 1.0),
              child: ControlIconShadow(
                child: const Icon(
                  Ionicons.play_skip_forward_outline,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
