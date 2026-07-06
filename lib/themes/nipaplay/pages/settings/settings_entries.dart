import 'package:flutter/material.dart';
import 'package:nipaplay/settings/unified_settings_entries.dart';

class NipaplaySettingEntryIds {
  const NipaplaySettingEntryIds._();

  static const String appearance = UnifiedSettingEntryIds.appearance;
  static const String language = UnifiedSettingEntryIds.language;
  static const String general = UnifiedSettingEntryIds.general;
  static const String storage = UnifiedSettingEntryIds.storage;
  static const String network = UnifiedSettingEntryIds.network;
  static const String backupRestore = UnifiedSettingEntryIds.backupRestore;
  static const String player = UnifiedSettingEntryIds.player;
  static const String danmaku = UnifiedSettingEntryIds.danmaku;
  static const String externalPlayer = UnifiedSettingEntryIds.externalPlayer;
  static const String shortcuts = UnifiedSettingEntryIds.shortcuts;
  static const String remoteAccess = UnifiedSettingEntryIds.remoteAccess;
  static const String remoteMediaLibrary =
      UnifiedSettingEntryIds.remoteMediaLibrary;
  static const String downloader = UnifiedSettingEntryIds.downloader;
  static const String developerOptions =
      UnifiedSettingEntryIds.developerOptions;
  static const String labs = UnifiedSettingEntryIds.labs;
  static const String plugins = UnifiedSettingEntryIds.plugins;
  static const String about = UnifiedSettingEntryIds.about;
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
  final entries = buildUnifiedSettingEntries(
    context,
    surface: UnifiedSettingsSurface.nipaplay,
  );

  return entries
      .map(
        (entry) => NipaplaySettingEntry(
          id: entry.id,
          title: entry.title(context, UnifiedSettingsSurface.nipaplay),
          icon: entry.icon,
          pageTitle: entry.pageTitle(context, UnifiedSettingsSurface.nipaplay),
          page: entry.buildPage(context, UnifiedSettingsSurface.nipaplay),
        ),
      )
      .toList();
}
