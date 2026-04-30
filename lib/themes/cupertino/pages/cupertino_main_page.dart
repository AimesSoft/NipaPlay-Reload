import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/themes/cupertino/pages/account/cupertino_account_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_home_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_media_library_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_play_video_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_settings_page.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bounce_wrapper.dart';
import 'package:nipaplay/pages/webdav_browser_page.dart';

class CupertinoMainPage extends StatefulWidget {
  final String? launchFilePath;

  const CupertinoMainPage({super.key, this.launchFilePath});

  @override
  State<CupertinoMainPage> createState() => _CupertinoMainPageState();
}

class _CupertinoMainPageState extends State<CupertinoMainPage> {
  int _selectedIndex = 0;
  TabChangeNotifier? _tabChangeNotifier;
  bool _isVideoPagePresented = false;
  bool _showWebDAVTab = false;
  WebDAVQuickAccessProvider? _webdavProvider;
  String? _lastAppliedDefaultTab;
  List<GlobalKey<CupertinoBounceWrapperState>> _bounceKeys = [];

  static const List<Widget> _basePages = [
    CupertinoHomePage(),
    CupertinoMediaLibraryPage(),
    CupertinoAccountPage(),
    CupertinoSettingsPage(),
  ];

  List<Widget> get _pages {
    if (_showWebDAVTab) {
      return [
        _basePages[0],
        const WebDAVBrowserPage(),
        _basePages[1],
        _basePages[2],
        _basePages[3],
      ];
    }
    return _basePages;
  }

  List<BottomNavigationBarItem> _buildNavItems(BuildContext context) {
    final l10n = context.l10n;
    if (_showWebDAVTab) {
      return [
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.house),
          activeIcon: const Icon(CupertinoIcons.house_fill),
          label: l10n.tabHome,
        ),
        const BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.cloud),
          activeIcon: Icon(CupertinoIcons.cloud_fill),
          label: 'WebDAV',
        ),
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.play_rectangle),
          activeIcon: const Icon(CupertinoIcons.play_rectangle_fill),
          label: l10n.tabMediaLibrary,
        ),
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.person_crop_circle),
          activeIcon: const Icon(CupertinoIcons.person_crop_circle_fill),
          label: l10n.tabAccount,
        ),
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.gear_alt),
          activeIcon: const Icon(CupertinoIcons.gear_alt_fill),
          label: l10n.tabSettings,
        ),
      ];
    }
    return [
      BottomNavigationBarItem(
        icon: const Icon(CupertinoIcons.house),
        activeIcon: const Icon(CupertinoIcons.house_fill),
        label: l10n.tabHome,
      ),
      BottomNavigationBarItem(
        icon: const Icon(CupertinoIcons.play_rectangle),
        activeIcon: const Icon(CupertinoIcons.play_rectangle_fill),
        label: l10n.tabMediaLibrary,
      ),
      BottomNavigationBarItem(
        icon: const Icon(CupertinoIcons.person_crop_circle),
        activeIcon: const Icon(CupertinoIcons.person_crop_circle_fill),
        label: l10n.tabAccount,
      ),
      BottomNavigationBarItem(
        icon: const Icon(CupertinoIcons.gear_alt),
        activeIcon: const Icon(CupertinoIcons.gear_alt_fill),
        label: l10n.tabSettings,
      ),
    ];
  }

  List<AdaptiveNavigationDestination> _buildAdaptiveNavItems(BuildContext context) {
    final l10n = context.l10n;
    if (_showWebDAVTab) {
      return [
        AdaptiveNavigationDestination(
          icon: 'house.fill',
          label: l10n.tabHome,
        ),
        const AdaptiveNavigationDestination(
          icon: 'cloud.fill',
          label: 'WebDAV',
        ),
        AdaptiveNavigationDestination(
          icon: 'play.rectangle.fill',
          label: l10n.tabMediaLibrary,
        ),
        AdaptiveNavigationDestination(
          icon: 'person.crop.circle.fill',
          label: l10n.tabAccount,
        ),
        AdaptiveNavigationDestination(
          icon: 'gearshape.fill',
          label: l10n.tabSettings,
        ),
      ];
    }
    return [
      AdaptiveNavigationDestination(
        icon: 'house.fill',
        label: l10n.tabHome,
      ),
      AdaptiveNavigationDestination(
        icon: 'play.rectangle.fill',
        label: l10n.tabMediaLibrary,
      ),
      AdaptiveNavigationDestination(
        icon: 'person.crop.circle.fill',
        label: l10n.tabAccount,
      ),
      AdaptiveNavigationDestination(
        icon: 'gearshape.fill',
        label: l10n.tabSettings,
      ),
    ];
  }

  void _updateBounceKeys() {
    final neededKeys = _pages.length;
    while (_bounceKeys.length < neededKeys) {
      _bounceKeys.add(GlobalKey<CupertinoBounceWrapperState>());
    }
  }

  int _getInitialTabIndex() {
    final defaultTab = _webdavProvider?.effectiveDefaultHomeTab ?? WebDAVQuickAccessProvider.tabHome;

    switch (defaultTab) {
      case WebDAVQuickAccessProvider.tabHome:
        return 0;
      case WebDAVQuickAccessProvider.tabWebDAV:
        return _showWebDAVTab ? 1 : 0;
      case WebDAVQuickAccessProvider.tabMediaLibrary:
        return _showWebDAVTab ? 2 : 1;
      case WebDAVQuickAccessProvider.tabAccount:
        return _showWebDAVTab ? 3 : 2;
      case WebDAVQuickAccessProvider.tabSettings:
        return _showWebDAVTab ? 4 : 3;
      default:
        return 0;
    }
  }

  void _onWebDAVSettingsChanged() {
    if (!mounted) return;
    final showWebDAVTab = _webdavProvider?.showWebDAVTab ?? false;
    final shouldUpdate = showWebDAVTab != _showWebDAVTab ||
        _webdavProvider?.defaultHomeTab != _lastAppliedDefaultTab;

    if (shouldUpdate) {
      setState(() {
        _showWebDAVTab = showWebDAVTab;
        _lastAppliedDefaultTab = _webdavProvider?.defaultHomeTab;
        _updateBounceKeys();
        _selectedIndex = _getInitialTabIndex().clamp(0, _pages.length - 1);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _updateBounceKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
      _tabChangeNotifier?.addListener(_handleTabChange);
      _webdavProvider = Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
      _webdavProvider?.addListener(_onWebDAVSettingsChanged);
      await _webdavProvider?.loadSettings();

      if (mounted) {
        setState(() {
          _showWebDAVTab = _webdavProvider?.showWebDAVTab ?? false;
          _updateBounceKeys();
          _selectedIndex = _getInitialTabIndex();
        });
        CupertinoBounceWrapper.playAnimation(_bounceKeys[_selectedIndex]);
      }
    });
  }

  @override
  void dispose() {
    _tabChangeNotifier?.removeListener(_handleTabChange);
    _webdavProvider?.removeListener(_onWebDAVSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const Color activeColor = Color(0xFFFF2E55);
    final Color inactiveColor =
        CupertinoDynamicColor.resolve(CupertinoColors.inactiveGray, context);
    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final double tabBarHeight = bottomInset > 0 ? 56.0 : 50.0;

    return Consumer<BottomBarProvider>(
      builder: (context, bottomBarProvider, _) {
        final bool showBottomBar = bottomBarProvider.isBottomBarVisible;
        return AdaptiveScaffold(
          minimizeBehavior: TabBarMinimizeBehavior.never,
          enableBlur: true,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 50),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedIndex),
              child: CupertinoBounceWrapper(
                key: _bounceKeys[_selectedIndex],
                autoPlay: false,
                child: _pages[_selectedIndex],
              ),
            ),
          ),
          bottomNavigationBar: showBottomBar
              ? AdaptiveBottomNavigationBar(
                  useNativeBottomBar: bottomBarProvider.useNativeBottomBar,
                  selectedItemColor: activeColor,
                  unselectedItemColor: inactiveColor,
                  cupertinoTabBar: CupertinoTabBar(
                    currentIndex: _selectedIndex,
                    onTap: _selectTab,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    height: tabBarHeight,
                    items: _buildNavItems(context),
                  ),
                  items: _buildAdaptiveNavItems(context),
                  selectedIndex: _selectedIndex,
                  onTap: _selectTab,
                )
              : null,
        );
      },
    );
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      return;
    }
    if (index >= _pages.length) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        CupertinoBounceWrapper.playAnimation(_bounceKeys[index]);
      }
    });
  }

  void _handleTabChange() {
    final notifier = _tabChangeNotifier;
    if (notifier == null) return;

    final targetIndex = notifier.targetTabIndex;
    if (targetIndex == null) {
      return;
    }

    if (targetIndex == 1) {
      _presentVideoPage();
      notifier.clearMainTabIndex();
      return;
    }

    final int clampedIndex = targetIndex.clamp(0, _pages.length - 1).toInt();
    _selectTab(clampedIndex);
    notifier.clearMainTabIndex();
  }

  Future<void> _presentVideoPage() async {
    if (_isVideoPagePresented || !mounted) {
      return;
    }

    _isVideoPagePresented = true;
    final bottomBarProvider = context.read<BottomBarProvider>();
    bottomBarProvider.hideBottomBar();
    try {
      await Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const CupertinoPlayVideoPage(),
        ),
      );
    } finally {
      bottomBarProvider.showBottomBar();
      if (mounted) {
        _isVideoPagePresented = false;
      }
    }
  }

}
