import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

// 导入 glassmorphism 插件
String backgroundImageUrl = (globals.isDesktop || globals.isTablet)
    ? 'assets/images/main_image.png'
    : 'assets/images/main_image_mobile.png';

String backgroundImageUrl2 = (globals.isDesktop || globals.isTablet)
    ? 'assets/images/main_image2.png'
    : 'assets/images/main_image_mobile2.png';

class BackgroundWithBlur extends StatelessWidget {
  final Widget child;

  const BackgroundWithBlur({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        return Stack(
          children: [
            // 背景图像
            Positioned.fill(
              child: _buildBackgroundImage(),
            ),
            // 使用 GlassmorphicContainer 实现毛玻璃效果
            if (settingsProvider.isBlurEnabled)
              Positioned.fill(
                child: GlassmorphicContainer(
                  blur: settingsProvider.blurPower, // 从Provider获取模糊强度
                  alignment: Alignment.center,
                  borderRadius: 0, // 圆角半径
                  border: 0, // 边框宽度
                  padding: const EdgeInsets.all(20), // 内边距
                  height: double.infinity,
                  width: double.infinity,
                  linearGradient: LinearGradient(
                    // 添加线性渐变
                    colors: [
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0),
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderGradient: LinearGradient(
                    // 添加边框渐变
                    colors: [
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0.3),
                      const Color.fromARGB(255, 0, 0, 0).withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            child,
          ],
        );
      },
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
        backgroundImageUrl,
        fit: BoxFit.cover,
      );
    } else if (globals.backgroundImageMode == '看板娘2') {
      return Image.asset(
        backgroundImageUrl2,
        fit: BoxFit.cover,
      );
    } else if (globals.backgroundImageMode == '自定义') {
      if (kIsWeb) {
        // Web平台不支持本地文件，回退到默认图片
        return Image.asset(
          backgroundImageUrl,
          fit: BoxFit.cover,
        );
      }
      final file = File(globals.customBackgroundPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              backgroundImageUrl,
              fit: BoxFit.cover,
            );
          },
        );
      } else {
        return Image.asset(
          backgroundImageUrl,
          fit: BoxFit.cover,
        );
      }
    }
    return Image.asset(
      backgroundImageUrl,
      fit: BoxFit.cover,
    );
  }
}