import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'base_settings_menu.dart';
import 'settings_hint_text.dart';
import 'settings_slider.dart';

class SubtitleSettingsMenu extends StatelessWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const SubtitleSettingsMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SubtitleSettingsPaneController>(
      builder: (context, controller, child) {
        final double scale = controller.subtitleScale;
        return BaseSettingsMenu(
          title: '字幕设置',
          onClose: onClose,
          onHoverChanged: onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsSlider(
                      value: scale,
                      onChanged: controller.setSubtitleScale,
                      label: '字幕大小',
                      displayTextBuilder: (v) =>
                          '${(v * 100).round()}%',
                      min: controller.minScale,
                      max: controller.maxScale,
                      step: 0.05,
                    ),
                    const SizedBox(height: 4),
                    const SettingsHintText('仅对 Media Kit + libass 字幕渲染生效'),
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
