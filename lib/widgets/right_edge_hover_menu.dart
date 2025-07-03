import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../utils/video_player_state.dart';
import '../utils/globals.dart' as globals;
import 'video_settings_menu.dart';

class RightEdgeHoverMenu extends StatefulWidget {
  const RightEdgeHoverMenu({super.key});

  @override
  State<RightEdgeHoverMenu> createState() => _RightEdgeHoverMenuState();
}

class _RightEdgeHoverMenuState extends State<RightEdgeHoverMenu> {
  bool _isHoverAreaVisible = false;
  bool _isMenuVisible = false;
  OverlayEntry? _settingsMenuOverlay;

  @override
  void dispose() {
    _hideSettingsMenuWithoutSetState();
    super.dispose();
  }

  void _showSettingsMenu() {
    if (_settingsMenuOverlay != null) return;
    
    _settingsMenuOverlay = OverlayEntry(
      builder: (context) => HoverSettingsMenuWrapper(
        onClose: _hideSettingsMenu,
        onHover: (isHovered) {
          if (mounted) {
            setState(() {
              _isMenuVisible = isHovered;
            });
          }
        },
      ),
    );

    Overlay.of(context).insert(_settingsMenuOverlay!);
    if (mounted) {
      setState(() {
        _isMenuVisible = true;
      });
    }
  }

  void _hideSettingsMenu() {
    _settingsMenuOverlay?.remove();
    _settingsMenuOverlay = null;
    if (mounted) {
      setState(() {
        _isMenuVisible = false;
      });
    }
  }

  void _hideSettingsMenuWithoutSetState() {
    _settingsMenuOverlay?.remove();
    _settingsMenuOverlay = null;
    _isMenuVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 只在有视频且非手机平台时显示
        if (!videoState.hasVideo || globals.isPhone) {
          return const SizedBox.shrink();
        }

        return Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: MouseRegion(
            onEnter: (_) {
              setState(() {
                _isHoverAreaVisible = true;
              });
              _showSettingsMenu();
            },
            onExit: (_) {
              setState(() {
                _isHoverAreaVisible = false;
              });
              // 延迟隐藏，给用户时间移动到菜单上
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted && !_isHoverAreaVisible && !_isMenuVisible) {
                  _hideSettingsMenu();
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: _isHoverAreaVisible ? 30 : 8,
              decoration: BoxDecoration(
                gradient: _isHoverAreaVisible
                    ? LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.15),
                          Colors.white.withOpacity(0.25),
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      )
                    : LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _isHoverAreaVisible ? 1.0 : 0.7,
                child: Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class HoverSettingsMenuWrapper extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool> onHover;

  const HoverSettingsMenuWrapper({
    super.key,
    required this.onClose,
    required this.onHover,
  });

  @override
  State<HoverSettingsMenuWrapper> createState() => _HoverSettingsMenuWrapperState();
}

class _HoverSettingsMenuWrapperState extends State<HoverSettingsMenuWrapper> {
  bool _isMenuHovered = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isMenuHovered) {
        widget.onClose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 使用自定义的鼠标检测包装VideoSettingsMenu
    return _HoverDetectionWrapper(
      onHover: (isHovered) {
        setState(() {
          _isMenuHovered = isHovered;
        });
        widget.onHover(isHovered);
        
        if (isHovered) {
          _hideTimer?.cancel(); // 取消隐藏定时器
        } else {
          _startHideTimer(); // 开始隐藏倒计时
        }
      },
      child: VideoSettingsMenu(
        onClose: widget.onClose,
      ),
    );
  }
}

/// 自定义的悬浮检测包装器，在不破坏VideoSettingsMenu布局的情况下添加悬浮检测
class _HoverDetectionWrapper extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool> onHover;

  const _HoverDetectionWrapper({
    required this.child,
    required this.onHover,
  });

  @override
  State<_HoverDetectionWrapper> createState() => _HoverDetectionWrapperState();
}

class _HoverDetectionWrapperState extends State<_HoverDetectionWrapper> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => widget.onHover(true),
      onExit: (_) => widget.onHover(false),
      child: widget.child,
    );
  }
}