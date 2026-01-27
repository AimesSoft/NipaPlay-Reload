import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_native_tab_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';
import '../style/sf_symbol.dart';
import 'adaptive_app_bar.dart';
import 'adaptive_badge.dart';
import 'adaptive_bottom_navigation_bar.dart';
import 'adaptive_button.dart';
import 'ios26/ios26_scaffold.dart';

/// Navigation destination for bottom navigation
class AdaptiveNavigationDestination {
  const AdaptiveNavigationDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.isSearch = false,
    this.badgeCount,
    this.addSpacerAfter = false,
  });

  /// Icon to display (SF Symbol name for iOS, IconData for cross-platform)
  final dynamic icon;

  /// Label text for the destination
  final String label;

  /// Optional selected state icon
  final dynamic selectedIcon;

  /// Whether this is a search tab (iOS 26+)
  /// Search tabs are visually separated and transform into a search field
  final bool isSearch;

  /// Badge count to display on the tab (null means no badge)
  /// On iOS 26+: Uses native UITabBarItem.badgeValue
  /// On iOS <26 and Android: Uses AdaptiveBadge widget
  final int? badgeCount;

  /// Add flexible space after this tab item (iOS 26+ only)
  /// Useful for creating grouped tabs (e.g., left group and right group)
  /// Only applies to iOS 26+ native tab bar
  final bool addSpacerAfter;
}

/// Tab bar minimize behavior for iOS 26+
enum TabBarMinimizeBehavior {
  /// Never minimize the tab bar
  never,

  /// Minimize when scrolling down
  onScrollDown,

  /// Minimize when scrolling up
  onScrollUp,

  /// Let the system decide
  automatic,
}

/// An adaptive scaffold that renders platform-specific navigation
class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({
    super.key,
    this.appBar,
    this.bottomNavigationBar,
    this.body,
    this.floatingActionButton,
    this.minimizeBehavior = TabBarMinimizeBehavior.automatic,
    this.enableBlur = true,
  });

  /// App bar configuration
  /// If null, no app bar or toolbar will be shown
  final AdaptiveAppBar? appBar;

  /// Bottom navigation bar configuration
  /// If null, no bottom navigation will be shown
  final AdaptiveBottomNavigationBar? bottomNavigationBar;

  /// Body widget
  final Widget? body;

  /// Floating action button (Material only)
  final Widget? floatingActionButton;

  /// Tab bar minimize behavior (iOS 26+ only)
  /// Controls how the tab bar minimizes when scrolling
  final TabBarMinimizeBehavior minimizeBehavior;

  /// Enable Liquid Glass blur effect behind tab bar (iOS 26+ only)
  /// When enabled, content behind the tab bar will be blurred
  final bool enableBlur;

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  final GlobalKey<_MinimizableTabBarState> _tabBarKey =
      GlobalKey<_MinimizableTabBarState>();

  @override
  Widget build(BuildContext context) {
    final useNativeToolbar = widget.appBar?.useNativeToolbar ?? false;
    final useNativeBottomBar =
        widget.bottomNavigationBar?.useNativeBottomBar ?? true;

    // iOS 26+ with native toolbar enabled - Use IOS26Scaffold
    if (PlatformInfo.isIOS26OrHigher() && useNativeToolbar) {
      // For GoRouter compatibility: Use body directly if it's StatefulNavigationShell
      // Otherwise replicate body for each destination
      List<Widget> childrenList;
      final bodyType = widget.body?.runtimeType.toString() ?? '';
      final isNavigationShell = bodyType.contains('StatefulNavigationShell');

      if (isNavigationShell) {
        // GoRouter's StatefulNavigationShell already manages children
        // Don't replicate, just use it directly
        childrenList = [widget.body ?? const SizedBox.shrink()];
      } else if (widget.bottomNavigationBar?.items != null &&
          widget.bottomNavigationBar!.items!.isNotEmpty) {
        // Tab-based navigation: replicate single body for all tabs with unique keys
        childrenList = List.generate(
          widget.bottomNavigationBar!.items!.length,
          (index) => KeyedSubtree(
            key: ValueKey('tab_$index'),
            child: widget.body ?? const SizedBox.shrink(),
          ),
        );
      } else {
        // Single page: just one body
        childrenList = [widget.body ?? const SizedBox.shrink()];
      }

      // Wrap children with Stack if floatingActionButton is provided
      if (widget.floatingActionButton != null) {
        final hasBottomNav =
            widget.bottomNavigationBar?.items != null &&
            widget.bottomNavigationBar!.items!.isNotEmpty;
        childrenList = childrenList.map((child) {
          return Stack(
            children: [
              child,
              Positioned(
                right: 16,
                bottom: hasBottomNav ? 96 : 96, // Add space for native tab bar
                child: widget.floatingActionButton!,
              ),
            ],
          );
        }).toList();
      }

      return IOS26Scaffold(
        key: ValueKey(
          'ios26_scaffold_${widget.bottomNavigationBar?.selectedIndex ?? 0}_${widget.body?.runtimeType.toString() ?? "empty"}',
        ),
        bottomNavigationBar: widget.bottomNavigationBar,
        title: widget.appBar?.title,
        actions: widget.appBar?.actions,
        leading: widget.appBar?.leading,
        minimizeBehavior: widget.minimizeBehavior,
        enableBlur: widget.enableBlur,
        children: childrenList,
      );
    }

    // iOS <26 (iOS 18 and below) OR iOS 26+ with useNativeToolbar: false
    // Use CupertinoPageScaffold with CupertinoTabBar if destinations provided
    if (PlatformInfo.isIOS) {
      // Auto back button for iOS 26+ when useNativeToolbar is false
      Widget? effectiveLeading = widget.appBar?.leading;
      if (PlatformInfo.isIOS26OrHigher() &&
          !useNativeToolbar &&
          widget.appBar?.leading == null &&
          (widget.bottomNavigationBar?.items == null ||
              widget.bottomNavigationBar!.items!.isEmpty)) {
        // Check if we can pop AND this is the current route (to prevent showing on previous page during transition)
        final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
        final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

        if (canPop) {
          if (isCurrent) {
            // Active route: show animated back button
            effectiveLeading = _AnimatedBackButton(
              onPressed: () => Navigator.of(context).pop(),
            );
          } else {
            // Transition/background route: show empty SizedBox to prevent native back button
            effectiveLeading = const SizedBox(height: 38, width: 38);
          }
        }
      }

      if (widget.bottomNavigationBar?.items != null &&
          widget.bottomNavigationBar!.items!.isNotEmpty &&
          widget.bottomNavigationBar!.selectedIndex != null &&
          widget.bottomNavigationBar!.onTap != null) {
        // Tab-based navigation

        // Determine which navigation bar to use
        ObstructingPreferredSizeWidget? navigationBar;

        // Priority 1: Custom CupertinoNavigationBar (if provided and useNativeToolbar is false)
        if (widget.appBar?.cupertinoNavigationBar != null) {
          navigationBar =
              widget.appBar!.cupertinoNavigationBar
                  as ObstructingPreferredSizeWidget;
        }
        // Priority 2: Build from title, actions, leading (if appBar has content)
        else if (widget.appBar != null &&
            (widget.appBar!.title != null ||
                (widget.appBar!.actions != null &&
                    widget.appBar!.actions!.isNotEmpty) ||
                effectiveLeading != null)) {
          navigationBar = CupertinoNavigationBar(
            automaticallyImplyLeading: PlatformInfo.isIOS26OrHigher()
                ? false
                : true, // Let CupertinoNavigationBar handle back button for iOS < 26
            middle: widget.appBar!.title != null
                ? Text(widget.appBar!.title!)
                : null,
            trailing:
                widget.appBar!.actions != null &&
                    widget.appBar!.actions!.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.appBar!.actions!.map((action) {
                      Widget actionChild;
                      if (action.title != null) {
                        actionChild = Text(action.title!);
                      } else if (action.icon != null) {
                        actionChild = Icon(action.icon!);
                      } else {
                        actionChild = const Icon(CupertinoIcons.circle);
                      }
                      return CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: action.onPressed,
                        child: actionChild,
                      );
                    }).toList(),
                  )
                : null,
            leading: effectiveLeading,
          );
        }

        // Determine which tab bar to use based on platform and configuration
        Widget? tabBar;

        // iOS 26+ with useNativeBottomBar=true -> Use native tab bar
        if (PlatformInfo.isIOS26OrHigher() && useNativeBottomBar) {
          tabBar = _MinimizableTabBar(
            key: _tabBarKey,
            selectedIndex: widget.bottomNavigationBar!.selectedIndex!,
            onTap: widget.bottomNavigationBar!.onTap!,
            destinations: widget.bottomNavigationBar!.items!,
            minimizeBehavior: widget.minimizeBehavior,
            enableBlur: widget.enableBlur,
            selectedItemColor: widget.bottomNavigationBar!.selectedItemColor,
            unselectedItemColor:
                widget.bottomNavigationBar!.unselectedItemColor,
          );
        }
        // iOS 26+ with useNativeBottomBar=false OR iOS <26
        else {
          // Priority 1: Custom CupertinoTabBar (if provided)
          if (widget.bottomNavigationBar!.cupertinoTabBar != null) {
            tabBar = widget.bottomNavigationBar!.cupertinoTabBar;
          }
          // Priority 2: Build from items
          else {
            tabBar = CupertinoTabBar(
              currentIndex: widget.bottomNavigationBar!.selectedIndex!,
              onTap: widget.bottomNavigationBar!.onTap!,
              activeColor: widget.bottomNavigationBar!.selectedItemColor,
              inactiveColor:
                  widget.bottomNavigationBar!.unselectedItemColor ??
                  CupertinoColors.inactiveGray,
              items: widget.bottomNavigationBar!.items!.map((dest) {
                // Convert icon to IconData if it's a String (SF Symbol)
                final IconData iconData = dest.icon is String
                    ? _sfSymbolToCupertinoIcon(dest.icon as String)
                    : dest.icon as IconData;

                final IconData? selectedIconData = dest.selectedIcon != null
                    ? (dest.selectedIcon is String
                          ? _sfSymbolToCupertinoIcon(
                              dest.selectedIcon as String,
                            )
                          : dest.selectedIcon as IconData)
                    : null;

                // Wrap icons with badge if badgeCount is provided
                Widget iconWidget = Icon(iconData);
                Widget activeIconWidget = selectedIconData != null
                    ? Icon(selectedIconData)
                    : Icon(iconData);

                if (dest.badgeCount != null && dest.badgeCount! > 0) {
                  iconWidget = AdaptiveBadge(
                    count: dest.badgeCount,
                    child: Icon(iconData),
                  );
                  activeIconWidget = AdaptiveBadge(
                    count: dest.badgeCount,
                    child: selectedIconData != null
                        ? Icon(selectedIconData)
                        : Icon(iconData),
                  );
                }

                return BottomNavigationBarItem(
                  icon: iconWidget,
                  activeIcon: activeIconWidget,
                  label: dest.label,
                );
              }).toList(),
            );
          }
        }

        // Wrap body with Stack if floatingActionButton is provided
        Widget bodyWidget = Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Forward scroll notifications to _MinimizableTabBar state (iOS 26+ native only)
                  if (PlatformInfo.isIOS26OrHigher() && useNativeBottomBar) {
                    _tabBarKey.currentState?.handleScrollNotification(
                      notification,
                    );
                  }
                  return false; // Let it bubble up
                },
                child: PlatformInfo.isIOS26OrHigher() && useNativeBottomBar
                    ? Stack(
                        children: [
                          widget.body ?? const SizedBox.shrink(),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: tabBar!,
                          ),
                        ],
                      )
                    : widget.body ?? const SizedBox.shrink(),
              ),
            ),
            // Show tab bar at bottom for non-native cases
            if (!PlatformInfo.isIOS26OrHigher() || !useNativeBottomBar) tabBar!,
          ],
        );

        if (widget.floatingActionButton != null) {
          bodyWidget = Stack(
            children: [
              bodyWidget,
              Positioned(
                right: 16,
                bottom: (!PlatformInfo.isIOS26OrHigher() || !useNativeBottomBar)
                    ? 96
                    : 16, // Add space for tab bar if not native
                child: widget.floatingActionButton!,
              ),
            ],
          );
        }

        return CupertinoPageScaffold(
          navigationBar: navigationBar,
          child: bodyWidget,
        );
      }

      // Simple page without tabs

      // Determine which navigation bar to use
      ObstructingPreferredSizeWidget? navigationBar;

      // Priority 1: Custom CupertinoNavigationBar (if provided and useNativeToolbar is false)
      if (widget.appBar?.cupertinoNavigationBar != null) {
        navigationBar =
            widget.appBar!.cupertinoNavigationBar
                as ObstructingPreferredSizeWidget;
      }
      // Priority 2: Build from title, actions, leading (if appBar has content)
      else if (widget.appBar != null &&
          (widget.appBar!.title != null ||
              (widget.appBar!.actions != null &&
                  widget.appBar!.actions!.isNotEmpty) ||
              effectiveLeading != null)) {
        navigationBar = CupertinoNavigationBar(
          automaticallyImplyLeading: PlatformInfo.isIOS26OrHigher()
              ? false
              : true, // Let CupertinoNavigationBar handle back button for iOS < 26
          middle: widget.appBar!.title != null
              ? Text(widget.appBar!.title!)
              : null,
          trailing:
              widget.appBar!.actions != null &&
                  widget.appBar!.actions!.isNotEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.appBar!.actions!.map((action) {
                    Widget actionChild;
                    if (action.title != null) {
                      actionChild = Text(action.title!);
                    } else if (action.icon != null) {
                      actionChild = Icon(action.icon!);
                    } else {
                      actionChild = const Icon(CupertinoIcons.circle);
                    }
                    return CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: action.onPressed,
                      child: actionChild,
                    );
                  }).toList(),
                )
              : null,
          leading: effectiveLeading,
        );
      }

      // If no navigation bar, just return body
      if (navigationBar == null) {
        return widget.body ?? const SizedBox.shrink();
      }

      // Wrap body with Stack if floatingActionButton is provided
      Widget body = widget.body ?? const SizedBox.shrink();
      if (widget.floatingActionButton != null) {
        body = Stack(
          children: [
            body,
            Positioned(
              right: 16,
              bottom: 16,
              child: widget.floatingActionButton!,
            ),
          ],
        );
      }

      return CupertinoPageScaffold(navigationBar: navigationBar, child: body);
    }

    // Android - Use NavigationBar if destinations provided
    if (widget.bottomNavigationBar?.items != null &&
        widget.bottomNavigationBar!.items!.isNotEmpty &&
        widget.bottomNavigationBar!.selectedIndex != null &&
        widget.bottomNavigationBar!.onTap != null) {
      // Tab-based navigation

      // Determine which app bar to use
      PreferredSizeWidget? appBar;

      // Priority 1: Custom AppBar (if provided)
      if (widget.appBar?.appBar != null) {
        appBar = widget.appBar!.appBar;
      }
      // Priority 2: Build from title, actions, leading (if appBar has content)
      else if (widget.appBar != null &&
          (widget.appBar!.title != null ||
              (widget.appBar!.actions != null &&
                  widget.appBar!.actions!.isNotEmpty) ||
              widget.appBar!.leading != null)) {
        appBar = AppBar(
          title: widget.appBar!.title != null
              ? Text(widget.appBar!.title!)
              : null,
          actions: widget.appBar!.actions?.map((action) {
            if (action.title != null) {
              return TextButton(
                onPressed: action.onPressed,
                child: Text(action.title!),
              );
            }
            return IconButton(
              icon: action.icon != null
                  ? Icon(action.icon!)
                  : const Icon(Icons.circle),
              onPressed: action.onPressed,
            );
          }).toList(),
          leading: widget.appBar!.leading,
        );
      }

      // Determine which bottom navigation bar to use
      Widget? bottomNavBar;

      // Priority 1: Custom BottomNavigationBar (if provided)
      if (widget.bottomNavigationBar!.bottomNavigationBar != null) {
        bottomNavBar = widget.bottomNavigationBar!.bottomNavigationBar;
      }
      // Priority 2: Build from items
      else {
        bottomNavBar = NavigationBar(
          selectedIndex: widget.bottomNavigationBar!.selectedIndex!,
          onDestinationSelected: widget.bottomNavigationBar!.onTap!,
          indicatorColor: widget.bottomNavigationBar!.selectedItemColor,
          destinations: widget.bottomNavigationBar!.items!.map((dest) {
            // Convert icon to IconData if it's a String (SF Symbol - fallback to Icons)
            final IconData iconData = dest.icon is String
                ? Icons
                      .circle // Fallback for Android if SF Symbol is provided
                : dest.icon as IconData;

            final IconData? selectedIconData = dest.selectedIcon != null
                ? (dest.selectedIcon is String
                      ? Icons
                            .circle // Fallback for Android
                      : dest.selectedIcon as IconData)
                : null;

            // Wrap icons with badge if badgeCount is provided
            Widget iconWidget = Icon(iconData);
            Widget selectedIconWidget = selectedIconData != null
                ? Icon(selectedIconData)
                : Icon(iconData);

            if (dest.badgeCount != null && dest.badgeCount! > 0) {
              iconWidget = AdaptiveBadge(
                count: dest.badgeCount,
                child: Icon(iconData),
              );
              selectedIconWidget = AdaptiveBadge(
                count: dest.badgeCount,
                child: selectedIconData != null
                    ? Icon(selectedIconData)
                    : Icon(iconData),
              );
            }

            return NavigationDestination(
              icon: iconWidget,
              selectedIcon: selectedIconWidget,
              label: dest.label,
            );
          }).toList(),
        );
      }

      return Scaffold(
        appBar: appBar,
        body: widget.body ?? const SizedBox.shrink(),
        bottomNavigationBar: bottomNavBar,
        floatingActionButton: widget.floatingActionButton,
      );
    }

    // Simple page without tabs

    // Determine which app bar to use
    PreferredSizeWidget? appBar;

    // Priority 1: Custom AppBar (if provided)
    if (widget.appBar?.appBar != null) {
      appBar = widget.appBar!.appBar;
    }
    // Priority 2: Build from title, actions, leading (if appBar has content)
    else if (widget.appBar != null &&
        (widget.appBar!.title != null ||
            (widget.appBar!.actions != null &&
                widget.appBar!.actions!.isNotEmpty) ||
            widget.appBar!.leading != null)) {
      appBar = AppBar(
        title: widget.appBar!.title != null
            ? Text(widget.appBar!.title!)
            : null,
        actions: widget.appBar!.actions?.map((action) {
          if (action.title != null) {
            return TextButton(
              onPressed: action.onPressed,
              child: Text(action.title!),
            );
          }
          return IconButton(
            icon: action.icon != null
                ? Icon(action.icon!)
                : const Icon(Icons.circle),
            onPressed: action.onPressed,
          );
        }).toList(),
        leading: widget.appBar!.leading,
      );
    }

    // If no app bar, just return body
    if (appBar == null) {
      return widget.body ?? const SizedBox.shrink();
    }

    return Scaffold(
      appBar: appBar,
      body: widget.body ?? const SizedBox.shrink(),
      floatingActionButton: widget.floatingActionButton,
    );
  }

  IconData _sfSymbolToCupertinoIcon(String sfSymbol) {
    const iconMap = {
      'house': CupertinoIcons.house,
      'house.fill': CupertinoIcons.house_fill,
      'magnifyingglass': CupertinoIcons.search,
      'heart': CupertinoIcons.heart,
      'heart.fill': CupertinoIcons.heart_fill,
      'person': CupertinoIcons.person,
      'person.fill': CupertinoIcons.person_fill,
      'gear': CupertinoIcons.settings,
      'star': CupertinoIcons.star,
      'star.fill': CupertinoIcons.star_fill,
      'bell': CupertinoIcons.bell,
      'bell.fill': CupertinoIcons.bell_fill,
      'bag': CupertinoIcons.bag,
      'bag.fill': CupertinoIcons.bag_fill,
      'bookmark': CupertinoIcons.bookmark,
      'bookmark.fill': CupertinoIcons.bookmark_fill,
      'info.circle': CupertinoIcons.info_circle,
      'info.circle.fill': CupertinoIcons.info_circle_fill,
      'plus.circle': CupertinoIcons.add_circled,
      'plus': CupertinoIcons.add,
      'checkmark.circle': CupertinoIcons.checkmark_circle,
    };
    return iconMap[sfSymbol] ?? CupertinoIcons.circle;
  }
}

/// Minimizable tab bar wrapper for iOS 26+ (used when useNativeToolbar: false)
/// Just handles animation, scroll notification is handled by parent
class _MinimizableTabBar extends StatefulWidget {
  const _MinimizableTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.destinations,
    required this.minimizeBehavior,
    required this.enableBlur,
    this.selectedItemColor,
    this.unselectedItemColor,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<AdaptiveNavigationDestination> destinations;
  final TabBarMinimizeBehavior minimizeBehavior;
  final bool enableBlur;
  final Color? selectedItemColor;
  final Color? unselectedItemColor;

  @override
  State<_MinimizableTabBar> createState() => _MinimizableTabBarState();
}

class _MinimizableTabBarState extends State<_MinimizableTabBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isMinimized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Called from parent's NotificationListener
  void handleScrollNotification(ScrollNotification notification) {
    if (widget.minimizeBehavior == TabBarMinimizeBehavior.never) {
      return;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final metrics = notification.metrics;

      // Check if we're in overscroll territory (pull-to-refresh or bottom bounce)
      // When pixels < minScrollExtent, user is pulling down beyond top (overscroll)
      // When pixels > maxScrollExtent, user is pulling up beyond bottom (overscroll)
      // Add tolerance (50px) to make it more stable - ignore scroll events near boundaries
      const overscrollTolerance = 50.0;
      final isOverscrolling =
          metrics.pixels < (metrics.minScrollExtent + overscrollTolerance) ||
          metrics.pixels > (metrics.maxScrollExtent - overscrollTolerance);

      // Ignore scroll events during overscroll to prevent tab bar animation during bounce
      if (isOverscrolling) {
        return;
      }

      if (widget.minimizeBehavior == TabBarMinimizeBehavior.onScrollDown ||
          widget.minimizeBehavior == TabBarMinimizeBehavior.automatic) {
        // Minimize when scrolling down (positive delta)
        if (delta > 0 && !_isMinimized) {
          _minimizeTabBar();
        } else if (delta < 0 && _isMinimized) {
          _expandTabBar();
        }
      } else if (widget.minimizeBehavior == TabBarMinimizeBehavior.onScrollUp) {
        // Minimize when scrolling up (negative delta)
        if (delta < 0 && !_isMinimized) {
          _minimizeTabBar();
        } else if (delta > 0 && _isMinimized) {
          _expandTabBar();
        }
      }
    }
  }

  void _minimizeTabBar() {
    if (!_isMinimized && mounted) {
      _isMinimized = true;
      _controller.forward();
    }
  }

  void _expandTabBar() {
    if (_isMinimized && mounted) {
      _isMinimized = false;
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // Calculate minimized state
        // value: 0.0 = expanded (full size), 1.0 = minimized (70% size, 50% opacity)
        final minimizeProgress = _animation.value;
        final scale = 1.0 - (minimizeProgress * 0.3); // 1.0 → 0.7
        final opacity = 1.0 - (minimizeProgress * 0.5); // 1.0 → 0.5

        return Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: IOS26NativeTabBar(
        destinations: widget.destinations,
        selectedIndex: widget.selectedIndex,
        onTap: widget.onTap,
        tint:
            widget.selectedItemColor ?? CupertinoTheme.of(context).primaryColor,
        unselectedItemTint: widget.unselectedItemColor,
        minimizeBehavior: widget.minimizeBehavior,
      ),
    );
  }
}

/// Animated back button for iOS 26+
/// Fades out when pressed
class _AnimatedBackButton extends StatefulWidget {
  const _AnimatedBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_AnimatedBackButton> createState() => _AnimatedBackButtonState();
}

class _AnimatedBackButtonState extends State<_AnimatedBackButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  bool _isPopping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePressed() {
    if (_isPopping) return;

    setState(() {
      _isPopping = true;
    });

    // Start animation and pop immediately (parallel)
    _controller.forward();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _isPopping ? 0.0 : _opacityAnimation.value,
          child: IgnorePointer(ignoring: _isPopping, child: child),
        );
      },
      child: SizedBox(
        height: 38,
        width: 38,
        child: AdaptiveButton.sfSymbol(
          onPressed: _handlePressed,
          sfSymbol: SFSymbol("chevron.left", size: 20),
        ),
      ),
    );
  }
}
