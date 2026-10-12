import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV 焦点卡片原语：D-pad 聚焦时放大 + 描边光环，确认键触发 [onActivate]。
///
/// 三种视觉状态（互不覆盖）：
/// - **焦点态**：D-pad/悬停当前所在项，放大 + 光环；
/// - **选中态**（[selected]）：当前所在页面/选项，常驻描边与淡色底，不随焦点移动而消失；
/// - **默认态**：其余项。
///
/// 输入方式（三通道，缺一不可）：
/// - 遥控/手柄 D-pad：方向键移动焦点，确认键（select/enter/space/gameButtonA）激活；
/// - 触屏/鼠标：直接点按激活（手机测试必需）；
/// - 鼠标悬停：指针进入即高亮。
///
/// 这是 TV 版自有 UI（阶段三新建），焦点逻辑按规划保留在各版本，不进 ui_common。
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.onActivate,
    this.autofocus = false,
    this.selected = false,
    this.focusNode,
    this.onFocused,
    this.borderRadius = 16,
    this.accentColor = const Color(0xFF26C6DA),
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    required this.child,
  });

  final VoidCallback onActivate;
  final bool autofocus;

  /// 外部焦点节点：供壳/页面在切换时主动把焦点交给本卡片。
  final FocusNode? focusNode;

  /// 获得焦点时的回调（壳用它记录当前导航项，供返回键回退）。
  final VoidCallback? onFocused;

  /// 是否为"当前选中项"：常驻描边+淡色底，与焦点态叠加显示。
  final bool selected;
  final double borderRadius;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _focused = false;
  bool _hovered = false;

  bool get _highlighted => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final accent = widget.accentColor;
    // 焦点态最强，其次选中态，最后默认态。
    final Color fill;
    final Color borderColor;
    final double borderWidth;
    final List<BoxShadow> shadow;
    if (_highlighted) {
      fill = accent.withValues(alpha: 0.16);
      borderColor = accent;
      borderWidth = 2.5;
      shadow = [
        BoxShadow(
          color: accent.withValues(alpha: 0.35),
          blurRadius: 22,
          spreadRadius: 1,
        ),
      ];
    } else if (widget.selected) {
      fill = accent.withValues(alpha: 0.10);
      borderColor = accent.withValues(alpha: 0.85);
      borderWidth = 2;
      shadow = const [];
    } else {
      fill = Colors.white.withValues(alpha: 0.05);
      borderColor = Colors.white24;
      borderWidth = 1;
      shadow = const [];
    }
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) {
        setState(() => _focused = v);
        if (v) widget.onFocused?.call();
      },
      onKeyEvent: (node, event) {
        final isActivate = event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA);
        if (isActivate) {
          widget.onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onActivate,
          child: AnimatedScale(
            scale: _highlighted ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: Border.all(color: borderColor, width: borderWidth),
                boxShadow: shadow,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: (_highlighted || widget.selected)
                      ? Colors.white
                      : Colors.white70,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.normal,
                ),
                child: Padding(padding: widget.padding, child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
