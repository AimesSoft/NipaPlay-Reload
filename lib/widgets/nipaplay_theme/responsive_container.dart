// widgets/responsive_container.dart
// ignore_for_file: sized_box_for_whitespace

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final Widget currentPage; // 接收当前显示的页面

  const ResponsiveContainer({super.key, required this.child, required this.currentPage});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 如果是桌面设备或平板设备，使用左右分区布局；手机设备使用单页布局
        if (globals.isDesktop || globals.isTablet) {
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
        } else {
          // 手机设备使用单页布局
          return child;
        }
      },
    );
  }
}