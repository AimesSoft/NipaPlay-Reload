import 'package:flutter/material.dart';

class AnimePage extends StatelessWidget {
  // 扩展列表，测试滚动条效果
  final List<String> episodeImages = [
    'assets/images/recent1.png',
    'assets/images/recent2.png',
    'assets/images/anime1.png',
    'assets/images/anime2.png',
    'assets/images/recent1.png',
    'assets/images/recent2.png',
    'assets/images/anime1.png',
    'assets/images/anime2.png',
  ];

  AnimePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 24),  // 添加上方间距，避免置顶
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text("观看记录", style: TextStyle(fontSize: 28, color: Colors.white,fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          // 使用SingleChildScrollView包装Wrap以使其支持横向滚动
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, // 设置水平滚动
              child: Row(
                children: episodeImages.map((imgPath) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        imgPath,
                        width: 100, // 缩小图标大小
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text("媒体库", style: TextStyle(fontSize: 22, color: Colors.white,fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 32,  // 水平方向间距
              runSpacing: 32,  // 垂直方向间距
              children: episodeImages.map((imgPath) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 160, // 固定宽度为100
                    child: AspectRatio(
                      aspectRatio: 7 / 10, // 设置9:16的比例
                      child: Image.asset(
                        imgPath,
                        fit: BoxFit.cover, // 裁剪和填充图片
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}