import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class CardDemoPage extends StatefulWidget {
  const CardDemoPage({super.key});

  @override
  State<CardDemoPage> createState() => _CardDemoPageState();
}

class _CardDemoPageState extends State<CardDemoPage> {
  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(title: 'AdaptiveCard Demo'),
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
          title: 'Basic Cards',
          description: 'Simple cards with default styling',
          child: Column(
            children: [
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                child: Text(
                  'This is a basic card with default styling',
                  style: _getTextStyle(context),
                ),
              ),
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Card with Multiple Elements',
                      style: _getTitleStyle(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cards can contain multiple widgets including text, images, and buttons.',
                      style: _getTextStyle(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Custom Colors',
          description: 'Cards with custom background colors',
          child: Column(
            children: [
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemBlue.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.1),
                child: Text('Blue tinted card', style: _getTextStyle(context)),
              ),
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemGreen.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                child: Text('Green tinted card', style: _getTextStyle(context)),
              ),
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemOrange.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                child: Text(
                  'Orange tinted card',
                  style: _getTextStyle(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Custom Border Radius',
          description: 'Cards with different corner radii',
          child: Column(
            children: [
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                borderRadius: BorderRadius.circular(4),
                child: Text(
                  'Small border radius (4px)',
                  style: _getTextStyle(context),
                ),
              ),
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                borderRadius: BorderRadius.circular(20),
                child: Text(
                  'Large border radius (20px)',
                  style: _getTextStyle(context),
                ),
              ),
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(0),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(0),
                ),
                child: Text(
                  'Custom corner radii',
                  style: _getTextStyle(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Elevation',
          description: 'Cards with different elevations (visible on Android)',
          child: Column(
            children: [
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                elevation: 0,
                child: Text('Elevation 0', style: _getTextStyle(context)),
              ),
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                elevation: 4,
                child: Text(
                  'Elevation 4 (default)',
                  style: _getTextStyle(context),
                ),
              ),
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                elevation: 8,
                child: Text('Elevation 8', style: _getTextStyle(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Complex Content',
          description: 'Cards with rich content layouts',
          child: Column(
            children: [
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            PlatformInfo.isIOS
                                ? CupertinoColors.systemBlue
                                : Colors.blue,
                            PlatformInfo.isIOS
                                ? CupertinoColors.systemPurple
                                : Colors.purple,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          PlatformInfo.isIOS
                              ? CupertinoIcons.photo
                              : Icons.photo,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Card with Image Header',
                            style: _getTitleStyle(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This card demonstrates a complex layout with an image header, title, description, and action buttons.',
                            style: _getTextStyle(context),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: AdaptiveButton(
                                    style: AdaptiveButtonStyle.plain,
                                    label: 'Action',
                                    onPressed: () {},
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: AdaptiveButton(
                                    style: PlatformInfo.isIOS26OrHigher()
                                        ? AdaptiveButtonStyle.prominentGlass
                                        : AdaptiveButtonStyle.filled,
                                    label: 'Share',
                                    onPressed: () {},
                                    textColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AdaptiveCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: PlatformInfo.isIOS
                            ? CupertinoColors.systemBlue
                            : Colors.blue,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        PlatformInfo.isIOS
                            ? CupertinoIcons.person_fill
                            : Icons.person,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'User Profile Card',
                            style: _getTitleStyle(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Card with avatar and user information',
                            style: _getTextStyle(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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

  TextStyle _getTextStyle(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return TextStyle(
      fontSize: 15,
      color: PlatformInfo.isIOS
          ? (isDark ? CupertinoColors.white : CupertinoColors.black)
          : Theme.of(context).colorScheme.onSurface,
    );
  }

  TextStyle _getTitleStyle(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: PlatformInfo.isIOS
          ? (isDark ? CupertinoColors.white : CupertinoColors.black)
          : Theme.of(context).colorScheme.onSurface,
    );
  }
}
