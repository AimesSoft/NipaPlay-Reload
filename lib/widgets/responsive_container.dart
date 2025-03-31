// widgets/responsive_container.dart
// ignore_for_file: sized_box_for_whitespace

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
// 导入新的 AboutPage

class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final Widget currentPage; // 接收当前显示的页面

  const ResponsiveContainer({super.key, required this.child, required this.currentPage});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 如果是移动设备，则直接显示 currentPage，不显示 child
        if (!isDesktop) {
          return child; // 只返回 currentPage
        } else {
          return Row(
            children: [
              // 左侧部分，显示 SettingsPage
              Container(
                width: constraints.maxWidth / 2,
                child: child,
              ),
              const VerticalDivider(
                color: Color.fromARGB(59, 255, 255, 255), // 竖线的颜色
                thickness: 1, // 竖线的宽度
                width: 0, // 竖线的间距
                indent: 20,
                endIndent: 20,
              ),
              // 右侧部分，根据 currentPage 显示不同内容
              Container(
                width: constraints.maxWidth / 2,
                child: currentPage,  // 显示传递过来的页面
              ),
            ],
          );
        }
      },
    );
  }
}