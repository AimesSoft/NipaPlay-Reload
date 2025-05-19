import 'package:flutter/material.dart';
import '../utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'base_settings_menu.dart';

class AudioTracksMenu extends StatelessWidget {
  final VoidCallback onClose;

  const AudioTracksMenu({
    super.key,
    required this.onClose,
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
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return BaseSettingsMenu(
          title: '音频轨道',
          onClose: onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (videoState.player.mediaInfo.audio != null)
                ...videoState.player.mediaInfo.audio!.asMap().entries.map((entry) {
                  final index = entry.key;
                  final track = entry.value;
                  final isActive = videoState.player.activeAudioTracks.contains(index);
                  
                  // 尝试从track中提取title和language
                  String title = '轨道 $index';
                  String language = '未知';
                  
                  final fullString = track.toString();
                  if (fullString.contains('metadata: {')) {
                    final metadataStart = fullString.indexOf('metadata: {') + 'metadata: {'.length;
                    final metadataEnd = fullString.indexOf('}', metadataStart);
                    
                    if (metadataEnd > metadataStart) {
                      final metadataStr = fullString.substring(metadataStart, metadataEnd);
                      
                      // 提取title
                      final titleMatch = RegExp(r'title: ([^,}]+)').firstMatch(metadataStr);
                      if (titleMatch != null) {
                        title = titleMatch.group(1)?.trim() ?? title;
                      }
                      
                      // 提取language
                      final languageMatch = RegExp(r'language: ([^,}]+)').firstMatch(metadataStr);
                      if (languageMatch != null) {
                        language = languageMatch.group(1)?.trim() ?? language;
                        // 获取映射后的语言名称
                        language = _getLanguageName(language);
                      }
                    }
                  }
                  
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (isActive) {
                          // 不允许取消选择音频轨道
                          return;
                        } else {
                          videoState.player.activeAudioTracks = [index];
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.white.withOpacity(0.1) : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withOpacity(0.5),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '语言: $language',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
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