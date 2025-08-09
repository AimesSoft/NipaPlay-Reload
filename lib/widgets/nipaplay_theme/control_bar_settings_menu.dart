import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'settings_hint_text.dart';
import 'settings_slider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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
  final bool _isHovering = false;
  final bool _isThumbHovered = false;
  final bool _isDragging = false;
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
                    SettingsSlider(
                      value: videoState.controlBarHeight,
                      onChanged: (v) => videoState.setControlBarHeight(v),
                      label: '控制栏高度',
                      displayTextBuilder: (v) => '${v.toInt()}px',
                      min: 0.0,
                      max: 150.0,
                      step: 20.0,
                    ),
                    const SizedBox(height: 4),
                    const SettingsHintText('拖动滑块调整控制栏高度'),
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