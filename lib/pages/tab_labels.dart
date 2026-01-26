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
  ];

  return tabs;
}

class HoverZoomTab extends StatefulWidget {
  final String text;
  final double fontSize;
  final Widget? icon;
  final Color? hoverColor;
  const HoverZoomTab({
    super.key,
    required this.text,
    this.fontSize = 20,
    this.icon,
    this.hoverColor,
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
    
    // 获取父级 TabBar 传递下来的样式（用于判断选中状态）
    final defaultStyle = DefaultTextStyle.of(context).style;
    final currentColor = defaultStyle.color ?? highlightColor;
    
    // 增加颜色比对的容差，确保在动画切换过程中也能正确识别选中状态
    final bool isSelected = (currentColor.r - activeColor.r).abs() < 0.1 && 
                            (currentColor.g - activeColor.g).abs() < 0.1 && 
                            (currentColor.b - activeColor.b).abs() < 0.1;

    // 1. 确定基础颜色（必须是不透明的，用于后续着色）
    Color solidColor = isSelected ? activeColor : highlightColor;
    
    // 如果设置了悬停颜色且当前处于悬停状态，应用悬停颜色
    if (_isHovered && widget.hoverColor != null && !isSelected) {
      solidColor = widget.hoverColor!;
    }

    // 2. 确定整体透明度
    // 选中或悬停时 100% 不透明，未选中默认状态跟随 TabBar 的 alpha (通常为 0.6 左右)
    final double targetOpacity = (isSelected || _isHovered) ? 1.0 : (currentColor.a < 1.0 ? currentColor.a : 0.6);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Opacity(
          opacity: targetOpacity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                // 关键修复：强制内部图标不透明
                // 这防止了 Icon 继承 TabBar 透明度后再被 ColorFiltered 二次淡化
                IconTheme(
                  data: const IconThemeData(
                    color: Colors.white,
                    opacity: 1.0,
                  ),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(solidColor, BlendMode.srcIn),
                    child: widget.icon!,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.text,
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: solidColor,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
