import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'tooltip_bubble.dart';
import 'package:nipaplay/utils/shortcut_tooltip_manager.dart'; // 使用新的快捷键提示管理器
import 'control_shadow.dart';

class SendDanmakuButton extends StatefulWidget {
  final VoidCallback onPressed;

  const SendDanmakuButton({
    super.key,
    required this.onPressed,
  });

  @override
  State<SendDanmakuButton> createState() => _SendDanmakuButtonState();
}

class _SendDanmakuButtonState extends State<SendDanmakuButton> 
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
      begin: const Offset(1.0, 0.0), // 从右侧滑入
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    // 启动进入动画
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取快捷键文本
    final tooltipManager = ShortcutTooltipManager();
    final shortcutText = tooltipManager.getShortcutText('send_danmaku');
    final tooltipText = shortcutText.isEmpty ? '发送弹幕' : '发送弹幕 ($shortcutText)';
    //debugPrint('[SendDanmakuButton] 快捷键文本: $shortcutText, 提示文本: $tooltipText');
    
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
                  Ionicons.chatbubble_ellipses_outline,
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
