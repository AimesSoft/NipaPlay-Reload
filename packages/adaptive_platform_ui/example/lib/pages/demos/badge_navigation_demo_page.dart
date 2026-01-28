import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:go_router/go_router.dart';

class BadgeNavigationDemoPage extends StatefulWidget {
  const BadgeNavigationDemoPage({super.key});

  @override
  State<BadgeNavigationDemoPage> createState() =>
      _BadgeNavigationDemoPageState();
}

class _BadgeNavigationDemoPageState extends State<BadgeNavigationDemoPage> {
  int _selectedIndex = 0;
  int _homeBadgeCount = 150;
  int _messagesBadgeCount = 12;
  int _notificationsBadgeCount = 0;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        leading: PlatformInfo.isIOS26OrHigher() ? popButton(context) : null,
        title: 'Badge Navigation Demo',
      ),
      body: _buildContent(),
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
            // Clear badge when tab is selected
            if (index == 0) _homeBadgeCount = 0;
            if (index == 1) _messagesBadgeCount = 0;
            if (index == 2) _notificationsBadgeCount = 0;
          });
        },
        items: [
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "house.fill"
                : PlatformInfo.isIOS
                ? CupertinoIcons.home
                : Icons.home_outlined,
            selectedIcon: PlatformInfo.isIOS ? CupertinoIcons.home : Icons.home,
            label: 'Home',
            badgeCount: _homeBadgeCount > 0 ? _homeBadgeCount : null,
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "message.fill"
                : PlatformInfo.isIOS
                ? CupertinoIcons.chat_bubble_fill
                : Icons.message_outlined,
            selectedIcon: PlatformInfo.isIOS
                ? CupertinoIcons.chat_bubble_fill
                : Icons.message,
            label: 'Messages',
            badgeCount: _messagesBadgeCount > 0 ? _messagesBadgeCount : null,
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "bell.fill"
                : PlatformInfo.isIOS
                ? CupertinoIcons.bell_fill
                : Icons.notifications_outlined,
            selectedIcon: PlatformInfo.isIOS
                ? CupertinoIcons.bell_fill
                : Icons.notifications,
            label: 'Notifications',
            badgeCount: _notificationsBadgeCount > 0
                ? _notificationsBadgeCount
                : null,
          ),
        ],
      ),
    );
  }

  Widget popButton(BuildContext context) {
    if (PlatformInfo.isIOS26OrHigher()) {
      return Container(
        margin: EdgeInsets.only(left: 8),
        width: 40,
        height: 40,
        child: AdaptiveButton.sfSymbol(
          onPressed: () {
            context.pop();
          },
          sfSymbol: SFSymbol("chevron.backward"),
        ),
      );
    }
    return SizedBox(
      width: 40,
      height: 40,
      child: AdaptiveButton.icon(
        onPressed: () {
          context.pop();
        },
        icon: Icons.arrow_back,
      ),
    );
  }

  Widget _buildContent() {
    final topPadding = PlatformInfo.isIOS ? 130.0 : 16.0;

    return ListView(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: topPadding,
        bottom: 16.0,
      ),
      children: [
        _buildSection(
          context,
          title: 'Badge Navigation Demo',
          description:
              'This demo shows badge counters on navigation tabs. Tap a tab to clear its badge.',
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                'Current Tab: ${_getTabName(_selectedIndex)}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Text(
                'Badge Counts:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Text('Home: $_homeBadgeCount'),
              Text('Messages: $_messagesBadgeCount'),
              Text('Notifications: $_notificationsBadgeCount'),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _homeBadgeCount = 150;
                    _messagesBadgeCount = 12;
                    _notificationsBadgeCount = 3;
                  });
                },
                child: const Text('Reset Badge Counts'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String description,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8.0),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16.0),
            child,
          ],
        ),
      ),
    );
  }

  String _getTabName(int index) {
    switch (index) {
      case 0:
        return 'Home';
      case 1:
        return 'Messages';
      case 2:
        return 'Notifications';
      default:
        return 'Unknown';
    }
  }
}
