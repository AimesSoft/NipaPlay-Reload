import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'subtitle_tracks_menu.dart';
import 'control_bar_settings_menu.dart';
import 'danmaku_settings_menu.dart';
import 'audio_tracks_menu.dart';
import 'danmaku_list_menu.dart';
import 'danmaku_tracks_menu.dart';
import 'subtitle_list_menu.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'playlist_menu.dart';
import 'playback_rate_menu.dart';
import 'danmaku_offset_menu.dart';
import 'jellyfin_quality_menu.dart';
import 'playback_info_menu.dart';
import 'seek_step_menu.dart';
import 'package:nipaplay/player_menu/player_menu_definition_builder.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'base_settings_menu.dart';

class VideoSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;
  final Rect? anchorRect;

  const VideoSettingsMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
    this.anchorRect,
  });

  @override
  State<VideoSettingsMenu> createState() => _VideoSettingsMenuState();
}

class _VideoSettingsMenuState extends State<VideoSettingsMenu> {
  PlayerMenuPaneId? _activePaneId;
  late final VideoPlayerState videoState;
  late final PlayerKernelType _currentKernelType;
  static const double _menuWidth = 300;
  static const double _menuRightOffset = 20;

  @override
  void initState() {
    super.initState();
    videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _currentKernelType = PlayerFactory.getKernelType();
    videoState.setControlsVisibilityLocked(true);
  }

  @override
  void dispose() {
    videoState.setControlsVisibilityLocked(false);
    super.dispose();
  }

  void _handleItemTap(PlayerMenuPaneId paneId) {
    if (mounted) {
      setState(() {
        _activePaneId = _activePaneId == paneId ? null : paneId;
      });
    } else {
      _activePaneId = _activePaneId == paneId ? null : paneId;
    }
  }

  void _closeActivePane() {
    if (!mounted) {
      _activePaneId = null;
      return;
    }
    setState(() {
      _activePaneId = null;
    });
  }

  SettingsMenuScope _wrapMenu({required bool showBackItem, required Widget child}) {
    return SettingsMenuScope(
      width: _menuWidth,
      rightOffset: _menuRightOffset,
      useBackButton: showBackItem,
      showHeader: false,
      showBackItem: showBackItem,
      lockControlsVisible: true,
      anchorRect: widget.anchorRect,
      showPointer: widget.anchorRect != null,
      child: child,
    );
  }

  Widget _buildPane(PlayerMenuPaneId paneId) {
    late final Widget child;
    switch (paneId) {
      case PlayerMenuPaneId.subtitleTracks:
        child = SubtitleTracksMenu(
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.subtitleList:
        child = SubtitleListMenu(
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.audioTracks:
        child = AudioTracksMenu(
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuSettings:
        child = DanmakuSettingsMenu(
          onClose: _closeActivePane,
          videoState: videoState,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuTracks:
        child = DanmakuTracksMenu(
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuList:
        child = DanmakuListMenu(
          videoState: videoState,
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuOffset:
        child = DanmakuOffsetMenu(
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.controlBarSettings:
        child = ControlBarSettingsMenu(
          onClose: _closeActivePane,
          videoState: videoState,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.playbackRate:
        child = ChangeNotifierProvider(
          create: (_) => PlaybackRatePaneController(videoState: videoState),
          child: PlaybackRateMenu(
            onClose: _closeActivePane,
            onHoverChanged: widget.onHoverChanged,
          ),
        );
        break;
      case PlayerMenuPaneId.playlist:
        child = PlaylistMenu(
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.jellyfinQuality:
        child = JellyfinQualityMenu(
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.playbackInfo:
        child = PlaybackInfoMenu(
          onClose: _closeActivePane,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.seekStep:
        child = ChangeNotifierProvider(
          create: (_) => SeekStepPaneController(videoState: videoState),
          child: SeekStepMenu(
            onClose: _closeActivePane,
            onHoverChanged: widget.onHoverChanged,
          ),
        );
        break;
    }

    return _wrapMenu(showBackItem: true, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final menuItems = PlayerMenuDefinitionBuilder(
          context: PlayerMenuContext(
            videoState: videoState,
            kernelType: _currentKernelType,
          ),
        ).build();
        final Widget menuContent = _activePaneId == null
            ? _wrapMenu(
                showBackItem: false,
                child: BaseSettingsMenu(
                  title: '设置',
                  width: _menuWidth,
                  rightOffset: _menuRightOffset,
                  onHoverChanged: widget.onHoverChanged,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: menuItems
                        .map((item) => _buildSettingsItem(item))
                        .toList(),
                  ),
                ),
              )
            : _buildPane(_activePaneId!);
        return Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      _closeActivePane();
                      widget.onClose();
                    },
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                menuContent,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsItem(PlayerMenuItemDefinition item) {
    final bool isActive = _activePaneId == item.paneId;

    return Material(
      color: isActive ? Colors.white.withOpacity(0.15) : Colors.transparent,
      child: InkWell(
        onTap: () => _handleItemTap(item.paneId),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.2),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _resolveIcon(item.icon),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Icon(
                isActive
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _resolveIcon(PlayerMenuIconToken icon) {
    switch (icon) {
      case PlayerMenuIconToken.subtitles:
        return Icons.subtitles;
      case PlayerMenuIconToken.subtitleList:
        return Icons.list;
      case PlayerMenuIconToken.audioTrack:
        return Icons.audiotrack;
      case PlayerMenuIconToken.danmakuSettings:
        return Icons.text_fields;
      case PlayerMenuIconToken.danmakuTracks:
        return Icons.track_changes;
      case PlayerMenuIconToken.danmakuList:
        return Icons.list_alt_outlined;
      case PlayerMenuIconToken.danmakuOffset:
        return Icons.schedule;
      case PlayerMenuIconToken.controlBarSettings:
        return Icons.height;
      case PlayerMenuIconToken.playbackRate:
        return Icons.speed;
      case PlayerMenuIconToken.playlist:
        return Icons.playlist_play;
      case PlayerMenuIconToken.jellyfinQuality:
        return Icons.hd;
      case PlayerMenuIconToken.playbackInfo:
        return Icons.info_outline;
      case PlayerMenuIconToken.seekStep:
        return Icons.settings;
    }
  }
}
