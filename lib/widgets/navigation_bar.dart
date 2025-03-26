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
import 'dart:ui'; // 用于 BackdropFilter

const double titleSize = 45.0; // 标题大小
double sizedboxTitle = 5.0; // 标题距离顶部距离
double sidebarWidth = isMobile ? 90.0 : 70.0;
double buttonXpos = 11.0;
double constSidebarWidth = 70.0;
double barSize = 2.0;
double barTextWidth = 130.0;
double iconTop = isMobile ?5:0;
double barOpacity = isMobile? 0.2 : 1;

class _NavigationBarState extends State<NavigationBar> {
  // 更新宽度的方法
  void _updateWidth(DragUpdateDetails details) {
    if (!isMobile) {
      setState(() {
        // 限制宽度在70到200之间
        sidebarWidth = (sidebarWidth + details.primaryDelta!)
            .clamp(constSidebarWidth, 200.0);
      });
    }
  }

  // 根据宽度计算透明度
  double _getTextOpacity() {
    return (sidebarWidth - constSidebarWidth) /
        barTextWidth; // 宽度从70到200，透明度从0到1
  }

  // 简化文本和按钮的创建
  Widget _buildRow(String text, String imagePath, bool isImage) {
  // 非移动端显示透明度变化的文本
  return isMobile
      // 在移动设备上，图标和文字竖直排列，文字大小为 5，并去除透明度变化
      ? Column(
          //mainAxisAlignment: MainAxisAlignment.start, // 确保图标和文字居中对齐
          children: [
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
            //const SizedBox(height: 5), // 设置图标和文字之间的间距
            Text(
              text,
              style: getIconTextStyle(context), // 设置文字大小为 5
            ),
          ],
        )
      : Row(
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
      width: !isMobile ? sidebarWidth : null, // 如果不是垂直方向，则使用 sidebarWidth 作为宽度
      height: isMobile ? sidebarWidth : null,
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: getBarColor().withOpacity(barOpacity),
        border: isMobile
            ? Border(
                top: BorderSide(
                  // ignore: deprecated_member_use
                  color: isDarkModeValue ? getBarLineColor().withOpacity(0.2) : getBarLineColor(),
                  width: 0.3,
                ),
              )
            : Border(
                right: BorderSide(
                  color: isDarkModeValue ? Colors.black : getBarLineColor(),
                  width: 1.0,
                ),
              ),
      ),
      child: Stack(
        children: [
          // 只对底部 sidebarWidth 高度部分应用高斯模糊
          Positioned(
            bottom: 0,  // 使模糊效果只应用在底部
            left: 0,
            right: 0,
            child: BackdropFilter(
              filter: isMobile?ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0):ImageFilter.blur(sigmaX: 0, sigmaY: 0),  // 高斯模糊效果
              child: Container(
                height: sidebarWidth, // 高斯模糊区域的高度
                // ignore: deprecated_member_use
              ),
            ),
          ),
          // 依据 sidebarBlurEffect 判断是否添加 FluidBackgroundWidget
          if (!sidebarBlurEffect && !isMobile)
            Padding(
                padding: EdgeInsets.only(top: iconTop),
                child: FluidBackgroundWidget(
                    child: SidebarContent(
                        sizedboxTitle: sizedboxTitle,
                        titleSize: titleSize,
                        titleImagePath: titleImagePath,
                        buildRow: _buildRow,
                        isDarkModeValue: isDarkModeValue)))
          else
            Padding(
                padding: EdgeInsets.only(top: iconTop),
                child: SidebarContent(
                    sizedboxTitle: sizedboxTitle,
                    titleSize: titleSize,
                    titleImagePath: titleImagePath,
                    buildRow: _buildRow,
                    isDarkModeValue: isDarkModeValue)),
          // 在侧边栏的右边添加拖动区域（仅在非移动设备上）
          if (!isMobile)
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