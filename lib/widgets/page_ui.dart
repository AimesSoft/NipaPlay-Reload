import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/menu_button.dart';
import 'package:window_manager/window_manager.dart';
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
class PageUI extends StatefulWidget {
  final String settingTitle;
  final List<Widget> settingsWidgets; // 用于接收控件列表

  const PageUI({
    super.key,
    required this.settingTitle,
    required this.settingsWidgets, // 传递控件列表
  });

  @override
  // ignore: library_private_types_in_public_api
  _PageUIState createState() => _PageUIState();
}

class _PageUIState extends State<PageUI> {
  double scrollOffset = 0.0;
  bool isMaximized = false;

  ImageProvider getImageProvider(String imagePath) {
    try {
      if (imagePath.contains('http')) {
        return NetworkImage(imagePath);
      } else if (imagePath.contains('assets')) {
        return AssetImage(imagePath);
      } else if (imagePath.startsWith('data:image')) {
        return MemoryImage(_base64ToImage(imagePath));
      } else {
        return FileImage(File(imagePath));
      }
    } catch (e) {
      if (imagePath.contains('assets')) {
        return AssetImage(imagePath);
      } else {
        return FileImage(File(imagePath));
      }
    }
  }

  Uint8List _base64ToImage(String base64String) {
    final base64Data = base64String.split(',').last;
    return base64Decode(base64Data);
  }

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
    Color textColor = isDarkModeValue ? Colors.white : Colors.black;

    return Container(
      color: getBackgroundColor(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: getImageProvider(backImage),
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
                        SizedBox(height: isPhone && isMobile ? 55 : 30),
                        Text(
                          widget.settingTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 30,
                            color: textColor,
                          ),
                        ),
                        ...widget.settingsWidgets, // 动态加载传入的控件
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                SizedBox(
                  height: isPhone && isMobile ? 55 : 30,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRect(
                          child: AnimatedOpacity(
                            opacity: scrollOffset == 0.0 ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      // ignore: deprecated_member_use
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
                        top: 0,
                        left: 0,
                        right: winLinDesktop ? 100 : 0,
                        child: GestureDetector(
                          onDoubleTap: _toggleWindowSize,
                          onPanStart: (details) async {
                            if (winLinDesktop) {
                              await windowManager.startDragging();
                            }
                          },
                          child: Container(
                            height: isPhone && isMobile ? 55 : 30,
                            color: Colors.transparent,
                            child: Align(
                              alignment: isMobile && !kIsWeb
                                  ? Alignment.bottomCenter
                                  : Alignment.center,
                              child: AnimatedOpacity(
                                opacity: scrollOffset == 0.0 ? 0.0 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: Text(
                                  widget.settingTitle,
                                  style: getTitleTextStyle(context),
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
                            height: isPhone && isMobile ? 55 : 30,
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