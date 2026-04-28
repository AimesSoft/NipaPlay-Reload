import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_input_controls.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_settings_panel.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_tab_panel.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_top_status_overlay.dart';

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
  bool _isTabPanelVisible = false;
  bool _isSettingsPanelVisible = false;
  int _focusedMenuIndex = 0;
  int _focusedSettingsIndex = 0;
  int _settingsEntryCount = 0;

  int get _menuItemCount {
    final int actionCount = [
      widget.onToggleLargeScreen,
      widget.onToggleThemeFromOrigin,
      widget.onOpenSettings,
    ].where((callback) => callback != null).length;
    return widget.tabPage.length + actionCount;
  }

  @override
  void initState() {
    super.initState();
    _inputFocusNode = FocusNode(debugLabel: 'nipaplay_large_screen_input');
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

  bool _moveContentFocus(TraversalDirection direction) {
    final focusScope = FocusScope.of(context);
    final focusedChild = focusScope.focusedChild;
    if (focusedChild == null || focusedChild == _inputFocusNode) {
      final moved = focusScope.nextFocus();
      if (!moved &&
          (direction == TraversalDirection.up ||
              direction == TraversalDirection.down)) {
        _jumpContentScrollBoundary(direction);
      }
      return moved;
    }
    final moved = focusedChild.focusInDirection(direction);
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
    if (focusScope.focusedChild == null ||
        focusScope.focusedChild == _inputFocusNode) {
      focusScope.nextFocus();
    }
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    final command = NipaplayLargeScreenInputControls.fromKeyEvent(event);
    if (command == null) {
      return KeyEventResult.ignored;
    }

    if (_isSettingsPanelVisible) {
      switch (command) {
        case NipaplayLargeScreenInputCommand.toggleMenu:
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

    switch (command) {
      case NipaplayLargeScreenInputCommand.toggleMenu:
        _toggleTabPanel();
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateUp:
        if (_isTabPanelVisible) {
          _moveMenuFocus(-1);
          return KeyEventResult.handled;
        }
        return _moveContentFocus(TraversalDirection.up)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.navigateDown:
        if (_isTabPanelVisible) {
          _moveMenuFocus(1);
          return KeyEventResult.handled;
        }
        return _moveContentFocus(TraversalDirection.down)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.navigateLeft:
        if (_isTabPanelVisible) {
          return KeyEventResult.handled;
        }
        return _moveContentFocus(TraversalDirection.left)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.navigateRight:
        if (_isTabPanelVisible) {
          return KeyEventResult.handled;
        }
        return _moveContentFocus(TraversalDirection.right)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case NipaplayLargeScreenInputCommand.activate:
        if (_isTabPanelVisible) {
          _activateFocusedMenuItem();
          return KeyEventResult.handled;
        }
        return _activateContentFocus()
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final bool showPanelBackdrop = _isTabPanelVisible || _isSettingsPanelVisible;

    return Focus(
      focusNode: _inputFocusNode,
      autofocus: true,
      canRequestFocus: true,
      onKeyEvent: _handleInputKeyEvent,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                kNipaplayLargeScreenBottomHintHeight,
                14,
                kNipaplayLargeScreenBottomHintHeight + mediaPadding.bottom,
              ),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
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
                onToggleLargeScreen: widget.onToggleLargeScreen,
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
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: NipaplayLargeScreenTopStatusOverlay(
              isDarkMode: widget.isDarkMode,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NipaplayLargeScreenBottomHintOverlay(
              isDarkMode: widget.isDarkMode,
              onToggleMenu: _toggleTabPanel,
              onOpenSettings: _toggleSettingsPanel,
            ),
          ),
        ],
      ),
    );
  }
}
