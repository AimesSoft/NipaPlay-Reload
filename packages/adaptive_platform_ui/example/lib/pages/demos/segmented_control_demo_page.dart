import 'package:flutter/cupertino.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

class SegmentedControlDemoPage extends StatefulWidget {
  const SegmentedControlDemoPage({super.key});

  @override
  State<SegmentedControlDemoPage> createState() =>
      _SegmentedControlDemoPageState();
}

class _SegmentedControlDemoPageState extends State<SegmentedControlDemoPage> {
  int _basicSegmentedControlIndex = 0;
  int _coloredSegmentedControlIndex = 1;
  int _shrinkWrappedSegmentedControlIndex = 0;
  int _iconSegmentedControlIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Segmented Control'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(
            left: 24.0,
            right: 24.0,
            top: 100.0,
            bottom: 16.0,
          ),
          children: [
            Row(
              children: [
                Text(
                  'Basic',
                  style: TextStyle(
                    color: PlatformInfo.isIOS
                        ? (MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                              ? CupertinoColors.white
                              : CupertinoColors.black)
                        : null,
                  ),
                ),
                const Spacer(),
                Text(
                  'Selected: ${_basicSegmentedControlIndex + 1}',
                  style: TextStyle(
                    color: PlatformInfo.isIOS
                        ? (MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                              ? CupertinoColors.white
                              : CupertinoColors.black)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveSegmentedControl(
              labels: const ['One', 'Two', 'Three'],
              selectedIndex: _basicSegmentedControlIndex,
              onValueChanged: (i) =>
                  setState(() => _basicSegmentedControlIndex = i),
            ),

            const SizedBox(height: 48),

            Row(
              children: [
                Text(
                  'Colored',
                  style: TextStyle(
                    color: PlatformInfo.isIOS
                        ? (MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                              ? CupertinoColors.white
                              : CupertinoColors.black)
                        : null,
                  ),
                ),
                const Spacer(),
                Text(
                  'Selected: ${_shrinkWrappedSegmentedControlIndex + 1}',
                  style: TextStyle(
                    color: PlatformInfo.isIOS
                        ? (MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                              ? CupertinoColors.white
                              : CupertinoColors.black)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveSegmentedControl(
              labels: const ['One', 'Two', 'Three'],
              selectedIndex: _shrinkWrappedSegmentedControlIndex,
              color: CupertinoColors.systemPink,
              onValueChanged: (i) =>
                  setState(() => _shrinkWrappedSegmentedControlIndex = i),
            ),

            const SizedBox(height: 48),

            Row(
              children: [
                Text(
                  'Shrink wrap',
                  style: TextStyle(
                    color: PlatformInfo.isIOS
                        ? (MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                              ? CupertinoColors.white
                              : CupertinoColors.black)
                        : null,
                  ),
                ),
                const Spacer(),
                Text(
                  'Selected: ${_coloredSegmentedControlIndex + 1}',
                  style: TextStyle(
                    color: PlatformInfo.isIOS
                        ? (MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                              ? CupertinoColors.white
                              : CupertinoColors.black)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveSegmentedControl(
              labels: const ['One', 'Two', 'Three'],
              selectedIndex: _coloredSegmentedControlIndex,
              onValueChanged: (i) =>
                  setState(() => _coloredSegmentedControlIndex = i),
              shrinkWrap: true,
            ),

            const SizedBox(height: 48),

            Row(
              children: [
                Text(
                  'Icons',
                  style: TextStyle(
                    color: PlatformInfo.isIOS
                        ? (MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                              ? CupertinoColors.white
                              : CupertinoColors.black)
                        : null,
                  ),
                ),
                const Spacer(),
                Text(
                  'Selected: ${_iconSegmentedControlIndex + 1}',
                  style: TextStyle(
                    color: PlatformInfo.isIOS
                        ? (MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                              ? CupertinoColors.white
                              : CupertinoColors.black)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: AdaptiveSegmentedControl(
                labels: const [],
                sfSymbols: [
                  PlatformInfo.isIOS26OrHigher() ? 'house.fill' : Icons.house,
                  PlatformInfo.isIOS26OrHigher()
                      ? 'leaf.arrow.trianglehead.clockwise'
                      : Icons.eco,
                  PlatformInfo.isIOS26OrHigher()
                      ? 'figure.walk.diamond'
                      : Icons.directions_walk,
                ],
                selectedIndex: _iconSegmentedControlIndex,
                iconColor: CupertinoColors.systemBlue,
                shrinkWrap: true,
                onValueChanged: (i) =>
                    setState(() => _iconSegmentedControlIndex = i),
                height: 48,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
