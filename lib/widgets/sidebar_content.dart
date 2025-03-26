import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/widgets/image_assets.dart';

class SidebarContent extends StatelessWidget {
  final double sizedboxTitle;
  final double titleSize;
  final String titleImagePath;
  final Function(String, String, bool) buildRow;
  final bool isDarkModeValue;

  const SidebarContent({
    super.key,
    required this.sizedboxTitle,
    required this.titleSize,
    required this.titleImagePath,
    required this.buildRow,
    required this.isDarkModeValue,
  });

  @override
  Widget build(BuildContext context) {

    // 图标和文字项列表
    List<Widget> rowItems = [
      if (!isMobile) SizedBox(height: sizedboxTitle),
      if (!isMobile) buildRow('NipaPlay', titleImagePath, true), // 在非移动设备上显示 NipaPlay
      buildRow('视频播放', ImageAssets.playVideo, false), // 视频播放按钮
      const SizedBox(width: 10),  // 横向间距
      buildRow('媒体库', ImageAssets.videoHistory, false), // 媒体库按钮
    ];

    return Align(
      alignment: isMobile? Alignment.topCenter : const Alignment(-1, 0.0), // 使内容始终位于容器的左侧
      child: isMobile
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,  // 水平居中
              children: rowItems,
            )
          : Column(
              children: rowItems,
            ),
    );
  }
}