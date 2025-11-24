import 'package:nipaplay/player_menu/player_menu_models.dart';

class PlayerMenuDefinitionBuilder {
  final PlayerMenuContext context;
  final Set<PlayerMenuPaneId>? _supportedPaneIds;

  const PlayerMenuDefinitionBuilder({
    required this.context,
    Set<PlayerMenuPaneId>? supportedPaneIds,
  }) : _supportedPaneIds = supportedPaneIds;

  List<PlayerMenuItemDefinition> build() {
    final definitions = <PlayerMenuItemDefinition>[
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.subtitleTracks,
        category: PlayerMenuCategory.subtitle,
        icon: PlayerMenuIconToken.subtitles,
        title: '字幕轨道',
        visibilityPredicate: (ctx) =>
            ctx.supportsAdvancedTracks && ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.subtitleList,
        category: PlayerMenuCategory.subtitle,
        icon: PlayerMenuIconToken.subtitleList,
        title: '字幕列表',
        visibilityPredicate: (ctx) =>
            ctx.supportsAdvancedTracks && ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.audioTracks,
        category: PlayerMenuCategory.audio,
        icon: PlayerMenuIconToken.audioTrack,
        title: '音频轨道',
        visibilityPredicate: (ctx) =>
            ctx.supportsAdvancedTracks && ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.danmakuSettings,
        category: PlayerMenuCategory.danmaku,
        icon: PlayerMenuIconToken.danmakuSettings,
        title: '弹幕设置',
        visibilityPredicate: (ctx) => ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.danmakuTracks,
        category: PlayerMenuCategory.danmaku,
        icon: PlayerMenuIconToken.danmakuTracks,
        title: '弹幕轨道',
        visibilityPredicate: (ctx) => ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.danmakuList,
        category: PlayerMenuCategory.danmaku,
        icon: PlayerMenuIconToken.danmakuList,
        title: '弹幕列表',
        visibilityPredicate: (ctx) => ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.danmakuOffset,
        category: PlayerMenuCategory.danmaku,
        icon: PlayerMenuIconToken.danmakuOffset,
        title: '弹幕偏移',
        visibilityPredicate: (ctx) => ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.controlBarSettings,
        category: PlayerMenuCategory.player,
        icon: PlayerMenuIconToken.controlBarSettings,
        title: '控件设置',
        visibilityPredicate: (ctx) => ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.playbackRate,
        category: PlayerMenuCategory.video,
        icon: PlayerMenuIconToken.playbackRate,
        title: '倍速设置',
        visibilityPredicate: (ctx) => ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.jellyfinQuality,
        category: PlayerMenuCategory.streaming,
        icon: PlayerMenuIconToken.jellyfinQuality,
        title: '清晰度',
        visibilityPredicate: (ctx) => ctx.isServerStreaming,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.playbackInfo,
        category: PlayerMenuCategory.info,
        icon: PlayerMenuIconToken.playbackInfo,
        title: '播放信息',
        visibilityPredicate: (ctx) => ctx.hasVideoPath,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.seekStep,
        category: PlayerMenuCategory.playbackControl,
        icon: PlayerMenuIconToken.seekStep,
        title: '播放设置',
        visibilityPredicate: (ctx) => ctx.hasVideo,
      ),
      PlayerMenuItemDefinition(
        paneId: PlayerMenuPaneId.playlist,
        category: PlayerMenuCategory.player,
        icon: PlayerMenuIconToken.playlist,
        title: '播放列表',
        visibilityPredicate: (ctx) => ctx.hasPlaylist,
      ),
    ];

    return definitions.where((definition) {
      if (_supportedPaneIds != null &&
          !_supportedPaneIds!.contains(definition.paneId)) {
        return false;
      }
      return definition.isVisible(context);
    }).toList();
  }
}
