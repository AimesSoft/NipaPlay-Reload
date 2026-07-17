import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'subtitle_tracks_menu.dart';
import 'subtitle_settings_menu.dart';
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
import 'player_menu_theme.dart';

class VideoSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;
  final Rect? anchorRect;
  final GlobalKey? anchorKey;
  final PlayerMenuPaneId? initialPaneId;
  final bool hideBackButtonForInitialPane;

  const VideoSettingsMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
    this.anchorRect,
    this.anchorKey,
    this.initialPaneId,
    this.hideBackButtonForInitialPane = false,
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
  static const double _menuHeaderHeight = 44;
  static const double _settingsItemHeight = 44;
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
    _activePaneId = widget.initialPaneId;
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
    final Rect? resolved = _anchorRect ?? _resolveAnchorRectFromKey();
    if (resolved == null) {
      return null;
    }
    return _normalizeAnchorRect(resolved);
  }

  Rect? _resolveAnchorRectFromKey() {
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

  Rect _normalizeAnchorRect(Rect rect) {
    // UiScaleWrapper shrinks MediaQuery size; normalize global coords to layout space.
    final mediaSize = MediaQuery.of(context).size;
    if (mediaSize.width == 0 || mediaSize.height == 0) {
      return rect;
    }
    final view = View.of(context);
    final viewSize = view.physicalSize / view.devicePixelRatio;
    final double scaleX = viewSize.width / mediaSize.width;
    final double scaleY = viewSize.height / mediaSize.height;
    if (!scaleX.isFinite ||
        !scaleY.isFinite ||
        scaleX <= 0 ||
        scaleY <= 0 ||
        ((scaleX - 1.0).abs() < 0.001 && (scaleY - 1.0).abs() < 0.001)) {
      return rect;
    }
    return Rect.fromLTWH(
      rect.left / scaleX,
      rect.top / scaleY,
      rect.width / scaleX,
      rect.height / scaleY,
    );
  }

  SettingsMenuScope _wrapMenu({
    required bool showBackItem,
    required Widget child,
    required double height,
    bool forceShowHeader = false,
    bool? useBackButtonOverride,
  }) {
    final bool showHeader = showBackItem || forceShowHeader;
    final bool useBackButton = useBackButtonOverride ?? showBackItem;
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
      useBackButton: useBackButton,
      showHeader: showHeader,
      showBackItem: showHeader ? false : showBackItem,
      lockControlsVisible: true,
      anchorRect: resolvedAnchorRect,
      showPointer: resolvedAnchorRect != null,
      height: height,
      requestClose: requestClose,
      child: child,
    );
  }

  double _heightForSettingsItemCount(
    int itemCount, {
    bool includeHeader = false,
  }) {
    final visibleItemCount = itemCount <= 0 ? 1 : itemCount;
    return (includeHeader ? _menuHeaderHeight : 0) +
        visibleItemCount * _settingsItemHeight;
  }

  double _heightForPane(PlayerMenuPaneId paneId) {
    return _heightForSettingsItemCount(
      _itemCountForPane(paneId),
      includeHeader: true,
    );
  }

  int _itemCountForPane(PlayerMenuPaneId paneId) {
    switch (paneId) {
      case PlayerMenuPaneId.subtitleSettings:
        return videoState.player.getPlayerKernelName() == 'Media Kit' ? 11 : 1;
      case PlayerMenuPaneId.subtitleTracks:
        return _subtitleTrackItemCount();
      case PlayerMenuPaneId.subtitleList:
        return 8;
      case PlayerMenuPaneId.audioTracks:
        return _boundedListItemCount(
          videoState.player.mediaInfo.audio?.length ?? 1,
        );
      case PlayerMenuPaneId.danmakuSettings:
        return 7;
      case PlayerMenuPaneId.danmakuTracks:
        return _boundedListItemCount(videoState.danmakuTracks.length + 3);
      case PlayerMenuPaneId.danmakuList:
        return _boundedListItemCount(videoState.danmakuList.length);
      case PlayerMenuPaneId.danmakuOffset:
        return 8;
      case PlayerMenuPaneId.playbackRate:
        return 13;
      case PlayerMenuPaneId.playlist:
        return 8;
      case PlayerMenuPaneId.jellyfinQuality:
        return 9;
      case PlayerMenuPaneId.playbackInfo:
        return 8;
      case PlayerMenuPaneId.seekStep:
        return 18;
    }
  }

  int _subtitleTrackItemCount() {
    final embeddedCount = videoState.player.mediaInfo.subtitle?.length ?? 0;
    final hasExternalSubtitle =
        (videoState.currentExternalSubtitlePath?.isNotEmpty ?? false);
    return _boundedListItemCount(
      2 + embeddedCount + (hasExternalSubtitle ? 1 : 0),
    );
  }

  int _boundedListItemCount(int itemCount) {
    if (itemCount <= 0) {
      return 1;
    }
    return itemCount;
  }

  Widget _buildPane(
    PlayerMenuPaneId paneId, {
    required VoidCallback onPaneClose,
    required bool showBackButton,
    required double height,
  }) {
    late final Widget child;
    switch (paneId) {
      case PlayerMenuPaneId.subtitleSettings:
        child = ChangeNotifierProvider(
          create: (_) => SubtitleSettingsPaneController(videoState: videoState),
          child: SubtitleSettingsMenu(
            onClose: onPaneClose,
            onHoverChanged: widget.onHoverChanged,
          ),
        );
        break;
      case PlayerMenuPaneId.subtitleTracks:
        child = SubtitleTracksMenu(
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.subtitleList:
        child = SubtitleListMenu(
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.audioTracks:
        child = AudioTracksMenu(
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuSettings:
        child = DanmakuSettingsMenu(
          onClose: onPaneClose,
          videoState: videoState,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuTracks:
        child = DanmakuTracksMenu(
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuList:
        child = DanmakuListMenu(
          videoState: videoState,
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.danmakuOffset:
        child = DanmakuOffsetMenu(
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.playbackRate:
        child = ChangeNotifierProvider(
          create: (_) => PlaybackRatePaneController(videoState: videoState),
          child: PlaybackRateMenu(
            onClose: onPaneClose,
            onHoverChanged: widget.onHoverChanged,
          ),
        );
        break;
      case PlayerMenuPaneId.playlist:
        child = PlaylistMenu(
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.jellyfinQuality:
        child = JellyfinQualityMenu(
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.playbackInfo:
        child = PlaybackInfoMenu(
          onClose: onPaneClose,
          onHoverChanged: widget.onHoverChanged,
        );
        break;
      case PlayerMenuPaneId.seekStep:
        child = ChangeNotifierProvider(
          create: (_) => SeekStepPaneController(videoState: videoState),
          child: SeekStepMenu(
            onClose: onPaneClose,
            onHoverChanged: widget.onHoverChanged,
          ),
        );
        break;
    }

    return _wrapMenu(
      showBackItem: showBackButton,
      height: height,
      forceShowHeader: !showBackButton,
      useBackButtonOverride: showBackButton,
      child: child,
    );
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
        )
            .build()
            .where((item) => item.paneId != PlayerMenuPaneId.playlist)
            .toList();
        final double menuHeight = _heightForSettingsItemCount(menuItems.length);
        final bool hideBackForStandaloneInitialPane =
            widget.hideBackButtonForInitialPane &&
                widget.initialPaneId != null &&
                _activePaneId == widget.initialPaneId;
        final VoidCallback paneCloseCallback = hideBackForStandaloneInitialPane
            ? () {
                requestClose();
              }
            : _closeActivePane;
        final Widget menuContent = _activePaneId == null
            ? _wrapMenu(
                showBackItem: false,
                height: menuHeight,
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
            : _buildPane(
                _activePaneId!,
                onPaneClose: paneCloseCallback,
                showBackButton: !hideBackForStandaloneInitialPane,
                height: hideBackForStandaloneInitialPane
                    ? _heightForPane(_activePaneId!)
                    : menuHeight,
              );
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
    final menuColors = PlayerMenuTheme.colorsOf(context);
    final foregroundColor =
        isActive ? menuColors.selectedForeground : menuColors.foreground;

    return Material(
      color: isActive ? menuColors.selectedBackground : Colors.transparent,
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
                color: menuColors.divider,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _resolveIcon(item.icon),
                color: foregroundColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                item.title,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const Spacer(),
              Icon(
                isActive
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: isActive
                    ? menuColors.selectedForeground
                    : menuColors.secondaryForeground,
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
      case PlayerMenuIconToken.subtitleSettings:
        return Icons.format_size;
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
