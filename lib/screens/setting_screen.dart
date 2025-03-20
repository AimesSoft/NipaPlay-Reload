// ignore_for_file: prefer_const_constructors

import 'dart:io';
import 'package:flutter/foundation.dart'; // 导入这个包来使用kIsWeb
import 'package:flutter/material.dart';
import 'package:nipaplay/screens/bar_settings.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart';
import 'package:nipaplay/utils/theme_colors.dart'; // 导入新的颜色管理文件
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/menu_button.dart';
import 'package:window_manager/window_manager.dart';
import 'account_settings.dart';
import 'background_settings.dart';
import 'color_settings.dart';
import 'theme_settings.dart';

const double titleBarHeight = 30.0;

class SubOptionDivider extends StatelessWidget {
  final bool isLast; // 是否是最后一个分割线，用于决定是否增加右边距

  const SubOptionDivider({super.key, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Divider(
      thickness: 0.38,
      color: getLineColor(),
      endIndent: isLast ? 0 : 50, // 控制右边距（如果不是最后一个分割线，则增加右边距）
    );
  }
}

class SettingScreen extends StatefulWidget {
  final SettingsService settingsService = SettingsService();

  SettingScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _SettingScreenState createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool isMaximized = false;
  double scrollOffset = 0.0; // 用于存储滚动偏移量

  void _toggleWindowSize() async {
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    setState(() {
      isMaximized = !isMaximized;
    });
  }

  void _minimizeWindow() async {
    await windowManager.minimize();
  }

  void _closeWindow() async {
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
    Color textColor = isDarkModeValue ? Colors.white : Colors.black;

    return Container(
      color: getBackgroundColor(), // 使用新封装的颜色方法
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(backImage),
            fit: BoxFit.cover,
            opacity: 0.5,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.only(left: 10, right: 20),
          child: Column(
            children: [
              SizedBox(
                height: titleBarHeight, // 给 Stack 一个固定高度
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: !kIsWeb &&Platform.isMacOS ? 0 : 100,
                      child: GestureDetector(
                        onDoubleTap: (kIsWeb || !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)
                            ? null
                            : _toggleWindowSize,
                        child: Container(
                          height: titleBarHeight,
                          color: Colors.transparent,
                          child: Align(
                            alignment: Alignment.center,
                            child: AnimatedOpacity(
                              opacity: scrollOffset == 0.0 ? 0.0 : 1.0, // 滚动距离为0时透明度为0
                              duration: Duration(milliseconds: 150), // 动画持续时间
                              child: Text(
                                "设置",
                                style: getBarTitleTextStyle(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!kIsWeb && (Platform.isWindows || Platform.isLinux))
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: titleBarHeight,
                          color: Colors.transparent,
                          child: WindowControlButtons(
                            isMaximized: isMaximized,
                            isDarkMode: isDarkModeValue,
                            onMinimize: _minimizeWindow,
                            onMaximizeRestore: _toggleWindowSize,
                            onClose: _closeWindow,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (scrollNotification) {
                    if (scrollNotification is ScrollUpdateNotification) {
                      setState(() {
                        scrollOffset = scrollNotification.metrics.pixels; // 更新滚动偏移量
                      });
                    }
                    return true;
                  },
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "设置",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 30,
                            color: textColor,
                          ),
                        ),
                        SubOptionDivider(isLast: true), // 第一个分割线不需要右边距
                        AccountSettings(settingsService: widget.settingsService),
                        SubOptionDivider(), // 后续分割线右边距增加50
                        BackgroundSettings(settingsService: widget.settingsService),
                        SubOptionDivider(), // 后续分割线右边距增加50
                        ColorSettings(),
                        SubOptionDivider(), // 后续分割线右边距增加50
                        DarkSettings(settingsService: widget.settingsService),
                        SubOptionDivider(), // 后续分割线右边距增加50
                        BarSettings(settingsService: widget.settingsService),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}