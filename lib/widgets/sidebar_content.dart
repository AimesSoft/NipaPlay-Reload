import 'package:flutter/material.dart';
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
    return Align(
      alignment: const Alignment(-1, 0.0), // 使内容始终位于容器的左侧
      child: Column(
        children: [
          SizedBox(height: sizedboxTitle), // 使用动态间距
          buildRow('NipaPlay', titleImagePath, true), // NipaPlay 显示图片
          const SizedBox(height: 10),
          buildRow('视频播放', ImageAssets.playVideo, false), // 视频播放按钮
          const SizedBox(height: 10),
          buildRow('媒体库', ImageAssets.videoHistory, false), // 媒体库按钮
        ],
      ),
    );
  }
}