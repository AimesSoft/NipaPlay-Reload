import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/pages/anime_page.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';
import 'package:nipaplay/pages/new_series_page.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/services/hotkey_service_initializer.dart';
import 'package:nipaplay/themes/material/pages/material_settings_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/splash_screen.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/shortcut_tooltip_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class MaterialMainPage extends StatefulWidget {
  final String? launchFilePath;

  const MaterialMainPage({super.key, this.launchFilePath});

  @override
  State<MaterialMainPage> createState() => _MaterialMainPageState();
}

class _MaterialMainPageState extends State<MaterialMainPage>
    with WindowListener {
  static const double _compactWidthBreakpoint = 600;
  static const double _expandedWidthBreakpoint = 840;

  final PageController _pageController = PageController();

  bool _showSplash = true;
  bool _isMaximized = false;
  int _selectedIndex = 0;

  TabChangeNotifier? _tabChangeNotifier;
  VideoPlayerState? _videoPlayerState;
  bool _hotkeysAreRegistered = false;

  List<_MaterialDestination> get _destinations {
    final items = <_MaterialDestination>[
      _MaterialDestination(
        label: '主页',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        builder: () => const DashboardHomePage(),
      ),
      _MaterialDestination(
        label: '播放',
        icon: Icons.play_circle_outline,
        selectedIcon: Icons.play_circle,
        builder: () => const PlayVideoPage(),
      ),
      _MaterialDestination(
        label: '媒体库',
        icon: Icons.video_library_outlined,
        selectedIcon: Icons.video_library,
        builder: () => const AnimePage(),
      ),
    ];

    if (!kIsWeb && !Platform.isIOS) {
      items.add(
        _MaterialDestination(
          label: '新番',
          icon: Icons.new_releases_outlined,
          selectedIcon: Icons.new_releases,
          builder: () => const NewSeriesPage(),
        ),
      );
    }

    items.add(
      _MaterialDestination(
        label: '设置',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        builder: () => const MaterialSettingsHomePage(),
      ),
    );

    return items;
  }

  @override
  void initState() {
    super.initState();
    _loadStartupPage();

    if (globals.winLinDesktop) {
      windowManager.addListener(this);
      _checkWindowMaximizedState();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
      _tabChangeNotifier?.addListener(_onTabChangeRequested);

      if (globals.isDesktop) {
        _initializeHotkeys();
      }

      // 延迟隐藏启动动画，保持和其他主题一致的节奏
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() {
          _showSplash = false;
        });
      });
    });
  }

  Future<void> _loadStartupPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedIndex = prefs.getInt('default_page_index') ?? 0;
      final clampedIndex = storedIndex.clamp(0, _destinations.length - 1);
      if (!mounted) return;
      setState(() {
        _selectedIndex = clampedIndex;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_pageController.hasClients) return;
        _pageController.jumpToPage(_selectedIndex);
      });
    } catch (e) {
      debugPrint('[MaterialMainPage] 加载默认页面失败: $e');
    }
  }

  void _initializeHotkeys() async {
    await HotkeyServiceInitializer().initialize(context);
    ShortcutTooltipManager();
  }

  @override
  void dispose() {
    _tabChangeNotifier?.removeListener(_onTabChangeRequested);
    _videoPlayerState?.removeListener(_manageHotkeys);
    _pageController.dispose();
    if (globals.winLinDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  void _onTabChangeRequested() {
    final notifier = _tabChangeNotifier;
    if (notifier == null) return;
    final targetIndex = notifier.targetTabIndex;
    if (targetIndex == null) return;

    final int clampedIndex = targetIndex.clamp(0, _destinations.length - 1);
    if (clampedIndex != _selectedIndex) {
      _selectIndex(clampedIndex);
    }
    notifier.clearMainTabIndex();
  }

  void _selectIndex(int index) {
    if (index < 0 || index >= _destinations.length) return;

    final enablePageAnimation =
        context.read<AppearanceSettingsProvider>().enablePageAnimation;

    setState(() {
      _selectedIndex = index;
    });

    if (enablePageAnimation) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(index);
    }
    _manageHotkeys();
  }

  void _manageHotkeys() {
    final videoState = _videoPlayerState;
    if (videoState == null || !mounted) return;

    final shouldBeRegistered = _selectedIndex == 1 && videoState.hasVideo;

    if (shouldBeRegistered && !_hotkeysAreRegistered) {
      HotkeyService().registerHotkeys().then((_) {
        _hotkeysAreRegistered = true;
      });
    } else if (!shouldBeRegistered && _hotkeysAreRegistered) {
      HotkeyService().unregisterHotkeys().then((_) {
        _hotkeysAreRegistered = false;
      });
    }
  }

  void _checkWindowMaximizedState() async {
    if (!globals.winLinDesktop) return;
    final maximized = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() {
      _isMaximized = maximized;
    });
  }

  void _toggleWindowSize() async {
    if (!globals.winLinDesktop) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  void _minimizeWindow() async {
    if (!globals.winLinDesktop) return;
    await windowManager.minimize();
  }

  void _closeWindow() async {
    if (!globals.winLinDesktop) return;
    await windowManager.close();
  }

  @override
  void onWindowMaximize() => _checkWindowMaximizedState();

  @override
  void onWindowUnmaximize() => _checkWindowMaximizedState();

  @override
  void onWindowResize() => _checkWindowMaximizedState();

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_videoPlayerState == videoState) return;
          _videoPlayerState?.removeListener(_manageHotkeys);
          _videoPlayerState = videoState;
          _videoPlayerState?.addListener(_manageHotkeys);
          _manageHotkeys();
        });

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final bool isCompact = width < _compactWidthBreakpoint;
            final bool isExpanded = width >= _expandedWidthBreakpoint;
            final destinations = _destinations;
            final shouldShowAppBar = videoState.shouldShowAppBar();

            final Widget navigation = isCompact
                ? NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectIndex,
                    destinations: destinations
                        .map(
                          (d) => NavigationDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: d.label,
                          ),
                        )
                        .toList(),
                  )
                : NavigationRail(
                    extended: isExpanded,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectIndex,
                    destinations: destinations
                        .map(
                          (d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ),
                        )
                        .toList(),
                  );

            final Widget body = PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: destinations.map((d) => d.builder()).toList(),
            );

            return Stack(
              children: [
                Scaffold(
                  appBar: shouldShowAppBar
                      ? AppBar(
                          title: Text(destinations[_selectedIndex].label),
                          actions: globals.winLinDesktop
                              ? [
                                  IconButton(
                                    tooltip: '最小化',
                                    onPressed: _minimizeWindow,
                                    icon: const Icon(
                                        Icons.horizontal_rule_rounded),
                                  ),
                                  IconButton(
                                    tooltip: _isMaximized ? '还原' : '最大化',
                                    onPressed: _toggleWindowSize,
                                    icon: Icon(
                                      _isMaximized
                                          ? Icons.filter_none_rounded
                                          : Icons.crop_square_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '关闭',
                                    onPressed: _closeWindow,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                  const SizedBox(width: 8),
                                ]
                              : null,
                        )
                      : null,
                  body: !shouldShowAppBar
                      ? body
                      : isCompact
                          ? body
                          : Row(
                              children: [
                                navigation,
                                const VerticalDivider(width: 1),
                                Expanded(child: body),
                              ],
                            ),
                  bottomNavigationBar: shouldShowAppBar && isCompact
                      ? Consumer<BottomBarProvider>(
                          builder: (context, bottomBarProvider, _) {
                            if (!bottomBarProvider.useNativeBottomBar) {
                              return const SizedBox.shrink();
                            }
                            return navigation;
                          },
                        )
                      : null,
                ),
                if (_showSplash)
                  const Positioned.fill(
                    child: SplashScreen(key: ValueKey('material_splash')),
                  ),
                if (globals.winLinDesktop && shouldShowAppBar)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 120,
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: GestureDetector(
                        onDoubleTap: _toggleWindowSize,
                        onPanStart: (_) async => windowManager.startDragging(),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MaterialDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;

  const _MaterialDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });
}
