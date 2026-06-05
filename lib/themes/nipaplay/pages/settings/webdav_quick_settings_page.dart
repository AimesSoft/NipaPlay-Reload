import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

/// WebDAV 快捷访问设置页面
class WebDAVQuickSettingsPage extends StatefulWidget {
  const WebDAVQuickSettingsPage({super.key});

  @override
  State<WebDAVQuickSettingsPage> createState() =>
      _WebDAVQuickSettingsPageState();
}

class _WebDAVQuickSettingsPageState extends State<WebDAVQuickSettingsPage> {
  late TextEditingController _patternController;
  late TextEditingController _tmdbPatternController;

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController();
    _tmdbPatternController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider =
          Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
      provider.loadSettings().then((_) {
        _patternController.text = provider.bgmIdMatchPattern;
        _tmdbPatternController.text = provider.tmdbIdMatchPattern;
      });
    });
  }

  @override
  void dispose() {
    _patternController.dispose();
    _tmdbPatternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = colorScheme.onSurface;
    final secondaryTextColor = textColor.withOpacity(0.7);
    final cardColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
    final accentColor = AppAccentColors.current;

    return Consumer<WebDAVQuickAccessProvider>(
      builder: (context, provider, child) {
        final connections = WebDAVService.instance.connections;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 说明文字
              Text(
                '配置底部 WebDAV 快捷 Tab，可以快速访问 WebDAV 服务器中的视频文件。',
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 24),

              // 开关：显示 WebDAV Tab
              _buildSettingsCard(
                cardColor: cardColor,
                child: ListTile(
                  leading: Icon(Ionicons.cloud_outline, color: textColor.withOpacity(0.7)),
                  title: Text(
                    '显示 WebDAV Tab',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '在底部导航栏显示 WebDAV 快捷入口',
                    style: TextStyle(
                      color: secondaryTextColor,
                    ),
                  ),
                  trailing: FluentSettingsSwitch(
                    value: provider.showWebDAVTab,
                    onChanged: (value) {
                      provider.setShowWebDAVTab(value);
                    },
                  ),
                  onTap: () {
                    provider.setShowWebDAVTab(!provider.showWebDAVTab);
                  },
                ),
              ),

              SizedBox(height: 16),

              // 默认主页 Tab 设置
              _buildSettingsCard(
                cardColor: cardColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '默认主页',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...provider.materialAvailableTabs.map((tabName) {
                      final isSelected = tabName == provider.defaultHomeTab;
                      return RadioListTile<String>(
                        title: Text(
                          WebDAVQuickAccessProvider.getTabDisplayName(tabName),
                          style: TextStyle(color: textColor),
                        ),
                        subtitle: Text(
                          tabName == WebDAVQuickAccessProvider.tabWebDAV
                              ? '打开应用时直接进入 WebDAV 文件浏览'
                              : '打开应用时直接进入此页面',
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                        value: tabName,
                        groupValue: provider.effectiveDefaultHomeTab,
                        activeColor: accentColor,
                        selected: isSelected,
                        onChanged: (value) {
                          if (value != null) {
                            provider.setDefaultHomeTab(value);
                          }
                        },
                      );
                    }),
                    if (provider.defaultHomeTab ==
                            WebDAVQuickAccessProvider.tabWebDAV &&
                        !provider.showWebDAVTab)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Text(
                          '⚠️ 当前已选择 WebDAV 为默认主页，但 WebDAV Tab 未开启，将自动回落到首页',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // 只有在开启 Tab 显示且有服务器连接时才显示以下设置
              if (provider.showWebDAVTab && connections.isNotEmpty) ...[
                // 选择默认服务器
                _buildSettingsCard(
                  cardColor: cardColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '默认服务器',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...connections.map((connection) {
                        final isSelected =
                            connection.name == provider.defaultServerName;
                        return RadioListTile<String>(
                          title: Text(
                            connection.name,
                            style: TextStyle(color: textColor),
                          ),
                          subtitle: Text(
                            connection.url,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                          value: connection.name,
                          groupValue: provider.defaultServerName,
                          activeColor: accentColor,
                          selected: isSelected,
                          onChanged: (value) {
                            if (value != null) {
                              provider.setDefaultServerName(value);
                            }
                          },
                        );
                      }),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // 设置默认目录
                _buildSettingsCard(
                  cardColor: cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '默认目录',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: TextEditingController(
                            text: provider.defaultDirectory,
                          ),
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: '例如: /视频/动画',
                            hintStyle: TextStyle(color: secondaryTextColor),
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: secondaryTextColor.withOpacity(0.3),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: secondaryTextColor.withOpacity(0.3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: accentColor),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.refresh),
                              color: secondaryTextColor,
                              onPressed: () {
                                // 重置为根目录
                                provider.setDefaultDirectory('/');
                              },
                            ),
                          ),
                          onSubmitted: (value) {
                            provider.setDefaultDirectory(value);
                          },
                        ),
                        SizedBox(height: 8),
                        Text(
                          '点击 WebDAV Tab 时将直接打开此目录',
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // 排序设置
                _buildSettingsCard(
                  cardColor: cardColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '文件排序',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...WebDAVSortPreset.values.map((preset) {
                        final isSelected = preset == provider.sortPreset;
                        return RadioListTile<WebDAVSortPreset>(
                          title: Text(
                            preset.displayName,
                            style: TextStyle(color: textColor),
                          ),
                          subtitle: Text(
                            preset.description,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 11,
                            ),
                          ),
                          value: preset,
                          groupValue: provider.sortPreset,
                          activeColor: accentColor,
                          selected: isSelected,
                          onChanged: (value) {
                            if (value != null) {
                              provider.setSortPreset(value);
                            }
                          },
                        );
                      }),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // 路径面包屑导航开关
                _buildSettingsCard(
                  cardColor: cardColor,
                  child: ListTile(
                    leading: Icon(Ionicons.folder_outline, color: textColor.withOpacity(0.7)),
                    title: Text(
                      '显示路径导航',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '在顶部显示可点击的路径面包屑导航',
                      style: TextStyle(
                        color: secondaryTextColor,
                      ),
                    ),
                    trailing: FluentSettingsSwitch(
                      value: provider.showPathBreadcrumb,
                      onChanged: (value) {
                        provider.setShowPathBreadcrumb(value);
                      },
                    ),
                    onTap: () {
                      provider.setShowPathBreadcrumb(!provider.showPathBreadcrumb);
                    },
                  ),
                ),

                SizedBox(height: 16),

                // 自动进入 Season 文件夹设置
                _buildSettingsCard(
                  cardColor: cardColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: Icon(Ionicons.folder_open_outline, color: textColor.withOpacity(0.7)),
                        title: Text(
                          '自动进入 Season 文件夹',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '打开文件夹时自动进入匹配的子文件夹',
                          style: TextStyle(
                            color: secondaryTextColor,
                          ),
                        ),
                        trailing: FluentSettingsSwitch(
                          value: provider.autoEnterSeasonFolder,
                          onChanged: (value) {
                            provider.setAutoEnterSeasonFolder(value);
                          },
                        ),
                        onTap: () {
                          provider.setAutoEnterSeasonFolder(!provider.autoEnterSeasonFolder);
                        },
                      ),
                      if (provider.autoEnterSeasonFolder) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '匹配模式',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '支持通配符：* 匹配任意字符，? 匹配单个字符',
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 12),
                              TextField(
                                controller: TextEditingController(
                                  text: provider.seasonFolderPattern,
                                ),
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  hintText: '例如: Season*、Season ??、S*',
                                  hintStyle:
                                      TextStyle(color: secondaryTextColor),
                                  filled: true,
                                  fillColor: cardColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color:
                                          secondaryTextColor.withOpacity(0.3),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color:
                                          secondaryTextColor.withOpacity(0.3),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: accentColor),
                                  ),
                                ),
                                onSubmitted: (value) {
                                  provider.setSeasonFolderPattern(value);
                                },
                              ),
                              SizedBox(height: 12),
                              // 预设模式
                              Wrap(
                                spacing: 8,
                                children: [
                                  _buildPresetChip(
                                    'Season*',
                                    provider,
                                    accentColor,
                                    secondaryTextColor,
                                  ),
                                  _buildPresetChip(
                                    'Season ??',
                                    provider,
                                    accentColor,
                                    secondaryTextColor,
                                  ),
                                  _buildPresetChip(
                                    'S*',
                                    provider,
                                    accentColor,
                                    secondaryTextColor,
                                  ),
                                  _buildPresetChip(
                                    'Disc*',
                                    provider,
                                    accentColor,
                                    secondaryTextColor,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

            SizedBox(height: 16),

            // bgmid 快速匹配开关
            _buildSettingsCard(
              cardColor: cardColor,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Ionicons.flash_outline, color: textColor.withOpacity(0.7)),
                    title: Text(
                      'bgmid 快速匹配',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '从 URL 中提取 bgmid，直接获取番剧信息',
                      style: TextStyle(
                        color: secondaryTextColor,
                      ),
                    ),
                    trailing: FluentSettingsSwitch(
                      value: provider.bgmIdQuickMatch,
                      onChanged: (value) {
                        provider.setBgmIdQuickMatch(value);
                      },
                    ),
                  ),
                  if (provider.bgmIdQuickMatch) ...[
                    Divider(height: 1, color: secondaryTextColor.withOpacity(0.2)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '匹配规则（正则表达式）',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '从完整 URL 中匹配 bgmid 数字，支持 bgmid=123 或 bgm-123 格式',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 11,
                            ),
                          ),
                          SizedBox(height: 8),
                          TextField(
                            controller: _patternController,
                            style: TextStyle(color: textColor, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'bgm(id)?[=-](\\d+)',
                              hintStyle: TextStyle(color: secondaryTextColor.withOpacity(0.5)),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: secondaryTextColor.withOpacity(0.3)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: accentColor),
                              ),
                              isDense: true,
                            ),
                            onSubmitted: (value) {
                              if (value.isNotEmpty) {
                                provider.setBgmIdMatchPattern(value);
                              }
                            },
                          ),
                          SizedBox(height: 4),
                          Text(
                            '最后一个捕获组应为数字，如 bgmid=(\\d+) 或 bgm-(\\d+)',
                            style: TextStyle(
                              color: secondaryTextColor.withOpacity(0.7),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            SizedBox(height: 16),

            // tmdbId 快速匹配开关
            _buildSettingsCard(
              cardColor: cardColor,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Ionicons.film_outline, color: textColor.withOpacity(0.7)),
                    title: Text(
                      'tmdbId 快速匹配',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '从 URL 中提取 tmdbId，通过 TMDB ID 直接获取番剧信息',
                      style: TextStyle(
                        color: secondaryTextColor,
                      ),
                    ),
                    trailing: FluentSettingsSwitch(
                      value: provider.tmdbIdQuickMatch,
                      onChanged: (value) {
                        provider.setTmdbIdQuickMatch(value);
                      },
                    ),
                  ),
                  if (provider.tmdbIdQuickMatch) ...[
                    Divider(height: 1, color: secondaryTextColor.withOpacity(0.2)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '匹配规则（正则表达式）',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '从完整 URL 中匹配 tmdbId 数字，支持 tmdbid=123 或 tmdb-123 格式',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 11,
                            ),
                          ),
                          SizedBox(height: 8),
                          TextField(
                            controller: _tmdbPatternController,
                            style: TextStyle(color: textColor, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'tmdb(id)?[=-](\\d+)',
                              hintStyle: TextStyle(color: secondaryTextColor.withOpacity(0.5)),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: secondaryTextColor.withOpacity(0.3)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: accentColor),
                              ),
                              isDense: true,
                            ),
                            onSubmitted: (value) {
                              if (value.isNotEmpty) {
                                provider.setTmdbIdMatchPattern(value);
                              }
                            },
                          ),
                          SizedBox(height: 4),
                          Text(
                            '最后一个捕获组应为数字，如 tmdbid=(\\d+) 或 tmdb-(\\d+)',
                            style: TextStyle(
                              color: secondaryTextColor.withOpacity(0.7),
                              fontSize: 10,
                            ),
                          ),
                          SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '匹配弹幕自动剧集偏移（实验中）',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '自动计算跨季剧集编号偏移量，修复 SxEx 季内编号与弹幕库绝对编号不匹配的问题',
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 11,
                              ),
                            ),
                            trailing: FluentSettingsSwitch(
                              value: provider.episodeOffsetEnabled,
                              onChanged: (value) {
                                provider.setEpisodeOffsetEnabled(value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            SizedBox(height: 16),

            // 搜索功能配置
            _buildSettingsCard(
              cardColor: cardColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 搜索功能总开关
                  ListTile(
                    leading: Icon(Ionicons.search_outline, color: textColor.withOpacity(0.7)),
                    title: Text(
                      '文件搜索',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '在 WebDAV 页面显示搜索按钮',
                      style: TextStyle(
                        color: secondaryTextColor,
                      ),
                    ),
                    trailing: FluentSettingsSwitch(
                      value: provider.enableSearch,
                      onChanged: (value) {
                        provider.setEnableSearch(value);
                      },
                    ),
                    onTap: () {
                      provider.setEnableSearch(!provider.enableSearch);
                    },
                  ),

                  // 搜索详细配置（仅在开启搜索时显示）
                  if (provider.enableSearch) ...[
                    Divider(height: 1, color: secondaryTextColor.withOpacity(0.2)),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 搜索范围
                          _buildSearchSectionTitle('搜索范围', textColor),
                          SizedBox(height: 8),
                          ...WebDAVSearchScope.values.map((scope) =>
                            RadioListTile<WebDAVSearchScope>(
                              title: Text(
                                scope.displayName,
                                style: TextStyle(color: textColor, fontSize: 14),
                              ),
                              subtitle: Text(
                                scope.description,
                                style: TextStyle(color: secondaryTextColor, fontSize: 11),
                              ),
                              value: scope,
                              groupValue: provider.searchScope,
                              activeColor: accentColor,
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onChanged: (value) {
                                if (value != null) {
                                  provider.setSearchScope(value);
                                }
                              },
                            ),
                          ),

                          // 层级限制（当前目录+子目录或全局搜索时显示）
                          if (provider.searchScope == WebDAVSearchScope.currentWithDepth ||
                              provider.searchScope == WebDAVSearchScope.global) ...[
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Text(
                                  '层级限制',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Spacer(),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: accentColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${provider.searchDepthLimit} 层',
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Slider(
                              value: provider.searchDepthLimit.toDouble(),
                              min: 1,
                              max: 10,
                              divisions: 9,
                              activeColor: accentColor,
                              onChanged: (value) {
                                provider.setSearchDepthLimit(value.round());
                              },
                            ),
                          ],

                          SizedBox(height: 16),

                          // 搜索目标（多选）
                          _buildSearchSectionTitle('搜索目标（可多选）', textColor),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: WebDAVSearchTarget.values.map((target) {
                              final isSelected = provider.searchTargets.contains(target);
                              return FilterChip(
                                label: Text(target.displayName),
                                selected: isSelected,
                                selectedColor: accentColor.withOpacity(0.2),
                                checkmarkColor: accentColor,
                                labelStyle: TextStyle(
                                  color: isSelected ? accentColor : textColor,
                                  fontSize: 13,
                                ),
                                side: BorderSide(
                                  color: isSelected ? accentColor : secondaryTextColor.withOpacity(0.3),
                                ),
                                onSelected: (selected) {
                                  provider.toggleSearchTarget(target);
                                },
                              );
                            }).toList(),
                          ),

                          SizedBox(height: 16),

                          // 搜索超时
                          _buildSearchSectionTitle('搜索超时', textColor),
                          SizedBox(height: 8),
                          ...WebDAVSearchTimeout.values.map((timeout) =>
                            RadioListTile<WebDAVSearchTimeout>(
                              title: Text(
                                timeout.displayName,
                                style: TextStyle(color: textColor, fontSize: 14),
                              ),
                              value: timeout,
                              groupValue: provider.searchTimeout,
                              activeColor: accentColor,
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onChanged: (value) {
                                if (value != null) {
                                  provider.setSearchTimeout(value);
                                }
                              },
                            ),
                          ),

                          SizedBox(height: 16),

                          // 请求间隔
                          Row(
                            children: [
                              Text(
                                '请求间隔',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Spacer(),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${provider.searchRequestInterval} ms',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            '防止请求过快被服务器限制，0 表示无延迟',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 11,
                            ),
                          ),
                          SizedBox(height: 8),
                          Slider(
                            value: provider.searchRequestInterval.toDouble(),
                            min: 0,
                            max: 1000,
                            divisions: 20,
                            activeColor: accentColor,
                            onChanged: (value) {
                              provider.setSearchRequestInterval(value.round());
                            },
                          ),

                          SizedBox(height: 16),

                          // 最大结果数
                          Row(
                            children: [
                              Text(
                                '最大结果数',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Spacer(),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${provider.searchMaxResults}',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            '搜索结果达到上限时自动停止',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 11,
                            ),
                          ),
                          SizedBox(height: 8),
                          Slider(
                            value: provider.searchMaxResults.toDouble(),
                            min: 50,
                            max: 2000,
                            divisions: 39,
                            activeColor: accentColor,
                            onChanged: (value) {
                              provider.setSearchMaxResults(value.round());
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 没有服务器连接时的提示
              if (provider.showWebDAVTab && connections.isEmpty)
                _buildSettingsCard(
                  cardColor: cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Ionicons.cloud_offline_outline,
                          size: 48,
                          color: secondaryTextColor,
                        ),
                        SizedBox(height: 16),
                        Text(
                          '没有配置 WebDAV 服务器',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '请先在「远程媒体库」设置中添加 WebDAV 服务器',
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              SizedBox(height: 32),

              // 重置按钮
              Center(
                child: TextButton.icon(
                  icon: Icon(Icons.refresh),
                  label: const Text('重置所有设置'),
                  style: TextButton.styleFrom(
                    foregroundColor: secondaryTextColor,
                  ),
                  onPressed: () {
                    provider.resetSettings();
                    BlurSnackBar.show(context, 'WebDAV 快捷设置已重置');
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsCard({
    required Color cardColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }

  Widget _buildPresetChip(
    String pattern,
    WebDAVQuickAccessProvider provider,
    Color accentColor,
    Color secondaryTextColor,
  ) {
    final isSelected = provider.seasonFolderPattern == pattern;
    return ActionChip(
      label: Text(
        pattern,
        style: TextStyle(
          color: isSelected ? accentColor : secondaryTextColor,
          fontSize: 13,
        ),
      ),
      backgroundColor: isSelected ? accentColor.withOpacity(0.1) : null,
      side: BorderSide(
        color: isSelected ? accentColor : secondaryTextColor.withOpacity(0.3),
      ),
      onPressed: () {
        provider.setSeasonFolderPattern(pattern);
      },
    );
  }

  Widget _buildSearchSectionTitle(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
