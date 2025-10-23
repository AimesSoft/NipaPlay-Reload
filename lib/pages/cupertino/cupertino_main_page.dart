import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:nipaplay/pages/cupertino/cupertino_home_page.dart';
import 'package:nipaplay/pages/cupertino/cupertino_media_library_page.dart';
import 'package:nipaplay/pages/cupertino/cupertino_settings_page.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_bounce_wrapper.dart';

class CupertinoMainPage extends StatefulWidget {
  final String? launchFilePath;

  const CupertinoMainPage({super.key, this.launchFilePath});

  @override
  State<CupertinoMainPage> createState() => _CupertinoMainPageState();
}

class _CupertinoMainPageState extends State<CupertinoMainPage> {
  int _selectedIndex = 0;

  // 为每个页面创建bounce控制器的GlobalKey
  final List<GlobalKey<CupertinoBounceWrapperState>> _bounceKeys = [
    GlobalKey<CupertinoBounceWrapperState>(),
    GlobalKey<CupertinoBounceWrapperState>(),
    GlobalKey<CupertinoBounceWrapperState>(),
  ];

  static const List<Widget> _pages = [
    CupertinoHomePage(),
    CupertinoMediaLibraryPage(),
    CupertinoSettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // 首次进入时触发初始页面的动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CupertinoBounceWrapper.playAnimation(_bounceKeys[_selectedIndex]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      minimizeBehavior: TabBarMinimizeBehavior.never,
      enableBlur: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages.asMap().entries.map((entry) {
          final index = entry.key;
          final page = entry.value;
          return CupertinoBounceWrapper(
            key: _bounceKeys[index],
            autoPlay: false, // 禁用自动播放，手动控制
            child: page,
          );
        }).toList(),
      ),
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        useNativeBottomBar: true,
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
            icon: 'gearshape.fill',
            label: '设置',
          ),
        ],
        selectedIndex: _selectedIndex,
        onTap: (index) {
          if (_selectedIndex == index) {
            return;
          }
          setState(() {
            _selectedIndex = index;
          });
          // 切换页面时触发bounce动画
          CupertinoBounceWrapper.playAnimation(_bounceKeys[index]);
        },
      ),
    );
  }
}
