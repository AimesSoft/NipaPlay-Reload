import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DatePickerDemoPage extends StatefulWidget {
  const DatePickerDemoPage({super.key});

  @override
  State<DatePickerDemoPage> createState() => _DatePickerDemoPageState();
}

class _DatePickerDemoPageState extends State<DatePickerDemoPage> {
  DateTime? _selectedDate;
  DateTime? _selectedDateWithRange;
  DateTime? _selectedDateTime;

  @override
  Widget build(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Date Picker'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(height: 100),
          _buildInfoCard(context, isDark),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: 'Basic Date Picker',
            description: 'Select a date',
            child: _buildDatePickerButton(
              context,
              isDark,
              label: 'Select Date',
              selectedDate: _selectedDate,
              onPressed: () async {
                final result = await AdaptiveDatePicker.show(
                  context: context,
                  initialDate: _selectedDate ?? DateTime.now(),
                );
                if (result != null) {
                  setState(() => _selectedDate = result);
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: 'Date Picker with Range',
            description: 'Select a date within a range',
            child: _buildDatePickerButton(
              context,
              isDark,
              label: 'Select Date (2020-2025)',
              selectedDate: _selectedDateWithRange,
              onPressed: () async {
                final result = await AdaptiveDatePicker.show(
                  context: context,
                  initialDate: _selectedDateWithRange ?? DateTime.now(),
                  firstDate: DateTime(2020, 1, 1),
                  lastDate: DateTime(2025, 12, 31),
                );
                if (result != null) {
                  setState(() => _selectedDateWithRange = result);
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            isDark,
            title: 'Date & Time Picker',
            description: 'Select both date and time (iOS only)',
            child: _buildDatePickerButton(
              context,
              isDark,
              label: 'Select Date & Time',
              selectedDate: _selectedDateTime,
              showTime: true,
              onPressed: () async {
                final result = await AdaptiveDatePicker.show(
                  context: context,
                  initialDate: _selectedDateTime ?? DateTime.now(),
                  mode: CupertinoDatePickerMode.dateAndTime,
                );
                if (result != null) {
                  setState(() => _selectedDateTime = result);
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
                  ? 'iOS uses CupertinoDatePicker in a modal bottom sheet'
                  : 'Android uses Material DatePicker dialog',
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

  Widget _buildDatePickerButton(
    BuildContext context,
    bool isDark, {
    required String label,
    required DateTime? selectedDate,
    required VoidCallback onPressed,
    bool showTime = false,
  }) {
    final dateFormat = showTime
        ? DateFormat('MMM dd, yyyy - HH:mm')
        : DateFormat('MMM dd, yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdaptiveButton(
          onPressed: onPressed,
          label: label,
          style: AdaptiveButtonStyle.tinted,
        ),
        if (selectedDate != null) ...[
          const SizedBox(height: 12),
          AdaptiveCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.calendar
                      : Icons.calendar_today,
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
                        'Selected Date${showTime ? ' & Time' : ''}',
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
                        dateFormat.format(selectedDate),
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
