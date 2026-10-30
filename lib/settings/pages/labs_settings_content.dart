import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/widgets/in_view_dialog.dart';

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
                        : _text(
                            context,
                            '梨花驱动的媒体库、独立播放器与 Mesh（开发者预览）',
                            '梨花驅動的媒體庫、獨立播放器與 Mesh（開發者預覽）',
                            'An Agent-driven media library, independent player, and Mesh (Developer Preview).'),
                    icon: Ionicons.flask_outline,
                    phoneIcon: cupertino.CupertinoIcons.lab_flask,
                    value: labsSettings.enableAgentEndpoint &&
                        context.watch<NextUiPreference>().enabled,
                    enabled: labsSettings.nextAvailable,
                    onChanged: (enabled) =>
                        _setNextEnabled(context, labsSettings, enabled),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Future<void> _setNextEnabled(
      BuildContext context, LabsSettingsProvider labs, bool enabled) async {
    // Switching interfaces can dispose Classic and this settings page. Capture
    // the root navigator and both owners before the first asynchronous write.
    final navigator = Navigator.of(context, rootNavigator: true);
    final preference = context.read<NextUiPreference>();
    if (enabled && !labs.enableAgentEndpoint) {
      final confirmed = await _confirmNext(context);
      if (!confirmed || !context.mounted) return;
    }
    // Prepare the interface before enabling its host so first-time entry does
    // not briefly start Classic's background work between the two settings.
    await preference.setEnabled(enabled);
    await labs.setEnableAgentEndpoint(enabled);
    if (enabled && navigator.mounted) {
      // Settings may be a root popup or a sheet with its own navigator. Closing
      // only the consent or inner Labs page leaves that popup covering Next.
      navigator.popUntil((route) => route.isFirst);
    }
  }

  String _sharedConsent(BuildContext context) => _text(
        context,
        'Agent 会犯错，软件也可能存在缺陷；网页、文件名、字幕和简介等外部内容中的恶意指令可能误导它，造成数据丢失、文件损坏、隐私或凭据泄露、账号操作和额外费用。\n\n'
            '任务所需的对话、文件内容和工具结果会发送给所选的模型服务商，适用该服务商的数据政策。\n\n'
            '这是高风险的开发者预览，功能和数据格式可能变化，不保证兼容。请使用隔离的测试设备、系统账号和数据副本，保留离线备份；不要在存放唯一重要数据或关键业务的环境中试用，只加入可信的 Mesh 设备。\n\n'
            '免责声明：本软件依 MIT 许可证按“现状”提供。在适用法律允许的范围内，AimesSoft、作者及贡献者不提供明示或默示担保，也不对数据、隐私、账号、费用或其他使用损失承担责任。你自行决定是否启用 Agent、授予权限和连接服务，并承担相应风险；本声明不排除依法不得排除或限制的责任。',
        'Agent 會犯錯，軟體也可能存在缺陷；網頁、檔案名稱、字幕和簡介等外部內容中的惡意指令可能誤導它，造成資料遺失、檔案損壞、隱私或憑證洩漏、帳號操作和額外費用。\n\n'
            '任務所需的對話、檔案內容和工具結果會傳送給所選的模型服務商，適用該服務商的資料政策。\n\n'
            '這是高風險的開發者預覽，功能和資料格式可能變更，不保證相容。請使用隔離的測試裝置、系統帳號和資料副本，保留離線備份；不要在存放唯一重要資料或關鍵業務的環境中試用，只加入可信的 Mesh 裝置。\n\n'
            '免責聲明：本軟體依 MIT 授權條款按「現狀」提供。在適用法律允許的範圍內，AimesSoft、作者及貢獻者不提供明示或默示擔保，也不對資料、隱私、帳號、費用或其他使用損失承擔責任。你自行決定是否啟用 Agent、授予權限和連接服務，並承擔相應風險；本聲明不排除依法不得排除或限制的責任。',
        'The Agent can make mistakes, and the software may contain defects. Malicious instructions in webpages, filenames, subtitles, or descriptions can mislead it and cause data loss, file corruption, privacy or credential leaks, account actions, and additional charges.\n\n'
            'Conversations, file contents, and tool results needed for a task are sent to the selected model provider and are subject to its data policies.\n\n'
            'This is a high-risk Developer Preview. Features and data formats may change without compatibility guarantees. Use isolated test devices, system accounts, and copies of data; keep offline backups. Do not try it in environments containing your only copy of important data or critical work. Join only trusted Mesh devices.\n\n'
            'Disclaimer: this software is provided “as is” under the MIT License. To the extent permitted by applicable law, AimesSoft, the authors, and contributors provide no express or implied warranties and accept no liability for losses involving data, privacy, accounts, charges, or other use of the software. You decide whether to enable the Agent, grant permissions, and connect services, and assume the associated risks. This notice does not exclude or limit liability that cannot legally be excluded or limited.',
      );

  /// Mobile hosts Next and Mesh; Nipa runs on another authenticated device.
  String _mobileConsent(BuildContext context, {required bool phone}) {
    final name = phone ? 'iPhone' : 'iPad';
    return _text(
          context,
          '这台 $name 运行 Next 界面、播放器和 Mesh，梨花在你同一账号下的其他设备上运行。其他设备上的 AI Agent 可以通过 Mesh 操作这台 $name 上的 NipaPlay：播放、改设置、读片库和观看记录、截取 NipaPlay 的画面。访问范围受这台设备开放的能力与系统权限限制。\n\n'
              '运行梨花的电脑可在其当前用户权限范围内读写和删除文件、运行程序、联网及使用可访问的登录状态。Mesh 将风险延伸到已连接设备；同一局域网和设备认证不能防止受信任的 Agent 出错。不要假定所有操作都会再次弹窗确认。\n\n',
          '這台 $name 執行 Next 介面、播放器和 Mesh，梨花在你同一帳號下的其他裝置上執行。其他裝置上的 AI Agent 可以透過 Mesh 操作這台 $name 上的 NipaPlay：播放、改設定、讀片庫和觀看紀錄、擷取 NipaPlay 的畫面。存取範圍受這台裝置開放的能力與系統權限限制。\n\n'
              '執行梨花的電腦可在其目前使用者權限範圍內讀寫和刪除檔案、執行程式、連網及使用可存取的登入狀態。Mesh 將風險延伸到已連接裝置；同一區域網路和裝置驗證不能防止受信任的 Agent 出錯。不要假定所有操作都會再次彈窗確認。\n\n',
          'This $name runs the Next interface, player, and Mesh. Nipa runs on your other devices signed in to the same account. The AI Agent on those devices can operate NipaPlay on this $name through Mesh: play, change settings, read the library and watch history, and capture NipaPlay\'s screen. Access is limited by the capabilities enabled here and this device\'s system permissions.\n\n'
              'The computer running Nipa can read, write, and delete files, run programs, access the network, and use accessible signed-in sessions within its current user permissions. Mesh extends these risks to connected devices. A local network and device authentication do not prevent a trusted Agent from making mistakes. Do not assume every operation will ask for confirmation again.\n\n',
        ) +
        _sharedConsent(context);
  }

  Future<bool> _confirmNext(BuildContext context) async =>
      await showInViewDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_text(
              context,
              '开启 NipaPlay Next（开发者预览）',
              '開啟 NipaPlay Next（開發者預覽）',
              'Enable NipaPlay Next (Developer Preview)')),
          content: SingleChildScrollView(
            child: Text(
              device().iPad || device().iPhone
                  ? _mobileConsent(context, phone: device().iPhone)
                  : _text(
                        context,
                        '完整权限 Agent：梨花将在应用进程和当前系统用户拥有的权限范围内使用这台电脑，读写、覆盖或删除文件、运行程序、联网，并使用可访问的账号和浏览器登录状态。操作范围可以超出媒体库，不要假定每一步都会再次弹窗确认。\n\n'
                            'Mesh 会将风险延伸到其他设备：同账号认证设备可以调用本机开放的能力、读取可访问的文件；启用远程程序运行后，其他设备上的 Agent 还可以在本机执行程序。同一局域网并不意味着安全，设备认证不能防止受信任的 Agent 出错。\n\n',
                        '完整權限 Agent：梨花將在應用程式處理程序和目前系統使用者擁有的權限範圍內使用這台電腦，讀寫、覆寫或刪除檔案、執行程式、連網，並使用可存取的帳號和瀏覽器登入狀態。操作範圍可以超出媒體庫，不要假定每一步都會再次彈窗確認。\n\n'
                            'Mesh 會將風險延伸到其他裝置：同帳號驗證裝置可以呼叫本機開放的能力、讀取可存取的檔案；啟用遠端程式執行後，其他裝置上的 Agent 還可以在本機執行程式。同一區域網路並不意味著安全，裝置驗證不能防止受信任的 Agent 出錯。\n\n',
                        'Full-permission Agent: Nipa will use this computer within the permissions of the application process and your current system user. It can read, overwrite, or delete files, run programs, access the network, and use accessible accounts and browser sign-ins. Its operations can extend beyond the media library. Do not assume every step will ask for confirmation again.\n\n'
                            'Mesh extends these risks to other devices. Authenticated devices on the same account can invoke capabilities enabled here and read accessible files. If remote program execution is enabled, Agents on other devices can also run programs on this computer. A local network does not imply safety, and device authentication does not prevent a trusted Agent from making mistakes.\n\n',
                      ) +
                      _sharedConsent(context),
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
