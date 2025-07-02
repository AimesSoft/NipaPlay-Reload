import 'package:flutter/material.dart';
import 'dart:ui';
import '../utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'base_settings_menu.dart';

class PlaybackRateMenu extends StatefulWidget {
  final VoidCallback onClose;

  const PlaybackRateMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<PlaybackRateMenu> createState() => _PlaybackRateMenuState();
}

class _PlaybackRateMenuState extends State<PlaybackRateMenu> {
  // 预设的倍速选项
  static const List<double> _speedOptions = [
    0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 5.0
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return BaseSettingsMenu(
          title: '倍速设置',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 当前倍速显示
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '当前倍速',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${videoState.playbackRate}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      videoState.isSpeedBoostActive ? '正在倍速播放' : '点击下方选项或长按屏幕倍速播放',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              
              const Divider(color: Colors.white24, height: 1),
              
              // 倍速选项列表
              ..._speedOptions.map((speed) {
                final isSelected = videoState.playbackRate == speed;
                final isNormalSpeed = speed == 1.0;
                
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      // 设置播放速度（会自动应用到播放器）
                      videoState.setPlaybackRate(speed);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getSpeedIcon(speed, isNormalSpeed),
                            color: isSelected 
                                ? Colors.white 
                                : isNormalSpeed 
                                    ? Colors.white70 
                                    : Colors.white60,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${speed}x ${_getSpeedDescription(speed, isNormalSpeed)}',
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
              
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // 获取圆滑的速度图标
  IconData _getSpeedIcon(double speed, bool isNormalSpeed) {
    if (isNormalSpeed) {
      return Icons.play_circle_outline_rounded;
    } else if (speed < 1.0) {
      return Icons.slow_motion_video_rounded;
    } else if (speed <= 2.0) {
      return Icons.fast_forward_rounded;
    } else {
      return Icons.rocket_launch_rounded;
    }
  }

  // 获取速度描述
  String _getSpeedDescription(double speed, bool isNormalSpeed) {
    if (isNormalSpeed) {
      return '(正常速度)';
    } else if (speed < 1.0) {
      return '(慢速)';
    } else if (speed <= 2.0) {
      return '(快速)';
    } else {
      return '(极速)';
    }
  }
} 