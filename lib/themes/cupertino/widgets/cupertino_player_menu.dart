import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Icons, Divider; // for Colors + fallback icons
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/player_menu/player_menu_definition_builder.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/nipaplay/widgets/audio_tracks_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/control_bar_settings_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/danmaku_list_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/danmaku_offset_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/danmaku_settings_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/danmaku_tracks_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/jellyfin_quality_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/playback_info_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/playlist_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/subtitle_list_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/subtitle_tracks_menu.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playback_rate_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_seek_step_sheet.dart';

class CupertinoPlayerMenu extends StatefulWidget {
  final VoidCallback onClose;

  const CupertinoPlayerMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<CupertinoPlayerMenu> createState() => _CupertinoPlayerMenuState();
}

class _CupertinoPlayerMenuState extends State<CupertinoPlayerMenu> {
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

  @override
  void dispose() {
    for (final entry in _paneOverlays.values) {
      entry.remove();
    }
    _paneOverlays.clear();
    super.dispose();
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
    setState(() => _activePaneId = paneId);
  }

  OverlayEntry _createOverlayForPane(PlayerMenuPaneId paneId) {
    late final Widget child;
    switch (paneId) {
      case PlayerMenuPaneId.subtitleTracks:
        child = SubtitleTracksMenu(
          onClose: () => _closePane(PlayerMenuPaneId.subtitleTracks),
        );
        break;
      case PlayerMenuPaneId.subtitleList:
        child = SubtitleListMenu(
          onClose: () => _closePane(PlayerMenuPaneId.subtitleList),
        );
        break;
      case PlayerMenuPaneId.audioTracks:
        child = AudioTracksMenu(
          onClose: () => _closePane(PlayerMenuPaneId.audioTracks),
        );
        break;
      case PlayerMenuPaneId.danmakuSettings:
        child = DanmakuSettingsMenu(
          onClose: () => _closePane(PlayerMenuPaneId.danmakuSettings),
          videoState: videoState,
        );
        break;
      case PlayerMenuPaneId.danmakuTracks:
        child = DanmakuTracksMenu(
          onClose: () => _closePane(PlayerMenuPaneId.danmakuTracks),
        );
        break;
      case PlayerMenuPaneId.danmakuList:
        child = DanmakuListMenu(
          videoState: videoState,
          onClose: () => _closePane(PlayerMenuPaneId.danmakuList),
        );
        break;
      case PlayerMenuPaneId.danmakuOffset:
        child = DanmakuOffsetMenu(
          onClose: () => _closePane(PlayerMenuPaneId.danmakuOffset),
        );
        break;
      case PlayerMenuPaneId.controlBarSettings:
        child = ControlBarSettingsMenu(
          onClose: () => _closePane(PlayerMenuPaneId.controlBarSettings),
          videoState: videoState,
        );
        break;
      case PlayerMenuPaneId.playbackRate:
        child = ChangeNotifierProvider(
          create: (_) => PlaybackRatePaneController(videoState: videoState),
          child: CupertinoPlaybackRateSheet(
            onClose: () => _closePane(PlayerMenuPaneId.playbackRate),
          ),
        );
        break;
      case PlayerMenuPaneId.playlist:
        child = PlaylistMenu(
          onClose: () => _closePane(PlayerMenuPaneId.playlist),
        );
        break;
      case PlayerMenuPaneId.jellyfinQuality:
        child = JellyfinQualityMenu(
          onClose: () => _closePane(PlayerMenuPaneId.jellyfinQuality),
        );
        break;
      case PlayerMenuPaneId.playbackInfo:
        child = PlaybackInfoMenu(
          onClose: () => _closePane(PlayerMenuPaneId.playbackInfo),
        );
        break;
      case PlayerMenuPaneId.seekStep:
        child = ChangeNotifierProvider(
          create: (_) => SeekStepPaneController(videoState: videoState),
          child: CupertinoSeekStepSheet(
            onClose: () => _closePane(PlayerMenuPaneId.seekStep),
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
      setState(() => _activePaneId = null);
    }
  }

  void _closeAllOverlays() {
    for (final entry in _paneOverlays.values) {
      entry.remove();
    }
    _paneOverlays.clear();
    setState(() => _activePaneId = null);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        final menuItems = PlayerMenuDefinitionBuilder(
          context: PlayerMenuContext(
            videoState: videoState,
            kernelType: _currentKernelType,
          ),
        ).build();

        final background = CupertinoTheme.of(context)
            .barBackgroundColor
            .withOpacity(0.9);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _closeAllOverlays();
                  widget.onClose();
                },
                child: Container(
                  color: Colors.black54,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                bottom: true,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(
                          maxHeight: 420,
                        ),
                        color: background,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40,
                              height: 5,
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color:
                                    CupertinoTheme.of(context).primaryColor.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '播放设置',
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .navTitleTextStyle,
                                  ),
                                  const Spacer(),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      _closeAllOverlays();
                                      widget.onClose();
                                    },
                                    child: const Icon(CupertinoIcons.xmark_circle_fill),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, thickness: 0.2),
                            Expanded(
                              child: ListView.separated(
                                itemCount: menuItems.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: CupertinoColors.separator.resolveFrom(context),
                                ),
                                itemBuilder: (context, index) {
                                  final item = menuItems[index];
                                  final isActive = _activePaneId == item.paneId;
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _handleItemTap(item.paneId),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _resolveIcon(item.icon),
                                            size: 20,
                                            color: CupertinoTheme.of(context)
                                                .textTheme
                                                .textStyle
                                                .color,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              style: CupertinoTheme.of(context)
                                                  .textTheme
                                                  .textStyle,
                                            ),
                                          ),
                                          Icon(
                                            isActive
                                                ? CupertinoIcons.chevron_left
                                                : CupertinoIcons.chevron_right,
                                            size: 16,
                                            color: CupertinoColors.systemGrey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
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
        );
      },
    );
  }

  IconData _resolveIcon(PlayerMenuIconToken token) {
    switch (token) {
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
      case PlayerMenuIconToken.controlBarSettings:
        return CupertinoIcons.slider_horizontal_3;
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
