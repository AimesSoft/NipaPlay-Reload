// lib/widgets/icon_button_with_background.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart'; // 引入必要的工具类

const double borderRadius = 7.0; // 圆角半径
const double borderSize = 47.0; // 按钮大小

class IconButtonWithBackground extends StatefulWidget {
  final String imagePath; // 本地图片路径
  final VoidCallback onPressed;
  final bool isSelected; // 传递按钮是否被选中的状态

  const IconButtonWithBackground({
    super.key,
    required this.imagePath,
    required this.onPressed, 
    required this.isSelected, // 传递 isSelected 状态
  });

  @override
  // ignore: library_private_types_in_public_api
  _IconButtonWithBackgroundState createState() =>
      _IconButtonWithBackgroundState();
}

class _IconButtonWithBackgroundState extends State<IconButtonWithBackground>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false; // 是否按下

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
    String imagePathToDisplay = widget.imagePath;

    // 判断暗黑模式下按下和选中时的图片变化
    if (isDarkModeValue) {
      imagePathToDisplay = widget.isSelected || _isPressed
          ? widget.imagePath
          : widget.imagePath.replaceFirst('.png', 'Light.png');
    } else {
      imagePathToDisplay = widget.isSelected || _isPressed
          ? widget.imagePath.replaceFirst('.png', 'Light.png')
          : widget.imagePath;
    }

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) {
          setState(() {
            _isPressed = true;
            _animationController.forward();
          });
        },
        onTapUp: (_) {
          setState(() {
            _isPressed = false;
            _animationController.reverse();
          });
        },
        onTapCancel: () {
          setState(() {
            _isPressed = false;
            _animationController.reverse();
          });
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() {
              _animationController.forward();
            });
          },
          onExit: (_) {
            setState(() {
              _animationController.reverse();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: borderSize,
            height: borderSize,
            decoration: BoxDecoration(
              color: widget.isSelected // 判断按钮是否被选中
                  ? (isDarkModeValue ? Colors.white : Colors.black)
                  : (_isPressed
                      ? (isDarkModeValue ? Colors.white : Colors.black)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: Image.asset(
                        imagePathToDisplay,
                        key: ValueKey<bool>(_isPressed),
                        width: isMobile ? 25 : 23.0,
                        height: isMobile ? 25 : 23.0,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}