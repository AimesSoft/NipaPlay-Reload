import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ExpansionTileDemoPage extends StatefulWidget {
  const ExpansionTileDemoPage({super.key});

  @override
  State<ExpansionTileDemoPage> createState() => _ExpansionTileDemoPageState();
}

class _ExpansionTileDemoPageState extends State<ExpansionTileDemoPage> {
  bool _tile1Expanded = false;
  bool _tile2Expanded = false;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(title: 'Expansion Tile Demo'),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Basic Expansion Tile
          _buildSectionHeader('Basic Expansion Tile'),
          AdaptiveExpansionTile(
            title: const Text('Basic Expansion'),
            children: [
              _buildListItem('Item 1'),
              _buildListItem('Item 2'),
              _buildListItem('Item 3'),
            ],
          ),
          const SizedBox(height: 24.0),

          // With Leading Icon
          _buildSectionHeader('With Leading Icon'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS ? CupertinoIcons.person : Icons.person,
            ),
            title: const Text('User Settings'),
            children: [
              _buildListItem('Profile'),
              _buildListItem('Privacy'),
              _buildListItem('Security'),
            ],
          ),
          const SizedBox(height: 24.0),

          // With Subtitle
          _buildSectionHeader('With Subtitle'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS ? CupertinoIcons.settings : Icons.settings,
            ),
            title: const Text('Application Settings'),
            subtitle: const Text('Configure your preferences'),
            children: [
              _buildListItem('Theme'),
              _buildListItem('Language'),
              _buildListItem('Notifications'),
            ],
          ),
          const SizedBox(height: 24.0),

          // Initially Expanded
          _buildSectionHeader('Initially Expanded'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS ? CupertinoIcons.info : Icons.info,
            ),
            title: const Text('Help & Support'),
            initiallyExpanded: true,
            children: [
              _buildListItem('FAQ'),
              _buildListItem('Contact Us'),
              _buildListItem('Documentation'),
            ],
          ),
          const SizedBox(height: 24.0),

          // Custom Colors
          _buildSectionHeader('Custom Colors'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS ? CupertinoIcons.star : Icons.star,
            ),
            title: const Text('Premium Features'),
            backgroundColor: PlatformInfo.isIOS
                ? CupertinoColors.systemYellow.withValues(alpha: 0.1)
                : Colors.amber.withValues(alpha: 0.1),
            collapsedBackgroundColor: PlatformInfo.isIOS
                ? CupertinoColors.systemBackground
                : Colors.white,
            iconColor: PlatformInfo.isIOS
                ? CupertinoColors.systemYellow
                : Colors.amber,
            collapsedIconColor: PlatformInfo.isIOS
                ? CupertinoColors.systemGrey
                : Colors.grey,
            children: [
              _buildListItem('Advanced Analytics'),
              _buildListItem('Custom Themes'),
              _buildListItem('Priority Support'),
            ],
          ),
          const SizedBox(height: 24.0),

          // With State Tracking
          _buildSectionHeader('With State Tracking'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS ? CupertinoIcons.chart_bar : Icons.bar_chart,
            ),
            title: Text(
              'Statistics ${_tile1Expanded ? '(Expanded)' : '(Collapsed)'}',
            ),
            onExpansionChanged: (expanded) {
              setState(() {
                _tile1Expanded = expanded;
              });
            },
            children: [
              _buildListItem('Daily Report'),
              _buildListItem('Weekly Report'),
              _buildListItem('Monthly Report'),
            ],
          ),
          const SizedBox(height: 24.0),

          // Nested Expansion Tiles
          _buildSectionHeader('Nested Expansion Tiles'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS ? CupertinoIcons.folder : Icons.folder,
            ),
            title: const Text('Documents'),
            children: [
              AdaptiveExpansionTile(
                leading: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.folder_fill
                      : Icons.folder_open,
                  size: 20,
                ),
                title: const Text('Work'),
                tilePadding: const EdgeInsets.only(left: 32.0, right: 16.0),
                children: [
                  _buildListItem('Project A', indent: 48.0),
                  _buildListItem('Project B', indent: 48.0),
                ],
              ),
              AdaptiveExpansionTile(
                leading: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.folder_fill
                      : Icons.folder_open,
                  size: 20,
                ),
                title: const Text('Personal'),
                tilePadding: const EdgeInsets.only(left: 32.0, right: 16.0),
                children: [
                  _buildListItem('Photos', indent: 48.0),
                  _buildListItem('Videos', indent: 48.0),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24.0),

          // Custom Padding
          _buildSectionHeader('Custom Padding'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS
                  ? CupertinoIcons.square_grid_2x2
                  : Icons.grid_view,
            ),
            title: const Text('Gallery'),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            childrenPadding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 8.0,
            ),
            children: [
              _buildListItem('Album 1', showDivider: false),
              _buildListItem('Album 2', showDivider: false),
              _buildListItem('Album 3', showDivider: false),
            ],
          ),
          const SizedBox(height: 24.0),

          // With Custom Trailing
          _buildSectionHeader('Custom Trailing Widget'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS ? CupertinoIcons.bell : Icons.notifications,
            ),
            title: const Text('Notifications'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              decoration: BoxDecoration(
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemRed
                    : Colors.red,
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Text(
                '3',
                style: TextStyle(
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.white
                      : Colors.white,
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            children: [
              _buildListItem('New message from John'),
              _buildListItem('Update available'),
              _buildListItem('Reminder: Meeting at 3 PM'),
            ],
          ),
          const SizedBox(height: 24.0),

          // Disabled State
          _buildSectionHeader('Disabled State'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS ? CupertinoIcons.lock : Icons.lock,
            ),
            title: const Text('Locked Feature'),
            subtitle: const Text('Upgrade to unlock'),
            enabled: false,
            collapsedTextColor: PlatformInfo.isIOS
                ? CupertinoColors.systemGrey
                : Colors.grey,
            collapsedIconColor: PlatformInfo.isIOS
                ? CupertinoColors.systemGrey
                : Colors.grey,
            children: [
              _buildListItem('Feature 1'),
              _buildListItem('Feature 2'),
            ],
          ),
          const SizedBox(height: 24.0),

          // Complex Content
          _buildSectionHeader('Complex Content'),
          AdaptiveExpansionTile(
            leading: Icon(
              PlatformInfo.isIOS
                  ? CupertinoIcons.shopping_cart
                  : Icons.shopping_cart,
            ),
            title: const Text('Shopping Cart'),
            subtitle: Text(_tile2Expanded ? 'Hide items' : 'Show items'),
            onExpansionChanged: (expanded) {
              setState(() {
                _tile2Expanded = expanded;
              });
            },
            children: [
              _buildCartItem(
                'Product 1',
                '\$29.99',
                PlatformInfo.isIOS
                    ? CupertinoIcons.device_phone_portrait
                    : Icons.phone_android,
              ),
              _buildCartItem(
                'Product 2',
                '\$49.99',
                PlatformInfo.isIOS
                    ? CupertinoIcons.headphones
                    : Icons.headphones,
              ),
              _buildCartItem(
                'Product 3',
                '\$19.99',
                PlatformInfo.isIOS ? CupertinoIcons.clock : Icons.watch,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total:',
                      style: TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                        color: PlatformInfo.isIOS
                            ? CupertinoColors.label
                            : Colors.black87,
                      ),
                    ),
                    Text(
                      '\$99.97',
                      style: TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                        color: PlatformInfo.isIOS
                            ? CupertinoColors.activeBlue
                            : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14.0,
          fontWeight: FontWeight.w600,
          color: PlatformInfo.isIOS
              ? CupertinoColors.secondaryLabel.resolveFrom(context)
              : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildListItem(
    String title, {
    bool showDivider = true,
    double indent = 16.0,
  }) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    if (PlatformInfo.isIOS) {
      return Padding(
        padding: EdgeInsets.only(
          left: indent == 16.0 ? 0 : indent - 16.0,
          top: 4.0,
          bottom: 4.0,
        ),
        child: CupertinoButton(
          onPressed: () {
            // Item tap action
            AdaptiveSnackBar.show(
              context,
              message: 'Tapped: $title',
              type: AdaptiveSnackBarType.info,
            );
          },
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? CupertinoColors.systemGrey6.darkColor.withValues(alpha: 0.5)
                  : CupertinoColors.systemGrey6.color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.label.resolveFrom(context),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14.0,
                  color: CupertinoColors.systemGrey.resolveFrom(context),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Android - Keep simple list style
    return Column(
      children: [
        InkWell(
          onTap: () {
            AdaptiveSnackBar.show(
              context,
              message: 'Tapped: $title',
              type: AdaptiveSnackBarType.info,
            );
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: indent,
              right: 16.0,
              top: 12.0,
              bottom: 12.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 16.0, color: Colors.black87),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18.0, color: Colors.grey[600]),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: indent, color: Colors.grey[300]),
      ],
    );
  }

  Widget _buildCartItem(String name, String price, IconData icon) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    if (PlatformInfo.isIOS) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: CupertinoButton(
          onPressed: () {
            AdaptiveSnackBar.show(
              context,
              message: 'Selected: $name',
              type: AdaptiveSnackBarType.success,
            );
          },
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: isDark
                  ? CupertinoColors.systemGrey6.darkColor.withValues(alpha: 0.5)
                  : CupertinoColors.systemGrey6.color.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: isDark
                    ? CupertinoColors.systemGrey5.darkColor
                    : CupertinoColors.systemGrey5.color,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48.0,
                  height: 48.0,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        CupertinoColors.activeBlue.withValues(alpha: 0.8),
                        CupertinoColors.activeBlue,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12.0),
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.activeBlue.withValues(
                          alpha: 0.3,
                        ),
                        blurRadius: 8.0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 24.0, color: CupertinoColors.white),
                ),
                const SizedBox(width: 14.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.label.resolveFrom(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        'In Stock',
                        style: TextStyle(
                          fontSize: 13.0,
                          color: CupertinoColors.systemGreen.resolveFrom(
                            context,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.activeBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    price,
                    style: TextStyle(
                      fontSize: 17.0,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Android - Modern Material style
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: InkWell(
          onTap: () {
            AdaptiveSnackBar.show(
              context,
              message: 'Selected: $name',
              type: AdaptiveSnackBarType.success,
            );
          },
          borderRadius: BorderRadius.circular(12.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                  width: 48.0,
                  height: 48.0,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.blue[400]!, Colors.blue[600]!],
                    ),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Icon(icon, size: 24.0, color: Colors.white),
                ),
                const SizedBox(width: 14.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        'In Stock',
                        style: TextStyle(
                          fontSize: 13.0,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    price,
                    style: TextStyle(
                      fontSize: 17.0,
                      fontWeight: FontWeight.w700,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
