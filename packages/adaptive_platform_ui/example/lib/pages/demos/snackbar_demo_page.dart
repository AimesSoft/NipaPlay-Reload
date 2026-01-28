import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class SnackbarDemoPage extends StatelessWidget {
  const SnackbarDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Snackbar Demo'),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              title: 'Basic Snackbar',
              description: 'Simple messages without actions',
              children: [
                _DemoButton(
                  label: 'Info Snackbar',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemGrey
                      : Colors.grey,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'This is an info message',
                      type: AdaptiveSnackBarType.info,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _DemoButton(
                  label: 'Success Snackbar',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemGreen
                      : Colors.green,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'Operation completed successfully!',
                      type: AdaptiveSnackBarType.success,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _DemoButton(
                  label: 'Warning Snackbar',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemOrange
                      : Colors.orange,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'This action cannot be undone',
                      type: AdaptiveSnackBarType.warning,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _DemoButton(
                  label: 'Error Snackbar',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemRed
                      : Colors.red,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'An error occurred. Please try again.',
                      type: AdaptiveSnackBarType.error,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSection(
              title: 'With Actions',
              description: 'Snackbars with action buttons',
              children: [
                _DemoButton(
                  label: 'Success with Action',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemGreen
                      : Colors.green,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'File saved successfully',
                      type: AdaptiveSnackBarType.success,
                      action: 'Open',
                      onActionPressed: () {
                        // Handle action
                        actionClicked(context);
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                _DemoButton(
                  label: 'Error with Retry',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemRed
                      : Colors.red,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'Connection failed',
                      type: AdaptiveSnackBarType.error,
                      action: 'Retry',
                      onActionPressed: () {
                        // Handle retry
                        actionClicked(context);
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                _DemoButton(
                  label: 'Info with Details',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemGrey
                      : Colors.grey,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'New update available',
                      type: AdaptiveSnackBarType.info,
                      action: 'Details',
                      onActionPressed: () {
                        // Show details
                        actionClicked(context);
                      },
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSection(
              title: 'Custom Duration',
              description: 'Control how long snackbars are visible',
              children: [
                _DemoButton(
                  label: 'Short (2 seconds)',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemBlue
                      : Colors.blue,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'This will disappear quickly',
                      duration: const Duration(seconds: 2),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _DemoButton(
                  label: 'Long (8 seconds)',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemBlue
                      : Colors.blue,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message: 'This will stay visible longer',
                      duration: const Duration(seconds: 8),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSection(
              title: 'Long Messages',
              description: 'Snackbars with longer text content',
              children: [
                _DemoButton(
                  label: 'Long Message',
                  color: PlatformInfo.isIOS
                      ? CupertinoColors.systemGrey
                      : Colors.grey,
                  onPressed: () {
                    AdaptiveSnackBar.show(
                      context,
                      message:
                          'This is a much longer message that demonstrates how snackbars handle multi-line text content gracefully.',
                      type: AdaptiveSnackBarType.info,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  void actionClicked(BuildContext context) {
    AdaptiveAlertDialog.show(
      context: context,
      title: 'Bingo!',
      message: 'You clicked the action button.',
      actions: [AlertAction(title: 'OK', onPressed: () {})],
    );
  }

  Widget _buildSection({
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 14,
            color: PlatformInfo.isIOS
                ? CupertinoColors.secondaryLabel
                : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

class _DemoButton extends StatelessWidget {
  const _DemoButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AdaptiveButton(onPressed: onPressed, label: label),
    );
  }
}
