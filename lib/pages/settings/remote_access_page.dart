// remote_access_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class RemoteAccessPage extends StatefulWidget {
  const RemoteAccessPage({super.key});

  @override
  State<RemoteAccessPage> createState() => _RemoteAccessPageState();
}

class _RemoteAccessPageState extends State<RemoteAccessPage> {
  // Web Server State
  bool _webServerEnabled = false;
  List<String> _accessUrls = [];
  String? _publicIpUrl;
  bool _isLoadingPublicIp = false;
  int _currentPort = 8080;

  @override
  void initState() {
    super.initState();
    _loadWebServerState();
  }

  Future<void> _loadWebServerState() async {
    final server = ServiceProvider.webServer;
    await server.loadSettings();
    if (mounted) {
      setState(() {
        _webServerEnabled = server.isRunning;
        _currentPort = server.port;
        if (_webServerEnabled) {
          _updateAccessUrls();
        }
      });
    }
  }

  Future<void> _updateAccessUrls() async {
    final urls = await ServiceProvider.webServer.getAccessUrls();
    if (mounted) {
      setState(() {
        _accessUrls = urls;
      });
      // 尝试获取公网IP
      _fetchPublicIp();
    }
  }
  
  Future<void> _fetchPublicIp() async {
    if (!_webServerEnabled) return;
    
    setState(() {
      _isLoadingPublicIp = true;
    });
    
    try {
      // 尝试从多个API获取公网IP
      final response = await http.get(Uri.parse('https://api.ipify.org')).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('获取公网IP超时'),
      );
      
      if (response.statusCode == 200) {
        final ip = response.body.trim();
        // 确保是有效的IP地址
        if (ip.isNotEmpty && !ip.contains('<') && !ip.contains('>')) {
          setState(() {
            _publicIpUrl = 'http://$ip:$_currentPort';
            _isLoadingPublicIp = false;
          });
        } else {
          throw Exception('获取到无效的公网IP');
        }
      } else {
        throw Exception('获取公网IP失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('获取公网IP出错: $e');
      setState(() {
        _publicIpUrl = null;
        _isLoadingPublicIp = false;
      });
    }
  }

  Future<void> _toggleWebServer(bool enabled) async {
    setState(() {
      _webServerEnabled = enabled;
    });

    final server = ServiceProvider.webServer;
    if (enabled) {
      final success = await server.startServer(port: _currentPort);
      if (success) {
        BlurSnackBar.show(context, 'Web服务器已启动');
        _updateAccessUrls();
      } else {
        BlurSnackBar.show(context, 'Web服务器启动失败');
        setState(() {
          _webServerEnabled = false;
        });
      }
    } else {
      await server.stopServer();
      BlurSnackBar.show(context, 'Web服务器已停止');
      setState(() {
        _accessUrls = [];
        _publicIpUrl = null;
      });
    }
    // 保存自动启动设置
    await ServiceProvider.webServer.setAutoStart(enabled);
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    BlurSnackBar.show(context, '访问地址已复制到剪贴板');
  }

  void _showPortDialog() async {
    final portController = TextEditingController(text: _currentPort.toString());
    final newPort = await BlurDialog.show<int>(
      context: context,
      title: '设置Web服务器端口',
      contentWidget: TextField(
        controller: portController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '端口 (1-65535)',
          labelStyle: TextStyle(color: Colors.white70),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white38),
          ),
        ),
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: const Text('确定', style: TextStyle(color: Colors.white)),
          onPressed: () {
            final port = int.tryParse(portController.text);
            if (port != null && port > 0 && port < 65536) {
              Navigator.of(context).pop(port);
            } else {
              BlurSnackBar.show(context, '请输入有效的端口号 (1-65535)');
            }
          },
        ),
      ],
    );

    if (newPort != null && newPort != _currentPort) {
      setState(() {
        _currentPort = newPort;
      });
      await ServiceProvider.webServer.setPort(newPort);
      BlurSnackBar.show(context, 'Web服务器端口已更新，正在重启服务...');
      _updateAccessUrls();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        _buildWebServerSection(),
      ],
    );
  }

  Widget _buildWebServerSection() {
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Ionicons.globe_outline,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Web远程访问',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (_webServerEnabled)
                Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: const Text(
                        '已启用',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              const Text(
                '启用Web服务器功能，可以通过浏览器远程访问和控制应用。此功能正在开发中，部分功能可能不完整。',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 启用/禁用开关
              _buildSettingItem(
                icon: Icons.power_settings_new,
                title: '启用Web服务器',
                subtitle: '允许通过浏览器远程访问应用',
                trailing: Switch(
                  value: _webServerEnabled,
                  onChanged: _toggleWebServer,
                  activeColor: Colors.white,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
              
              if (_webServerEnabled) ...[
                const SizedBox(height: 8),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 8),
                
                // 访问地址
                _buildAccessAddressSection(),
                
                const SizedBox(height: 8),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 8),
                
                // 端口设置
                _buildSettingItem(
                  icon: Icons.settings_ethernet,
                  title: '端口设置',
                  subtitle: '当前端口: $_currentPort',
                  trailing: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: _showPortDialog,
                  ),
                ),
              ],
        ],
      ),
    );
  }
  
  Widget _buildAccessAddressSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.link,
                color: Colors.white70,
                size: 20,
              ),
              SizedBox(width: 16),
              Text(
                '访问地址',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_accessUrls.isEmpty)
            const Text('正在获取地址...', style: TextStyle(color: Colors.white70))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._accessUrls.map((url) => _buildAddressItem(url)),
                if (_isLoadingPublicIp)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '正在获取公网IP...',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Colors.white70
                          )
                        ),
                      ],
                    ),
                  )
                else if (_publicIpUrl != null)
                  _buildAddressItem(_publicIpUrl!, isPublic: true),
              ],
            ),
        ],
      ),
    );
  }
  
  Widget _buildAddressItem(String url, {bool isPublic = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          if (isPublic)
            const Icon(
              Icons.public,
              color: Colors.white38,
              size: 14,
            )
          else
            const Icon(
              Icons.lan,
              color: Colors.white38,
              size: 14,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white70
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyUrl(url),
            //tooltip: '复制地址',
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
} 