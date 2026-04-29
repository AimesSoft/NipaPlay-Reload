import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/settings_entries.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_editable_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_side_panel.dart';

const double kNipaplayLargeScreenSettingsPanelWidth = 900;
const double _kNipaplayLargeScreenSettingsMenuWidth = 230;
const Color _kNipaplayLargeScreenActiveColor = Color(0xFFFF2E55);

enum NipaplayLargeScreenSettingsPanelCommand {
  activateFocused,
  navigateUp,
  navigateDown,
  navigateLeft,
  navigateRight,
}

class NipaplayLargeScreenSettingsPanel extends StatefulWidget {
  const NipaplayLargeScreenSettingsPanel({
    super.key,
    required this.isDarkMode,
    this.focusedIndex = 0,
    this.commandNotifier,
    this.onFocusedIndexChanged,
    this.onEntryCountChanged,
    this.onRequestClose,
  });

  final bool isDarkMode;
  final int focusedIndex;
  final ValueListenable<NipaplayLargeScreenSettingsPanelCommand?>?
      commandNotifier;
  final ValueChanged<int>? onFocusedIndexChanged;
  final ValueChanged<int>? onEntryCountChanged;
  final VoidCallback? onRequestClose;

  @override
  State<NipaplayLargeScreenSettingsPanel> createState() =>
      _NipaplayLargeScreenSettingsPanelState();
}

class _NipaplayLargeScreenSettingsPanelState
    extends State<NipaplayLargeScreenSettingsPanel> {
  late List<NipaplaySettingEntry> _entries;
  int _selectedIndex = 0;
  bool _isContentFocused = false;
  final FocusScopeNode _contentFocusScope = FocusScopeNode(
    debugLabel: 'nipaplay_large_screen_settings_content',
  );
  OnKeyEventCallback? _earlyKeyHandler;

  @override
  void initState() {
    super.initState();
    _entries = const <NipaplaySettingEntry>[];
    _earlyKeyHandler = _handleEarlyKeyEvent;
    FocusManager.instance.addEarlyKeyEventHandler(_earlyKeyHandler!);
  }

  @override
  void dispose() {
    if (_earlyKeyHandler != null) {
      FocusManager.instance.removeEarlyKeyEventHandler(_earlyKeyHandler!);
      _earlyKeyHandler = null;
    }
    _contentFocusScope.dispose();
    super.dispose();
  }

  KeyEventResult _handleEarlyKeyEvent(KeyEvent event) {
    if (!_isContentFocused) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_isFocusInsideContentScope(FocusManager.instance.primaryFocus)) {
      return KeyEventResult.ignored;
    }
    if (NipaplayLargeScreenEditableSlider.isAnyEditing) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveContentVerticalFocus(reverse: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveContentVerticalFocus(reverse: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _entries = buildNipaplaySettingEntries(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onEntryCountChanged?.call(_entries.length);
    });

    final Color inactiveColor =
        widget.isDarkMode ? Colors.white70 : Colors.black54;
    final Color panelBackgroundColor =
        widget.isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);

    if (_entries.isEmpty) {
      return ColoredBox(
        color: panelBackgroundColor,
        child: const SizedBox.expand(),
      );
    }

    if (_selectedIndex < 0 || _selectedIndex >= _entries.length) {
      _selectedIndex = widget.focusedIndex.clamp(0, _entries.length - 1);
    }

    final normalizedFocusedIndex =
        widget.focusedIndex.clamp(0, _entries.length - 1);
    if (normalizedFocusedIndex != widget.focusedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFocusedIndexChanged?.call(normalizedFocusedIndex);
      });
    }

    return ColoredBox(
      color: panelBackgroundColor,
      child: _NipaplayLargeScreenSettingsPanelCommandHost(
        commandNotifier: widget.commandNotifier,
        onNavigateUp: _handleNavigateUp,
        onNavigateDown: _handleNavigateDown,
        onNavigateLeft: _handleNavigateLeft,
        onNavigateRight: _handleNavigateRight,
        onActivateFocused: () async {
          if (_isContentFocused) {
            _activateContentFocus();
            return;
          }
          _selectIndex(normalizedFocusedIndex);
        },
        child: Row(
          children: [
            SizedBox(
              width: _kNipaplayLargeScreenSettingsMenuWidth,
              child: NipaplayLargeScreenSidePanel(
                isDarkMode: widget.isDarkMode,
                width: _kNipaplayLargeScreenSettingsMenuWidth,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: kNipaplayLargeScreenBottomHintHeight,
                    bottom: kNipaplayLargeScreenBottomHintHeight,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final bool isSelectedByFocus =
                          !_isContentFocused && index == normalizedFocusedIndex;
                      final bool isSelectedByPage = index == _selectedIndex;
                      final bool isActive =
                          isSelectedByFocus || isSelectedByPage;
                      final Color itemColor =
                          isActive ? Colors.white : inactiveColor;
                      return NipaplayLargeScreenSidePanelItem(
                        isSelected: isActive,
                        activeColor: _kNipaplayLargeScreenActiveColor,
                        inactiveColor: inactiveColor,
                        onTap: () {
                          _setContentFocused(false);
                          widget.onFocusedIndexChanged?.call(index);
                          _selectIndex(index);
                        },
                        child: Row(
                          children: [
                            Icon(entry.icon, size: 19, color: itemColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: itemColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: kNipaplayLargeScreenBottomHintHeight,
                  bottom: kNipaplayLargeScreenBottomHintHeight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _entries[_selectedIndex].pageTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: widget.isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭设置',
                            onPressed: widget.onRequestClose,
                            icon: Icon(
                              Icons.close_rounded,
                              color: widget.isDarkMode
                                  ? Colors.white70
                                  : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color:
                          widget.isDarkMode ? Colors.white12 : Colors.black12,
                    ),
                    Expanded(
                      child: FocusScope(
                        node: _contentFocusScope,
                        child: KeyedSubtree(
                          key: ValueKey<String>(_entries[_selectedIndex].id),
                          child: _entries[_selectedIndex].page,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectIndex(int index) {
    if (_entries.isEmpty) {
      return;
    }
    final clamped = index.clamp(0, _entries.length - 1);
    if (_selectedIndex == clamped) {
      return;
    }
    setState(() {
      _selectedIndex = clamped;
    });
  }

  void _setContentFocused(bool value) {
    if (_isContentFocused == value) {
      return;
    }
    setState(() {
      _isContentFocused = value;
    });

    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _ensureContentFocus();
      });
    }
  }

  void _handleNavigateUp() {
    if (_isContentFocused) {
      _moveContentVerticalFocus(reverse: true);
      return;
    }
    widget.onFocusedIndexChanged?.call(widget.focusedIndex - 1);
  }

  void _handleNavigateDown() {
    if (_isContentFocused) {
      _moveContentVerticalFocus(reverse: false);
      return;
    }
    widget.onFocusedIndexChanged?.call(widget.focusedIndex + 1);
  }

  void _handleNavigateLeft() {
    if (!_isContentFocused) {
      return;
    }
    final moved = _moveContentFocus(TraversalDirection.left);
    if (!moved) {
      _setContentFocused(false);
    }
  }

  void _handleNavigateRight() {
    if (!_isContentFocused) {
      _setContentFocused(true);
      return;
    }
    _moveContentFocus(TraversalDirection.right);
  }

  bool _moveContentFocus(TraversalDirection direction) {
    final previousPrimaryFocus = FocusManager.instance.primaryFocus;
    if (!_isFocusInsideContentScope(previousPrimaryFocus)) {
      _ensureContentFocus();
    }
    final fallbackFocus =
        _contentFocusScope.focusedChild ?? FocusManager.instance.primaryFocus;

    final focusedChild = _contentFocusScope.focusedChild;
    if (focusedChild == null) {
      final moved = _contentFocusScope.focusInDirection(direction);
      if (!_isFocusInsideContentScope(FocusManager.instance.primaryFocus)) {
        _restoreContentFocus(fallbackFocus);
        return false;
      }
      if (!moved &&
          (direction == TraversalDirection.up ||
              direction == TraversalDirection.down)) {
        _jumpContentScrollBoundary(direction);
      }
      return moved;
    }

    final moved = focusedChild.focusInDirection(direction);
    if (!_isFocusInsideContentScope(FocusManager.instance.primaryFocus)) {
      _restoreContentFocus(fallbackFocus);
      return false;
    }
    if (!moved &&
        (direction == TraversalDirection.up ||
            direction == TraversalDirection.down)) {
      _jumpContentScrollBoundary(direction);
    }
    return moved;
  }

  bool _moveContentVerticalFocus({required bool reverse}) {
    final previousPrimaryFocus = FocusManager.instance.primaryFocus;
    if (!_isFocusInsideContentScope(previousPrimaryFocus)) {
      _ensureContentFocus();
    }
    final fallbackFocus =
        _contentFocusScope.focusedChild ?? FocusManager.instance.primaryFocus;

    final moved = reverse
        ? _contentFocusScope.previousFocus()
        : _contentFocusScope.nextFocus();

    if (!_isFocusInsideContentScope(FocusManager.instance.primaryFocus)) {
      _restoreContentFocus(fallbackFocus);
      return false;
    }

    if (!moved) {
      _jumpContentScrollBoundary(
        reverse ? TraversalDirection.up : TraversalDirection.down,
      );
    }
    return moved;
  }

  bool _isFocusInsideContentScope(FocusNode? node) {
    if (node == null) {
      return false;
    }
    if (identical(node, _contentFocusScope)) {
      return true;
    }
    return node.ancestors
        .any((ancestor) => identical(ancestor, _contentFocusScope));
  }

  void _restoreContentFocus(FocusNode? fallbackFocus) {
    if (fallbackFocus != null &&
        _isFocusInsideContentScope(fallbackFocus) &&
        fallbackFocus.canRequestFocus &&
        fallbackFocus.context != null) {
      fallbackFocus.requestFocus();
      return;
    }
    _ensureContentFocus();
  }

  void _jumpContentScrollBoundary(TraversalDirection direction) {
    if (direction != TraversalDirection.up &&
        direction != TraversalDirection.down) {
      return;
    }
    final focusContext = _contentFocusScope.focusedChild?.context;
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

  void _ensureContentFocus() {
    if (_contentFocusScope.focusedChild != null) {
      return;
    }
    _contentFocusScope.requestFocus();
    _contentFocusScope.nextFocus();
  }

  void _activateContentFocus() {
    final focused = _contentFocusScope.focusedChild;
    if (focused == null) {
      _ensureContentFocus();
      return;
    }
    final nodeContext = focused.context;
    if (nodeContext == null) {
      return;
    }
    Actions.maybeInvoke<ActivateIntent>(nodeContext, const ActivateIntent());
  }
}

class _NipaplayLargeScreenSettingsPanelCommandHost extends StatefulWidget {
  const _NipaplayLargeScreenSettingsPanelCommandHost({
    required this.child,
    required this.onActivateFocused,
    required this.onNavigateUp,
    required this.onNavigateDown,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    this.commandNotifier,
  });

  final Widget child;
  final Future<void> Function() onActivateFocused;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateRight;
  final ValueListenable<NipaplayLargeScreenSettingsPanelCommand?>?
      commandNotifier;

  @override
  State<_NipaplayLargeScreenSettingsPanelCommandHost> createState() =>
      _NipaplayLargeScreenSettingsPanelCommandHostState();
}

class _NipaplayLargeScreenSettingsPanelCommandHostState
    extends State<_NipaplayLargeScreenSettingsPanelCommandHost> {
  @override
  void initState() {
    super.initState();
    widget.commandNotifier?.addListener(_handleCommand);
  }

  @override
  void didUpdateWidget(
      covariant _NipaplayLargeScreenSettingsPanelCommandHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commandNotifier == widget.commandNotifier) {
      return;
    }
    oldWidget.commandNotifier?.removeListener(_handleCommand);
    widget.commandNotifier?.addListener(_handleCommand);
  }

  @override
  void dispose() {
    widget.commandNotifier?.removeListener(_handleCommand);
    super.dispose();
  }

  void _handleCommand() {
    final command = widget.commandNotifier?.value;
    switch (command) {
      case NipaplayLargeScreenSettingsPanelCommand.activateFocused:
        widget.onActivateFocused();
        break;
      case NipaplayLargeScreenSettingsPanelCommand.navigateUp:
        widget.onNavigateUp();
        break;
      case NipaplayLargeScreenSettingsPanelCommand.navigateDown:
        widget.onNavigateDown();
        break;
      case NipaplayLargeScreenSettingsPanelCommand.navigateLeft:
        widget.onNavigateLeft();
        break;
      case NipaplayLargeScreenSettingsPanelCommand.navigateRight:
        widget.onNavigateRight();
        break;
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
