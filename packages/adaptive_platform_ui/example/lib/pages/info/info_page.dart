import 'dart:io';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui_example/utils/global_variables.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final padding = MediaQuery.of(context).padding;
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: "Info"),
      body: SafeArea(
        bottom: false,
        child: ListView(
          controller: infoScrollController,
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('Platform Information'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow('Platform', PlatformInfo.platformDescription),
              if (PlatformInfo.isIOS)
                _InfoRow('iOS Version', '${PlatformInfo.iOSVersion}'),
              if (PlatformInfo.isIOS)
                _InfoRow(
                  'iOS 26+ Features',
                  PlatformInfo.isIOS26OrHigher()
                      ? 'Available'
                      : 'Not Available',
                ),
              if (!PlatformInfo.isWeb)
                _InfoRow('OS Version', Platform.operatingSystemVersion),
            ]),
            const SizedBox(height: 24),
            _buildSectionHeader('Screen Information'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow(
                'Screen Size',
                '${screenSize.width.toStringAsFixed(1)} × ${screenSize.height.toStringAsFixed(1)}',
              ),
              _InfoRow('Pixel Ratio', '${pixelRatio.toStringAsFixed(2)}x'),
              _InfoRow(
                'Logical Resolution',
                '${(screenSize.width * pixelRatio).toStringAsFixed(0)} × ${(screenSize.height * pixelRatio).toStringAsFixed(0)}',
              ),
              _InfoRow('Brightness Mode', isDark ? 'Dark' : 'Light'),
            ]),
            const SizedBox(height: 24),
            _buildSectionHeader('Safe Area'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow('Top', '${padding.top.toStringAsFixed(1)} pt'),
              _InfoRow('Bottom', '${padding.bottom.toStringAsFixed(1)} pt'),
              _InfoRow('Left', '${padding.left.toStringAsFixed(1)} pt'),
              _InfoRow('Right', '${padding.right.toStringAsFixed(1)} pt'),
            ]),
            const SizedBox(height: 24),
            _buildSectionHeader('Available Widgets'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow('AdaptiveScaffold', 'Available'),
              _InfoRow('AdaptiveButton', 'Available'),
              _InfoRow('AdaptiveSwitch', 'Available'),
              _InfoRow('AdaptiveSlider', 'Available'),
              _InfoRow('AdaptiveSegmentedControl', 'Available'),
              _InfoRow('AdaptiveAlertDialog', 'Available'),
              if (PlatformInfo.isIOS26OrHigher()) ...[
                _InfoRow('IOS26NativeTabBar', 'Available'),
                _InfoRow('IOS26NativeToolbar', 'Available'),
                _InfoRow('IOS26NativeSearchTabBar', 'Available'),
              ],
            ]),
            const SizedBox(height: 24),
            _buildSectionHeader('Package Information'),
            const SizedBox(height: 12),
            _buildInfoCard([
              _InfoRow('Package', 'adaptive_platform_ui'),
              _InfoRow('Purpose', 'Adaptive Platform Widgets'),
              _InfoRow('GitHub', 'github.com/berkaycatak/adaptive_platform_ui'),
            ]),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoCard(List<_InfoRow> rows) {
    if (PlatformInfo.isIOS) {
      return CupertinoListSection.insetGrouped(
        margin: EdgeInsets.zero,
        backgroundColor: CupertinoColors.systemBackground,
        children: rows
            .map(
              (row) => CupertinoListTile(
                title: Text(row.label),
                trailing: Text(
                  row.value,
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            )
            .toList(),
      );
    }

    // Android
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: rows
              .map(
                (row) => ListTile(
                  title: Text(row.label),
                  trailing: Text(
                    row.value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                  dense: true,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;

  _InfoRow(this.label, this.value);
}
