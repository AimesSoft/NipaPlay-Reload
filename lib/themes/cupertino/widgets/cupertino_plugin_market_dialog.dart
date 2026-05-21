import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/widgets/adaptive_markdown.dart';
import 'package:http/http.dart' as http;
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

class CupertinoPluginMarketDialog extends StatefulWidget {
  const CupertinoPluginMarketDialog({super.key});

  static Future<void> show(BuildContext context) {
    return CupertinoBottomSheet.show<void>(
      context: context,
      title: '插件市场',
      heightRatio: 0.88,
      child: const CupertinoPluginMarketDialog(),
    );
  }

  @override
  State<CupertinoPluginMarketDialog> createState() =>
      _CupertinoPluginMarketDialogState();
}

class _CupertinoPluginMarketDialogState
    extends State<CupertinoPluginMarketDialog> {
  final TextEditingController _searchController = TextEditingController();

  String _applyProxyIfNeeded(String rawUrl, String proxyUrl, String? proxy) {
    if (proxy == null || proxy.isEmpty) return rawUrl;
    final normalizedProxy = proxy.endsWith('/') ? proxy : '$proxy/';
    return '$normalizedProxy$proxyUrl';
  }

  bool _isLoading = true;
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
      setState(() => _currentAppVersion = info.version);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
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
      final url = _applyProxyIfNeeded(
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
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() => _filteredPlugins = _plugins);
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
    final pluginService =
        Provider.of<PluginService>(context, listen: false);
    final index = pluginService.pluginIndex;

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
        _applyProxyIfNeeded(rawReadmeUrl, proxyReadmeUrl, proxyUrl);

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() => _readmeContent = response.body);
      } else {
        setState(() => _readmeContent = '暂无文档');
      }
    } catch (e) {
      setState(() => _readmeContent = '文档加载失败: ${e.toString()}');
    } finally {
      setState(() => _isLoadingReadme = false);
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
      AdaptiveSnackBar.show(
        context,
        message:
            '当前应用版本$_currentAppVersion低于插件要求的最低版本${plugin.minHostVersion}',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    if (plugin.downloadUrl.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: '该插件暂无下载链接',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    setState(() => plugin.isInstalling = true);

    try {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      final proxyUrl = settingsProvider.githubProxyUrl;
      final url = _applyProxyIfNeeded(
          plugin.downloadUrl, plugin.proxyDownloadUrl, proxyUrl);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (!mounted) return;
        final pluginService =
            Provider.of<PluginService>(context, listen: false);
        final wasInstalled = plugin.isInstalled;
        await pluginService.importPluginFromContent(response.body,
            updateForId: plugin.localId);
        if (!mounted) return;
        plugin.isInstalled = true;
        plugin.localVersion = plugin.version;
        plugin.localId = plugin.id;
        AdaptiveSnackBar.show(
          context,
          message: wasInstalled ? '插件更新成功' : '插件安装成功',
          type: AdaptiveSnackBarType.success,
        );
      } else {
        if (!mounted) return;
        AdaptiveSnackBar.show(
          context,
          message: '下载插件失败: ${response.statusCode}',
          type: AdaptiveSnackBarType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '安装错误: $e',
        type: AdaptiveSnackBarType.error,
      );
    } finally {
      setState(() => plugin.isInstalling = false);
    }
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: CupertinoTextField(
        controller: _searchController,
        placeholder: '搜索插件',
        prefix: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(
            CupertinoIcons.search,
            size: 18,
            color: CupertinoColors.systemGrey,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        style: TextStyle(
          color: CupertinoDynamicColor.resolve(CupertinoColors.label, context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.cloud,
                size: 48, color: CupertinoColors.systemGrey),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: CupertinoColors.systemGrey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            CupertinoButton(
              onPressed: _loadPlugins,
              child: const Text('重新加载'),
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
            const Icon(CupertinoIcons.search,
                size: 48, color: CupertinoColors.systemGrey),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty ? '未找到匹配的插件' : '暂无插件',
              style: const TextStyle(color: CupertinoColors.systemGrey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: _filteredPlugins.length,
      itemBuilder: (context, index) =>
          _buildPluginCard(_filteredPlugins[index]),
    );
  }

  Widget _buildPluginCard(_PluginInfo plugin) {
    final isVersionCompatible = _isVersionCompatible(plugin.minHostVersion);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground, context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plugin.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CupertinoTheme.of(context)
                      .primaryColor
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  plugin.version,
                  style: TextStyle(
                    fontSize: 11,
                    color: CupertinoTheme.of(context).primaryColor,
                  ),
                ),
              ),
              if (plugin.isInstalled)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '已安装',
                    style: TextStyle(
                        fontSize: 11, color: CupertinoColors.systemGreen),
                  ),
                ),
              if (!isVersionCompatible)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '版本不兼容',
                    style: TextStyle(
                        fontSize: 11, color: CupertinoColors.systemOrange),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${plugin.author}  ·  最低版本: ${plugin.minHostVersion}',
            style: const TextStyle(
                fontSize: 12, color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 8),
          Text(
            plugin.description,
            style: const TextStyle(
              fontSize: 13,
              color: CupertinoColors.systemGrey,
              height: 1.4,
            ),
          ),
          if (plugin.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: plugin.tags.map((tag) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemGrey5, context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(
                        fontSize: 11, color: CupertinoColors.systemGrey),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                onPressed: () => _showPluginReadme(plugin),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.doc_text, size: 16),
                    SizedBox(width: 4),
                    Text('查看文档', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const Spacer(),
              _buildActionButtons(plugin),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(_PluginInfo plugin) {
    final isVersionCompatible = _isVersionCompatible(plugin.minHostVersion);

    if (plugin.isInstalling) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CupertinoActivityIndicator(),
      );
    }

    if (plugin.isInstalled) {
      final hasUpdate = plugin.localVersion != null &&
          _compareVersions(plugin.version, plugin.localVersion!) > 0;
      if (hasUpdate) {
        return CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          minimumSize: const Size(0, 0),
          borderRadius: BorderRadius.circular(8),
          onPressed: () => _installPlugin(plugin),
          child:
              const Text('更新', style: TextStyle(fontSize: 14)),
        );
      }
      return const Text(
        '已安装',
        style: TextStyle(
            fontSize: 14,
            color: CupertinoColors.systemGrey),
      );
    }

    if (!isVersionCompatible) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey4,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '版本不兼容',
          style: TextStyle(fontSize: 14, color: CupertinoColors.systemGrey),
        ),
      );
    }

    return CupertinoButton.filled(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minimumSize: const Size(0, 0),
      borderRadius: BorderRadius.circular(8),
      onPressed: () => _installPlugin(plugin),
      child: const Text('安装', style: TextStyle(fontSize: 14)),
    );
  }

  Widget _buildReadmeView(BuildContext context) {
    final brightness = CupertinoTheme.of(context).brightness ?? Brightness.light;
    final isDark = brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                onPressed: _closeReadme,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.back, size: 20),
                    SizedBox(width: 2),
                    Text('返回', style: TextStyle(fontSize: 15)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedPlugin?.name ?? '文档',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Text(
                      'README.md',
                      style: TextStyle(
                          fontSize: 12, color: CupertinoColors.systemGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(
          height: 0.5,
          child: ColoredBox(color: CupertinoColors.separator),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _isLoadingReadme
                ? const Center(child: CupertinoActivityIndicator())
                : _readmeContent != null
                    ? SingleChildScrollView(
                        child: AdaptiveMarkdown(
                          data: _readmeContent!,
                          brightness: brightness,
                          baseTextStyle: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.systemGrey,
                          ),
                          linkColor: CupertinoTheme.of(context).primaryColor,
                        ),
                      )
                    : const Center(child: Text('暂无文档')),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showReadme) return _buildReadmeView(context);

    return Column(
      children: [
        _buildSearchBar(context),
        Expanded(child: _buildContent(context)),
      ],
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
      proxyDownloadUrl:
          file.isNotEmpty ? '$_repoBaseUrlForProxy/$file' : '',
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              [],
    );
  }
}
