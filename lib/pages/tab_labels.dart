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
      child: HoverZoomTab(text: "设置"),
    ),
  ];

  return tabs;
}

class HoverZoomTab extends StatefulWidget {
  final String text;
  final double fontSize;
  const HoverZoomTab({
    super.key,
    required this.text,
    this.fontSize = 20,
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
    // 获取父级 TabBar 传递下来的样式（包含了选中/未选中颜色动画）
    final defaultStyle = DefaultTextStyle.of(context).style;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedDefaultTextStyle(
          style: defaultStyle.copyWith(
            color: _isHovered ? highlightColor : defaultStyle.color,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
          ),
          duration: const Duration(milliseconds: 200),
          child: Text(widget.text, locale: const Locale("zh-Hans", "zh")),
        ),
      ),
    );
  }
}