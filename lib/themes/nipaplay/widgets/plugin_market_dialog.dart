import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/widgets/adaptive_markdown.dart';
import 'package:nipaplay/utils/github_accel_resolver.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

const String _pluginsIndexUrl =
    'https://raw.githubusercontent.com/AimesSoft/Nipaplay-plugins/refs/heads/main/plugins.json';

const String _repoBaseUrl =
    'https://raw.githubusercontent.com/AimesSoft/Nipaplay-plugins/refs/heads/main';

const String _pluginsIndexUrlForProxy =
    'https://github.com/AimesSoft/Nipaplay-plugins/blob/main/plugins.json';

const String _repoBaseUrlForProxy =
    'https://github.com/AimesSoft/Nipaplay-plugins/blob/main';

const String _readmeBaseUrl = '$_repoBaseUrl/plugins';

class PluginMarketDialog extends StatefulWidget {
  const PluginMarketDialog({super.key});

  static Future<void> show(BuildContext context) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<void>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: const PluginMarketDialog(),
    );
  }

  @override
  State<PluginMarketDialog> createState() => _PluginMarketDialogState();
}

class _PluginMarketDialogState extends State<PluginMarketDialog> {
  static Color get _accentColor => AppAccentColors.current;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Future<String> _applyProxyIfNeeded(
      String rawUrl, String proxyUrl, String? proxy) async {
    if (proxy == null || proxy.trim().isEmpty) {
      return await GithubAccelResolver.resolveFirstReachable(rawUrl) ?? rawUrl;
    }
    final normalizedProxy = proxy.endsWith('/') ? proxy : '$proxy/';
    return '$normalizedProxy$proxyUrl';
  }

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  List<_PluginInfo> _plugins = [];
  List<_PluginInfo> _filteredPlugins = [];

  _PluginInfo? _selectedPlugin;
  bool _showReadme = false;
  String? _readmeContent;
  bool _isLoadingReadme = false;

  String _currentAppVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadPlugins();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _currentAppVersion = info.version;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPlugins() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      final proxyUrl = settingsProvider.githubProxyUrl;
      final url = await _applyProxyIfNeeded(
          _pluginsIndexUrl, _pluginsIndexUrlForProxy, proxyUrl);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final dynamic jsonData = json.decode(response.body);
        List<dynamic> data;
        if (jsonData is List) {
          data = jsonData;
        } else if (jsonData is Map) {
          if (jsonData.containsKey('plugins')) {
            data = jsonData['plugins'] as List;
          } else if (jsonData.containsKey('data')) {
            data = jsonData['data'] as List;
          } else {
            data = [];
          }
        } else {
          data = [];
        }
        setState(() {
          _plugins = data.map((item) => _PluginInfo.fromJson(item)).toList();
          _filteredPlugins = _plugins;
        });
        _syncInstalledStatus();
      } else {
        setState(() {
          _errorMessage = '加载插件列表失败: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '网络错误: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _refreshPlugins() async {
    if (_isLoading || _isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    await _loadPlugins();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredPlugins = _plugins;
      });
    } else {
      setState(() {
        _filteredPlugins = _plugins.where((plugin) {
          return plugin.name.toLowerCase().contains(query) ||
              plugin.description.toLowerCase().contains(query) ||
              plugin.author.toLowerCase().contains(query) ||
              plugin.tags.any((tag) => tag.toLowerCase().contains(query));
        }).toList();
      });
    }
  }

  bool _isVersionCompatible(String minHostVersion) {
    return _compareVersions(_currentAppVersion, minHostVersion) >= 0;
  }

  int _compareVersions(String version1, String version2) {
    final parts1 =
        version1.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final parts2 =
        version2.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final length =
        parts1.length > parts2.length ? parts1.length : parts2.length;

    for (int i = 0; i < length; i++) {
      final v1 = i < parts1.length ? parts1[i] : 0;
      final v2 = i < parts2.length ? parts2[i] : 0;
      if (v1 > v2) return 1;
      if (v1 < v2) return -1;
    }
    return 0;
  }

  void _syncInstalledStatus() {
    final pluginService = Provider.of<PluginService>(context, listen: false);
    final index = pluginService.pluginIndex;

    // 构建 remoteId → (localId, version) 的映射，支持前缀匹配
    final remoteToLocal = <String, (String, String)>{};
    for (final entry in index.entries) {
      final localId = entry.key;
      final version = entry.value.version;
      remoteToLocal[localId] = (localId, version);
      final dotIndex = localId.indexOf('.');
      if (dotIndex >= 0 && dotIndex < localId.length - 1) {
        remoteToLocal[localId.substring(dotIndex + 1)] = (localId, version);
      }
    }

    setState(() {
      for (final plugin in _plugins) {
        final match = remoteToLocal[plugin.id];
        plugin.isInstalled = match != null;
        plugin.localId = match?.$1;
        plugin.localVersion = match?.$2;
      }
    });
  }

  Future<void> _showPluginReadme(_PluginInfo plugin) async {
    setState(() {
      _selectedPlugin = plugin;
      _showReadme = true;
      _readmeContent = null;
      _isLoadingReadme = true;
    });

    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final proxyUrl = settingsProvider.githubProxyUrl;
    final rawReadmeUrl = '$_readmeBaseUrl/${plugin.id}/README.md';
    final proxyReadmeUrl =
        '$_repoBaseUrlForProxy/plugins/${plugin.id}/README.md';
    final url =
        await _applyProxyIfNeeded(rawReadmeUrl, proxyReadmeUrl, proxyUrl);

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() {
          _readmeContent = response.body;
        });
      } else {
        setState(() {
          _readmeContent = '暂无文档';
        });
      }
    } catch (e) {
      setState(() {
        _readmeContent = '文档加载失败: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoadingReadme = false;
      });
    }
  }

  void _closeReadme() {
    setState(() {
      _showReadme = false;
      _selectedPlugin = null;
      _readmeContent = null;
    });
  }

  Future<void> _installPlugin(_PluginInfo plugin) async {
    if (!_isVersionCompatible(plugin.minHostVersion)) {
      BlurSnackBar.show(context,
          '当前应用版本$_currentAppVersion低于插件要求的最低版本${plugin.minHostVersion}');
      return;
    }

    if (plugin.downloadUrl.isEmpty) {
      BlurSnackBar.show(context, '该插件暂无下载链接');
      return;
    }

    setState(() {
      plugin.isInstalling = true;
    });

    try {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      final proxyUrl = settingsProvider.githubProxyUrl;
      final url = await _applyProxyIfNeeded(
          plugin.downloadUrl, plugin.proxyDownloadUrl, proxyUrl);
      final response = await http.get(Uri.parse(url));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final pluginService =
            Provider.of<PluginService>(context, listen: false);
        final wasInstalled = plugin.isInstalled;
        await pluginService.importPluginFromContent(response.body,
            updateForId: plugin.localId);
        if (!mounted) return;
        plugin.isInstalled = true;
        plugin.localVersion = plugin.version;
        plugin.localId = plugin.id;
        BlurSnackBar.show(context, wasInstalled ? '插件更新成功' : '插件安装成功');
      } else {
        BlurSnackBar.show(context, '下载插件失败: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '安装错误: $e');
    } finally {
      if (mounted) {
        setState(() {
          plugin.isInstalling = false;
        });
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.storefront_outline, size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '插件市场',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    '发现更多扩展功能',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Tooltip(
                message: '刷新',
                child: HoverScaleTextButton(
                  onPressed: _isLoading || _isRefreshing
                      ? null
                      : () => _refreshPlugins(),
                  padding: const EdgeInsets.all(8),
                  hoverScale: 1.16,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: _isRefreshing
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : const Icon(Ionicons.refresh_outline, size: 24),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSearchBar(context),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3A) : Colors.grey[200]!,
        ),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          prefixIcon: Icon(Ionicons.search_outline, color: Colors.grey[400]),
          hintText: '搜索插件',
          hintStyle: TextStyle(color: Colors.grey[400]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Ionicons.cloud_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            HoverScaleTextButton(
              text: '重新加载',
              onPressed: _loadPlugins,
              idleColor: _accentColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ],
        ),
      );
    }

    if (_filteredPlugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Ionicons.search_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty ? '未找到匹配的插件' : '暂无插件',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: _filteredPlugins.length,
      itemBuilder: (context, index) =>
          _buildPluginCard(_filteredPlugins[index]),
    );
  }

  Widget _buildPluginCard(_PluginInfo plugin) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVersionCompatible = _isVersionCompatible(plugin.minHostVersion);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3A) : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plugin.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              plugin.version,
                              style: TextStyle(
                                fontSize: 11,
                                color: _accentColor,
                              ),
                            ),
                          ),
                          if (plugin.isInstalled)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '已安装',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          if (!isVersionCompatible)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '版本不兼容',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            plugin.author,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[500],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '最低版本: ${plugin.minHostVersion}',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              plugin.description,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[300] : Colors.grey[600],
                height: 1.4,
              ),
            ),
            if (plugin.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: plugin.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                HoverScaleTextButton(
                  onPressed: () => _showPluginReadme(plugin),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Ionicons.document_outline, size: 16),
                      SizedBox(width: 6),
                      Text('查看文档'),
                    ],
                  ),
                ),
                const Spacer(),
                _buildActionButtons(plugin),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(_PluginInfo plugin) {
    final isVersionCompatible = _isVersionCompatible(plugin.minHostVersion);

    if (plugin.isInstalling) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (plugin.isInstalled) {
      final hasUpdate = plugin.localVersion != null &&
          _compareVersions(plugin.version, plugin.localVersion!) > 0;
      if (hasUpdate) {
        return HoverScaleTextButton(
          text: '更新',
          onPressed: () => _installPlugin(plugin),
          idleColor: _accentColor,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        );
      }
      return HoverScaleTextButton(
        text: '已安装',
        onPressed: () {
          BlurSnackBar.show(context, '该插件已安装');
        },
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      );
    }

    if (!isVersionCompatible) {
      return HoverScaleTextButton(
        text: '版本不兼容',
        onPressed: null,
        idleColor: Colors.grey[600],
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      );
    }

    return HoverScaleTextButton(
      text: '安装',
      onPressed: () => _installPlugin(plugin),
      idleColor: _accentColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    );
  }

  Widget _buildReadmeView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Row(
            children: [
              HoverScaleTextButton(
                onPressed: _closeReadme,
                padding: const EdgeInsets.all(8),
                hoverScale: 1.16,
                child: const Icon(Ionicons.chevron_back_outline, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedPlugin?.name ?? '文档',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'README.md',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _isLoadingReadme
                ? const Center(child: CircularProgressIndicator())
                : _readmeContent != null
                    ? SingleChildScrollView(
                        child: AdaptiveMarkdown(
                          data: _readmeContent!,
                          brightness:
                              isDark ? Brightness.dark : Brightness.light,
                          baseTextStyle: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                          linkColor: _accentColor,
                        ),
                      )
                    : const Center(
                        child: Text('暂无文档'),
                      ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return NipaplayWindowScaffold(
      maxWidth: 800,
      maxHeightFactor: 0.85,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: _showReadme
          ? _buildReadmeView(context)
          : Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: _buildContent(context),
                ),
              ],
            ),
    );
  }
}

class _PluginInfo {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final String minHostVersion;
  final String downloadUrl;
  final String proxyDownloadUrl;
  final List<String> tags;
  bool isInstalled = false;
  bool isInstalling = false;
  String? localVersion;
  String? localId;

  _PluginInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.minHostVersion,
    required this.downloadUrl,
    required this.proxyDownloadUrl,
    required this.tags,
  });

  factory _PluginInfo.fromJson(Map<String, dynamic> json) {
    final file = json['file'] as String? ?? '';
    return _PluginInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      author: json['author'] ?? '',
      version: json['version'] ?? '1.0.0',
      minHostVersion: json['minHostVersion'] ?? '1.0.0',
      downloadUrl: file.isNotEmpty ? '$_repoBaseUrl/$file' : '',
      proxyDownloadUrl: file.isNotEmpty ? '$_repoBaseUrlForProxy/$file' : '',
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              [],
    );
  }
}
