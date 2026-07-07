import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:provider/provider.dart';

class WebDAVQuickSettingsContent extends StatefulWidget {
  const WebDAVQuickSettingsContent({super.key});

  @override
  State<WebDAVQuickSettingsContent> createState() =>
      _WebDAVQuickSettingsContentState();
}

class _WebDAVQuickSettingsContentState
    extends State<WebDAVQuickSettingsContent> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final provider = context.read<WebDAVQuickAccessProvider>();
    await WebDAVService.instance.initialize();
    await provider.loadSettings();
    if (!mounted) return;
    setState(() {
      _isInitializing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return AdaptiveSettingsPage(
        title: 'WebDAV快捷设置',
        children: [
          AdaptiveSettingsSection(
            children: [
              AdaptiveSettingsTile.card(
                title: '正在加载设置',
                subtitle: '正在读取 WebDAV 连接和快捷入口配置',
                icon: Icons.hourglass_empty,
                phoneIcon: cupertino.CupertinoIcons.refresh,
                enabled: false,
                onTap: () {},
              ),
            ],
          ),
        ],
      );
    }

    return Consumer<WebDAVQuickAccessProvider>(
      builder: (context, provider, child) {
        final connections = WebDAVService.instance.connections;
        final isPhoneLayout = AdaptiveSettingsScope.isPhoneLayout(context);
        final availableTabs = isPhoneLayout
            ? provider.phoneAvailableTabs
            : provider.desktopTabletAvailableTabs;

        return AdaptiveSettingsPage(
          title: 'WebDAV快捷设置',
          children: [
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile.card(
                  title: 'WebDAV 快捷入口',
                  subtitle: '配置底部 WebDAV 快捷 Tab，快速访问 WebDAV 服务器中的视频文件',
                  icon: Icons.info_outline,
                  phoneIcon: cupertino.CupertinoIcons.info_circle,
                  enabled: false,
                  onTap: () {},
                ),
                AdaptiveSettingsTile.toggle(
                  title: '显示 WebDAV Tab',
                  subtitle: '在底部导航栏显示 WebDAV 快捷入口',
                  icon: Icons.cloud_outlined,
                  phoneIcon: cupertino.CupertinoIcons.cloud,
                  value: provider.showWebDAVTab,
                  onChanged: provider.setShowWebDAVTab,
                ),
                AdaptiveSettingsTile<String>.dropdown(
                  title: '默认主页',
                  subtitle: _defaultHomeSubtitle(provider),
                  icon: Icons.home_outlined,
                  phoneIcon: cupertino.CupertinoIcons.house,
                  items: availableTabs
                      .map(
                        (tab) => DropdownMenuItemData<String>(
                          title:
                              WebDAVQuickAccessProvider.getTabDisplayName(tab),
                          value: tab,
                          isSelected: tab == provider.effectiveDefaultHomeTab,
                          description:
                              tab == WebDAVQuickAccessProvider.tabWebDAV
                                  ? '打开应用时直接进入 WebDAV 文件浏览'
                                  : '打开应用时直接进入此页面',
                        ),
                      )
                      .toList(),
                  onChanged: provider.setDefaultHomeTab,
                ),
                if (provider.defaultHomeTab ==
                        WebDAVQuickAccessProvider.tabWebDAV &&
                    !provider.showWebDAVTab)
                  AdaptiveSettingsTile.card(
                    title: 'WebDAV 默认主页未生效',
                    subtitle: '当前已选择 WebDAV 为默认主页，但 WebDAV Tab 未开启，将自动回落到首页',
                    icon: Icons.warning_amber_outlined,
                    phoneIcon:
                        cupertino.CupertinoIcons.exclamationmark_triangle,
                    enabled: false,
                    onTap: () {},
                  ),
              ],
            ),
            if (provider.showWebDAVTab) ...[
              const SizedBox(height: 16),
              AdaptiveSettingsSection(
                children: [
                  if (connections.isEmpty)
                    AdaptiveSettingsTile.card(
                      title: '没有配置 WebDAV 服务器',
                      subtitle: '请先在「远程媒体库」设置中添加 WebDAV 服务器',
                      icon: Ionicons.cloud_offline_outline,
                      phoneIcon:
                          cupertino.CupertinoIcons.exclamationmark_triangle,
                      enabled: false,
                      onTap: () {},
                    )
                  else ...[
                    AdaptiveSettingsTile<String>.dropdown(
                      title: '默认服务器',
                      subtitle: '点击 WebDAV Tab 时默认连接的服务器',
                      icon: Icons.dns_outlined,
                      phoneIcon: cupertino.CupertinoIcons.square_stack_3d_up,
                      items: _serverItems(connections, provider),
                      onChanged: provider.setDefaultServerName,
                    ),
                    AdaptiveSettingsTile.card(
                      title: '默认目录',
                      subtitle:
                          '${provider.defaultDirectory} · 点击 WebDAV Tab 时将直接打开此目录',
                      icon: Icons.folder_outlined,
                      phoneIcon: cupertino.CupertinoIcons.folder,
                      onTap: () => _editText(
                        title: '默认目录',
                        initialValue: provider.defaultDirectory,
                        hintText: '例如: /视频/动画',
                        onSaved: provider.setDefaultDirectory,
                        fallbackValue: '/',
                      ),
                    ),
                    AdaptiveSettingsTile<WebDAVSortPreset>.dropdown(
                      title: '文件排序',
                      subtitle: provider.sortPreset.description,
                      icon: Icons.sort,
                      phoneIcon: cupertino.CupertinoIcons.sort_down,
                      items: WebDAVSortPreset.values
                          .map(
                            (preset) => DropdownMenuItemData<WebDAVSortPreset>(
                              title: preset.displayName,
                              value: preset,
                              isSelected: preset == provider.sortPreset,
                              description: preset.description,
                            ),
                          )
                          .toList(),
                      onChanged: provider.setSortPreset,
                    ),
                    AdaptiveSettingsTile.toggle(
                      title: '显示路径导航',
                      subtitle: '在顶部显示可点击的路径面包屑导航',
                      icon: Icons.account_tree_outlined,
                      phoneIcon: cupertino.CupertinoIcons.list_bullet,
                      value: provider.showPathBreadcrumb,
                      onChanged: provider.setShowPathBreadcrumb,
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile.toggle(
                  title: '自动进入 Season 文件夹',
                  subtitle: '打开文件夹时自动进入匹配的子文件夹',
                  icon: Icons.folder_open_outlined,
                  phoneIcon: cupertino.CupertinoIcons.folder_open,
                  value: provider.autoEnterSeasonFolder,
                  onChanged: provider.setAutoEnterSeasonFolder,
                ),
                if (provider.autoEnterSeasonFolder) ...[
                  AdaptiveSettingsTile<String>.dropdown(
                    title: 'Season 匹配模式',
                    subtitle: '支持通配符：* 匹配任意字符，? 匹配单个字符',
                    icon: Icons.text_fields,
                    phoneIcon: cupertino.CupertinoIcons.textformat,
                    items: _seasonPatternItems(provider.seasonFolderPattern),
                    onChanged: provider.setSeasonFolderPattern,
                  ),
                  AdaptiveSettingsTile.card(
                    title: '自定义 Season 匹配模式',
                    subtitle: provider.seasonFolderPattern,
                    icon: Icons.edit_outlined,
                    phoneIcon: cupertino.CupertinoIcons.pencil,
                    onTap: () => _editText(
                      title: 'Season 匹配模式',
                      initialValue: provider.seasonFolderPattern,
                      hintText: '例如: Season*、Season ??、S*',
                      onSaved: provider.setSeasonFolderPattern,
                      fallbackValue: 'Season*',
                    ),
                  ),
                ],
                AdaptiveSettingsTile.toggle(
                  title: 'bgmid 快速匹配',
                  subtitle: '从 URL 中提取 bgmid，直接获取番剧信息',
                  icon: Icons.flash_on_outlined,
                  phoneIcon: cupertino.CupertinoIcons.bolt,
                  value: provider.bgmIdQuickMatch,
                  onChanged: provider.setBgmIdQuickMatch,
                ),
                if (provider.bgmIdQuickMatch)
                  AdaptiveSettingsTile.card(
                    title: 'bgmid 匹配规则',
                    subtitle: provider.bgmIdMatchPattern,
                    icon: Icons.rule_outlined,
                    phoneIcon: cupertino.CupertinoIcons.doc_text,
                    onTap: () => _editText(
                      title: 'bgmid 匹配规则',
                      initialValue: provider.bgmIdMatchPattern,
                      hintText: r'bgm(id)?[=-](\d+)',
                      helperText: r'最后一个捕获组应为数字，如 bgmid=(\d+) 或 bgm-(\d+)',
                      onSaved: provider.setBgmIdMatchPattern,
                      fallbackValue: r'bgm(id)?[=-](\d+)',
                    ),
                  ),
                AdaptiveSettingsTile.toggle(
                  title: 'tmdbId 快速匹配',
                  subtitle: '从 URL 中提取 tmdbId，通过 TMDB ID 直接获取番剧信息',
                  icon: Icons.movie_filter_outlined,
                  phoneIcon: cupertino.CupertinoIcons.film,
                  value: provider.tmdbIdQuickMatch,
                  onChanged: provider.setTmdbIdQuickMatch,
                ),
                if (provider.tmdbIdQuickMatch) ...[
                  AdaptiveSettingsTile.card(
                    title: 'tmdbId 匹配规则',
                    subtitle: provider.tmdbIdMatchPattern,
                    icon: Icons.rule_outlined,
                    phoneIcon: cupertino.CupertinoIcons.doc_text,
                    onTap: () => _editText(
                      title: 'tmdbId 匹配规则',
                      initialValue: provider.tmdbIdMatchPattern,
                      hintText: r'tmdb(id)?[=-](\d+)',
                      helperText: r'最后一个捕获组应为数字，如 tmdbid=(\d+) 或 tmdb-(\d+)',
                      onSaved: provider.setTmdbIdMatchPattern,
                      fallbackValue: r'tmdb(id)?[=-](\d+)',
                    ),
                  ),
                  AdaptiveSettingsTile.toggle(
                    title: '匹配弹幕自动剧集偏移',
                    subtitle: '自动计算跨季剧集编号偏移量，修复季内编号与弹幕库绝对编号不匹配的问题',
                    icon: Icons.format_list_numbered,
                    phoneIcon: cupertino.CupertinoIcons.number,
                    value: provider.episodeOffsetEnabled,
                    onChanged: provider.setEpisodeOffsetEnabled,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile.toggle(
                  title: '文件搜索',
                  subtitle: '在 WebDAV 页面显示搜索按钮',
                  icon: Icons.search_outlined,
                  phoneIcon: cupertino.CupertinoIcons.search,
                  value: provider.enableSearch,
                  onChanged: provider.setEnableSearch,
                ),
                if (provider.enableSearch) ...[
                  AdaptiveSettingsTile<WebDAVSearchScope>.dropdown(
                    title: '搜索范围',
                    subtitle: provider.searchScope.description,
                    icon: Icons.travel_explore_outlined,
                    phoneIcon: cupertino.CupertinoIcons.search,
                    items: WebDAVSearchScope.values
                        .map(
                          (scope) => DropdownMenuItemData<WebDAVSearchScope>(
                            title: scope.displayName,
                            value: scope,
                            isSelected: scope == provider.searchScope,
                            description: scope.description,
                          ),
                        )
                        .toList(),
                    onChanged: provider.setSearchScope,
                  ),
                  if (_usesSearchDepth(provider.searchScope))
                    AdaptiveSettingsTile.slider(
                      title: '层级限制',
                      subtitle: '当前目录 + 子目录或全局搜索时生效',
                      icon: Icons.account_tree_outlined,
                      phoneIcon: cupertino.CupertinoIcons.layers_alt,
                      value: provider.searchDepthLimit.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      labelFormatter: (value) => '${value.round()} 层',
                      onChanged: (value) =>
                          provider.setSearchDepthLimit(value.round()),
                    ),
                  AdaptiveSettingsTile.toggle(
                    title: '搜索文件夹',
                    subtitle: '搜索结果包含文件夹',
                    icon: Icons.folder_outlined,
                    phoneIcon: cupertino.CupertinoIcons.folder,
                    value: provider.searchTargets
                        .contains(WebDAVSearchTarget.folder),
                    onChanged: (_) =>
                        provider.toggleSearchTarget(WebDAVSearchTarget.folder),
                  ),
                  AdaptiveSettingsTile.toggle(
                    title: '搜索视频文件',
                    subtitle: '搜索结果包含视频文件',
                    icon: Icons.video_file_outlined,
                    phoneIcon: cupertino.CupertinoIcons.film,
                    value: provider.searchTargets
                        .contains(WebDAVSearchTarget.video),
                    onChanged: (_) =>
                        provider.toggleSearchTarget(WebDAVSearchTarget.video),
                  ),
                  AdaptiveSettingsTile<WebDAVSearchTimeout>.dropdown(
                    title: '搜索超时',
                    subtitle: '达到时间限制时停止搜索',
                    icon: Icons.timer_outlined,
                    phoneIcon: cupertino.CupertinoIcons.timer,
                    items: WebDAVSearchTimeout.values
                        .map(
                          (timeout) =>
                              DropdownMenuItemData<WebDAVSearchTimeout>(
                            title: timeout.displayName,
                            value: timeout,
                            isSelected: timeout == provider.searchTimeout,
                          ),
                        )
                        .toList(),
                    onChanged: provider.setSearchTimeout,
                  ),
                  AdaptiveSettingsTile.slider(
                    title: '请求间隔',
                    subtitle: '防止请求过快被服务器限制，0 表示无延迟',
                    icon: Icons.speed_outlined,
                    phoneIcon: cupertino.CupertinoIcons.speedometer,
                    value: provider.searchRequestInterval.toDouble(),
                    min: 0,
                    max: 1000,
                    divisions: 20,
                    labelFormatter: (value) => '${value.round()} ms',
                    onChanged: (value) =>
                        provider.setSearchRequestInterval(value.round()),
                  ),
                  AdaptiveSettingsTile.slider(
                    title: '最大结果数',
                    subtitle: '搜索结果达到上限时自动停止',
                    icon: Icons.format_list_numbered,
                    phoneIcon: cupertino.CupertinoIcons.number,
                    value: provider.searchMaxResults.toDouble(),
                    min: 50,
                    max: 2000,
                    divisions: 39,
                    labelFormatter: (value) => value.round().toString(),
                    onChanged: (value) =>
                        provider.setSearchMaxResults(value.round()),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile.card(
                  title: '重置所有设置',
                  subtitle: '恢复 WebDAV 快捷入口、排序、自动识别和搜索参数为默认值',
                  icon: Icons.restart_alt,
                  phoneIcon: cupertino.CupertinoIcons.refresh,
                  isDestructive: true,
                  onTap: () async {
                    await provider.resetSettings();
                    if (!context.mounted) return;
                    AdaptiveSnackBar.show(
                      context,
                      message: 'WebDAV 快捷设置已重置',
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  List<DropdownMenuItemData<String>> _serverItems(
    List<WebDAVConnection> connections,
    WebDAVQuickAccessProvider provider,
  ) {
    return connections
        .map(
          (connection) => DropdownMenuItemData<String>(
            title: connection.name,
            value: connection.name,
            isSelected: connection.name == provider.defaultServerName,
            description: connection.url,
          ),
        )
        .toList();
  }

  List<DropdownMenuItemData<String>> _seasonPatternItems(String current) {
    const presets = ['Season*', 'Season ??', 'S*', 'Disc*'];
    final values = <String>[...presets];
    if (current.isNotEmpty && !values.contains(current)) {
      values.add(current);
    }
    return values
        .map(
          (pattern) => DropdownMenuItemData<String>(
            title: pattern == current && !presets.contains(pattern)
                ? '自定义：$pattern'
                : pattern,
            value: pattern,
            isSelected: pattern == current,
          ),
        )
        .toList();
  }

  String _defaultHomeSubtitle(WebDAVQuickAccessProvider provider) {
    if (provider.defaultHomeTab == WebDAVQuickAccessProvider.tabWebDAV &&
        !provider.showWebDAVTab) {
      return 'WebDAV Tab 未开启时会自动回落到首页';
    }
    return '打开应用时默认进入的页面';
  }

  bool _usesSearchDepth(WebDAVSearchScope scope) {
    return scope == WebDAVSearchScope.currentWithDepth ||
        scope == WebDAVSearchScope.global;
  }

  Future<void> _editText({
    required String title,
    required String initialValue,
    required String hintText,
    required Future<void> Function(String value) onSaved,
    String? helperText,
    String? fallbackValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await BlurDialog.show<String>(
      context: context,
      title: title,
      contentWidget: TextField(
        controller: controller,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: hintText,
          helperText: helperText,
        ),
      ),
      actions: [
        Builder(
          builder: (dialogContext) {
            return AdaptiveSettingsActionButton(
              label: '取消',
              onPressed: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
        Builder(
          builder: (dialogContext) {
            return AdaptiveSettingsActionButton(
              label: '保存',
              primary: true,
              onPressed: () {
                final value = controller.text.trim();
                Navigator.of(dialogContext).pop(
                  value.isEmpty ? fallbackValue : value,
                );
              },
            );
          },
        ),
      ],
    );
    controller.dispose();

    if (result == null) {
      return;
    }
    await onSaved(result);
  }
}
