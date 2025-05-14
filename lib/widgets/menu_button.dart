// ignore: file_names
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/image_assets.dart';
import 'package:window_manager/window_manager.dart';
// 导入 system_theme.dart

const double iconSize = 15.0; // 图标大小
const double horizontalSpacing = 5.0; // 按钮之间的左右间距
const double buttonPadding = 7.0; // 按钮的上下左右内边距（默认5）

class WindowControlButton extends StatefulWidget {
  final String imagePath;
  final VoidCallback onPressed;

  const WindowControlButton({
    super.key,
    required this.imagePath,
    required this.onPressed,
  });

  @override
  // ignore: library_private_types_in_public_api
  _WindowControlButtonState createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<WindowControlButton> {
  bool _isHovered = false;
  final bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    String imagePathToDisplay;

    // 根据日间模式和悬浮状态切换图片
      imagePathToDisplay = _isPressed
          ? widget.imagePath // 按下时仍显示普通图片
          : widget.imagePath.replaceFirst(
              '.png', ImageAssets.lightSuffix); // 默认显示带 Light 后缀的图片

    // 悬浮时反转图标
    if (_isHovered && widget.imagePath != ImageAssets.closeButton) {
      imagePathToDisplay = imagePathToDisplay.replaceFirst('Light.png', '.png');
    }

    // 悬浮时关闭按钮背景颜色变为 #FF3535 并强制使用 Light 图标
    Color backgroundColor = Colors.transparent;
    if (_isHovered) {
      if (widget.imagePath == ImageAssets.closeButton) {
        backgroundColor = const Color(0xFFFF3535); // 红色背景
        imagePathToDisplay = widget.imagePath
            .replaceFirst('.png', ImageAssets.lightSuffix); // 永远显示 Light 后缀
      } else {
        backgroundColor =
            Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black; // 根据模式切换背景色
        // 悬浮时切换为 Light 图标（除了关闭按钮）
        if (Theme.of(context).brightness == Brightness.dark) {
          imagePathToDisplay =
              imagePathToDisplay.replaceFirst(ImageAssets.lightSuffix, '.png');
        } else {
          imagePathToDisplay =
              imagePathToDisplay.replaceFirst('.png', ImageAssets.lightSuffix);
        }
      }
    }

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _isHovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _isHovered = false;
        });
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          color: backgroundColor, // 悬浮时背景颜色
          padding: const EdgeInsets.all(buttonPadding), // 设置按钮内边距
          child: Image.asset(imagePathToDisplay,
              width: iconSize, height: iconSize),
        ),
      ),
    );
  }
}

class WindowControlButtons extends StatefulWidget {
  final bool isMaximized;
  final VoidCallback onMinimize;
  final VoidCallback onMaximizeRestore;
  final VoidCallback onClose;

  const WindowControlButtons({
    super.key,
    required this.isMaximized,
    required this.onMinimize,
    required this.onMaximizeRestore,
    required this.onClose,
  });

  @override
  State<WindowControlButtons> createState() => _WindowControlButtonsState();
}

class _WindowControlButtonsState extends State<WindowControlButtons> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (globals.winLinDesktop) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (globals.winLinDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  // WindowListener回调
  @override
  void onWindowMaximize() {
    // 窗口最大化时强制更新UI
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void onWindowUnmaximize() {
    // 窗口还原时强制更新UI
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 使用统一的图片路径
        WindowControlButton(
          imagePath: ImageAssets.minButton, // 最小化按钮
          onPressed: widget.onMinimize,
        ),
        const SizedBox(width: horizontalSpacing), // 使用 SizedBox 来设置按钮之间的间距
        WindowControlButton(
          imagePath: widget.isMaximized
              ? ImageAssets.unMaxButton
              : ImageAssets.maxButton, // 最大化/恢复按钮
          onPressed: widget.onMaximizeRestore,
        ),
        const SizedBox(width: horizontalSpacing), // 使用 SizedBox 来设置按钮之间的间距
        WindowControlButton(
          imagePath: ImageAssets.closeButton, // 关闭按钮
          onPressed: widget.onClose,
        ),
      ],
    );
  }
}
