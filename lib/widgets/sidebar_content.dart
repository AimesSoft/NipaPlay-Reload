import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/image_assets.dart';

class SidebarContent extends StatelessWidget {
  final double sizedboxTitle;
  final double titleSize;
  final String titleImagePath;
  final Function(String, String, bool, double) buildRow;
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
      if (!isMobile)
        buildRow('NipaPlay', titleImagePath, true, 10), // 在非移动设备上显示 NipaPlay
      if (!isMobile) const SizedBox(height: 10),
      buildRow('视频播放', ImageAssets.playVideo, false, 0), // 视频播放按钮
      if (!isMobile) const SizedBox(height: 10),
      buildRow('媒体库', ImageAssets.videoHistory, false, 1), // 媒体库按钮
      if (!isMobile) const SizedBox(height: 10),
      buildRow('设置', ImageAssets.settings, false, 2), // 设置按钮
      if (!isMobile) const Spacer(),
      if (!isMobile)
        Text(
          "v$Appversion    ",
          style: getVersionTextStyle(context),
        )
    ];

    return Align(
      alignment: isMobile
          ? Alignment.topCenter // 在移动设备上居中
          : const Alignment(-1, 0.0), // 在非移动设备上始终位于容器的左侧
      child: isMobile
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 自动分配间隔
              children: rowItems,
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.start, // 垂直排列时顶部对齐
              children: rowItems,
            ),
    );
  }
}
