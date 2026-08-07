import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_input_controls.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_player_menu_panel.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_player_menu_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_settings_panel.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_tab_panel.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_top_status_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_pop_route_guard.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

enum NipaplayLargeScreenPlayerMenuTarget { revealControls, openPlayerMenu }

@visibleForTesting
NipaplayLargeScreenPlayerMenuTarget resolveLargeScreenPlayerMenuTarget({
  required bool controlsVisible,
}) {
  return controlsVisible
      ? NipaplayLargeScreenPlayerMenuTarget.openPlayerMenu
      : NipaplayLargeScreenPlayerMenuTarget.revealControls;
}

class NipaplayLargeScreenScaffoldLayout extends StatefulWidget {
  const NipaplayLargeScreenScaffoldLayout({
    super.key,
    required this.currentIndex,
    required this.isDarkMode,
    required this.tabPage,
    required this.tabController,
    required this.content,
    this.onToggleLargeScreen,
    this.onToggleThemeFromOrigin,
    this.onOpenSettings,
  });

  final int currentIndex;
  final bool isDarkMode;
  final List<Widget> tabPage;
  final TabController tabController;
  final Widget content;
  final VoidCallback? onToggleLargeScreen;
  final Future<void> Function(Offset globalOrigin)? onToggleThemeFromOrigin;
  final VoidCallback? onOpenSettings;

  @override
  State<NipaplayLargeScreenScaffoldLayout> createState() =>
      _NipaplayLargeScreenScaffoldLayoutState();
}

class _NipaplayLargeScreenScaffoldLayoutState
    extends State<NipaplayLargeScreenScaffoldLayout> {
  late final FocusNode _inputFocusNode;
  late final ValueNotifier<NipaplayLargeScreenTabPanelCommand?>
      _tabPanelCommand;
  late final ValueNotifier<NipaplayLargeScreenSettingsPanelCommand?>
      _settingsPanelCommand;
  late final FocusNode _playerMenuInitialFocusNode;
  final GlobalKey _contextActionKey =
      GlobalKey(debugLabel: 'nipaplay_large_screen_context_action');
  bool _isTabPanelVisible = false;
  bool _isSettingsPanelVisible = false;
  bool _isPlayerMenuVisible = false;
  DateTime? _lastPlayerMenuPressAt;
  int _focusedMenuIndex = 0;
  int _focusedSettingsIndex = 0;
  int _settingsEntryCount = 0;

  int get _menuItemCount {
    final int actionCount = [
      globals.isTelevision ? null : widget.onToggleLargeScreen,
      widget.onToggleThemeFromOrigin,
      widget.onOpenSettings,
    ].where((callback) => callback != null).length;
    return widget.tabPage.length + actionCount;
  }

  @override
  void initState() {
    super.initState();
    _inputFocusNode = FocusNode(debugLabel: 'nipaplay_large_screen_input');
    _playerMenuInitialFocusNode = FocusNode(
      debugLabel: 'nipaplay_large_screen_player_menu_initial',
    );
    _tabPanelCommand = ValueNotifier<NipaplayLargeScreenTabPanelCommand?>(null);
    _settingsPanelCommand =
        ValueNotifier<NipaplayLargeScreenSettingsPanelCommand?>(null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _playerMenuInitialFocusNode.dispose();
    _settingsPanelCommand.dispose();
    _tabPanelCommand.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NipaplayLargeScreenScaffoldLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_menuItemCount == 0) {
      _focusedMenuIndex = 0;
      return;
    }
    final int maxIndex = _menuItemCount - 1;
    if (_focusedMenuIndex > maxIndex || _focusedMenuIndex < 0) {
      _focusedMenuIndex = _focusedMenuIndex.clamp(0, maxIndex);
    }
  }

  void _toggleTabPanel() {
    if (_isSettingsPanelVisible) {
      _closeSettingsPanel();
    }
    if (_isPlayerMenuVisible) {
      _closePlayerMenu();
    }
    setState(() {
      final bool nextVisible = !_isTabPanelVisible;
      _isTabPanelVisible = nextVisible;
      if (nextVisible) {
        _focusedMenuIndex = _clampMenuIndex(widget.currentIndex);
      }
    });
    if (_isTabPanelVisible) {
      _inputFocusNode.requestFocus();
    } else {
      _ensureContentFocus();
    }
  }

  void _closeTabPanel() {
    if (!_isTabPanelVisible) {
      return;
    }
    setState(() {
      _isTabPanelVisible = false;
    });
    _ensureContentFocus();
  }

  void _toggleSettingsPanel() {
    if (_isTabPanelVisible) {
      _closeTabPanel();
    }
    if (_isPlayerMenuVisible) {
      _closePlayerMenu();
    }
    setState(() {
      _isSettingsPanelVisible = !_isSettingsPanelVisible;
      if (_isSettingsPanelVisible) {
        _focusedSettingsIndex = _clampSettingsIndex(_focusedSettingsIndex);
      }
    });
    if (_isSettingsPanelVisible) {
      _inputFocusNode.requestFocus();
    } else {
      _ensureContentFocus();
    }
  }

  void _closeSettingsPanel() {
    if (!_isSettingsPanelVisible) {
      return;
    }
    setState(() {
      _isSettingsPanelVisible = false;
    });
    _ensureContentFocus();
  }

  void _toggleContextPanel({required bool usePlayerMenu}) {
    if (usePlayerMenu) {
      _togglePlayerMenu();
      return;
    }
    _toggleSettingsPanel();
  }

  void _togglePlayerMenu() {
    if (_isPlayerMenuVisible) {
      _closePlayerMenu();
      return;
    }
    if (_isTabPanelVisible) {
      _closeTabPanel();
    }
    if (_isSettingsPanelVisible) {
      _closeSettingsPanel();
    }
    _openPlayerMenu();
  }

  bool _isPlayerPlaybackContext(VideoPlayerState videoState) {
    return widget.currentIndex == 1 && videoState.hasVideo;
  }

  void _revealPlayerControls(VideoPlayerState videoState) {
    videoState.setControlsHovered(false);
    videoState.revealLargeScreenControls();
  }

  bool _handlePlayerMenuPress(VideoPlayerState videoState) {
    final now = DateTime.now();
    final lastPressAt = _lastPlayerMenuPressAt;
    if (lastPressAt != null &&
        now.difference(lastPressAt) < const Duration(milliseconds: 300)) {
      return true;
    }
    _lastPlayerMenuPressAt = now;

    if (_isSettingsPanelVisible) {
      _closeSettingsPanel();
    } else if (_isPlayerMenuVisible) {
      _closePlayerMenu();
    } else if (_isTabPanelVisible) {
      _closeTabPanel();
    } else {
      switch (resolveLargeScreenPlayerMenuTarget(
        controlsVisible: videoState.showControls,
      )) {
        case NipaplayLargeScreenPlayerMenuTarget.revealControls:
          _revealPlayerControls(videoState);
        case NipaplayLargeScreenPlayerMenuTarget.openPlayerMenu:
          _openPlayerMenu();
      }
    }
    return true;
  }

  KeyEventResult _handlePlayerMediaKey(
    VideoPlayerState videoState,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.mediaPlayPause:
        videoState.togglePlayPause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaPlay:
        if (videoState.status != PlayerStatus.playing) {
          videoState.togglePlayPause();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaPause:
        if (videoState.status == PlayerStatus.playing) {
          videoState.togglePlayPause();
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _openPlayerMenu() {
    final videoState = context.read<VideoPlayerState>();
    if (!videoState.hasVideo) {
      return;
    }
    setState(() {
      _isPlayerMenuVisible = true;
    });
    videoState.setControlsVisibilityLocked(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_isPlayerMenuVisible ||
          !_playerMenuInitialFocusNode.canRequestFocus) {
        return;
      }
      _playerMenuInitialFocusNode.requestFocus();
    });
  }

  void _closePlayerMenu() {
    if (!_isPlayerMenuVisible) {
      return;
    }
    if (mounted) {
      setState(() {
        _isPlayerMenuVisible = false;
      });
      final videoState = context.read<VideoPlayerState>();
      videoState.setControlsVisibilityLocked(false);
      videoState.resetLargeScreenControlsAutoHideTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isPlayerMenuVisible) {
          _ensureContentFocus();
        }
      });
    } else {
      _isPlayerMenuVisible = false;
    }
  }

  Future<void> _exitPlaybackFromPlayerMenu() async {
    // 退出播放时取消续播倒计时。
    AutoNextEpisodeService.instance.cancelAutoNext();

    final videoState = context.read<VideoPlayerState>();
    _closePlayerMenu();
    final shouldExit = await videoState.handleBackButton();
    if (shouldExit) {
      await videoState.resetPlayer();
    }
  }

  Future<void> _sendDanmakuFromPlayerMenu() async {
    final videoState = context.read<VideoPlayerState>();
    _closePlayerMenu();
    await Future<void>.delayed(Duration.zero);
    await videoState.showSendDanmakuDialog();
  }

  int _clampMenuIndex(int index) {
    if (_menuItemCount <= 0) {
      return 0;
    }
    return index.clamp(0, _menuItemCount - 1);
  }

  int _clampSettingsIndex(int index) {
    if (_settingsEntryCount <= 0) {
      return 0;
    }
    return index.clamp(0, _settingsEntryCount - 1);
  }

  void _moveMenuFocus(int delta) {
    if (!_isTabPanelVisible) {
      return;
    }
    final int count = _menuItemCount;
    if (count <= 0) {
      return;
    }
    setState(() {
      _focusedMenuIndex = (_focusedMenuIndex + delta) % count;
      if (_focusedMenuIndex < 0) {
        _focusedMenuIndex += count;
      }
    });
  }

  void _activateFocusedMenuItem() {
    if (!_isTabPanelVisible) {
      return;
    }
    // Activation is delegated to the panel to keep input logic decoupled from UI/actions.
    _tabPanelCommand.value = null;
    _tabPanelCommand.value = NipaplayLargeScreenTabPanelCommand.activateFocused;
  }

  void _dispatchSettingsPanelCommand(
      NipaplayLargeScreenSettingsPanelCommand command) {
    _settingsPanelCommand.value = null;
    _settingsPanelCommand.value = command;
  }

  void _jumpContentScrollBoundary(TraversalDirection direction) {
    if (direction != TraversalDirection.up &&
        direction != TraversalDirection.down) {
      return;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final scrollController =
        PrimaryScrollController.maybeOf(focusContext ?? context);
    if (scrollController == null || !scrollController.hasClients) {
      return;
    }
    final target = direction == TraversalDirection.up
        ? scrollController.position.minScrollExtent
        : scrollController.position.maxScrollExtent;
    scrollController.jumpTo(target);
  }

  void _ensurePrimaryFocusVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        focusContext,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  bool _moveContentFocus(TraversalDirection direction) {
    final focusScope = FocusScope.of(context);
    final focusedNode = FocusManager.instance.primaryFocus;
    if (focusedNode == null || focusedNode == _inputFocusNode) {
      final moved = focusScope.nextFocus();
      if (moved) {
        _ensurePrimaryFocusVisible();
      }
      if (!moved &&
          (direction == TraversalDirection.up ||
              direction == TraversalDirection.down)) {
        _jumpContentScrollBoundary(direction);
      }
      return moved;
    }
    final moved = focusedNode.focusInDirection(direction);
    if (moved) {
      _ensurePrimaryFocusVisible();
    }
    if (!moved &&
        (direction == TraversalDirection.up ||
            direction == TraversalDirection.down)) {
      _jumpContentScrollBoundary(direction);
    }
    return moved;
  }

  bool _activateContentFocus() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused == _inputFocusNode) {
      return false;
    }
    final nodeContext = focused.context;
    if (nodeContext == null) {
      return false;
    }
    return Actions.maybeInvoke<ActivateIntent>(
          nodeContext,
          const ActivateIntent(),
        ) !=
        null;
  }

  void _ensureContentFocus() {
    final focusScope = FocusScope.of(context);
    final focusedNode = FocusManager.instance.primaryFocus;
    if (focusedNode == null || focusedNode == _inputFocusNode) {
      focusScope.nextFocus();
    }
  }

  bool _handleTvOSRootPopRoute() {
    final videoState = context.read<VideoPlayerState>();
    if (_isPlayerPlaybackContext(videoState)) {
      return _handlePlayerMenuPress(videoState);
    }
    if (_isSettingsPanelVisible) {
      _closeSettingsPanel();
    } else if (_isPlayerMenuVisible) {
      _closePlayerMenu();
    } else if (_isTabPanelVisible) {
      _closeTabPanel();
    } else {
      _toggleTabPanel();
    }
    return true;
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    final videoState = context.read<VideoPlayerState>();
    final isPlayerPlaybackContext = _isPlayerPlaybackContext(videoState);
    if (isPlayerPlaybackContext) {
      final mediaResult = _handlePlayerMediaKey(videoState, event);
      if (mediaResult == KeyEventResult.handled) {
        return mediaResult;
      }
    }
    final command = NipaplayLargeScreenInputControls.fromKeyEvent(event);
    if (command == null) {
      return KeyEventResult.ignored;
    }

    if (isPlayerPlaybackContext &&
        (command == NipaplayLargeScreenInputCommand.toggleMenu ||
            command == NipaplayLargeScreenInputCommand.back)) {
      return _handlePlayerMenuPress(videoState)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (_isSettingsPanelVisible) {
      switch (command) {
        case NipaplayLargeScreenInputCommand.toggleMenu:
        case NipaplayLargeScreenInputCommand.back:
          _closeSettingsPanel();
          return KeyEventResult.handled;
        case NipaplayLargeScreenInputCommand.navigateUp:
          _dispatchSettingsPanelCommand(
            NipaplayLargeScreenSettingsPanelCommand.navigateUp,
          );
          return KeyEventResult.handled;
        case NipaplayLargeScreenInputCommand.navigateDown:
          _dispatchSettingsPanelCommand(
            NipaplayLargeScreenSettingsPanelCommand.navigateDown,
          );
          return KeyEventResult.handled;
        case NipaplayLargeScreenInputCommand.navigateLeft:
          _dispatchSettingsPanelCommand(
            NipaplayLargeScreenSettingsPanelCommand.navigateLeft,
          );
          return KeyEventResult.handled;
        case NipaplayLargeScreenInputCommand.navigateRight:
          _dispatchSettingsPanelCommand(
            NipaplayLargeScreenSettingsPanelCommand.navigateRight,
          );
          return KeyEventResult.handled;
        case NipaplayLargeScreenInputCommand.activate:
          _dispatchSettingsPanelCommand(
            NipaplayLargeScreenSettingsPanelCommand.activateFocused,
          );
          return KeyEventResult.handled;
      }
    }

    if (_isPlayerMenuVisible) {
      switch (command) {
        case NipaplayLargeScreenInputCommand.toggleMenu:
        case NipaplayLargeScreenInputCommand.back:
          _closePlayerMenu();
          return KeyEventResult.handled;
        case NipaplayLargeScreenInputCommand.navigateUp:
        case NipaplayLargeScreenInputCommand.navigateDown:
        case NipaplayLargeScreenInputCommand.navigateLeft:
        case NipaplayLargeScreenInputCommand.navigateRight:
        case NipaplayLargeScreenInputCommand.activate:
          return KeyEventResult.ignored;
      }
    }

    switch (command) {
      case NipaplayLargeScreenInputCommand.toggleMenu:
        _toggleTabPanel();
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.back:
        if (_isTabPanelVisible) {
          _closeTabPanel();
          return KeyEventResult.handled;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.navigateUp:
        if (_isTabPanelVisible) {
          _moveMenuFocus(-1);
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext && !videoState.showControls) {
          videoState.increaseVolume();
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext) {
          videoState.resetLargeScreenControlsAutoHideTimer();
        }
        return _moveContentFocus(TraversalDirection.up)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.navigateDown:
        if (_isTabPanelVisible) {
          _moveMenuFocus(1);
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext && !videoState.showControls) {
          videoState.decreaseVolume();
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext) {
          videoState.resetLargeScreenControlsAutoHideTimer();
        }
        return _moveContentFocus(TraversalDirection.down)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.navigateLeft:
        if (_isTabPanelVisible) {
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext && !videoState.showControls) {
          videoState.seekBackwardByStep();
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext) {
          videoState.resetLargeScreenControlsAutoHideTimer();
        }
        return _moveContentFocus(TraversalDirection.left)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.navigateRight:
        if (_isTabPanelVisible) {
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext && !videoState.showControls) {
          videoState.seekForwardByStep();
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext) {
          videoState.resetLargeScreenControlsAutoHideTimer();
        }
        return _moveContentFocus(TraversalDirection.right)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.activate:
        if (_isTabPanelVisible) {
          _activateFocusedMenuItem();
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext && !videoState.showControls) {
          videoState.togglePlayPause();
          return KeyEventResult.handled;
        }
        if (isPlayerPlaybackContext) {
          videoState.resetLargeScreenControlsAutoHideTimer();
        }
        return _activateContentFocus()
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasVideo = context.select<VideoPlayerState, bool>(
      (videoState) => videoState.hasVideo,
    );
    final bool videoControlsVisible = context.select<VideoPlayerState, bool>(
      (videoState) => videoState.showControls,
    );
    final bool usePlayerContextPanel = widget.currentIndex == 1 && hasVideo;
    final bool useDarkSystemBars = usePlayerContextPanel || widget.isDarkMode;
    final bool showPanelBackdrop =
        _isTabPanelVisible || _isSettingsPanelVisible || _isPlayerMenuVisible;
    final bool showSystemBars =
        !usePlayerContextPanel || videoControlsVisible || showPanelBackdrop;

    final content = Focus(
      focusNode: _inputFocusNode,
      autofocus: true,
      canRequestFocus: true,
      onKeyEvent: _handleInputKeyEvent,
      child: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: NipaplayLargeScreenPlayerMenuScope(
                onMenuPressed: () {
                  _handlePlayerMenuPress(context.read<VideoPlayerState>());
                },
                child: widget.content,
              ),
            ),
          ),
          if (showPanelBackdrop)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_isSettingsPanelVisible) {
                    _closeSettingsPanel();
                    return;
                  }
                  if (_isPlayerMenuVisible) {
                    _closePlayerMenu();
                    return;
                  }
                  _closeTabPanel();
                },
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: ColoredBox(
                      color: widget.isDarkMode
                          ? Colors.black.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            left: _isTabPanelVisible ? 0 : -kNipaplayLargeScreenTabPanelWidth,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_isTabPanelVisible,
              child: NipaplayLargeScreenTabPanel(
                currentIndex: widget.currentIndex,
                isDarkMode: widget.isDarkMode,
                tabPage: widget.tabPage,
                tabController: widget.tabController,
                focusedIndex: _focusedMenuIndex,
                commandNotifier: _tabPanelCommand,
                onFocusedIndexChanged: (index) {
                  if (_focusedMenuIndex == index) {
                    return;
                  }
                  setState(() {
                    _focusedMenuIndex = index;
                  });
                },
                onTabActivated: _closeTabPanel,
                onToggleLargeScreen:
                    globals.isTelevision ? null : widget.onToggleLargeScreen,
                onToggleThemeFromOrigin: widget.onToggleThemeFromOrigin,
                onOpenSettings: _toggleSettingsPanel,
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            right: _isSettingsPanelVisible
                ? 0
                : -kNipaplayLargeScreenSettingsPanelWidth,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_isSettingsPanelVisible,
              child: SizedBox(
                width: kNipaplayLargeScreenSettingsPanelWidth,
                child: NipaplayLargeScreenSettingsPanel(
                  isDarkMode: widget.isDarkMode,
                  focusedIndex: _focusedSettingsIndex,
                  commandNotifier: _settingsPanelCommand,
                  onFocusedIndexChanged: (index) {
                    if (_focusedSettingsIndex == index) {
                      return;
                    }
                    setState(() {
                      _focusedSettingsIndex = _clampSettingsIndex(index);
                    });
                  },
                  onEntryCountChanged: (count) {
                    if (_settingsEntryCount == count) {
                      return;
                    }
                    setState(() {
                      _settingsEntryCount = count;
                      _focusedSettingsIndex =
                          _clampSettingsIndex(_focusedSettingsIndex);
                    });
                  },
                  onRequestClose: _closeSettingsPanel,
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            right: _isPlayerMenuVisible
                ? 0
                : -kNipaplayLargeScreenPlayerMenuPanelWidth,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_isPlayerMenuVisible,
              child: ExcludeFocus(
                excluding: !_isPlayerMenuVisible,
                child: NipaplayLargeScreenPlayerMenuPanel(
                  initialFocusNode: _playerMenuInitialFocusNode,
                  onExitPlayback: () {
                    unawaited(_exitPlaybackFromPlayerMenu());
                  },
                  onSendDanmaku: () {
                    unawaited(_sendDanmakuFromPlayerMenu());
                  },
                  onRequestClose: _closePlayerMenu,
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            top: showSystemBars ? 0 : -kNipaplayLargeScreenBottomHintHeight,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              opacity: showSystemBars ? 1 : 0,
              child: IgnorePointer(
                ignoring: !showSystemBars,
                child: NipaplayLargeScreenTopStatusOverlay(
                  isDarkMode: useDarkSystemBars,
                  useVideoBackground: usePlayerContextPanel,
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: showSystemBars ? 0 : -kNipaplayLargeScreenBottomHintHeight,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              opacity: showSystemBars ? 1 : 0,
              child: IgnorePointer(
                ignoring: !showSystemBars,
                child: NipaplayLargeScreenBottomHintOverlay(
                  isDarkMode: useDarkSystemBars,
                  useVideoBackground: usePlayerContextPanel,
                  onToggleMenu: usePlayerContextPanel
                      ? _togglePlayerMenu
                      : _toggleTabPanel,
                  menuLabel: usePlayerContextPanel ? '播放器菜单' : '菜单',
                  contextKey: _contextActionKey,
                  contextIcon: Icons.settings_rounded,
                  contextLabel: '设置',
                  onOpenContext: globals.isTelevision || usePlayerContextPanel
                      ? null
                      : () => _toggleContextPanel(usePlayerMenu: false),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return NipaplayTvOSPopRouteGuard(
      enabled: globals.isTelevision,
      onRootPopRoute: _handleTvOSRootPopRoute,
      child: content,
    );
  }
}
