import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoAudioTracksPane extends StatelessWidget {
  const CupertinoAudioTracksPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
    final List<PlayerAudioStreamInfo>? audioTracks =
        videoState.player.mediaInfo.audio;

    if ((useServerTracks && serverTracks.isEmpty) &&
        (audioTracks == null || audioTracks.isEmpty)) {
      return _buildEmptyPlaceholder(context);
    }

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
      return CupertinoBottomSheetContentLayout(
        sliversBuilder: (context, topSpacing) => [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '音频轨道',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navTitleTextStyle
                        .copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '选择希望使用的音轨语言或关闭其他音轨',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .textStyle
                        .copyWith(
                          fontSize: 13,
                          color:
                              CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed([
                CupertinoListSection.insetGrouped(
                  header: const Text('可用音轨'),
                  children: [
                    for (final track in serverTracks)
                      _buildServerTrackTile(
                        context,
                        track,
                        selectedIndex == track.index,
                      ),
                  ],
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: CupertinoPaneBackButton(onPressed: onBack),
          ),
        ],
      );
    }

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '音频轨道',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .navTitleTextStyle
                      .copyWith(fontSize: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  '选择希望使用的音轨语言或关闭其他音轨',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              CupertinoListSection.insetGrouped(
                header: const Text('可用音轨'),
                children: [
                  for (final entry in audioTracks!.asMap().entries)
                    _buildTrackTile(context, entry.key, entry.value),
                ],
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: onBack),
        ),
      ],
    );
  }

  Widget _buildTrackTile(
    BuildContext context,
    int index,
    PlayerAudioStreamInfo track,
  ) {
    final bool isActive =
        videoState.player.activeAudioTracks.contains(index);
    final Color activeColor =
        CupertinoTheme.of(context).primaryColor.withOpacity(0.9);
    final String title = _resolveTrackTitle(index, track);
    final String language = _resolveLanguage(track.language);

    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(vertical: 8),
      title: Text(
        title,
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
      ),
      subtitle: Text(
        '语言：$language',
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
      ),
      trailing: isActive
          ? Icon(
              CupertinoIcons.check_mark_circled_solid,
              color: activeColor,
            )
          : null,
      onTap: () {
        if (isActive) return;
        videoState.player.activeAudioTracks = [index];
      },
    );
  }

  Widget _buildServerTrackTile(
    BuildContext context,
    _ServerAudioTrack track,
    bool isActive,
  ) {
    final Color activeColor =
        CupertinoTheme.of(context).primaryColor.withOpacity(0.9);
    String title = track.title?.isNotEmpty == true
        ? track.title!
        : '轨道 ${track.index + 1}';
    if (track.codec != null && track.codec!.isNotEmpty) {
      title = '$title (${track.codec})';
    }
    final String language = _resolveLanguage(track.language);

    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(vertical: 8),
      title: Text(
        title,
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
      ),
      subtitle: Text(
        '语言：$language',
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
      ),
      trailing: isActive
          ? Icon(
              CupertinoIcons.check_mark_circled_solid,
              color: activeColor,
            )
          : null,
      onTap: () async {
        if (isActive) return;
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
            serverSubtitleIndex:
                videoState.getJellyfinServerSubtitleSelection(itemId),
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
      },
    );
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

  Widget _buildEmptyPlaceholder(BuildContext context) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.speaker_slash,
                  size: 42,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
                const SizedBox(height: 12),
                Text(
                  '未检测到可切换的音频轨道',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 16,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '请确认当前视频包含多个音轨',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 13,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: onBack),
        ),
      ],
    );
  }

  String _resolveTrackTitle(int index, PlayerAudioStreamInfo track) {
    String baseTitle = track.title ?? '轨道 ${index + 1}';
    final String? metadataTitle = track.metadata['title'];
    if ((baseTitle.startsWith('轨道') || baseTitle.isEmpty) &&
        metadataTitle != null &&
        metadataTitle.isNotEmpty) {
      baseTitle = metadataTitle;
    }

    final String codecName = track.codec.name ?? '';
    if (codecName.isNotEmpty && codecName != 'Unknown Audio Codec') {
      return '$baseTitle ($codecName)';
    }
    return baseTitle;
  }

  String _resolveLanguage(String? language) {
    if (language == null || language.isEmpty) return '未知';

    const Map<String, String> languageCodes = {
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

    for (final entry in languageCodes.entries) {
      if (language.toLowerCase().contains(entry.key)) {
        return entry.value;
      }
    }

    final List<MapEntry<RegExp, String>> languagePatterns = [
      MapEntry(RegExp(r'chi|chs|zh|中文|简体|繁体', caseSensitive: false), '中文'),
      MapEntry(RegExp(r'eng|english|英文', caseSensitive: false), '英文'),
      MapEntry(RegExp(r'jpn|ja|日文|japanese', caseSensitive: false), '日语'),
      MapEntry(RegExp(r'kor|ko|韩', caseSensitive: false), '韩语'),
      MapEntry(RegExp(r'fra|fr|法', caseSensitive: false), '法语'),
      MapEntry(RegExp(r'ger|de|德', caseSensitive: false), '德语'),
      MapEntry(RegExp(r'spa|es|西班牙', caseSensitive: false), '西班牙语'),
      MapEntry(RegExp(r'ita|it|意大利', caseSensitive: false), '意大利语'),
      MapEntry(RegExp(r'rus|ru|俄', caseSensitive: false), '俄语'),
    ];

    for (final matcher in languagePatterns) {
      if (matcher.key.hasMatch(language)) {
        return matcher.value;
      }
    }

    return language;
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
