import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class FluentAudioTracksMenu extends StatelessWidget {
  final VideoPlayerState videoState;

  const FluentAudioTracksMenu({
    super.key,
    required this.videoState,
  });

  String _getLanguageName(String language) {
    // 语言代码映射
    final Map<String, String> languageCodes = {
      'chi': '中文',
      'eng': '英文',
      'jpn': '日语',
      'kor': '韩语',
      'fra': '法语',
      'deu': '德语',
      'spa': '西班牙语',
      'ita': '意大利语',
      'rus': '俄语',
    };
    
    // 常见的语言标识符
    final Map<String, String> languagePatterns = {
      r'chi|chs|zh|中文|简体|繁体|chi.*?simplified|chinese': '中文',
      r'eng|en|英文|english': '英文',
      r'jpn|ja|日文|japanese': '日语',
      r'kor|ko|韩文|korean': '韩语',
      r'fra|fr|法文|french': '法语',
      r'ger|de|德文|german': '德语',
      r'spa|es|西班牙文|spanish': '西班牙语',
      r'ita|it|意大利文|italian': '意大利语',
      r'rus|ru|俄文|russian': '俄语',
    };

    // 首先检查语言代码映射
    final mappedLanguage = languageCodes[language.toLowerCase()];
    if (mappedLanguage != null) {
      return mappedLanguage;
    }

    // 然后检查语言标识符
    for (final entry in languagePatterns.entries) {
      final pattern = RegExp(entry.key, caseSensitive: false);
      if (pattern.hasMatch(language.toLowerCase())) {
        return entry.value;
      }
    }

    return language;
  }

  @override
  Widget build(BuildContext context) {
    final audioTracks = videoState.player.mediaInfo.audio;
    
    if (audioTracks == null || audioTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.volume3,
              size: 48,
              color: FluentTheme.of(context).resources.textFillColorSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              '未找到音频轨道',
              style: FluentTheme.of(context).typography.bodyLarge?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前视频没有可选择的音频轨道',
              style: FluentTheme.of(context).typography.caption?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 提示信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '可用音频轨道',
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
              const SizedBox(height: 4),
              Text(
                '选择你想要的音频轨道语言',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorTertiary,
                ),
              ),
            ],
          ),
        ),
        
        // 分隔线
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        
        // 音频轨道列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: audioTracks.length,
            itemBuilder: (context, index) {
              final track = audioTracks[index];
              final isActive = videoState.player.activeAudioTracks.contains(index);
              
              // 从PlayerAudioStreamInfo获取标题和语言
              String title = track.title ?? '轨道 $index';
              String language = track.language ?? '未知';

              // 如果语言不是"未知"，则尝试获取更友好的名称
              if (language != '未知') {
                language = _getLanguageName(language);
              }
              // 如果标题是 "轨道 X" 并且元数据中有标题，优先使用元数据的标题
              if (title == '轨道 $index' && track.metadata['title'] != null && track.metadata['title']!.isNotEmpty) {
                title = track.metadata['title']!;
              }

              // 如果有编解码器名称，可以附加到标题上
              if (track.codec.name != null && track.codec.name!.isNotEmpty && track.codec.name != 'Unknown Audio Codec') {
                title += " (${track.codec.name})";
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: HoverButton(
                  onPressed: isActive ? null : () {
                    // 切换到指定的音频轨道
                    videoState.player.activeAudioTracks = [index];
                  },
                  builder: (context, states) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                            : states.isHovered
                                ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: isActive
                            ? Border.all(
                                color: FluentTheme.of(context).accentColor,
                                width: 1,
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isActive ? FluentIcons.radio_btn_on : FluentIcons.radio_btn_off,
                            size: 16,
                            color: isActive
                                ? FluentTheme.of(context).accentColor
                                : FluentTheme.of(context).resources.textFillColorPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: FluentTheme.of(context).typography.body?.copyWith(
                                    color: isActive
                                        ? FluentTheme.of(context).accentColor
                                        : FluentTheme.of(context).resources.textFillColorPrimary,
                                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '语言: $language',
                                  style: FluentTheme.of(context).typography.caption?.copyWith(
                                    color: isActive
                                        ? FluentTheme.of(context).accentColor.withValues(alpha: 0.8)
                                        : FluentTheme.of(context).resources.textFillColorSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isActive)
                            Icon(
                              FluentIcons.check_mark,
                              size: 16,
                              color: FluentTheme.of(context).accentColor,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}