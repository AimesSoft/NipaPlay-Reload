import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_provider.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/icon_button_with_background.dart';
import 'package:provider/provider.dart'; // 导入 themeProvider

Widget buildNavigationRow({
  required BuildContext context,
  required String text,
  required String imagePath,
  required bool isImage,
  required double barPage,
  required bool isMobile,
  required double buttonXpos,
  required double titleSize,
  required double textOpacity,
  required Function(double) onBarPagePressed, // 接收一个回调函数
}) {
  final themeProvider = context.watch<ThemeProvider>();  // 获取 themeProvider 实例

  return isMobile
      ? Column(
          children: [
            isImage
                ? Image.asset(
                    imagePath,
                    width: titleSize,
                    height: titleSize,
                  )
                : IconButtonWithBackground(
                    imagePath: imagePath,
                    isSelected: barPageNumber == barPage,
                    onPressed: () {
                      onBarPagePressed(barPage); // 调用传入的回调函数
                      themeProvider.updateDraw();  // 按下按钮后执行 updateDraw
                    },
                  ),
            Text(
              text,
              style: getIconTextStyle(context),
            ),
          ],
        )
      : Row(
          children: [
            Padding(padding: EdgeInsets.only(left: buttonXpos)),
            isImage
                ? Image.asset(
                    imagePath,
                    width: titleSize,
                    height: titleSize,
                  )
                : IconButtonWithBackground(
                    imagePath: imagePath,
                    onPressed: () {
                      onBarPagePressed(barPage); // 调用传入的回调函数
                      themeProvider.updateDraw();  // 按下按钮后执行 updateDraw
                    },
                    isSelected: barPageNumber == barPage,
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Opacity(
                opacity: textOpacity,
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