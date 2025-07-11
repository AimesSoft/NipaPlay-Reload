// blur_dropdown.dart
// ignore_for_file: deprecated_member_use

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/hover_tooltip_bubble.dart';
// Assume getTitleTextStyle is defined elsewhere, e.g., in theme_utils.dart
// import 'package:nipaplay/utils/theme_utils.dart';

class BlurDropdown<T> extends StatefulWidget {
  final GlobalKey dropdownKey;
  final List<DropdownMenuItemData<T>> items;
  final Function(T) onItemSelected;

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

    // No need for status listener to remove overlay here anymore,
    // as _closeDropdown handles the animation and removal logic.
    // _animationController.addStatusListener((status) {
    //   if (status == AnimationStatus.dismissed && !_isDropdownOpen) {
    //     _removeOverlay();
    //   }
    // });
  }

  @override
  void dispose() {
    // Ensure overlay is removed first if it exists
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  // --- Helper to safely remove the overlay ---
  void _removeOverlay() {
    // Check if overlayEntry exists before trying to remove
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }


  T? _findInitialValue() {
    try {
      return widget.items.firstWhere((item) => item.isSelected).value;
    } catch (e) {
      // If no item is marked as selected, return null or the first item's value
      return widget.items.isNotEmpty ? widget.items.first.value : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the key provided to the parent Row for positioning calculations
    return Row(
      key: widget.dropdownKey, // Apply the key here
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wrap the trigger content in a GestureDetector
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
             mainAxisSize: MainAxisSize.min, // Keep original layout
             children: [
                Text(
                  _getSelectedItemText(),
                  style: getTitleTextStyle(context),
                ),
                const SizedBox(width: 10),
                RotationTransition(
                  turns: Tween(begin: 0.0, end: 0.5).animate(_animationController),
                  child: const Icon(
                    Ionicons.chevron_down_outline,
                    color: Colors.white,
                  ),
                ),
             ],
          ),
          ),
        ),
      ],
    );
  }

  String _getSelectedItemText() {
    final selectedItem = widget.items.firstWhere(
      (item) => item.value == _currentSelectedValue,
      orElse: () => widget.items.isNotEmpty
          ? widget.items.first // Default to first if none selected or initial value not found
          : DropdownMenuItemData(title: '', value: null as T), // Handle empty list case
    );
    return selectedItem.title;
  }

  void _openDropdown() {
    // If already open or animating, do nothing
    if (_isDropdownOpen || _animationController.isAnimating) return;
    // Ensure any previous overlay is removed (shouldn't happen often, but safe)
    _removeOverlay();


    // Find the RenderBox of the trigger element using the key
    final RenderBox? renderBox = widget.dropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return; // Safety check

    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // 计算下拉菜单的初始位置
    double top = position.dy + size.height + 5;
    double maxHeight = screenHeight * 0.7; // 最大高度为屏幕高度的70%
    
    // 检查下拉菜单是否会超出屏幕底部
    double estimatedHeight = widget.items.length * 50.0; // 估算每个项目的高度
    if (top + estimatedHeight > screenHeight) {
      // 如果会超出底部，则向上调整位置
      top = screenHeight - estimatedHeight - 10; // 留出10像素的边距
    }

    // 确保top不会小于0
    top = top.clamp(0.0, screenHeight - 100.0); // 确保至少留出100像素的高度

    final right = screenWidth - position.dx - size.width;
    final safeRight = (right < 10.0) ? 10.0 : right;
    final left = position.dx;

    final Color borderColor = Theme.of(context).brightness == Brightness.light
        ? const Color.fromARGB(255, 201, 201, 201)
        : const Color.fromARGB(255, 130, 130, 130);

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
                    maxHeight: screenHeight - top - 10, // 动态计算最大高度
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 0.5),
                    color: const Color.fromARGB(255, 130, 130, 130).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 5,
                        spreadRadius: 1,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.transparent,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white.withOpacity(0.1),
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
                          
                          // 如果有描述，则包装在HoverTooltipBubble中
                          if (item.description != null && item.description!.isNotEmpty) {
                            return HoverTooltipBubble(
                              text: item.description!,
                              showDelay: const Duration(milliseconds: 300),
                              hideDelay: const Duration(milliseconds: 100),
                              child: menuItem,
                            );
                          } else {
                            return menuItem;
                          }
                        },
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

    // Insert the overlay and start the animation
    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _isDropdownOpen = true;
    });
    _animationController.forward(); // Play open animation
  }

  // --- Updated Close Dropdown Method ---
  void _closeDropdown() {
    // Only proceed if the dropdown is actually open and not already animating closed
    if (!_isDropdownOpen || (_animationController.status == AnimationStatus.reverse)) {
       return;
    }

    // Start the reverse animation (fade/scale out)
    _animationController.reverse().then((_) {
      // This code runs *after* the reverse animation completes
      // Safely remove the overlay *after* the animation finishes
      _removeOverlay();
      // Update the state *after* removal to prevent build errors if widget disposed quickly
      if (mounted) { // Check if the widget is still in the tree
         setState(() {
           _isDropdownOpen = false;
         });
      }
    }).catchError((error) {
       // Handle potential errors during animation reversal if needed
       //////debugPrint("Error closing dropdown animation: $error");
       // Still try to remove overlay and update state in case of error
       _removeOverlay();
        if (mounted) {
           setState(() {
             _isDropdownOpen = false;
           });
        }
    });
  }


  Widget _buildMenuItem(DropdownMenuItemData<T> item) {
    bool isSelected = item.value == _currentSelectedValue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onItemSelected(item.value);
          // Update state immediately for visual feedback if desired
          if (mounted) { // Check if widget is still mounted
            setState(() {
              _currentSelectedValue = item.value;
            });
          }
          _closeDropdown(); // Close dropdown after selecting
        },
        borderRadius: BorderRadius.circular(4), // Optional: for InkWell splash shape
        child: Container(
          width: double.infinity, // Ensure item takes full width
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent, // Subtle selection highlight
          child: Text(
            item.title,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withOpacity(isSelected ? 1.0 : 0.8), // Adjust opacity
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal, // Adjust font weight
            ),
            textAlign: TextAlign.start, // Ensure text aligns left
          ),
        ),
      ),
    );
  }
}

// Data class for menu items (no changes needed here)
class DropdownMenuItemData<T> {
  final String title;
  final T value;
  final bool isSelected; // Used for initial selection hint
  final String? description; // 新增：描述信息

  DropdownMenuItemData({
    required this.title,
    required this.value,
    this.isSelected = false,
    this.description, // 新增：描述信息
  });

   // Added for easy comparison, especially for finding the initial value
   @override
   bool operator ==(Object other) =>
       identical(this, other) ||
       other is DropdownMenuItemData &&
           runtimeType == other.runtimeType &&
           value == other.value;

   @override
   int get hashCode => value.hashCode;
}