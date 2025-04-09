import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'tooltip_bubble.dart';
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