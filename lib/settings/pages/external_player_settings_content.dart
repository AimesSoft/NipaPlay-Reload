import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class ExternalPlayerSettingsContent extends StatelessWidget {
  const ExternalPlayerSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    final externalSupported = globals.isDesktop;

    return AdaptiveSettingsPage(
      title: context.l10n.externalCall,
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

  String _text(
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
