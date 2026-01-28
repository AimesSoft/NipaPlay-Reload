import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui_example/service/router/router_service.dart';
import 'package:adaptive_platform_ui_example/utils/constants/route_constants.dart';
import 'package:adaptive_platform_ui_example/utils/global_variables.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainPage extends StatefulWidget {
  const MainPage({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AdaptiveScaffold(
          minimizeBehavior: TabBarMinimizeBehavior.automatic,
          body: widget.navigationShell,
          bottomNavigationBar:
              getMatchedLocation(
                context,
              ).contains(RouteConstants().badgeNavigation)
              ? null
              : AdaptiveBottomNavigationBar(
                  selectedIndex: widget.navigationShell.currentIndex,
                  onTap: (index) => onDestinationSelected(index, context),
                  items: [
                    AdaptiveNavigationDestination(
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? "house.fill"
                          : PlatformInfo.isIOS
                          ? CupertinoIcons.home
                          : Icons.home_outlined,

                      selectedIcon: PlatformInfo.isIOS
                          ? CupertinoIcons.home
                          : Icons.home,
                      label: 'Home',
                      badgeCount: 1,
                    ),
                    AdaptiveNavigationDestination(
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? "info.circle"
                          : PlatformInfo.isIOS
                          ? CupertinoIcons.info
                          : Icons.info_outline,
                      selectedIcon: PlatformInfo.isIOS
                          ? CupertinoIcons.info
                          : Icons.info,
                      label: 'Info',
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
        ),
      ],
    );
  }

  void onDestinationSelected(tappedIndex, BuildContext context) {
    // scroll to top if the user taps the current tab
    var matchedLocation = getMatchedLocation(context);

    if (widget.navigationShell.currentIndex == tappedIndex) {
      bool shouldNavigateToRoot = false;

      switch (tappedIndex) {
        case 0:
          if (matchedLocation != RouterService.routes.home) {
            shouldNavigateToRoot = true;
          } else {
            homeScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
          break;
        case 1:
          if (matchedLocation != RouterService.routes.info) {
            shouldNavigateToRoot = true;
          } else {
            infoScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
          break;
        case 2:
          if (matchedLocation != RouterService.routes.search) {
            shouldNavigateToRoot = true;
          } else {
            // searchScrollController.animateTo(
            //   0,
            //   duration: const Duration(milliseconds: 500),
            //   curve: Curves.easeInOut,
            // );
          }
          break;
      }

      if (shouldNavigateToRoot) {
        // Pop until we reach the root of the current branch
        widget.navigationShell.goBranch(tappedIndex, initialLocation: true);
        return;
      }
      return;
    }

    widget.navigationShell.goBranch(tappedIndex);
  }

  String getMatchedLocation(BuildContext context) {
    return GoRouter.of(
      navigatorKey.currentContext!,
    ).routerDelegate.currentConfiguration.last.matchedLocation;
  }
}
