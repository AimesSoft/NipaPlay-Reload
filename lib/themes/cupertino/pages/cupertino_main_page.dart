import 'package:nipaplay/app/app_navigation_scope.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_pages.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_app_page_actions.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bounce_wrapper.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:provider/provider.dart';

class CupertinoMainPage extends StatefulWidget {
  const CupertinoMainPage({super.key, this.launchFilePath});

  final String? launchFilePath;

  @override
  State<CupertinoMainPage> createState() => _CupertinoMainPageState();
}

class _CupertinoMainPageState extends State<CupertinoMainPage> {
  String _selectedPageId = AppPageIds.home;
  bool _showWebDAV = false;
  bool _showDownloader = false;
  bool _didApplyInitialPage = false;

  TabChangeNotifier? _tabChangeNotifier;
  WebDAVQuickAccessProvider? _webdavProvider;
  DownloaderSettingsProvider? _downloaderProvider;
  PluginService? _pluginService;

  final Map<String, GlobalKey<CupertinoBounceWrapperState>> _bounceKeys =
      <String, GlobalKey<CupertinoBounceWrapperState>>{};

  List<UnifiedAppPage> get _pages => buildUnifiedAppPages(
        availability: AppPageAvailability(
          showWebDAV: _showWebDAV,
          showDownloader: _showDownloader,
        ),
      );

  int get _selectedIndex {
    final index = appPageIndexById(_pages, _selectedPageId);
    return index < 0 ? 0 : index;
  }

  GlobalKey<CupertinoBounceWrapperState> _bounceKey(String pageId) {
    return _bounceKeys.putIfAbsent(
      pageId,
      () => GlobalKey<CupertinoBounceWrapperState>(),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (!mounted) return;

    _tabChangeNotifier = context.read<TabChangeNotifier>()
      ..addListener(_handleNavigationRequest);
    _webdavProvider = context.read<WebDAVQuickAccessProvider>()
      ..addListener(_handleWebDAVChanged);
    await _webdavProvider?.loadSettings();
    if (!mounted) return;

    _downloaderProvider = context.read<DownloaderSettingsProvider>()
      ..addListener(_handleDownloaderChanged);
    _pluginService = context.read<PluginService>()
      ..addListener(_handleDownloaderChanged);
    PluginService.setBuildContext(context);

    final downloader = _downloaderProvider;
    setState(() {
      _showWebDAV = _webdavProvider?.showWebDAVTab ?? false;
      _showDownloader = globals.isDownloaderSupportedPlatform &&
          (downloader == null || !downloader.isLoaded || downloader.enabled);
      _applyInitialPage();
    });
    _playBounce(_selectedPageId);
  }

  void _applyInitialPage() {
    if (_didApplyInitialPage) return;
    _didApplyInitialPage = true;
    _selectedPageId = effectiveAppPageId(
      _pages,
      _webdavProvider?.effectiveDefaultHomeTab,
    );
  }

  void _handleWebDAVChanged() {
    if (!mounted) return;
    final show = _webdavProvider?.showWebDAVTab ?? false;
    if (show == _showWebDAV) return;
    setState(() {
      _showWebDAV = show;
      _selectedPageId = effectiveAppPageId(_pages, _selectedPageId);
    });
  }

  void _handleDownloaderChanged() {
    if (!mounted) return;
    final provider = _downloaderProvider;
    if (provider == null || !provider.isLoaded) return;
    final show = globals.isDownloaderSupportedPlatform && provider.enabled;
    if (show == _showDownloader) return;
    setState(() {
      _showDownloader = show;
      _selectedPageId = effectiveAppPageId(_pages, _selectedPageId);
    });
  }

  @override
  void dispose() {
    _tabChangeNotifier?.removeListener(_handleNavigationRequest);
    _webdavProvider?.removeListener(_handleWebDAVChanged);
    _downloaderProvider?.removeListener(_handleDownloaderChanged);
    _pluginService?.removeListener(_handleDownloaderChanged);
    super.dispose();
  }

  void _handleNavigationRequest() {
    final notifier = _tabChangeNotifier;
    if (notifier == null) return;
    final pageId = notifier.targetPageId ??
        AppPageIds.fromLegacyIndex(notifier.targetTabIndex ?? -1);
    if (pageId == null) return;
    _selectPage(pageId);
    notifier.clearMainTabIndex();
  }

  void _selectPage(String pageId) {
    final effectiveId = effectiveAppPageId(_pages, pageId);
    if (effectiveId == _selectedPageId) return;
    setState(() => _selectedPageId = effectiveId);
    _playBounce(effectiveId);
  }

  void _selectIndex(int index) {
    final pages = _pages;
    if (index < 0 || index >= pages.length) return;
    _selectPage(pages[index].id);
  }

  void _playBounce(String pageId) {
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      CupertinoBounceWrapper.playAnimation(_bounceKey(pageId));
    });
  }

  List<BottomNavigationBarItem> _buildCupertinoItems(
    BuildContext context,
    List<UnifiedAppPage> pages,
  ) {
    return pages
        .map(
          (page) => BottomNavigationBarItem(
            icon: Icon(page.phoneIcon),
            activeIcon: Icon(page.phoneActiveIcon),
            label: page.title(context.l10n),
          ),
        )
        .toList(growable: false);
  }

  List<AdaptiveNavigationDestination> _buildNativeItems(
    BuildContext context,
    List<UnifiedAppPage> pages,
  ) {
    return pages
        .map(
          (page) => AdaptiveNavigationDestination(
            icon: page.phoneSymbol,
            selectedIcon: page.phoneActiveSymbol,
            label: page.title(context.l10n),
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final selectedIndex = _selectedIndex;
    final selectedPage = pages[selectedIndex];
    final activeColor = AppAccentColors.current;
    final inactiveColor = CupertinoDynamicColor.resolve(
      CupertinoColors.inactiveGray,
      context,
    );
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final tabBarHeight = bottomInset > 0 ? 56.0 : 50.0;

    return Consumer<BottomBarProvider>(
      builder: (context, bottomBar, _) {
        final body = AppNavigationScope(
          selectedPageId: selectedPage.id,
          pageIds: pages.map((page) => page.id).toList(growable: false),
          onSelectPage: _selectPage,
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 90),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey<String>(selectedPage.id),
                  child: CupertinoBounceWrapper(
                    key: _bounceKey(selectedPage.id),
                    autoPlay: false,
                    child: selectedPage.build(context, AppDisplaySurface.phone),
                  ),
                ),
              ),
              if (selectedPage.actionIds.isNotEmpty)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 4,
                  right: 12 + MediaQuery.paddingOf(context).right,
                  child: CupertinoAppPageActions(
                    actionIds: selectedPage.actionIds,
                  ),
                ),
            ],
          ),
        );

        final cupertinoTabBar = CupertinoTabBar(
          currentIndex: selectedIndex,
          onTap: _selectIndex,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          height: tabBarHeight,
          items: _buildCupertinoItems(context, pages),
        );

        if (PlatformInfo.isIOS26OrHigher()) {
          return AdaptiveScaffold(
            minimizeBehavior: TabBarMinimizeBehavior.never,
            enableBlur: true,
            body: body,
            bottomNavigationBar: bottomBar.isBottomBarVisible
                ? AdaptiveBottomNavigationBar(
                    useNativeBottomBar: bottomBar.useNativeBottomBar,
                    selectedItemColor: activeColor,
                    unselectedItemColor: inactiveColor,
                    cupertinoTabBar: cupertinoTabBar,
                    items: _buildNativeItems(context, pages),
                    selectedIndex: selectedIndex,
                    onTap: _selectIndex,
                  )
                : null,
          );
        }

        // Android and older iOS deliberately use Cupertino controls. This is
        // the phone renderer's non-Material fallback.
        return CupertinoPageScaffold(
          child: Column(
            children: [
              Expanded(child: body),
              if (bottomBar.isBottomBarVisible) cupertinoTabBar,
            ],
          ),
        );
      },
    );
  }
}
