import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'settings_hint_text.dart';

class ControlBarSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final VideoPlayerState videoState;
  final ValueChanged<bool>? onHoverChanged;

  const ControlBarSettingsMenu({
    super.key,
    required this.onClose,
    required this.videoState,
    this.onHoverChanged,
  });

  @override
  State<ControlBarSettingsMenu> createState() => _ControlBarSettingsMenuState();
}

class _ControlBarSettingsMenuState extends State<ControlBarSettingsMenu> {
  Widget _buildColorOption(int colorValue, String label) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final isSelected = videoState.minimalProgressBarColor.value == colorValue;
        return GestureDetector(
          onTap: () {
            videoState.setMinimalProgressBarColor(colorValue);
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(colorValue),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.3),
                width: isSelected ? 3 : 1,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: Color(colorValue).withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return BaseSettingsMenu(
          title: '控件设置',
          onClose: widget.onClose,
          onHoverChanged: widget.onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 底部进度条开关
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '底部进度条',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: videoState.minimalProgressBarEnabled,
                          onChanged: (value) {
                            videoState.setMinimalProgressBarEnabled(value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const SettingsHintText('显示底部细进度条'),
                    const SizedBox(height: 20),
                    
                    // 弹幕密度曲线开关
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '弹幕密度曲线',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: widget.videoState.showDanmakuDensityChart,
                          onChanged: (value) {
                            widget.videoState.setShowDanmakuDensityChart(value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const SettingsHintText('显示播放器底部弹幕密度曲线'),
                    if (videoState.minimalProgressBarEnabled) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '进度条和曲线颜色',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 颜色选择器
                      Wrap(
                        spacing: 12,
                        children: [
                          _buildColorOption(0xFFFF7274, '红色'), // #ff7274
                          _buildColorOption(0xFF40C7FF, '蓝色'), // #40c7ff
                          _buildColorOption(0xFF6DFF69, '绿色'), // #6dff69
                          _buildColorOption(0xFF4CFFB1, '青色'), // #4cffb1
                          _buildColorOption(0xFFFFFFFF, '白色'), // #ffffff
                        ],
                      ),
                    ],
                    
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
