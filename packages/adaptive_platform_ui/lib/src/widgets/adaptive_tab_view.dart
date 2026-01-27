import 'package:flutter/material.dart';
import '../platform/platform_info.dart';
import 'adaptive_segmented_control.dart';

/// An adaptive tab bar view (horizontal swipeable tabs)
///
/// Shows tabs at the top with a swipeable content area below
///
/// On iOS 26+: Uses native iOS 26 segmented control with Liquid Glass + PageView
/// On iOS <26: Uses CupertinoSegmentedControl + PageView
/// On Android: Uses Material TabBar + TabBarView
///
/// Example:
/// ```dart
/// AdaptiveTabBarView(
///   tabs: ['Tab 1', 'Tab 2', 'Tab 3'],
///   children: [
///     Page1(),
///     Page2(),
///     Page3(),
///   ],
/// )
/// ```
class AdaptiveTabBarView extends StatefulWidget {
  /// Creates an adaptive tab bar view
  const AdaptiveTabBarView({
    super.key,
    required this.tabs,
    required this.children,
    this.onTabChanged,
    this.backgroundColor,
    this.selectedColor,
    this.unselectedColor,
  });

  /// Tab labels
  final List<String> tabs;

  /// Tab content pages
  final List<Widget> children;

  /// Callback when tab changes
  final ValueChanged<int>? onTabChanged;

  /// Background color for the tab bar
  /// On iOS: Background color of the segmented control
  /// On Android: Background color of the TabBar
  final Color? backgroundColor;

  /// Color for the selected tab
  /// On iOS: Thumb color of the selected segment
  /// On Android: Label color of the selected tab
  final Color? selectedColor;

  /// Color for unselected tabs
  /// On iOS: Text color of unselected segments
  /// On Android: Label color of unselected tabs
  final Color? unselectedColor;

  @override
  State<AdaptiveTabBarView> createState() => _AdaptiveTabBarViewState();
}

class _AdaptiveTabBarViewState extends State<AdaptiveTabBarView>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late TabController _materialController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _materialController = TabController(
      length: widget.tabs.length,
      vsync: this,
    );
    _materialController.addListener(_handleMaterialTabChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _materialController.removeListener(_handleMaterialTabChanged);
    _materialController.dispose();
    super.dispose();
  }

  void _handleMaterialTabChanged() {
    if (_materialController.indexIsChanging) {
      widget.onTabChanged?.call(_materialController.index);
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    widget.onTabChanged?.call(index);
  }

  void _onSegmentChanged(int index) {
    if (index != _currentIndex) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // iOS implementation - Uses AdaptiveSegmentedControl
    // On iOS 26+: Native segmented control with Liquid Glass
    // On iOS <26: CupertinoSlidingSegmentedControl
    if (PlatformInfo.isIOS) {
      return Column(
        children: [
          // iOS segmented control as tab bar
          Container(
            color: widget.backgroundColor,
            padding: const EdgeInsets.all(16.0),
            child: AdaptiveSegmentedControl(
              labels: widget.tabs,
              selectedIndex: _currentIndex,
              onValueChanged: _onSegmentChanged,
              height: 40.0,
              color: widget.selectedColor,
            ),
          ),
          // Content with PageView for iOS
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              children: widget.children,
            ),
          ),
        ],
      );
    }

    // Android - Material Design implementation
    if (PlatformInfo.isAndroid) {
      final defaultBackgroundColor =
          widget.backgroundColor ?? Theme.of(context).primaryColor;
      final defaultSelectedColor = widget.selectedColor ?? Colors.white;
      final defaultUnselectedColor =
          widget.unselectedColor ?? Colors.white.withValues(alpha: 0.7);

      return Column(
        children: [
          Material(
            color: defaultBackgroundColor,
            child: TabBar(
              controller: _materialController,
              tabs: widget.tabs.map((label) => Tab(text: label)).toList(),
              indicatorColor: defaultSelectedColor,
              labelColor: defaultSelectedColor,
              unselectedLabelColor: defaultUnselectedColor,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _materialController,
              children: widget.children,
            ),
          ),
        ],
      );
    }

    // Fallback - iOS style
    return Column(
      children: [
        Container(
          color: widget.backgroundColor,
          padding: const EdgeInsets.all(16.0),
          child: AdaptiveSegmentedControl(
            labels: widget.tabs,
            selectedIndex: _currentIndex,
            onValueChanged: _onSegmentChanged,
            height: 40.0,
            color: widget.selectedColor,
          ),
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: widget.children,
          ),
        ),
      ],
    );
  }
}
