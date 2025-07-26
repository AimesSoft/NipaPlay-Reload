import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'tooltip_bubble.dart';
import '../utils/shortcut_tooltip_manager.dart'; // 使用新的快捷键提示管理器

class SendDanmakuButton extends StatefulWidget {
  final VoidCallback onPressed;

  const SendDanmakuButton({
    super.key,
    required this.onPressed,
  });

  @override
  State<SendDanmakuButton> createState() => _SendDanmakuButtonState();
}

class _SendDanmakuButtonState extends State<SendDanmakuButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // 获取快捷键文本
    final tooltipManager = ShortcutTooltipManager();
    final shortcutText = tooltipManager.getShortcutText('send_danmaku');
    final tooltipText = shortcutText.isEmpty ? '发送弹幕' : '发送弹幕 ($shortcutText)';
    debugPrint('[SendDanmakuButton] 快捷键文本: $shortcutText, 提示文本: $tooltipText');
    
    return MouseRegion(
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
            blur: 30,
            alignment: Alignment.center,
            border: 1,
            linearGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFffffff).withOpacity(0.2),
                const Color(0xFFFFFFFF).withOpacity(0.2),
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