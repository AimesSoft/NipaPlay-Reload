import 'package:flutter/widgets.dart';
import 'package:nipaplay/pages/shortcuts_settings_page.dart';
import 'package:nipaplay/settings/adaptive_settings_navigation.dart';
import 'package:nipaplay/settings/pages/about_settings_content.dart';
import 'package:nipaplay/settings/pages/appearance_settings_content.dart';
import 'package:nipaplay/settings/pages/danmaku_settings_content.dart';
import 'package:nipaplay/settings/pages/developer_options_settings_content.dart';
import 'package:nipaplay/settings/pages/downloader_settings_content.dart';
import 'package:nipaplay/settings/pages/external_player_settings_content.dart';
import 'package:nipaplay/settings/pages/general_settings_content.dart';
import 'package:nipaplay/settings/pages/labs_settings_content.dart';
import 'package:nipaplay/settings/pages/language_settings_content.dart';
import 'package:nipaplay/settings/pages/network_settings_content.dart';
import 'package:nipaplay/settings/pages/player_settings_content.dart';
import 'package:nipaplay/settings/pages/plugin_settings_content.dart';
import 'package:nipaplay/settings/pages/remote_media_library_settings_content.dart';
import 'package:nipaplay/settings/pages/storage_settings_content.dart';
import 'package:nipaplay/settings/pages/webdav_quick_settings_content.dart';
import 'package:nipaplay/settings/unified_setting_content_type.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/backup_restore_page.dart';

class UnifiedSettingContent extends StatelessWidget {
  const UnifiedSettingContent({
    super.key,
    required this.type,
  });

  final UnifiedSettingContentType type;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      UnifiedSettingContentType.appearance => const AppearanceSettingsContent(),
      UnifiedSettingContentType.language => const LanguageSettingsContent(),
      UnifiedSettingContentType.general => const GeneralSettingsContent(),
      UnifiedSettingContentType.storage => const StorageSettingsContent(),
      UnifiedSettingContentType.network => const NetworkSettingsContent(),
      UnifiedSettingContentType.backupRestore => const BackupRestorePage(),
      UnifiedSettingContentType.player => const PlayerSettingsContent(),
      UnifiedSettingContentType.danmaku => const DanmakuSettingsContent(),
      UnifiedSettingContentType.externalPlayer =>
        const ExternalPlayerSettingsContent(),
      UnifiedSettingContentType.shortcuts => const ShortcutsSettingsPage(),
      UnifiedSettingContentType.remoteAccess =>
        const UnifiedRemoteAccessSettingsContent(),
      UnifiedSettingContentType.remoteMediaLibrary =>
        const RemoteMediaLibrarySettingsContent(),
      UnifiedSettingContentType.downloader => const DownloaderSettingsContent(),
      UnifiedSettingContentType.developerOptions =>
        const DeveloperOptionsSettingsContent(),
      UnifiedSettingContentType.labs => LabsSettingsContent(
          onOpenWebDavQuickSettings: () {
            AdaptiveSettingsNavigation.openChildPage<void>(
              context,
              title: 'WebDAV快捷设置',
              child: const WebDAVQuickSettingsContent(),
            );
          },
        ),
      UnifiedSettingContentType.plugins => const PluginSettingsContent(),
      UnifiedSettingContentType.about => const AboutSettingsContent(),
    };
  }
}
