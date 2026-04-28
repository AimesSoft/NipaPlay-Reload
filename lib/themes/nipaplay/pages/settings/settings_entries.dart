import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/pages/shortcuts_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/about_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/backup_restore_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/danmaku_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/developer_options_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/external_player_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/general_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/language_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/network_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/player_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/remote_access_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/remote_media_library_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/storage_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/theme_mode_page.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

class NipaplaySettingEntryIds {
  const NipaplaySettingEntryIds._();

  static const String appearance = 'appearance';
  static const String language = 'language';
  static const String general = 'general';
  static const String storage = 'storage';
  static const String network = 'network';
  static const String backupRestore = 'backup_restore';
  static const String player = 'player';
  static const String danmaku = 'danmaku';
  static const String externalPlayer = 'external_player';
  static const String shortcuts = 'shortcuts';
  static const String remoteAccess = 'remote_access';
  static const String remoteMediaLibrary = 'remote_media_library';
  static const String developerOptions = 'developer_options';
  static const String about = 'about';
}

class NipaplaySettingEntry {
  const NipaplaySettingEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.pageTitle,
    required this.page,
  });

  final String id;
  final String title;
  final IconData icon;
  final String pageTitle;
  final Widget page;
}

List<NipaplaySettingEntry> buildNipaplaySettingEntries(BuildContext context) {
  final themeNotifier = context.read<ThemeNotifier>();
  final l10n = context.l10n;
  final entries = <NipaplaySettingEntry>[
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.appearance,
      title: l10n.appearance,
      icon: Ionicons.color_palette_outline,
      pageTitle: l10n.appearanceSettings,
      page: ThemeModePage(themeNotifier: themeNotifier),
    ),
  ];

  entries.addAll([
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.language,
      title: l10n.language,
      icon: Ionicons.language_outline,
      pageTitle: l10n.languageSettingsTitle,
      page: const LanguagePage(),
    ),
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.general,
      title: l10n.general,
      icon: Ionicons.settings_outline,
      pageTitle: l10n.generalSettings,
      page: const GeneralPage(),
    ),
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.storage,
      title: l10n.storage,
      icon: Ionicons.folder_open_outline,
      pageTitle: l10n.storageSettings,
      page: const StoragePage(),
    ),
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.network,
      title: l10n.networkSettings,
      icon: Ionicons.wifi_outline,
      pageTitle: l10n.networkSettings,
      page: const NetworkSettingsPage(),
    ),
  ]);

  if (!globals.isPhone) {
    entries.add(
      NipaplaySettingEntry(
        id: NipaplaySettingEntryIds.backupRestore,
        title: l10n.backupAndRestore,
        icon: Ionicons.cloud_upload_outline,
        pageTitle: l10n.backupAndRestore,
        page: const BackupRestorePage(),
      ),
    );
  }

  entries.add(
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.player,
      title: l10n.player,
      icon: Ionicons.play_circle_outline,
      pageTitle: l10n.playerSettings,
      page: const PlayerSettingsPage(),
    ),
  );

  entries.add(
    const NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.danmaku,
      title: '弹幕',
      icon: Ionicons.hardware_chip_outline,
      pageTitle: '弹幕设置',
      page: DanmakuSettingsPage(),
    ),
  );

  entries.add(
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.externalPlayer,
      title: l10n.externalCall,
      icon: Ionicons.open_outline,
      pageTitle: l10n.externalCall,
      page: const ExternalPlayerSettingsPage(),
    ),
  );

  if (!globals.isPhone) {
    entries.addAll([
      NipaplaySettingEntry(
        id: NipaplaySettingEntryIds.shortcuts,
        title: l10n.shortcuts,
        icon: Ionicons.key_outline,
        pageTitle: l10n.shortcutsSettings,
        page: const ShortcutsSettingsPage(),
      ),
      NipaplaySettingEntry(
        id: NipaplaySettingEntryIds.remoteAccess,
        title: l10n.remoteAccess,
        icon: Ionicons.link_outline,
        pageTitle: l10n.remoteAccess,
        page: const RemoteAccessPage(),
      ),
    ]);
  }

  entries.addAll([
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.remoteMediaLibrary,
      title: l10n.remoteMediaLibrary,
      icon: Ionicons.library_outline,
      pageTitle: l10n.remoteMediaLibrary,
      page: const RemoteMediaLibraryPage(),
    ),
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.developerOptions,
      title: l10n.developerOptions,
      icon: Ionicons.code_slash_outline,
      pageTitle: l10n.developerOptions,
      page: const DeveloperOptionsPage(),
    ),
    NipaplaySettingEntry(
      id: NipaplaySettingEntryIds.about,
      title: l10n.about,
      icon: Ionicons.information_circle_outline,
      pageTitle: l10n.about,
      page: const AboutPage(),
    ),
  ]);

  return entries;
}
