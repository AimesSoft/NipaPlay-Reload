import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'subtitle_tracks_menu.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'control_bar_settings_menu.dart';
import 'danmaku_settings_menu.dart';
import 'audio_tracks_menu.dart';
import 'danmaku_list_menu.dart';
import 'danmaku_tracks_menu.dart';
import 'subtitle_list_menu.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'playlist_menu.dart';
import 'playback_rate_menu.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'danmaku_offset_menu.dart';
import 'jellyfin_quality_menu.dart';
import 'playback_info_menu.dart';
import 'seek_step_menu.dart';
import 'package:nipaplay/player_menu/player_menu_definition_builder.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';

class VideoSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const VideoSettingsMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
  });

  @override
  State<VideoSettingsMenu> createState() => _VideoSettingsMenuState();
}

class _VideoSettingsMenuState extends State<VideoSettingsMenu> {
  final Map<PlayerMenuPaneId, OverlayEntry> _paneOverlays = {};
  PlayerMenuPaneId? _activePaneId;
  late final VideoPlayerState videoState;
  late final PlayerKernelType _currentKernelType;

  @override
  void initState() {
    super.initState();
    videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _currentKernelType = PlayerFactory.getKernelType();
  }

  void _handleItemTap(PlayerMenuPaneId paneId) {
    if (_activePaneId == paneId) {
      _closePane(paneId);
      return;
    }
    _closeAllOverlays();
    final overlayEntry = _createOverlayForPane(paneId);
    _paneOverlays[paneId] = overlayEntry;
    Overlay.of(context).insert(overlayEntry);
    if (mounted) {
      setState(() {
        _activePaneId = paneId;
      });
    } else {
      _activePaneId = paneId;
    }
  }

  OverlayEntry _createOverlayForPane(PlayerMenuPaneId paneId) {
    late final Widget child;
    switch (paneId) {
      case PlayerMenuPaneId.subtitleTracks:
        child = SubtitleTracksMenu(
          onClose: () => _closePane(PlayerMenuPaneId.subtitleTracks),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.subtitleList:
        child = SubtitleListMenu(
          onClose: () => _closePane(PlayerMenuPaneId.subtitleList),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.audioTracks:
        child = AudioTracksMenu(
          onClose: () => _closePane(PlayerMenuPaneId.audioTracks),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuSettings:
        child = DanmakuSettingsMenu(
          onClose: () => _closePane(PlayerMenuPaneId.danmakuSettings),
          videoState: videoState,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuTracks:
        child = DanmakuTracksMenu(
          onClose: () => _closePane(PlayerMenuPaneId.danmakuTracks),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuList:
        child = DanmakuListMenu(
          videoState: videoState,
          onClose: () => _closePane(PlayerMenuPaneId.danmakuList),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuOffset:
        child = DanmakuOffsetMenu(
          onClose: () => _closePane(PlayerMenuPaneId.danmakuOffset),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.controlBarSettings:
        child = ControlBarSettingsMenu(
          onClose: () => _closePane(PlayerMenuPaneId.controlBarSettings),
          videoState: videoState,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.playbackRate:
        child = ChangeNotifierProvider(
          create: (_) => PlaybackRatePaneController(videoState: videoState),
          child: PlaybackRateMenu(
            onClose: () => _closePane(PlayerMenuPaneId.playbackRate),
            onHoverChanged: widget.onHoverChanged,
          ),
        );
        break;
      case PlayerMenuPaneId.playlist:
        child = PlaylistMenu(
          onClose: () => _closePane(PlayerMenuPaneId.playlist),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.jellyfinQuality:
        child = JellyfinQualityMenu(
          onClose: () => _closePane(PlayerMenuPaneId.jellyfinQuality),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.playbackInfo:
        child = PlaybackInfoMenu(
          onClose: () => _closePane(PlayerMenuPaneId.playbackInfo),
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.seekStep:
        child = ChangeNotifierProvider(
          create: (_) => SeekStepPaneController(videoState: videoState),
          child: SeekStepMenu(
            onClose: () => _closePane(PlayerMenuPaneId.seekStep),
            onHoverChanged: widget.onHoverChanged,
          ),
        );
        break;
    }

    return OverlayEntry(builder: (context) => child);
  }

  void _closePane(PlayerMenuPaneId paneId) {
    final entry = _paneOverlays.remove(paneId);
    entry?.remove();
    if (_activePaneId == paneId) {
      if (mounted) {
        setState(() {
          _activePaneId = null;
        });
      } else {
        _activePaneId = null;
      }
    }
  }

  void _closeAllOverlays() {
    for (final entry in _paneOverlays.values) {
      entry.remove();
    }
    _paneOverlays.clear();
    if (mounted) {
      setState(() {
        _activePaneId = null;
      });
    } else {
      _activePaneId = null;
    }
  }

  @override
  void dispose() {
    for (final entry in _paneOverlays.values) {
      entry.remove();
    }
    _paneOverlays.clear();
    super.dispose();
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
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final backgroundColor = isDarkMode 
            ? const Color.fromARGB(255, 130, 130, 130).withOpacity(0.5)
            : const Color.fromARGB(255, 193, 193, 193).withOpacity(0.5);
        final borderColor = Colors.white.withOpacity(0.5);

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
                      _closeAllOverlays();
                      widget.onClose();
                    },
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  top: globals.isPhone ? 10 : 80,
                  child: Container(
                    width: 200,
                    constraints: BoxConstraints(
                      maxHeight: globals.isPhone 
                          ? MediaQuery.of(context).size.height - 120 
                          : MediaQuery.of(context).size.height - 200,
                    ),
                    child: MouseRegion(
                      onEnter: (_) => videoState.setControlsHovered(true),
                      onExit: (_) => videoState.setControlsHovered(false),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: backgroundColor,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: borderColor,
                                width: 0.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: borderColor,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Text(
                                        '设置',
                                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Spacer(),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: menuItems
                                          .map((item) => _buildSettingsItem(item))
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
                color: Colors.white.withOpacity(0.5),
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
