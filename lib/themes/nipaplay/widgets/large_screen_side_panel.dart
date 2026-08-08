import 'package:flutter/material.dart';

class NipaplayLargeScreenSidePanel extends StatelessWidget {
  const NipaplayLargeScreenSidePanel({
    super.key,
    required this.isDarkMode,
    required this.child,
    this.width = 220,
  });

  final bool isDarkMode;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: isDarkMode ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
      ),
      child: child,
    );
  }
}

class NipaplayLargeScreenSidePanelItem extends StatefulWidget {
  const NipaplayLargeScreenSidePanelItem({
    super.key,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
    required this.child,
    this.isFocused = false,
  });

  /// 当前页是否选中（焦点可能在内容区）。
  final bool isSelected;

  /// 焦点是否在此菜单项上（菜单列激活且此项是焦点项）。
  /// 与 [isSelected] 区分：isFocused=true 时背景更亮（0.92 alpha），
  /// isSelected=true 但 isFocused=false 时背景较暗（0.5 alpha），
  /// 用于提示用户焦点在菜单列还是在内容区。
  final bool isFocused;

  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<NipaplayLargeScreenSidePanelItem> createState() =>
      _NipaplayLargeScreenSidePanelItemState();
}

class _NipaplayLargeScreenSidePanelItemState
    extends State<NipaplayLargeScreenSidePanelItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isInteractiveActive = _isHovered || _isPressed;
    final bool isFocused = widget.isFocused || isInteractiveActive;
    final bool isSelected = widget.isSelected;
    final bool isActive = isSelected || isFocused;
    final Color itemColor = isActive ? Colors.white : widget.inactiveColor;

    // 三种视觉态：
    // - 焦点在此项（菜单列激活）：activeColor @ 0.92
    // - 选中但焦点在内容区：activeColor @ 0.5
    // - 既未选中也未聚焦：透明
    final Color backgroundColor;
    if (isFocused) {
      backgroundColor = widget.activeColor.withValues(alpha: 0.92);
    } else if (isSelected) {
      backgroundColor = widget.activeColor.withValues(alpha: 0.5);
    } else {
      backgroundColor = Colors.transparent;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.zero,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: widget.onTap,
        onHover: _setHovered,
        onHighlightChanged: _setPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border(
              left: BorderSide(
                color: isActive ? widget.activeColor : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: itemColor),
            child: IconTheme.merge(
              data: IconThemeData(color: itemColor),
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
