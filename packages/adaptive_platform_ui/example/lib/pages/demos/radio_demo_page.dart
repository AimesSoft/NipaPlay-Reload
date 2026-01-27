import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

enum SizeOption { small, medium, large }

enum ColorOption { red, green, blue }

enum NotificationOption { all, mentions, none }

class RadioDemoPage extends StatefulWidget {
  const RadioDemoPage({super.key});

  @override
  State<RadioDemoPage> createState() => _RadioDemoPageState();
}

class _RadioDemoPageState extends State<RadioDemoPage> {
  SizeOption? _selectedSize = SizeOption.medium;
  ColorOption? _selectedColor = ColorOption.blue;
  NotificationOption? _selectedNotification = NotificationOption.all;
  String? _toggleableOption = 'Option 1';

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'AdaptiveRadio Demo'),
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
          title: 'Basic Radio Group',
          description: 'Simple radio button group with text labels',
          child: Column(
            children: [
              _buildRadioListTile<SizeOption>(
                title: 'Small',
                value: SizeOption.small,
                groupValue: _selectedSize,
                onChanged: (value) {
                  setState(() {
                    _selectedSize = value;
                  });
                },
              ),
              _buildRadioListTile<SizeOption>(
                title: 'Medium',
                value: SizeOption.medium,
                groupValue: _selectedSize,
                onChanged: (value) {
                  setState(() {
                    _selectedSize = value;
                  });
                },
              ),
              _buildRadioListTile<SizeOption>(
                title: 'Large',
                value: SizeOption.large,
                groupValue: _selectedSize,
                onChanged: (value) {
                  setState(() {
                    _selectedSize = value;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Custom Colors',
          description: 'Radio buttons with custom active colors',
          child: Column(
            children: [
              _buildRadioListTileWithColor(
                title: 'Red',
                value: ColorOption.red,
                groupValue: _selectedColor,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemRed
                    : Colors.red,
                onChanged: (value) {
                  setState(() {
                    _selectedColor = value;
                  });
                },
              ),
              _buildRadioListTileWithColor(
                title: 'Green',
                value: ColorOption.green,
                groupValue: _selectedColor,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemGreen
                    : Colors.green,
                onChanged: (value) {
                  setState(() {
                    _selectedColor = value;
                  });
                },
              ),
              _buildRadioListTileWithColor(
                title: 'Blue',
                value: ColorOption.blue,
                groupValue: _selectedColor,
                color: PlatformInfo.isIOS
                    ? CupertinoColors.systemBlue
                    : Colors.blue,
                onChanged: (value) {
                  setState(() {
                    _selectedColor = value;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Radio Group in Card',
          description: 'Radio buttons grouped inside a card',
          child: AdaptiveCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notification Settings', style: _getTitleStyle(context)),
                const SizedBox(height: 12),
                _buildRadioListTile<NotificationOption>(
                  title: 'All Notifications',
                  subtitle: 'Receive all notifications',
                  value: NotificationOption.all,
                  groupValue: _selectedNotification,
                  onChanged: (value) {
                    setState(() {
                      _selectedNotification = value;
                    });
                  },
                ),
                _buildRadioListTile<NotificationOption>(
                  title: 'Mentions Only',
                  subtitle: 'Only when mentioned',
                  value: NotificationOption.mentions,
                  groupValue: _selectedNotification,
                  onChanged: (value) {
                    setState(() {
                      _selectedNotification = value;
                    });
                  },
                ),
                _buildRadioListTile<NotificationOption>(
                  title: 'None',
                  subtitle: 'Disable all notifications',
                  value: NotificationOption.none,
                  groupValue: _selectedNotification,
                  onChanged: (value) {
                    setState(() {
                      _selectedNotification = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Toggleable Radio',
          description: 'Radio buttons that can be deselected by tapping again',
          child: Column(
            children: [
              _buildRadioListTile<String>(
                title: 'Option 1',
                value: 'Option 1',
                groupValue: _toggleableOption,
                toggleable: true,
                onChanged: (value) {
                  setState(() {
                    _toggleableOption = value;
                  });
                },
              ),
              _buildRadioListTile<String>(
                title: 'Option 2',
                value: 'Option 2',
                groupValue: _toggleableOption,
                toggleable: true,
                onChanged: (value) {
                  setState(() {
                    _toggleableOption = value;
                  });
                },
              ),
              _buildRadioListTile<String>(
                title: 'Option 3',
                value: 'Option 3',
                groupValue: _toggleableOption,
                toggleable: true,
                onChanged: (value) {
                  setState(() {
                    _toggleableOption = value;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSection(
          context,
          title: 'Disabled State',
          description: 'Radio buttons in disabled state',
          child: Column(
            children: [
              _buildRadioListTile<int>(
                title: 'Disabled Unselected',
                value: 1,
                groupValue: 2,
                onChanged: null,
              ),
              _buildRadioListTile<int>(
                title: 'Disabled Selected',
                value: 2,
                groupValue: 2,
                onChanged: null,
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

  Widget _buildRadioListTile<T>({
    required String title,
    String? subtitle,
    required T value,
    required T? groupValue,
    required ValueChanged<T?>? onChanged,
    bool toggleable = false,
  }) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: onChanged == null
            ? null
            : () {
                if (toggleable && value == groupValue) {
                  onChanged(null);
                } else {
                  onChanged(value);
                }
              },
        child: Row(
          children: [
            AdaptiveRadio<T>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              toggleable: toggleable,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: PlatformInfo.isIOS
                          ? (isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black)
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: PlatformInfo.isIOS
                            ? (isDark
                                  ? CupertinoColors.systemGrey
                                  : CupertinoColors.systemGrey2)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioListTileWithColor<T>({
    required String title,
    required T value,
    required T? groupValue,
    required Color color,
    required ValueChanged<T?>? onChanged,
  }) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged(value),
        child: Row(
          children: [
            AdaptiveRadio<T>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: PlatformInfo.isIOS
                      ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
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
