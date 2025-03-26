import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/utils/theme_helper.dart';
import 'package:nipaplay/widgets/fluid_background_widget.dart';
import 'package:nipaplay/widgets/image_assets.dart';
import 'package:nipaplay/widgets/sidebar_content.dart';
import 'dart:io';
import 'dart:ui';
import 'package:nipaplay/widgets/navigation_row.dart'; // 导入新的 navigation_row.dart 文件

const double titleSize = 45.0;
double sizedboxTitle = 5.0;
double sidebarWidth = isPhone ? 100.0 : 70.0;
double sidebarHeight = 90.0;
double buttonXpos = isPhone ? 42.0 : 11.0;
double constSidebarWidth = isPhone ? 100.0 : 70.0;
double barTextWidth = isPhone ? 100.0 : 130.0;
double iconTop = 5;

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
    return (sidebarWidth - constSidebarWidth) / barTextWidth;
  }

// 处理 onPressed 的回调
  void _onBarPagePressed(double barPage) {
    setState(() {
      barPageNumber = barPage; // 更新 barPageNumber
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkModeValue = getCurrentThemeMode(context, modeSwitch);

    if (!kIsWeb) {
      if (Platform.isMacOS) {
        sizedboxTitle = 30.0;
      } else if (Platform.isIOS) {
        sizedboxTitle = 10.0;
      } else {
        sizedboxTitle = 5.0;
      }
    } else {
      sizedboxTitle = 5.0;
    }

    String titleImagePath = isDarkModeValue
        ? ImageAssets.title.replaceFirst('.png', 'Light.png')
        : ImageAssets.title;

    return Container(
      width: !isMobile ? sidebarWidth : null,
      height: isMobile ? sidebarHeight : null,
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: isMobile ? getBarColor().withOpacity(0.2) : getBarColor(),
        border: isMobile
            ? Border(
                top: BorderSide(
                  // ignore: deprecated_member_use
                  color: isDarkModeValue
                      // ignore: deprecated_member_use
                      ? getBarLineColor().withOpacity(0.2)
                      : getBarLineColor(),
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
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: BackdropFilter(
              filter: isMobile
                  ? ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0)
                  : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
              child: Container(
                height: sidebarHeight,
              ),
            ),
          ),
          if (!sidebarBlurEffect && !isMobile)
            Padding(
                padding: isMobile
                    ? EdgeInsets.only(top: iconTop)
                    : const EdgeInsets.only(top: 0),
                child: FluidBackgroundWidget(
                    child: SidebarContent(
                        sizedboxTitle: sizedboxTitle,
                        titleSize: titleSize,
                        titleImagePath: titleImagePath,
                        buildRow: (text, imagePath, isImage, barPage) =>
                            buildNavigationRow(
                              context: context,
                              text: text,
                              imagePath: imagePath,
                              isImage: isImage,
                              barPage: barPage,
                              isMobile: isMobile,
                              buttonXpos: buttonXpos,
                              titleSize: titleSize,
                              textOpacity: _getTextOpacity(),
                              onBarPagePressed: _onBarPagePressed, // 传入回调
                            ),
                        isDarkModeValue: isDarkModeValue)))
          else
            Padding(
                padding: isMobile
                    ? EdgeInsets.only(top: iconTop)
                    : const EdgeInsets.only(top: 0),
                child: SidebarContent(
                    sizedboxTitle: sizedboxTitle,
                    titleSize: titleSize,
                    titleImagePath: titleImagePath,
                    buildRow: (text, imagePath, isImage, barPage) =>
                        buildNavigationRow(
                          context: context,
                          text: text,
                          imagePath: imagePath,
                          isImage: isImage,
                          barPage: barPage,
                          isMobile: isMobile,
                          buttonXpos: buttonXpos,
                          titleSize: titleSize,
                          textOpacity: _getTextOpacity(),
                          onBarPagePressed: _onBarPagePressed, // 传入回调
                        ),
                    isDarkModeValue: isDarkModeValue)),
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
                    width: isTouch ? 10.0 : 2.0,
                    color: Colors.transparent,
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
