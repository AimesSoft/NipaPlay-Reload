import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class TooltipDemoPage extends StatefulWidget {
  const TooltipDemoPage({super.key});

  @override
  State<TooltipDemoPage> createState() => _TooltipDemoPageState();
}

class _TooltipDemoPageState extends State<TooltipDemoPage> {
  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'AdaptiveTooltip Demo'),
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
          title: 'Basic Tooltips',
          description: 'Tap or long press icons to see tooltips',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              AdaptiveTooltip(
                message: 'Home',
                child: Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.home : Icons.home,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveTooltip(
                message: 'Search',
                child: Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.search : Icons.search,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveTooltip(
                message: 'Settings',
                child: Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.settings : Icons.settings,
                  size: 32,
                  color: _getIconColor(context),
                ),
              ),
              AdaptiveTooltip(
                message: 'Profile',
                child: Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.person : Icons.person,
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
          title: 'Tooltips on Buttons',
          description: 'Long press buttons to show tooltips',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              AdaptiveTooltip(
                message: 'Add new item',
                child: _buildIconButton(
                  context,
                  icon: PlatformInfo.isIOS ? CupertinoIcons.add : Icons.add,
                  onPressed: () {},
                ),
              ),
              AdaptiveTooltip(
                message: 'Edit selected',
                child: _buildIconButton(
                  context,
                  icon: PlatformInfo.isIOS ? CupertinoIcons.pencil : Icons.edit,
                  onPressed: () {},
                ),
              ),
              AdaptiveTooltip(
                message: 'Delete item',
                child: _buildIconButton(
                  context,
                  icon: PlatformInfo.isIOS
                      ? CupertinoIcons.delete
                      : Icons.delete,
                  onPressed: () {},
                ),
              ),
              AdaptiveTooltip(
                message: 'Share with others',
                child: _buildIconButton(
                  context,
                  icon: PlatformInfo.isIOS ? CupertinoIcons.share : Icons.share,
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Long Messages',
          description: 'Tooltips with longer descriptive text',
          child: Column(
            children: [
              AdaptiveTooltip(
                message:
                    'This is a much longer tooltip message that provides more detailed information',
                child: AdaptiveCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        PlatformInfo.isIOS
                            ? CupertinoIcons.info_circle
                            : Icons.info,
                        color: PlatformInfo.isIOS
                            ? CupertinoColors.systemBlue
                            : Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Long press for more information',
                          style: _getTextStyle(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Tooltips Below',
          description: 'Tooltips positioned below the widget',
          child: Center(
            child: AdaptiveTooltip(
              message: 'Tooltip appears below',
              preferBelow: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemBlue
                      : Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Long Press Me',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Tooltips Above',
          description: 'Tooltips positioned above the widget',
          child: Center(
            child: AdaptiveTooltip(
              message: 'Tooltip appears above',
              preferBelow: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemGreen
                      : Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Long Press Me',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Interactive Elements',
          description: 'Tooltips on various interactive elements',
          child: AdaptiveCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                AdaptiveTooltip(
                  message: 'Toggle notifications',
                  child: Row(
                    children: [
                      Icon(
                        PlatformInfo.isIOS
                            ? CupertinoIcons.bell
                            : Icons.notifications,
                        color: _getIconColor(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Notifications',
                          style: _getTextStyle(context),
                        ),
                      ),
                      AdaptiveSwitch(value: true, onChanged: (value) {}),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AdaptiveTooltip(
                  message: 'Adjust brightness level',
                  child: Row(
                    children: [
                      Icon(
                        PlatformInfo.isIOS
                            ? CupertinoIcons.brightness
                            : Icons.brightness_6,
                        color: _getIconColor(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AdaptiveSlider(
                          value: 0.7,
                          onChanged: (value) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Grid with Tooltips',
          description: 'Multiple items with individual tooltips',
          child: GridView.count(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              _buildGridItem(
                context,
                'Camera',
                CupertinoIcons.camera,
                Icons.camera_alt,
              ),
              _buildGridItem(
                context,
                'Photos',
                CupertinoIcons.photo,
                Icons.photo_library,
              ),
              _buildGridItem(
                context,
                'Music',
                CupertinoIcons.music_note,
                Icons.music_note,
              ),
              _buildGridItem(
                context,
                'Videos',
                CupertinoIcons.play_rectangle,
                Icons.video_library,
              ),
              _buildGridItem(
                context,
                'Files',
                CupertinoIcons.folder,
                Icons.folder,
              ),
              _buildGridItem(
                context,
                'Calendar',
                CupertinoIcons.calendar,
                Icons.calendar_today,
              ),
              _buildGridItem(
                context,
                'Clock',
                CupertinoIcons.clock,
                Icons.access_time,
              ),
              _buildGridItem(
                context,
                'Weather',
                CupertinoIcons.cloud_sun,
                Icons.wb_sunny,
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

  Widget _buildIconButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: AdaptiveButton.icon(
        style: PlatformInfo.isIOS26OrHigher()
            ? AdaptiveButtonStyle.tinted
            : AdaptiveButtonStyle.filled,
        icon: icon,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildGridItem(
    BuildContext context,
    String tooltip,
    IconData iosIcon,
    IconData androidIcon,
  ) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return AdaptiveTooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: PlatformInfo.isIOS
              ? (isDark
                    ? CupertinoColors.systemGrey5.darkColor
                    : CupertinoColors.systemGrey6)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          PlatformInfo.isIOS ? iosIcon : androidIcon,
          size: 32,
          color: _getIconColor(context),
        ),
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
}
