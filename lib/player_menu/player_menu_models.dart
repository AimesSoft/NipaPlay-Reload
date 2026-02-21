import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';

/// 播放器菜单中可能出现的功能面板 ID
enum PlayerMenuPaneId {
  subtitleSettings,
  subtitleTracks,
  subtitleList,
  audioTracks,
  danmakuSettings,
  danmakuTracks,
  danmakuList,
  danmakuOffset,
  controlBarSettings,
  playbackRate,
  playlist,
  jellyfinQuality,
  playbackInfo,
  seekStep,
}

/// 菜单分组，UI 层可以根据分组决定布局或标题
enum PlayerMenuCategory {
  playbackControl,
  video,
  audio,
  subtitle,
  danmaku,
  player,
  streaming,
  info,
}

/// UI 图标的抽象标识，由各主题自行映射到具体 Icon
enum PlayerMenuIconToken {
  subtitleSettings,
  subtitles,
  subtitleList,
  audioTrack,
  danmakuSettings,
  danmakuTracks,
  danmakuList,
  danmakuOffset,
  controlBarSettings,
  playbackRate,
  playlist,
  jellyfinQuality,
  playbackInfo,
  seekStep,
}

typedef PlayerMenuVisibilityPredicate = bool Function(PlayerMenuContext context);

/// 用于描述单个菜单项的逻辑信息
class PlayerMenuItemDefinition {
  final PlayerMenuPaneId paneId;
  final PlayerMenuCategory category;
  final PlayerMenuIconToken icon;
  final String title;
  final PlayerMenuVisibilityPredicate? visibilityPredicate;

  const PlayerMenuItemDefinition({
    required this.paneId,
    required this.category,
    required this.icon,
    required this.title,
    this.visibilityPredicate,
  });

  bool isVisible(PlayerMenuContext context) =>
      visibilityPredicate?.call(context) ?? true;
}

/// 菜单逻辑层可用的上下文信息
class PlayerMenuContext {
  final VideoPlayerState videoState;
  final PlayerKernelType kernelType;

  const PlayerMenuContext({
    required this.videoState,
    required this.kernelType,
  });

  bool get supportsAdvancedTracks =>
      kernelType != PlayerKernelType.videoPlayer;

  bool get hasVideo => videoState.hasVideo;

  bool get hasVideoPath => videoState.currentVideoPath != null;

  bool get hasPlaylist =>
      videoState.currentVideoPath != null || videoState.animeId != null;

  bool get isServerStreaming =>
      (videoState.currentVideoPath?.startsWith('jellyfin://') ?? false) ||
      (videoState.currentVideoPath?.startsWith('emby://') ?? false);

  bool get isTranscodeEnabledForCurrentSource {
    final path = videoState.currentVideoPath ?? '';
    if (path.startsWith('jellyfin://')) {
      return JellyfinService.instance.isTranscodeEnabled;
    }
    if (path.startsWith('emby://')) {
      return EmbyService.instance.isTranscodeEnabled;
    }
    return true;
  }
}
