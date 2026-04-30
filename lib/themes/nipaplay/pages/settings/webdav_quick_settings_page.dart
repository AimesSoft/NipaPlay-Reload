import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';

/// WebDAV 快捷访问设置页面
class WebDAVQuickSettingsPage extends StatefulWidget {
  const WebDAVQuickSettingsPage({super.key});

  @override
  State<WebDAVQuickSettingsPage> createState() => _WebDAVQuickSettingsPageState();
}

class _WebDAVQuickSettingsPageState extends State<WebDAVQuickSettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WebDAVQuickAccessProvider>(context, listen: false).loadSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = colorScheme.onSurface;
    final secondaryTextColor = textColor.withOpacity(0.7);
    final cardColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
    const accentColor = Color(0xFFFF2E55);

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
              const SizedBox(height: 24),

              // 开关：显示 WebDAV Tab
              _buildSettingsCard(
                cardColor: cardColor,
                child: SwitchListTile(
                  title: Text(
                    '显示 WebDAV Tab',
                    style: TextStyle(color: textColor),
                  ),
                  subtitle: Text(
                    '在底部导航栏显示 WebDAV 快捷入口',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 12,
                    ),
                  ),
                  value: provider.showWebDAVTab,
                  activeColor: accentColor,
                  onChanged: (value) {
                    provider.setShowWebDAVTab(value);
                  },
                ),
              ),

              const SizedBox(height: 16),

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
                    ...provider.availableTabs.map((tabName) {
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
                    if (provider.defaultHomeTab == WebDAVQuickAccessProvider.tabWebDAV && !provider.showWebDAVTab)
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

              const SizedBox(height: 16),

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

                const SizedBox(height: 16),

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
                        const SizedBox(height: 12),
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
                              borderSide: const BorderSide(color: accentColor),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.refresh),
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
                        const SizedBox(height: 8),
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

                const SizedBox(height: 16),

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

                const SizedBox(height: 16),

                // 路径面包屑导航开关
                _buildSettingsCard(
                  cardColor: cardColor,
                  child: SwitchListTile(
                    title: Text(
                      '显示路径导航',
                      style: TextStyle(color: textColor),
                    ),
                    subtitle: Text(
                      '在顶部显示可点击的路径面包屑导航',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 12,
                      ),
                    ),
                    value: provider.showPathBreadcrumb,
                    activeColor: accentColor,
                    onChanged: (value) {
                      provider.setShowPathBreadcrumb(value);
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // 自动进入 Season 文件夹设置
                _buildSettingsCard(
                  cardColor: cardColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: Text(
                          '自动进入 Season 文件夹',
                          style: TextStyle(color: textColor),
                        ),
                        subtitle: Text(
                          '打开文件夹时自动进入匹配的子文件夹',
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                        value: provider.autoEnterSeasonFolder,
                        activeColor: accentColor,
                        onChanged: (value) {
                          provider.setAutoEnterSeasonFolder(value);
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
                              const SizedBox(height: 8),
                              Text(
                                '支持通配符：* 匹配任意字符，? 匹配单个字符',
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: TextEditingController(
                                  text: provider.seasonFolderPattern,
                                ),
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  hintText: '例如: Season*、Season ??、S*',
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
                                    borderSide: const BorderSide(color: accentColor),
                                  ),
                                ),
                                onSubmitted: (value) {
                                  provider.setSeasonFolderPattern(value);
                                },
                              ),
                              const SizedBox(height: 12),
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
                        const SizedBox(height: 16),
                        Text(
                          '没有配置 WebDAV 服务器',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
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

              const SizedBox(height: 32),

              // 重置按钮
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.refresh),
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
      child: child,
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
}