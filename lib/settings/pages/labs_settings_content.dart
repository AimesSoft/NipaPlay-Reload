import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/next_runtime.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/services/folder_opener.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
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
                if (!globals.isTelevision)
                  AdaptiveSettingsTile.toggle(
                    title: _text(
                      context,
                      '新版番剧卡片页面',
                      '新版番劇卡片頁面',
                      'New Anime Detail Page',
                    ),
                    subtitle: _text(
                      context,
                      '开启后，桌面、平板和手机均使用新版全屏番剧详情页',
                      '開啟後，桌面、平板和手機均使用新版全螢幕番劇詳情頁',
                      'Use the new full-screen anime detail page on desktop, tablet, and phone.',
                    ),
                    icon: Ionicons.albums_outline,
                    phoneIcon: cupertino.CupertinoIcons.rectangle_stack,
                    value: labsSettings.enableImmersiveAnimeDetail,
                    onChanged: labsSettings.setEnableImmersiveAnimeDetail,
                  ),
                if (PlayerFactory.isErikaKernelSupported &&
                    !globals.isTelevision)
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
            if (globals.isDesktop)
              Consumer<NextRuntime>(
                builder: (context, runtime, child) {
                  final status = runtime.endpointStatus;
                  var subtitle = _text(
                    context,
                    '在本机开放 MCP 接口，可在 Codex 中用对话操作 NipaPlay',
                    '在本機開放 MCP 介面，可在 Codex 中用對話操作 NipaPlay',
                    'Expose a local MCP endpoint to control NipaPlay through conversation in Codex.',
                  );
                  if (labsSettings.enableAgentEndpoint) {
                    final trustHint = _text(
                      context,
                      '在 Codex 中添加此文件夹为项目并选择信任',
                      '在 Codex 中新增此資料夾為專案並選擇信任',
                      'Add this folder as a project in Codex and choose to trust it.',
                    );
                    final statusText = switch (status) {
                      AgentEndpointRunning(:final url, :final workspace) =>
                        '$url\n${workspace.path}\n$trustHint',
                      AgentEndpointFailed(:final message) => message,
                      AgentEndpointStopped() => _text(
                          context,
                          '正在启动…',
                          '正在啟動…',
                          'Starting…',
                        ),
                    };
                    subtitle = '$subtitle\n$statusText';
                  }
                  return AdaptiveSettingsSection(
                    children: [
                      AdaptiveSettingsTile.toggle(
                        title: _text(
                          context,
                          'Agent 接口（NipaPlay Next）',
                          'Agent 介面（NipaPlay Next）',
                          'Agent Endpoint (NipaPlay Next)',
                        ),
                        subtitle: subtitle,
                        icon: Ionicons.flask_outline,
                        phoneIcon: cupertino.CupertinoIcons.lab_flask,
                        value: labsSettings.enableAgentEndpoint,
                        onChanged: labsSettings.setEnableAgentEndpoint,
                      ),
                      if (labsSettings.enableAgentEndpoint)
                        if (status case AgentEndpointRunning(:final workspace))
                          AdaptiveSettingsTile.button(
                            title: _text(
                              context,
                              '打开工作区文件夹',
                              '開啟工作區資料夾',
                              'Open Workspace Folder',
                            ),
                            icon: Ionicons.folder_outline,
                            phoneIcon: cupertino.CupertinoIcons.folder,
                            onTap: () => FolderOpener.open(workspace.path),
                          ),
                    ],
                  );
                },
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
