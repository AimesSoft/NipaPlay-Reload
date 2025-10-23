import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/pages/cupertino/cupertino_home_page.dart';
import 'package:nipaplay/pages/cupertino/cupertino_media_library_page.dart';
import 'package:nipaplay/pages/cupertino/cupertino_settings_page.dart';

class CupertinoMainPage extends StatefulWidget {
  final String? launchFilePath;

  const CupertinoMainPage({super.key, this.launchFilePath});

  @override
  State<CupertinoMainPage> createState() => _CupertinoMainPageState();
}

class _CupertinoMainPageState extends State<CupertinoMainPage> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    CupertinoHomePage(),
    CupertinoMediaLibraryPage(),
    CupertinoSettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        useNativeBottomBar: true,
        items: [
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS ? 'house.fill' : Icons.home_filled,
            label: '主页',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS ? 'play.rectangle.fill' : Icons.video_library_rounded,
            label: '媒体库',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS ? 'gearshape.fill' : Icons.settings_rounded,
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
        },
      ),
    );
  }
}
