import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
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
          context, '弹弹play服务器已切换到: ${_getServerDisplayName(serverUrl)}');
    }
  }

  Future<void> _saveCustomServer() async {
    final input = _customServerController.text.trim();
    if (input.isEmpty) {
      BlurSnackBar.show(context, '请输入服务器地址');
      return;
    }

    if (!NetworkSettings.isValidServerUrl(input)) {
      BlurSnackBar.show(context, '服务器地址格式不正确，请以 http/https 开头');
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

    BlurSnackBar.show(context, '已切换到自定义服务器');
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
    final items = [
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

    if (NetworkSettings.isCustomServer(_currentServer)) {
      items.add(
        DropdownMenuItemData(
          title: '自定义：$_currentServer',
          value: _currentServer,
          isSelected: true,
        ),
      );
    }

    return items;
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
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Ionicons.create_outline,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '自定义服务器',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '输入兼容弹弹play接口规范的弹幕服务器地址，例如 https://example.com',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customServerController,
                    decoration: const InputDecoration(
                      hintText: 'https://your-danmaku-server.com',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: BlurButton(
                      icon: _isSavingCustom ? null : Ionicons.checkmark_outline,
                      text: _isSavingCustom ? '保存中...' : '使用该服务器',
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
