import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  String _currentServer = '';
  bool _isLoading = true;
  final GlobalKey _serverDropdownKey = GlobalKey();
  final TextEditingController _customServerController = TextEditingController();
  bool _isSavingCustom = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentServer();
  }

  @override
  void dispose() {
    _customServerController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentServer() async {
    final server = await NetworkSettings.getDandanplayServer();
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
    setState(() {
      _currentServer = serverUrl;
      if (NetworkSettings.isCustomServer(serverUrl)) {
        _customServerController.text = serverUrl;
      } else {
        _customServerController.clear();
      }
    });

    if (mounted) {
      BlurSnackBar.show(
        context,
        context.l10n.networkServerSwitchedTo(
          _getServerDisplayName(context, serverUrl),
        ),
      );
    }
  }

  Future<void> _saveCustomServer() async {
    final input = _customServerController.text.trim();
    if (input.isEmpty) {
      BlurSnackBar.show(context, context.l10n.enterServerAddress);
      return;
    }

    if (!NetworkSettings.isValidServerUrl(input)) {
      BlurSnackBar.show(context, context.l10n.invalidServerAddress);
      return;
    }

    setState(() {
      _isSavingCustom = true;
    });

    await NetworkSettings.setDandanplayServer(input);
    final server = await NetworkSettings.getDandanplayServer();
    if (!mounted) return;

    setState(() {
      _currentServer = server;
      _isSavingCustom = false;
    });

    BlurSnackBar.show(context, context.l10n.switchedToCustomServer);
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

  List<DropdownMenuItemData> _getServerDropdownItems(BuildContext context) {
    final items = [
      DropdownMenuItemData(
        title: context.l10n.networkPrimaryServerRecommended,
        value: NetworkSettings.primaryServer,
        isSelected: _currentServer == NetworkSettings.primaryServer,
      ),
      DropdownMenuItemData(
        title: context.l10n.networkBackupServer,
        value: NetworkSettings.backupServer,
        isSelected: _currentServer == NetworkSettings.backupServer,
      ),
    ];

    if (NetworkSettings.isCustomServer(_currentServer)) {
      items.add(
        DropdownMenuItemData(
          title: context.l10n.customServerWithValue(_currentServer),
          value: _currentServer,
          isSelected: true,
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          SettingsItem.dropdown(
            title: l10n.dandanplayServer,
            subtitle: l10n.networkServerSelectSubtitle,
            icon: Ionicons.server_outline,
            items: _getServerDropdownItems(context),
            onChanged: (serverUrl) => _changeServer(serverUrl),
            dropdownKey: _serverDropdownKey,
          ),
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Ionicons.create_outline,
                        color: colorScheme.onSurface, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      l10n.customServer,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.customServerInputHint,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7), fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customServerController,
                  cursorColor: const Color(0xFFff2e55),
                  decoration: InputDecoration(
                    hintText: l10n.customServerPlaceholder,
                    hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                    filled: true,
                    fillColor: colorScheme.onSurface.withOpacity(0.1),
                    border: const OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFff2e55), width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: BlurButton(
                    icon: _isSavingCustom ? null : Ionicons.checkmark_outline,
                    text: _isSavingCustom ? l10n.saving : l10n.useThisServer,
                    onTap: _isSavingCustom ? () {} : _saveCustomServer,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    fontSize: 13,
                    iconSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
          // 显示当前服务器信息
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Ionicons.information_circle_outline,
                      color: colorScheme.onSurface,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.currentServerInfo,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.serverField(_getServerDisplayName(context, _currentServer)),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.urlField(_currentServer),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // 服务器说明
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Ionicons.help_circle_outline,
                      color: colorScheme.onSurface,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.serverDescriptionTitle,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.serverBullet(
                    l10n.primaryServer,
                    l10n.networkServerDescriptionPrimary,
                  ),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.serverBullet(
                    l10n.backupServer,
                    l10n.networkServerDescriptionBackup,
                  ),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
