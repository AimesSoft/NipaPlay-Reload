import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class CheckboxDemoPage extends StatefulWidget {
  const CheckboxDemoPage({super.key});

  @override
  State<CheckboxDemoPage> createState() => _CheckboxDemoPageState();
}

class _CheckboxDemoPageState extends State<CheckboxDemoPage> {
  bool _basicCheckbox = false;
  bool _blueCheckbox = true;
  bool _redCheckbox = false;
  bool _greenCheckbox = true;
  bool _purpleCheckbox = false;
  bool? _tristateCheckbox = false;
  final bool _disabledCheckbox = true;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'AdaptiveCheckbox Demo'),
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
        const SizedBox(height: 120),
        // Platform Information
        _buildSection(
          'Platform Information',
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PlatformInfo.isIOS
                  ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                        ? CupertinoColors.systemGrey5
                        : CupertinoColors.systemGrey6)
                  : (isDark ? Colors.grey[850] : Colors.grey[200]),
              borderRadius: BorderRadius.circular(8),
            ),
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

        // Basic Checkbox
        _buildSection(
          'Basic Checkbox',
          _buildCheckboxRow(
            'Default Checkbox',
            _basicCheckbox,
            (value) => setState(() => _basicCheckbox = value ?? false),
          ),
        ),

        const SizedBox(height: 32),

        // Custom Color Checkboxes
        _buildSection(
          'Custom Colors',
          Column(
            children: [
              _buildCheckboxRow(
                'Blue Checkbox',
                _blueCheckbox,
                (value) => setState(() => _blueCheckbox = value ?? false),
                activeColor: Colors.blue,
              ),
              const SizedBox(height: 16),
              _buildCheckboxRow(
                'Red Checkbox',
                _redCheckbox,
                (value) => setState(() => _redCheckbox = value ?? false),
                activeColor: Colors.red,
              ),
              const SizedBox(height: 16),
              _buildCheckboxRow(
                'Green Checkbox',
                _greenCheckbox,
                (value) => setState(() => _greenCheckbox = value ?? false),
                activeColor: Colors.green,
              ),
              const SizedBox(height: 16),
              _buildCheckboxRow(
                'Purple Checkbox',
                _purpleCheckbox,
                (value) => setState(() => _purpleCheckbox = value ?? false),
                activeColor: Colors.purple,
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Tristate Checkbox
        _buildSection(
          'Tristate Checkbox',
          Column(
            children: [
              _buildCheckboxRow(
                'Tristate (tap to cycle)',
                _tristateCheckbox,
                (value) => setState(() => _tristateCheckbox = value),
                tristate: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Current state: ${_tristateCheckbox == null ? "null (mixed)" : _tristateCheckbox.toString()}',
                style: TextStyle(
                  fontSize: 12,
                  color: PlatformInfo.isIOS
                      ? (MediaQuery.platformBrightnessOf(context) ==
                                Brightness.dark
                            ? CupertinoColors.systemGrey
                            : CupertinoColors.systemGrey2)
                      : (isDark ? Colors.grey[400] : Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Disabled State
        _buildSection(
          'Disabled State',
          _buildCheckboxRow('Disabled (Checked)', _disabledCheckbox, null),
        ),

        const SizedBox(height: 32),

        // Checkbox States Overview
        _buildSection(
          'All States',
          Column(
            children: [
              _buildStateRow('Unchecked', false),
              const SizedBox(height: 12),
              _buildStateRow('Checked', true),
              const SizedBox(height: 12),
              _buildStateRow('Mixed (tristate)', null, tristate: true),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Description
        _buildSection(
          'About',
          Text(
            'The AdaptiveCheckbox automatically uses:\n\n'
            '• Native iOS 26 checkbox on iOS 26+\n'
            '• Custom iOS-style checkbox on iOS 18 and below\n'
            '• Material Checkbox on Android\n\n'
            'Features:\n'
            '• Native animations and haptic feedback\n'
            '• Hot reload support\n'
            '• Automatic light/dark mode\n'
            '• Tristate support (true/false/null)',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: PlatformInfo.isIOS
                ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                      ? CupertinoColors.white
                      : CupertinoColors.black)
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildCheckboxRow(
    String label,
    bool? value,
    ValueChanged<bool?>? onChanged, {
    Color? activeColor,
    bool tristate = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: PlatformInfo.isIOS
                ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                      ? CupertinoColors.white
                      : CupertinoColors.black)
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
        AdaptiveCheckbox(
          value: value,
          tristate: tristate,
          onChanged: onChanged,
          activeColor: activeColor,
        ),
      ],
    );
  }

  Widget _buildStateRow(String label, bool? value, {bool tristate = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: PlatformInfo.isIOS
                ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2)
                : (isDark ? Colors.grey[400] : Colors.grey[700]),
          ),
        ),
        AdaptiveCheckbox(value: value, tristate: tristate, onChanged: (v) {}),
      ],
    );
  }
}
