import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'base_settings_menu.dart';

class AudioTracksMenu extends StatelessWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const AudioTracksMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
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

  List<_ServerAudioTrack> _getServerAudioTracks(VideoPlayerState videoState) {
    final session = videoState.currentPlaybackSession;
    final source = session?.selectedSource ??
        (session?.mediaSources.isNotEmpty == true
            ? session!.mediaSources.first
            : null);
    final streams = source?.mediaStreams ?? const [];
    final tracks = <_ServerAudioTrack>[];
    for (final stream in streams) {
      if (stream['Type']?.toString() != 'Audio') continue;
      final index = stream['Index'];
      final parsedIndex = index is int
          ? index
          : int.tryParse(index?.toString() ?? '');
      if (parsedIndex == null) continue;
      tracks.add(
        _ServerAudioTrack(
          index: parsedIndex,
          title: stream['Title']?.toString(),
          language: stream['Language']?.toString(),
          codec: stream['Codec']?.toString(),
          isDefault: stream['IsDefault'] == true,
        ),
      );
    }
    return tracks;
  }

  Future<void> _switchServerAudioTrack({
    required BuildContext context,
    required VideoPlayerState videoState,
    required _ServerAudioTrack track,
  }) async {
    final path = videoState.currentVideoPath;
    if (path == null) return;
    if (path.startsWith('jellyfin://')) {
      final itemId = path.replaceFirst('jellyfin://', '');
      final jellyfinProvider =
          Provider.of<JellyfinTranscodeProvider>(context, listen: false);
      await jellyfinProvider.initialize();
      videoState.setJellyfinServerAudioSelection(itemId, track.index);
      await videoState.reloadCurrentJellyfinStream(
        quality: jellyfinProvider.currentVideoQuality,
        serverSubtitleIndex: videoState.getJellyfinServerSubtitleSelection(
          itemId,
        ),
        burnInSubtitle: videoState.getJellyfinServerSubtitleBurnIn(itemId),
        audioStreamIndex: track.index,
      );
      return;
    }
    if (path.startsWith('emby://')) {
      final embyPath = path.replaceFirst('emby://', '');
      final parts = embyPath.split('/');
      final itemId = parts.isNotEmpty ? parts.last : embyPath;
      final embyProvider =
          Provider.of<EmbyTranscodeProvider>(context, listen: false);
      await embyProvider.initialize();
      videoState.setEmbyServerAudioSelection(itemId, track.index);
      await videoState.reloadCurrentEmbyStream(
        quality: embyProvider.currentVideoQuality,
        serverSubtitleIndex: videoState.getEmbyServerSubtitleSelection(itemId),
        burnInSubtitle: videoState.getEmbyServerSubtitleBurnIn(itemId),
        audioStreamIndex: track.index,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final path = videoState.currentVideoPath ?? '';
        final isJellyfin = path.startsWith('jellyfin://');
        final isEmby = path.startsWith('emby://');
        final isServerStream = isJellyfin || isEmby;
        final useServerTracks = (isJellyfin &&
                JellyfinService.instance.isTranscodeEnabled) ||
            (isEmby && EmbyService.instance.isTranscodeEnabled);
        final serverTracks = useServerTracks
            ? _getServerAudioTracks(videoState)
            : <_ServerAudioTrack>[];
        final audioTracks = videoState.player.mediaInfo.audio;
        if (isServerStream && useServerTracks && serverTracks.isNotEmpty) {
          int? selectedIndex;
          if (isJellyfin) {
            final itemId = path.replaceFirst('jellyfin://', '');
            selectedIndex = videoState.getJellyfinServerAudioSelection(itemId);
            selectedIndex ??= serverTracks
                .firstWhere((t) => t.isDefault, orElse: () => serverTracks.first)
                .index;
          } else if (isEmby) {
            final embyPath = path.replaceFirst('emby://', '');
            final parts = embyPath.split('/');
            final itemId = parts.isNotEmpty ? parts.last : embyPath;
            selectedIndex = videoState.getEmbyServerAudioSelection(itemId);
            selectedIndex ??= serverTracks
                .firstWhere((t) => t.isDefault, orElse: () => serverTracks.first)
                .index;
          }
          return BaseSettingsMenu(
            title: '音频轨道',
            onClose: onClose,
            onHoverChanged: onHoverChanged,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: serverTracks.map((track) {
                final isActive = track.index == selectedIndex;
                final language = track.language == null ||
                        track.language!.isEmpty ||
                        track.language == '未知'
                    ? '未知'
                    : _getLanguageName(track.language!);
                String title = track.title?.isNotEmpty == true
                    ? track.title!
                    : '轨道 ${track.index + 1}';
                if (track.codec != null && track.codec!.isNotEmpty) {
                  title += ' (${track.codec})';
                }
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      if (isActive) return;
                      await _switchServerAudioTrack(
                        context: context,
                        videoState: videoState,
                        track: track,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withOpacity(0.1)
                            : Colors.transparent,
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
                            isActive
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
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
                                  locale: const Locale("zh", "Hans"),
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
              }).toList(),
            ),
          );
        }
        return BaseSettingsMenu(
          title: '音频轨道',
          onClose: onClose,
          onHoverChanged: onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (audioTracks != null)
                ...audioTracks.asMap().entries.map((entry) {
                  final index = entry.key;
                  final track = entry.value; // track is PlayerAudioStreamInfo
                  final isActive = videoState.player.activeAudioTracks.contains(index);
                  
                  // 从PlayerAudioStreamInfo获取标题和语言
                  String title = track.title ?? '轨道 $index';
                  String language = track.language ?? '未知';

                  // 如果语言不是"未知"，则尝试获取更友好的名称
                  if (language != '未知') {
                    language = _getLanguageName(language);
                  }
                  // 如果标题是 "Audio track X" 并且元数据中有标题，优先使用元数据的标题
                  if (title == '轨道 $index' && track.metadata['title'] != null && track.metadata['title']!.isNotEmpty) {
                    title = track.metadata['title']!;
                  }

                  // 如果有编解码器名称，可以附加到标题上
                  if (track.codec.name != null && track.codec.name!.isNotEmpty && track.codec.name != 'Unknown Audio Codec') {
                    title += " (${track.codec.name})";
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
                                    locale:Locale("zh-Hans","zh"),
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

class _ServerAudioTrack {
  final int index;
  final String? title;
  final String? language;
  final String? codec;
  final bool isDefault;

  const _ServerAudioTrack({
    required this.index,
    this.title,
    this.language,
    this.codec,
    this.isDefault = false,
  });
}
