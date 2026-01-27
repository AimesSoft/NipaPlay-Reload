import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class SliderDemoPage extends StatefulWidget {
  const SliderDemoPage({super.key});

  @override
  State<SliderDemoPage> createState() => _SliderDemoPageState();
}

class _SliderDemoPageState extends State<SliderDemoPage> {
  double _basicValue = 0.5;
  double _blueValue = 0.3;
  double _redValue = 0.7;
  double _greenValue = 0.6;
  double _rangeValue = 50.0;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'AdaptiveSlider Demo'),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        SizedBox(height: 120),
        _buildSection(
          'Basic Slider',
          Column(
            children: [
              AdaptiveSlider(
                value: _basicValue,
                onChanged: (value) => setState(() => _basicValue = value),
              ),
              const SizedBox(height: 8),
              Text(
                'Value: ${_basicValue.toStringAsFixed(2)}',
                style: TextStyle(
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
        _buildSection(
          'Custom Colors',
          Column(
            children: [
              AdaptiveSlider(
                value: _blueValue,
                onChanged: (value) => setState(() => _blueValue = value),
                activeColor: Colors.blue,
              ),
              const SizedBox(height: 16),
              AdaptiveSlider(
                value: _redValue,
                onChanged: (value) => setState(() => _redValue = value),
                activeColor: Colors.red,
              ),
              const SizedBox(height: 16),
              AdaptiveSlider(
                value: _greenValue,
                onChanged: (value) => setState(() => _greenValue = value),
                activeColor: Colors.green,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _buildSection(
          'Custom Range (0-100)',
          Column(
            children: [
              AdaptiveSlider(
                value: _rangeValue,
                min: 0,
                max: 100,
                onChanged: (value) => setState(() => _rangeValue = value),
                activeColor: Colors.purple,
              ),
              const SizedBox(height: 8),
              Text(
                'Value: ${_rangeValue.toStringAsFixed(0)}',
                style: TextStyle(
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
}
