import 'package:adaptive_platform_ui_example/service/router/router_service.dart';
import 'package:adaptive_platform_ui_example/utils/global_variables.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    if (kDebugMode) {
      print("HomePage initState");
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: "Adaptive Platform UI",
        useNativeToolbar: true,
        actions: [
          if (PlatformInfo.isIOS26OrHigher()) ...[
            AdaptiveAppBarAction(
              iosSymbol: 'arrow.uturn.backward',
              icon: Icons.undo,

              onPressed: () {
                if (kDebugMode) {
                  print("Undo action pressed");
                }
              },
            ),
            AdaptiveAppBarAction(
              iosSymbol: 'arrow.uturn.forward',
              icon: Icons.redo,
              onPressed: () {
                if (kDebugMode) {
                  print("Redo action pressed");
                }
              },
              spacerAfter:
                  ToolbarSpacerType.flexible, // Push next group to right
            ),
            // Markup group
            AdaptiveAppBarAction(
              iosSymbol: 'pencil.tip.crop.circle',
              icon: Icons.edit,
              onPressed: () {
                if (kDebugMode) {
                  print("Edit action pressed");
                }
              },
            ),
            AdaptiveAppBarAction(
              iosSymbol: 'ellipsis.circle',
              icon: Icons.more_horiz,
              onPressed: () {
                if (kDebugMode) {
                  print("More action pressed");
                }
              },
            ),
          ] else ...[
            AdaptiveAppBarAction(
              iosSymbol: 'info.circle',
              icon: Icons.info,
              onPressed: () {
                RouterService.goNamed(
                  context: context,
                  route: RouterService.routes.info,
                );
              },
            ),
          ],
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final topPadding = PlatformInfo.isIOS ? 16.0 : 16.0;

    return SafeArea(
      top: false,
      bottom: false,
      child: ListView(
        controller: homeScrollController,
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: topPadding,
          bottom: 16.0,
        ),
        children: [
          SizedBox(height: 100),
          _buildHeader(context),
          const SizedBox(height: 24),
          // _buildSection(
          //   context,
          //   title: 'Screen',
          //   items: [
          //     _DemoItem(
          //       icon: PlatformInfo.isIOS
          //           ? CupertinoIcons.square_split_2x2
          //           : Icons.dashboard,
          //       title: 'Tabbar',
          //       description: 'Adaptive tab bars with platform-specific styles',
          //       routeName: RouterService.routes.demoTabbar,
          //     ),
          //   ],
          // ),
          // const SizedBox(height: 12),
          _buildSection(
            context,
            title: 'Components',
            items: [
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.hand_point_right_fill
                    : Icons.touch_app,
                title: 'Button',
                description: 'Adaptive buttons with platform-specific styles',
                routeName: RouterService.routes.button,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.chat_bubble_fill
                    : Icons.message,
                title: 'Alert Dialog',
                description: 'Native alert dialogs with adaptive styling',
                routeName: RouterService.routes.alertDialog,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.bell_fill
                    : Icons.notifications,
                title: 'Snackbar',
                description: 'Platform-specific notification snackbars',
                routeName: RouterService.routes.snackbar,
                isNew: true,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.ellipsis_circle_fill
                    : Icons.more_horiz,
                title: 'Popup Menu',
                description: 'Native popup menus with adaptive styling',
                routeName: RouterService.routes.popupMenu,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.hand_raised_fill
                    : Icons.touch_app,
                title: 'Context Menu',
                description: 'Long-press context menus with platform styles',
                routeName: RouterService.routes.contextMenu,
                isNew: false,
              ),
              _DemoItem(
                icon: Icons.tune,
                title: 'Slider',
                description: 'Native sliders with adaptive styling',
                routeName: RouterService.routes.slider,
              ),
              _DemoItem(
                icon: Icons.toggle_on,
                title: 'Switch',
                description: 'Native switches with adaptive styling',
                routeName: RouterService.routes.switchDemo,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.checkmark_square
                    : Icons.check_box,
                title: 'Checkbox',
                description: 'Native checkboxes with adaptive styling',
                routeName: RouterService.routes.checkbox,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.circle
                    : Icons.radio_button_checked,
                title: 'Radio',
                description: 'Radio button groups with adaptive styling',
                routeName: RouterService.routes.radio,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.rectangle_on_rectangle
                    : Icons.credit_card,
                title: 'Card',
                description: 'Adaptive cards with platform-specific styling',
                routeName: RouterService.routes.card,
                isNew: true,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.number_circle_fill
                    : Icons.notifications_active,
                title: 'Badge',
                description: 'Notification badges with adaptive styling',
                routeName: RouterService.routes.badge,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.rectangle_stack
                    : Icons.tab,
                title: 'Badge Navigation',
                description: 'Badge counters on navigation tabs',
                routeName: RouterService.routes.badgeNavigation,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.info_circle
                    : Icons.info_outline,
                title: 'Tooltip',
                description: 'Platform-specific tooltips',
                routeName: RouterService.routes.tooltip,
                isNew: true,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.square_split_2x2
                    : Icons.segment,
                title: 'Segmented Control',
                description: 'Native segmented controls with adaptive styling',
                routeName: RouterService.routes.segmentedControl,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.calendar
                    : Icons.calendar_today,
                title: 'Date Picker',
                description: 'Platform-specific date selection dialogs',
                routeName: RouterService.routes.datePicker,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.clock
                    : Icons.access_time,
                title: 'Time Picker',
                description: 'Platform-specific time selection dialogs',
                routeName: RouterService.routes.timePicker,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.list_bullet
                    : Icons.list,
                title: 'List Tile',
                description: 'Platform-specific list item tiles',
                routeName: RouterService.routes.listTile,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.textformat
                    : Icons.text_fields,
                title: 'Text Field',
                description:
                    'Platform-specific text input fields with validation',
                routeName: RouterService.routes.textField,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.square_stack_3d_down_right
                    : Icons.tab,
                title: 'Tab View',
                description: 'Bottom navigation and swipeable tab views',
                routeName: RouterService.routes.tabView,
                isNew: true,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.add_circled_solid
                    : Icons.add_circle,
                title: 'Floating Action Button',
                description: 'Platform-specific circular action buttons',
                routeName: RouterService.routes.floatingActionButton,
                isNew: true,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.list_bullet_below_rectangle
                    : Icons.list_alt,
                title: 'Form Section',
                description: 'Grouped form sections with headers and footers',
                routeName: RouterService.routes.formSection,
                isNew: true,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.chevron_down_circle
                    : Icons.expand_more,
                title: 'Expansion Tile',
                description: 'Expandable and collapsible list tiles',
                routeName: RouterService.routes.expansionTile,
                isNew: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSection(
            context,
            title: 'iOS 26+ Features',
            items: [
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.layers_alt
                    : Icons.blur_on,
                title: 'Blur View',
                isCritical: true,
                description: 'Native UIVisualEffectView with Liquid Glass',
                routeName: RouterService.routes.blurView,
                isNew: true,
              ),
              _DemoItem(
                icon: PlatformInfo.isIOS
                    ? CupertinoIcons.search_circle_fill
                    : Icons.search,
                title: 'Native Search Tab',
                description:
                    'EXPERIMENTAL: Native tab bar with search transformation',
                routeName: RouterService.routes.nativeSearchTab,
                isCritical: true,
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildInfoCard(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: PlatformInfo.isIOS
              ? [
                  CupertinoColors.systemBlue,
                  CupertinoColors.systemBlue.withValues(alpha: 0.7),
                ]
              : [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PlatformInfo.isIOS
                ? CupertinoIcons.device_phone_portrait
                : Icons.phone_iphone,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'Adaptive Platform UI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cross-platform Flutter widgets that adapt to iOS 26+, iOS <26 (iOS 18 and below), and Android',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<_DemoItem> items,
  }) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: PlatformInfo.isIOS
                  ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        ...items.map((item) => _buildDemoItem(context, item)),
      ],
    );
  }

  Widget _buildDemoItem(BuildContext context, _DemoItem item) {
    if (PlatformInfo.isIOS) {
      final isDark =
          MediaQuery.platformBrightnessOf(context) == Brightness.dark;

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _navigateToPageWithRouter(context, item.routeName),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? CupertinoColors.darkBackgroundGray
                  : CupertinoColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: item.isCritical
                    ? CupertinoColors.systemYellow.withValues(alpha: 0.5)
                    : item.isNew
                    ? CupertinoColors.systemGreen.withValues(alpha: 0.5)
                    : (isDark
                          ? CupertinoColors.systemGrey4
                          : CupertinoColors.separator),
                width: (item.isCritical || item.isNew) ? 1.5 : 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.icon,
                    color: CupertinoColors.systemBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? CupertinoColors.white
                                    : CupertinoColors.black,
                              ),
                            ),
                          ),
                          if (item.isNew) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemGreen.withValues(
                                  alpha: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: CupertinoColors.systemGreen,
                                  width: 1,
                                ),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: CupertinoColors.systemGreen,
                                ),
                              ),
                            ),
                          ],
                          if (item.isCritical) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemYellow.withValues(
                                  alpha: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: CupertinoColors.systemYellow,
                                  width: 1,
                                ),
                              ),
                              child: const Text(
                                'EXPERIMENTAL',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: CupertinoColors.systemYellow,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.systemGrey2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  color: CupertinoColors.systemGrey,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: item.isCritical
            ? BorderSide(color: Colors.orange.withValues(alpha: 0.5), width: 2)
            : item.isNew
            ? BorderSide(color: Colors.green.withValues(alpha: 0.5), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _navigateToPageWithRouter(context, item.routeName),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (item.isNew) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green, width: 1),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ],
                        if (item.isCritical) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.orange,
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'EXPERIMENTAL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PlatformInfo.isIOS
            ? (isDark
                  ? CupertinoColors.darkBackgroundGray
                  : CupertinoColors.white)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: PlatformInfo.isIOS
            ? Border.all(
                color: isDark
                    ? CupertinoColors.systemGrey4
                    : CupertinoColors.separator,
                width: 0.5,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PlatformInfo.isIOS
                    ? CupertinoIcons.info_circle_fill
                    : Icons.info,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemBlue
                    : Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'About',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: PlatformInfo.isIOS
                      ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This package provides adaptive widgets that automatically render platform-specific designs based on the user\'s device and OS version.',
            style: TextStyle(
              fontSize: 14,
              color: PlatformInfo.isIOS
                  ? (isDark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.systemGrey2)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _buildFeatureRow(
            context,
            icon: PlatformInfo.isIOS
                ? CupertinoIcons.checkmark_circle_fill
                : Icons.check_circle,
            text: 'iOS 26+ native designs with Liquid Glass effects',
          ),
          const SizedBox(height: 8),
          _buildFeatureRow(
            context,
            icon: PlatformInfo.isIOS
                ? CupertinoIcons.checkmark_circle_fill
                : Icons.check_circle,
            text:
                'Traditional Cupertino widgets for iOS <26 (iOS 18 and below)',
          ),
          const SizedBox(height: 8),
          _buildFeatureRow(
            context,
            icon: PlatformInfo.isIOS
                ? CupertinoIcons.checkmark_circle_fill
                : Icons.check_circle,
            text: 'Material Design 3 for Android',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: PlatformInfo.isIOS
              ? CupertinoColors.systemGreen
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: PlatformInfo.isIOS
                  ? (isDark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.systemGrey2)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  void _navigateToPageWithRouter(BuildContext context, String routeName) {
    RouterService.pushNamed(context: context, route: routeName);
  }
}

class _DemoItem {
  final IconData icon;
  final String title;
  final String description;
  final String routeName;
  final bool isNew;
  final bool isCritical;

  const _DemoItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.routeName,
    this.isNew = false,
    this.isCritical = false,
  });
}
