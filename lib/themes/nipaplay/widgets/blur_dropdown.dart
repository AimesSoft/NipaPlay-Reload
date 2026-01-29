// blur_dropdown.dart
// ignore_for_file: deprecated_member_use

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class BlurDropdown<T> extends StatefulWidget {
  final GlobalKey dropdownKey;
  final List<DropdownMenuItemData<T>> items;
  final ValueChanged<T> onItemSelected;

  const BlurDropdown({
    super.key,
    required this.dropdownKey,
    required this.items,
    required this.onItemSelected,
  });

  @override
  // ignore: library_private_types_in_public_api
  _BlurDropdownState<T> createState() => _BlurDropdownState<T>();
}

class _BlurDropdownState<T> extends State<BlurDropdown<T>>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  bool _isDropdownOpen = false;
  T? _currentSelectedValue;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  final Duration _animationDuration = const Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _currentSelectedValue = _findInitialValue();
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
      });
      return;
    }

    final currentValue = _currentSelectedValue;
    if (currentValue != null &&
        !widget.items.any((item) => item.value == currentValue)) {
      setState(() {
        _currentSelectedValue =
            widget.items.isNotEmpty ? widget.items.first.value : null;
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const activeColor = Color(0xFFFF2E55);
    final idleBorderColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1);
    final bgColor = isDark 
        ? Colors.white.withValues(alpha: 0.12) 
        : Colors.white;

    return Container(
      height: 40, // 统一高度
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDropdownOpen ? activeColor : idleBorderColor,
          width: _isDropdownOpen ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        key: widget.dropdownKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              if (_animationController.isAnimating) return;
              if (_isDropdownOpen) {
                _closeDropdown();
              } else {
                _openDropdown();
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
                    turns:
                        Tween(begin: 0.0, end: 0.5).animate(_animationController),
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

  void _openDropdown() {
    if (_isDropdownOpen || _animationController.isAnimating) return;
    _removeOverlay();

    final RenderBox? renderBox =
        widget.dropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

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
    
    final Color dropdownBgColor = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFFFFFFF);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDropdown,
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
                      child: GestureDetector(
                        onTap: () {},
                        child: child!,
                      ),
                    ),
                  ),
                );
              },
              child: Material(
                color: Colors.transparent,
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
                        final Widget menuItem = InkWell(
                          onTap: () {
                            setState(() {
                              _currentSelectedValue = item.value;
                            });
                            widget.onItemSelected(item.value);
                            _closeDropdown();
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: item.value == _currentSelectedValue
                                  ? (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05))
                                  : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
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

                        return menuItem;
                      },
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
    setState(() {
      _isDropdownOpen = true;
    });
    _animationController.forward();
  }

  void _closeDropdown() {
    if (!_isDropdownOpen || (_animationController.status == AnimationStatus.reverse)) {
      return;
    }
    _animationController.reverse().then((_) {
      _removeOverlay();
      if (mounted) {
        setState(() {
          _isDropdownOpen = false;
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
