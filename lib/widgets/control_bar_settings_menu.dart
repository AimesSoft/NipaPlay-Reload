import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'base_settings_menu.dart';

class ControlBarSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final VideoPlayerState videoState;

  const ControlBarSettingsMenu({
    super.key,
    required this.onClose,
    required this.videoState,
  });

  @override
  State<ControlBarSettingsMenu> createState() => _ControlBarSettingsMenuState();
}

class _ControlBarSettingsMenuState extends State<ControlBarSettingsMenu> {
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
                      '${widget.videoState.controlBarHeight.toInt()}px',
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

  void _updateHeightFromPosition(Offset localPosition) {
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox != null) {
      final width = sliderBox.size.width;
      final progress = (localPosition.dx / width).clamp(0.0, 1.0);
      final height = (progress * 150).round();
      
      // 将值调整为最接近的档位
      final List<int> steps = [0, 20, 40, 60, 80, 100, 120, 150];
      int closest = steps[0];
      for (int step in steps) {
        if ((height - step).abs() < (height - closest).abs()) {
          closest = step;
        }
      }
      
      widget.videoState.setControlBarHeight(closest.toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return BaseSettingsMenu(
          title: '控制栏设置',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '控制栏高度',
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
                          final height = (progress * 150).round();
                          
                          final progressRect = Rect.fromLTWH(0, 0, width, sliderBox.size.height);
                          final thumbRect = Rect.fromLTWH(
                            (videoState.controlBarHeight / 150 * width) - 8,
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
                          _updateHeightFromPosition(details.localPosition);
                          _showOverlay(context, videoState.controlBarHeight / 150);
                        },
                        onHorizontalDragUpdate: (details) {
                          _updateHeightFromPosition(details.localPosition);
                          if (_overlayEntry != null) {
                            _showOverlay(context, videoState.controlBarHeight / 150);
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          setState(() => _isDragging = false);
                          _updateHeightFromPosition(details.localPosition);
                          _removeOverlay();
                        },
                        onTapDown: (details) {
                          setState(() => _isDragging = true);
                          _updateHeightFromPosition(details.localPosition);
                          _showOverlay(context, videoState.controlBarHeight / 150);
                        },
                        onTapUp: (details) {
                          setState(() => _isDragging = false);
                          _updateHeightFromPosition(details.localPosition);
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
                                    widthFactor: videoState.controlBarHeight / 150,
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
                                  left: (videoState.controlBarHeight / 150 * constraints.maxWidth) - (_isThumbHovered || _isDragging ? 8 : 6),
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
                    const Text(
                      '拖动滑块调整控制栏高度',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
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