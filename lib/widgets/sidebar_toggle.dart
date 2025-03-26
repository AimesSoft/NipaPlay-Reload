import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/utils/theme_utils.dart';
// 导入 MouseCursor

class SidebarToggle extends StatefulWidget { // 修改为 StatefulWidget
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SidebarToggle({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  State<SidebarToggle> createState() => _SidebarToggleState();
}

class _SidebarToggleState extends State<SidebarToggle> {

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 0.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.title,
            style: getToggleTextStyle(context),
          ),
          const SizedBox(width: 10),
          MouseRegion( // 使用 MouseRegion 包裹 GestureDetector
            cursor: SystemMouseCursors.click, // 设置鼠标光标
            child: GestureDetector(
              onTap: () => widget.onChanged(!widget.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100), // 动画时间改为 100 毫秒
                width: 40,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: widget.value ? getWBColor() : getSwitchCloseColor(),
                  boxShadow: [
                    BoxShadow(
                      // ignore: deprecated_member_use
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 6.0,
                      spreadRadius: 2.0,
                    ),
                  ],
                ),
                alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: getBackgroundColor(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}