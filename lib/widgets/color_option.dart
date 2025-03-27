import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart';

double colorHoverd = 1.3;

class ColorOption extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  final bool isPressed; // 接受 isPressed 参数

  const ColorOption({
    super.key, 
    required this.color, 
    required this.onTap, 
    this.isPressed = false, // 默认值为 false
  });

  @override
  // ignore: library_private_types_in_public_api
  _ColorOptionState createState() => _ColorOptionState();
}

class _ColorOptionState extends State<ColorOption> {
  late Color _currentColor;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.color; // 初始颜色
  }

  // 函数：调整颜色明度
  Color _adjustBrightness(Color color, double factor) {
    final HSLColor hsl = HSLColor.fromColor(color);
    return hsl.withLightness(hsl.lightness * factor).toColor();
  }

  @override
  Widget build(BuildContext context) {
    isDarkModeValue = getCurrentThemeMode(context, modeSwitch);

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) {
            setState(() {
              _isHovered = true;
              _currentColor = _adjustBrightness(widget.color, colorHoverd); // 悬浮时提高明度
            });
          },
          onExit: (_) {
            setState(() {
              _isHovered = false;
              _currentColor = widget.color; // 恢复原颜色
            });
          },
          child: InkWell(
            onTap: widget.onTap,
            onHover: (_) {
              setState(() {
                _currentColor = _adjustBrightness(widget.color, colorHoverd); // 悬浮时提高明度
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200), // 设置动画持续时间
              curve: Curves.easeInOut, // 设置动画效果
              width: 30, // 正方形的宽度
              height: 30, // 正方形的高度
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: widget.isPressed ? widget.color.withOpacity(0.8) : _currentColor,
                borderRadius: BorderRadius.circular(7.0), // 圆角半径
                border: Border.all(
                  color: (_isHovered || widget.isPressed) 
                      ? (isDarkModeValue ? Colors.white : Colors.black)
                      : Colors.transparent,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
                ], // 添加阴影效果
              ),
            ),
          ),
        ),
      ),
    );
  }
}