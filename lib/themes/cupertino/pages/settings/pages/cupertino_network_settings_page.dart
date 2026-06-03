import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';

import 'package:nipaplay/services/server_connectivity_service.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_modal_popup.dart';

class CupertinoNetworkSettingsPage extends StatefulWidget {
  const CupertinoNetworkSettingsPage({super.key});

  @override
  State<CupertinoNetworkSettingsPage> createState() =>
      _CupertinoNetworkSettingsPageState();
}

class _CupertinoNetworkSettingsPageState
    extends State<CupertinoNetworkSettingsPage> {
  String _currentServer = '';
  String _currentBangumiServer = '';
  bool _isLoading = true;
  bool _isSavingCustom = false;
  bool _isSavingBangumiCustom = false;
  late final TextEditingController _customServerController;
  late final TextEditingController _customBangumiServerController;

  final _connectivity = ServerConnectivityService.instance;

  @override
  void initState() {
    super.initState();
    _customServerController = TextEditingController();
    _customBangumiServerController = TextEditingController();
    _loadCurrentServer();
    _connectivity.dandanplayNotifier.addListener(_onConnectivityChanged);
    _connectivity.bangumiNotifier.addListener(_onConnectivityChanged);
    _connectivity.checkingNotifier.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _connectivity.dandanplayNotifier.removeListener(_onConnectivityChanged);
    _connectivity.bangumiNotifier.removeListener(_onConnectivityChanged);
    _connectivity.checkingNotifier.removeListener(_onConnectivityChanged);
    _customServerController.dispose();
    _customBangumiServerController.dispose();
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCurrentServer() async {
    final server = await NetworkSettings.getDandanplayServer();
    final bangumiServer = await NetworkSettings.getBangumiServer();
    if (!mounted) return;
    setState(() {
      _currentServer = server;
      _currentBangumiServer = bangumiServer;
      _isLoading = false;
      if (NetworkSettings.isCustomServer(server)) {
        _customServerController.text = server;
      } else {
        _customServerController.clear();
      }
      if (NetworkSettings.isCustomBangumiServer(bangumiServer)) {
        _customBangumiServerController.text = bangumiServer;
      } else {
        _customBangumiServerController.clear();
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
      message: context.l10n.networkServerSwitchedTo(
        _getServerDisplayName(context, serverUrl),
      ),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _saveCustomServer() async {
    final input = _customServerController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _isSavingCustom = true;
      });
      try {
        await NetworkSettings.resetToDefaultServer();
        final server = await NetworkSettings.getDandanplayServer();
        if (!mounted) return;
        setState(() {
          _currentServer = server;
        });
        AdaptiveSnackBar.show(
          context,
          message: '已切换到默认服务器',
          type: AdaptiveSnackBarType.success,
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSavingCustom = false;
          });
        }
      }
      return;
    }
    if (!NetworkSettings.isValidServerUrl(input)) {
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.invalidServerAddress,
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
        message: context.l10n.switchedToCustomServer,
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

  Future<void> _saveCustomBangumiServer() async {
    final input = _customBangumiServerController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _isSavingBangumiCustom = true;
      });
      try {
        await NetworkSettings.resetBangumiServer();
        final server = await NetworkSettings.getBangumiServer();
        if (!mounted) return;
        setState(() {
          _currentBangumiServer = server;
        });
        AdaptiveSnackBar.show(
          context,
          message: '已切换到默认服务器',
          type: AdaptiveSnackBarType.success,
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSavingBangumiCustom = false;
          });
        }
      }
      return;
    }
    if (!NetworkSettings.isValidServerUrl(input)) {
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.invalidServerAddress,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    setState(() {
      _isSavingBangumiCustom = true;
    });

    try {
      await NetworkSettings.setBangumiServer(input);
      final server = await NetworkSettings.getBangumiServer();
      if (!mounted) return;
      setState(() {
        _currentBangumiServer = server;
      });
      AdaptiveSnackBar.show(
        context,
        message: 'Bangumi 服务器已切换到自定义服务器',
        type: AdaptiveSnackBarType.success,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBangumiCustom = false;
        });
      }
    }
  }

  Future<void> _showServerPicker() async {
    final List<_ServerOption> options = [
      _ServerOption(
        label: context.l10n.networkPrimaryServerRecommended,
        value: NetworkSettings.primaryServer,
        description: 'api.dandanplay.net',
      ),
      _ServerOption(
        label: context.l10n.networkBackupServer,
        value: NetworkSettings.backupServer,
        description: '139.224.252.88:16001',
      ),
    ];

    if (NetworkSettings.isCustomServer(_currentServer)) {
      options.add(
        _ServerOption(
          label: context.l10n.networkCurrentCustomServer,
          value: _currentServer,
          description: _currentServer,
        ),
      );
    }

    final selected = await showCupertinoModalPopupWithBottomBar<String>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: Text(context.l10n.networkSelectServer),
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
            child: Text(context.l10n.cancel),
          ),
        );
      },
    );

    if (selected != null && selected != _currentServer) {
      await _changeServer(selected);
    }
  }

  String _getServerDisplayName(BuildContext context, String serverUrl) {
    switch (serverUrl) {
      case NetworkSettings.primaryServer:
        return context.l10n.primaryServer;
      case NetworkSettings.backupServer:
        return context.l10n.backupServer;
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
      appBar: AdaptiveAppBar(
        title: context.l10n.networkSettings,
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
                    _buildConnectivityCard(context),
                    const SizedBox(height: 24),
                    _buildBangumiSectionCard(context),
                    const SizedBox(height: 24),
                    _buildDandanplaySectionCard(context),
                    const SizedBox(height: 24),
                    _buildServerInfoCard(context),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildConnectivityCard(BuildContext context) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color secondaryColor = resolveSettingsSecondaryTextColor(context);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final isChecking = _connectivity.isChecking;

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
                  Icon(CupertinoIcons.wifi, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    '网络诊断',
                    style: textTheme.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: isChecking ? null : _connectivity.checkConnectivity,
                    child: isChecking
                        ? const CupertinoActivityIndicator(radius: 10)
                        : Icon(
                            CupertinoIcons.refresh,
                            color: iconColor,
                            size: 20,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildCupertinoStatusRow(
                '弹弹play 服务器',
                _connectivity.dandanplayAvailable,
                textTheme,
                secondaryColor,
              ),
              const SizedBox(height: 10),
              _buildCupertinoStatusRow(
                'Bangumi 服务器',
                _connectivity.bangumiAvailable,
                textTheme,
                secondaryColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCupertinoStatusRow(
    String label,
    bool? available,
    TextStyle textTheme,
    Color secondaryColor,
  ) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (available == null) {
      statusText = '检测中…';
      statusColor = secondaryColor;
      statusIcon = CupertinoIcons.hourglass;
    } else if (available) {
      statusText = '可用';
      statusColor = CupertinoColors.activeGreen;
      statusIcon = CupertinoIcons.checkmark_circle;
    } else {
      statusText = '不可用';
      statusColor = CupertinoColors.systemRed;
      statusIcon = CupertinoIcons.xmark_circle;
    }

    return Row(
      children: [
        Icon(statusIcon, color: statusColor, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: textTheme.copyWith(
            fontSize: 14,
            color: secondaryColor,
          ),
        ),
        const Spacer(),
        Text(
          statusText,
          style: textTheme.copyWith(
            fontSize: 14,
            color: statusColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBangumiSectionCard(BuildContext context) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color separatorColor = resolveSettingsSeparatorColor(context);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final Color subtitleColor = resolveSettingsSecondaryTextColor(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Icon(CupertinoIcons.book, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                'Bangumi',
                style: textTheme.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subtitleColor,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自定义 Bangumi API 服务器',
                style: textTheme.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '输入自定义 Bangumi API 服务器地址，留空使用默认服务器 (${NetworkSettings.bangumiDefaultServer})',
                style: textTheme.copyWith(
                  fontSize: 13,
                  color: subtitleColor,
                ),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _customBangumiServerController,
                placeholder: 'https://example.com',
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
                    onPressed:
                        _isSavingBangumiCustom ? null : _saveCustomBangumiServer,
                    child: _isSavingBangumiCustom
                        ? const CupertinoActivityIndicator(radius: 8)
                        : Text(context.l10n.useThisServer),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDandanplaySectionCard(BuildContext context) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color tileColor = resolveSettingsTileBackground(context);
    final Color iconColor = resolveSettingsIconColor(context);
    final Color separatorColor = resolveSettingsSeparatorColor(context);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final Color subtitleColor = resolveSettingsSecondaryTextColor(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Icon(CupertinoIcons.chat_bubble_text_fill, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                '弹弹play',
                style: textTheme.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subtitleColor,
                ),
              ),
            ],
          ),
        ),
        CupertinoSettingsTile(
          leading: Icon(
            CupertinoIcons.cloud,
            color: iconColor,
          ),
          title: Text(context.l10n.dandanplayServer),
          subtitle: Text(
            context.l10n.currentServer(
              _getServerDisplayName(context, _currentServer),
            ),
          ),
          backgroundColor: tileColor,
          showChevron: true,
          onTap: _showServerPicker,
        ),
        Container(height: 0.5, color: separatorColor),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自定义弹弹play API 服务器',
                style: textTheme.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.customServerInputHint,
                style: textTheme.copyWith(
                  fontSize: 13,
                  color: subtitleColor,
                ),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _customServerController,
                placeholder: context.l10n.customServerPlaceholder,
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
                        : Text(context.l10n.useThisServer),
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
    final serverList = [
      (
        name: context.l10n.primaryServer,
        description: context.l10n.networkServerDescriptionPrimary,
      ),
      (
        name: context.l10n.backupServer,
        description: context.l10n.networkServerDescriptionBackup,
      ),
    ];

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
                    context.l10n.currentServerInfo,
                    style: textTheme.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Bangumi',
                style: textTheme.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _currentBangumiServer,
                style: textTheme.copyWith(
                  fontSize: 13,
                  color: secondaryColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '弹弹play',
                style: textTheme.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.l10n.serverField(
                  _getServerDisplayName(context, _currentServer),
                ),
                style: textTheme.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                _currentServer,
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
                    context.l10n.serverDescriptionTitle,
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
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      context.l10n.serverBullet(
                        server.name,
                        server.description,
                      ),
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
