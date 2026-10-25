import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class LabsSettingsContent extends StatelessWidget {
  const LabsSettingsContent({
    super.key,
    required this.onOpenWebDavQuickSettings,
  });

  final VoidCallback onOpenWebDavQuickSettings;

  /// Which kind of device this is for NipaPlay Next: a desktop runs Nipa, an
  /// iPad or an iPhone only hosts Next's interface and body. Android has no
  /// Next. Tests set it.
  @visibleForTesting
  static ({bool desktop, bool iPad, bool iPhone}) Function() device = () => (
        desktop: globals.isDesktop,
        iPad: globals.isIPad,
        iPhone: !kIsWeb && Platform.isIOS && !globals.isTvOS && !globals.isIPad,
      );

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
            // The way into NipaPlay Next, and nothing of it: Nipa, her
            // endpoint and her settings live in Next's own interface and run
            // only while it is open (D1). An iPad gets Next's interface and
            // body; so does an iPhone. Nipa runs on the user's other devices.
            if (device().desktop || device().iPad || device().iPhone)
              AdaptiveSettingsSection(
                children: [
                  AdaptiveSettingsTile.toggle(
                    title: 'NipaPlay Next',
                    subtitle: labsSettings.isLoaded &&
                            !labsSettings.nextAvailable
                        ? _text(
                            context,
                            '此 macOS 应用处于 App Sandbox 中，无法提供 NipaPlay Next。请使用 GitHub 完整版。',
                            '此 macOS 應用處於 App Sandbox 中，無法提供 NipaPlay Next。請使用 GitHub 完整版。',
                            'This macOS app runs in App Sandbox. NipaPlay Next requires the full GitHub release.')
                        : _text(context, '全新的界面（实验）', '全新的介面（實驗）',
                            'A new interface (experimental).'),
                    icon: Ionicons.flask_outline,
                    phoneIcon: cupertino.CupertinoIcons.lab_flask,
                    value: labsSettings.enableAgentEndpoint,
                    enabled: labsSettings.nextAvailable,
                    onChanged: (enabled) async {
                      if (enabled) {
                        final confirmed = await _confirmNext(context);
                        if (!confirmed || !context.mounted) return;
                      }
                      await labsSettings.setEnableAgentEndpoint(enabled);
                    },
                  ),
                  if (labsSettings.enableAgentEndpoint)
                    AdaptiveSettingsTile.toggle(
                      title: _text(context, '使用 Next 界面', '使用 Next 介面',
                          'Use the Next Interface'),
                      subtitle: _text(
                        context,
                        '用 Next 的首页替换主界面，可随时回到经典界面',
                        '用 Next 的首頁取代主介面，可隨時回到經典介面',
                        'Replace the main interface with Next. You can switch back at any time.',
                      ),
                      icon: Ionicons.sparkles_outline,
                      phoneIcon: cupertino.CupertinoIcons.sparkles,
                      value: context.watch<NextUiPreference>().enabled,
                      onChanged: context.read<NextUiPreference>().setEnabled,
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  /// An iPad or an iPhone does not run Nipa: the Nipa on the user's other
  /// devices (same account, same local network) can operate NipaPlay here.
  String _mobileConsent(BuildContext context, {required bool phone}) {
    final name = phone ? 'iPhone' : 'iPad';
    return _text(
        context,
        '开启后，你同一账号下其他设备上的 AI Agent 可以在同一局域网内操作这台 $name 上的 NipaPlay：播放、改设置、读片库和观看记录、截取 NipaPlay 的画面。删除文件、登录账号仍要你在这台 $name 上亲手确认。\n\n'
            'Agent 会犯错，也可能被网页、文件名、简介里的恶意内容误导，做出你没有要求的事。\n\n'
            '你在这里的对话以及 Agent 读到的内容，会发送给那台设备所选的模型服务商。\n\n'
            '这是实验功能，行为和数据随时可能变化，不保证兼容。\n\n'
            '只在你信任的设备和模型服务上开启。',
        '開啟後，你同一帳號下其他裝置上的 AI Agent 可以在同一區域網路內操作這台 $name 上的 NipaPlay：播放、改設定、讀片庫和觀看紀錄、擷取 NipaPlay 的畫面。刪除檔案、登入帳號仍要你在這台 $name 上親手確認。\n\n'
            'Agent 會犯錯，也可能被網頁、檔案名稱、簡介裡的惡意內容誤導，做出你沒有要求的事。\n\n'
            '你在這裡的對話以及 Agent 讀到的內容，會傳送給那台裝置所選的模型服務商。\n\n'
            '這是實驗功能，行為和資料隨時可能變化，不保證相容。\n\n'
            '只在你信任的裝置和模型服務上開啟。',
        'Once enabled, the AI Agent on your other devices signed in to the same account can operate NipaPlay on this $name over the local network: play, change settings, read the library and watch history, and capture NipaPlay\'s screen. Deleting files and signing in to accounts still need you to confirm on this $name.\n\n'
            'The Agent makes mistakes and may be misled by malicious content in webpages, filenames or descriptions into doing things you did not request.\n\n'
            'Your conversations here and the content the Agent reads will be sent to the model provider chosen on that device.\n\n'
            'This is an experimental feature. Its behavior and data may change at any time, with no guarantee of compatibility.\n\n'
            'Enable it only on devices and a model service you trust.',
      );
  }

  Future<bool> _confirmNext(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_text(context, '开启 NipaPlay Next（实验）',
              '開啟 NipaPlay Next（實驗）', 'Enable NipaPlay Next (Experimental)')),
          content: SingleChildScrollView(
            child: Text(
              device().iPad || device().iPhone
                  ? _mobileConsent(context, phone: device().iPhone)
                  : _text(
                      context,
                      '开启后，AI Agent 将以你的身份使用这台电脑：读写和删除文件、联网、运行程序、使用你浏览器中各网站的登录状态。\n\n'
                          'Agent 会犯错，也可能被网页、文件名、简介里的恶意内容误导，做出你没有要求的事。\n\n'
                          '你的对话以及 Agent 读到的内容，会发送给你所选的模型服务商。\n\n'
                          '这是实验功能，行为和数据随时可能变化，不保证兼容。\n\n'
                          '只在你信任的电脑和模型服务上开启。',
                      '開啟後，AI Agent 將以你的身分使用這台電腦：讀寫和刪除檔案、連網、執行程式、使用你瀏覽器中各網站的登入狀態。\n\n'
                          'Agent 會犯錯，也可能被網頁、檔案名稱、簡介裡的惡意內容誤導，做出你沒有要求的事。\n\n'
                          '你的對話以及 Agent 讀到的內容，會傳送給你所選的模型服務商。\n\n'
                          '這是實驗功能，行為和資料隨時可能變化，不保證相容。\n\n'
                          '只在你信任的電腦和模型服務上開啟。',
                      'Once enabled, the AI Agent will use this computer as you: read, write and delete files, access the network, run programs, and use your signed-in sessions on websites in your browser.\n\n'
                          'The Agent makes mistakes and may be misled by malicious content in webpages, filenames or descriptions into doing things you did not request.\n\n'
                          'Your conversations and the content the Agent reads will be sent to your chosen model provider.\n\n'
                          'This is an experimental feature. Its behavior and data may change at any time, with no guarantee of compatibility.\n\n'
                          'Enable it only on a computer and model service you trust.',
                    ),
              style: const TextStyle(color: Colors.red),
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_text(context, '取消', '取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_text(context, '我了解风险，开启', '我了解風險，開啟',
                  'I understand the risks, enable')),
            ),
          ],
        ),
      ) ??
      false;

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
