import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'tooltip_bubble.dart';

class LockControlsButton extends StatefulWidget {
  final bool locked;
  final VoidCallback onPressed;

  const LockControlsButton({
    super.key,
    required this.locked,
    required this.onPressed,
  });

  @override
  State<LockControlsButton> createState() => _LockControlsButtonState();
}

class _LockControlsButtonState extends State<LockControlsButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;

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
    final tooltipText = widget.locked ? '解锁' : '锁定';
    final iconData =
        widget.locked ? Ionicons.lock_closed_outline : Ionicons.lock_open_outline;

    return SlideTransition(
      position: _slideAnimation,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: TooltipBubble(
          text: tooltipText,
          showOnRight: true,
          verticalOffset: 8,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) {
              setState(() => _isPressed = false);
              widget.onPressed();
            },
            onTapCancel: () => setState(() => _isPressed = false),
            child: GlassmorphicContainer(
              width: 48,
              height: 48,
              borderRadius: 25,
              blur: context
                      .watch<AppearanceSettingsProvider>()
                      .enableWidgetBlurEffect
                  ? 25
                  : 0,
              alignment: Alignment.center,
              border: 1,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFffffff).withOpacity(0.1),
                  const Color(0xFFFFFFFF).withOpacity(0.1),
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFffffff).withOpacity(0.5),
                  const Color((0xFFFFFFFF)).withOpacity(0.5),
                ],
              ),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isHovered ? 1.0 : 0.6,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 100),
                  scale: _isPressed ? 0.9 : 1.0,
                  child: Icon(
                    iconData,
                    color: Colors.white,
                    size: 28,
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

