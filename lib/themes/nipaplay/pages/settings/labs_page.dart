import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/webdav_quick_settings_page.dart';
import 'package:provider/provider.dart';

class LabsPage extends StatelessWidget {
  const LabsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Consumer<LabsSettingsProvider>(
          builder: (context, labsSettings, child) {
            return Column(
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
        ),
        SettingsItem.button(
          title: 'WebDAV 快捷设置',
          subtitle: '配置底部 WebDAV 快捷 Tab，快速访问 WebDAV 服务器',
          icon: Ionicons.cloud_outline,
          trailingIcon: Ionicons.chevron_forward,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const WebDAVQuickSettingsPage(),
              ),
            );
          },
        ),
        Divider(
          color: colorScheme.onSurface.withValues(alpha: 0.12),
          height: 1,
        ),
      ],
    );
  }
}
