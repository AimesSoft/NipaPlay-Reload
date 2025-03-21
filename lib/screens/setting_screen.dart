// ignore_for_file: prefer_const_constructors

import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/screens/bar_settings.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/menu_button.dart';
import 'package:window_manager/window_manager.dart';
import 'account_settings.dart';
import 'background_settings.dart';
import 'color_settings.dart';
import 'theme_settings.dart';

const double titleBarHeight = 30.0;

class SubOptionDivider extends StatelessWidget {
  final bool isLast;

  const SubOptionDivider({super.key, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Divider(
      thickness: 0.38,
      color: getLineColor(),
      endIndent: isLast ? 0 : 50,
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
  double scrollOffset = 0.0;

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

  ImageProvider getImageProvider(String imagePath) {
  if (imagePath.contains('assets')|| kIsWeb) {
    return AssetImage(imagePath);
  } else {
    return FileImage(File(imagePath));
  }
}
  @override
  Widget build(BuildContext context) {
    bool isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
    Color textColor = isDarkModeValue ? Colors.white : Colors.black;

    return Container(
      color: getBackgroundColor(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image:getImageProvider(backImage),
            fit: BoxFit.cover,
            opacity: 0.5,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: NotificationListener<ScrollNotification>(
                onNotification: (scrollNotification) {
                  if (scrollNotification is ScrollUpdateNotification) {
                    setState(() {
                      scrollOffset = scrollNotification.metrics.pixels;
                    });
                  }
                  return true;
                },
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.only(left: 10, right: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: titleBarHeight),
                        Text(
                          settingTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 30,
                            color: textColor,
                          ),
                        ),
                        SubOptionDivider(isLast: true),
                        AccountSettings(
                            settingsService: widget.settingsService),
                        SubOptionDivider(),
                        BackgroundSettings(
                            settingsService: widget.settingsService),
                        SubOptionDivider(),
                        ColorSettings(),
                        SubOptionDivider(),
                        DarkSettings(settingsService: widget.settingsService),
                        SubOptionDivider(),
                        BarSettings(settingsService: widget.settingsService),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                SizedBox(
                  height: titleBarHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRect(
                          child: AnimatedOpacity(
                            opacity: scrollOffset == 0.0 ? 0.0 : 1.0,
                            duration: Duration(milliseconds: 200),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: getLineColor().withOpacity(0.2),
                                      width: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        // 恢复点击事件
                        top: 0,
                        left: 0,
                        right:
                            winLinDesktop
                                ? 100
                                : 0,
                        child: GestureDetector(
                          onDoubleTap: (noMenuButton)
                              ? null
                              : _toggleWindowSize,
                          onPanStart: (details) async {
                            if (winLinDesktop) {
                              await windowManager.startDragging();
                            }
                          },
                          child: Container(
                            height: titleBarHeight,
                            color: Colors.transparent,
                            child: Align(
                              alignment: Alignment.center,
                              child: AnimatedOpacity(
                                opacity: scrollOffset == 0.0 ? 0.0 : 1.0,
                                duration: Duration(milliseconds: 200),
                                child: Text(
                                  settingTitle,
                                  style: getBarTitleTextStyle(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (winLinDesktop)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 100,
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
