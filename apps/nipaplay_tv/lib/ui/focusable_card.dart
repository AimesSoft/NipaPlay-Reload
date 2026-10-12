import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV 焦点卡片原语：D-pad 聚焦时放大 + 描边光环，确认键触发 [onActivate]。
///
/// 这是 TV 版自有 UI（阶段三新建），焦点逻辑按规划保留在各版本，不进 ui_common。
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.onActivate,
    this.autofocus = false,
    this.borderRadius = 16,
    this.accentColor = const Color(0xFF26C6DA),
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    required this.child,
  });

  final VoidCallback onActivate;
  final bool autofocus;
  final double borderRadius;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (node, event) {
        final isActivate = event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA);
        if (isActivate) {
          widget.onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _focused ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: _focused
                ? widget.accentColor.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: radius,
            border: Border.all(
              color: _focused ? widget.accentColor : Colors.white24,
              width: _focused ? 2.5 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.35),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: _focused ? Colors.white : Colors.white70,
            ),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
