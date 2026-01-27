import 'package:adaptive_platform_ui_example/main/main_page.dart';
import 'package:adaptive_platform_ui_example/pages/home/home_page.dart';
import 'package:adaptive_platform_ui_example/pages/info/info_page.dart';
import 'package:adaptive_platform_ui_example/pages/search/search_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/alert_dialog_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/badge_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/badge_navigation_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/button_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/card_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/checkbox_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/context_menu_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/demo_tabbar_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/native_search_tab_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/popup_menu_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/radio_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/segmented_control_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/slider_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/snackbar_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/switch_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/tooltip_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/date_picker_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/time_picker_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/list_tile_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/text_field_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/tab_view_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/floating_action_button_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/form_section_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/expansion_tile_demo_page.dart';
import 'package:adaptive_platform_ui_example/pages/demos/blur_view_demo_page.dart';
import 'package:adaptive_platform_ui_example/utils/constants/route_constants.dart';
import 'package:adaptive_platform_ui_example/utils/global_variables.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RouterService {
  static RouteConstants routes = RouteConstants();

  // Navigator keys for each branch

  static void push({
    required BuildContext context,
    required String route,
    Map<String, String>? parameter,
  }) {
    GoRouter.of(context).push("/$route", extra: parameter);
  }

  static void goNamed({
    required BuildContext context,
    required String route,
    Map<String, String> pathParameters = const {},
    Object? extra,
  }) {
    context.goNamed(route, extra: extra, pathParameters: pathParameters);
  }

  static Future<T?> pushNamed<T extends Object?>({
    required BuildContext context,
    required String route,
    Object? extra,
  }) async {
    return await context.pushNamed(route, extra: extra);
  }

  static void go({required BuildContext context, required String route}) {
    GoRouter.of(context).go("/$route");
  }

  static void pop({required BuildContext context}) {
    GoRouter.of(context).pop();
  }

  static void pushReplacementNamed({
    required BuildContext context,
    required String route,
  }) {
    GoRouter.of(context).pushReplacementNamed("/$route");
  }

  final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) {
              return MainPage(navigationShell: navigationShell);
            },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                name: routes.home,
                path: routes.home,
                pageBuilder: (context, state) {
                  return CustomTransitionPage(
                    child: const HomePage(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          // fastOutSlowIn eğrisini SlideTransition ile uygula
                          return FadeTransition(
                            opacity: CurveTween(
                              curve: Curves.easeIn,
                            ).animate(animation),
                            child: child,
                          );
                        },
                  );
                },
                routes: [
                  GoRoute(
                    name: routes.demoTabbar,
                    path: routes.demoTabbar,
                    builder: (context, state) => const DemoTabbarPage(),
                  ),
                  GoRoute(
                    name: routes.button,
                    path: routes.button,
                    builder: (context, state) => const ButtonDemoPage(),
                  ),
                  GoRoute(
                    name: routes.alertDialog,
                    path: routes.alertDialog,
                    builder: (context, state) => const AlertDialogDemoPage(),
                  ),
                  GoRoute(
                    name: routes.popupMenu,
                    path: routes.popupMenu,
                    builder: (context, state) => const PopupMenuDemoPage(),
                  ),
                  GoRoute(
                    name: routes.contextMenu,
                    path: routes.contextMenu,
                    builder: (context, state) => const ContextMenuDemoPage(),
                  ),
                  GoRoute(
                    name: routes.slider,
                    path: routes.slider,
                    builder: (context, state) => const SliderDemoPage(),
                  ),
                  GoRoute(
                    name: routes.switchDemo,
                    path: routes.switchDemo,
                    builder: (context, state) => const SwitchDemoPage(),
                  ),
                  GoRoute(
                    name: routes.checkbox,
                    path: routes.checkbox,
                    builder: (context, state) => const CheckboxDemoPage(),
                  ),
                  GoRoute(
                    name: routes.radio,
                    path: routes.radio,
                    builder: (context, state) => const RadioDemoPage(),
                  ),
                  GoRoute(
                    name: routes.card,
                    path: routes.card,
                    builder: (context, state) => const CardDemoPage(),
                  ),
                  GoRoute(
                    name: routes.badge,
                    path: routes.badge,
                    builder: (context, state) => const BadgeDemoPage(),
                  ),
                  GoRoute(
                    name: routes.badgeNavigation,
                    path: routes.badgeNavigation,
                    builder: (context, state) =>
                        const BadgeNavigationDemoPage(),
                  ),
                  GoRoute(
                    name: routes.tooltip,
                    path: routes.tooltip,
                    builder: (context, state) => const TooltipDemoPage(),
                  ),
                  GoRoute(
                    name: routes.segmentedControl,
                    path: routes.segmentedControl,
                    builder: (context, state) =>
                        const SegmentedControlDemoPage(),
                  ),
                  GoRoute(
                    name: routes.nativeSearchTab,
                    path: routes.nativeSearchTab,
                    builder: (context, state) =>
                        const NativeSearchTabDemoPage(),
                  ),
                  GoRoute(
                    name: routes.snackbar,
                    path: routes.snackbar,
                    builder: (context, state) => const SnackbarDemoPage(),
                  ),
                  GoRoute(
                    name: routes.datePicker,
                    path: routes.datePicker,
                    builder: (context, state) => const DatePickerDemoPage(),
                  ),
                  GoRoute(
                    name: routes.timePicker,
                    path: routes.timePicker,
                    builder: (context, state) => const TimePickerDemoPage(),
                  ),
                  GoRoute(
                    name: routes.listTile,
                    path: routes.listTile,
                    builder: (context, state) => const ListTileDemoPage(),
                  ),
                  GoRoute(
                    name: routes.textField,
                    path: routes.textField,
                    builder: (context, state) => const TextFieldDemoPage(),
                  ),
                  GoRoute(
                    name: routes.tabView,
                    path: routes.tabView,
                    builder: (context, state) => const TabViewDemoPage(),
                  ),
                  GoRoute(
                    name: routes.floatingActionButton,
                    path: routes.floatingActionButton,
                    builder: (context, state) =>
                        const FloatingActionButtonDemoPage(),
                  ),
                  GoRoute(
                    name: routes.formSection,
                    path: routes.formSection,
                    builder: (context, state) => const FormSectionDemoPage(),
                  ),
                  GoRoute(
                    name: routes.expansionTile,
                    path: routes.expansionTile,
                    builder: (context, state) => const ExpansionTileDemoPage(),
                  ),
                  GoRoute(
                    name: routes.blurView,
                    path: routes.blurView,
                    builder: (context, state) => const BlurViewDemoPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                name: routes.info,
                path: routes.info,
                builder: (BuildContext context, GoRouterState state) {
                  return const InfoPage();
                },
                routes: [],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                name: routes.search,
                path: routes.search,
                builder: (BuildContext context, GoRouterState state) {
                  return const SearchPage();
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
