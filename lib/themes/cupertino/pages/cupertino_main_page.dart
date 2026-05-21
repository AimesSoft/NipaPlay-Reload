import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

import 'package:nipaplay/themes/cupertino/pages/account/cupertino_account_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_home_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_media_library_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_play_video_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_settings_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_torrent_download_page.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bounce_wrapper.dart';
import 'package:nipaplay/pages/webdav_browser_page.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

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
  bool _showDownloaderTab = false;
  WebDAVQuickAccessProvider? _webdavProvider;
  DownloaderSettingsProvider? _downloaderProvider;
  PluginService? _pluginService;
  String? _lastAppliedDefaultTab;
  List<GlobalKey<CupertinoBounceWrapperState>> _bounceKeys = [];

  static const List<Widget> _basePages = [
    CupertinoHomePage(),
    CupertinoMediaLibraryPage(),
    CupertinoAccountPage(),
    CupertinoSettingsPage(),
  ];

  List<Widget> get _pages {
    final pages = <Widget>[];
    // 0: Home
    pages.add(_basePages[0]);
    // 1: WebDAV (optional)
    if (_showWebDAVTab) {
      pages.add(const WebDAVBrowserPage());
    }
    // Next: Media Library
    pages.add(_basePages[1]);
    // Next: Account
    pages.add(_basePages[2]);
    // Next: Downloader (optional)
    if (_showDownloaderTab) {
      pages.add(const CupertinoTorrentDownloadPage());
    }
    // Last: Settings
    pages.add(_basePages[3]);
    return pages;
  }

  List<BottomNavigationBarItem> _buildNavItems(BuildContext context) {
    final l10n = context.l10n;
    final items = <BottomNavigationBarItem>[];
    items.add(BottomNavigationBarItem(
      icon: Icon(CupertinoIcons.house),
      activeIcon: Icon(CupertinoIcons.house_fill),
      label: l10n.tabHome,
    ));
    if (_showWebDAVTab) {
      items.add(const BottomNavigationBarItem(
        icon: Icon(CupertinoIcons.cloud),
        activeIcon: Icon(CupertinoIcons.cloud_fill),
        label: 'WebDAV',
      ));
    }
    items.add(BottomNavigationBarItem(
      icon: Icon(CupertinoIcons.play_rectangle),
      activeIcon: Icon(CupertinoIcons.play_rectangle_fill),
      label: l10n.tabMediaLibrary,
    ));
    items.add(BottomNavigationBarItem(
      icon: Icon(CupertinoIcons.person_crop_circle),
      activeIcon: Icon(CupertinoIcons.person_crop_circle_fill),
      label: l10n.tabAccount,
    ));
    if (_showDownloaderTab) {
      items.add(BottomNavigationBarItem(
        icon: const Icon(CupertinoIcons.arrow_down_circle),
        activeIcon: const Icon(CupertinoIcons.arrow_down_circle_fill),
        label: l10n.tabTorrentDownload,
      ));
    }
    items.add(BottomNavigationBarItem(
      icon: Icon(CupertinoIcons.gear_alt),
      activeIcon: Icon(CupertinoIcons.gear_alt_fill),
      label: l10n.tabSettings,
    ));
    return items;
  }

  List<AdaptiveNavigationDestination> _buildAdaptiveNavItems(
      BuildContext context) {
    final l10n = context.l10n;
    final items = <AdaptiveNavigationDestination>[];
    items.add(AdaptiveNavigationDestination(
      icon: 'house.fill',
      label: l10n.tabHome,
    ));
    if (_showWebDAVTab) {
      items.add(const AdaptiveNavigationDestination(
        icon: 'cloud.fill',
        label: 'WebDAV',
      ));
    }
    items.add(AdaptiveNavigationDestination(
      icon: 'play.rectangle.fill',
      label: l10n.tabMediaLibrary,
    ));
    items.add(AdaptiveNavigationDestination(
      icon: 'person.crop.circle.fill',
      label: l10n.tabAccount,
    ));
    if (_showDownloaderTab) {
      items.add(AdaptiveNavigationDestination(
        icon: 'arrow.down.circle.fill',
        label: l10n.tabTorrentDownload,
      ));
    }
    items.add(AdaptiveNavigationDestination(
      icon: 'gearshape.fill',
      label: l10n.tabSettings,
    ));
    return items;
  }

  void _updateBounceKeys() {
    final neededKeys = _pages.length;
    while (_bounceKeys.length < neededKeys) {
      _bounceKeys.add(GlobalKey<CupertinoBounceWrapperState>());
    }
  }

  int _getInitialTabIndex() {
    final defaultTab = _webdavProvider?.effectiveDefaultHomeTab ??
        WebDAVQuickAccessProvider.tabHome;

    switch (defaultTab) {
      case WebDAVQuickAccessProvider.tabHome:
        return 0;
      case WebDAVQuickAccessProvider.tabWebDAV:
        return _showWebDAVTab ? 1 : 0;
      case WebDAVQuickAccessProvider.tabMediaLibrary:
        return _mediaLibraryIndex;
      case WebDAVQuickAccessProvider.tabTorrent:
        return _showDownloaderTab ? _downloaderIndex : 0;
      case WebDAVQuickAccessProvider.tabAccount:
        return _accountIndex;
      case WebDAVQuickAccessProvider.tabSettings:
        return _settingsIndex;
      default:
        return 0;
    }
  }

  int get _mediaLibraryIndex => _showWebDAVTab ? 2 : 1;
  int get _accountIndex => _mediaLibraryIndex + 1;
  int get _downloaderIndex => _showDownloaderTab ? _accountIndex + 1 : -1;
  int get _settingsIndex => _accountIndex + (_showDownloaderTab ? 2 : 1);

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

  void _onDownloaderSettingsChanged() {
    if (!mounted) return;
    final provider = _downloaderProvider;
    if (provider == null || !provider.isLoaded) return;
    final showDownloaderTab =
        globals.isDownloaderSupportedPlatform && provider.enabled;
    if (showDownloaderTab != _showDownloaderTab) {
      setState(() {
        _showDownloaderTab = showDownloaderTab;
        _updateBounceKeys();
        _selectedIndex = _selectedIndex.clamp(0, _pages.length - 1);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _updateBounceKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _tabChangeNotifier =
          Provider.of<TabChangeNotifier>(context, listen: false);
      _tabChangeNotifier?.addListener(_handleTabChange);
      _webdavProvider =
          Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
      _webdavProvider?.addListener(_onWebDAVSettingsChanged);
      await _webdavProvider?.loadSettings();

      _downloaderProvider =
          Provider.of<DownloaderSettingsProvider>(context, listen: false);
      _downloaderProvider?.addListener(_onDownloaderSettingsChanged);

      _pluginService = Provider.of<PluginService>(context, listen: false);
      _pluginService?.addListener(_onDownloaderSettingsChanged);
      PluginService.setBuildContext(context);

      if (mounted) {
        final dlProvider = _downloaderProvider;
        setState(() {
          _showWebDAVTab = _webdavProvider?.showWebDAVTab ?? false;
          _showDownloaderTab = globals.isDownloaderSupportedPlatform &&
              (dlProvider == null ||
                  !dlProvider.isLoaded ||
                  dlProvider.enabled);
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
    _downloaderProvider?.removeListener(_onDownloaderSettingsChanged);
    _pluginService?.removeListener(_onDownloaderSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor = AppAccentColors.current;
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
