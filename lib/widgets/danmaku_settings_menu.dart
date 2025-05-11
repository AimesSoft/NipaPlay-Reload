import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'settings_hint_text.dart';
import 'dart:ui';
import 'settings_slider.dart';

class DanmakuSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final VideoPlayerState videoState;

  const DanmakuSettingsMenu({
    super.key,
    required this.onClose,
    required this.videoState,
  });

  @override
  State<DanmakuSettingsMenu> createState() => _DanmakuSettingsMenuState();
}

class _DanmakuSettingsMenuState extends State<DanmakuSettingsMenu> {
  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return BaseSettingsMenu(
          title: '弹幕设置',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 弹幕开关
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '显示弹幕',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: videoState.danmakuVisible,
                          onChanged: (value) {
                            videoState.setDanmakuVisible(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('开启后在视频上显示弹幕内容'),
                  ],
                ),
              ),
              // 弹幕堆叠开关
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '弹幕堆叠',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: videoState.danmakuStacking,
                          onChanged: (value) {
                            videoState.setDanmakuStacking(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('允许多条弹幕重叠显示，适合弹幕密集场景'),
                  ],
                ),
              ),
              // 合并相同弹幕开关
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '合并相同弹幕',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: videoState.mergeDanmaku,
                          onChanged: (value) {
                            videoState.setMergeDanmaku(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('将内容相同的弹幕合并为一条显示，减少屏幕干扰'),
                  ],
                ),
              ),
              // 弹幕透明度
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsSlider(
                      value: videoState.danmakuOpacity,
                      onChanged: (v) => videoState.setDanmakuOpacity(v),
                      label: '弹幕透明度',
                      displayTextBuilder: (v) => '${(v * 100).toInt()}%',
                      min: 0.0,
                      max: 1.0,
                    ),
                    const SizedBox(height: 4),
                    const SettingsHintText('拖动滑块调整弹幕透明度'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// 新增弹幕透明度滑块组件
class _DanmakuOpacitySlider extends StatefulWidget {
  final VideoPlayerState videoState;
  const _DanmakuOpacitySlider({required this.videoState});

  @override
  State<_DanmakuOpacitySlider> createState() => _DanmakuOpacitySliderState();
}

class _DanmakuOpacitySliderState extends State<_DanmakuOpacitySlider> {
  final GlobalKey _sliderKey = GlobalKey();
  bool _isHovering = false;
  bool _isThumbHovered = false;
  bool _isDragging = false;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, double progress) {
    _removeOverlay();
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;
    final position = sliderBox.localToGlobal(Offset.zero);
    final size = sliderBox.size;
    final bubbleX = position.dx + (progress * size.width) - 20;
    final bubbleY = position.dy - 40;
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: bubbleX,
              top: bubbleY,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${(widget.videoState.danmakuOpacity * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateOpacityFromPosition(Offset localPosition) {
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox != null) {
      final width = sliderBox.size.width;
      final progress = (localPosition.dx / width).clamp(0.0, 1.0);
      widget.videoState.setDanmakuOpacity(progress);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '弹幕透明度',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        MouseRegion(
          onEnter: (_) {
            setState(() {
              _isHovering = true;
            });
          },
          onExit: (_) {
            setState(() {
              _isHovering = false;
              _isThumbHovered = false;
            });
          },
          onHover: (event) {
            if (!_isHovering || _isDragging) return;
            final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
            if (sliderBox != null) {
              final localPosition = sliderBox.globalToLocal(event.position);
              final width = sliderBox.size.width;
              final progress = (localPosition.dx / width).clamp(0.0, 1.0);
              final thumbRect = Rect.fromLTWH(
                (widget.videoState.danmakuOpacity * width) - 8,
                16,
                16,
                16
              );
              setState(() {
                _isThumbHovered = thumbRect.contains(localPosition);
              });
            }
          },
          child: GestureDetector(
            onHorizontalDragStart: (details) {
              setState(() => _isDragging = true);
              _updateOpacityFromPosition(details.localPosition);
              _showOverlay(context, widget.videoState.danmakuOpacity);
            },
            onHorizontalDragUpdate: (details) {
              _updateOpacityFromPosition(details.localPosition);
              if (_overlayEntry != null) {
                _showOverlay(context, widget.videoState.danmakuOpacity);
              }
            },
            onHorizontalDragEnd: (details) {
              setState(() => _isDragging = false);
              _removeOverlay();
            },
            onTapDown: (details) {
              setState(() => _isDragging = true);
              _updateOpacityFromPosition(details.localPosition);
              _showOverlay(context, widget.videoState.danmakuOpacity);
            },
            onTapUp: (details) {
              setState(() => _isDragging = false);
              _removeOverlay();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  key: _sliderKey,
                  clipBehavior: Clip.none,
                  children: [
                    // 背景轨道
                    Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 进度轨道
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 20,
                      child: FractionallySizedBox(
                        widthFactor: widget.videoState.danmakuOpacity,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.3),
                                blurRadius: 2,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 滑块
                    Positioned(
                      left: (widget.videoState.danmakuOpacity * constraints.maxWidth) - (_isThumbHovered || _isDragging ? 8 : 6),
                      top: 22 - (_isThumbHovered || _isDragging ? 8 : 6),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          width: _isThumbHovered || _isDragging ? 16 : 12,
                          height: _isThumbHovered || _isDragging ? 16 : 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: _isThumbHovered || _isDragging ? 6 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SettingsHintText('拖动滑块调整弹幕透明度'),
      ],
    );
  }
} 