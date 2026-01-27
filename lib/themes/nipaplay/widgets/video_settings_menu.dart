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
  final GlobalKey? anchorKey;

  const VideoSettingsMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
    this.anchorRect,
    this.anchorKey,
  });

  @override
  State<VideoSettingsMenu> createState() => VideoSettingsMenuState();
}

class VideoSettingsMenuState extends State<VideoSettingsMenu>
    with SingleTickerProviderStateMixin {
  PlayerMenuPaneId? _activePaneId;
  late final VideoPlayerState videoState;
  late final PlayerKernelType _currentKernelType;
  static const double _menuWidth = 300;
  static const double _menuRightOffset = 20;
  static const double _menuHeight = 420;
  static const int _maxAnchorRefreshAttempts = 6;
  static const Duration _menuEnterDuration = Duration(milliseconds: 240);
  static const Duration _menuExitDuration = Duration(milliseconds: 170);
  Rect? _anchorRect;
  int _anchorRefreshAttempts = 0;
  bool _loggedNullAnchor = false;
  bool _loggedResolvedAnchor = false;
  bool _isClosing = false;
  late final AnimationController _menuAnimationController;
  late final Animation<double> _menuFadeAnimation;
  late final Animation<double> _menuScaleAnimation;

  @override
  void initState() {
    super.initState();
    videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _currentKernelType = PlayerFactory.getKernelType();
    videoState.setControlsVisibilityLocked(true);
    _anchorRect = widget.anchorRect;
    _anchorRefreshAttempts = 0;
    _menuAnimationController = AnimationController(
      vsync: this,
      duration: _menuEnterDuration,
      reverseDuration: _menuExitDuration,
    );
    _menuFadeAnimation = CurvedAnimation(
      parent: _menuAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _menuScaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _menuAnimationController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    assert(() {
      debugPrint(
        'VideoSettingsMenu: init anchorRect=$_anchorRect anchorKey=${widget.anchorKey != null}',
      );
      return true;
    }());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAnchorRect());
    _menuAnimationController.forward();
  }

  @override
  void dispose() {
    videoState.setControlsVisibilityLocked(false);
    _menuAnimationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(VideoSettingsMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anchorRect != oldWidget.anchorRect) {
      _anchorRect = widget.anchorRect ?? _anchorRect;
    }
    if (widget.anchorKey != oldWidget.anchorKey ||
        widget.anchorRect != oldWidget.anchorRect) {
      _anchorRefreshAttempts = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAnchorRect());
    }
  }

  void _refreshAnchorRect() {
    if (!mounted) return;
    if (widget.anchorKey == null) {
      return;
    }
    final context = widget.anchorKey?.currentContext;
    if (context == null) {
      _scheduleAnchorRefresh();
      return;
    }
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      _scheduleAnchorRefresh();
      return;
    }
    final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    if (_anchorRect != rect) {
      assert(() {
        debugPrint('VideoSettingsMenu: anchorRect updated to $rect');
        return true;
      }());
      setState(() {
        _anchorRect = rect;
      });
    }
    _anchorRefreshAttempts = 0;
  }

  void _scheduleAnchorRefresh() {
    if (widget.anchorKey == null) {
      return;
    }
    if (_anchorRefreshAttempts >= _maxAnchorRefreshAttempts) {
      assert(() {
        debugPrint(
          'VideoSettingsMenu: anchorRect refresh aborted after $_anchorRefreshAttempts attempts',
        );
        return true;
      }());
      return;
    }
    _anchorRefreshAttempts += 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAnchorRect());
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

  Future<void> requestClose() async {
    if (_isClosing) return;
    _isClosing = true;
    if (mounted) {
      await _menuAnimationController.reverse();
    }
    widget.onClose();
  }

  bool _isPointUp(BuildContext context) {
    final Rect? anchorRect = _resolveAnchorRect();
    if (anchorRect == null) {
      return true;
    }
    final Size screenSize = MediaQuery.of(context).size;
    final double spaceAbove = anchorRect.top;
    final double spaceBelow = screenSize.height - anchorRect.bottom;
    return spaceAbove < spaceBelow;
  }

  Rect? _resolveAnchorRect() {
    if (_anchorRect != null) {
      return _anchorRect;
    }
    final context = widget.anchorKey?.currentContext;
    if (context == null) {
      return null;
    }
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return null;
    }
    return renderBox.localToGlobal(Offset.zero) & renderBox.size;
  }

  SettingsMenuScope _wrapMenu({required bool showBackItem, required Widget child}) {
    final bool showHeader = showBackItem;
    final Rect? resolvedAnchorRect = _resolveAnchorRect();
    if (resolvedAnchorRect == null) {
      if (!_loggedNullAnchor) {
        assert(() {
          debugPrint(
            'VideoSettingsMenu: resolvedAnchorRect is null (widgetAnchorRect=${widget.anchorRect}, anchorKey=${widget.anchorKey != null})',
          );
          return true;
        }());
        _loggedNullAnchor = true;
      }
    } else if (!_loggedResolvedAnchor) {
      assert(() {
        debugPrint(
          'VideoSettingsMenu: resolvedAnchorRect=$resolvedAnchorRect',
        );
        return true;
      }());
      _loggedResolvedAnchor = true;
    }
    return SettingsMenuScope(
      width: _menuWidth,
      rightOffset: _menuRightOffset,
      useBackButton: showBackItem,
      showHeader: showHeader,
      showBackItem: showHeader ? false : showBackItem,
      lockControlsVisible: true,
      anchorRect: resolvedAnchorRect,
      showPointer: resolvedAnchorRect != null,
      height: _menuHeight,
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
        final bool pointUp = _isPointUp(context);
        final Offset slideBegin =
            pointUp ? const Offset(0, -0.03) : const Offset(0, 0.03);
        final Animation<Offset> slideAnimation = Tween<Offset>(
          begin: slideBegin,
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _menuAnimationController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
        final Alignment scaleAlignment =
            pointUp ? Alignment.topCenter : Alignment.bottomCenter;
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
        final Widget animatedMenuContent = FadeTransition(
          opacity: _menuFadeAnimation,
          child: SlideTransition(
            position: slideAnimation,
            child: ScaleTransition(
              alignment: scaleAlignment,
              scale: _menuScaleAnimation,
              child: menuContent,
            ),
          ),
        );
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
                      requestClose();
                    },
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: _isClosing,
                  child: animatedMenuContent,
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
