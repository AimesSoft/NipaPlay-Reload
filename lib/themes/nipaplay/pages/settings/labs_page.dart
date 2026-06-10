import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/webdav_quick_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
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
            SettingsItem.toggle(
              title: '显示远程访问二维码',
              subtitle: '开启后，远程访问服务页面会显示供手机扫码连接的二维码',
              icon: Ionicons.qr_code_outline,
              value: labsSettings.showRemoteAccessQrCode,
              onChanged: (bool value) {
                labsSettings.setShowRemoteAccessQrCode(value);
              },
            ),
            Divider(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
              height: 1,
            ),
            SettingsItem.toggle(
              title: '显示 Next2和 DFM+ 弹幕内核',
              subtitle: '开启后，弹幕渲染引擎下拉菜单显示 NipaPlay Next2 和 DFM+',
              icon: Ionicons.flask_outline,
              value: labsSettings.enableNext2DanmakuKernel,
              onChanged: (bool value) {
                labsSettings.setEnableNext2DanmakuKernel(value);
              },
            ),
            Divider(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
              height: 1,
            ),
            if (PlayerFactory.isErikaKernelSupported) ...[
              SettingsItem.toggle(
                title: '显示 Erika 播放内核',
                subtitle: '开启后，播放器内核下拉菜单显示 Erika',
                icon: Ionicons.flask_outline,
                value: labsSettings.enableErikaPlayerKernel,
                onChanged: (bool value) {
                  labsSettings.setEnableErikaPlayerKernel(value);
                },
              ),
              Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1,
              ),
            ],
            SettingsItem.toggle(
              title: 'Next++ 激进优化引擎',
              subtitle: '激进优化，推荐。关闭则回退至 Next 原始引擎路径',
              icon: Ionicons.rocket_outline,
              value: labsSettings.enableNextPlusPlusEngine,
              onChanged: (bool value) {
                labsSettings.setEnableNextPlusPlusEngine(value);
              },
            ),
            Divider(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
              height: 1,
            ),
            SettingsItem.button(
              title: 'WebDAV 快捷设置',
              subtitle: '配置底部 WebDAV 快捷 Tab，快速访问 WebDAV 服务器',
              icon: Ionicons.cloud_outline,
              trailingIcon: Ionicons.chevron_forward,
              onTap: () {
                NipaplayWindow.show(
                  context: context,
                  child: const NipaplayWindowScaffold(
                    maxWidth: 600,
                    maxHeightFactor: 0.9,
                    child: WebDAVQuickSettingsPage(),
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
      },
    );
  }
}
