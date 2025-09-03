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
  final List<double> _speedBoostOptions = [1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0];
  final TextEditingController _skipSecondsController = TextEditingController();

  @override
  void dispose() {
    _skipSecondsController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 延迟初始化输入框值，等待Consumer构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final videoState = Provider.of<VideoPlayerState>(context, listen: false);
        _skipSecondsController.text = videoState.skipSeconds.toString();
      }
    });
  }

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
              // 快进快退时间设置
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
              
              // 快进快退时间选项列表
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
              
              const Divider(color: Colors.white24, height: 1),
              
              // 长按倍速播放设置
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '长按右键倍速',
                          locale: Locale("zh", "CN"),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${videoState.speedBoostRate}x',
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
                      '设置长按右方向键时的播放倍速',
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
              
              // 倍速选项列表
              ..._speedBoostOptions.map((speed) {
                final isSelected = videoState.speedBoostRate == speed;
                
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      videoState.setSpeedBoostRate(speed);
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
                            '${speed}x',
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
              
              const Divider(color: Colors.white24, height: 1),
              
              // 跳过时间设置
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '跳过时间',
                          locale: Locale("zh", "CN"),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${videoState.skipSeconds}秒',
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
                      '设置跳过功能的跳跃时间',
                      locale: Locale("zh", "CN"),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 加减号控制和输入框
                    Row(
                      children: [
                        // 减少按钮
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              final newValue = (videoState.skipSeconds - 10).clamp(10, 600);
                              videoState.setSkipSeconds(newValue);
                              _skipSecondsController.text = newValue.toString();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30),
                              ),
                              child: const Icon(
                                Icons.remove,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 输入框
                        Expanded(
                          child: TextField(
                            controller: _skipSecondsController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.white30),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.white30),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.white70),
                              ),
                              filled: true,
                              fillColor: Colors.white10,
                              suffixText: '秒',
                              suffixStyle: const TextStyle(color: Colors.white54),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onChanged: (value) {
                              final intValue = int.tryParse(value);
                              if (intValue != null && intValue >= 10 && intValue <= 600) {
                                videoState.setSkipSeconds(intValue);
                              }
                            },
                            onTap: () {
                              if (_skipSecondsController.text.isEmpty) {
                                _skipSecondsController.text = videoState.skipSeconds.toString();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 增加按钮
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              final newValue = (videoState.skipSeconds + 10).clamp(10, 600);
                              videoState.setSkipSeconds(newValue);
                              _skipSecondsController.text = newValue.toString();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30),
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
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