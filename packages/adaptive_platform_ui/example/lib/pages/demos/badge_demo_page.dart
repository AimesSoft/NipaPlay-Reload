import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class BadgeDemoPage extends StatefulWidget {
  const BadgeDemoPage({super.key});

  @override
  State<BadgeDemoPage> createState() => _BadgeDemoPageState();
}

class _BadgeDemoPageState extends State<BadgeDemoPage> {
  int _notificationCount = 5;
  final int _messageCount = 99;
  int _cartCount = 0;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(title: 'AdaptiveBadge Demo'),
      body: _buildContent(),
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
          title: 'Basic Badges',
          description: 'Simple badges with count numbers',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              AdaptiveBadge(
                count: _notificationCount,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.bell_fill
                      : Icons.notifications,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveBadge(
                count: _messageCount,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.chat_bubble_fill
                      : Icons.message,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveBadge(
                count: 3,
                child: Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.mail_solid : Icons.email,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _buildButton(
                context,
                label: '+ Add',
                onPressed: () {
                  setState(() {
                    _notificationCount++;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildButton(
                context,
                label: '- Remove',
                onPressed: () {
                  setState(() {
                    if (_notificationCount > 0) _notificationCount--;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Custom Colors',
          description: 'Badges with custom background colors',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              AdaptiveBadge(
                count: 5,
                backgroundColor: PlatformInfo.isIOS
                    ? CupertinoColors.systemGreen
                    : Colors.green,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.checkmark_circle_fill
                      : Icons.check_circle,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveBadge(
                count: 12,
                backgroundColor: PlatformInfo.isIOS
                    ? CupertinoColors.systemOrange
                    : Colors.orange,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.exclamationmark_circle_fill
                      : Icons.warning,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveBadge(
                count: 7,
                backgroundColor: PlatformInfo.isIOS
                    ? CupertinoColors.systemPurple
                    : Colors.purple,
                child: Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.star_fill : Icons.star,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Text Labels',
          description: 'Badges with custom text labels',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              AdaptiveBadge(
                label: 'NEW',
                backgroundColor: PlatformInfo.isIOS
                    ? CupertinoColors.systemBlue
                    : Colors.blue,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.doc_text_fill
                      : Icons.article,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveBadge(
                label: 'HOT',
                backgroundColor: PlatformInfo.isIOS
                    ? CupertinoColors.systemRed
                    : Colors.red,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.flame_fill
                      : Icons.local_fire_department,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveBadge(
                label: 'PRO',
                backgroundColor: PlatformInfo.isIOS
                    ? CupertinoColors.systemYellow
                    : Colors.amber,
                textColor: PlatformInfo.isIOS
                    ? CupertinoColors.black
                    : Colors.black,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.sparkles
                      : Icons.workspace_premium,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Large Badges',
          description: 'Badges with larger size',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              AdaptiveBadge(
                count: 8,
                isLarge: true,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.bell_fill
                      : Icons.notifications,
                  size: 40,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveBadge(
                label: 'VIP',
                isLarge: true,
                backgroundColor: PlatformInfo.isIOS
                    ? CupertinoColors.systemPurple
                    : Colors.purple,
                child: Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.person_fill
                      : Icons.person,
                  size: 40,
                  color: _getIconColor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Show Zero',
          description: 'Badge visible even when count is 0',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  AdaptiveBadge(
                    count: _cartCount,
                    showZero: true,
                    child: Icon(
                      PlatformInfo.isIOS
                          ? CupertinoIcons.cart_fill
                          : Icons.shopping_cart,
                      size: 32,
                      color: _getIconColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('showZero: true', style: _getSmallTextStyle(context)),
                ],
              ),
              Column(
                children: [
                  AdaptiveBadge(
                    count: _cartCount,
                    showZero: false,
                    child: Icon(
                      PlatformInfo.isIOS
                          ? CupertinoIcons.cart_fill
                          : Icons.shopping_cart,
                      size: 32,
                      color: _getIconColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('showZero: false', style: _getSmallTextStyle(context)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _buildButton(
                context,
                label: 'Add to Cart',
                onPressed: () {
                  setState(() {
                    _cartCount++;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildButton(
                context,
                label: 'Remove',
                onPressed: () {
                  setState(() {
                    if (_cartCount > 0) _cartCount--;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'In App Bar',
          description: 'Badges used in navigation bars',
          child: AdaptiveCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                AdaptiveBadge(
                  count: 3,
                  child: Icon(
                    PlatformInfo.isIOS ? CupertinoIcons.home : Icons.home,
                    size: 28,
                    color: _getIconColor(context),
                  ),
                ),
                AdaptiveBadge(
                  count: 15,
                  child: Icon(
                    PlatformInfo.isIOS ? CupertinoIcons.search : Icons.search,
                    size: 28,
                    color: _getIconColor(context),
                  ),
                ),
                AdaptiveBadge(
                  count: 0,
                  child: Icon(
                    PlatformInfo.isIOS
                        ? CupertinoIcons.heart
                        : Icons.favorite_border,
                    size: 28,
                    color: _getIconColor(context),
                  ),
                ),
                AdaptiveBadge(
                  count: 2,
                  child: Icon(
                    PlatformInfo.isIOS ? CupertinoIcons.person : Icons.person,
                    size: 28,
                    color: _getIconColor(context),
                  ),
                ),
              ],
            ),
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
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: PlatformInfo.isIOS
                ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 14,
            color: PlatformInfo.isIOS
                ? (isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }

  Widget _buildButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 38,
      width: double.infinity,
      child: AdaptiveButton(
        style: PlatformInfo.isIOS26OrHigher()
            ? AdaptiveButtonStyle.prominentGlass
            : AdaptiveButtonStyle.filled,
        label: label,
        onPressed: onPressed,
        textColor: Colors.white,
      ),
    );
  }

  Color _getIconColor(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return PlatformInfo.isIOS
        ? (isDark ? CupertinoColors.white : CupertinoColors.black)
        : Theme.of(context).colorScheme.onSurface;
  }

  TextStyle _getSmallTextStyle(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return TextStyle(
      fontSize: 12,
      color: PlatformInfo.isIOS
          ? (isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2)
          : Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
