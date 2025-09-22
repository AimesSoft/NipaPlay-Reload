import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_item.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  String _currentServer = '';
  bool _isLoading = true;
  final GlobalKey _serverDropdownKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadCurrentServer();
  }

  Future<void> _loadCurrentServer() async {
    final server = await NetworkSettings.getDandanplayServer();
    setState(() {
      _currentServer = server;
      _isLoading = false;
    });
  }

  Future<void> _changeServer(String serverUrl) async {
    await NetworkSettings.setDandanplayServer(serverUrl);
    setState(() {
      _currentServer = serverUrl;
    });
    
    if (mounted) {
      BlurSnackBar.show(context, '弹弹play服务器已切换到: ${_getServerDisplayName(serverUrl)}');
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

  List<DropdownMenuItemData> _getServerDropdownItems() {
    return [
      DropdownMenuItemData(
        title: '主服务器 (推荐)',
        value: NetworkSettings.primaryServer,
        isSelected: _currentServer == NetworkSettings.primaryServer,
      ),
      DropdownMenuItemData(
        title: '备用服务器',
        value: NetworkSettings.backupServer,
        isSelected: _currentServer == NetworkSettings.backupServer,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          SettingsItem.dropdown(
            title: "弹弹play服务器",
            subtitle: "选择弹弹play弹幕服务器。备用服务器可在主服务器无法访问时使用。",
            icon: Ionicons.server_outline,
            items: _getServerDropdownItems(),
            onChanged: (serverUrl) => _changeServer(serverUrl),
            dropdownKey: _serverDropdownKey,
          ),
          const Divider(color: Colors.white12, height: 1),
          // 显示当前服务器信息
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Ionicons.information_circle_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '当前服务器信息',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '服务器: ${_getServerDisplayName(_currentServer)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'URL: $_currentServer',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 服务器说明
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Ionicons.help_circle_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '服务器说明',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• 主服务器：api.dandanplay.net（官方服务器，推荐使用）',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• 备用服务器：139.217.235.62:16001（镜像服务器，主服务器无法访问时使用）',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}