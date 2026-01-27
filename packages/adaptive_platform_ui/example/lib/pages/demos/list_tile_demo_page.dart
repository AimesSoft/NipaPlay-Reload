import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ListTileDemoPage extends StatefulWidget {
  const ListTileDemoPage({super.key});

  @override
  State<ListTileDemoPage> createState() => _ListTileDemoPageState();
}

class _ListTileDemoPageState extends State<ListTileDemoPage> {
  int? _selectedIndex;
  bool _switchValue = false;

  @override
  Widget build(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'List Tile'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 100),
          _buildInfoCard(context, isDark),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: 'Basic List Tiles',
            children: [
              AdaptiveListTile(
                title: const Text('Simple List Tile'),
                onTap: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'Simple tile tapped',
                    type: AdaptiveSnackBarType.info,
                  );
                },
              ),
              AdaptiveListTile(
                title: const Text('List Tile with Subtitle'),
                subtitle: const Text('This is a subtitle'),
                onTap: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'Tile with subtitle tapped',
                    type: AdaptiveSnackBarType.info,
                  );
                },
              ),
              AdaptiveListTile(
                title: const Text('Disabled List Tile'),
                subtitle: const Text('This tile is not interactive'),
                enabled: false,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: 'List Tiles with Leading Icons',
            children: [
              AdaptiveListTile(
                leading: Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.person : Icons.person,
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemBlue
                      : Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Profile'),
                subtitle: const Text('View your profile'),
                trailing: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.chevron_right
                      : Icons.chevron_right,
                  color: CupertinoColors.systemGrey,
                  size: 20,
                ),
                onTap: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'Profile tapped',
                    type: AdaptiveSnackBarType.info,
                  );
                },
              ),
              AdaptiveListTile(
                leading: Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.settings : Icons.settings,
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemGreen
                      : Colors.green,
                ),
                title: const Text('Settings'),
                subtitle: const Text('Manage your preferences'),
                trailing: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.chevron_right
                      : Icons.chevron_right,
                  color: CupertinoColors.systemGrey,
                  size: 20,
                ),
                onTap: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'Settings tapped',
                    type: AdaptiveSnackBarType.info,
                  );
                },
              ),
              AdaptiveListTile(
                leading: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.bell
                      : Icons.notifications,
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemOrange
                      : Colors.orange,
                ),
                title: const Text('Notifications'),
                subtitle: const Text('Manage notification settings'),
                trailing: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.chevron_right
                      : Icons.chevron_right,
                  color: CupertinoColors.systemGrey,
                  size: 20,
                ),
                onTap: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'Notifications tapped',
                    type: AdaptiveSnackBarType.info,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: 'Selectable List Tiles',
            children: [
              ...List.generate(
                3,
                (index) => AdaptiveListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getColorForIndex(index).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getIconForIndex(index),
                      color: _getColorForIndex(index),
                      size: 24,
                    ),
                  ),
                  title: Text('Option ${index + 1}'),
                  subtitle: Text('Tap to select option ${index + 1}'),
                  trailing: _selectedIndex == index
                      ? Icon(
                          PlatformInfo.isIOS
                              ? CupertinoIcons.check_mark_circled_solid
                              : Icons.check_circle,
                          color: PlatformInfo.isIOS
                              ? CupertinoColors.systemBlue
                              : Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  selected: _selectedIndex == index,
                  onTap: () {
                    setState(() {
                      _selectedIndex = index;
                    });
                    AdaptiveSnackBar.show(
                      context,
                      message: 'Selected option ${index + 1}',
                      type: AdaptiveSnackBarType.success,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: 'List Tiles with Trailing Widgets',
            children: [
              AdaptiveListTile(
                title: const Text('Enable Feature'),
                subtitle: const Text('Toggle to enable or disable'),
                trailing: AdaptiveSwitch(
                  value: _switchValue,
                  onChanged: (value) {
                    setState(() {
                      _switchValue = value;
                    });
                  },
                ),
              ),
              AdaptiveListTile(
                title: const Text('Badge Notification'),
                subtitle: const Text('3 unread messages'),
                trailing: AdaptiveBadge(
                  count: 3,
                  child: Icon(
                    PlatformInfo.isIOS ? CupertinoIcons.mail : Icons.mail,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                onTap: () {
                  AdaptiveSnackBar.show(
                    context,
                    message: 'Messages tapped',
                    type: AdaptiveSnackBarType.info,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getIconForIndex(int index) {
    switch (index) {
      case 0:
        return PlatformInfo.isIOS ? CupertinoIcons.star_fill : Icons.star;
      case 1:
        return PlatformInfo.isIOS ? CupertinoIcons.heart_fill : Icons.favorite;
      case 2:
        return PlatformInfo.isIOS
            ? CupertinoIcons.bookmark_fill
            : Icons.bookmark;
      default:
        return PlatformInfo.isIOS ? CupertinoIcons.circle : Icons.circle;
    }
  }

  Color _getColorForIndex(int index) {
    switch (index) {
      case 0:
        return PlatformInfo.isIOS ? CupertinoColors.systemYellow : Colors.amber;
      case 1:
        return PlatformInfo.isIOS ? CupertinoColors.systemPink : Colors.pink;
      case 2:
        return PlatformInfo.isIOS
            ? CupertinoColors.systemPurple
            : Colors.purple;
      default:
        return PlatformInfo.isIOS ? CupertinoColors.systemBlue : Colors.blue;
    }
  }

  Widget _buildInfoCard(BuildContext context, bool isDark) {
    return AdaptiveCard(
      padding: const EdgeInsets.all(16),
      color: isDark
          ? (PlatformInfo.isIOS
                ? CupertinoColors.systemBlue.darkColor.withValues(alpha: 0.2)
                : Colors.blue.shade900.withValues(alpha: 0.3))
          : (PlatformInfo.isIOS
                ? CupertinoColors.systemBlue.color.withValues(alpha: 0.1)
                : Colors.blue.shade50),
      child: Row(
        children: [
          Icon(
            PlatformInfo.isIOS ? CupertinoIcons.info_circle_fill : Icons.info,
            color: PlatformInfo.isIOS
                ? CupertinoColors.systemBlue
                : Colors.blue.shade700,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              PlatformInfo.isIOS
                  ? 'iOS uses CupertinoListTile-like styling'
                  : 'Android uses Material ListTile',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? (PlatformInfo.isIOS
                          ? CupertinoColors.white
                          : Colors.white)
                    : (PlatformInfo.isIOS
                          ? CupertinoColors.black
                          : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    bool isDark, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? (PlatformInfo.isIOS ? CupertinoColors.white : Colors.white)
                  : (PlatformInfo.isIOS
                        ? CupertinoColors.black
                        : Colors.black87),
            ),
          ),
        ),
        AdaptiveCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}
