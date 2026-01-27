import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';

class CupertinoNetworkSettingsPage extends StatefulWidget {
  const CupertinoNetworkSettingsPage({super.key});

  @override
  State<CupertinoNetworkSettingsPage> createState() =>
      _CupertinoNetworkSettingsPageState();
}

class _CupertinoNetworkSettingsPageState
    extends State<CupertinoNetworkSettingsPage> {
  String _currentServer = '';
  bool _isLoading = true;
  bool _isSavingCustom = false;
  late final TextEditingController _customServerController;

  @override
  void initState() {
    super.initState();
    _customServerController = TextEditingController();
    _loadCurrentServer();
  }

  @override
  void dispose() {
    _customServerController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentServer() async {
    final server = await NetworkSettings.getDandanplayServer();
    if (!mounted) return;
    setState(() {
      _currentServer = server;
      _isLoading = false;
      if (NetworkSettings.isCustomServer(server)) {
        _customServerController.text = server;
      } else {
        _customServerController.clear();
      }
    });
  }

  Future<void> _changeServer(String serverUrl) async {
    await NetworkSettings.setDandanplayServer(serverUrl);
    if (!mounted) return;
    setState(() {
      _currentServer = serverUrl;
      if (NetworkSettings.isCustomServer(serverUrl)) {
        _customServerController.text = serverUrl;
      } else {
        _customServerController.clear();
      }
    });

    AdaptiveSnackBar.show(
      context,
      message: '弹弹play 服务器已切换到 ${_getServerDisplayName(serverUrl)}',
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _saveCustomServer() async {
    final input = _customServerController.text.trim();
    if (input.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: '请输入服务器地址',
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }
    if (!NetworkSettings.isValidServerUrl(input)) {
      AdaptiveSnackBar.show(
        context,
        message: '服务器地址格式不正确，请以 http/https 开头',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    setState(() {
      _isSavingCustom = true;
    });

    try {
      await NetworkSettings.setDandanplayServer(input);
      final server = await NetworkSettings.getDandanplayServer();
      if (!mounted) return;
      setState(() {
        _currentServer = server;
      });
      AdaptiveSnackBar.show(
        context,
        message: '已切换到自定义服务器',
        type: AdaptiveSnackBarType.success,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingCustom = false;
        });
      }
    }
  }

  Future<void> _showServerPicker() async {
    final List<_ServerOption> options = [
      _ServerOption(
        label: '主服务器 (推荐)',
        value: NetworkSettings.primaryServer,
        description: 'api.dandanplay.net',
      ),
      _ServerOption(
        label: '备用服务器',
        value: NetworkSettings.backupServer,
        description: '139.224.252.88:16001',
      ),
    ];

    if (NetworkSettings.isCustomServer(_currentServer)) {
      options.add(
        _ServerOption(
          label: '当前自定义服务器',
          value: _currentServer,
          description: _currentServer,
        ),
      );
    }

    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('选择弹弹play 服务器'),
          actions: options
              .map(
                (option) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(context).pop(option.value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        );
      },
    );

    if (selected != null && selected != _currentServer) {
      await _changeServer(selected);
    }
  }

  String _getServerDisplayName(String serverUrl) {
    switch (serverUrl) {
      case NetworkSettings.primaryServer:
        return '主服务器';
      case NetworkSettings.backupServer:
        return '备用服务器';
      default:
        return serverUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(
        title: '网络设置',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: _isLoading
              ? const Center(child: CupertinoActivityIndicator())
              : ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
                  children: [
                    _buildServerSelectorCard(context),
                    const SizedBox(height: 24),
                    _buildCustomServerCard(context),
                    const SizedBox(height: 24),
                    _buildServerInfoCard(context),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildServerSelectorCard(BuildContext context) {
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color sectionColor = resolveSettingsSectionBackground(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      addDividers: true,
      dividerIndent: 56,
      children: [
        CupertinoSettingsTile(
          leading: Icon(
            CupertinoIcons.cloud,
            color: resolveSettingsIconColor(context),
          ),
          title: const Text('弹弹play 服务器'),
          subtitle: Text('当前：${_getServerDisplayName(_currentServer)}'),
          backgroundColor: tileColor,
          showChevron: true,
          onTap: _showServerPicker,
        ),
      ],
    );
  }

  Widget _buildCustomServerCard(BuildContext context) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final Color subtitleColor = resolveSettingsSecondaryTextColor(context);
    final Color iconColor = resolveSettingsIconColor(context);

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
                  Icon(CupertinoIcons.pencil_outline,
                      size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    '自定义服务器',
                    style: textTheme.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '输入兼容弹弹play API 的弹幕服务器地址，例如 https://example.com',
                style: textTheme.copyWith(
                  fontSize: 13,
                  color: subtitleColor,
                ),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _customServerController,
                placeholder: 'https://your-danmaku-server.com',
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiarySystemFill,
                    context,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 36,
                  child: CupertinoButton.filled(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    onPressed: _isSavingCustom ? null : _saveCustomServer,
                    child: _isSavingCustom
                        ? const CupertinoActivityIndicator(radius: 8)
                        : const Text('使用该服务器'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServerInfoCard(BuildContext context) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color separatorColor = resolveSettingsSeparatorColor(context);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);
    final serverList = NetworkSettings.getAvailableServers();

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(CupertinoIcons.info, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    '当前服务器信息',
                    style: textTheme.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '服务器：${_getServerDisplayName(_currentServer)}',
                style: textTheme.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'URL：$_currentServer',
                style: textTheme.copyWith(
                  fontSize: 13,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
        ),
        Container(height: 0.5, color: separatorColor),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(CupertinoIcons.book, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    '服务器说明',
                    style: textTheme.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...serverList.map(
                (server) {
                  final name = server['name'] ?? '';
                  final description = server['description'] ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• $name：$description',
                      style: textTheme.copyWith(
                        fontSize: 13,
                        color: secondaryColor,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServerOption {
  const _ServerOption({
    required this.label,
    required this.value,
    required this.description,
  });

  final String label;
  final String value;
  final String description;
}
