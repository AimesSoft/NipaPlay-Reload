import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

/// Demo page showcasing AdaptiveButton features
class DemoTabbarPage extends StatefulWidget {
  const DemoTabbarPage({super.key});

  @override
  State<DemoTabbarPage> createState() => _DemoTabbarPageState();
}

class _DemoTabbarPageState extends State<DemoTabbarPage> {
  int _selectedIndex = 0;

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return const HomeScreen();
      case 1:
        return const ProfileScreen();
      case 2:
        return const SearchScreen();
      default:
        return const HomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tabbar Demos')),
        bottomNavigationBar: BottomNavigationBar(
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          ],
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              if (kDebugMode) {
                print('Index selected: $index');
              }
              _selectedIndex = index;
            });
          },
        ),
        body: _buildCurrentScreen(),
      );
    }

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: 'Tabbar Demos',
        actions: [
          AdaptiveAppBarAction(onPressed: () {}, title: "Title"),
          AdaptiveAppBarAction(
            onPressed: () {},
            icon: Icons.info,
            iosSymbol: "info.circle",
          ),
        ],
      ),
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            if (kDebugMode) {
              print('Index selected: $index');
            }
            _selectedIndex = index;
          });
        },

        items: [
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "house.fill"
                : PlatformInfo.isIOS
                ? CupertinoIcons.home
                : Icons.home_outlined,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? "house.fill"
                : PlatformInfo.isIOS
                ? CupertinoIcons.home
                : Icons.home,
            label: 'Home',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "person.fill"
                : PlatformInfo.isIOS
                ? CupertinoIcons.person
                : Icons.person_outline,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? "person.fill"
                : PlatformInfo.isIOS
                ? CupertinoIcons.person_fill
                : Icons.person,
            label: 'Profile',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "magnifyingglass"
                : PlatformInfo.isIOS
                ? CupertinoIcons.search
                : Icons.search,
            label: 'Search',
            isSearch: true,
          ),
        ],
      ),

      // body is automatically wrapped into a single-item children list for iOS26Scaffold
      // The scaffold handles showing the content based on selectedIndex
      body: _buildCurrentScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    if (kDebugMode) {
      print("Home Screen initState called");
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return const Text("Home Screen");
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    if (kDebugMode) {
      print("Profile Screen initState called");
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return const Text("Profile Screen");
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  @override
  void initState() {
    if (kDebugMode) {
      print("Search Screen initState called");
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
