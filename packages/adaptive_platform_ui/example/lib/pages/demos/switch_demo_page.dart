import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class SwitchDemoPage extends StatefulWidget {
  const SwitchDemoPage({super.key});

  @override
  State<SwitchDemoPage> createState() => _SwitchDemoPageState();
}

class _SwitchDemoPageState extends State<SwitchDemoPage> {
  bool _basicSwitch = false;
  bool _customColorSwitch = true;
  bool _redSwitch = false;
  bool _greenSwitch = true;
  bool _purpleSwitch = false;
  final bool _disabledSwitch = false;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'AdaptiveSwitch Demo'),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.only(
        left: 16.0,
        bottom: 40,
        right: 32.0,
        top: 16.0,
      ),
      children: [
        SizedBox(height: 120),
        // Platform Information
        _buildSection(
          'Platform Information',
          AdaptiveCard(
            padding: const EdgeInsets.all(12),

            child: Text(
              PlatformInfo.platformDescription,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PlatformInfo.isIOS
                    ? (MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? CupertinoColors.white
                          : CupertinoColors.black)
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        // Basic Switch
        _buildSection(
          'Basic Switch',
          _buildSwitchRow(
            'Default Switch',
            _basicSwitch,
            (value) => setState(() => _basicSwitch = value),
          ),
        ),

        const SizedBox(height: 32),

        // Custom Color Switch
        _buildSection(
          'Custom Colors',
          Column(
            children: [
              _buildSwitchRow(
                'Blue Switch',
                _customColorSwitch,
                (value) => setState(() => _customColorSwitch = value),
                activeColor: Colors.blue,
              ),
              const SizedBox(height: 16),
              _buildSwitchRow(
                'Red Switch',
                _redSwitch,
                (value) => setState(() => _redSwitch = value),
                activeColor: Colors.red,
              ),
              const SizedBox(height: 16),
              _buildSwitchRow(
                'Green Switch',
                _greenSwitch,
                (value) => setState(() => _greenSwitch = value),
                activeColor: Colors.green,
              ),
              const SizedBox(height: 16),
              _buildSwitchRow(
                'Purple Switch',
                _purpleSwitch,
                (value) => setState(() => _purpleSwitch = value),
                activeColor: Colors.purple,
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Disabled State
        _buildSection(
          'Disabled State',
          _buildSwitchRow('Disabled (On)', _disabledSwitch, null),
        ),

        const SizedBox(height: 32),

        // Switch States Overview
        _buildSection(
          'All States',
          Column(
            children: [
              _buildStateRow('Off', false),
              const SizedBox(height: 12),
              _buildStateRow('On', true),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Description
        _buildSection(
          'About',
          Text(
            'The AdaptiveSwitch automatically uses:\n\n'
            '• Native iOS 26 UISwitch on iOS 26+\n'
            '• CupertinoSwitch on iOS 18 and below\n'
            '• Material Switch on Android\n\n'
            'Features:\n'
            '• Native animations and haptic feedback\n'
            '• Hot reload support\n'
            '• Automatic light/dark mode',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: PlatformInfo.isIOS
                  ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.systemGrey2)
                  : (isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildSwitchRow(
    String label,
    bool value,
    ValueChanged<bool>? onChanged, {
    Color? activeColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 16)),
        AdaptiveSwitch(
          value: value,
          onChanged: onChanged,
          activeColor: activeColor,
        ),
      ],
    );
  }

  Widget _buildStateRow(String label, bool value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: PlatformInfo.isIOS
                ? CupertinoColors.secondaryLabel
                : (isDark ? Colors.grey[400] : Colors.grey[700]),
          ),
        ),
        AdaptiveSwitch(value: value, onChanged: (v) {}),
      ],
    );
  }
}
