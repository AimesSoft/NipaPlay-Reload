import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/services/server_connectivity_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

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

  final _connectivity = ServerConnectivityService.instance;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (mounted) setState(() {});
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

  Widget _buildStatusRow(String label, bool? available, ColorScheme colorScheme) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (available == null) {
      statusText = '检测中…';
      statusColor = colorScheme.onSurface.withOpacity(0.5);
      statusIcon = Ionicons.hourglass_outline;
    } else if (available) {
      statusText = '可用';
      statusColor = Colors.green;
      statusIcon = Ionicons.checkmark_circle_outline;
    } else {
      statusText = '不可用';
      statusColor = Colors.red;
      statusIcon = Ionicons.close_circle_outline;
    }

    return Row(
      children: [
        Icon(statusIcon, color: statusColor, size: 16),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.8),
            fontSize: 13,
          ),
        ),
        Spacer(),
        Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
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
    final isChecking = _connectivity.isChecking;
    final dandanplayAvailable = _connectivity.dandanplayAvailable;
    final bangumiAvailable = _connectivity.bangumiAvailable;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Ionicons.wifi_outline,
                      color: colorScheme.onSurface,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '网络诊断',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Spacer(),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        onPressed: isChecking ? null : _connectivity.checkConnectivity,
                        icon: isChecking
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppAccentColors.current,
                                ),
                              )
                            : Icon(
                                Ionicons.refresh_outline,
                                color: colorScheme.onSurface,
                                size: 18,
                              ),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _buildStatusRow(
                  '弹弹play 服务器',
                  dandanplayAvailable,
                  colorScheme,
                ),
                SizedBox(height: 8),
                _buildStatusRow(
                  'Bangumi 服务器',
                  bangumiAvailable,
                  colorScheme,
                ),
              ],
            ),
          ),
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
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
                    SizedBox(width: 8),
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
                SizedBox(height: 8),
                Text(
                  l10n.customServerInputHint,
                  style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 12),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: _customServerController,
                  cursorColor: AppAccentColors.current,
                  decoration: InputDecoration(
                    hintText: l10n.customServerPlaceholder,
                    hintStyle: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.38)),
                    filled: true,
                    fillColor: colorScheme.onSurface.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppAccentColors.current, width: 2),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                SizedBox(height: 8),
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
                    foregroundColor: colorScheme.onSurface,
                    hoverForegroundColor: AppAccentColors.current,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
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
                    SizedBox(width: 8),
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
                SizedBox(height: 8),
                Text(
                  l10n.serverField(
                      _getServerDisplayName(context, _currentServer)),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
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
                    SizedBox(width: 8),
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
                SizedBox(height: 8),
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
                SizedBox(height: 4),
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
