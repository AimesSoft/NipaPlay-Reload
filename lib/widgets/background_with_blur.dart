// widgets/background_with_blur.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'dart:io';
// 导入 glassmorphism 插件

class BackgroundWithBlur extends StatefulWidget {
  final Widget child;

  const BackgroundWithBlur({super.key, required this.child});

  @override
  // ignore: library_private_types_in_public_api
  _BackgroundWithBlurState createState() => _BackgroundWithBlurState();
}

class _BackgroundWithBlurState extends State<BackgroundWithBlur> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景图像
        Positioned.fill(
          child: _buildBackgroundImage(),
        ),
        // 使用 GlassmorphicContainer 实现毛玻璃效果
        Positioned.fill(
          child: GlassmorphicContainer(
            blur: globals.blurPower, // 模糊效果的强度
            alignment: Alignment.center,
            borderRadius: 0, // 圆角半径
            border: 0, // 边框宽度
            padding: const EdgeInsets.all(20), // 内边距
            height: double.infinity,
            width: double.infinity,
            linearGradient: LinearGradient( // 添加线性渐变
              colors: [
                const Color.fromARGB(255, 0, 0, 0).withOpacity(0),
                const Color.fromARGB(255, 0, 0, 0).withOpacity(0),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderGradient: LinearGradient( // 添加边框渐变
              colors: [
                const Color.fromARGB(255, 0, 0, 0).withOpacity(0.3),
                const Color.fromARGB(255, 0, 0, 0).withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }

  Widget _buildBackgroundImage() {
    if (globals.backgroundImageMode == '关闭') {
      return Image.asset(
        'assets/backempty.png',
        fit: BoxFit.cover,
      );
    } else if (globals.backgroundImageMode == '看板娘') {
      return Image.asset(
        'assets/images/main_image.png',
        fit: BoxFit.cover,
      );
    } else if (globals.backgroundImageMode == '自定义') {
      final file = File(globals.customBackgroundPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              'assets/images/main_image.png',
              fit: BoxFit.cover,
            );
          },
        );
      } else {
        return Image.asset(
          'assets/images/main_image.png',
          fit: BoxFit.cover,
        );
      }
    }
    return Image.asset(
      'assets/images/main_image.png',
      fit: BoxFit.cover,
    );
  }
}