import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class ExternalPlayerSettingsContent extends StatelessWidget {
  const ExternalPlayerSettingsContent({super.key});

  /// 开启外部播放器后自动切换到弹幕控制台的开关
  static final Consumer<SettingsProvider> _autoSwitchToDanmakuConsoleTile =
  Consumer<SettingsProvider>(builder: (context, settingsProvider, child) {

    // 文字定义
    const String titleSimplified                = '自动切换到弹幕控制台';
    const String titleTraditional               = '自動切換到彈幕控制台';
    const String titleEnglish                   = 'Open Danmaku Console Automatically';
    const String subtitleSimplified             = '开始外部播放后，主程序自动切换到弹幕控制台页面';
    const String subtitleTraditional            = '開始外部播放後，主程式自動切換到彈幕控制台頁面';
    const String subtitleEnglish                = 'Switch to the Danmaku Console after external playback starts.';
    const String subtitleUnsupportedSimplified  = '弹幕控制台目前仅支持 Linux';
    const String subtitleUnsupportedTraditional = '彈幕控制台目前僅支援 Linux';
    const String subtitleUnsupportedEnglish     = 'The Danmaku Console is currently available on Linux only.';

    final consoleSupported = ExternalPlayerConsoleService.isSupportedPlatform;
    return AdaptiveSettingsTile<bool>.toggle(
      title    : _text(context, titleSimplified, titleTraditional, titleEnglish),
      subtitle : consoleSupported ? 
        _text(context, subtitleSimplified, subtitleTraditional, subtitleEnglish) :
        _text(context, subtitleUnsupportedSimplified, subtitleUnsupportedTraditional, subtitleUnsupportedEnglish),
      icon     : Ionicons.chatbox_ellipses_outline,
      phoneIcon: cupertino.CupertinoIcons.captions_bubble,
      enabled  : consoleSupported,
      value    : settingsProvider.externalPlayerAutoSwitchToDanmakuConsole,
      onChanged: (value) => settingsProvider.setExternalPlayerAutoSwitchToDanmakuConsole(value),
    );
  });

  @override
  Widget build(BuildContext context) {
    final externalSupported = globals.isDesktop;

    return AdaptiveSettingsPage(
      children: [
        AdaptiveSettingsSection(
          children: [
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return AdaptiveSettingsTile<bool>.toggle(
                  title: context.l10n.externalPlayerEnableTitle,
                  subtitle: externalSupported
                      ? context.l10n.externalPlayerEnableSubtitle
                      : context.l10n.desktopOnlySupported,
                  icon: Ionicons.play_outline,
                  phoneIcon: cupertino.CupertinoIcons.square_arrow_up,
                  enabled: externalSupported,
                  value: settingsProvider.useExternalPlayer,
                  onChanged: (value) => _toggleExternal(
                    context,
                    settingsProvider,
                    value,
                    externalSupported,
                  ),
                );
              },
            ),
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                final path = settingsProvider.externalPlayerPath.trim();
                final subtitle = !externalSupported
                    ? context.l10n.desktopOnlySupported
                    : (path.isEmpty
                        ? context.l10n.externalPlayerNotSelected
                        : path);

                return AdaptiveSettingsTile<void>.card(
                  title: context.l10n.externalPlayerSelectTitle,
                  subtitle: subtitle,
                  icon: Ionicons.folder_outline,
                  phoneIcon: cupertino.CupertinoIcons.folder,
                  enabled: externalSupported,
                  onTap: () => _selectExternalPlayer(
                    context,
                    settingsProvider,
                    externalSupported,
                  ),
                );
              },
            ),
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return AdaptiveSettingsTile<bool>.toggle(
                  title: _text(context, '弹幕外挂', '彈幕外掛', 'Danmaku Overlay'),
                  subtitle: externalSupported
                      ? _text(
                          context,
                          '在外部播放器中注入ASS形式的弹幕作为次字幕（支持 mpv / mpv.net / PotPlayer）',
                          '在外部播放器中注入 ASS 形式的彈幕作為次字幕（支援 mpv / mpv.net / PotPlayer）',
                          'Inject danmaku as an ASS secondary subtitle in external players (mpv, mpv.net, PotPlayer).',
                        )
                      : context.l10n.desktopOnlySupported,
                  icon: Ionicons.chatbubbles_outline,
                  phoneIcon: cupertino.CupertinoIcons.chat_bubble,
                  enabled: externalSupported,
                  value: settingsProvider.externalPlayerDanmakuOverlay,
                  onChanged: (value) => _toggleDanmakuOverlay(
                    context,
                    settingsProvider,
                    value,
                    externalSupported,
                  ),
                );
              },
            ),
            _autoSwitchToDanmakuConsoleTile
          ],
        ),
      ],
    );
  }

  Future<void> _toggleExternal(
    BuildContext context,
    SettingsProvider settingsProvider,
    bool value,
    bool externalSupported,
  ) async {
    if (!externalSupported) return;
    final l10n = context.l10n;

    if (value) {
      if (settingsProvider.externalPlayerPath.trim().isEmpty) {
        final picked = await FilePickerService().pickExternalPlayerExecutable();
        if (picked == null || picked.trim().isEmpty) {
          if (!context.mounted) return;
          AdaptiveSnackBar.show(
            context,
            message: l10n.externalPlayerSelectionCanceled,
            type: AdaptiveSnackBarType.info,
          );
          await settingsProvider.setUseExternalPlayer(false);
          return;
        }
        await settingsProvider.setExternalPlayerPath(picked);
      }
      await settingsProvider.setUseExternalPlayer(true);
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.externalPlayerEnabled,
        type: AdaptiveSnackBarType.success,
      );
      return;
    }

    await settingsProvider.setUseExternalPlayer(false);
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: l10n.externalPlayerDisabled,
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _selectExternalPlayer(
    BuildContext context,
    SettingsProvider settingsProvider,
    bool externalSupported,
  ) async {
    if (!externalSupported) return;
    final l10n = context.l10n;
    final picked = await FilePickerService().pickExternalPlayerExecutable();
    if (picked == null || picked.trim().isEmpty) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: l10n.externalPlayerSelectionCanceled,
        type: AdaptiveSnackBarType.info,
      );
      return;
    }

    await settingsProvider.setExternalPlayerPath(picked);
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: l10n.externalPlayerUpdated,
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _toggleDanmakuOverlay(
    BuildContext context,
    SettingsProvider settingsProvider,
    bool value,
    bool externalSupported,
  ) async {
    if (!externalSupported) return;
    await settingsProvider.setExternalPlayerDanmakuOverlay(value);
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: value
          ? _text(context, '已启用弹幕外挂', '已啟用彈幕外掛', 'Danmaku overlay enabled.')
          : _text(context, '已关闭弹幕外挂', '已關閉彈幕外掛', 'Danmaku overlay disabled.'),
      type: AdaptiveSnackBarType.success,
    );
  }

  static String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') {
      return english;
    }
    if (locale == 'zh_Hant') {
      return traditional;
    }
    return simplified;
  }
}
