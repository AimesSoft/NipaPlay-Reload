import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/external_player_console_window_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/external_player_utils.dart';
import 'package:nipaplay/utils/mpv_utils.dart';
import 'package:provider/provider.dart';

class ExternalPlayerSettingsContent extends StatelessWidget {
  const ExternalPlayerSettingsContent({super.key});

  /// 开启外部播放器后自动切换到弹幕控制台的开关
  static final Consumer<SettingsProvider> _autoSwitchToDanmakuConsoleTile =
      Consumer<SettingsProvider>(builder: (context, settingsProvider, child) {
    // 文字定义
    const String titleSimplified = '自动切换到弹幕控制台';
    const String titleTraditional = '自動切換到彈幕控制台';
    const String titleEnglish = 'Open Danmaku Console Automatically';
    const String subtitleSimplified = '开始外部播放后，主程序自动切换到弹幕控制台页面';
    const String subtitleTraditional = '開始外部播放後，主程式自動切換到彈幕控制台頁面';
    const String subtitleEnglish = 'Switch to the Danmaku Console after external playback starts.';
    const String subtitleUnsupportedSimplified = '弹幕控制台支持 mpv 和 Windows PotPlayer';
    const String subtitleUnsupportedTraditional = '彈幕控制台支援 mpv 和 Windows PotPlayer';
    const String subtitleUnsupportedEnglish = 'The Danmaku Console supports mpv and PotPlayer on Windows.';
    const String subtitleWindowModeSimplified = '独立窗口模式下，外部播放开始后会直接打开控制台窗口';
    const String subtitleWindowModeTraditional = '獨立視窗模式下，外部播放開始後會直接開啟控制台視窗';
    const String subtitleWindowModeEnglish =
        'Window mode opens the Danmaku Console window when external playback starts.';

    final consoleSupported = ExternalPlayerConsoleService.isSupportedPlatform;
    final windowMode = settingsProvider.externalPlayerConsoleWindowMode;
    return AdaptiveSettingsTile<bool>.toggle(
      title: _text(context, titleSimplified, titleTraditional, titleEnglish),
      subtitle: !consoleSupported
          ? _text(context, subtitleUnsupportedSimplified,
              subtitleUnsupportedTraditional, subtitleUnsupportedEnglish)
          : windowMode
              ? _text(
                  context,
                  subtitleWindowModeSimplified,
                  subtitleWindowModeTraditional,
                  subtitleWindowModeEnglish,
                )
              : _text(
                  context,
                  subtitleSimplified,
                  subtitleTraditional,
                  subtitleEnglish,
                ),
      icon: Ionicons.chatbox_ellipses_outline,
      phoneIcon: cupertino.CupertinoIcons.captions_bubble,
      enabled: consoleSupported && !windowMode,
      value: settingsProvider.externalPlayerAutoSwitchToDanmakuConsole,
      onChanged: (value) =>
          settingsProvider.setExternalPlayerAutoSwitchToDanmakuConsole(value),
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
                return AdaptiveSettingsTile<ExternalPlayerType>.dropdown(
                  title: _text(
                    context,
                    '播放器类型',
                    '播放器類型',
                    'Player Type',
                  ),
                  subtitle: _text(
                    context,
                    '请选择与可执行文件对应的播放器类型',
                    '請選擇與執行檔對應的播放器類型',
                    'Select the type that matches the executable.',
                  ),
                  icon: Ionicons.apps_outline,
                  phoneIcon: cupertino.CupertinoIcons.square_grid_2x2,
                  enabled: externalSupported,
                  items: _externalPlayerTypeItems(
                    context,
                    settingsProvider.externalPlayerType,
                  ),
                  onChanged: settingsProvider.setExternalPlayerType,
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
                          '在外部播放器中注入 ASS 弹幕（支持 mpv / mpv.net / Windows PotPlayer）',
                          '在外部播放器中注入 ASS 彈幕（支援 mpv / mpv.net / Windows PotPlayer）',
                          'Inject ASS danmaku in mpv, mpv.net, and PotPlayer on Windows.',
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
            _autoSwitchToDanmakuConsoleTile,
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                final consoleSupported =
                    ExternalPlayerConsoleWindowService.isSupported;
                return AdaptiveSettingsTile<bool>.toggle(
                  title: _text(
                    context,
                    '弹幕控制台使用独立窗口',
                    '彈幕控制台使用獨立視窗',
                    'Open Danmaku Console in Windows',
                  ),
                  subtitle: consoleSupported
                      ? _text(
                          context,
                          '不再显示控制台 Tab；左侧控制面板使用竖屏窗口，并可唤出单独的弹幕列表窗口',
                          '不再顯示控制台分頁；左側控制面板使用直向視窗，並可叫出獨立的彈幕列表視窗',
                          'Replace the console tab with a portrait controls window and an optional danmaku-list window.',
                        )
                      : _text(
                          context,
                          '独立控制台窗口目前仅支持 Linux 和 macOS',
                          '獨立控制台視窗目前僅支援 Linux 和 macOS',
                          'Console windows are currently available on Linux and macOS only.',
                        ),
                  icon: Ionicons.albums_outline,
                  phoneIcon: cupertino.CupertinoIcons.rectangle_on_rectangle,
                  enabled: consoleSupported,
                  value: settingsProvider.externalPlayerConsoleWindowMode,
                  onChanged: (value) async {
                    await settingsProvider
                        .setExternalPlayerConsoleWindowMode(value);
                    if (value &&
                        ExternalPlayerConsoleService.hasActiveSession) {
                      await ExternalPlayerConsoleWindowService.instance
                          .showControlsWindow();
                    } else if (!value) {
                      await ExternalPlayerConsoleWindowService.instance
                          .closeAll();
                    }
                  },
                );
              },
            ),
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return AdaptiveSettingsTile<bool>.toggle(
                  title: _text(
                    context,
                    '外部播放时缩小主窗口',
                    '外部播放時縮小主視窗',
                    'Resize Main Window During External Playback',
                  ),
                  subtitle: externalSupported
                      ? _text(
                          context,
                          '播放期间将 NipaPlay 缩至当前屏幕一半宽度，播放结束后自动恢复',
                          '播放期間將 NipaPlay 縮至目前螢幕一半寬度，播放結束後自動恢復',
                          'Resize NipaPlay to half of the current screen width during playback, then restore it automatically.',
                        )
                      : context.l10n.desktopOnlySupported,
                  icon: Ionicons.resize_outline,
                  phoneIcon:
                      cupertino.CupertinoIcons.rectangle_compress_vertical,
                  enabled: externalSupported,
                  value: settingsProvider.externalPlayerShrinkWindow,
                  onChanged: settingsProvider.setExternalPlayerShrinkWindow,
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
        final detected = await detectInstalledMpv();
        final picked = detected ??
            await FilePickerService().pickExternalPlayerExecutable();
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

        // 如果用户选择了一个新的播放器路径，尝试检测播放器类型并更新设置
        await settingsProvider.setExternalPlayerType(detectExternalPlayerType(picked));

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

  static List<DropdownMenuItemData<ExternalPlayerType>>
      _externalPlayerTypeItems(
    BuildContext context,
    ExternalPlayerType selectedType,
  ) {
    String title(ExternalPlayerType type) => switch (type) {
      ExternalPlayerType.mpv => 'mpv',
      ExternalPlayerType.mpvNet => 'mpv.net',
      ExternalPlayerType.potPlayer => 'PotPlayer',
      ExternalPlayerType.vlc => 'VLC',
      ExternalPlayerType.generic =>
        _text(context, '其他/通用', '其他/通用', 'Other / Generic'),
    };

    return ExternalPlayerType.values.map((type) {
      return DropdownMenuItemData<ExternalPlayerType>(
        title: title(type),
        value: type,
        isSelected: type == selectedType,
      );
    }).toList(growable: false);
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
    await settingsProvider.setExternalPlayerType(detectExternalPlayerType(picked));

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
