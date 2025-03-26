import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/utils/theme_helper.dart';

class RoundedButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isSelected;  // 新增 isSelected 参数，用来表示按钮是否被选中
  final double? fontSize;  // 可选参数 fontSize
  final double? verticalPadding;  // 可选参数 verticalPadding
  final double? horizontalPadding;  // 可选参数 horizontalPadding

  const RoundedButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isSelected = false, // 默认值为 false，表示按钮未选中
    this.fontSize = 14.0,    // 默认字体大小为 14.0
    this.verticalPadding = 3.0,  // 默认上下内边距为 3.0
    this.horizontalPadding = 10.0, // 默认左右内边距为 10.0
  });

  @override
  // ignore: library_private_types_in_public_api
  _RoundedButtonState createState() => _RoundedButtonState();
}

class _RoundedButtonState extends State<RoundedButton> {
  bool _isHovered = false; // 用来检测是否悬浮
  bool _isPressed = false; // 用来检测是否被按下

  @override
  Widget build(BuildContext context) {
    // 获取当前主题模式（夜间模式或日间模式）
    isDarkModeValue = getCurrentThemeMode(context, modeSwitch);

    // 按钮背景颜色：悬浮时使用白色或黑色，默认时使用深灰色（夜间模式下）
    Color buttonColor = widget.isSelected
        ? (isDarkModeValue ? Colors.white : Colors.black) // 被选中时按钮颜色
        : _isHovered || _isPressed
            ? (isDarkModeValue ? Colors.white : Colors.black) // 悬浮或按下时按钮颜色
            : getButtonColor(); // 默认按钮颜色，浅灰色

    // 悬浮时的文字颜色
    Color textColor = widget.isSelected
        ? (isDarkModeValue ? Colors.black : Colors.white) // 被选中时文字颜色
        : _isHovered || _isPressed
            ? (isDarkModeValue ? Colors.black : Colors.white) // 悬浮或按下时文字颜色
            : (isDarkModeValue ? const Color.fromARGB(255, 202, 202, 202) : const Color.fromARGB(255, 54, 54, 54)); // 默认文字颜色

    // 始终显示阴影
    BoxShadow boxShadow = BoxShadow(
      // ignore: deprecated_member_use
      color: Colors.black.withOpacity(0.15), // 阴影颜色
      blurRadius: 6.0, // 模糊半径
      spreadRadius: 2.0,
    );

    // 设置边框：悬浮、按下和选中时都不显示描边
    Border border = widget.isSelected || _isHovered || _isPressed
        ? Border.all(color: Colors.transparent, width: 0.5) // 不显示边框
        : Border.all(
            color: getButtonLineColor(), // 使用 getButtonLineColor 获取描边颜色
            width: 0.5, // 1像素描边
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0), // 给按钮添加上下外边距
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) {
          setState(() {
            _isPressed = true; // 按下时改变状态
          });
        },
        onTapUp: (_) {
          setState(() {
            _isPressed = false; // 松开时恢复状态
          });
        },
        onTapCancel: () {
          setState(() {
            _isPressed = false; // 取消时恢复状态
          });
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() {
              _isHovered = true; // 悬浮时改变状态
            });
          },
          onExit: (_) {
            setState(() {
              _isHovered = false; // 离开时恢复状态
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200), // 按钮颜色过渡动画时间
            padding: EdgeInsets.symmetric(
              vertical: widget.verticalPadding ?? 3.0,  // 使用传入的 verticalPadding 或默认 3.0
              horizontal: widget.horizontalPadding ?? 10.0, // 使用传入的 horizontalPadding 或默认 10.0
            ), // 文字上下内边距
            decoration: BoxDecoration(
              color: buttonColor,
              borderRadius: BorderRadius.circular(7),
              boxShadow: [boxShadow], // 始终应用阴影效果
              border: border, // 动态设置边框
            ),
            child: Center(
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: widget.fontSize ?? 14.0, // 使用传入的 fontSize 或默认 14.0
                  color: textColor, // 动态设置文字颜色
                  fontWeight: FontWeight.normal, // 不加粗
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}