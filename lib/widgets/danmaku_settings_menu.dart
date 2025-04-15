import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'custom_slider.dart';
import 'base_settings_menu.dart';

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
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
              ),
              // 合并相同弹幕开关
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
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
              ),
              // 弹幕透明度
              Container(
                padding: const EdgeInsets.all(16),
                child: CustomSlider(
                  value: videoState.danmakuOpacity,
                  onChanged: (value) {
                    videoState.setDanmakuOpacity(value);
                  },
                  label: '弹幕透明度',
                  hintText: '拖动滑块调整弹幕透明度',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
} 