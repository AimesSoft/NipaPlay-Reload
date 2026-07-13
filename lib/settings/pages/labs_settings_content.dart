import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:provider/provider.dart';

class LabsSettingsContent extends StatelessWidget {
  const LabsSettingsContent({
    super.key,
    required this.onOpenWebDavQuickSettings,
  });

  final VoidCallback onOpenWebDavQuickSettings;

  @override
  Widget build(BuildContext context) {
    return Consumer<LabsSettingsProvider>(
      builder: (context, labsSettings, child) {
        return AdaptiveSettingsPage(
          children: [
            AdaptiveSettingsSection(
              dividerIndent: 56,
              children: [
                AdaptiveSettingsTile.toggle(
                  title: _text(context, '大屏幕模式', '大螢幕模式', 'Large Screen Mode'),
                  subtitle: _text(
                    context,
                    '开启后，桌面和平板布局右上角显示大屏幕模式按钮',
                    '開啟後，桌面和平板布局右上角顯示大螢幕模式按鈕',
                    'Show the large-screen mode button in the desktop and tablet layout.',
                  ),
                  icon: Ionicons.tv_outline,
                  phoneIcon: cupertino.CupertinoIcons.tv,
                  value: labsSettings.enableLargeScreenMode,
                  onChanged: labsSettings.setEnableLargeScreenMode,
                ),
                if (PlayerFactory.isErikaKernelSupported)
                  AdaptiveSettingsTile.toggle(
                    title: _text(
                      context,
                      '显示 Erika 播放内核',
                      '顯示 Erika 播放內核',
                      'Show Erika Player Kernel',
                    ),
                    subtitle: _text(
                      context,
                      '开启后，播放器内核下拉菜单显示 Erika',
                      '開啟後，播放器內核下拉選單顯示 Erika',
                      'Expose Erika in player kernel menus.',
                    ),
                    icon: Ionicons.flask_outline,
                    phoneIcon: cupertino.CupertinoIcons.lab_flask,
                    value: labsSettings.enableErikaPlayerKernel,
                    onChanged: labsSettings.setEnableErikaPlayerKernel,
                  ),
                AdaptiveSettingsTile.button(
                  title: _text(
                    context,
                    'WebDAV 快捷设置',
                    'WebDAV 快捷設定',
                    'WebDAV Quick Settings',
                  ),
                  subtitle: _text(
                    context,
                    '配置底部 WebDAV 快捷 Tab，快速访问 WebDAV 服务器',
                    '配置底部 WebDAV 快捷 Tab，快速訪問 WebDAV 伺服器',
                    'Configure the bottom WebDAV shortcut tab.',
                  ),
                  icon: Ionicons.cloud_outline,
                  phoneIcon: cupertino.CupertinoIcons.cloud,
                  trailingIcon: Ionicons.chevron_forward,
                  onTap: onOpenWebDavQuickSettings,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final localeName = context.l10n.localeName;
    if (localeName.startsWith('zh_Hant')) {
      return traditional;
    }
    if (localeName.startsWith('en')) {
      return english;
    }
    return simplified;
  }
}
