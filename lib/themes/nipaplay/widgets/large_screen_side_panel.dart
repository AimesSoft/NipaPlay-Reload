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
  });

  final bool isSelected;
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
    final bool isActive = widget.isSelected || isInteractiveActive;
    final Color itemColor = isActive ? Colors.white : widget.inactiveColor;

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
            color: isActive ? widget.activeColor : Colors.transparent,
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
