import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';

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
      message: context.l10n.networkServerSwitchedTo(
        _getServerDisplayName(context, serverUrl),
      ),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _saveCustomServer() async {
    final input = _customServerController.text.trim();
    if (input.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.enterServerAddress,
        type: AdaptiveSnackBarType.warning,
      );
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
                    context.l10n.customServer,
                    style: textTheme.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                context.l10n.serverField(
                  _getServerDisplayName(context, _currentServer),
                ),
                style: textTheme.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.urlField(_currentServer),
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
