import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';

class CupertinoWebDAVQuickSettingsPage extends StatefulWidget {
  const CupertinoWebDAVQuickSettingsPage({super.key});

  @override
  State<CupertinoWebDAVQuickSettingsPage> createState() =>
      _CupertinoWebDAVQuickSettingsPageState();
}

class _CupertinoWebDAVQuickSettingsPageState
    extends State<CupertinoWebDAVQuickSettingsPage> {
  late final TextEditingController _directoryController;

  @override
  void initState() {
    super.initState();
    _directoryController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WebDAVQuickAccessProvider>(context, listen: false)
          .loadSettings();
    });
  }

  @override
  void dispose() {
    _directoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return Consumer<WebDAVQuickAccessProvider>(
      builder: (context, provider, _) {
        _directoryController.text = provider.defaultDirectory;

        return AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: 'WebDAV快捷设置',
            useNativeToolbar: true,
          ),
          body: ColoredBox(
            color: backgroundColor,
            child: SafeArea(
              top: false,
              bottom: false,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
                children: [
                  _buildDescriptionCard(context),
                  const SizedBox(height: 24),
                  _buildToggleCard(context, provider),
                  const SizedBox(height: 24),
                  _buildDefaultTabCard(context, provider),
                  if (provider.showWebDAVTab) ...[
                    const SizedBox(height: 24),
                    _buildServerSelectorCard(context, provider),
                    const SizedBox(height: 24),
                    _buildDirectoryCard(context, provider),
                  ],
                  const SizedBox(height: 24),
                  _buildSortPresetCard(context, provider),
                  const SizedBox(height: 24),
                  _buildPathBreadcrumbCard(context, provider),
                  const SizedBox(height: 24),
                  _buildAutoEnterSeasonCard(context, provider),
                  const SizedBox(height: 24),
                  _buildResetCard(context, provider),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDescriptionCard(BuildContext context) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '配置底部 WebDAV 快捷 Tab，可以快速访问 WebDAV 服务器中的视频文件。',
            style: textTheme.copyWith(
              fontSize: 14,
              color: secondaryColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleCard(BuildContext context, WebDAVQuickAccessProvider provider) {
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        CupertinoSettingsTile(
          leading: Icon(CupertinoIcons.eye, color: iconColor),
          title: const Text('显示 WebDAV Tab'),
          subtitle: const Text('在底部导航栏显示 WebDAV 快捷入口'),
          backgroundColor: tileColor,
          trailing: CupertinoSwitch(
            value: provider.showWebDAVTab,
            activeColor: CupertinoColors.activeBlue,
            onChanged: (value) {
              provider.setShowWebDAVTab(value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultTabCard(BuildContext context, WebDAVQuickAccessProvider provider) {
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      addDividers: true,
      dividerIndent: 56,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.house, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                '默认主页',
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontSize: 13,
                      color: secondaryColor,
                    ),
              ),
            ],
          ),
        ),
        ...provider.cupertinoAvailableTabs.map((tabName) {
          final isSelected = tabName == provider.defaultHomeTab;
          return CupertinoSettingsTile(
            leading: Icon(
              _getTabIcon(tabName),
              color: iconColor,
            ),
            title: Text(WebDAVQuickAccessProvider.getTabDisplayName(tabName)),
            subtitle: Text(
              tabName == WebDAVQuickAccessProvider.tabWebDAV
                  ? '打开时直接进入 WebDAV'
                  : '打开时直接进入此页面',
              style: TextStyle(fontSize: 11, color: secondaryColor),
            ),
            backgroundColor: tileColor,
            trailing: isSelected
                ? const Icon(CupertinoIcons.check_mark, color: CupertinoColors.activeBlue)
                : null,
            onTap: () {
              provider.setDefaultHomeTab(tabName);
            },
          );
        }),
        if (provider.defaultHomeTab == WebDAVQuickAccessProvider.tabWebDAV && !provider.showWebDAVTab)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              '⚠️ 当前已选择 WebDAV 为默认主页，但 WebDAV Tab 未开启，将自动回落到首页',
              style: TextStyle(
                color: CupertinoColors.systemOrange.resolveFrom(context),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  IconData _getTabIcon(String tabName) {
    switch (tabName) {
      case WebDAVQuickAccessProvider.tabHome:
        return CupertinoIcons.house_fill;
      case WebDAVQuickAccessProvider.tabVideo:
        return CupertinoIcons.play_rectangle_fill;
      case WebDAVQuickAccessProvider.tabMediaLibrary:
        return CupertinoIcons.film_fill;
      case WebDAVQuickAccessProvider.tabAccount:
        return CupertinoIcons.person_crop_circle_fill;
      case WebDAVQuickAccessProvider.tabSettings:
        return CupertinoIcons.gear_alt_fill;
      case WebDAVQuickAccessProvider.tabWebDAV:
        return CupertinoIcons.cloud_fill;
      default:
        return CupertinoIcons.circle;
    }
  }

  Widget _buildServerSelectorCard(
      BuildContext context, WebDAVQuickAccessProvider provider) {
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);
    final connections = WebDAVService.instance.connections;

    if (connections.isEmpty) {
      return CupertinoSettingsGroupCard(
        margin: EdgeInsets.zero,
        backgroundColor: sectionColor,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  CupertinoIcons.cloud,
                  size: 48,
                  color: secondaryColor,
                ),
                const SizedBox(height: 12),
                Text(
                  '没有配置 WebDAV 服务器',
                  style: CupertinoTheme.of(context).textTheme.textStyle,
                ),
                const SizedBox(height: 8),
                Text(
                  '请先在「远程媒体库」设置中添加 WebDAV 服务器',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 13,
                        color: secondaryColor,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      addDividers: true,
      dividerIndent: 56,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.device_desktop, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                '默认服务器',
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontSize: 13,
                      color: secondaryColor,
                    ),
              ),
            ],
          ),
        ),
        ...connections.map((connection) {
          final isSelected = connection.name == provider.defaultServerName;
          return CupertinoSettingsTile(
            leading: Icon(
              isSelected ? CupertinoIcons.cloud_fill : CupertinoIcons.cloud,
              color: iconColor,
            ),
            title: Text(connection.name),
            subtitle: Text(
              connection.url,
              style: TextStyle(fontSize: 11, color: secondaryColor),
            ),
            backgroundColor: tileColor,
            trailing: isSelected
                ? const Icon(CupertinoIcons.check_mark, color: CupertinoColors.activeBlue)
                : null,
            onTap: () {
              provider.setDefaultServerName(connection.name);
            },
          );
        }),
      ],
    );
  }

  Widget _buildDirectoryCard(
      BuildContext context, WebDAVQuickAccessProvider provider) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(CupertinoIcons.folder, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    '默认目录',
                    style: textTheme.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '点击 WebDAV Tab 时将直接打开此目录',
                style: textTheme.copyWith(
                  fontSize: 13,
                  color: secondaryColor,
                ),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _directoryController,
                placeholder: '例如: /视频/动画',
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiarySystemFill,
                    context,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                suffix: CupertinoButton(
                  padding: const EdgeInsets.only(right: 4),
                  onPressed: () {
                    provider.setDefaultDirectory('/');
                    _directoryController.text = '/';
                  },
                  child: const Icon(CupertinoIcons.refresh, size: 18),
                ),
                onSubmitted: (value) {
                  provider.setDefaultDirectory(value);
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 36,
                  child: CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    onPressed: () {
                      provider.setDefaultDirectory(_directoryController.text);
                      AdaptiveSnackBar.show(
                        context,
                        message: '目录已保存',
                        type: AdaptiveSnackBarType.success,
                      );
                    },
                    child: const Text('保存'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSortPresetCard(BuildContext context, WebDAVQuickAccessProvider provider) {
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      addDividers: true,
      dividerIndent: 56,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.sort_down, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                '文件排序',
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontSize: 13,
                      color: secondaryColor,
                    ),
              ),
            ],
          ),
        ),
        ...WebDAVSortPreset.values.map((preset) {
          final isSelected = preset == provider.sortPreset;
          return CupertinoSettingsTile(
            leading: Icon(
              _getSortIcon(preset),
              color: iconColor,
            ),
            title: Text(preset.displayName),
            subtitle: Text(
              preset.description,
              style: TextStyle(fontSize: 11, color: secondaryColor),
            ),
            backgroundColor: tileColor,
            trailing: isSelected
                ? const Icon(CupertinoIcons.check_mark, color: CupertinoColors.activeBlue)
                : null,
            onTap: () {
              provider.setSortPreset(preset);
            },
          );
        }),
      ],
    );
  }

  IconData _getSortIcon(WebDAVSortPreset preset) {
    switch (preset) {
      case WebDAVSortPreset.defaultValue:
        return CupertinoIcons.folder_fill;
      case WebDAVSortPreset.nameAsc:
        return CupertinoIcons.sort_up;
      case WebDAVSortPreset.nameDesc:
        return CupertinoIcons.sort_down;
      case WebDAVSortPreset.modifiedDesc:
        return CupertinoIcons.time;
      case WebDAVSortPreset.modifiedAsc:
        return CupertinoIcons.clock;
      case WebDAVSortPreset.sizeDesc:
        return CupertinoIcons.arrow_down;
      case WebDAVSortPreset.sizeAsc:
        return CupertinoIcons.arrow_up;
      default:
        return CupertinoIcons.sort_down;
    }
  }

  Widget _buildPathBreadcrumbCard(BuildContext context, WebDAVQuickAccessProvider provider) {
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        CupertinoSettingsTile(
          leading: Icon(CupertinoIcons.map_pin, color: iconColor),
          title: const Text('显示路径导航'),
          subtitle: const Text('在顶部显示可点击的路径面包屑导航'),
          backgroundColor: tileColor,
          trailing: CupertinoSwitch(
            value: provider.showPathBreadcrumb,
            activeColor: CupertinoColors.activeBlue,
            onChanged: (value) {
              provider.setShowPathBreadcrumb(value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAutoEnterSeasonCard(BuildContext context, WebDAVQuickAccessProvider provider) {
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        CupertinoSettingsTile(
          leading: Icon(CupertinoIcons.folder_fill, color: iconColor),
          title: const Text('自动进入 Season 文件夹'),
          subtitle: const Text('打开文件夹时自动进入匹配的子文件夹'),
          backgroundColor: tileColor,
          trailing: CupertinoSwitch(
            value: provider.autoEnterSeasonFolder,
            activeColor: CupertinoColors.activeBlue,
            onChanged: (value) {
              provider.setAutoEnterSeasonFolder(value);
            },
          ),
        ),
        if (provider.autoEnterSeasonFolder) ...[
          Container(
            color: tileColor,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '匹配模式',
                  style: textTheme.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '支持通配符：* 匹配任意字符，? 匹配单个字符',
                  style: textTheme.copyWith(
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: TextEditingController(
                    text: provider.seasonFolderPattern,
                  ),
                  placeholder: '例如: Season*、Season ??、S*',
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiarySystemFill,
                      context,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onSubmitted: (value) {
                    provider.setSeasonFolderPattern(value);
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildPresetChip(context, 'Season*', provider),
                    _buildPresetChip(context, 'Season ??', provider),
                    _buildPresetChip(context, 'S*', provider),
                    _buildPresetChip(context, 'Disc*', provider),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPresetChip(
    BuildContext context,
    String pattern,
    WebDAVQuickAccessProvider provider,
  ) {
    final isSelected = provider.seasonFolderPattern == pattern;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minSize: 0,
      color: isSelected
          ? CupertinoColors.activeBlue.withOpacity(0.1)
          : CupertinoDynamicColor.resolve(
              CupertinoColors.tertiarySystemFill,
              context,
            ),
      borderRadius: BorderRadius.circular(16),
      onPressed: () {
        provider.setSeasonFolderPattern(pattern);
      },
      child: Text(
        pattern,
        style: TextStyle(
          color: isSelected
              ? CupertinoColors.activeBlue
              : CupertinoDynamicColor.resolve(
                  CupertinoColors.label,
                  context,
                ),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildResetCard(BuildContext context, WebDAVQuickAccessProvider provider) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        Center(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 16),
            onPressed: () {
              provider.resetSettings();
              _directoryController.text = '/';
              AdaptiveSnackBar.show(
                context,
                message: 'WebDAV 快捷设置已重置',
                type: AdaptiveSnackBarType.success,
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.refresh, size: 18, color: secondaryColor),
                const SizedBox(width: 8),
                Text(
                  '重置所有设置',
                  style: TextStyle(color: secondaryColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
