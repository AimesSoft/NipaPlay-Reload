import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:provider/provider.dart';

class LabsPage extends StatelessWidget {
  const LabsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<LabsSettingsProvider>(
      builder: (context, labsSettings, child) {
        return ListView(
          children: [
            SettingsItem.toggle(
              title: '大屏幕模式',
              subtitle: '开启后，NipaPlay 主题右上角显示大屏幕模式按钮',
              icon: Ionicons.tv_outline,
              value: labsSettings.enableLargeScreenMode,
              onChanged: (bool value) {
                labsSettings.setEnableLargeScreenMode(value);
              },
            ),
            Divider(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
              height: 1,
            ),
          ],
        );
      },
    );
  }
}
