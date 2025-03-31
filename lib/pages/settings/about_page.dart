// about_page.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_utils.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent, // 设置背景颜色
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.info_outline,
              color: Colors.white,
              size: 100,
            ),
            const SizedBox(height: 20),
            const Text(
              '关于 NipaPlay',
              style: TextStyle(fontSize: 24, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                'NipaPlay 是一个提供视频播放、媒体库管理和新番更新的应用。',
                style: getTextStyle(context),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}