import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:provider/provider.dart';
import 'package:nipaplay/l10n/l10n.dart';

import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/models/anime_detail_display_mode.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';

import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';

class CupertinoAppearanceSettingsPage extends StatefulWidget {
  const CupertinoAppearanceSettingsPage({super.key});

  @override
  State<CupertinoAppearanceSettingsPage> createState() =>
      _CupertinoAppearanceSettingsPageState();
}

class _CupertinoAppearanceSettingsPageState
    extends State<CupertinoAppearanceSettingsPage> {
  late ThemeMode _currentMode;
  late AnimeDetailDisplayMode _detailMode;
  late RecentWatchingStyle _recentStyle;

  @override
  void initState() {
    super.initState();
    final notifier = Provider.of<ThemeNotifier>(context, listen: false);
    final appearanceSettings =
        Provider.of<AppearanceSettingsProvider>(context, listen: false);
    _currentMode = notifier.themeMode;
    _detailMode = notifier.animeDetailDisplayMode;
    _recentStyle = appearanceSettings.recentWatchingStyle;
  }

  void _updateThemeMode(ThemeMode mode) {
    if (_currentMode == mode) return;
    setState(() {
      _currentMode = mode;
    });
    Provider.of<ThemeNotifier>(context, listen: false).themeMode = mode;
  }

  void _updateDetailMode(AnimeDetailDisplayMode mode) {
    if (_detailMode == mode) return;
    setState(() {
      _detailMode = mode;
    });
    Provider.of<ThemeNotifier>(context, listen: false).animeDetailDisplayMode =
        mode;
  }

  void _updateRecentStyle(RecentWatchingStyle style) {
    if (_recentStyle == style) return;
    setState(() {
      _recentStyle = style;
    });
    Provider.of<AppearanceSettingsProvider>(context, listen: false)
        .setRecentWatchingStyle(style);
  }

  @override
  Widget build(BuildContext context) {
    final homeSections = context.watch<HomeSectionsSettingsProvider>();
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final sectionBackground = resolveSettingsSectionBackground(context);
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: context.l10n.appearance,
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            children: [
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: sectionBackground,
                addDividers: true,
                dividerIndent: 16,
                children: [
                  _buildThemeOptionTile(
                    mode: ThemeMode.light,
                    title: context.l10n.lightMode,
                    subtitle: context.l10n.appearanceLightModeSubtitle,
                  ),
                  _buildThemeOptionTile(
                    mode: ThemeMode.dark,
                    title: context.l10n.darkMode,
                    subtitle: context.l10n.appearanceDarkModeSubtitle,
                  ),
                  _buildThemeOptionTile(
                    mode: ThemeMode.system,
                    title: context.l10n.followSystem,
                    subtitle: context.l10n.appearanceFollowSystemSubtitle,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  context.l10n.appearanceAnimeDetailStyle,
                  style:
                      CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                            fontSize: 13,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.systemGrey,
                              context,
                            ),
                            letterSpacing: 0.2,
                          ),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: sectionBackground,
                addDividers: true,
                dividerIndent: 16,
                children: [
                  _buildDetailModeTile(
                    mode: AnimeDetailDisplayMode.simple,
                    title: context.l10n.appearanceDetailSimple,
                    subtitle: context.l10n.appearanceDetailSimpleSubtitle,
                  ),
                  _buildDetailModeTile(
                    mode: AnimeDetailDisplayMode.vivid,
                    title: context.l10n.appearanceDetailVivid,
                    subtitle: context.l10n.appearanceDetailVividSubtitle,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  context.l10n.appearanceRecentWatchingStyle,
                  style:
                      CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                            fontSize: 13,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.systemGrey,
                              context,
                            ),
                            letterSpacing: 0.2,
                          ),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: sectionBackground,
                addDividers: true,
                dividerIndent: 16,
                children: [
                  _buildRecentStyleTile(
                    style: RecentWatchingStyle.simple,
                    title: context.l10n.appearanceRecentSimple,
                    subtitle: context.l10n.appearanceRecentSimpleSubtitle,
                  ),
                  _buildRecentStyleTile(
                    style: RecentWatchingStyle.detailed,
                    title: context.l10n.appearanceRecentDetailed,
                    subtitle: context.l10n.appearanceRecentDetailedSubtitle,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  context.l10n.appearanceHomeSections,
                  style:
                      CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                            fontSize: 13,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.systemGrey,
                              context,
                            ),
                            letterSpacing: 0.2,
                          ),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: sectionBackground,
                addDividers: true,
                dividerIndent: 16,
                children: [
                  ...HomeSectionType.values.map(
                    (section) => _buildHomeSectionToggleTile(
                      section: section,
                      enabled: homeSections.isSectionEnabled(section),
                      onChanged: (value) =>
                          homeSections.setSectionEnabled(section, value),
                    ),
                  ),
                  CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.refresh,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: Text(context.l10n.restoreDefaults),
                    subtitle: Text(context.l10n.restoreDefaultsSubtitle),
                    backgroundColor: resolveSettingsTileBackground(context),
                    onTap: homeSections.restoreDefaults,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOptionTile({
    required ThemeMode mode,
    required String title,
    required String subtitle,
  }) {
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        mode == ThemeMode.dark
            ? CupertinoIcons.moon_fill
            : (mode == ThemeMode.light
                ? CupertinoIcons.sun_max_fill
                : CupertinoIcons.circle_lefthalf_fill),
        color: resolveSettingsIconColor(context),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      backgroundColor: tileColor,
      selected: _currentMode == mode,
      onTap: () => _updateThemeMode(mode),
    );
  }

  Widget _buildDetailModeTile({
    required AnimeDetailDisplayMode mode,
    required String title,
    required String subtitle,
  }) {
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        mode == AnimeDetailDisplayMode.simple
            ? CupertinoIcons.list_bullet
            : CupertinoIcons.rectangle_on_rectangle_angled,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      backgroundColor: tileColor,
      selected: _detailMode == mode,
      onTap: () => _updateDetailMode(mode),
    );
  }

  Widget _buildRecentStyleTile({
    required RecentWatchingStyle style,
    required String title,
    required String subtitle,
  }) {
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        style == RecentWatchingStyle.simple
            ? CupertinoIcons.textformat
            : CupertinoIcons.photo_on_rectangle,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      backgroundColor: tileColor,
      selected: _recentStyle == style,
      onTap: () => _updateRecentStyle(style),
    );
  }

  Widget _buildHomeSectionToggleTile({
    required HomeSectionType section,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    final tileColor = resolveSettingsTileBackground(context);
    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.square_grid_2x2,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(section.title),
      trailing: CupertinoSwitch(
        value: enabled,
        onChanged: onChanged,
      ),
      backgroundColor: tileColor,
      onTap: () => onChanged(!enabled),
    );
  }
}
