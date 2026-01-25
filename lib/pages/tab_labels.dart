// tab_labels.dart
import 'package:flutter/material.dart';

List<Widget> createTabLabels() {
  List<Widget> tabs = [
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: HoverZoomTab(text: "主页"),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: HoverZoomTab(text: "视频播放"),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: HoverZoomTab(text: "媒体库"),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: HoverZoomTab(text: "个人中心"),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: HoverZoomTab(text: "设置"),
    ),
  ];

  return tabs;
}

class HoverZoomTab extends StatefulWidget {
  final String text;
  final double fontSize;
  final Widget? icon;
  const HoverZoomTab({
    super.key,
    required this.text,
    this.fontSize = 20,
    this.icon,
  });

  @override
  State<HoverZoomTab> createState() => _HoverZoomTabState();
}

class _HoverZoomTabState extends State<HoverZoomTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final highlightColor = isDarkMode ? Colors.white : Colors.black;
    const activeColor = Color(0xFFFF2E55);
    
    // 获取父级 TabBar 传递下来的样式
    final defaultStyle = DefaultTextStyle.of(context).style;
    final currentColor = defaultStyle.color ?? highlightColor;
    
    // 判断是否被选中：如果颜色是品牌红（或接近），则视为选中状态
    final bool isSelected = currentColor.value == activeColor.value;

    // 确定最终颜色：
    // 1. 如果选中 -> 始终红色（悬停不改变颜色）
    // 2. 如果未选中且悬停 -> 变成高亮色（白/黑）
    // 3. 否则 -> 使用当前默认颜色
    final displayColor = isSelected 
        ? activeColor 
        : (_isHovered ? highlightColor : currentColor);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              // 使用 ColorFiltered 强制让任何图标（Icon/Image/Svg）跟随文字颜色
              ColorFiltered(
                colorFilter: ColorFilter.mode(displayColor, BlendMode.srcIn),
                child: widget.icon!,
              ),
              const SizedBox(width: 6),
            ],
            AnimatedDefaultTextStyle(
              style: defaultStyle.copyWith(
                color: displayColor,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.bold,
              ),
              duration: const Duration(milliseconds: 200),
              child: Text(widget.text, locale: const Locale("zh-Hans", "zh")),
            ),
          ],
        ),
      ),
    );
  }
}
