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
          title: _text(context, '实验室', '實驗室', 'Labs'),
          children: [
            AdaptiveSettingsSection(
              dividerIndent: 56,
              children: [
                AdaptiveSettingsTile.toggle(
                  title: _text(context, '大屏幕模式', '大螢幕模式', 'Large Screen Mode'),
                  subtitle: _text(
                    context,
                    '开启后，NipaPlay 主题右上角显示大屏幕模式按钮',
                    '開啟後，NipaPlay 主題右上角顯示大螢幕模式按鈕',
                    'Show the large-screen mode button in the NipaPlay theme.',
                  ),
                  icon: Ionicons.tv_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.tv,
                  value: labsSettings.enableLargeScreenMode,
                  onChanged: labsSettings.setEnableLargeScreenMode,
                ),
                AdaptiveSettingsTile.toggle(
                  title: _text(
                    context,
                    '显示 Next2和 DFM+ 弹幕内核',
                    '顯示 Next2 和 DFM+ 彈幕內核',
                    'Show Next2 and DFM+ Danmaku Kernels',
                  ),
                  subtitle: _text(
                    context,
                    '开启后，弹幕渲染引擎下拉菜单显示 NipaPlay Next2 和 DFM+',
                    '開啟後，彈幕渲染引擎下拉選單顯示 NipaPlay Next2 和 DFM+',
                    'Expose NipaPlay Next2 and DFM+ in danmaku renderer menus.',
                  ),
                  icon: Ionicons.flask_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.lab_flask,
                  value: labsSettings.enableNext2DanmakuKernel,
                  onChanged: labsSettings.setEnableNext2DanmakuKernel,
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
                    cupertinoIcon: cupertino.CupertinoIcons.lab_flask,
                    value: labsSettings.enableErikaPlayerKernel,
                    onChanged: labsSettings.setEnableErikaPlayerKernel,
                  ),
                AdaptiveSettingsTile.toggle(
                  title: _text(
                    context,
                    'Next++ 激进优化引擎',
                    'Next++ 激進最佳化引擎',
                    'Next++ Aggressive Engine',
                  ),
                  subtitle: _text(
                    context,
                    '激进优化，推荐。关闭则回退至 Next 原始引擎路径',
                    '激進最佳化，推薦。關閉則回退至 Next 原始引擎路徑',
                    'Recommended aggressive optimization. Disable to use the original Next engine path.',
                  ),
                  icon: Ionicons.rocket_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.bolt,
                  value: labsSettings.enableNextPlusPlusEngine,
                  onChanged: labsSettings.setEnableNextPlusPlusEngine,
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
                  cupertinoIcon: cupertino.CupertinoIcons.cloud,
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
