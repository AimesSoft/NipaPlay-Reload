import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/common_setting_tiles.dart';
import 'package:nipaplay/settings/unified_setting_content.dart';
import 'package:nipaplay/settings/unified_setting_content_type.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

enum UnifiedSettingsSurface {
  desktopTablet,
  phone,
}

enum UnifiedSettingSection {
  general,
  labs,
  about,
}

enum UnifiedSettingInlineControlType {
  autoUpdate,
}

enum UnifiedSettingSubtitleType {
  packageVersion,
}

class UnifiedSettingEntryIds {
  const UnifiedSettingEntryIds._();

  static const String appearance = 'appearance';
  static const String language = 'language';
  static const String general = 'general';
  static const String updateCheck = 'update_check';
  static const String storage = 'storage';
  static const String network = 'network';
  static const String backupRestore = 'backup_restore';
  static const String player = 'player';
  static const String danmaku = 'danmaku';
  static const String externalPlayer = 'external_player';
  static const String shortcuts = 'shortcuts';
  static const String remoteAccess = 'remote_access';
  static const String remoteMediaLibrary = 'remote_media_library';
  static const String downloader = 'downloader';
  static const String developerOptions = 'developer_options';
  static const String labs = 'labs';
  static const String plugins = 'plugins';
  static const String about = 'about';
}

typedef UnifiedSettingTextBuilder = String Function(
  material.BuildContext context,
  UnifiedSettingsSurface surface,
);
typedef UnifiedSettingVisibleBuilder = bool Function(
  material.BuildContext context,
  UnifiedSettingsSurface surface,
);

class UnifiedSettingEntry {
  const UnifiedSettingEntry({
    required this.id,
    required this.section,
    required this.titleBuilder,
    required this.pageTitleBuilder,
    required this.icon,
    this.phoneIcon,
    this.subtitleBuilder,
    this.subtitleType,
    this.contentType,
    this.inlineControlType,
    this.visible,
  });

  final String id;
  final UnifiedSettingSection section;
  final UnifiedSettingTextBuilder titleBuilder;
  final UnifiedSettingTextBuilder pageTitleBuilder;
  final material.IconData icon;
  final material.IconData? phoneIcon;
  final UnifiedSettingTextBuilder? subtitleBuilder;
  final UnifiedSettingSubtitleType? subtitleType;
  final UnifiedSettingContentType? contentType;
  final UnifiedSettingInlineControlType? inlineControlType;
  final UnifiedSettingVisibleBuilder? visible;

  String title(material.BuildContext context, UnifiedSettingsSurface surface) {
    return titleBuilder(context, surface);
  }

  String pageTitle(
    material.BuildContext context,
    UnifiedSettingsSurface surface,
  ) {
    return pageTitleBuilder(context, surface);
  }

  bool isVisible(
    material.BuildContext context,
    UnifiedSettingsSurface surface,
  ) {
    if (visible?.call(context, surface) == false) {
      return false;
    }
    return contentType != null || inlineControlType != null;
  }

  material.Widget buildPage(
    material.BuildContext context,
    UnifiedSettingsSurface surface,
  ) {
    final type = contentType;
    if (type == null) {
      return const material.SizedBox.shrink();
    }

    return AdaptiveSettingsScope(
      style: surface == UnifiedSettingsSurface.phone
          ? AdaptiveSettingsStyle.phone
          : AdaptiveSettingsStyle.desktopTablet,
      child: UnifiedSettingContent(type: type),
    );
  }

  material.Widget? subtitleWidget(
    material.BuildContext context,
    UnifiedSettingsSurface surface,
  ) {
    switch (subtitleType) {
      case UnifiedSettingSubtitleType.packageVersion:
        return const _PackageVersionSubtitle();
      case null:
        break;
    }
    final subtitle = subtitleBuilder?.call(context, surface);
    if (subtitle == null || subtitle.trim().isEmpty) {
      return null;
    }
    return material.Text(subtitle);
  }
}

List<UnifiedSettingEntry> buildUnifiedSettingEntries(
  material.BuildContext context, {
  required UnifiedSettingsSurface surface,
}) {
  return _buildUnifiedSettingEntryDefinitions()
      .where((entry) => entry.isVisible(context, surface))
      .toList();
}

String unifiedSettingSectionTitle(
  material.BuildContext context,
  UnifiedSettingSection section,
) {
  switch (section) {
    case UnifiedSettingSection.general:
      return context.l10n.settingsBasicSection;
    case UnifiedSettingSection.labs:
      return _text(context, '实验室', '實驗室', 'Labs');
    case UnifiedSettingSection.about:
      return context.l10n.settingsAboutSection;
  }
}

class UnifiedCupertinoSettingsSectionView extends material.StatelessWidget {
  const UnifiedCupertinoSettingsSectionView({
    super.key,
    required this.section,
    required this.entries,
  });

  final UnifiedSettingSection section;
  final List<UnifiedSettingEntry> entries;

  @override
  material.Widget build(material.BuildContext context) {
    if (entries.isEmpty) {
      return const material.SizedBox.shrink();
    }

    final textStyle =
        cupertino.CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              fontSize: 13,
              color: cupertino.CupertinoDynamicColor.resolve(
                cupertino.CupertinoColors.systemGrey,
                context,
              ),
              letterSpacing: 0.2,
            );

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        material.Padding(
          padding: const material.EdgeInsets.symmetric(horizontal: 20),
          child: material.Text(
            unifiedSettingSectionTitle(context, section),
            style: textStyle,
          ),
        ),
        const material.SizedBox(height: 8),
        CupertinoSettingsGroupCard(
          addDividers: true,
          backgroundColor: resolveSettingsSectionBackground(context),
          children: [
            for (final entry in entries)
              UnifiedCupertinoSettingHomeTile(entry: entry),
          ],
        ),
      ],
    );
  }
}

class UnifiedCupertinoSettingHomeTile extends material.StatefulWidget {
  const UnifiedCupertinoSettingHomeTile({
    super.key,
    required this.entry,
  });

  final UnifiedSettingEntry entry;

  @override
  material.State<UnifiedCupertinoSettingHomeTile> createState() =>
      _UnifiedCupertinoSettingHomeTileState();
}

class _UnifiedCupertinoSettingHomeTileState
    extends material.State<UnifiedCupertinoSettingHomeTile> {
  @override
  material.Widget build(material.BuildContext context) {
    switch (widget.entry.inlineControlType) {
      case UnifiedSettingInlineControlType.autoUpdate:
        return const AutoUpdateSettingTile();
      case null:
        break;
    }

    return CupertinoSettingsTile(
      leading: material.Icon(
        widget.entry.phoneIcon ?? widget.entry.icon,
        color: resolveSettingsIconColor(context),
      ),
      title: material.Text(
        widget.entry.title(context, UnifiedSettingsSurface.phone),
      ),
      subtitle: widget.entry.subtitleWidget(
        context,
        UnifiedSettingsSurface.phone,
      ),
      backgroundColor: resolveSettingsTileBackground(context),
      showChevron: widget.entry.contentType != null,
      onTap: widget.entry.contentType == null
          ? null
          : () async {
              await openUnifiedCupertinoSettingEntry(context, widget.entry);
              if (!mounted) return;
              setState(() {});
            },
    );
  }
}

Future<void> openUnifiedCupertinoSettingEntry(
  material.BuildContext context,
  UnifiedSettingEntry entry,
) {
  return CupertinoBottomSheetPageNavigator.push<void>(
    context,
    title: entry.pageTitle(context, UnifiedSettingsSurface.phone),
    builder: (routeContext) => entry.buildPage(
      routeContext,
      UnifiedSettingsSurface.phone,
    ),
  );
}

List<UnifiedSettingEntry> _buildUnifiedSettingEntryDefinitions() {
  return [
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.appearance,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.appearance,
      pageTitleBuilder: (context, surface) => context.l10n.appearanceSettings,
      subtitleBuilder: (context, surface) => _themeModeLabel(context),
      icon: Ionicons.color_palette_outline,
      phoneIcon: cupertino.CupertinoIcons.paintbrush,
      contentType: UnifiedSettingContentType.appearance,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.language,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.language,
      pageTitleBuilder: (context, surface) =>
          context.l10n.languageSettingsTitle,
      subtitleBuilder: (context, surface) {
        final provider = context.watch<AppLanguageProvider>();
        return context.l10n.currentLanguage(
          _languageModeLabel(context, provider.mode),
        );
      },
      icon: Ionicons.language_outline,
      phoneIcon: cupertino.CupertinoIcons.globe,
      contentType: UnifiedSettingContentType.language,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.general,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.general,
      pageTitleBuilder: (context, surface) => context.l10n.generalSettings,
      icon: Ionicons.settings_outline,
      phoneIcon: cupertino.CupertinoIcons.settings,
      contentType: UnifiedSettingContentType.general,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.updateCheck,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.aboutAutoCheckUpdates,
      pageTitleBuilder: (context, surface) =>
          context.l10n.aboutAutoCheckUpdates,
      subtitleBuilder: (context, surface) =>
          context.l10n.aboutManualOnlyWhenDisabled,
      icon: Ionicons.cloud_outline,
      phoneIcon: cupertino.CupertinoIcons.arrow_clockwise_circle,
      inlineControlType: UnifiedSettingInlineControlType.autoUpdate,
      visible: (context, surface) => surface == UnifiedSettingsSurface.phone,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.storage,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.storage,
      pageTitleBuilder: (context, surface) => context.l10n.storageSettings,
      subtitleBuilder: (context, surface) =>
          context.l10n.storageSettingsSubtitle,
      icon: Ionicons.folder_open_outline,
      phoneIcon: cupertino.CupertinoIcons.archivebox,
      contentType: UnifiedSettingContentType.storage,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.network,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.networkSettings,
      pageTitleBuilder: (context, surface) => context.l10n.networkSettings,
      subtitleBuilder: (context, surface) =>
          context.l10n.networkSettingsSubtitle,
      icon: Ionicons.wifi_outline,
      phoneIcon: cupertino.CupertinoIcons.globe,
      contentType: UnifiedSettingContentType.network,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.backupRestore,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.backupAndRestore,
      pageTitleBuilder: (context, surface) => context.l10n.backupAndRestore,
      icon: Ionicons.cloud_upload_outline,
      phoneIcon: cupertino.CupertinoIcons.cloud_upload,
      contentType: UnifiedSettingContentType.backupRestore,
      visible: (context, surface) =>
          surface == UnifiedSettingsSurface.desktopTablet && !globals.isPhone,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.player,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.player,
      pageTitleBuilder: (context, surface) => context.l10n.playerSettings,
      subtitleBuilder: (context, surface) =>
          _playerKernelLabel(context, PlayerFactory.getKernelType()),
      icon: Ionicons.play_circle_outline,
      phoneIcon: cupertino.CupertinoIcons.play_circle,
      contentType: UnifiedSettingContentType.player,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.danmaku,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => _text(context, '弹幕', '彈幕', 'Danmaku'),
      pageTitleBuilder: (context, surface) =>
          _text(context, '弹幕设置', '彈幕設定', 'Danmaku Settings'),
      subtitleBuilder: (context, surface) => _text(
        context,
        '渲染、防剧透与匹配',
        '渲染、防劇透與匹配',
        'Rendering, spoiler filtering, and matching.',
      ),
      icon: Ionicons.hardware_chip_outline,
      phoneIcon: cupertino.CupertinoIcons.bubble_left_bubble_right,
      contentType: UnifiedSettingContentType.danmaku,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.externalPlayer,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.externalCall,
      pageTitleBuilder: (context, surface) => context.l10n.externalCall,
      subtitleBuilder: (context, surface) {
        final externalSupported = globals.isDesktop;
        if (!externalSupported) {
          return context.l10n.desktopOnlySupported;
        }
        final settingsProvider = context.watch<SettingsProvider>();
        return settingsProvider.useExternalPlayer
            ? context.l10n.externalPlayerEnabled
            : context.l10n.externalPlayerDisabled;
      },
      icon: Ionicons.open_outline,
      phoneIcon: cupertino.CupertinoIcons.square_arrow_up,
      contentType: UnifiedSettingContentType.externalPlayer,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.shortcuts,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.shortcuts,
      pageTitleBuilder: (context, surface) => context.l10n.shortcutsSettings,
      icon: Ionicons.key_outline,
      phoneIcon: cupertino.CupertinoIcons.keyboard,
      contentType: UnifiedSettingContentType.shortcuts,
      visible: (context, surface) =>
          surface == UnifiedSettingsSurface.desktopTablet && !globals.isPhone,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.remoteAccess,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.remoteAccess,
      pageTitleBuilder: (context, surface) => context.l10n.remoteAccess,
      subtitleBuilder: (context, surface) => _text(
        context,
        '本机被控端、共享媒体库与局域网遥控器',
        '本機被控端、共享媒體庫與區域網路遙控器',
        'Receiver, shared library, and LAN remote control.',
      ),
      icon: Ionicons.link_outline,
      phoneIcon: cupertino.CupertinoIcons.dot_radiowaves_left_right,
      contentType: UnifiedSettingContentType.remoteAccess,
      visible: (context, surface) => !kIsWeb,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.remoteMediaLibrary,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) =>
          surface == UnifiedSettingsSurface.phone
              ? context.l10n.networkMediaLibrary
              : context.l10n.remoteMediaLibrary,
      pageTitleBuilder: (context, surface) =>
          surface == UnifiedSettingsSurface.phone
              ? context.l10n.networkMediaLibrary
              : context.l10n.remoteMediaLibrary,
      subtitleBuilder: _mediaServerSubtitle,
      icon: Ionicons.library_outline,
      phoneIcon: cupertino.CupertinoIcons.cloud,
      contentType: UnifiedSettingContentType.remoteMediaLibrary,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.downloader,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.tabTorrentDownload,
      pageTitleBuilder: (context, surface) => context.l10n.tabTorrentDownload,
      subtitleBuilder: (context, surface) => _text(
        context,
        '下载任务、设置',
        '下載任務、設定',
        'Download tasks and settings.',
      ),
      icon: Ionicons.cloud_download_outline,
      phoneIcon: cupertino.CupertinoIcons.arrow_down_circle,
      contentType: UnifiedSettingContentType.downloader,
      visible: (context, surface) => globals.isDownloaderSupportedPlatform,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.developerOptions,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => context.l10n.developerOptions,
      pageTitleBuilder: (context, surface) => context.l10n.developerOptions,
      subtitleBuilder: (context, surface) =>
          context.l10n.developerOptionsSubtitle,
      icon: Ionicons.code_slash_outline,
      phoneIcon: cupertino.CupertinoIcons.command,
      contentType: UnifiedSettingContentType.developerOptions,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.labs,
      section: UnifiedSettingSection.labs,
      titleBuilder: (context, surface) => _text(context, '实验室', '實驗室', 'Labs'),
      pageTitleBuilder: (context, surface) =>
          _text(context, '实验室', '實驗室', 'Labs'),
      subtitleBuilder: (context, surface) => _text(
        context,
        '实验性功能与开关',
        '實驗性功能與開關',
        'Experimental features and switches.',
      ),
      icon: Ionicons.flask_outline,
      phoneIcon: cupertino.CupertinoIcons.lab_flask,
      contentType: UnifiedSettingContentType.labs,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.plugins,
      section: UnifiedSettingSection.general,
      titleBuilder: (context, surface) => _text(context, '插件', '插件', 'Plugins'),
      pageTitleBuilder: (context, surface) =>
          _text(context, '插件设置', '插件設定', 'Plugin Settings'),
      subtitleBuilder: (context, surface) => _text(
        context,
        '管理 JS 插件并配置启用状态',
        '管理 JS 插件並配置啟用狀態',
        'Manage JavaScript plugins and enabled states.',
      ),
      icon: Ionicons.extension_puzzle_outline,
      phoneIcon: cupertino.CupertinoIcons.cube_box,
      contentType: UnifiedSettingContentType.plugins,
    ),
    UnifiedSettingEntry(
      id: UnifiedSettingEntryIds.about,
      section: UnifiedSettingSection.about,
      titleBuilder: (context, surface) => context.l10n.about,
      pageTitleBuilder: (context, surface) => context.l10n.about,
      subtitleType: UnifiedSettingSubtitleType.packageVersion,
      icon: Ionicons.information_circle_outline,
      phoneIcon: cupertino.CupertinoIcons.info_circle,
      contentType: UnifiedSettingContentType.about,
    ),
  ];
}

String _themeModeLabel(material.BuildContext context) {
  final themeMode = context.watch<ThemeNotifier>().themeMode;
  switch (themeMode) {
    case material.ThemeMode.light:
      return context.l10n.lightMode;
    case material.ThemeMode.dark:
      return context.l10n.darkMode;
    case material.ThemeMode.system:
      return context.l10n.followSystem;
  }
}

String _languageModeLabel(
  material.BuildContext context,
  AppLanguageMode mode,
) {
  switch (mode) {
    case AppLanguageMode.simplifiedChinese:
      return context.l10n.languageSimplifiedChinese;
    case AppLanguageMode.traditionalChinese:
      return context.l10n.languageTraditionalChinese;
    case AppLanguageMode.english:
      return context.l10n.languageEnglish;
    case AppLanguageMode.auto:
      return context.l10n.languageAuto;
  }
}

String _playerKernelLabel(
  material.BuildContext context,
  PlayerKernelType type,
) {
  switch (type) {
    case PlayerKernelType.mdk:
      return context.l10n.playerKernelCurrentMdk;
    case PlayerKernelType.videoPlayer:
      return context.l10n.playerKernelCurrentVideoPlayer;
    case PlayerKernelType.mediaKit:
      return context.l10n.playerKernelCurrentLibmpv;
    case PlayerKernelType.erika:
      return _text(context, '当前：Erika', '目前：Erika', 'Current: Erika');
  }
}

String _mediaServerSubtitle(
  material.BuildContext context,
  UnifiedSettingsSurface surface,
) {
  final jellyfinProvider = context.watch<JellyfinProvider>();
  final embyProvider = context.watch<EmbyProvider>();
  final jellyfinConnected = jellyfinProvider.isConnected;
  final embyConnected = embyProvider.isConnected;

  if (!jellyfinConnected && !embyConnected) {
    return context.l10n.noConnectedServer;
  }

  final segments = <String>[];
  if (jellyfinConnected) {
    segments.add(
      context.l10n.mediaServerSummary(
        'Jellyfin',
        _resolveLibrarySummary(
          context,
          jellyfinProvider.availableLibraries,
          jellyfinProvider.selectedLibraryIds,
        ),
      ),
    );
  }

  if (embyConnected) {
    segments.add(
      context.l10n.mediaServerSummary(
        'Emby',
        _resolveLibrarySummary(
          context,
          embyProvider.availableLibraries,
          embyProvider.selectedLibraryIds,
        ),
      ),
    );
  }

  return segments.join('  |  ');
}

String _resolveLibrarySummary<T>(
  material.BuildContext context,
  List<T> libraries,
  Iterable<String> selectedIds,
) {
  if (selectedIds.isEmpty) {
    return context.l10n.mediaLibraryNotSelected;
  }

  final nameMap = <String, String>{
    for (final library in libraries)
      if (library is JellyfinLibrary)
        library.id: library.name
      else if (library is EmbyLibrary)
        library.id: library.name,
  };

  final names = <String>[];
  for (final id in selectedIds) {
    final name = nameMap[id];
    if (name != null && name.isNotEmpty) {
      names.add(name);
    }
  }

  if (names.isEmpty) {
    return context.l10n.mediaLibraryNotMatched;
  }
  if (names.length == 1) {
    return names.first;
  }
  return context.l10n.mediaLibraryAndCount(names.first, names.length);
}

String _text(
  material.BuildContext context,
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

class _PackageVersionSubtitle extends material.StatefulWidget {
  const _PackageVersionSubtitle();

  @override
  material.State<_PackageVersionSubtitle> createState() =>
      _PackageVersionSubtitleState();
}

class _PackageVersionSubtitleState
    extends material.State<_PackageVersionSubtitle> {
  String? _version;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
      });
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final subtitle = _loadFailed
        ? context.l10n.versionLoadFailed
        : (_version == null
            ? context.l10n.loading
            : context.l10n.currentVersion(_version!));
    return material.Text(subtitle);
  }
}
