// ignore: file_names
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:window_manager/window_manager.dart';
import 'dart:ui';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

const double iconSize = 25.0; // 图标大小
const double buttonSize = 28.0; // 按钮大小
const double containerHeight = 32.0; // 容器高度
const double containerPadding = 2.0; // 容器内边距
const double borderRadius = 8.0; // 圆角半径

class WindowControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isCloseButton;
  final double? customIconSize;

  const WindowControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.isCloseButton = false,
    this.customIconSize,
  });

  @override
  _WindowControlButtonState createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<WindowControlButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 悬停时的背景颜色 - 参考blur_snackbar的设计
    Color hoverColor = Colors.transparent;
    if (_isHovered) {
      if (widget.isCloseButton) {
        hoverColor = const Color(0x40FF4444); // 红色悬停
      } else {
        hoverColor = Colors.white.withOpacity(0.1); // 白色悬停
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
        onTapDown: (_) {
          setState(() {
            _isPressed = true;
          });
          _animationController.forward();
        },
        onTapUp: (_) {
          setState(() {
            _isPressed = false;
          });
          _animationController.reverse();
          widget.onPressed();
        },
        onTapCancel: () {
          setState(() {
            _isPressed = false;
          });
          _animationController.reverse();
        },
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _isPressed ? _scaleAnimation.value : 1.0,
              child: Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4.0),
                  color: hoverColor,
                ),
                child: Icon(
                  widget.icon,
                  size: widget.customIconSize ?? iconSize,
                  color: Colors.white,
                ),
              ),
            );
          },
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
    // 参考system_resource_display的毛玻璃设计
    return Container(
      margin: const EdgeInsets.all(4.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            height: containerHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: containerPadding * 2,
              vertical: containerPadding,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              color: const Color.fromARGB(255, 253, 253, 253).withOpacity(0.2),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 最小化按钮
                WindowControlButton(
                  icon: Icons.horizontal_rule_rounded,
                  onPressed: widget.onMinimize,
                ),
                const SizedBox(width: 8),
                
                // 最大化/恢复按钮
                WindowControlButton(
                  icon: widget.isMaximized 
                      ? Icons.filter_none_rounded 
                      : Icons.crop_square_rounded,
                  onPressed: widget.onMaximizeRestore,
                  customIconSize: widget.isMaximized ? 18.0 : null,
                ),
                const SizedBox(width: 8),
                
                // 关闭按钮
                WindowControlButton(
                  icon: Icons.close_rounded,
                  onPressed: widget.onClose,
                  isCloseButton: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
