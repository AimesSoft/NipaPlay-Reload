import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/themes/cupertino/pages/account/cupertino_account_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_home_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_media_library_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_play_video_page.dart';
import 'package:nipaplay/themes/cupertino/pages/cupertino_settings_page.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bounce_wrapper.dart';

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

  final List<GlobalKey<CupertinoBounceWrapperState>> _bounceKeys = [
    GlobalKey<CupertinoBounceWrapperState>(),
    GlobalKey<CupertinoBounceWrapperState>(),
    GlobalKey<CupertinoBounceWrapperState>(),
    GlobalKey<CupertinoBounceWrapperState>(),
  ];

  static const List<Widget> _pages = [
    CupertinoHomePage(),
    CupertinoMediaLibraryPage(),
    CupertinoAccountPage(),
    CupertinoSettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CupertinoBounceWrapper.playAnimation(_bounceKeys[_selectedIndex]);
      _tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
      _tabChangeNotifier?.addListener(_handleTabChange);
    });
  }

  @override
  void dispose() {
    _tabChangeNotifier?.removeListener(_handleTabChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cupertinoTheme = CupertinoTheme.of(context);
    final Color activeColor = cupertinoTheme.primaryColor;
    final Color inactiveColor =
        CupertinoDynamicColor.resolve(CupertinoColors.inactiveGray, context);

    return Consumer<BottomBarProvider>(
      builder: (context, bottomBarProvider, _) {
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
          bottomNavigationBar: AdaptiveBottomNavigationBar(
            useNativeBottomBar: bottomBarProvider.useNativeBottomBar,
            selectedItemColor: activeColor,
            unselectedItemColor: inactiveColor,
            items: const [
              AdaptiveNavigationDestination(
                icon: 'house.fill',
                label: '主页',
              ),
              AdaptiveNavigationDestination(
                icon: 'play.rectangle.fill',
                label: '媒体库',
              ),
              AdaptiveNavigationDestination(
                icon: 'person.crop.circle.fill',
                label: '账户',
              ),
              AdaptiveNavigationDestination(
                icon: 'gearshape.fill',
                label: '设置',
              ),
            ],
            selectedIndex: _selectedIndex,
            onTap: _selectTab,
          ),
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
