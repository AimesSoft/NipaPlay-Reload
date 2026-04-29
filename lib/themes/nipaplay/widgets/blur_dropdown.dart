// blur_dropdown.dart
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/utils/theme_utils.dart';

class _BlurDropdownGlobalState {
  static int expandedCount = 0;
}

class BlurDropdown<T> extends StatefulWidget {
  final GlobalKey dropdownKey;
  final List<DropdownMenuItemData<T>> items;
  final FutureOr<void> Function(T value) onItemSelected;

  const BlurDropdown({
    super.key,
    required this.dropdownKey,
    required this.items,
    required this.onItemSelected,
  });

  static bool get isAnyExpanded => _BlurDropdownGlobalState.expandedCount > 0;

  @override
  State<BlurDropdown<T>> createState() => _BlurDropdownState<T>();
}

class _BlurDropdownState<T> extends State<BlurDropdown<T>>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  bool _isDropdownOpen = false;
  bool _isSelecting = false;
  bool _isControlFocused = false;
  bool _isCountedAsExpanded = false;
  T? _currentSelectedValue;
  int _keyboardHighlightedIndex = 0;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  final Duration _animationDuration = const Duration(milliseconds: 200);

  final FocusNode _controlFocusNode = FocusNode(
    debugLabel: 'blur_dropdown_control',
  );
  final FocusNode _menuFocusNode = FocusNode(
    debugLabel: 'blur_dropdown_menu',
  );

  @override
  void initState() {
    super.initState();
    _currentSelectedValue = _findInitialValue();
    _keyboardHighlightedIndex = _findSelectedIndex();
    _animationController = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant BlurDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    final selectedFromProps = _findSelectedValue();
    if (selectedFromProps != null &&
        selectedFromProps != _currentSelectedValue) {
      setState(() {
        _currentSelectedValue = selectedFromProps;
        _keyboardHighlightedIndex = _findSelectedIndex();
      });
      return;
    }

    final currentValue = _currentSelectedValue;
    if (currentValue != null &&
        !widget.items.any((item) => item.value == currentValue)) {
      setState(() {
        _currentSelectedValue =
            widget.items.isNotEmpty ? widget.items.first.value : null;
        _keyboardHighlightedIndex = _findSelectedIndex();
      });
    }
  }

  @override
  void dispose() {
    _setExpandedTracked(false);
    _removeOverlay();
    _animationController.dispose();
    _menuFocusNode.dispose();
    _controlFocusNode.dispose();
    super.dispose();
  }

  void _setExpandedTracked(bool expanded) {
    if (expanded) {
      if (_isCountedAsExpanded) {
        return;
      }
      _isCountedAsExpanded = true;
      _BlurDropdownGlobalState.expandedCount++;
      return;
    }

    if (!_isCountedAsExpanded) {
      return;
    }
    _isCountedAsExpanded = false;
    if (_BlurDropdownGlobalState.expandedCount > 0) {
      _BlurDropdownGlobalState.expandedCount--;
    }
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }

  T? _findInitialValue() {
    for (final DropdownMenuItemData<T> item in widget.items) {
      if (item.isSelected) {
        return item.value;
      }
    }
    return widget.items.isNotEmpty ? widget.items.first.value : null;
  }

  T? _findSelectedValue() {
    for (final DropdownMenuItemData<T> item in widget.items) {
      if (item.isSelected) {
        return item.value;
      }
    }
    return null;
  }

  int _findSelectedIndex() {
    if (widget.items.isEmpty) {
      return 0;
    }
    final selectedIndex = widget.items.indexWhere(
      (item) => item.value == _currentSelectedValue,
    );
    if (selectedIndex < 0) {
      return 0;
    }
    return selectedIndex;
  }

  void _moveHighlighted(int delta) {
    if (widget.items.isEmpty) {
      return;
    }
    final length = widget.items.length;
    setState(() {
      _keyboardHighlightedIndex = (_keyboardHighlightedIndex + delta) % length;
      if (_keyboardHighlightedIndex < 0) {
        _keyboardHighlightedIndex += length;
      }
    });
    _overlayEntry?.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLargeScreenModeActive =
        NipaplayLargeScreenModeScope.isActiveOf(context);
    const activeColor = Color(0xFFFF2E55);
    final idleBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.1);
    final bgColor =
        isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white;

    final control = Container(
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (_isDropdownOpen || (isLargeScreenModeActive && _isControlFocused))
              ? activeColor
              : idleBorderColor,
          width: (_isDropdownOpen || (isLargeScreenModeActive && _isControlFocused))
              ? 1.5
              : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        key: widget.dropdownKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              if (_isSelecting || _animationController.isAnimating) {
                return;
              }
              if (_isDropdownOpen) {
                _closeDropdown(restoreControlFocus: true);
              } else {
                _openDropdown(
                  requestMenuFocus: isLargeScreenModeActive,
                );
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getSelectedItemText(),
                    style: getTitleTextStyle(context),
                  ),
                  const SizedBox(width: 10),
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5)
                        .animate(_animationController),
                    child: Icon(
                      Ionicons.chevron_down_outline,
                      color: _isDropdownOpen
                          ? activeColor
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (!isLargeScreenModeActive) {
      return control;
    }

    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            if (_isSelecting || _animationController.isAnimating) {
              return null;
            }
            if (_isDropdownOpen) {
              _closeDropdown(restoreControlFocus: true);
            } else {
              _openDropdown(requestMenuFocus: true);
            }
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _controlFocusNode,
        onFocusChange: (focused) {
          if (_isControlFocused == focused) {
            return;
          }
          setState(() {
            _isControlFocused = focused;
          });
        },
        onKeyEvent: _handleControlKeyEvent,
        descendantsAreFocusable: false,
        child: control,
      ),
    );
  }

  String _getSelectedItemText() {
    if (widget.items.isEmpty) {
      return '';
    }
    for (final DropdownMenuItemData<T> item in widget.items) {
      if (item.value == _currentSelectedValue) {
        return item.title;
      }
    }
    return widget.items.first.title;
  }

  Future<void> _handleItemSelected(
    T value, {
    bool restoreControlFocus = false,
  }) async {
    if (_isSelecting) {
      return;
    }
    setState(() {
      _isSelecting = true;
      _currentSelectedValue = value;
      _keyboardHighlightedIndex = _findSelectedIndex();
    });
    try {
      await widget.onItemSelected(value);
    } catch (e) {
      debugPrint('[BlurDropdown] 选项回调执行失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSelecting = false;
        });
        _closeDropdown(restoreControlFocus: restoreControlFocus);
      }
    }
  }

  KeyEventResult _handleControlKeyEvent(FocusNode node, KeyEvent event) {
    if (!NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA;
    final isEscape = key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.gameButtonB;

    if (isEnter) {
      if (_isSelecting || _animationController.isAnimating) {
        return KeyEventResult.handled;
      }
      if (_isDropdownOpen) {
        _closeDropdown(restoreControlFocus: true);
      } else {
        _openDropdown(requestMenuFocus: true);
      }
      return KeyEventResult.handled;
    }

    if (isEscape && _isDropdownOpen) {
      _closeDropdown(restoreControlFocus: true);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleMenuKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA;
    final isEscape = key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.gameButtonB;

    if (isEscape) {
      _closeDropdown(restoreControlFocus: true);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlighted(-1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlighted(1);
      return KeyEventResult.handled;
    }

    if (isEnter) {
      if (widget.items.isEmpty || _isSelecting) {
        _closeDropdown(restoreControlFocus: true);
        return KeyEventResult.handled;
      }
      final item = widget.items[_keyboardHighlightedIndex];
      unawaited(_handleItemSelected(item.value, restoreControlFocus: true));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _openDropdown({bool requestMenuFocus = false}) {
    if (_isDropdownOpen || _animationController.isAnimating) {
      return;
    }
    _removeOverlay();

    final RenderBox? renderBox =
        widget.dropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }

    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    double top = position.dy + size.height + 5;
    double estimatedHeight = widget.items.length * 50.0;
    if (top + estimatedHeight > screenHeight) {
      top = screenHeight - estimatedHeight - 10;
    }
    top = top.clamp(0.0, screenHeight - 100.0);

    final right = screenWidth - position.dx - size.width;
    final safeRight = (right < 10.0) ? 10.0 : right;
    final left = position.dx;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.1);

    final Color dropdownBgColor =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFFFFFFF);

    _keyboardHighlightedIndex = _findSelectedIndex();

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _isSelecting
                    ? null
                    : () => _closeDropdown(restoreControlFocus: true),
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Positioned(
                  top: top,
                  right: safeRight,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      alignment: Alignment.topRight,
                      child: child!,
                    ),
                  ),
                );
              },
              child: Material(
                color: Colors.transparent,
                child: Focus(
                  focusNode: _menuFocusNode,
                  onKeyEvent: _handleMenuKeyEvent,
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: screenWidth - left - safeRight > 100
                            ? screenWidth - left - safeRight
                            : size.width * 1.5,
                        maxHeight: screenHeight - top - 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: borderColor, width: 0.5),
                        color: dropdownBgColor,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            spreadRadius: 0,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: widget.items.length,
                          itemBuilder: (context, index) {
                            final item = widget.items[index];
                            final isHighlighted = index == _keyboardHighlightedIndex;
                            final isSelected = item.value == _currentSelectedValue;
                            final backgroundColor = isHighlighted
                                ? const Color(0xFFFF2E55).withValues(alpha: 0.2)
                                : (isSelected
                                    ? (isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.black.withValues(alpha: 0.05))
                                    : Colors.transparent);

                            return InkWell(
                              onTap: _isSelecting
                                  ? null
                                  : () async {
                                      await _handleItemSelected(
                                        item.value,
                                        restoreControlFocus: true,
                                      );
                                    },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : Colors.black.withValues(alpha: 0.05),
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  item.title,
                                  style: getTitleTextStyle(context),
                                ),
                              ),
                            );
                          },
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

    Overlay.of(context).insert(_overlayEntry!);
    _setExpandedTracked(true);
    setState(() {
      _isDropdownOpen = true;
    });
    _animationController.forward();

    if (requestMenuFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isDropdownOpen) {
          return;
        }
        _menuFocusNode.requestFocus();
      });
    }
  }

  void _closeDropdown({bool restoreControlFocus = false}) {
    if (!_isDropdownOpen ||
        (_animationController.status == AnimationStatus.reverse)) {
      return;
    }
    _animationController.reverse().then((_) {
      _removeOverlay();
      _setExpandedTracked(false);
      if (mounted) {
        setState(() {
          _isDropdownOpen = false;
        });
      }
      if (restoreControlFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _controlFocusNode.requestFocus();
        });
      }
    });
  }
}

class DropdownMenuItemData<T> {
  final String title;
  final T value;
  final bool isSelected;
  final String? description;

  DropdownMenuItemData({
    required this.title,
    required this.value,
    this.isSelected = false,
    this.description,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DropdownMenuItemData &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}
