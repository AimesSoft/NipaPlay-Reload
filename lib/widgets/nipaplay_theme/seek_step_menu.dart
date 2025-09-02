import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';

class SeekStepMenu extends StatefulWidget {
  final VoidCallback onClose;

  const SeekStepMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<SeekStepMenu> createState() => _SeekStepMenuState();
}

class _SeekStepMenuState extends State<SeekStepMenu> {
  final List<int> _seekStepOptions = [5, 10, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return BaseSettingsMenu(
          title: '播放设置',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 当前设置显示
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '快进快退时间',
                          locale: Locale("zh", "CN"),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${videoState.seekStepSeconds}秒',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '设置快进和快退的跳跃时间',
                      locale: Locale("zh", "CN"),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              
              const Divider(color: Colors.white24, height: 1),
              
              // 时间选项列表
              ..._seekStepOptions.map((seconds) {
                final isSelected = videoState.seekStepSeconds == seconds;
                
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      videoState.setSeekStepSeconds(seconds);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: isSelected ? Colors.white : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${seconds}秒',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}