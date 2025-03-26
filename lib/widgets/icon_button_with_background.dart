// lib/widgets/icon_button_with_background.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart'; // 引入必要的工具类

double iconSize = isMobile ?25:23.0; // 定义统一的图标大小
const double borderRadius = 7.0; // 圆角半径
const double borderSize = 47.0; // 按钮大小

class IconButtonWithBackground extends StatefulWidget {
  final String imagePath; // 本地图片路径
  final VoidCallback onPressed;

  const IconButtonWithBackground({
    super.key,
    required this.imagePath,
    required this.onPressed,
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
    if (isDarkModeValue) {
      imagePathToDisplay = _isPressed
          ? widget.imagePath
          : widget.imagePath.replaceFirst('.png', 'Light.png');
    } else {
      imagePathToDisplay = _isPressed
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
              color: _isPressed
                  ? (isDarkModeValue ? Colors.white : Colors.black)
                  : Colors.transparent,
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
                        width: iconSize,
                        height: iconSize,
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