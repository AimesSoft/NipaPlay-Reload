import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/utils/theme_helper.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/fluid_background_widget.dart';
import 'package:nipaplay/widgets/image_assets.dart';
import 'package:nipaplay/widgets/icon_button_with_background.dart'; // 导入新的 IconButtonWithBackground
import 'package:nipaplay/widgets/sidebar_content.dart';
import 'dart:io'; // 用于平台判断

const double titleSize = 45.0; // 标题大小
double sizedboxTitle = 5.0; // 标题距离顶部距离
double sidebarWidth = !kIsWeb&&(Platform.isIOS || Platform.isAndroid) ? 100 : 70.0; // 初始宽度
double buttonXpos = !kIsWeb&&(Platform.isIOS || Platform.isAndroid) ? 42 : 11.0;
// ignore: non_constant_identifier_names
double ConstsidebarWidth = !kIsWeb&&(Platform.isIOS || Platform.isAndroid)  ? 100 : 70.0;
double barSize = kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) || !kIsWeb&&(Platform.isIOS || Platform.isAndroid) ? 10.0 : 2.0; 
class _NavigationBarState extends State<NavigationBar> {
  // 更新宽度的方法
  void _updateWidth(DragUpdateDetails details) {
    setState(() {
      // 限制宽度在70到200之间
      sidebarWidth = (sidebarWidth + details.primaryDelta!)
          .clamp(ConstsidebarWidth, 200.0);
    });
  }

  // 根据宽度计算透明度
  double _getTextOpacity() {
    return (sidebarWidth - ConstsidebarWidth) / 130; // 宽度从70到200，透明度从0到1
  }

  // 简化文本和按钮的创建
  Widget _buildRow(String text, String imagePath, bool isImage) {
    return Row(
      children: [
        Padding(padding: EdgeInsets.only(left: buttonXpos)),
        isImage
            ? Image.asset(
                imagePath,
                width: titleSize, // 图片大小设置为 45
                height: titleSize,
              )
            : IconButtonWithBackground(
                imagePath: imagePath,
                onPressed: () {},
              ),
        const SizedBox(width: 10),
        Expanded(
          child: Opacity(
            opacity: _getTextOpacity(), // 根据宽度变化透明度
            child: Text(
              text,
              style: getBarTextStyle(context),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkModeValue = getCurrentThemeMode(context, modeSwitch);

    // 根据操作系统调整标题的间距
    if (!kIsWeb) {
      if (Platform.isMacOS) {
        sizedboxTitle = 30.0; // macOS 下的间距
      } else if (Platform.isIOS) {
        sizedboxTitle = 10.0; // iOS 下的间距
      } else {
        sizedboxTitle = 5.0; // 非 macOS（如 Windows 或 Linux）下的间距
      }
    } else {
      sizedboxTitle = 5.0; // Web平台下的间距设置
    }

    // 根据亮暗模式选择不同的标题图片
    String titleImagePath = isDarkModeValue
        ? ImageAssets.title.replaceFirst('.png', 'Light.png')
        : ImageAssets.title;

    return Container(
      width: sidebarWidth, // 使用动态宽度
      decoration: BoxDecoration(
        color: getBarColor(),
        border: Border(
          right: BorderSide(
            color: isDarkModeValue ? Colors.black : getBarLineColor(),
            width: 1.0,
          ),
        ),
      ),
      child: Stack(
        children: [
          // 依据 sidebarBlurEffect 判断是否添加 FluidBackgroundWidget
          if (!sidebarBlurEffect)
            FluidBackgroundWidget(
                child: SidebarContent(
                    sizedboxTitle: sizedboxTitle,
                    titleSize: titleSize,
                    titleImagePath: titleImagePath,
                    buildRow: _buildRow,
                    isDarkModeValue: isDarkModeValue))
          else
            SidebarContent(
                sizedboxTitle: sizedboxTitle,
                titleSize: titleSize,
                titleImagePath: titleImagePath,
                buildRow: _buildRow,
                isDarkModeValue: isDarkModeValue),
          // 在侧边栏的右边添加拖动区域
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: _updateWidth,
                child: Container(
                  width: barSize,
                  color: Colors.transparent, // 透明颜色，显示拖动区域
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NavigationBar extends StatefulWidget {
  const NavigationBar({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _NavigationBarState createState() => _NavigationBarState();
}
