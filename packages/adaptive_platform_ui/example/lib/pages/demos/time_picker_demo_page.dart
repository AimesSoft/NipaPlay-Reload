import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class TimePickerDemoPage extends StatefulWidget {
  const TimePickerDemoPage({super.key});

  @override
  State<TimePickerDemoPage> createState() => _TimePickerDemoPageState();
}

class _TimePickerDemoPageState extends State<TimePickerDemoPage> {
  TimeOfDay? _selectedTime12;
  TimeOfDay? _selectedTime24;

  @override
  Widget build(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Time Picker'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(height: 100),
          _buildInfoCard(context, isDark),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: '12-Hour Format',
            description: 'Select time in 12-hour format (AM/PM)',
            child: _buildTimePickerButton(
              context,
              isDark,
              label: 'Select Time (12h)',
              selectedTime: _selectedTime12,
              onPressed: () async {
                final result = await AdaptiveTimePicker.show(
                  context: context,
                  initialTime: _selectedTime12 ?? TimeOfDay.now(),
                  use24HourFormat: false,
                );
                if (result != null) {
                  setState(() => _selectedTime12 = result);
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: '24-Hour Format',
            description: 'Select time in 24-hour format',
            child: _buildTimePickerButton(
              context,
              isDark,
              label: 'Select Time (24h)',
              selectedTime: _selectedTime24,
              onPressed: () async {
                final result = await AdaptiveTimePicker.show(
                  context: context,
                  initialTime: _selectedTime24 ?? TimeOfDay.now(),
                  use24HourFormat: true,
                );
                if (result != null) {
                  setState(() => _selectedTime24 = result);
                }
              },
            ),
          ),
        ],
      ),
    );
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
                  ? 'iOS uses CupertinoDatePicker in time mode in a modal bottom sheet'
                  : 'Android uses Material TimePicker dialog',
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
    required String description,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: isDark
                ? (PlatformInfo.isIOS ? CupertinoColors.white : Colors.white)
                : (PlatformInfo.isIOS ? CupertinoColors.black : Colors.black87),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(
            fontSize: 14,
            color: isDark
                ? (PlatformInfo.isIOS
                      ? CupertinoColors.systemGrey
                      : Colors.grey[400])
                : (PlatformInfo.isIOS
                      ? CupertinoColors.systemGrey2
                      : Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }

  Widget _buildTimePickerButton(
    BuildContext context,
    bool isDark, {
    required String label,
    required TimeOfDay? selectedTime,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdaptiveButton(
          onPressed: onPressed,
          label: label,
          style: AdaptiveButtonStyle.tinted,
        ),
        if (selectedTime != null) ...[
          const SizedBox(height: 12),
          AdaptiveCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  PlatformInfo.isIOS ? CupertinoIcons.clock : Icons.access_time,
                  size: 20,
                  color: isDark
                      ? (PlatformInfo.isIOS
                            ? CupertinoColors.systemGrey
                            : Colors.grey[400])
                      : (PlatformInfo.isIOS
                            ? CupertinoColors.systemGrey2
                            : Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected Time',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? (PlatformInfo.isIOS
                                    ? CupertinoColors.systemGrey
                                    : Colors.grey[400])
                              : (PlatformInfo.isIOS
                                    ? CupertinoColors.systemGrey2
                                    : Colors.grey[600]),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedTime.format(context),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? (PlatformInfo.isIOS
                                    ? CupertinoColors.white
                                    : Colors.white)
                              : (PlatformInfo.isIOS
                                    ? CupertinoColors.black
                                    : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
