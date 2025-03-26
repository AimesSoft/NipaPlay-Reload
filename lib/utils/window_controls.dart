import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/widgets/menu_button.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatefulWidget {
  final String title;
  final double scrollOffset;

  const WindowControls({
    super.key,
    required this.title,
    required this.scrollOffset,
  });

  @override
  // ignore: library_private_types_in_public_api
  _WindowControlsState createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool isMaximized = false;

  // 切换窗口最大化/恢复状态
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

  // 最小化窗口
  void _minimizeWindow() async {
    await windowManager.minimize();
  }

  // 关闭窗口
  void _closeWindow() async {
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: isPhone && isMobile ? 55 : 30,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: AnimatedOpacity(
                    opacity: widget.scrollOffset == 0.0 ? 0.0 : 1.0,
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
                      alignment: isMobile ? Alignment.bottomCenter : Alignment.center,
                      child: AnimatedOpacity(
                        opacity: widget.scrollOffset == 0.0 ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 30,
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                          ),
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
    );
  }
}
