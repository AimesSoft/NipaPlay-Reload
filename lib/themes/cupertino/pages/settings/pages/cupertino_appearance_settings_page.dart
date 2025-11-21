import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:provider/provider.dart';

import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/models/anime_detail_display_mode.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

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
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final sectionBackground = resolveSettingsSectionBackground(context);
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(
        title: '外观',
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
                    title: '浅色模式',
                    subtitle: '保持明亮的界面与对比度。',
                  ),
                  _buildThemeOptionTile(
                    mode: ThemeMode.dark,
                    title: '深色模式',
                    subtitle: '降低亮度，保护视力并节省电量。',
                  ),
                  _buildThemeOptionTile(
                    mode: ThemeMode.system,
                    title: '跟随系统',
                    subtitle: '自动根据系统设置切换外观。',
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '番剧详情样式',
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
                    title: '简洁模式',
                    subtitle: '经典布局，信息分栏展示。',
                  ),
                  _buildDetailModeTile(
                    mode: AnimeDetailDisplayMode.vivid,
                    title: '绚丽模式',
                    subtitle: '海报主视觉、横向剧集卡片。',
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '最近观看样式',
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
                    title: '简洁版',
                    subtitle: '纯文本列表，节省空间。',
                  ),
                  _buildRecentStyleTile(
                    style: RecentWatchingStyle.detailed,
                    title: '详细版',
                    subtitle: '带截图的横向滚动卡片。',
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
}
