import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/player_menu/player_menu_definition_builder.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_audio_tracks_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_danmaku_list_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_danmaku_offset_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_danmaku_settings_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_danmaku_tracks_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_jellyfin_quality_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playback_info_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playback_rate_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_seek_step_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playlist_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_subtitle_list_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_subtitle_settings_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_subtitle_tracks_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class CupertinoPlayerMenu extends StatelessWidget {
  const CupertinoPlayerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        final menuItems = PlayerMenuDefinitionBuilder(
          context: PlayerMenuContext(
            videoState: videoState,
            kernelType: PlayerFactory.getKernelType(),
          ),
        ).build();
        return _CupertinoPlayerMenuHome(
          items: menuItems,
          onSelect: (item) => _openPane(context, item, videoState),
        );
      },
    );
  }

  Future<void> _openPane(
    BuildContext context,
    PlayerMenuItemDefinition item,
    VideoPlayerState videoState,
  ) {
    return CupertinoBottomSheetPageNavigator.push<void>(
      context,
      title: item.title,
      builder: (_) => _buildPaneContent(item.paneId, videoState),
    );
  }

  Widget _buildPaneContent(
    PlayerMenuPaneId paneId,
    VideoPlayerState videoState,
  ) {
    switch (paneId) {
      case PlayerMenuPaneId.subtitleTracks:
        return CupertinoSubtitleTracksPane(videoState: videoState);
      case PlayerMenuPaneId.subtitleSettings:
        return ChangeNotifierProvider(
          create: (_) => SubtitleSettingsPaneController(videoState: videoState),
          child: const CupertinoSubtitleSettingsPane(),
        );
      case PlayerMenuPaneId.subtitleList:
        return CupertinoSubtitleListPane(videoState: videoState);
      case PlayerMenuPaneId.audioTracks:
        return CupertinoAudioTracksPane(videoState: videoState);
      case PlayerMenuPaneId.danmakuSettings:
        return CupertinoDanmakuSettingsPane(videoState: videoState);
      case PlayerMenuPaneId.danmakuTracks:
        return CupertinoDanmakuTracksPane(videoState: videoState);
      case PlayerMenuPaneId.danmakuList:
        return CupertinoDanmakuListPane(videoState: videoState);
      case PlayerMenuPaneId.danmakuOffset:
        return const CupertinoDanmakuOffsetPane();
      case PlayerMenuPaneId.playbackRate:
        return ChangeNotifierProvider(
          create: (_) => PlaybackRatePaneController(videoState: videoState),
          child: const CupertinoPlaybackRatePane(),
        );
      case PlayerMenuPaneId.seekStep:
        return ChangeNotifierProvider(
          create: (_) => SeekStepPaneController(videoState: videoState),
          child: const CupertinoSeekStepPane(),
        );
      case PlayerMenuPaneId.playbackInfo:
        return CupertinoPlaybackInfoPane(videoState: videoState);
      case PlayerMenuPaneId.playlist:
        return CupertinoPlaylistPane(videoState: videoState);
      case PlayerMenuPaneId.jellyfinQuality:
        return CupertinoJellyfinQualityPane(videoState: videoState);
    }
  }
}

class _CupertinoPlayerMenuHome extends StatelessWidget {
  const _CupertinoPlayerMenuHome({
    required this.items,
    required this.onSelect,
  });

  final List<PlayerMenuItemDefinition> items;
  final ValueChanged<PlayerMenuItemDefinition> onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return CupertinoBottomSheetContentLayout(
        sliversBuilder: (context, topSpacing) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                '当前无可用的设置项',
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
              ),
            ),
          ),
        ],
      );
    }

    final Map<PlayerMenuCategory, List<PlayerMenuItemDefinition>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    final sections = <Widget>[];
    grouped.forEach((category, defs) {
      sections.add(
        AdaptivePlayerMenuSection(
          header: Text(_categoryTitle(category)),
          children: defs
              .map(
                (item) => AdaptivePlayerMenuTile(
                  leading: Icon(
                    _iconFor(item.icon),
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                  title: Text(item.title),
                  trailing: const Icon(CupertinoIcons.chevron_right),
                  onTap: () => onSelect(item),
                ),
              )
              .toList(),
        ),
      );
    });

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.only(top: topSpacing, bottom: 12),
          sliver: SliverList(
            delegate: SliverChildListDelegate(sections),
          ),
        ),
      ],
    );
  }

  String _categoryTitle(PlayerMenuCategory category) {
    switch (category) {
      case PlayerMenuCategory.playbackControl:
        return '播放控制';
      case PlayerMenuCategory.video:
        return '视频';
      case PlayerMenuCategory.audio:
        return '音频';
      case PlayerMenuCategory.subtitle:
        return '字幕';
      case PlayerMenuCategory.danmaku:
        return '弹幕';
      case PlayerMenuCategory.player:
        return '播放器';
      case PlayerMenuCategory.streaming:
        return '串流';
      case PlayerMenuCategory.info:
        return '信息';
    }
  }

  IconData _iconFor(PlayerMenuIconToken token) {
    switch (token) {
      case PlayerMenuIconToken.subtitleSettings:
        return CupertinoIcons.textformat;
      case PlayerMenuIconToken.subtitles:
        return CupertinoIcons.captions_bubble;
      case PlayerMenuIconToken.subtitleList:
        return CupertinoIcons.square_list;
      case PlayerMenuIconToken.audioTrack:
        return CupertinoIcons.music_note;
      case PlayerMenuIconToken.danmakuSettings:
        return CupertinoIcons.bubble_right;
      case PlayerMenuIconToken.danmakuTracks:
        return CupertinoIcons.bubble_right_fill;
      case PlayerMenuIconToken.danmakuList:
        return CupertinoIcons.list_bullet;
      case PlayerMenuIconToken.danmakuOffset:
        return CupertinoIcons.clock;
      case PlayerMenuIconToken.playbackRate:
        return CupertinoIcons.speedometer;
      case PlayerMenuIconToken.playlist:
        return CupertinoIcons.square_stack_3d_up;
      case PlayerMenuIconToken.jellyfinQuality:
        return CupertinoIcons.tv;
      case PlayerMenuIconToken.playbackInfo:
        return CupertinoIcons.info;
      case PlayerMenuIconToken.seekStep:
        return CupertinoIcons.settings;
    }
  }
}
