import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_input_controls.dart';
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
  bool _isTabPanelVisible = false;
  int _focusedMenuIndex = 0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
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

  int _clampMenuIndex(int index) {
    if (_menuItemCount <= 0) {
      return 0;
    }
    return index.clamp(0, _menuItemCount - 1);
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

  bool _moveContentFocus(TraversalDirection direction) {
    final focusScope = FocusScope.of(context);
    final focusedChild = focusScope.focusedChild;
    if (focusedChild == null || focusedChild == _inputFocusNode) {
      return focusScope.nextFocus();
    }
    return focusedChild.focusInDirection(direction);
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
                14 + mediaPadding.bottom,
              ),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: widget.content,
              ),
            ),
          ),
          if (_isTabPanelVisible)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeTabPanel,
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
                onOpenSettings: widget.onOpenSettings,
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
            ),
          ),
        ],
      ),
    );
  }
}
