import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/rounded_button.dart';  // 请确保您有这个 RoundedButton 组件的引用
import 'dart:ui';

double fontSize = 16;
double verticalPadding = 5;
double horizontalPadding = 40;
double paddingHeight = 15;

class AlertDialogWidget extends StatelessWidget {
  final String message;  // 用来接收警告信息

  const AlertDialogWidget({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent, // 设置背景为透明
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 300,
        padding: EdgeInsets.all(paddingHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.transparent, // 设置模糊背景的颜色
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16), // 确保内容也被裁剪为圆角
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: Container(
              padding: EdgeInsets.all(paddingHeight),
              // ignore: deprecated_member_use
              color: getBorderColor().withOpacity(0.7), // 背景色稍微透明
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 显示警告信息，使用 getTitleTextStyle 来获取样式
                  Text(
                    message,
                    style: getTitleTextStyle(context),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: paddingHeight),
                  // 使用 RoundedButton 来创建确认按钮
                  RoundedButton(
                    text: '确认',
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    fontSize: fontSize,
                    verticalPadding: verticalPadding,
                    horizontalPadding: horizontalPadding,
                    isSelected: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 显示警告框
void showAlertDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialogWidget(message: message);  // 传入警告信息
    },
  );
}